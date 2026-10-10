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
