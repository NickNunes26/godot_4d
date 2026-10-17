## Headless test for the site plant: the procedural models, where they are
## placed, and how they follow the schedule.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_equipment.gd
extends SceneTree

const SM_SCRIPT := "res://addons/construction_4d_tool/runtime/sequence_manager.gd"

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

func _part(parent: Node3D, part_name: String, size: Vector3, center: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = part_name
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = center
	parent.add_child(m)
	return m

func _action(id: String, label: String, type: String, start: String, days: float) -> Dictionary:
	return {"id": id, "target_prefix": id, "type": type, "start_date": start, "duration_days": days,
		"batch": type != "drop_in", "comment": "%s -- n part(s)" % label}

## A 20 x 10 m, 9 m tall building with its dig, footings, walls in segments, a
## cornice of stone pieces and a roof; a cross 90 m away (out of any jib's
## reach), a granary placed after the roof is done, street lights, and a
## boundary wall 40 m out that must not drag the crane away from the building.
func _scene() -> Dictionary:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	current_scene = main
	var sm := Node3D.new()
	sm.name = "SequenceManager"
	main.add_child(sm)
	var parts := Node3D.new()
	parts.name = "Parts"
	sm.add_child(parts)
	for i in 2:
		_part(parts, "C01_Excavacion_%d" % i, Vector3(11, 1.5, 12), Vector3(-5.5 + i * 11, -0.75, 0))
	for i in 8:
		_part(parts, "C02_Zapatas_%d" % i, Vector3(1.5, 1, 1.5), Vector3(-9 + (i % 4) * 6, -0.5, -4 if i < 4 else 4))
	for i in 5:
		_part(parts, "C03_Muros_N%d" % i, Vector3(4, 9, 0.5), Vector3(-8 + i * 4, 4.5, -5))
		_part(parts, "C03_Muros_S%d" % i, Vector3(4, 9, 0.5), Vector3(-8 + i * 4, 4.5, 5))
	for i in 2:
		_part(parts, "C03_Muros_E%d" % i, Vector3(0.5, 9, 5), Vector3(10, 4.5, -2.5 + i * 5))
		_part(parts, "C03_Muros_W%d" % i, Vector3(0.5, 9, 5), Vector3(-10, 4.5, -2.5 + i * 5))
	for i in 8:
		_part(parts, "C04_Cornisa_%d" % i, Vector3(4, 0.5, 0.8), Vector3(-8 + (i % 4) * 5, 9.25, -5.2 if i < 4 else 5.2))
	_part(parts, "C05_Cubierta_1", Vector3(20, 0.3, 10), Vector3(0, 9.6, 0))
	_part(parts, "C06_Cruceiro_1", Vector3(1, 4, 1), Vector3(90, 2, 0))
	_part(parts, "C07_Horreo_1", Vector3(3, 3, 8), Vector3(0, 1.5, 14))
	_part(parts, "C08_Farolas_1", Vector3(0.3, 4, 0.3), Vector3(12, 2, 12))
	_part(parts, "C09_Cerre_N", Vector3(80, 2, 0.4), Vector3(0, 1, -40))
	_part(parts, "C09_Cerre_S", Vector3(80, 2, 0.4), Vector3(0, 1, 40))
	_part(parts, "C09_Cerre_E", Vector3(0.4, 2, 80), Vector3(40, 1, 0))
	_part(parts, "C09_Cerre_W", Vector3(0.4, 2, 80), Vector3(-40, 1, 0))
	sm.set_script(load(SM_SCRIPT))
	sm.set("parts_container_path", NodePath("Parts"))
	var data := {"steps": [{"actions": [
		_action("C01_Excavacion", "Excavación", "sink_down", "2027-03-01", 10),
		_action("C02_Zapatas", "Zapatas de hormigón", "fill_up", "2027-03-11", 10),
		_action("C03_Muros", "Muros de mampostería", "build_up", "2027-03-21", 30),
		_action("C04_Cornisa", "Cornisa", "drop_in", "2027-04-20", 10),
		_action("C05_Cubierta", "Cubierta de pizarra", "fade_in", "2027-04-30", 10),
		_action("C06_Cruceiro", "Cruceiro", "drop_in", "2027-04-25", 4),
		_action("C07_Horreo", "Hórreo", "drop_in", "2027-06-01", 5),
		_action("C08_Farolas", "Farolas", "drop_in", "2027-06-10", 3),
		_action("C09_Cerre", "Muro de cerre", "build_up", "2027-06-15", 10),
	]}]}
	sm.set("sequence_data", data)
	return {"main": main, "sm": sm, "data": data}

func _run() -> void:
	_test_models()
	_test_dig_cycle()
	_test_mobile_aim()
	_test_site()
	_test_mobile_routes()
	_test_mobile_boom()
	_test_other_crane_and_opt_out()
	print("\n%s (%d failure(s))" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)

func _test_models() -> void:
	print("=== models: named moving parts, small triangle budgets")
	var tc := EquipmentModels.tower_crane(30, 50, 15)
	var mc := EquipmentModels.mobile_crane()
	var tr := EquipmentModels.truck()
	var ex := EquipmentModels.excavator()
	for n in ["Mast", "Arm", "Arm/Track", "Arm/Track/Rope", "Arm/Track/Hook", "PickupZone"]:
		_check("tower crane has %s" % n, tc.has_node(n), true)
	for n in ["Slew", "Slew/Boom", "Slew/Boom/Section0/Section1/Section2/Section3/Tip", "Hook", "Rope", "Outrigger0", "Outrigger3"]:
		_check("mobile crane has %s" % n, mc.has_node(n), true)
	for n in ["Body", "Body/Load"]:
		_check("truck has %s" % n, tr.has_node(n), true)
	for n in ["Undercarriage", "Upper", "Upper/Boom", "Upper/Boom/Stick", "Upper/Boom/Stick/Bucket",
			"Upper/BoomRamL", "Upper/BoomRamR", "Upper/Boom/StickRam", "Upper/Boom/Stick/BucketRam",
			"Upper/Boom/Stick/PowerLink", "Upper/Boom/Stick/Bucket/Load"]:
		_check("excavator has %s" % n, ex.has_node(n), true)
	for m in [tc, mc, tr, ex]:
		var tris := EquipmentModels.triangle_count(m)
		_check("%s under 3000 triangles (%d)" % [m.name, tris], tris > 200 and tris < 3000, true)
	var box := SiteEquipment.rest_box(tr)
	_check("truck ~9 m long, 2.5 m wide, 3.3 m tall",
		[snappedf(box.size.z, 0.5), snappedf(box.size.x, 0.5), snappedf(box.size.y, 0.5)], [9.0, 2.5, 3.0])
	box = SiteEquipment.rest_box(ex)
	_check("excavator 3 m wide over the tracks", snappedf(box.size.x, 0.1), 3.0)
	_test_excavator_against_spec(ex)
	_check("tower crane: jib reaches 50 m", snappedf(SiteEquipment.rest_box(tc.get_node("Arm")).end.x, 1.0), 51.0)
	EquipmentModels.pose_truck(tr, 1.0, 0.5)
	_check("truck body tips to 50 degrees", snappedf(rad_to_deg((tr.get_node("Body") as Node3D).rotation.x), 0.1), 50.0)
	EquipmentModels.pose_mobile_crane(mc, 0, 0.5, 1.0, 1.0, 5.0)
	var tip := EquipmentModels.boom_tip(mc)
	var foot := EquipmentModels.MOBILE_SLEW + EquipmentModels.MOBILE_FOOT
	_check("mobile boom fully out = BOOM_MAX", snappedf(tip.distance_to(foot), 0.1), snappedf(EquipmentModels.BOOM_MAX, 0.1))
	_check("outriggers out 3.6 m", snappedf(absf((mc.get_node("Outrigger0") as Node3D).position.x), 0.1), 3.6)
	for m in [tc, mc, tr, ex]:
		m.free()
	var crane := EquipmentModels.tower_crane(30, 50, 15, Vector3(0, 0, 9), true)
	root.add_child(crane)
	_check("as_crane: a working Crane", crane is Crane and crane.get("_arm") != null and crane.get("_hook") != null, true)
	_check("its pickup is the laydown", (crane as Crane).get_pickup_position(Vector3(100, 0, 0)), Vector3(0, 0, 9))
	crane.free()

## The excavator against Caterpillar's sheet (equipment/specs/excavator_cat_320.json):
## the dimensions it is built to, and the working range its joint limits give.
func _test_excavator_against_spec(ex: Node3D) -> void:
	print("=== excavator against the Cat 320 sheet")
	var id := EquipmentSpecs.EXCAVATOR
	var spec := EquipmentSpecs.load_spec(id)
	_check("spec loads, with its source", spec.has("source") and String(spec.source.url).begins_with("https://"), true)
	_check("listed among the specs", EquipmentSpecs.ids().has(id), true)
	var mm := func(section: String, key: String) -> float: return EquipmentSpecs.metres(id, section, key)
	var under := SiteEquipment.rest_box(ex.get_node("Undercarriage"))
	_check("track length overall %.2f m" % under.size.z, absf(under.size.z - mm.call("dimensions", "track_length_overall")) < 0.02, true)
	_check("track width %.2f m" % under.size.x, absf(under.size.x - mm.call("dimensions", "track_width_600_shoes")) < 0.05, true)
	var car := SiteEquipment.rest_box(ex.get_node("Undercarriage/CarBody"))
	_check("ground clearance %.2f m" % car.position.y, absf(car.position.y - mm.call("dimensions", "ground_clearance")) < 0.01, true)
	var cw := ex.get_node("Upper/Counterweight") as Node3D
	var cw_box := SiteEquipment.rest_box(cw)
	var cw_world := (ex.get_node("Upper") as Node3D).transform * cw_box
	_check("counterweight clearance %.2f m" % cw_world.position.y,
		absf(cw_world.position.y - mm.call("dimensions", "counterweight_clearance")) < 0.01, true)
	var tail := Vector2(cw_box.end.x, cw_box.end.z).length()
	_check("tail swing radius %.2f m" % tail, absf(tail - mm.call("dimensions", "tail_swing_radius")) < 0.02, true)
	var cab := (ex.get_node("Upper") as Node3D).transform * SiteEquipment.rest_box(ex.get_node("Upper/Cab"))
	_check("cab top %.2f m" % cab.end.y, absf(cab.end.y - mm.call("dimensions", "cab_top_height")) < 0.05, true)
	var upper := SiteEquipment.rest_box(ex.get_node("Upper/House"))
	_check("upperframe width %.2f m" % upper.size.x, absf(upper.size.x - mm.call("dimensions", "upperframe_width_without_walkways")) < 0.01, true)
	var boom := EquipmentModels.EXC_BOOM_TIP.length()
	_check("boom %.2f m pin to pin, stick %.1f m" % [boom, EquipmentModels.EXC_STICK],
		absf(boom - mm.call("front", "boom_length")) < 0.02 and absf(EquipmentModels.EXC_STICK - mm.call("front", "stick_length")) < 0.01, true)
	var tip := Vector2(EquipmentModels.EXC_TEETH_TIP).length()
	_check("bucket tip radius %.2f m, width %.1f m" % [tip, EquipmentModels.EXC_BUCKET_WIDTH],
		absf(tip - mm.call("front", "bucket_tip_radius")) < 0.01 and absf(EquipmentModels.EXC_BUCKET_WIDTH - mm.call("front", "bucket_width")) < 0.01, true)
	var env := EquipmentModels.excavator_envelope()
	for pair in [["reach", "max_reach_at_ground_line"], ["depth", "max_digging_depth"], ["cut", "max_cutting_height"]]:
		var want: float = mm.call("working_ranges", pair[1])
		var got: float = env[pair[0]]
		_check("working range %s %.2f m (Cat: %.2f), within 5 %%" % [pair[0], got, want], absf(got - want) / want < 0.05, true)

func _test_dig_cycle() -> void:
	print("=== excavator: digs below ground, dumps over the truck body")
	var deepest := INF
	for i in 40:
		var p := SiteEquipment.dig_pose(0.14 + i * 0.005)
		deepest = minf(deepest, EquipmentModels.excavator_teeth(0, p.boom, p.stick, p.bucket).y)
	_check("teeth go into the ground", deepest < -0.3, true)
	var d := SiteEquipment.dig_pose(0.74)
	var bucket := EquipmentModels.excavator_bucket_pin(-PI / 2.0 * d.slew, d.boom, d.stick)
	var spot := SiteEquipment.TRUCK_SPOT
	_check("dump: bucket pin over the body (x %.1f)" % bucket.x, bucket.x > spot.x - 1.0 and bucket.x < spot.x + 1.0, true)
	_check("and well above it (y %.1f)" % bucket.y, bucket.y > 4.0, true)
	var ok_limits := true
	for i in 100:
		var p := SiteEquipment.dig_pose(i / 100.0)
		for joint in [[p.boom, EquipmentModels.EXC_BOOM_RANGE], [p.stick, EquipmentModels.EXC_STICK_RANGE],
				[p.bucket, EquipmentModels.EXC_BUCKET_RANGE]]:
			ok_limits = ok_limits and joint[0] >= joint[1].x - 1e-6 and joint[0] <= joint[1].y + 1e-6
	_check("the cycle stays inside the joint limits", ok_limits, true)
	_check("loaded from the drag to the dump", [SiteEquipment.dig_pose(0.1).loaded, SiteEquipment.dig_pose(0.5).loaded, SiteEquipment.dig_pose(0.8).loaded], [false, true, false])
	var a := SiteEquipment.dig_pose(0.0)
	var z := SiteEquipment.dig_pose(0.9999)
	_check("a full cycle comes back to its start", [a.slew, a.boom, a.stick, a.bucket].map(func(v): return snappedf(v, 0.001)),
		[z.slew, z.boom, z.stick, z.bucket].map(func(v): return snappedf(v, 0.001)))

func _test_mobile_aim() -> void:
	print("=== mobile crane: boom tip over the piece")
	var mc := EquipmentModels.mobile_crane()
	root.add_child(mc)
	var target := Vector3(8, 6, -20)
	var a := SiteEquipment.aim_mobile(mc.global_transform, target)
	EquipmentModels.pose_mobile_crane(mc, a.slew, a.luff, a.extend, 1.0, 3.0)
	var tip := EquipmentModels.boom_tip(mc)
	_check("tip 6 m above the target", snappedf(tip.y - target.y, 0.1), 6.0)
	_check("tip over it (within 2 m)", Vector2(tip.x, tip.z).distance_to(Vector2(target.x, target.z)) < 2.0, true)
	a = SiteEquipment.aim_mobile(mc.global_transform, Vector3(0, 0, -80))
	_check("out of range: fully extended, not past it", snappedf(a.extend, 0.01), 1.0)
	mc.free()

func _test_site() -> void:
	print("=== placement and the schedule")
	var s := _scene()
	var sm: Node3D = s.sm
	sm.initialize_parts()
	var eq := SiteEquipment.ensure(sm, true)
	_check("created automatically", eq != null and eq.get_parent() == sm, true)
	var cranes: Dictionary = sm._resolve_cranes()
	_check("the tower crane is the scene's crane", cranes.keys(), [&"TowerCrane"])
	var crane: Crane = cranes.get(&"TowerCrane")
	var site: Vector3 = eq.get_node(SiteEquipment.TOWER_SITE).global_position
	var building := AABB(Vector3(-10.25, -1, -5.6), Vector3(20.5, 10.75, 11.2))
	_check("mast clear of the building", building.grow(2.0).has_point(Vector3(site.x, 0, site.z)), false)
	_check("mast close to it, not out by the boundary wall (%.1f m)" % Vector2(site.x, site.z).length(),
		Vector2(site.x, site.z).length() < 25.0, true)
	var jib: float = eq._tower_jib
	var far := 0.0
	for x in [-10.0, 10.0]:
		for z in [-5.0, 5.0]:
			far = maxf(far, Vector2(x, z).distance_to(Vector2(site.x, site.z)))
	_check("jib covers every corner (%.0f m for %.1f m)" % [jib, far], jib >= far and jib <= 75.0, true)
	var arm_y: float = (crane.get_node("Arm") as Node3D).global_position.y
	_check("jib 10 m over the top (%.1f)" % arm_y, arm_y >= 9.75 + 9.5, true)
	_check("equipment is not a part", sm.building_parts.keys().filter(func(k): return not String(k).begins_with("C0")).is_empty(), true)
	var exc_site: Vector3 = eq.get_node(SiteEquipment.EXCAVATOR_SITE).global_position
	_check("excavator just off the dig's edge", snappedf(exc_site.z, 0.1), 10.0)

	var schedule := ConstructionSchedule.new(s.data, sm.building_parts, SpatialGrouper.new(), cranes)
	var ctl := TimelineController.new()
	sm.add_child(ctl)
	ctl.set_schedule(schedule, sm.building_parts, cranes)
	var plan: Dictionary = eq._plan
	_check("tower crane: up before the footings, down after the roof", [plan.tower.on, plan.tower.off], [10.0 - eq.erect_days, 70.0 + eq.erect_days])
	var tower_names: Array = plan.tower.parts.map(func(t): return String(t.name))
	_check("tower crane lowers the cornice", tower_names.filter(func(n): return n.begins_with("C04_")).size(), 8)
	_check("...and nothing else", tower_names.size(), 8)
	var jobs: Array = plan.mobile.map(func(j): return String(j.parts[0].name))
	_check("mobile crane: the cross (out of reach) and the granary (after the roof)", jobs, ["C06_Cruceiro_1", "C07_Horreo_1"])
	_check("street lights need no crane", jobs.has("C08_Farolas_1") or tower_names.has("C08_Farolas_1"), false)
	for j in plan.mobile:
		var standing: Array = []
		for n in sm.building_parts:
			var w := schedule.get_part_window(n)
			if w.is_empty() or w.end_day <= j.start:
				standing.append(SiteEquipment.rest_box(sm.building_parts[n]))
		_check("mobile crane for %s set up clear of what is built" % j.parts[0].name,
			SiteEquipment._blocked(standing, Vector2(j.pos.x, j.pos.z), 4.9, 0.0), false)
	_check("one dig window", plan.digs.map(func(d): return [d.start, d.finish, d.fill]), [[0.0, 10.0, false]])

	var tower: Node3D = eq._tower
	var mast: Node3D = tower.get_node("Mast")
	ctl.scrub_to(2.0)
	_check("day 2: excavator and truck at work, no crane yet", [eq._excavator.visible, eq._truck.visible, tower.visible], [true, true, false])
	ctl.scrub_to(8.0)
	var shown := mast.get_children().filter(func(c): return c.visible).size()
	_check("day 8: mast half up, no jib yet", [shown > 0 and shown < mast.get_child_count(), (tower.get_node("Arm") as Node3D).visible], [true, false])
	ctl.scrub_to(30.0)
	_check("day 30: crane complete, dig over", [tower.visible, (tower.get_node("Arm") as Node3D).visible, eq._excavator.visible], [true, true, false])
	var first: Dictionary = plan.tower.parts[0]
	ctl.scrub_to((first.start + first.end) * 0.5)
	_check("lowering a cornice stone: the crane follows it", String(crane.get("_tracked_part").name), String(first.name))
	ctl.scrub_to(57.0)
	_check("cross being placed: mobile crane there", eq._mobile.visible, true)
	var to_cross := Vector2(eq._mobile.global_position.x, eq._mobile.global_position.z).distance_to(Vector2(90, 0))
	_check("set up beside it (%.1f m), not on it" % to_cross, to_cross > 5.0 and to_cross < 15.0, true)
	ctl.scrub_to(80.0)
	_check("day 80: crane gone, no mobile job", [tower.visible, eq._mobile.visible], [false, false])
	ctl.scrub_to(94.0)
	_check("granary: mobile crane back", eq._mobile.visible, true)

	print("=== the mobile crane drives in and out")
	var drives: Array = plan.drives
	_check("in and out for each of the two jobs (they are %.0f days apart)" % (plan.mobile[1].start - plan.mobile[0].finish), drives.size(), 4)
	var d_in: Dictionary = drives[0]
	var cross: Dictionary = plan.mobile[0]
	_check("the cross: a free road from outside", [d_in.ok, d_in.direct], [true, true])
	_check("...ending at its spot", d_in.points[d_in.points.size() - 1].is_equal_approx(Vector2(cross.pos.x, cross.pos.z)), true)
	ctl.scrub_to(d_in.t0 - 0.05)
	_check("before the drive: not on site", eq._mobile.visible, false)
	ctl.scrub_to((d_in.t0 + d_in.t1) * 0.5)
	var mid: Vector2 = Vector2(eq._mobile.global_position.x, eq._mobile.global_position.z)
	_check("mid-drive: on the road, short of its spot", [eq._mobile.visible, mid.distance_to(Vector2(cross.pos.x, cross.pos.z)) > 5.0], [true, true])
	var fwd := -eq._mobile.global_transform.basis.z
	var along: Vector2 = (d_in.points[d_in.points.size() - 1] - d_in.points[0]).normalized()
	_check("...pointing along it", absf(Vector2(fwd.x, fwd.z).dot(along)) > 0.95, true)
	_check("...boom stowed, outriggers in", eq._mobile_pose.out, 0.0)
	var d_out: Dictionary = drives[1]
	ctl.scrub_to(d_out.t1 + 0.01)
	_check("after the drive out: gone", eq._mobile.visible, false)
	_check("the granary: the boundary wall is not built yet, so the road in is open", [drives[2].ok, drives[2].direct], [true, true])

	print("=== truck round")
	eq._dig = plan.digs[0]
	eq._anim_time = 0.0
	eq._animate_dig()
	_check("arriving from 40 m out", snappedf(eq._truck.position.z - SiteEquipment.TRUCK_SPOT.z, 1.0), SiteEquipment.TRUCK_RUN)
	eq._anim_time = SiteEquipment.DIG_CYCLE * 2.9
	eq._animate_dig()
	_check("two loads in after two dumps", [eq._truck.position.is_equal_approx(SiteEquipment.TRUCK_SPOT), snappedf((eq._truck.get_node("Body/Load") as Node3D).scale.y / 1.5, 0.01)], [true, 0.5])
	eq._anim_time = SiteEquipment.DIG_CYCLE * 5.9
	eq._animate_dig()
	_check("gone after the fourth", eq._truck.visible, false)

	SiteEquipment.reset_all(self)
	_check("reset: the finished site", [tower.visible, (tower.get_node("Arm") as Node3D).visible, eq._excavator.visible], [true, true, true])
	s.main.free()
	current_scene = null

## The mobile crane's life between jobs, on made-up jobs: does it need to move,
## and if so, how.
func _test_mobile_routes() -> void:
	print("=== mobile crane: move only when needed, round what is built")
	var s := _scene()
	var sm: Node3D = s.sm
	sm.initialize_parts()
	var eq := SiteEquipment.ensure(sm, true)
	eq._ground_level = 0.0
	eq.hold_days = 30.0
	var house := AABB(Vector3(-10, 0, -5), Vector3(20, 9, 10))
	var standing := [{"box": house, "from": -INF, "begin": -INF}]
	var mast := Vector2(1000, 1000)
	var work := Vector2.ZERO
	var west := _job(-30.0, 0.0, 10.0, 12.0, Vector3(-36, 0, 0))
	var near_west := _job(-30.0, 0.0, 20.0, 22.0, Vector3(-40, 0, 3)) # 10 m from the same spot
	var east := _job(30.0, 0.0, 20.0, 22.0, Vector3(36, 0, 0))
	var late_east := _job(30.0, 0.0, 200.0, 202.0, Vector3(36, 0, 0))

	var plan: Dictionary = eq._plan_mobile([west, near_west], standing, work, {}, mast)
	_check("a second lift within reach: one spot, no drive between", plan.stands.size(), 1)
	_check("...which serves both pieces for the whole time", [plan.stands[0].parts.size(), plan.stands[0].start, plan.stands[0].finish], [2, 10.0, 22.0])
	_check("...so only the way in and the way out", plan.drives.size(), 2)

	plan = eq._plan_mobile([west, east], standing, work, {}, mast)
	_check("a lift out of reach: a second spot", plan.stands.size(), 2)
	var kinds: Array = plan.segments.map(func(g): return g.kind)
	_check("in, work, wait, drive, work, out", kinds, ["drive", "stand", "park", "drive", "stand", "drive"])
	var between: Dictionary = plan.segments[3]
	_check("the house is in the way: not the straight line", [between.ok, between.direct], [true, false])
	_check("...a way round: %.0f m for 60 m as the crow flies" % between.length, between.length > 62.0 and between.length < 90.0, true)
	var rects := [Rect2(house.position.x, house.position.z, house.size.x, house.size.z)]
	_check("...that the carrier itself clears", RoutePlanner._clear(between.points, rects, EquipmentModels.MOBILE_LENGTH, EquipmentModels.MOBILE_WIDTH * 0.5), true)
	_check("...driven between its two jobs", [between.t0 >= west.finish + 0.75, between.t1 == east.start - 0.75], [true, true])
	var tiles := true
	for i in range(1, plan.segments.size()):
		tiles = tiles and plan.segments[i].t0 >= plan.segments[i - 1].t1 - 0.001
	_check("segments follow one another without overlap", tiles, true)

	plan = eq._plan_mobile([west, late_east], standing, work, {}, mast)
	kinds = plan.segments.map(func(g): return g.kind)
	_check("jobs months apart: it leaves and comes back", kinds, ["drive", "stand", "drive", "drive", "stand", "drive"])

	var tower := {"on": 0.0, "off": 100.0}
	var mast_at := Vector2(0, 12) # the tower crane stands on the straight line round the house
	var east2 := _job(30.0, 12.0, 20.0, 22.0, Vector3(36, 0, 12))
	var west2 := _job(-30.0, 12.0, 10.0, 12.0, Vector3(-36, 0, 12))
	var open: Dictionary = eq._plan_mobile([west2, east2], [], work, {}, mast_at)
	var blocked: Dictionary = eq._plan_mobile([west2, east2], [], work, tower, mast_at)
	_check("nothing built: straight on", open.segments[3].direct, true)
	_check("a tower crane's mast in the way: round it", [blocked.segments[3].ok, blocked.segments[3].direct], [true, false])
	s.main.free()
	current_scene = null

func _job(x: float, z: float, start: float, finish: float, piece: Vector3) -> Dictionary:
	var box := AABB(piece - Vector3(1, 0, 1), Vector3(2, 2, 2))
	return {"start": start, "finish": finish, "pos": Vector3(x, 0, z), "yaw": 0.0,
		"parts": [{"name": "P%d" % int(start), "start": start, "end": finish, "kind": "drop_in", "box": box}],
		"aim": Vector3(piece.x, 2, piece.z)}


## The boom clears what is built: another spot if there is one, else a higher tip.
func _test_mobile_boom() -> void:
	print("=== mobile crane: the boom clears what is built")
	var s := _scene()
	var sm: Node3D = s.sm
	sm.initialize_parts()
	var eq := SiteEquipment.ensure(sm, true)
	eq._ground_level = 0.0
	var work := Vector2.ZERO
	var piece := Vector3(30, 0, 0)
	var entry := {"name": "P", "start": 10.0, "end": 12.0, "kind": "drop_in", "box": AABB(piece - Vector3(1, 0, 1), Vector3(2, 2, 2))}

	var job: Dictionary = eq._mobile_job_for([entry], work, [])
	_check("open site: the boom clears at its usual height", [job.boom_ok, job.tip_up], [true, 0.0])
	var usual: Vector3 = job.pos

	# A 12 m wall right behind the usual spot, across the boom's line.
	var wall := AABB(Vector3(33, 0, -10), Vector3(1, 12, 20))
	var standing := [{"box": wall, "from": -INF, "begin": -INF}]
	job = eq._mobile_job_for([entry], work, standing)
	_check("a wall across the boom: it stands elsewhere, boom still at its usual height", [job.boom_ok, job.tip_up, job.pos.is_equal_approx(usual)], [true, 0.0, false])
	var tf := Transform3D(Basis(Vector3.UP, job.yaw), job.pos)
	_check("...and the boom really clears (checked again from there)", eq._boom_lift(tf, [entry], eq._boom_obstacles(standing, entry.box, 12.0)), 0.0)
	var straight := eq._boom_lift(Transform3D(Basis(Vector3.UP, 0.0), usual), [entry], eq._boom_obstacles(standing, entry.box, 12.0))
	_check("...which it did not from the usual one (%s)" % str(straight), straight > 0.0, true)

	# The same wall, but cleared away (fade_out) before the lift: not in the way.
	var cleared := [{"box": wall, "from": -INF, "begin": 0.0, "gone": 5.0}]
	job = eq._mobile_job_for([entry], work, cleared)
	_check("a wall taken down before the lift is not there: the usual spot", [job.pos.is_equal_approx(usual), job.tip_up], [true, 0.0])
	cleared[0]["gone"] = 11.0
	job = eq._mobile_job_for([entry], work, cleared)
	_check("...but still up when the piece goes in: it is", job.pos.is_equal_approx(usual), false)

	# The piece in a well: four 14 m walls 3 m round it. Every spot has the boom
	# over a wall, so the tip goes higher instead.
	var well: Array = []
	for b in [AABB(Vector3(26, 0, -4), Vector3(1, 14, 8)), AABB(Vector3(33, 0, -4), Vector3(1, 14, 8)),
			AABB(Vector3(26, 0, -4), Vector3(8, 14, 1)), AABB(Vector3(26, 0, 3), Vector3(8, 14, 1))]:
		well.append({"box": b, "from": -INF, "begin": -INF})
	job = eq._mobile_job_for([entry], work, well)
	_check("a well: the boom is held higher (%.0f m)" % job.tip_up, [job.boom_ok, job.tip_up > 0.0], [true, true])
	tf = Transform3D(Basis(Vector3.UP, job.yaw), job.pos)
	_check("...and clears (checked again)", eq._boom_lift(tf, [entry], eq._boom_obstacles(well, entry.box, 12.0)) <= job.tip_up, true)
	var tall: Array = well.duplicate()
	for b in well:
		var raised: AABB = (b.box as AABB)
		tall.append({"box": AABB(raised.position, Vector3(raised.size.x, 80.0, raised.size.z)), "from": -INF, "begin": -INF})
	job = eq._mobile_job_for([entry], work, tall)
	_check("walls no boom can clear: reported, the crane still stands somewhere", [job.boom_ok, job.pos != Vector3.ZERO], [false, true])

	# A piece only reachable over a wall too high to clear: not the same stand.
	var west := _job(-30.0, 0.0, 10.0, 12.0, Vector3(-36, 0, 0))
	var behind := _job(-30.0, 0.0, 20.0, 22.0, Vector3(-40, 0, 3))
	var high := [{"box": AABB(Vector3(-37, 0, -20), Vector3(1, 60, 40)), "from": -INF, "begin": -INF}]
	var plan: Dictionary = eq._plan_mobile([west, behind], [{"box": high[0].box, "from": -INF, "begin": 12.0}], work, {}, Vector2(1000, 1000))
	_check("within reach but behind a 60 m wall: not one stand", plan.stands.size(), 2)
	plan = eq._plan_mobile([west, behind], [], work, {}, Vector2(1000, 1000))
	_check("without the wall: one stand", plan.stands.size(), 1)
	s.main.free()
	current_scene = null


func _test_other_crane_and_opt_out() -> void:
	print("=== a scene's own crane, and opting out")
	var s := _scene()
	var sm: Node3D = s.sm
	sm.initialize_parts()
	var own := Crane.new()
	own.name = "MyCrane"
	s.main.add_child(own)
	var eq := SiteEquipment.ensure(sm, true)
	_check("no tower crane next to the user's own", eq._tower, null)
	_check("the other machines still come", eq._excavator != null and eq._mobile != null, true)
	s.main.free()
	s = _scene()
	(s.sm as Node3D).set("auto_equipment", false)
	_check("auto_equipment off and none in the scene: nothing", SiteEquipment.ensure(s.sm, false), null)
	s.main.free()
	current_scene = null
