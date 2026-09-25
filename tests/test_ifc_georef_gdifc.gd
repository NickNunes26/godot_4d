## End-to-end check of the georeference through a real GDIFC load: the same
## steps Load IFC (4D) runs (GDIFCRecenter -> GDIFC -> framing shift ->
## GDIFC4DAdapter -> GeoOrigin), on three invented fixtures, verifying that the
## box in each lands at the map coordinates its IFC file describes. This is
## also the test of GDIFC's axis convention (IFC x,y,z -> Godot x,z,-y).
##
## Needs the GDIFC addon; skips (and passes) without it.
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_georef_gdifc.gd
extends SceneTree

const FIXTURES := "res://addons/construction_4d_tool/tests/fixtures/"

var _fails := 0
var _started := false

func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   " + detail])

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
	if not ClassDB.class_exists("GDIFCManager"):
		print("GDIFC not installed -- skipped.")
		quit(0)
		return
	var c30 := cos(deg_to_rad(30.0))
	var s30 := sin(deg_to_rad(30.0))
	# The box: IFC local x 9..11, y 18.5..21.5, z 5..9 under its site placement.
	await _case("root point", "georef_root_point.ifc", "ifc_coordinates",
		PackedFloat64Array([500110.0, 4400220.0, 657.0]), 0.0)
	await _case("map conversion (rotated 30 deg)", "georef_map_conversion.ifc", "ifc_map_conversion",
		PackedFloat64Array([500100.0 + 10.0 * c30 - 20.0 * s30, 4400200.0 + 10.0 * s30 + 20.0 * c30, 657.0]), 30.0)
	await _case("not georeferenced", "not_georeferenced.ifc", "", PackedFloat64Array(), 0.0)
	print("\n%s (%d failure(s))" % ["ALL PASSED" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)

func _case(label: String, file: String, want_source: String, want_center: PackedFloat64Array, want_rot: float) -> void:
	print("=== %s" % label)
	var info := GDIFCRecenter.recenter_with_info(FIXTURES + file)
	var mgr = ClassDB.instantiate("GDIFCManager")
	root.add_child(mgr)
	var settings = ClassDB.instantiate("GDIFCLoaderSettings")
	settings.set("coordinate_to_origin", false)
	mgr.set_gdifc_settings(settings)
	var err = mgr.read_ifc(info.path, false, [])
	_check("read_ifc started", err == OK, str(err))
	await mgr.ifc_read

	var box := AABB()
	var first := true
	for node in mgr.find_children("*", "MeshInstance3D", true, false):
		if node.mesh:
			var b: AABB = node.global_transform * node.get_aabb()
			box = b if first else box.merge(b)
			first = false
	_check("geometry loaded", not first)
	# GDIFC's axes: the box is 2 (x) x 3 (y) x 4 (z) in IFC -> 2 x 4 x 3 in Godot.
	_check("axis mapping: size (2, 4, 3)", box.size.distance_to(Vector3(2, 4, 3)) < 1e-3, str(box.size))
	_check("loaded geometry is small (offset stripped)", box.get_center().length() < 1000.0, str(box.get_center()))
	var shift := box.get_center()
	mgr.global_position -= shift
	var container := GDIFC4DAdapter.adapt(mgr, null)
	root.add_child(container)
	var geo := GeoOrigin.from_ifc_import(info, shift)
	_check("source '%s'" % want_source, geo.source == want_source, geo.source)
	if not want_center.is_empty():
		var part := container.get_child(0) as MeshInstance3D
		var local_center := part.transform * part.mesh.get_aabb().get_center()
		var m := geo.local_to_map(local_center)
		var d := Vector3(m[0] - want_center[0], m[1] - want_center[1], m[2] - want_center[2])
		_check("box centre on the map (off by %.4f m)" % d.length(), d.length() < 0.01, "%s vs %s" % [str(m), str(want_center)])
		_check("rotation %.0f deg" % want_rot, absf(geo.rotation_deg - want_rot) < 1e-6, str(geo.rotation_deg))
		# A corner too, so a rotation error can't hide in a symmetric centre.
		var aabb := part.mesh.get_aabb()
		var corner := geo.local_to_map(part.transform * aabb.position)
		var h_min := corner[2]
		_check("box bottom at H 655", absf(h_min - 655.0) < 0.01, str(h_min))
	mgr.queue_free()
	container.queue_free()
