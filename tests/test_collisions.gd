## Headless test for crane-lift (install) clash detection, on plain boxes:
## a slab, a column standing on it, a beam craned onto the column, and a post
## standing in the beam's path.
##
## What it pins down:
##   - a piece landing where the model puts it is not a clash, whether it just
##     touches its bearing or is embedded in it (designed contact);
##   - a piece swinging through something on the way still is;
##   - a not-yet-grown (zero-scale) part is not treated as full size;
##   - the lift starts beside the piece at its own height even when the model's
##     container is offset (georeferenced / lowered onto the terrain);
##   - a full scan only samples the days a lift is in progress.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_collisions.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.name = name
	m.position = pos
	parent.add_child(m)
	return m

## Same metas SequenceManager.initialize_parts() records.
func _register(parts: Dictionary) -> void:
	for p in parts.values():
		p.set_meta("original_pos", p.position)
		p.set_meta("original_scale", p.scale)
		p.set_meta("original_transform", p.global_transform)
		p.set_meta("original_aabb", p.mesh.get_aabb())

## Slab, column on it, beam on the column (sunk `embed` metres into it), and
## optionally a post the beam's slide passes through. Beam: install, days 3..5
## (lift 3-3.6, slide 3.6-4.4, lower 4.4-5).
func _site(offset: Vector3, embed: float, with_post: bool, with_neighbour: bool = false) -> Dictionary:
	var container := Node3D.new()
	container.position = offset
	root.add_child(container)
	var parts := {}
	parts["SLAB"] = _box(container, "SLAB", Vector3(10, 0.3, 10), Vector3(0, 0.15, 0))
	parts["COL"] = _box(container, "COL", Vector3(0.4, 3, 0.4), Vector3(0, 1.8, 0))
	parts["BEAM"] = _box(container, "BEAM", Vector3(4, 0.5, 0.4), Vector3(0, 3.55 - embed, 0))
	var actions := [
		{"id": "S", "target_prefix": "SLAB", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 1},
		{"id": "C", "target_prefix": "COL", "type": "fill_up", "start_date": "2027-01-02", "duration_days": 1},
		{"id": "B", "target_prefix": "BEAM", "type": "install", "start_date": "2027-01-04", "duration_days": 2},
	]
	if with_neighbour:
		# The next segment along, already in place, sharing the beam's end face
		# over its full height -- adjacent cornice stones, a run of beams.
		parts["NEXT"] = _box(container, "NEXT", Vector3(4, 0.5, 0.4), Vector3(4, 3.55 - embed, 0))
		actions.append({"id": "N", "target_prefix": "NEXT", "type": "fill_up", "start_date": "2027-01-02", "duration_days": 1})
	if with_post:
		parts["POST"] = _box(container, "POST", Vector3(0.5, 10, 0.5), Vector3(7, 5, 0))
		actions.append({"id": "P", "target_prefix": "POST", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 1})
	_register(parts)
	var sched := ConstructionSchedule.new({"steps": [{"actions": actions}]}, parts, SpatialGrouper.new())
	var tc := TimelineController.new()
	root.add_child(tc)
	tc.set_schedule(sched, parts)
	return {"container": container, "parts": parts, "schedule": sched, "tc": tc}

## Drops every reference to the site's schedule as well: its CollisionQuery's
## physics areas live until it is freed, and would otherwise sit in the shared
## space under the next case's parts.
func _teardown(site: Dictionary) -> void:
	site.tc.queue_free()
	site.container.queue_free()
	site.clear()

## Collision pair names seen at any of `days`.
func _clashes(site: Dictionary, days: Array) -> Array:
	var seen := {}
	for day in days:
		site.tc.scrub_to(day, false)
		for c in site.tc.get_collisions():
			seen["%s|%s" % [c.part1, c.part2] if c.part1 < c.part2 else "%s|%s" % [c.part2, c.part1]] = true
	var out := seen.keys()
	out.sort()
	return out

