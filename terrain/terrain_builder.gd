@tool
class_name TerrainBuilder
extends RefCounted

## Stateless helpers between raw downloads and a TerrainData: resampling onto
## the regular UTM grid, orthophoto textures, local-file input, and the
## "does the model sit on this ground?" check. No networking, no scene tree
## (except model_samples(), which only reads transforms).

## Samples a grid in geographic degrees (x = longitude, y = latitude) at every
## point of `spec`'s UTM grid.
static func sample_geographic(grid: AscGrid, spec: TerrainSpec) -> PackedFloat32Array:
	var geo := spec.geo_grid()
	var lat: PackedFloat64Array = geo.lat
	var lon: PackedFloat64Array = geo.lon
	var out := PackedFloat32Array()
	out.resize(lat.size())
	for i in lat.size():
		out[i] = grid.sample(lon[i], lat[i])
	return out

## Samples a grid already in the spec's UTM metres.
static func sample_projected(grid: AscGrid, spec: TerrainSpec) -> PackedFloat32Array:
	var n := spec.grid_n()
	var out := PackedFloat32Array()
	out.resize(n * n)
	for r in n:
		var y := spec.grid_north(r)
		for c in n:
			out[r * n + c] = grid.sample(spec.grid_e(c), y)
	return out

## Heights from a user's own .asc: projected in the spec's zone (metres), or
## geographic degrees -- told apart by the magnitude of its corner.
static func heights_from_asc_file(path: String, spec: TerrainSpec) -> Dictionary:
	var err := {}
	var grid := AscGrid.parse(FileAccess.get_file_as_string(path), err)
	if grid == null:
		return {"error": "%s is not an ASC grid (%s)" % [path.get_file(), err.get("message", "")]}
	if grid.fill_nodata() == 0:
		return {"error": "%s has no valid heights" % path.get_file()}
	var projected := absf(grid.xll) > 1000.0 or absf(grid.yll) > 1000.0
	if projected and not grid.contains(spec.center_e, spec.center_n):
		return {"error": "%s does not cover the model (is it in UTM zone %d?)" % [path.get_file(), spec.zone]}
	var c := spec.center_geo()
	if not projected and not grid.contains(c.lon, c.lat):
		return {"error": "%s does not cover the model" % path.get_file()}
	return {"heights": sample_projected(grid, spec) if projected else sample_geographic(grid, spec), "error": ""}

## A TerrainData from finished heights.
static func make_data(spec: TerrainSpec, heights: PackedFloat32Array) -> TerrainData:
	var d := TerrainData.new()
	d.zone = spec.zone
	d.south = spec.south
	d.center_e = spec.center_e
	d.center_n = spec.center_n
	d.cell = spec.cell
	d.grid_n = spec.grid_n()
	d.heights = heights
	var lo := INF
	var hi := -INF
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	d.min_height = lo
	d.max_height = hi
	add_collision(d)
	return d

## Fills data.collision_map: the heights resampled to the smallest 2^k + 1 grid
## at least as fine as the visual one (capped at 1025).
static func add_collision(d: TerrainData) -> void:
	var m := 3
	while m < mini(d.grid_n, 1025):
		m = (m - 1) * 2 + 1
	var size := (d.grid_n - 1) * d.cell
	var spacing := size / (m - 1)
	var west := d.center_e - size / 2.0
	var north := d.center_n + size / 2.0
	var out := PackedFloat32Array()
	out.resize(m * m)
	for r in m:
		for c in m:
			out[r * m + c] = d.height_at(west + c * spacing, north - r * spacing) / spacing
	d.collision_n = m
	d.collision_map = out

## An orthophoto file -> RGB8 image with mipmaps (thread-safe), or null.
static func ortho_image(path: String) -> Image:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	return img

## A mipmapped image -> a VRAM-compressed texture that saves inside the terrain
## resource. Main thread only (it creates a GPU texture).
static func compressed_texture(img: Image) -> Texture2D:
	if img == null:
		return null
	var tex := PortableCompressedTexture2D.new()
	# Without this the pixels live only on the GPU and the saved resource is empty.
	tex.keep_compressed_buffer = true
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_S3TC)
	return tex

## ortho_image() + compressed_texture(), on the calling thread.
static func ortho_texture(path: String) -> Texture2D:
	return compressed_texture(ortho_image(path))

