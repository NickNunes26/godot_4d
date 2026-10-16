## Headless test for a scene crane's on-site window and the luffing boom.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_crane_site.gd
extends SceneTree

const CraneScript = preload("res://addons/construction_4d_tool/runtime/crane.gd")

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

## A crawler-style crane: Arm slews at 2 m; a 30 m Boom at 60 degrees from a
## foot 1 m out; Track at its head carrying Rope and Hook.
func _crawler(crane_name: String) -> Node3D:
	var c := Node3D.new()
	c.name = crane_name
	c.set_script(CraneScript)
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0, 2, 0)
	c.add_child(arm)
	var boom := MeshInstance3D.new()
	boom.name = "Boom"
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 1, 1)
	boom.mesh = bm
	var dir := Vector3(cos(deg_to_rad(60)), sin(deg_to_rad(60)), 0)
	boom.transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(60)), Vector3(1, 0, 0) + dir * 15.0)
	arm.add_child(boom)
	var track := Node3D.new()
	track.name = "Track"
	track.position = Vector3(1, 0, 0) + dir * 30.0
	arm.add_child(track)
	var rope := MeshInstance3D.new()
	rope.name = "Rope"
	var rm := CylinderMesh.new()
	rm.height = 1.0
	rope.mesh = rm
	track.add_child(rope)
	var hook := MeshInstance3D.new()
	hook.name = "Hook"
	var hm := BoxMesh.new()
	hm.size = Vector3.ONE * 0.5
	hook.mesh = hm
	hook.position = Vector3(0, -5, 0)
	track.add_child(hook)
	return c

