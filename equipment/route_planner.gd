## The ground route of a vehicle across the site, around what is built.
##
## Plan view only (x, z): obstacles are rectangles, the vehicle is a rectangle
## of `length` x `width` that points along its path. `find()` first asks
## whether the straight line from start to goal is free; only if it is not does
## it look for the shortest way round -- a visibility graph over the obstacles'
## corners, searched with A*. The route is then checked again with the real
## body (the swept rectangle along each leg and the swing at each turn), and
## if the body does not fit it tries again with more room, so the result is
## the shortest route the vehicle itself can drive, not just a point.
##
## Pure functions, no scene access; SiteEquipment feeds it the boxes standing
## on the day of the drive (docs/13_SITE_EQUIPMENT.md, "Driving between jobs").
class_name RoutePlanner
extends RefCounted

## Room left beside the vehicle's body, in metres, tried in this order: the
## first that works is the shortest route (less room = tighter round corners).
const MARGINS := [0.6, 1.5, 3.0, 5.0, 8.0]
## How far round the start-goal box obstacles count, tried in this order.
const SEARCH := [40.0, 120.0]
## Safety beside the body when a route is checked, in metres.
const BODY_MARGIN := 0.6
const _EPS := 0.001
const _CELL := 10.0


## The route from `start` to `goal` (Vector2, x and z) for a vehicle of
## `length` x `width`, avoiding `obstacles` (Array of Rect2, x/z footprints).
## Returns {ok, direct, points: PackedVector2Array, length, margin}.
## `direct` is true when the straight line was free; `ok` false when no route
## exists (a closed wall, a start or goal buried in a building) -- `points` is
## then the straight line, so the caller can still show something.
static func find(start: Vector2, goal: Vector2, obstacles: Array, length: float, width: float) -> Dictionary:
	var straight := PackedVector2Array([start, goal])
	var fail := {"ok": false, "direct": false, "points": straight, "length": start.distance_to(goal), "margin": -1.0}
	var half_w := width * 0.5 + BODY_MARGIN
	if start.distance_to(goal) < 0.01:
		return {"ok": true, "direct": true, "points": straight, "length": 0.0, "margin": 0.0}
	if _clear(straight, obstacles, length, half_w):
		return {"ok": true, "direct": true, "points": straight, "length": start.distance_to(goal), "margin": 0.0}
	for search in SEARCH:
		var area := Rect2(start, Vector2.ZERO).expand(goal).grow(search)
		var near: Array = obstacles.filter(func(r: Rect2): return r.intersects(area))
		if near.is_empty():
			continue
		for margin in MARGINS:
			var pts := _search(start, goal, near, area, width * 0.5 + margin)
			if pts.size() < 2:
				continue
			if _clear(pts, near, length, half_w):
				return {"ok": true, "direct": false, "points": pts, "length": path_length(pts), "margin": margin}
	return fail


## Which ground can be reached from `start` over `area`: the obstacles grown by
## `inflate`, a grid of `cell`-metre squares, flooded from `start`. A cheap
## answer to "is there any road to here" for many places at once, where find()
## answers for one -- and slowly when there is none. Returns a Dictionary for
## reached().
static func flood(start: Vector2, obstacles: Array, area: Rect2, cell := 2.0, inflate := 2.5) -> Dictionary:
	var nx := maxi(int(ceil(area.size.x / cell)), 1)
	var nz := maxi(int(ceil(area.size.y / cell)), 1)
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	for o in obstacles:
		var r: Rect2 = (o as Rect2).grow(inflate)
		var x0 := clampi(int(floor((r.position.x - area.position.x) / cell)), 0, nx - 1)
		var x1 := clampi(int(floor((r.end.x - area.position.x) / cell)), 0, nx - 1)
		var z0 := clampi(int(floor((r.position.y - area.position.y) / cell)), 0, nz - 1)
		var z1 := clampi(int(floor((r.end.y - area.position.y) / cell)), 0, nz - 1)
		if r.end.x < area.position.x or r.position.x > area.end.x or r.end.y < area.position.y or r.position.y > area.end.y:
			continue
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				blocked[z * nx + x] = 1
	var reached := PackedByteArray()
	reached.resize(nx * nz)
	var sx := clampi(int(floor((start.x - area.position.x) / cell)), 0, nx - 1)
	var sz := clampi(int(floor((start.y - area.position.y) / cell)), 0, nz - 1)
	var stack := PackedInt32Array([sz * nx + sx])
	reached[sz * nx + sx] = 1
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var x := at % nx
		var z := at / nx
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ax: int = x + step[0]
			var az: int = z + step[1]
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var k := az * nx + ax
			if reached[k] == 0 and blocked[k] == 0:
				reached[k] = 1
				stack.append(k)
	return {"area": area, "cell": cell, "nx": nx, "nz": nz, "reached": reached}


