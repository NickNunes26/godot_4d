@tool
class_name GroundTextures
extends RefCounted

## The tiled textures the ground shader blends in near the camera: leaf litter
## on flat ground and rock on slopes. Downloaded once from Poly Haven (CC0 --
## no attribution required, though it is appreciated) through its public API,
## converted to compressed textures, and shared by every terrain in the project.
##
## The terrain works without them (orthophoto only); they are what keeps the
## ground from turning into a blur of 25 cm pixels close up.

const DEFAULT_DIR := "res://terrain/_ground_textures"
const API := "https://api.polyhaven.com/files/%s"
const RESOLUTION := "2k"
## shader prefix -> Poly Haven asset id
const SETS := {"leaves": "forest_leaves_02", "rock": "dry_riverbed_rock"}
## shader suffix -> Poly Haven map name
const MAPS := {"albedo": "Diffuse", "roughness": "Rough", "normal": "nor_gl"}
const CREDIT := "Texturas de suelo: Poly Haven (CC0) — forest_leaves_02, dry_riverbed_rock"

static func texture_path(dir: String, prefix: String, suffix: String) -> String:
	return dir.path_join("%s_%s.res" % [prefix, suffix])

## Whether every texture is already in `dir`.
static func present(dir: String = DEFAULT_DIR) -> bool:
	for prefix in SETS:
		for suffix in MAPS:
			if not ResourceLoader.exists(texture_path(dir, prefix, suffix)):
				return false
	return true

## {"leaves_albedo": Texture2D, ...} (the shader's uniform names), or {} if any
## is missing.
static func load_all(dir: String = DEFAULT_DIR) -> Dictionary:
	if not present(dir):
		return {}
	var out := {}
	for prefix in SETS:
		for suffix in MAPS:
			var tex := load(texture_path(dir, prefix, suffix)) as Texture2D
			if tex == null:
				return {}
			out["%s_%s" % [prefix, suffix]] = tex
	return out

## Downloads whatever is missing, using `service` for the requests. Returns ""
## on success, else the error.
static func ensure(service: TerrainService, dir: String = DEFAULT_DIR) -> String:
	if present(dir):
		return ""
	var raw := dir.path_join("raw")
	TerrainService._ensure_raw_dir(raw)
	for prefix in SETS:
		var asset: String = SETS[prefix]
		var listing := raw.path_join(asset + ".json")
		if not FileAccess.file_exists(listing):
			service.progress.emit("Texturas de suelo: consultando %s en Poly Haven..." % asset)
			var err := await service.fetch(API % asset, listing, 60.0, func(p): return "" if JSON.parse_string(FileAccess.get_file_as_string(p)) is Dictionary else "invalid JSON")
			if err != "":
				return "Poly Haven no responde (%s)" % err
		var files = JSON.parse_string(FileAccess.get_file_as_string(listing))
		if not (files is Dictionary):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(listing))
			return "respuesta inesperada de Poly Haven para %s" % asset
		for suffix in MAPS:
			var out_path := texture_path(dir, prefix, suffix)
			if ResourceLoader.exists(out_path):
				continue
			var url := _map_url(files, MAPS[suffix])
			if url == "":
				return "%s no tiene el mapa %s" % [asset, MAPS[suffix]]
			var jpg := raw.path_join(url.get_file())
			if not FileAccess.file_exists(jpg):
				service.progress.emit("Texturas de suelo: descargando %s..." % url.get_file())
				var err := await service.fetch(url, jpg, 120.0, TerrainProvider.image_complete)
				if err != "":
					return "no se pudo descargar %s (%s)" % [url.get_file(), err]
			var img := Image.load_from_file(jpg)
			if img == null:
				return "%s no es una imagen" % jpg.get_file()
			img.generate_mipmaps()
			var tex := PortableCompressedTexture2D.new()
			tex.keep_compressed_buffer = true
			tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_S3TC, suffix == "normal")
			var save_err := ResourceSaver.save(tex, out_path, ResourceSaver.FLAG_COMPRESS)
			if save_err != OK:
				return "no se pudo guardar %s (error %d)" % [out_path, save_err]
	return ""

static func _map_url(files: Dictionary, map_name: String) -> String:
	var by_res = files.get(map_name, {})
	if not (by_res is Dictionary):
		return ""
	for res in [RESOLUTION, "1k", "4k"]:
		var entry = by_res.get(res, {})
		if entry is Dictionary and entry.get("jpg") is Dictionary:
			return String(entry.jpg.get("url", ""))
	return ""
