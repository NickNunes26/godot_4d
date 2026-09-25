## Several IFC models in one scene (IfcSceneModels): two invented fixtures of
## one site share a map conversion (rotated 20 deg) but hold different boxes.
## Imported one after the other with the dock's steps (GDIFCRecenter -> GDIFC
## -> framing shift -> GDIFC4DAdapter -> IfcSceneModels.attach()), each box
## must land where its own file puts it on the map, measured through the
## scene's single origin; the first origin must be kept; both containers must
## be registered; re-importing a file must replace its container. Also the
## cases that cannot be placed (no georeference, another UTM zone).
##
## The GDIFC part needs the GDIFC addon and is skipped without it.
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_scene_models.gd
extends SceneTree

const FIXTURES := "res://addons/construction_4d_tool/tests/fixtures/"
const SM_SCRIPT := "res://addons/construction_4d_tool/runtime/sequence_manager.gd"

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
	_test_unplaceable()
	if ClassDB.class_exists("GDIFCManager"):
		await _test_two_models()
	else:
		print("GDIFC not installed -- two-model import skipped.")
	print("\n%s (%d failure(s))" % ["ALL PASSED" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)

## A SequenceManager that never enters the tree (its runtime _ready would
## load a schedule); IfcSceneModels only needs its properties and children.
func _new_sm() -> Node3D:
	var sm := Node3D.new()
	sm.set_script(load(SM_SCRIPT))
	sm.name = "SequenceManager"
	return sm

## Where box `ifc_center` (IFC local x, y, z) of a file with this fixture's map
## conversion is on the map.
func _expected(ifc_center: Vector3) -> Vector3:
	var c := cos(deg_to_rad(20.0))
	var s := sin(deg_to_rad(20.0))
	return Vector3(440000.0 + ifc_center.x * c - ifc_center.y * s,
		4474000.0 + ifc_center.x * s + ifc_center.y * c, 600.0 + ifc_center.z)

## The one part of `container`, measured on the map through the scene origin.
func _on_map(sm, container: Node3D) -> Vector3:
	var anchor := sm.get_node(sm.parts_container_path) as Node3D
	var part := container.get_child(0) as MeshInstance3D
	var local := anchor.transform.affine_inverse() * container.transform * (part.transform * part.mesh.get_aabb().get_center())
	var m: PackedFloat64Array = sm.geo_origin.local_to_map(local)
	return Vector3(m[0], m[1], m[2])

func _import(sm, file: String) -> Dictionary:
	var info := GDIFCRecenter.recenter_with_info(FIXTURES + file)
	var mgr = ClassDB.instantiate("GDIFCManager")
	root.add_child(mgr)
	var settings = ClassDB.instantiate("GDIFCLoaderSettings")
	settings.set("coordinate_to_origin", false)
	mgr.set_gdifc_settings(settings)
	mgr.read_ifc(info.path, false, [])
	await mgr.ifc_read
	var box := AABB()
	var first := true
	for node in mgr.find_children("*", "MeshInstance3D", true, false):
		if node.mesh:
			var b: AABB = node.global_transform * node.get_aabb()
			box = b if first else box.merge(b)
			first = false
	var shift := box.get_center()
	mgr.global_position -= shift
	var container := GDIFC4DAdapter.adapt(mgr, null, IfcSceneModels.taken_part_names(sm, file))
	mgr.queue_free()
	var result := IfcSceneModels.attach(sm, container, GeoOrigin.from_ifc_import(info, shift), file)
	result.container = container
	return result

func _test_two_models() -> void:
	print("=== two models of one site")
	var holder := Node3D.new()
	root.add_child(holder)
	var sm = _new_sm()
	var want_a := _expected(Vector3(10.0, 20.0, 7.0))   # box A: 2 x 3 x 4 at (10, 20, 5)
	var want_b := _expected(Vector3(45.0, -12.0, 5.5))  # box B: 6 x 2 x 5 at (45, -12, 3)

	var a: Dictionary = await _import(sm, "site_model_a.ifc")
	_check("first model is the primary", a.role == "primary" and sm.parts_container_path == NodePath("IFCParts_site_model_a"), str(sm.parts_container_path))
	_check("first model sets the origin", a.geo_changed and sm.geo_origin.has_position())
	var origin: GeoOrigin = sm.geo_origin
	_check("box A on the map (off %.4f m)" % _on_map(sm, a.container).distance_to(want_a), _on_map(sm, a.container).distance_to(want_a) < 0.01)

	var b: Dictionary = await _import(sm, "site_model_b.ifc")
	_check("second model goes to extra_part_containers", b.role == "extra" and sm.extra_part_containers == [NodePath("IFCParts_site_model_b")], str(sm.extra_part_containers))
	_check("primary unchanged", sm.parts_container_path == NodePath("IFCParts_site_model_a"))
	_check("origin kept", sm.geo_origin == origin and not b.geo_changed)
	_check("second model placed by the georeference", b.placement == "map", b.placement)
	var off_b: float = _on_map(sm, b.container).distance_to(want_b)
	_check("box B on the map, through the first origin (off %.4f m)" % off_b, off_b < 0.01)
	_check("box A still in place", _on_map(sm, a.container).distance_to(want_a) < 0.01)
	var names: Array = sm.collect_part_nodes().map(func(p): return String(p.name))
	_check("both models registered, names unique", names.size() == 2 and names[0] != names[1], str(names))

	# Re-import B: replaced in its slot, nothing duplicated.
	var b2: Dictionary = await _import(sm, "site_model_b.ifc")
	_check("re-import replaces the extra", b2.replaced and b2.role == "extra" and sm.extra_part_containers.size() == 1, str(sm.extra_part_containers))
	_check("re-import keeps the name", String(b2.container.name) == "IFCParts_site_model_b", b2.container.name)
	_check("still two containers", IfcSceneModels.containers(sm).size() == 2)
	_check("re-imported box B in place", _on_map(sm, b2.container).distance_to(want_b) < 0.01)

	# Re-import A (the primary): the origin is rebased onto the new container,
	# both boxes stay put.
	var a2: Dictionary = await _import(sm, "site_model_a.ifc")
	_check("re-import replaces the primary", a2.replaced and a2.role == "primary" and sm.get_node(sm.parts_container_path) == a2.container)
	_check("box A in place after re-import", _on_map(sm, a2.container).distance_to(want_a) < 0.01)
	_check("box B in place after primary re-import", _on_map(sm, b2.container).distance_to(want_b) < 0.01)
	_check("old containers freed from the scene", sm.get_child_count() == 2, str(sm.get_child_count()))
	sm.free()
	holder.queue_free()

func _test_unplaceable() -> void:
	print("=== models that cannot be placed")
	var sm = _new_sm()
	var first := Node3D.new()
	var mc := {"e": 440000.0, "n": 4474000.0, "h": 600.0, "abscissa": 1.0, "ordinate": 0.0, "scale": 1.0}
	var geo := GeoOrigin.from_ifc_import({"map_conversion": mc, "crs_zone": 30}, Vector3.ZERO)
	IfcSceneModels.attach(sm, first, geo, "first.ifc")
	first.position = Vector3(5, 0, 5) # the user moved the first model: others follow it

	var plain := Node3D.new()
	var r := IfcSceneModels.attach(sm, plain, GeoOrigin.from_ifc_import({}, Vector3(3, 1, -4)), "plain.ifc")
	_check("no georeference: unplaced, at the first model's origin", r.placement == "unplaced" and plain.transform == first.transform and r.message != "", r.message)
	_check("no georeference: origin kept", sm.geo_origin == geo and not r.geo_changed)

	var far := Node3D.new()
	var r2 := IfcSceneModels.attach(sm, far, GeoOrigin.from_ifc_import({"map_conversion": mc, "crs_zone": 31}, Vector3.ZERO), "far.ifc")
	_check("other UTM zone: unplaced, with a message", r2.placement == "unplaced" and r2.message.contains("zone 31"), r2.message)
	_check("three containers, primary first", IfcSceneModels.containers(sm) == [first, plain, far])

	# A scene whose first model had no georeference adopts the first one that has.
	var sm2 = _new_sm()
	var p0 := Node3D.new()
	IfcSceneModels.attach(sm2, p0, GeoOrigin.from_ifc_import({}, Vector3.ZERO), "p0.ifc")
	var p1 := Node3D.new()
	var r3 := IfcSceneModels.attach(sm2, p1, geo, "p1.ifc")
	_check("unreferenced scene adopts a georeferenced model's origin", r3.geo_changed and sm2.geo_origin == geo and p1.transform == p0.transform)
	sm.free()
	sm2.free()