## Whether `p` is on ground flood() reached (a place outside its area: no).
static func reached(flooded: Dictionary, p: Vector2) -> bool:
	var area: Rect2 = flooded.area
	if not area.has_point(p):
		return false
	var x := clampi(int(floor((p.x - area.position.x) / flooded.cell)), 0, flooded.nx - 1)
	var z := clampi(int(floor((p.y - area.position.y) / flooded.cell)), 0, flooded.nz - 1)
	return (flooded.reached as PackedByteArray)[z * flooded.nx + x] == 1


static func path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## Position and heading (radians, atan2(y, x) of the direction of travel) at
## `dist` metres along `points`. The heading turns gradually over `blend`
## metres either side of a corner instead of snapping. `start_heading` and
## `end_heading` (NAN = none) are the headings the vehicle has before the
## first and after the last point (the way a crane stands on its spot): the
## path eases into them over the first and last `blend` metres.
static func sample(points: PackedVector2Array, dist: float, start_heading := NAN, end_heading := NAN, blend := 4.0) -> Dictionary:
	var n := points.size()
	if n == 0:
		return {"pos": Vector2.ZERO, "heading": 0.0}
	if n == 1:
		return {"pos": points[0], "heading": 0.0 if is_nan(start_heading) else start_heading}
	var total := path_length(points)
	dist = clampf(dist, 0.0, total)
	var seg := 0
	var at := 0.0
	var starts: Array = []
	var heads: Array = []
	for i in n - 1:
		starts.append(at)
		heads.append((points[i + 1] - points[i]).angle())
		at += points[i].distance_to(points[i + 1])
	for i in range(1, n - 1):
		if dist >= starts[i]:
			seg = i
	var seg_len: float = points[seg].distance_to(points[seg + 1])
	var t: float = 0.0 if seg_len <= 0.0 else (dist - starts[seg]) / seg_len
	var pos := points[seg].lerp(points[seg + 1], t)
	var h: float = heads[seg]
	# Round a corner: turn from the previous leg to this one around the vertex.
	if seg > 0:
		var b := minf(blend, minf(seg_len, points[seg - 1].distance_to(points[seg])) * 0.5)
		var into: float = dist - starts[seg]
		if into < b and b > 0.0:
			h = lerp_angle(heads[seg - 1], h, smoothstep(-b, b, into))
	if seg < n - 2:
		var b2 := minf(blend, minf(seg_len, points[seg + 1].distance_to(points[seg + 2])) * 0.5)
		var left: float = starts[seg] + seg_len - dist
		if left < b2 and b2 > 0.0:
			h = lerp_angle(h, heads[seg + 1], smoothstep(-b2, b2, -left))
	if not is_nan(start_heading) and dist < blend:
		h = lerp_angle(start_heading, h, smoothstep(0.0, blend, dist))
	if not is_nan(end_heading) and total - dist < blend:
		h = lerp_angle(end_heading, h, smoothstep(0.0, blend, total - dist))
	return {"pos": pos, "heading": h}


# --- Search -------------------------------------------------------------------

## Shortest path round the obstacles, each grown by `inflate`; empty when none.
static func _search(start: Vector2, goal: Vector2, near: Array, area: Rect2, inflate: float) -> PackedVector2Array:
	var rects: Array = []
	for r in near:
		rects.append(_grown(r, inflate, start, goal))
	rects = rects.filter(func(r): return r.size.x > 0.0)
	rects = _without_contained(rects)
	var grid := _index(rects)
	var nodes: Array = [start, goal]
	for r in rects:
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if area.has_point(c) and not _inside_any(c, rects, grid):
				nodes.append(c)
	var count := nodes.size()
	var g := PackedFloat64Array()
	g.resize(count)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var open := PackedInt32Array([0])
	g[0] = 0.0
	while not open.is_empty():
		var best := 0
		var best_f := INF
		for k in open.size():
			var f: float = g[open[k]] + nodes[open[k]].distance_to(goal)
			if f < best_f:
				best_f = f
				best = k
		var u: int = open[best]
		open.remove_at(best)
		if u == 1:
			break
		closed[u] = 1
		for v in count:
			if closed[v] == 1 or v == u:
				continue
			var d: float = nodes[u].distance_to(nodes[v])
			if g[u] + d >= g[v]:
				continue
			if not _visible(nodes[u], nodes[v], rects, grid):
				continue
			if g[v] == INF:
				open.append(v)
			g[v] = g[u] + d
			prev[v] = u
	if prev[1] == -1:
		return PackedVector2Array()
	var rev: Array = []
	var at := 1
	while at != -1:
		rev.append(nodes[at])
		at = prev[at]
	rev.reverse()
	return PackedVector2Array(rev)


