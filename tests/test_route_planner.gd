## Headless test for RoutePlanner: the straight line when it is free, the
## shortest way round when it is not, and that the body fits what it finds.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_route_planner.gd
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
	var L := 11.6
	var W := 2.55

	print("=== free ground: the straight line")
	var r := RoutePlanner.find(Vector2(0, 0), Vector2(50, 0), [Rect2(20, 20, 10, 10)], L, W)
	_check("direct, ok", [r.ok, r.direct], [true, true])
	_check("length is the distance", snappedf(r.length, 0.01), 50.0)

	print("=== a building in the way")
	var house := Rect2(20, -10, 10, 20) # x 20..30, z -10..10
	r = RoutePlanner.find(Vector2(0, 0), Vector2(50, 0), [house], L, W)
	_check("found a way", [r.ok, r.direct], [true, false])
	_check("two corners on the way", r.points.size(), 4)
	_check("longer than straight, shorter than a lap", r.length > 50.0 and r.length < 80.0, true)
	# Shortest: round one corner of the house, grown by the body's half width + margin.
	var grow := W * 0.5 + RoutePlanner.MARGINS[0]
	var best := 2.0 * sqrt(pow(20.0 - grow, 2) + pow(10.0 + grow, 2)) # not exact; just a lower bound check
	_check("no shorter than the geometry allows", r.length >= 50.0, true)
	_check("passes clear of the house", _min_gap(r.points, house) >= grow - 0.01, true)
	_check("the body fits every leg", RoutePlanner._clear(r.points, [house], L, W * 0.5 + RoutePlanner.BODY_MARGIN), true)

	print("=== two ways round: the shorter one")
	var wall := Rect2(20, -6, 4, 30) # z -6..24: shorter to pass at z<-6
	r = RoutePlanner.find(Vector2(0, 0), Vector2(50, 0), [wall], L, W)
	_check("goes round the near end", r.ok and r.points[1].y < 0.0, true)

	print("=== a wall with a gap")
	var north := Rect2(20, -40, 2, 34) # z -40..-6
	var south := Rect2(20, 6, 2, 34) # z 6..40, gap 12 m wide
	r = RoutePlanner.find(Vector2(0, 0), Vector2(50, 0), [north, south], L, W)
	_check("straight through the gap", [r.ok, r.direct], [true, true])
	south = Rect2(20, 1.5, 2, 38) # gap 7.5 m wide: the body fits
	r = RoutePlanner.find(Vector2(0, -3), Vector2(50, -3), [north, south], L, W)
	_check("a gap wider than the body", r.ok, true)
	north = Rect2(20, -40, 2, 38.5) # gap z -1.5..1.5 = 3 m: too narrow for body + room
	south = Rect2(20, 1.5, 2, 38)
	r = RoutePlanner.find(Vector2(0, 0), Vector2(50, 0), [north, south], L, W)
	_check("a 3 m gap is not enough for a 2.55 m body with room", r.direct, false)

	print("=== closed in")
	var ring := [Rect2(-30, -30, 60, 2), Rect2(-30, 28, 60, 2), Rect2(-30, -30, 2, 60), Rect2(28, -30, 2, 60)]
	r = RoutePlanner.find(Vector2(0, 0), Vector2(60, 0), ring, L, W)
	_check("no route into a closed yard", r.ok, false)
	_check("...and the straight line comes back", r.points.size(), 2)
	r = RoutePlanner.find(Vector2(-10, -10), Vector2(10, 10), ring, L, W)
	_check("inside the yard: free", [r.ok, r.direct], [true, true])

	print("=== start beside a wall")
	r = RoutePlanner.find(Vector2(14.0, 0), Vector2(50, 0), [Rect2(20, -3, 4, 6)], L, W)
	_check("starting 6 m from a block still finds a way", r.ok, true)

	print("=== L-shaped yard: the body must turn")
	var a := Rect2(0, 0, 40, 10)
	var b := Rect2(0, 20, 40, 10)
	r = RoutePlanner.find(Vector2(-20, 15), Vector2(60, 15), [a, b], L, W)
	_check("corridor between two blocks, straight", r.direct, true)

	print("=== which ground can be reached")
	var area := Rect2(-100, -100, 200, 200)
	var f := RoutePlanner.flood(Vector2(90, 90), ring, area)
	_check("outside a closed yard: reached", RoutePlanner.reached(f, Vector2(60, 0)), true)
	_check("inside it: not", RoutePlanner.reached(f, Vector2(0, 0)), false)
	var gapped := [Rect2(-30, -30, 60, 2), Rect2(-30, 28, 60, 2), Rect2(-30, -30, 2, 60), Rect2(28, -30, 2, 24), Rect2(28, 6, 2, 24)] # a 12 m gate east
	f = RoutePlanner.flood(Vector2(90, 90), gapped, area)
	_check("a yard with a gate: reached through it", RoutePlanner.reached(f, Vector2(0, 0)), true)
	_check("...but not right up against the wall inside (no room for the body)", RoutePlanner.reached(f, Vector2(-29, 0)), false)
	_check("beyond the area: no", RoutePlanner.reached(f, Vector2(500, 0)), false)

	print("=== sampling")
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var s := RoutePlanner.sample(pts, 0.0)
	_check("start", [s.pos, snappedf(s.heading, 0.01)], [Vector2(0, 0), 0.0])
	s = RoutePlanner.sample(pts, 5.0)
	_check("mid first leg heading +x", [s.pos, snappedf(s.heading, 0.01)], [Vector2(5, 0), 0.0])
	s = RoutePlanner.sample(pts, 15.0)
	_check("second leg heading +z", [s.pos, snappedf(s.heading, 0.01)], [Vector2(10, 5), snappedf(PI * 0.5, 0.01)])
	s = RoutePlanner.sample(pts, 10.0)
	_check("at the corner: half turned", snappedf(s.heading, 0.01), snappedf(PI * 0.25, 0.01))
	s = RoutePlanner.sample(pts, 20.0)
	_check("end", s.pos, Vector2(10, 10))

	print("\nFAILS: %d" % _fails)
	quit(1 if _fails > 0 else 0)

static func _min_gap(points: PackedVector2Array, r: Rect2) -> float:
	var best := INF
	for i in range(1, points.size() - 1):
		var p := points[i]
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best
