## The path a crane takes a piece along from its laydown to its place, round
## what is already built.
##
## The `install` animation lifts a piece 5 m, carries it across at that height
## and lowers it. Where something stands in the way -- a wall already up that
## is taller than the hover, a floor over the place the piece belongs -- that
## path goes through it. `find()` keeps the default when it is free, and
## otherwise looks for the shortest path that is: lifted high enough to clear
## what is in the way and lowered straight down, or, when the way down is shut
## from above, brought in sideways at the level of its place.
##
## Geometry is axis-aligned boxes. The moving piece is one box (its unit's,
## the finished placement) and every obstacle is one box, so the piece's
## centre can be treated as a point among obstacles grown by the piece's own
## size (the Minkowski sum): a segment of the path is free exactly when it
## misses every grown box. Paths are in offsets from the piece's place, in
## world axes: (0, 0, 0) is where it ends up, the first point is where it starts.
##
## Pure functions, no scene access: ConstructionSchedule feeds it the boxes
## standing on the day of the lift (docs/13_SITE_EQUIPMENT.md, "Lifts that
## clear what is built").
class_name LiftPlanner
extends RefCounted

## Room kept round the piece, in metres.
const MARGIN := 0.15
## The default lift's height above the place, in metres (what `install` does).
const HOVER := 5.0
## Directions tried for a sideways approach, and distances along them.
const SIDES := 8
const REACH_STEPS := [2.0, 3.0, 4.5, 6.0, 8.0, 12.0, 16.0, 24.0]
## Obstacles further than this from the move, in plan, are ignored.
const REGION := 40.0
const _EPS := 0.001


## The path of a piece whose box (at its place) is `box`, from `d0` (its pickup,
## as an offset from the place) to its place, among `obstacles` (world AABBs).
## `limits` (all optional): `mast_d` (Vector3, the crane's mast in the same
## offsets), `r_min`, `r_max` (hook radius from it), `y_max` (highest the piece's
## origin may go, as an offset).
## Returns {ok, direct, offsets: PackedVector3Array, length, mode}:
## `direct` is true when the default path was free (nothing to change),
## `ok` false when no path exists (the default is returned).
static func find(d0: Vector3, box: AABB, obstacles: Array, limits := {}) -> Dictionary:
	var h0 := maxf(HOVER, d0.y)
	var default_path := PackedVector3Array([d0, Vector3(d0.x, h0, d0.z), Vector3(0, h0, 0), Vector3.ZERO])
	var blockers := _blockers(d0, box, obstacles)
	if _free(default_path, blockers, {}):
		return {"ok": true, "direct": true, "offsets": default_path, "length": path_length(default_path), "mode": "default"}

	# Heights that clear something, lowest first: just over the top of each
	# obstacle the move passes (grown by the piece's size).
	var heights: Array = [h0]
	var y_max: float = limits.get("y_max", INF)
	for b in blockers:
		var top: float = b.end.y + _EPS
		if top > h0 and top <= y_max:
			heights.append(top)
	heights.sort()
	var unique: Array = []
	for h in heights:
		if unique.is_empty() or h - unique[unique.size() - 1] > 0.1:
			unique.append(h)

	var candidates: Array = []
	for h in unique:
		var up := PackedVector3Array([d0, Vector3(d0.x, h, d0.z), Vector3(0, h, 0), Vector3.ZERO])
		candidates.append([path_length(up), up, "raised"])
		for k in SIDES:
			var dir := Vector3(cos(TAU * k / SIDES), 0, sin(TAU * k / SIDES))
			for s in REACH_STEPS:
				var q: Vector3 = dir * s
				var side := PackedVector3Array([d0, Vector3(d0.x, h, d0.z), Vector3(q.x, h, q.z), q, Vector3.ZERO])
				candidates.append([path_length(side), side, "side"])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for c in candidates:
		if _free(c[1], blockers, limits):
			return {"ok": true, "direct": false, "offsets": c[1], "length": c[0], "mode": c[2]}
	return {"ok": false, "direct": false, "offsets": default_path, "length": path_length(default_path), "mode": "blocked"}


