@tool
class_name TerrainProvider
extends RefCounted

## A source of elevation (and optionally orthophotos) for some part of the
## world. New countries plug in by subclassing this; nothing else in the
## terrain pipeline knows about a specific service.
##
## Downloads are *described* here (URL, cache file name, timeout) and performed
## by TerrainDownloader, so a provider stays plain data + parsing and can be
## unit-tested without a network.

## Short stable id, used in cache keys and saved terrain data.
func id() -> String:
	return ""

## Human-readable name for the dock.
func display_name() -> String:
	return ""

## Whether this provider has data at (lat, lon).
func covers(_lat: float, _lon: float) -> bool:
	return false

## Whether ortho_download() can return anything.
func has_imagery() -> bool:
	return false

## Credit line that must be shown wherever the terrain is used.
func attribution() -> String:
	return ""

## Elevation files to fetch: [{"url", "file", "timeout"}], file relative to
## the cache folder.
func elevation_downloads(_spec: TerrainSpec) -> Array:
	return []

## Builds the spec's regular grid from the downloaded files in `dir`:
## {"heights": PackedFloat32Array (grid_n^2, row 0 = north), "error": String}.
## Runs on a worker thread: must not touch the scene tree.
func build_heights(_spec: TerrainSpec, _dir: String) -> Dictionary:
	return {"error": "not implemented"}

## One orthophoto square of half side `half`: {"url", "file", "timeout",
## "rect": PackedFloat64Array([e0, n0, e1, n1])} or {} when unsupported.
func ortho_download(_spec: TerrainSpec, _half: float, _name: String) -> Dictionary:
	return {}

## "" if the downloaded file at `path` is a usable image, else the reason.
func validate_ortho(path: String) -> String:
	return image_complete(path)

## "" if a downloaded elevation file is complete and parseable, else the reason.
func validate_elevation(_path: String) -> String:
	return ""

## "" if `path` is a whole JPEG or PNG (start and end markers present), else
## the reason -- including the service's own error text when it sent one.
static func image_complete(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return "cannot open %s" % path
	var n := f.get_length()
	var head := f.get_buffer(4)
	var is_jpeg := head.size() >= 2 and head[0] == 0xFF and head[1] == 0xD8
	var is_png := head.size() >= 4 and head[0] == 0x89 and head[1] == 0x50
	if not is_jpeg and not is_png:
		f.seek(0)
		return "the service did not return an image: %s" % f.get_buffer(mini(400, n)).get_string_from_utf8()
	f.seek(maxi(n - 12, 0))
	var tail := f.get_buffer(12)
	if is_jpeg and tail.size() >= 2 and tail[tail.size() - 2] == 0xFF and tail[tail.size() - 1] == 0xD9:
		return ""
	if is_png and tail.size() >= 8 and tail.slice(tail.size() - 8, tail.size() - 4).get_string_from_ascii() == "IEND":
		return ""
	return "incomplete image (%d bytes)" % n

## A tiny elevation query around (lat, lon), for telling UTM zones apart:
## {"url", "file", "timeout"} or {} when unsupported.
func probe_download(_lat: float, _lon: float) -> Dictionary:
	return {}

## Mean ground height of a probe file; NAN for sea / no data.
func probe_height(_path: String) -> float:
	return NAN

## UTM zones to try when the model does not declare one.
func candidate_zones() -> Array:
	return []