func _run() -> void:
	print("=== luffing boom: the head reaches the lift's radius at the boom tip")
	var c := _crawler("Crawler")
	root.add_child(c)
	await process_frame
	var arm: Node3D = c.get_node("Arm")
	var boom: Node3D = arm.get_node("Boom")
	var track: Node3D = arm.get_node("Track")
	# The foot is the middle of the heel (x = 1 minus half the width's slant).
	_check("boom measured: 30 m (%.3f)" % c._boom_length, absf(c._boom_length - 30.0) < 0.6, true)
	_check("at 60 degrees (%.2f)" % rad_to_deg(c._boom_angle0), absf(rad_to_deg(c._boom_angle0) - 60.0) < 1.0, true)
	var ang: float = c.boom_angle_for(22.0)
	c._set_boom_angle(ang)
	_check("head at 22 m radius (%.3f)" % track.position.x, absf(track.position.x - 22.0) < 1e-3, true)
	var tip: Vector3 = boom.transform * Vector3(15, 0, 0)
	_check("and still on the boom's tip (%.3f m off)" % (tip - track.position).length(), (tip - track.position).length() < 0.6, true)
	var heel: Vector3 = boom.transform * Vector3(-15, 0, 0)
	_check("the heel stays put (%.3f m)" % (heel - Vector3(1, 0, 0)).length(), (heel - Vector3(1, 0, 0)).length() < 0.6, true)
	c._set_boom_angle(c.boom_angle_for(200.0))
	_check("never below 15 degrees", absf(rad_to_deg(c._boom_angle) - 15.0) < 1e-3, true)

	print("\n=== following a lift: luffs instead of sliding a trolley")
	c.retract(2.0) # a scrub just before the lift: its tween must not fight it
	var part := MeshInstance3D.new()
	part.name = "Beam"
	var pm := BoxMesh.new()
	pm.size = Vector3(10, 1, 2)
	part.mesh = pm
	part.position = Vector3(0, 3, 18)
	root.add_child(part)
	part.set_meta("original_aabb", pm.get_aabb())
	c.swing(part.global_position, part.global_position, 0.01, 0.0, part)
	for i in 5:
		await process_frame
	var hook: Node3D = track.get_node("Hook")
	var hook_xz := Vector2(hook.global_position.x, hook.global_position.z)
	_check("hook over the beam (%.3f m off)" % hook_xz.distance_to(Vector2(0, 18)), hook_xz.distance_to(Vector2(0, 18)) < 0.05, true)
	var head_r := Vector2(track.global_position.x, track.global_position.z).length()
	_check("boom head at the beam's radius (%.3f)" % head_r, absf(head_r - 18.0) < 0.05, true)
	c.retract(0.01)
	for i in 5:
		await process_frame
	_check("retract lays the boom back to its own angle", absf(c._boom_angle - c._boom_angle0) < 1e-3, true)

	var fresh := _crawler("Fresh")
	var zone := Node3D.new()
	zone.name = "PickupZone"
	zone.position = Vector3(-14, 0, 0)
	fresh.add_child(zone)
	root.add_child(fresh)
	# As when the schedule asks before this crane's _ready() (later in the tree
	# than the SequenceManager): its @onready reference is still unset.
	fresh._pickup_zone = null
	_check("laydown found before the crane is ready", fresh.get_pickup_position(Vector3(99, 0, 0)), Vector3(-14, 0, 0))
	fresh.queue_free()

	print("\n=== on site only around its work")
	var actions := [
		{"id": "A", "target_prefix": "Start", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 10},
		{"id": "L1", "target_prefix": "Beam", "type": "fill_up", "depends_on": "A", "duration_days": 2, "crane_id": "Crawler"},
		{"id": "L2", "target_prefix": "NoParts", "type": "fill_up", "depends_on": "L1", "duration_days": 3, "crane_id": "Crawler"},
		{"id": "Z", "target_prefix": "End", "type": "fill_up", "depends_on": "L2", "duration_days": 10},
	]
	var parts := {"Beam": part}
	# Parts for the first and last actions, so the schedule runs from day 0 to
	# 25 rather than over the beam's two days only.
	for n in ["Start", "End"]:
		var q := MeshInstance3D.new()
		q.name = n
		q.mesh = BoxMesh.new()
		q.position = Vector3(50, 0, 50)
		root.add_child(q)
		parts[n] = q
	for q in parts.values():
		q.set_meta("original_pos", q.position)
		q.set_meta("original_scale", q.scale)
		q.set_meta("original_transform", q.global_transform)
		q.set_meta("original_aabb", q.mesh.get_aabb())
	var sched := ConstructionSchedule.new({"steps": [{"actions": actions}]}, parts, SpatialGrouper.new())
	var w := sched.crane_window(c)
	_check("from a day before its first action (day 9)", w.start_day, 9.0)
	_check("to a day after its last (day 16)", w.end_day, 16.0)
	c.set("setup_days", 0.0)
	c.set("on_site_from", "2027-01-05")
	c.set("on_site_until", "L1")
	w = sched.crane_window(c)
	_check("a date for on_site_from (day 4)", w.start_day, 4.0)
	_check("an action id for on_site_until: its finish (day 12)", w.end_day, 12.0)
	c.set("on_site_from", "no such thing")
	c.set("on_site_until", "")
	c.set("setup_days", 1.0)
	_check("an unknown value counts as empty", sched.crane_window(c).start_day, 9.0)
	c.set("on_site_from", "")
	var idle := _crawler("Idle")
	root.add_child(idle)
	await process_frame
	_check("a crane with no window and no work stands throughout", sched.crane_window(idle), {})

	print("\n=== the timeline shows and hides it, and puts it back")
	var tc := TimelineController.new()
	root.add_child(tc)
	tc.set_schedule(sched, parts, {"Crawler": c, "Idle": idle})
	tc.scrub_to(5.0)
	_check("day 5: not there yet", c.visible, false)
	tc.scrub_to(11.0)
	_check("day 11: on site", c.visible, true)
	tc.scrub_to(20.0)
	_check("day 20: gone", c.visible, false)
	_check("the idle crane never leaves", idle.visible, true)
	tc.restore_site_cranes()
	_check("restored to its own visibility", c.visible, true)

	print("\n=== stands: one crane, lifting from where each lift is made")
	var walker := _crawler("Walker")
	var lay := Node3D.new()
	lay.name = "PickupZone"
	lay.position = Vector3(-14, 0, 0)
	walker.add_child(lay)
	root.add_child(walker)
	var marks := Node3D.new()
	marks.name = "Stands"
	root.add_child(marks)
	var sa := Marker3D.new()
	sa.name = "StandA"
	sa.position = Vector3(100, 0, 0)
	marks.add_child(sa)
	var sb := Marker3D.new()
	sb.name = "StandB"
	sb.position = Vector3(200, 0, 0)
	sb.rotation.y = PI / 2
	marks.add_child(sb)
	walker.set("stands", [walker.get_path_to(sa), walker.get_path_to(sb)] as Array[NodePath])
	await process_frame
	_check("the nearest stand to a piece", ConstructionSchedule.nearest_stand(walker, Vector3(190, 0, 30)), sb)
	_check("or the one named", ConstructionSchedule.nearest_stand(walker, Vector3(190, 0, 30), "StandA"), sa)
	_check("the laydown travels with the crane (%s)" % walker.get_pickup_position(Vector3.ZERO, sb),
		walker.get_pickup_position(Vector3.ZERO, sb).distance_to(Vector3(200, 0, 14)) < 1e-3, true)
	var walk_actions := [
		{"id": "A", "target_prefix": "Start", "type": "fill_up", "start_date": "2027-01-01", "duration_days": 10},
		{"id": "W1", "target_prefix": "NoParts1", "type": "fill_up", "depends_on": "A", "duration_days": 2, "crane_id": "Walker", "crane_stand": "StandA"},
		{"id": "W2", "target_prefix": "NoParts2", "type": "fill_up", "depends_on": "W1", "lag_days": 2, "duration_days": 2, "crane_id": "Walker", "crane_stand": "StandB"},
		{"id": "Z", "target_prefix": "End", "type": "fill_up", "depends_on": "W2", "duration_days": 10},
	]
	var ws := ConstructionSchedule.new({"steps": [{"actions": walk_actions}]}, parts, SpatialGrouper.new())
	var pose_at := func(day: float) -> Vector3: return (ws.crane_pose(walker, day) as Transform3D).origin
	_check("before its first lift: at that lift's stand", pose_at.call(3.0), Vector3(100, 0, 0))
	_check("lifting W1 (days 10-12): at StandA", pose_at.call(11.0), Vector3(100, 0, 0))
	_check("half way through the 2-day gap: half way across", pose_at.call(13.0), Vector3(150, 0, 0))
	_check("lifting W2 (days 14-16): at StandB", pose_at.call(15.0), Vector3(200, 0, 0))
	_check("turned like the marker", absf((ws.crane_pose(walker, 15.0) as Transform3D).basis.get_euler().y - PI / 2) < 1e-4, true)
	_check("after: stays at the last stand", pose_at.call(25.0), Vector3(200, 0, 0))
	_check("a crane without stands has no pose", ws.crane_pose(idle, 11.0), null)
	var tc2 := TimelineController.new()
	root.add_child(tc2)
	walker.position = Vector3(5, 0, 5)
	tc2.set_schedule(ws, parts, {"Walker": walker})
	tc2.scrub_to(15.0)
	_check("the timeline puts it there", walker.global_position.distance_to(Vector3(200, 0, 0)) < 1e-3, true)
	walker.retract(0.01)
	for i in 3:
		await process_frame
	var arm_fwd: Vector3 = walker.get_node("Arm").global_transform.basis.x
	_check("its arm rests turned with it", absf(arm_fwd.normalized().dot(walker.global_transform.basis.x.normalized()) - 1.0) < 1e-3, true)
	# A lift of the walker's that is over: the timeline takes its hook off.
	walker.set("_tracked_part", part)
	_check("not lifting between its lifts", ws.crane_lifting(walker, 13.0), false)
	tc2.scrub_to(13.0)
	_check("so the timeline retracts it (hook off the piece)", walker.get("_tracked_part"), null)
	tc2.restore_site_cranes()
	_check("and Stop Preview puts it back", walker.position.distance_to(Vector3(5, 0, 5)) < 1e-3, true)

	print("\n" + ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
