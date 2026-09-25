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
## This is a best-effort text patch, not a full STEP parser: it assumes one
## entity per line (as basically every IFC exporter emits), and only handles
## the two common carriers of a large global offset -- IfcMapConversion and
## a root IfcLocalPlacement's IfcCartesianPoint. Anything more exotic (offset
## smeared across many placements, no single root) will pass through
## unmodified.

const JITTER_THRESHOLD := 1000.0 ## world units; float32 spacing gets coarse enough to matter well before this
const CACHE_DIR := "user://gdifc_recentered/"

## Returns the path to a recentered copy of `ifc_path` if a large offset was
## found and stripped, or `ifc_path` unchanged if nothing needed fixing (or
## preprocessing failed, in which case the original will load as before --
## possibly with jitter, but never worse than the pre-existing behavior).
static func recenter(ifc_path: String) -> String:
	var file := FileAccess.open(ifc_path, FileAccess.READ)
	if not file:
		push_warning("GDIFCRecenter: could not open '%s' for preprocessing, loading as-is" % ifc_path)
		return ifc_path

	var text := file.get_as_text()
	file.close()

	var result := _strip_large_offsets(text)
	if not result.changed:
		return ifc_path

	var dir_err := DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("GDIFCRecenter: could not create cache dir '%s' (err %s), loading original (expect float32 jitter)" % [CACHE_DIR, dir_err])
		return ifc_path

	var out_path := CACHE_DIR.path_join(ifc_path.get_file())
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if not out_file:
		push_warning("GDIFCRecenter: could not write recentered copy to '%s', loading original (expect float32 jitter)" % out_path)
		return ifc_path

	out_file.store_string(result.text)
	out_file.close()

	print("GDIFCRecenter: '%s' had a large georeferenced offset (~%s) -- recentered copy written to '%s'" % [ifc_path.get_file(), result.offset, out_path])
	return out_path


static func _strip_large_offsets(text: String) -> Dictionary:
	var changed := false
	var offset := Vector3.ZERO

	# IfcMapConversion(SourceCRS, TargetCRS, Eastings, Northings, OrthogonalHeight, XAxisAbscissa, XAxisOrdinate, Scale)
	var map_re := RegEx.new()
	map_re.compile("(?im)^(#\\d+=IFCMAPCONVERSION\\(\\s*#\\d+\\s*,\\s*#\\d+\\s*,\\s*)([^,]+),([^,]+),([^,]+)(,.*\\);)$")
	for m in map_re.search_all(text):
		var e := m.get_string(2).to_float()
		var n := m.get_string(3).to_float()
		var h := m.get_string(4).to_float()
		if absf(e) > JITTER_THRESHOLD or absf(n) > JITTER_THRESHOLD or absf(h) > JITTER_THRESHOLD:
			var replacement := "%s0.,0.,0.%s" % [m.get_string(1), m.get_string(5)]
			text = text.replace(m.get_string(0), replacement)
			offset = Vector3(e, n, h)
			changed = true

	# Root placements: IfcLocalPlacement($, #axis) -> IfcAxis2Placement3D(#point, ...) -> IfcCartesianPoint((x,y,z))
	var root_re := RegEx.new()
	root_re.compile("(?im)^#\\d+=IFCLOCALPLACEMENT\\(\\$,\\s*#(\\d+)\\)")
	var axis_ids := {}
	for m in root_re.search_all(text):
		axis_ids[m.get_string(1)] = true

	for axis_id in axis_ids:
		var axis_re := RegEx.new()
		axis_re.compile("(?im)^#%s=IFCAXIS2PLACEMENT3D\\(#(\\d+)" % axis_id)
		var am := axis_re.search(text)
		if not am:
			continue

		var point_id := am.get_string(1)
		var point_re := RegEx.new()
		point_re.compile("(?im)^(#%s=IFCCARTESIANPOINT\\(\\()([^)]+)(\\)\\);)$" % point_id)
		var pm := point_re.search(text)
		if not pm:
			continue

		var coords := pm.get_string(2).split(",")
		var is_large := false
		for c in coords:
			if absf(c.to_float()) > JITTER_THRESHOLD:
				is_large = true
				break
		if not is_large:
			continue

		var zero_coords := PackedStringArray()
		for i in coords.size():
			zero_coords.append("0.")
		var replacement := "%s%s%s" % [pm.get_string(1), ",".join(zero_coords), pm.get_string(3)]
		text = text.replace(pm.get_string(0), replacement)
		if coords.size() >= 3:
			offset = Vector3(coords[0].to_float(), coords[1].to_float(), coords[2].to_float())
		changed = true

	return {"text": text, "changed": changed, "offset": offset}