## Map rectangle [e0, n0, e1, n1] of an image from its world file (.jgw, .pgw,
## .wld, ...), or an empty array when there is none. World files give the
## centre of the top-left pixel and the pixel size.
static func world_file_rect(image_path: String, width: int, height: int) -> PackedFloat64Array:
	var base := image_path.get_basename()
	for ext in [".jgw", ".jpgw", ".pgw", ".pngw", ".wld", ".tfw"]:
		if not FileAccess.file_exists(base + ext):
			continue
		var nums := PackedFloat64Array()
		for tok in FileAccess.get_file_as_string(base + ext).replace(",", ".").split("\n", false):
			if not tok.strip_edges().is_empty():
				nums.append(tok.strip_edges().to_float())
		if nums.size() < 6:
			continue
		var px := nums[0]
		var py := nums[3] # negative: rows go south
		var x0 := nums[4] - px / 2.0
		var y1 := nums[5] - py / 2.0
		return PackedFloat64Array([x0, y1 + py * height, x0 + px * width, y1])
	return PackedFloat64Array()

## Writes a world file for a downloaded square image, so the raw cache is
## usable in any GIS tool too.
static func write_world_file(image_path: String, rect: PackedFloat64Array, px: int) -> void:
	var t := (rect[2] - rect[0]) / px
	var f := FileAccess.open(image_path.get_basename() + ".jgw", FileAccess.WRITE)
	if f:
		f.store_string("%.6f\n0\n0\n%.6f\n%.4f\n%.4f\n" % [t, -t, rect[0] + t / 2.0, rect[3] - t / 2.0])

## Every part's footprint centre and vertical extent on the map:
## [{"e", "n", "bottom", "top"}]. Reads the parts container's direct children.
## `to_anchor` takes the container's space into the space `geo` describes (for
## a second model's container: anchor.transform.affine_inverse() * its transform).
static func model_samples(container: Node3D, geo: GeoOrigin, to_anchor := Transform3D()) -> Array:
	var out: Array = []
	if not container:
		return out
	for child in container.get_children():
		if not (child is Node3D):
			continue
		var box := to_anchor * _local_aabb(child as Node3D, container)
		if box.size == Vector3.ZERO:
			continue
		var c := box.get_center()
		var p := geo.local_to_map(Vector3(c.x, box.position.y, c.z))
		var top := geo.local_to_map(Vector3(c.x, box.end.y, c.z))
		out.append({"e": p[0], "n": p[1], "bottom": p[2], "top": top[2]})
	return out

static func _local_aabb(node: Node3D, container: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var meshes: Array = [node] if node is MeshInstance3D else []
	meshes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for m in meshes:
		var mi := m as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		var tf := Transform3D()
		var walk: Node = mi
		while walk and walk != container:
			if walk is Node3D:
				tf = (walk as Node3D).transform * tf
			walk = walk.get_parent()
		var b := tf * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

## Compares the model with the ground under it. Returns {"ok": bool, "text":
## String, "lift": float} where `lift` is how far the model would have to rise
## (negative: sink) for its most ground-penetrating part to just touch the
## ground -- what "sit on the ground" applies to a model with no known height.
## `ground` (optional, (e, n) -> height) replaces the natural ground, e.g. with
## ConstructionTerrain.height_at to check against the levelled platforms.
static func position_check(data: TerrainData, samples: Array, ground := Callable()) -> Dictionary:
	var rows: Array = []
	for s in samples:
		if not data.contains(s.e, s.n):
			continue
		var g: float = ground.call(s.e, s.n) if ground.is_valid() else data.height_at(s.e, s.n)
		rows.append({"bottom": s.bottom - g, "top": s.top - g})
	if rows.is_empty():
		return {"ok": false, "text": "El modelo queda fuera del terreno descargado.", "lift": 0.0, "count": 0}
	var lowest := INF
	var highest_bottom := -INF
	var buried := 0
	for r in rows:
		lowest = minf(lowest, r.bottom)
		highest_bottom = maxf(highest_bottom, r.bottom)
		if r.top < -1.5:
			buried += 1
	var frac := float(buried) / rows.size()
	var problems: Array = []
	if frac > 0.5:
		problems.append("el %d %% de las piezas queda bajo el terreno" % int(round(frac * 100.0)))
	if lowest > 40.0:
		problems.append("el modelo flota: su pieza más baja está %.0f m sobre el suelo" % lowest)
	var text := "Posición: la base de las piezas va de %+.1f a %+.1f m respecto al suelo; %d de %d piezas enterradas." % [
		lowest, highest_bottom, buried, rows.size()]
	if not problems.is_empty():
		text += " AVISO: " + "; ".join(problems) + ". Revisa la georreferencia (E, N, huso, altura, giro)."
	return {"ok": problems.is_empty(), "text": text, "lift": -lowest, "count": rows.size()}