## An obstacle grown by `inflate`, but only as much as keeps the start and the
## goal outside it (a vehicle that begins or ends beside a wall cannot move
## away from it first). Zero-size when an end is inside the obstacle itself.
static func _grown(r: Rect2, inflate: float, start: Vector2, goal: Vector2) -> Rect2:
	var k := inflate
	for p in [start, goal]:
		if r.has_point(p):
			return Rect2()
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		k = minf(k, maxf(sqrt(dx * dx + dz * dz) - 0.05, 0.05))
	return r.grow(k)


static func _without_contained(rects: Array) -> Array:
	var out: Array = []
	for i in rects.size():
		var inner := false
		for j in rects.size():
			if i != j and rects[j].encloses(rects[i]) and (rects[j] != rects[i] or j < i):
				inner = true
				break
		if not inner:
			out.append(rects[i])
	return out


static func _index(rects: Array) -> Dictionary:
	var grid := {}
	for i in rects.size():
		var r: Rect2 = rects[i]
		for cx in range(int(floor(r.position.x / _CELL)), int(floor(r.end.x / _CELL)) + 1):
			for cz in range(int(floor(r.position.y / _CELL)), int(floor(r.end.y / _CELL)) + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(i)
	return grid


static func _inside_any(p: Vector2, rects: Array, grid: Dictionary) -> bool:
	var key := Vector2i(int(floor(p.x / _CELL)), int(floor(p.y / _CELL)))
	for i in grid.get(key, []):
		var r: Rect2 = rects[i]
		if p.x > r.position.x + _EPS and p.x < r.end.x - _EPS and p.y > r.position.y + _EPS and p.y < r.end.y - _EPS:
			return true
	return false


static func _visible(a: Vector2, b: Vector2, rects: Array, grid: Dictionary) -> bool:
	var seen := {}
	var lo := Vector2i(int(floor(minf(a.x, b.x) / _CELL)), int(floor(minf(a.y, b.y) / _CELL)))
	var hi := Vector2i(int(floor(maxf(a.x, b.x) / _CELL)), int(floor(maxf(a.y, b.y) / _CELL)))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			for i in grid.get(Vector2i(cx, cz), []):
				if seen.has(i):
					continue
				seen[i] = true
				if _segment_hits(a, b, rects[i]):
					return false
	return true


## Whether the segment passes through the inside of `r` (touching is allowed).
static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var lo := r.position + Vector2(_EPS, _EPS)
	var hi := r.end - Vector2(_EPS, _EPS)
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
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


# --- Checking the route with the vehicle's body ---------------------------------

## Whether a vehicle of `length` x 2*`half_w` drives `points` without touching
## `rects`: its body swept along every leg, and swung round at every corner.
## The body's ends are not swept past the first and last point (the vehicle
## starts and stops there; its spot was already chosen clear).
static func _clear(points: PackedVector2Array, rects: Array, length: float, half_w: float) -> bool:
	var half_l := length * 0.5
	var last := points.size() - 1
	for i in last:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var lo := -half_l if i > 0 else 0.0
		var hi := a.distance_to(b) + (half_l if i + 1 < last else 0.0)
		var centre := a + dir * ((lo + hi) * 0.5)
		for r in rects:
			if _body_hits(centre, dir, (hi - lo) * 0.5, half_w, r):
				return false
		if i > 0:
			var h0 := (a - points[i - 1]).angle()
			var h1 := dir.angle()
			for k in range(1, 6):
				var d := Vector2.from_angle(lerp_angle(h0, h1, k / 6.0))
				for r in rects:
					if _body_hits(a, d, half_l, half_w, r):
						return false
	return true


## Whether the rectangle (centre, forward direction, half length, half width)
## overlaps the axis-aligned `r` (separating axis test).
static func _body_hits(centre: Vector2, dir: Vector2, half_l: float, half_w: float, r: Rect2) -> bool:
	var side := Vector2(-dir.y, dir.x)
	var ex := absf(dir.x) * half_l + absf(side.x) * half_w
	var ez := absf(dir.y) * half_l + absf(side.y) * half_w
	if centre.x + ex <= r.position.x + _EPS or centre.x - ex >= r.end.x - _EPS:
		return false
	if centre.y + ez <= r.position.y + _EPS or centre.y - ez >= r.end.y - _EPS:
		return false
	var rc := r.get_center() - centre
	var rh := r.size * 0.5
	for axis in [dir, side]:
		var reach: float = rh.x * absf(axis.x) + rh.y * absf(axis.y)
		var own: float = half_l if axis == dir else half_w
		if absf(rc.dot(axis)) >= own + reach - _EPS:
			return false
	return true
