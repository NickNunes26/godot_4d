## Headless test for LiftPlanner: the default lift when it is free, and the
## shortest path round what is built when it is not.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_lift_planner.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# A 2 m cube whose place is x 9..11 in the world; offsets are from its place.
	var world := Vector3(10, 0, 0) # the middle of its footprint
	var seat := AABB(world + Vector3(-1, 0, -1), Vector3(2, 2, 2))
	var d0 := Vector3(15, 0, 0) # picked up 15 m to the side, on the ground

	print("=== free: the default lift, untouched")
	var r := LiftPlanner.find(d0, seat, [])
	_check("nothing built: the default path", [r.ok, r.direct, r.mode], [true, true, "default"])
	_check("up 5, across, down", r.offsets, PackedVector3Array([d0, Vector3(15, 5, 0), Vector3(0, 5, 0), Vector3.ZERO]))
	var low := AABB(world + Vector3(7, 0, -3), Vector3(1, 3, 6)) # 3 m tall wall between: under the hover
	r = LiftPlanner.find(d0, seat, [low])
	_check("a 3 m wall is under the 5 m hover: still the default", r.direct, true)

	print("=== a wall taller than the hover")
	var wall := AABB(world + Vector3(7, 0, -10), Vector3(1, 12, 20)) # 12 m tall, 20 m long
	r = LiftPlanner.find(d0, seat, [wall])
	_check("found a path", [r.ok, r.direct], [true, false])
	_check("lifted over it (the piece's bottom clears 12 m)", r.offsets[1].y > 12.0, true)
	_check("...and no higher than it needs (%.2f)" % r.offsets[1].y, r.offsets[1].y < 12.5, true)
	_check("lowered straight down onto its place", [r.offsets[r.offsets.size() - 1], r.offsets[r.offsets.size() - 2].x, r.offsets[r.offsets.size() - 2].z], [Vector3.ZERO, 0.0, 0.0])
	_check("no path point is inside the wall (grown by the piece)", _clear(r.offsets, d0, seat, [wall]), true)

	print("=== a short wall in the way is gone round, not over")
	var post := AABB(world + Vector3(7, 0, -0.25), Vector3(0.5, 10, 0.5))
	r = LiftPlanner.find(d0, seat, [post])
	_check("a 10 m post: round it at the hover height is shorter than over it", r.mode, "side")
	_check("...and clear", _clear(r.offsets, d0, seat, [post]), true)

	print("=== the way down is shut from above: in from the side")
	var slab := AABB(world + Vector3(-5, 4, -5), Vector3(10, 1, 10)) # a floor 2 m over its place
	r = LiftPlanner.find(d0, seat, [slab])
	_check("brought in sideways", [r.ok, r.mode], [true, "side"])
	_check("...from the laydown's side (+X) as the shortest", r.offsets[r.offsets.size() - 2].x > 0.0, true)
	_check("...level with its place", r.offsets[r.offsets.size() - 2].y, 0.0)
	_check("clear", _clear(r.offsets, d0, seat, [slab]), true)

	print("=== it touches its bearing: that is not in the way")
	var bearing := AABB(world + Vector3(-3, -1, -3), Vector3(6, 1, 6)) # right under it
	r = LiftPlanner.find(d0, seat, [bearing])
	_check("lands on the bearing without any change", r.direct, true)
	var next := AABB(world + Vector3(1, 0, -1), Vector3(2, 2, 2)) # shares its end face
	r = LiftPlanner.find(d0, seat, [next])
	_check("...and against the segment beside it", r.direct, true)

	print("=== shut in")
	var room: Array = [
		AABB(world + Vector3(-6, 4, -6), Vector3(12, 1, 12)),
		AABB(world + Vector3(-6, 0, -6), Vector3(1, 5, 12)), AABB(world + Vector3(5, 0, -6), Vector3(1, 5, 12)),
		AABB(world + Vector3(-6, 0, -6), Vector3(12, 5, 1)), AABB(world + Vector3(-6, 0, 5), Vector3(12, 5, 1)),
	]
	r = LiftPlanner.find(d0, seat, room, {"y_max": 30.0})
	_check("walls on four sides and a floor over: no path, the default comes back", [r.ok, r.mode, r.offsets.size()], [false, "blocked", 4])

	print("=== a crane's limits")
	r = LiftPlanner.find(d0, seat, [wall], {"y_max": 8.0})
	_check("the jib is lower than the wall: no way over it", r.ok, false)
	var tall := LiftPlanner.find(d0, seat, [wall], {"y_max": 20.0, "mast_d": Vector3(30, 0, 0), "r_max": 40.0, "r_min": 3.0})
	_check("under the jib and within its reach: found", tall.ok, true)
	var near := LiftPlanner.find(d0, seat, [slab], {"mast_d": Vector3(30, 0, 0), "r_max": 32.0, "r_min": 3.0})
	_check("a side approach stays within the hook's reach", near.ok and Vector2(near.offsets[near.offsets.size() - 2].x - 30.0, near.offsets[near.offsets.size() - 2].z).length() <= 32.0, true)

	print("=== sampling")
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 10, 0), Vector3(10, 10, 0)])
	_check("start, end", [LiftPlanner.sample(pts, 0.0), LiftPlanner.sample(pts, 1.0)], [Vector3(0, 0, 0), Vector3(10, 10, 0)])
	_check("halfway is the corner (equal legs)", LiftPlanner.sample(pts, 0.5).is_equal_approx(Vector3(0, 10, 0)), true)
	var last := Vector3.ZERO
	var monotone := true
	for i in 101:
		var p := LiftPlanner.sample(pts, i / 100.0)
		monotone = monotone and (p.y >= last.y - 0.001 or p.x > 0.0)
		last = p
	_check("moves forward only", monotone, true)

	print("\nFAILS: %d" % _fails)
	quit(1 if _fails > 0 else 0)

## Whether the piece, at every point of the path and along every segment (sampled),
## stays out of the obstacles.
func _clear(points: PackedVector3Array, d0: Vector3, seat: AABB, obstacles: Array) -> bool:
	# `seat` at offset d overlaps an obstacle: the piece's box is seat translated by d.
	for i in range(1, points.size()):
		for k in range(0, 41):
			var d := points[i - 1].lerp(points[i], k / 40.0)
			var box := AABB(seat.position + d, seat.size)
			for o in obstacles:
				var ob: AABB = o
				# What it touches at its place or at its pickup is not in its way.
				if ob.intersects(seat.grow(0.2)) or ob.intersects(AABB(seat.position + d0, seat.size).grow(0.2)):
					continue
				if ob.grow(-0.01).intersects(box):
					return false
	return true
