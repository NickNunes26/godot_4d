@tool
class_name TerrainService
extends Node

## Downloads a site and turns it into a saved TerrainData. Must be inside the
## scene tree (it uses HTTPRequest and timers); works in the editor and at
## runtime. Everything is async (`await`) and heavy parsing runs on a worker
## thread, so the editor never blocks.
##
## Files for a site live in `<cache_root>/<spec key>/`: the raw downloads in
## `raw/` (with a .gdignore so the editor does not import 4000 px JPEGs) and
## the finished `terrain.res`. Anything already downloaded is reused.

signal progress(text: String)

const USER_AGENT := "Construction4DTool/0.5 (Godot Engine addon)"
## Waits before retries 2, 3 and 4. The Spanish services fail intermittently
## (502s, timeouts); a single failed request must not sink a whole build.
const RETRY_WAITS := [3.0, 12.0, 27.0]

var cancelled := false

## Available providers, most specific first; the first one covering a point wins.
static func providers() -> Array:
	return [SpainIgnProvider.new(), TerrariumProvider.new()]

static func provider_for(lat: float, lon: float) -> TerrainProvider:
	for p in providers():
		if p.covers(lat, lon):
			return p
	return null

static func provider_by_id(pid: String) -> TerrainProvider:
	for p in providers():
		if p.id() == pid:
			return p
	return null

## Downloads `url` to `dest` (through a ".parcial" file, so an interrupted
## download never leaves a broken file behind), retrying on failure.
## `validate(path) -> String` checks the content is complete and is what was
## asked for ("" = fine). Returns "" on success, else the last error.
##
## With a validator, a connection that drops right at the end still counts
## when the bytes that did arrive are complete: the Spanish WCS routinely
## closes its TLS connection without finishing the chunked stream (curl shrugs
## it off; Godot's HTTPRequest reports a connection error and, when writing to
## a file, loses the last chunk). That is why this uses HTTPClient directly.
func fetch(url: String, dest: String, timeout: float, validate: Callable = Callable()) -> String:
	var err := ""
	for attempt in RETRY_WAITS.size() + 1:
		if cancelled:
			return "cancelado"
		var partial := ProjectSettings.globalize_path(dest + ".parcial")
		var res: Dictionary = await run_threaded(func(): return download_blocking(url, partial, timeout, self))
		err = res.error
		if res.code != 0 and res.code != 200:
			err = "HTTP %d %s" % [res.code, FileAccess.get_file_as_string(partial).substr(0, 300).strip_edges()]
		elif validate.is_valid() and FileAccess.file_exists(partial):
			var bad: String = validate.call(partial)
			if bad == "":
				err = "" # complete, even if the connection closed badly
			elif err == "":
				err = bad
		if err == "":
			var abs_dest := ProjectSettings.globalize_path(dest)
			if FileAccess.file_exists(abs_dest):
				DirAccess.remove_absolute(abs_dest)
			var mv := DirAccess.rename_absolute(partial, abs_dest)
			return "" if mv == OK else "no se pudo guardar %s (error %d)" % [dest.get_file(), mv]
		DirAccess.remove_absolute(partial)
		if attempt < RETRY_WAITS.size() and not cancelled:
			var wait: float = RETRY_WAITS[attempt]
			progress.emit("El servicio no ha respondido bien (%s). Reintento %d de %d en %d s..." % [err, attempt + 2, RETRY_WAITS.size() + 1, int(wait)])
			await get_tree().create_timer(wait).timeout
	return err

