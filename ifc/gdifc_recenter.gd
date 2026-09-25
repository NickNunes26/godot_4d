@tool
class_name GDIFCRecenter
extends RefCounted

## Preprocesses a raw IFC (STEP) file to strip large georeferenced offsets
## before GDIFCManager ever loads it.
##
## GDIFC bakes coordinates directly into vertex data at float32 precision.
## Survey/map coordinates (hundreds of thousands to millions of units) leave
## less than float32's usual precision between neighboring vertices -- at
## ~4.7e6 the gap between representable values is already ~0.5 units -- so
## georeferenced models jitter and z-fight no matter what transform is
## applied to them after loading. The fix has to happen before GDIFC
## converts the geometry, which means editing the source file.
##
## What is stripped is *recorded*, not thrown away: recenter_with_info()
## returns it so the import can keep the model's position on Earth (see
## GeoOrigin and docs/10_TERRAIN.md). GDIFC itself ignores IfcMapConversion
## (verified against the GDIFC build this was written with), so the map
## conversion is only reported, never stripped: it does not reach the
## geometry, and a file whose only offset is there loads as-is, with no copy.
##
## This is a best-effort text patch, not a full STEP parser: the offset it
## strips is the common one, in a root IfcLocalPlacement's IfcCartesianPoint.
## Anything more exotic (offset smeared across many placements, no single
## root) will pass through unmodified.
##
## Cost, measured on a ~300 MB file: ~1.2 s and a transient ~1.3 GB (the file
## as a String), freed before GDIFC starts -- whose own peak is higher.

const JITTER_THRESHOLD := 1000.0 ## world units; float32 spacing gets coarse enough to matter well before this
const CACHE_DIR := "user://gdifc_recentered/"

## Returns the path to a recentered copy of `ifc_path` if a large offset was
## found and stripped, or `ifc_path` unchanged if nothing needed fixing (or
## preprocessing failed, in which case the original will load as before --
## possibly with jitter, but never worse than the pre-existing behavior).
static func recenter(ifc_path: String) -> String:
	return recenter_with_info(ifc_path).path

## Same as recenter(), plus what the file says about its georeference:
## {
##   "path": String,                        # the file to hand to GDIFC
##   "root_offset": PackedFloat64Array,     # (x, y, z) subtracted from the root placement(s), IFC axes
##   "map_conversion": Dictionary,          # IfcGeoref.read()'s block, {} if none
##   "crs_name": String, "crs_zone": int,   # from IfcProjectedCRS, "" / 0 if absent
## }
## `root_offset` is what the loaded geometry is missing relative to the file's
## own coordinates; the map conversion then applies on top of that.
static func recenter_with_info(ifc_path: String) -> Dictionary:
	var info := {"path": ifc_path, "root_offset": PackedFloat64Array([0.0, 0.0, 0.0]),
		"map_conversion": {}, "crs_name": "", "crs_zone": 0}
	var file := FileAccess.open(ifc_path, FileAccess.READ)
	if not file:
		push_warning("GDIFCRecenter: could not open '%s' for preprocessing, loading as-is" % ifc_path)
		return info

	var text := file.get_as_text()
	file.close()

	var georef := IfcGeoref.read(text)
	info.map_conversion = georef.map_conversion
	info.crs_name = georef.crs_name
	info.crs_zone = georef.crs_zone

	var result := _strip_large_offsets(text, georef)
	if not result.changed:
		return info

	var dir_err := DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("GDIFCRecenter: could not create cache dir '%s' (err %s), loading original (expect float32 jitter)" % [CACHE_DIR, dir_err])
		return info

	var out_path := CACHE_DIR.path_join(ifc_path.get_file())
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if not out_file:
		push_warning("GDIFCRecenter: could not write recentered copy to '%s', loading original (expect float32 jitter)" % out_path)
		return info

	out_file.store_string(result.text)
	out_file.close()

	info.path = out_path
	info.root_offset = result.root_offset
	var ro: PackedFloat64Array = result.root_offset
	var parts := PackedStringArray()
	if ro[0] != 0.0 or ro[1] != 0.0 or ro[2] != 0.0:
		parts.append("root placement %.3f, %.3f, %.3f" % [ro[0], ro[1], ro[2]])
	if not georef.map_conversion.is_empty():
		parts.append("map conversion E %.3f N %.3f H %.3f" % [georef.map_conversion.e, georef.map_conversion.n, georef.map_conversion.h])
	print("GDIFCRecenter: '%s' had a large georeferenced offset (%s) -- recentered copy written to '%s'" % [
		ifc_path.get_file(), "; ".join(parts), out_path])
	return info


## Subtracts one common offset from every large root placement point.
## Subtracting the *same* offset from all of them keeps several roots in their
## right relative positions, where zeroing each one independently would stack
## them on top of each other.
##
## A large IfcMapConversion origin is left in the file: GDIFC ignores the map
## conversion (it never reaches the geometry), IfcGeoref.read() has already
## recorded it, and rewriting the file only for it would copy a model of
## hundreds of MB on every import for no effect.
##
## Lines may end in CRLF (what most exporters write), hence the `\r?$`.
static func _strip_large_offsets(text: String, georef: Dictionary) -> Dictionary:
	var changed := false
	var root_offset := PackedFloat64Array([0.0, 0.0, 0.0])

	var roots: Array = georef.get("root_points", [])
	var have_offset := false
	for root in roots:
		var coords: PackedFloat64Array = root.coords
		var is_large := false
		for c in coords:
			if absf(c) > JITTER_THRESHOLD:
				is_large = true
				break
		if not is_large:
			continue
		if not have_offset:
			root_offset = PackedFloat64Array([coords[0], coords[1], coords[2]])
			have_offset = true
		elif absf(coords[0] - root_offset[0]) > 0.001 or absf(coords[1] - root_offset[1]) > 0.001 or absf(coords[2] - root_offset[2]) > 0.001:
			push_warning("GDIFCRecenter: root placements carry different large offsets; they keep their relative positions, measured from the first one")

		var point_re := RegEx.new()
		point_re.compile("(?im)^(%s\\s*=\\s*IFCCARTESIANPOINT\\(\\()([^)]+)(\\)\\);\\r?)$" % root.id)
		var pm := point_re.search(text)
		if not pm:
			continue
		var parts := pm.get_string(2).split(",")
		var shifted := PackedStringArray()
		for i in parts.size():
			var v := parts[i].to_float() - (root_offset[i] if i < 3 else 0.0)
			var s := "0." if is_zero_approx(v) else String.num(v, 6)
			shifted.append(s if s.contains(".") else s + ".") # a STEP REAL needs its point
		var replacement := "%s%s%s" % [pm.get_string(1), ",".join(shifted), pm.get_string(3)]
		text = text.replace(pm.get_string(0), replacement)
		changed = true

	return {"text": text, "changed": changed, "root_offset": root_offset}