func _run() -> void:
	await physics_frame
	var every_phase := [3.05, 3.3, 3.55, 3.7, 4.0, 4.3, 4.5, 4.8, 4.95, 4.99, 4.999]

	print("=== landing on the bearing is not a clash")
	var touching := _site(Vector3.ZERO, 0.0, false)
	await physics_frame
	_check("beam resting on the column: no clash in any phase", _clashes(touching, every_phase), [])
	_teardown(touching)

	var embedded := _site(Vector3.ZERO, 0.4, false)
	await physics_frame
	_check("beam modelled 40 cm into the column head: no clash either", _clashes(embedded, every_phase), [])
	_teardown(embedded)

	var neighbour := _site(Vector3.ZERO, 0.0, false, true)
	await physics_frame
	_check("lowered alongside the segment it abuts: no clash", _clashes(neighbour, every_phase), [])
	_teardown(neighbour)

	print("=== something in the way still is, on the default path")
	ConstructionSchedule.plan_lifts_enabled = false
	var blocked := _site(Vector3.ZERO, 0.0, true)
	await physics_frame
	_check("the post in the slide path clashes", _clashes(blocked, [4.0, 4.1, 4.2]), ["BEAM|POST"])
	_check("and only while the beam passes it", _clashes(blocked, [3.3, 4.8, 4.99]), [])
	var windows: Array = blocked.tc.scan_collisions(0.02)
	_check("full scan: one window", windows.size(), 1)
	if windows.size() == 1:
		_check("full scan: the post", [windows[0].part1, windows[0].part2].has("POST"), true)
		_check("full scan: inside the slide phase", windows[0].start_day > 3.6 and windows[0].end_day < 4.4, true)
	_check("install windows are what gets scanned", blocked.schedule.get_install_windows(), [[3.0, 5.0]])
	_teardown(blocked)
	ConstructionSchedule.plan_lifts_enabled = true

	print("=== ...and is cleared by a planned path (round the post, 10 m tall, at the hover height)")
	var planned := _site(Vector3.ZERO, 0.0, true)
	await physics_frame
	_check("the beam is taken over the post: no clash in any phase", _clashes(planned, every_phase.duplicate() + [4.1, 4.2, 4.35, 3.8, 4.6]), [])
	_check("the plan says so, and not the default", [planned.schedule.lift_plans["BEAM"].ok, planned.schedule.lift_plans["BEAM"].direct], [true, false])
	_check("full scan finds nothing", planned.tc.scan_collisions(0.02).size(), 0)
	planned.tc.scrub_to(5.0, false)
	_check("the lift ends where the model puts the beam", (planned.parts["BEAM"] as Node3D).position.is_equal_approx(planned.parts["BEAM"].get_meta("original_pos")), true)
	_teardown(planned)

	print("=== a part that has not grown yet is not full size")
	var ghost_site := _site(Vector3.ZERO, 0.0, false)
	await physics_frame
	var parts: Dictionary = ghost_site.parts
	var ghost := _box(ghost_site.container, "GHOST", Vector3(3, 3, 3), Vector3(0, 3.55, 0))
	parts["GHOST"] = ghost
	ghost.set_meta("original_transform", Transform3D(Basis(), Vector3(50, 0, 0))) # stands elsewhere when built
	var cq := CollisionQuery.new()
	cq.setup(parts)
	for p in parts.values():
		p.visible = true
	parts["BEAM"].position = ghost.position # mid-lift, right inside the ghost
	ghost.scale = Vector3.ONE * 1e-4
	var states := {
		"BEAM": {"anim_type": "install", "progress": 0.5},
		"GHOST": {"anim_type": "scale_up", "progress": 0.0001},
	}
	await physics_frame
	_check("tiny scale_up part around the beam: ignored", cq.query(parts, states, {}, {}).size(), 0)
	ghost.scale = Vector3.ONE
	_check("same part grown: clashes", cq.query(parts, states, {}, {}).size(), 1)
	_teardown(ghost_site)

	print("=== the lift starts beside the piece, in an offset container too")
	for offset in [Vector3.ZERO, Vector3(0, -12, 0), Vector3(300, 40, -80)]:
		var site := _site(offset, 0.0, false)
		await physics_frame
		var beam: MeshInstance3D = site.parts["BEAM"]
		var final_world: Vector3 = beam.get_meta("original_transform").origin
		site.tc.scrub_to(3.0001, false)
		var start_world := beam.global_position
		_check("offset %s: starts 15 m to the side at its own height" % offset, start_world.distance_to(final_world + Vector3(15, 0, 0)) < 0.05, true)
		site.tc.scrub_to(5.0, false)
		_check("offset %s: lands where the model puts it" % offset, beam.global_position.distance_to(final_world) < 0.001, true)
		_teardown(site)
		await physics_frame

	print("\n" + ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
