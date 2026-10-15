## Headless test for "rotate": parts built standing up, then swung down about
## a hinge into their modelled place (an arch half lowered onto its springing).
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_rotate.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

## A box part with the metas SequenceManager.initialize_parts() records.
func _part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, tilt_deg: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = part_name
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.rotation_degrees.z = tilt_deg
	parent.add_child(m)
	m.set_meta("original_pos", m.position)
	m.set_meta("original_scale", m.scale)
	m.set_meta("original_quaternion", m.quaternion)
	m.set_meta("original_transform", m.global_transform)
	m.set_meta("original_aabb", b.get_aabb())
	return m

## World centre of a part's box, from its live transform.
func _centre(part: MeshInstance3D) -> Vector3:
	return part.global_transform * part.mesh.get_aabb().get_center()

func _group_centre(parts: Array) -> Vector3:
	var box := AABB()
	for i in parts.size():
		var p: MeshInstance3D = parts[i]
		var b: AABB = p.global_transform * p.mesh.get_aabb()
		box = b if i == 0 else box.merge(b)
	return box.get_center()

func _same(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 1e-3 and (a.basis.x - b.basis.x).length() < 1e-4 \
		and (a.basis.y - b.basis.y).length() < 1e-4 and (a.basis.z - b.basis.z).length() < 1e-4

func _run() -> void:
	# The container is moved and turned, as an IFC container recentred on a
	# georeferenced site is: the hinge works in world space regardless.
	var container := Node3D.new()
	root.add_child(container)
	container.position = Vector3(100, 5, -20)
	container.rotation_degrees.y = 30

	# A quarter arch: three 5 m dovelas climbing at 40 degrees from (0,0,0).
	var dir := Vector3(cos(deg_to_rad(40)), sin(deg_to_rad(40)), 0)
	var parts := {}
	var dovelas: Array = []
	for i in 3:
		var p := _part(container, "D%d" % (i + 1), Vector3(5, 1.5, 2), dir * (2.5 + 5.0 * i), 40)
		parts[p.name] = p
		dovelas.append(p)

	print("=== hinge_geometry: the pivot under the lowest piece, standing the group up")
	var geo := ConstructionSchedule.hinge_geometry(dovelas)
	var low_box: AABB = dovelas[0].global_transform * dovelas[0].mesh.get_aabb()
	_check("pivot is the middle of the lowest piece's base",
		geo.pivot.distance_to(Vector3(low_box.get_center().x, low_box.position.y, low_box.get_center().z)) < 1e-4, true)
	_check("axis is horizontal", absf(geo.axis.y) < 1e-6, true)
	_check("angle stands the pivot-to-centre line upright",
		absf(rad_to_deg(geo.angle) - rad_to_deg((_group_centre(dovelas) - geo.pivot).angle_to(Vector3.UP))) < 1e-3, true)
	_check("no geometry, no hinge", ConstructionSchedule.hinge_geometry([Node3D.new()]), {})

	print("\n=== the swing starts when the last piece is built, plus lag_days")
	var actions := [
		{"id": "D1", "target_prefix": "D1", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 2,
			"rotate": {"group": "HALF", "duration_days": 2}},
		{"id": "D2", "target_prefix": "D2", "type": "fill_up", "depends_on": "D1", "duration_days": 2,
			"rotate": {"group": "HALF"}},
		{"id": "D3", "target_prefix": "D3", "type": "fill_up", "depends_on": "D2", "duration_days": 2,
			"rotate": {"group": "HALF", "lag_days": 1}},
	]
	var sched := ConstructionSchedule.new({"steps": [{"actions": actions}]}, parts, SpatialGrouper.new())
	var h: Dictionary = sched.get_hinge("D1")
	_check("swing starts on day 7 (built by 6, lag 1)", h.start_day, 7.0)
	_check("and lasts 2 days", h.end_day, 9.0)
	_check("every piece swings about the same pivot", sched.get_hinge("D3").pivot == h.pivot, true)
	_check("the schedule runs to the end of the swing", sched.get_date_range().max_day, 9.0)
	_check("no rotate, no hinge", sched.get_hinge("nothing"), {})

	var tc := TimelineController.new()
	root.add_child(tc)
	tc.set_schedule(sched, parts)

	print("\n=== built standing up, as one rigid body")
	tc.scrub_to(6.5)
	var up_angle := rad_to_deg((_group_centre(dovelas) - h.pivot).angle_to(Vector3.UP))
	_check("before the swing the group stands upright (%.3f deg off)" % up_angle, up_angle < 0.01, true)
	_check("pieces keep their spacing", absf(_centre(dovelas[0]).distance_to(_centre(dovelas[1])) - 5.0) < 1e-3, true)
	var moved: Transform3D = dovelas[2].global_transform * (dovelas[2].get_meta("original_transform") as Transform3D).affine_inverse()
	_check("the pivot does not move", (moved * h.pivot).distance_to(h.pivot) < 1e-3, true)
	var upright: Transform3D = dovelas[2].global_transform

	print("\n=== the swing, eased")
	tc.scrub_to(8.0)
	var mid: float = sched.get_part_states(8.0)["D2"].hinge.angle
	_check("half way through the window, half the angle", absf(mid - h.angle / 2.0) < 1e-4, true)
	var early: float = sched.get_part_states(7.2)["D2"].hinge.angle
	_check("slow off the jacks (less than a linear 10 %)", h.angle - early < h.angle * 0.1, true)

	print("\n=== lands exactly on its modelled place")
	tc.scrub_to(9.5)
	for p in dovelas:
		_check("%s back to its modelled transform" % p.name, _same(p.global_transform, p.get_meta("original_transform")), true)

	print("\n=== scrubbing back and forth does not pile up")
	tc.scrub_to(8.0)
	tc.scrub_to(6.5)
	_check("back before the swing: same upright pose", _same(dovelas[2].global_transform, upright), true)
	tc.scrub_to(6.5)
	_check("the same day twice: same pose", _same(dovelas[2].global_transform, upright), true)

	print("\n=== the rotate removed: parts go back to their own rotation")
	tc.scrub_to(8.0)
	var plain := []
	for a in actions:
		var b: Dictionary = a.duplicate()
		b.erase("rotate")
		plain.append(b)
	var sched2 := ConstructionSchedule.new({"steps": [{"actions": plain}]}, parts, SpatialGrouper.new())
	tc.set_schedule(sched2, parts)
	tc.scrub_to(8.0)
	_check("D3 unturned once its swing is gone", _same(dovelas[2].global_transform, dovelas[2].get_meta("original_transform")), true)

	print("\n=== reset_rotation keeps position and scale")
	var p0: MeshInstance3D = dovelas[0]
	p0.rotation_degrees = Vector3(10, 20, 30)
	p0.scale = Vector3(1, 0.5, 1)
	p0.position = Vector3(1, 2, 3)
	AnimationApplier.reset_rotation(p0)
	_check("rotation back", p0.quaternion.is_equal_approx(p0.get_meta("original_quaternion")), true)
	_check("scale kept", p0.scale.is_equal_approx(Vector3(1, 0.5, 1)), true)
	_check("position kept", p0.position.is_equal_approx(Vector3(1, 2, 3)), true)

	print("\n=== a malformed rotate is ignored")
	var bad := [{"id": "D1", "target_prefix": "D1", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 1, "rotate": 5}]
	var sched3 := ConstructionSchedule.new({"steps": [{"actions": bad}]}, parts, SpatialGrouper.new())
	_check("no hinge from a rotate that is not an object", sched3.get_hinge("D1"), {})

	print("\n" + ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