static func path_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## Where the piece is at `progress` (0--1) along `points`: its speed eases in
## and out over the whole path, like the default lift's sine easing.
static func sample(points: PackedVector3Array, progress: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if progress <= 0.0 or n == 1:
		return points[0]
	if progress >= 1.0:
		return points[n - 1]
	var total := path_length(points)
	var s: float = total * Tween.interpolate_value(0.0, 1.0, progress, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	for i in range(1, n):
		var leg := points[i].distance_to(points[i - 1])
		if s <= leg or i == n - 1:
			return points[i - 1].lerp(points[i], 0.0 if leg <= 0.0 else clampf(s / leg, 0.0, 1.0))
		s -= leg
	return points[n - 1]


## The world box of a part where it rests in the finished building (from the
## metas SequenceManager keeps while a timeline moves it); an empty AABB when
## the part has no geometry.
static func rest_box(part: Node3D) -> AABB:
	if not part.has_meta("original_aabb") or not part.has_meta("original_transform"):
		return AABB()
	var local: AABB = part.get_meta("original_aabb")
	var xf: Transform3D = part.get_meta("original_transform")
	var box := AABB(xf * local.position, Vector3.ZERO)
	for i in 8:
		box = box.expand(xf * (local.position + Vector3(local.size.x * (i & 1), local.size.y * ((i >> 1) & 1), local.size.z * ((i >> 2) & 1))))
	return box


## Obstacles in offset space: each grown by the piece's size and the margin,
## those too far from the move left out.
static func _blockers(d0: Vector3, box: AABB, obstacles: Array) -> Array:
	var lo := Vector2(minf(d0.x, 0.0), minf(d0.z, 0.0)) - Vector2.ONE * REGION
	var hi := Vector2(maxf(d0.x, 0.0), maxf(d0.z, 0.0)) + Vector2.ONE * REGION
	# What the piece touches at its place (it is meant to sit on and against
	# those) or at its pickup (it starts there) is not in its way.
	var seat := box.grow(MARGIN + 0.02)
	var start := AABB(box.position + d0, box.size).grow(MARGIN + 0.02)
	var out: Array = []
	for o in obstacles:
		var b: AABB = o
		if b.intersects(seat) or b.intersects(start):
			continue
		var grown_pos := b.position - box.end - Vector3.ONE * MARGIN
		var grown_end := b.end - box.position + Vector3.ONE * MARGIN
		if grown_end.x < lo.x or grown_pos.x > hi.x or grown_end.z < lo.y or grown_pos.z > hi.y:
			continue
		out.append(AABB(grown_pos, grown_end - grown_pos))
	return out


static func _free(points: PackedVector3Array, blockers: Array, limits: Dictionary) -> bool:
	if not limits.is_empty():
		var y_max: float = limits.get("y_max", INF)
		var mast = limits.get("mast_d")
		for p in points:
			if p.y > y_max:
				return false
			if mast != null:
				var r := Vector2(p.x - mast.x, p.z - mast.z).length()
				if r > limits.get("r_max", INF) or r < limits.get("r_min", 0.0):
					return false
	for i in range(1, points.size()):
		for b in blockers:
			if _segment_hits(points[i - 1], points[i], b):
				return false
	return true


## Whether the segment passes through the inside of `box` (touching is fine).
static func segment_hits(a: Vector3, b: Vector3, box: AABB) -> bool:
	return _segment_hits(a, b, box)


static func _segment_hits(a: Vector3, b: Vector3, box: AABB) -> bool:
	var lo := box.position + Vector3.ONE * _EPS
	var hi := box.end - Vector3.ONE * _EPS
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if a[axis] <= lo[axis] or a[axis] >= hi[axis]:
				return false
		else:
			var ta: float = (lo[axis] - a[axis]) / d[axis]
			var tb: float = (hi[axis] - a[axis]) / d[axis]
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 >= t1:
				return false
	return true