## Blocking GET of `url` into the absolute path `out_path`, following up to 5
## redirects. Meant for a worker thread. Returns {"error": String ("" = the
## body ended cleanly), "code": int HTTP status (0 = none)}. Whatever arrived is
## left in `out_path` either way, for the caller to judge.
static func download_blocking(url: String, out_path: String, timeout: float, owner: Object = null) -> Dictionary:
	var current := url
	var re := RegEx.new()
	re.compile("^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$")
	for _redirect in 5:
		var m := re.search(current)
		if not m:
			return {"error": "URL no válida: %s" % current, "code": 0}
		var tls := m.get_string(1) == "https"
		var host := m.get_string(2)
		var port := m.get_string(3).to_int() if m.get_string(3) != "" else (443 if tls else 80)
		var path := m.get_string(4) if m.get_string(4) != "" else "/"
		var client := HTTPClient.new()
		var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
		if client.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
			return {"error": "no se pudo conectar con %s" % host, "code": 0}
		while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
			client.poll()
			if Time.get_ticks_msec() > deadline:
				return {"error": "tiempo de espera agotado al conectar", "code": 0}
			OS.delay_msec(5)
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			return {"error": "no se pudo conectar con %s (estado %d)" % [host, client.get_status()], "code": 0}
		client.request(HTTPClient.METHOD_GET, path, PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: */*"]))
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			if Time.get_ticks_msec() > deadline:
				return {"error": "tiempo de espera agotado", "code": 0}
			OS.delay_msec(5)
		if not client.has_response():
			return {"error": "sin respuesta (estado %d)" % client.get_status(), "code": 0}
		var code := client.get_response_code()
		if code in [301, 302, 303, 307, 308]:
			var location := ""
			for h in client.get_response_headers():
				if h.to_lower().begins_with("location:"):
					location = h.substr(9).strip_edges()
			client.close()
			if location == "":
				return {"error": "redirección sin destino", "code": code}
			current = location if location.begins_with("http") else "%s://%s%s" % [m.get_string(1), host, location]
			continue
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if not f:
			client.close()
			return {"error": "no se puede escribir %s" % out_path, "code": code}
		var error := ""
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk := client.read_response_body_chunk()
			if chunk.is_empty():
				OS.delay_msec(2)
			else:
				f.store_buffer(chunk)
			if Time.get_ticks_msec() > deadline:
				error = "tiempo de espera agotado"
				break
			if owner and owner.get("cancelled"):
				error = "cancelado"
				break
		f.close()
		var st := client.get_status()
		if error == "" and st != HTTPClient.STATUS_CONNECTED and st != HTTPClient.STATUS_DISCONNECTED:
			error = "conexión interrumpida (estado %d)" % st
		client.close()
		return {"error": error, "code": code}
	return {"error": "demasiadas redirecciones", "code": 0}

## Runs `fn` (no arguments, returns a value) on a worker thread and awaits it
## without blocking the main loop.
func run_threaded(fn: Callable) -> Variant:
	var box := [null]
	var task := WorkerThreadPool.add_task(func(): box[0] = fn.call(), false, "Construction 4D terrain")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return box[0]

## Tells the UTM zone of (e, n) by asking the provider for the ground height
## in each candidate zone and keeping the one matching the model's height.
## Returns pick_zone()'s result plus "detail" text.
func detect_zone(provider: TerrainProvider, e: float, n: float, model_height: float, cache_dir: String) -> Dictionary:
	var cands: Array = []
	_ensure_raw_dir(cache_dir)
	for z in provider.candidate_zones():
		var g := Utm.to_geo(e, n, z)
		if not provider.covers(g.lat, g.lon):
			continue
		var job: Dictionary = provider.probe_download(g.lat, g.lon)
		if job.is_empty():
			continue
		progress.emit("Huso %d: consultando la cota del terreno en %.4f, %.4f..." % [z, g.lat, g.lon])
		var path := cache_dir.path_join(job.file)
		if not FileAccess.file_exists(path) and await fetch(job.url, path, job.timeout, provider.validate_elevation) != "":
			continue
		var h := provider.probe_height(path)
		if is_nan(h):
			continue # sea or no coverage
		cands.append({"zone": z, "ground": h, "diff": absf(h - model_height)})
	return pick_zone(cands, model_height)

## The zone decision, kept pure for testing. `cands`: [{zone, ground, diff}].
## Accepted only with a wide margin -- best within 120 m of the model and the
## runner-up at least max(300 m, 3x best) off -- because a wrong zone puts the
## model hundreds of kilometres away. Returns {"zone" (0 = undecided), "detail"}.
static func pick_zone(cands: Array, model_height: float) -> Dictionary:
	var sorted := cands.duplicate()
	sorted.sort_custom(func(a, b): return a.diff < b.diff)
	if sorted.is_empty():
		return {"zone": 0, "detail": "Con ningún huso candidato el punto cae en tierra con datos: indica el huso a mano."}
	var best: Dictionary = sorted[0]
	var lines := PackedStringArray()
	for c in sorted:
		lines.append("huso %d: terreno %.0f m (%.0f m de diferencia)" % [c.zone, c.ground, c.diff])
	if sorted.size() == 1 or (best.diff <= 120.0 and sorted[1].diff >= maxf(300.0, 3.0 * best.diff)):
		return {"zone": best.zone, "detail": "Huso %d deducido: el modelo está a %.0f m y el terreno a %.0f m (%s)." % [best.zone, model_height, best.ground, "; ".join(lines)]}
	return {"zone": 0, "detail": "No se puede deducir el huso con seguridad (modelo a %.0f m; %s). Indícalo a mano." % [model_height, "; ".join(lines)]}

## Downloads (or reuses) everything for `spec` and saves the TerrainData.
## Returns {"data": TerrainData or null, "path": String, "error": String}.
func build(spec: TerrainSpec, provider: TerrainProvider, cache_root: String, with_imagery := true) -> Dictionary:
	cancelled = false
	var dir := cache_root.path_join(spec.key())
	var raw := dir.path_join("raw")
	_ensure_raw_dir(raw)

	var jobs: Array = provider.elevation_downloads(spec)
	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var path := raw.path_join(job.file)
		if FileAccess.file_exists(path):
			continue
		progress.emit("Elevación (%s): descargando %d de %d..." % [provider.display_name(), i + 1, jobs.size()])
		var err := await fetch(job.url, path, job.timeout, provider.validate_elevation)
		if err != "":
			return _fail("No se pudo descargar la elevación tras %d intentos (%s). ¿Hay conexión? Si el servicio está caído, prueba más tarde o usa archivos propios." % [RETRY_WAITS.size() + 1, err])

	progress.emit("Elevación: remuestreando %d x %d puntos..." % [spec.grid_n(), spec.grid_n()])
	var built: Dictionary = await run_threaded(func(): return _with_data(provider.build_heights(spec, raw), spec))
	if built.get("error", "") != "":
		return _fail(built.error)
	var data: TerrainData = built.data
	data.provider_id = provider.id()
	data.attribution = provider.attribution()

	if with_imagery and provider.has_imagery():
		for which in ["context", "detail"]:
			var half: float = spec.context_half if which == "context" else spec.detail_half
			var job: Dictionary = provider.ortho_download(spec, half, "ortho_%s_%d_%d" % [which, int(half), spec.ortho_px])
			if job.is_empty():
				continue
			var path := raw.path_join(job.file)
			if not FileAccess.file_exists(path):
				progress.emit("Ortofoto de %s (%.0f x %.0f m, %d px): descargando..." % ["contexto" if which == "context" else "detalle", half * 2.0, half * 2.0, spec.ortho_px])
				var err := await fetch(job.url, path, job.timeout, provider.validate_ortho)
				if err != "":
					return _fail("No se pudo descargar la ortofoto (%s)." % err)
				TerrainBuilder.write_world_file(path, job.rect, spec.ortho_px)
			progress.emit("Ortofoto de %s: comprimiendo textura..." % ("contexto" if which == "context" else "detalle"))
			var img: Image = await run_threaded(func(): return TerrainBuilder.ortho_image(path))
			var tex := TerrainBuilder.compressed_texture(img)
			if tex == null:
				return _fail("La ortofoto %s no se puede leer." % path.get_file())
			if which == "context":
				data.context_texture = tex
				data.context_rect = job.rect
			else:
				data.detail_texture = tex
				data.detail_rect = job.rect
	return _save(data, dir)

## Same result from the user's own files: an .asc (UTM in the spec's zone or
## geographic degrees) and optional orthophotos (JPG/PNG with a world file;
## GeoTIFF is not readable by Godot).
func build_from_files(spec: TerrainSpec, asc_path: String, ortho_paths: Array, cache_root: String) -> Dictionary:
	var dir := cache_root.path_join(spec.key() + "_files")
	_ensure_raw_dir(dir.path_join("raw"))
	progress.emit("Leyendo %s..." % asc_path.get_file())
	var built: Dictionary = await run_threaded(func(): return _with_data(TerrainBuilder.heights_from_asc_file(asc_path, spec), spec))
	if built.get("error", "") != "":
		return _fail(built.error)
	var data: TerrainData = built.data
	data.provider_id = "files"
	data.attribution = "Datos propios: %s" % asc_path.get_file()
	# Largest image becomes the context layer, the next the detail layer.
	var layers: Array = []
	for p in ortho_paths:
		var img := Image.load_from_file(p)
		if img == null:
			return _fail("No se puede leer la imagen %s (usa JPG o PNG)." % String(p).get_file())
		var rect := TerrainBuilder.world_file_rect(p, img.get_width(), img.get_height())
		if rect.is_empty():
			return _fail("%s no tiene world file (.jgw/.pgw/.wld) al lado: sin él no se sabe dónde va." % String(p).get_file())
		layers.append({"path": p, "rect": rect, "area": (rect[2] - rect[0]) * (rect[3] - rect[1])})
	layers.sort_custom(func(a, b): return a.area > b.area)
	for i in mini(layers.size(), 2):
		var tex := TerrainBuilder.ortho_texture(layers[i].path)
		if i == 0:
			data.context_texture = tex
			data.context_rect = layers[i].rect
		else:
			data.detail_texture = tex
			data.detail_rect = layers[i].rect
	return _save(data, dir)

## Worker-thread tail of a heights build: wraps them in a TerrainData
## (including the collision grid, the other heavy loop).
static func _with_data(built: Dictionary, spec: TerrainSpec) -> Dictionary:
	if built.get("error", "") == "":
		built["data"] = TerrainBuilder.make_data(spec, built.heights)
	return built

func _save(data: TerrainData, dir: String) -> Dictionary:
	var path := dir.path_join("terrain.res")
	progress.emit("Guardando %s..." % path)
	# take_over_path: a rebuild of the same site replaces the copy already
	# loaded in the editor instead of clashing with it over the path.
	data.take_over_path(path)
	var err := ResourceSaver.save(data, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		return _fail("No se pudo guardar %s (error %d)." % [path, err])
	return {"data": data, "path": path, "error": ""}

func _fail(msg: String) -> Dictionary:
	progress.emit("ERROR: " + msg)
	return {"data": null, "path": "", "error": msg}

## Raw downloads are data for this tool, not assets for the editor to import.
static func _ensure_raw_dir(raw: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(raw))
	var marker := raw.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		var f := FileAccess.open(marker, FileAccess.WRITE)
		if f:
			f.store_string("")
