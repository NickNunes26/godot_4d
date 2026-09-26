@tool
class_name TerrainGrading
extends RefCounted

## TerrainPlatforms applied to a TerrainData's height grid: what each grid point
## is cut or filled by, stored so the shader can blend every platform in on its
## own schedule. The saved TerrainData is never modified -- clearing the
## platforms gives back the natural ground.
##
## Only the rectangle of grid points some platform actually changes is kept
## (`rect`, in grid columns/rows), typically a few thousand points out of the
## grid's 700,000. Each point has two slots, so a pit dug into a pad keeps both
## steps: slot 0 is the first platform that touched it, slot 1 the last. A third
## overlapping platform folds the older slot-1 change into slot 0.
##
## The ground is a 5 m (or coarser) triangle grid, so an edge cannot follow the
## footprint exactly: a triangle with one corner inside and one up the bank
## would tilt across the footprint's edge and poke through whatever the model
## puts there. So every grid point within one cell diagonal of the footprint is
## levelled too, and the banks start from there: the levelled area is up to
## that much (7 m at 5 m cells) wider than drawn, never narrower.
##
## Encoding (the `image`, RGBAF, one texel per grid point of `rect`):
## R = slot-0 height change, G = slot-0 code, B = slot-1 change, A = slot-1 code,
## where code = platform slot + 1 (0 = unused), plus 0.5 when the point lies
## inside that platform's footprint (drawn fully as bare earth).

const MAX_PLATFORMS := 16
## A bank point counts as fully bare earth once the ground moved this much.
const EARTH_FULL_CHANGE := 0.3

## Platforms in slot order (the enabled ones that reached the grid).
var used: Array[TerrainPlatform] = []
var rect := Rect2i()
var image: Image
var min_height := INF
var max_height := -INF
## Volumes at full progress, m^3 (positive numbers).
var cut_m3 := 0.0
var fill_m3 := 0.0

var _data: TerrainData
var _d0 := PackedFloat32Array()
var _c0 := PackedInt32Array()
var _d1 := PackedFloat32Array()
var _c1 := PackedInt32Array()

## Applies `platforms` to `data`; `to_terrain` takes the parts container's space
## into the terrain node's (x east, y absolute height, z south, origin at the
## grid centre). null when no platform changes anything.
static func compute(data: TerrainData, platforms: Array, to_terrain: Transform3D) -> TerrainGrading:
	if not data or data.grid_n < 2 or data.heights.size() != data.grid_n * data.grid_n:
		return null
	var n := data.grid_n
	var half := (n - 1) * 0.5
	var jobs: Array = []
	var area := Rect2i()
	for p in platforms:
		if not (p is TerrainPlatform) or not p.enabled or p.footprint.size() < 3:
			continue
		if jobs.size() == MAX_PLATFORMS:
			push_warning("TerrainGrading: more than %d platforms, the rest are ignored" % MAX_PLATFORMS)
			break
		var poly := PackedVector2Array()
		var level := 0.0
		for q in p.footprint:
			var t := to_terrain * Vector3(q.x, p.level, q.y)
			poly.append(Vector2(t.x, t.z))
			level += t.y
		level /= p.footprint.size()
		var slope := maxf(p.bank_slope, 0.0)
		var flat := data.cell * sqrt(2.0) + 0.001
		# No bank can reach further than the whole height range at this slope.
		var reach := flat + slope * maxf(data.max_height - level, level - data.min_height) + data.cell
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in poly:
			lo = lo.min(v)
			hi = hi.max(v)
		var c0 := maxi(int(floor((lo.x - reach) / data.cell + half)), 0)
		var r0 := maxi(int(floor((lo.y - reach) / data.cell + half)), 0)
		var c1 := mini(int(ceil((hi.x + reach) / data.cell + half)) + 1, n)
		var r1 := mini(int(ceil((hi.y + reach) / data.cell + half)) + 1, n)
		if c1 <= c0 or r1 <= r0:
			continue
		var box := Rect2i(c0, r0, c1 - c0, r1 - r0)
		area = box if jobs.is_empty() else area.merge(box)
		jobs.append({"platform": p, "poly": poly, "level": level, "slope": slope, "flat": flat, "reach": reach, "box": box})
	if jobs.is_empty():
		return null

	var g := TerrainGrading.new()
	g._data = data
	var w := area.size.x
	var count := w * area.size.y
	g._d0.resize(count)
	g._c0.resize(count)
	g._d1.resize(count)
	g._c1.resize(count)
	g._d0.fill(0.0)
	g._c0.fill(0)
	g._d1.fill(0.0)
	g._c1.fill(0)
	var touched_lo := Vector2i(n, n)
	var touched_hi := Vector2i(-1, -1)
	var heights := data.heights
	for slot in jobs.size():
		var job: Dictionary = jobs[slot]
		g.used.append(job.platform)
		var poly: PackedVector2Array = job.poly
		var level: float = job.level
		var slope: float = job.slope
		var reach: float = job.reach
		var flat: float = job.flat
		var box: Rect2i = job.box
		for r in range(box.position.y, box.end.y):
			var z := (r - half) * data.cell
			for c in range(box.position.x, box.end.x):
				var pt := Vector2((c - half) * data.cell, z)
				var inside := Geometry2D.is_point_in_polygon(pt, poly)
				var dist := 0.0
				if not inside:
					dist = _distance_to_outline(pt, poly)
					if dist > reach:
						continue
					if dist <= flat:
						inside = true
						dist = 0.0
					elif slope == 0.0:
						continue
					else:
						dist -= flat
				var k := (r - area.position.y) * w + (c - area.position.x)
				var current: float = heights[r * n + c] + g._d0[k] + g._d1[k]
				var tol := dist / slope if slope > 0.0 else 0.0
				var change := clampf(current, level - tol, level + tol) - current
				if not inside and absf(change) < 1e-4:
					continue
				var code := (slot + 1) * 2 + (1 if inside else 0)
				if g._c0[k] == 0:
					g._d0[k] = change
					g._c0[k] = code
				else:
					if g._c1[k] != 0:
						g._d0[k] += g._d1[k]
					g._d1[k] = change
					g._c1[k] = code
				touched_lo = touched_lo.min(Vector2i(c, r))
				touched_hi = touched_hi.max(Vector2i(c, r))
	if touched_hi.x < 0:
		return null
	g._crop(area, Rect2i(touched_lo, touched_hi - touched_lo + Vector2i.ONE))
	g._summarise()
	return g

## Shortest distance from `p` to the closed outline `poly`.
static func _distance_to_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

func _crop(from: Rect2i, to: Rect2i) -> void:
	var d0 := PackedFloat32Array()
	var c0 := PackedInt32Array()
	var d1 := PackedFloat32Array()
	var c1 := PackedInt32Array()
	var count := to.size.x * to.size.y
	d0.resize(count)
	c0.resize(count)
	d1.resize(count)
	c1.resize(count)
	for r in to.size.y:
		for c in to.size.x:
			var src := (r + to.position.y - from.position.y) * from.size.x + (c + to.position.x - from.position.x)
			var dst := r * to.size.x + c
			d0[dst] = _d0[src]
			c0[dst] = _c0[src]
			d1[dst] = _d1[src]
			c1[dst] = _c1[src]
	_d0 = d0
	_c0 = c0
	_d1 = d1
	_c1 = c1
	rect = to

func _summarise() -> void:
	var n := _data.grid_n
	var cell_area := _data.cell * _data.cell
	var texels := PackedFloat32Array()
	texels.resize(_d0.size() * 4)
	min_height = _data.min_height
	max_height = _data.max_height
	for r in rect.size.y:
		for c in rect.size.x:
			var k := r * rect.size.x + c
			var change := _d0[k] + _d1[k]
			var h: float = _data.heights[(r + rect.position.y) * n + c + rect.position.x] + change
			min_height = minf(min_height, h)
			max_height = maxf(max_height, h)
			if change < 0.0:
				cut_m3 -= change * cell_area
			else:
				fill_m3 += change * cell_area
			texels[k * 4] = _d0[k]
			texels[k * 4 + 1] = _c0[k] * 0.5
			texels[k * 4 + 2] = _d1[k]
			texels[k * 4 + 3] = _c1[k] * 0.5
	image = Image.create_from_data(rect.size.x, rect.size.y, false, Image.FORMAT_RGBAF, texels.to_byte_array())

## Per-slot 1.0 / 0.0: whether that platform is drawn as bare earth.
func bare_flags() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MAX_PLATFORMS)
	out.fill(0.0)
	for i in used.size():
		out[i] = 1.0 if used[i].bare_earth else 0.0
	return out

## Height change at grid point (c, r) with every platform complete.
func change_at(c: int, r: int) -> float:
	var local := Vector2i(c, r) - rect.position
	if local.x < 0 or local.y < 0 or local.x >= rect.size.x or local.y >= rect.size.y:
		return 0.0
	var k := local.y * rect.size.x + local.x
	return _d0[k] + _d1[k]

## Levelled height (m) at map point (e, n), bilinear like TerrainData.height_at().
func height_at(e: float, n: float) -> float:
	var d := _data
	if d.grid_n < 2:
		return NAN
	var half := (d.grid_n - 1) * 0.5
	return _bilinear(clampf((e - d.center_e) / d.cell + half, 0.0, d.grid_n - 1.001),
		clampf((d.center_n - n) / d.cell + half, 0.0, d.grid_n - 1.001))

func _graded(c: int, r: int) -> float:
	return _data.heights[r * _data.grid_n + c] + change_at(c, r)

func _bilinear(u: float, v: float) -> float:
	var c0 := int(u)
	var r0 := int(v)
	var fu := u - c0
	var fv := v - r0
	return lerpf(lerpf(_graded(c0, r0), _graded(c0 + 1, r0), fu),
		lerpf(_graded(c0, r0 + 1), _graded(c0 + 1, r0 + 1), fu), fv)

## A copy of the data's collision grid with the levelled area resampled from the
## levelled heights (every platform complete).
func patched_collision() -> PackedFloat32Array:
	var d := _data
	var out := d.collision_map.duplicate()
	var m := d.collision_n
	if m < 2:
		return out
	var half := (d.grid_n - 1) * 0.5
	var size := (d.grid_n - 1) * d.cell
	var spacing := d.collision_spacing()
	# Collision sample (col, row) sits at terrain-local x = -size/2 + col * spacing
	# (z likewise, row 0 = north), i.e. grid coordinate x / cell + half.
	var x0 := (rect.position.x - half) * d.cell
	var x1 := (rect.end.x - 1 - half) * d.cell
	var z0 := (rect.position.y - half) * d.cell
	var z1 := (rect.end.y - 1 - half) * d.cell
	var col0 := maxi(int(floor((x0 + size / 2.0) / spacing)), 0)
	var col1 := mini(int(ceil((x1 + size / 2.0) / spacing)), m - 1)
	var row0 := maxi(int(floor((z0 + size / 2.0) / spacing)), 0)
	var row1 := mini(int(ceil((z1 + size / 2.0) / spacing)), m - 1)
	for row in range(row0, row1 + 1):
		var v := clampf((-size / 2.0 + row * spacing) / d.cell + half, 0.0, d.grid_n - 1.001)
		for col in range(col0, col1 + 1):
			var u := clampf((-size / 2.0 + col * spacing) / d.cell + half, 0.0, d.grid_n - 1.001)
			out[row * m + col] = _bilinear(u, v) / spacing
	return out

# --- Platforms from a model ---------------------------------------------------

## Earthwork words in action ids and comments (Spanish, Galician, English).
const PAD_WORDS := ["terra vexetal", "tierra vegetal", "topsoil", "desmonte", "explana", "nivela",
	"movemento de terras", "movimiento de tierras", "terraplen", "terraplén", "grading", "earthwork",
	"levelling", "leveling", "site prep"]
const PIT_WORDS := ["escava", "excava", "vaciado", "baleirado", "zanja", "gabia", "trench"]
## IFC classes that go below the finished ground on purpose.
const BELOW_GROUND := ["IfcFooting", "IfcPile", "IfcDeepFoundation", "IfcCaissonFoundation", "IfcEarthworksCut"]

## Proposes platforms for a building: a pad under the whole model and, when
## parts reach below it (footings, the dig itself), a pit around them.
##
## - Pad level: the level most of the model stands on -- the bottom elevation
##   carrying the largest plan area of parts, foundations and dig parts left
##   out. Parts resting on it keep their bottom faces exactly on the ground.
## - Pad footprint: the model's plan extent (its own axes) plus `margin`.
## - Pit: the plan extent of parts whose bottom is more than 0.25 m under the
##   pad (+0.5 m working room unless the model draws the dig itself), down to
##   the lowest of them, banks at no more than 0.5.
## - Timing: actions whose id or comment reads as site levelling drive the pad,
##   those that read as excavation drive the pit; each falls back to the
##   other's so a pit never shows before its pad.
##
## `actions` is [{id, prefix, text}]. Returns [] when the container has no parts.
static func platforms_from_model(container: Node3D, actions: Array, margin := 0.0, slope := 1.5) -> Array[TerrainPlatform]:
	var out: Array[TerrainPlatform] = []
	var pad_ids := PackedStringArray()
	var pit_ids := PackedStringArray()
	var dig_prefixes: Array = []
	for a in actions:
		var text: String = String(a.get("text", "")).to_lower()
		if PIT_WORDS.any(func(k): return text.contains(k)):
			pit_ids.append(a.id)
			if String(a.get("prefix", "")) != "":
				dig_prefixes.append(a.prefix)
		elif PAD_WORDS.any(func(k): return text.contains(k)):
			pad_ids.append(a.id)

	var rows: Array = []
	for child in container.get_children():
		if not (child is Node3D) or child.has_meta(FormworkBuilder.META_OWNER):
			continue
		var box := _rest_aabb(child as Node3D, container)
		if box.size == Vector3.ZERO:
			continue
		var cls = child.get("ifc_class")
		var dig: bool = dig_prefixes.any(func(p): return String(child.name).begins_with(p))
		rows.append({"box": box, "below": dig or BELOW_GROUND.has(str(cls) if cls != null else ""), "dig": dig})
	if rows.is_empty():
		return out

	var area_at := {}
	var bottom_at := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in rows:
		var box: AABB = row.box
		lo = lo.min(Vector2(box.position.x, box.position.z))
		hi = hi.max(Vector2(box.end.x, box.end.z))
		if row.below:
			continue
		var bin := int(round(box.position.y / 0.05))
		area_at[bin] = area_at.get(bin, 0.0) + box.size.x * box.size.z
		if not bottom_at.has(bin) or box.position.y < bottom_at[bin]:
			bottom_at[bin] = box.position.y
	var level: float
	if area_at.is_empty():
		level = rows.map(func(row): return row.box.end.y).max()
	else:
		var best = area_at.keys()[0]
		for bin in area_at:
			if area_at[bin] > area_at[best]:
				best = bin
		level = bottom_at[best]

	var pad := TerrainPlatform.new()
	pad.name = "Plataforma"
	pad.footprint = _rectangle(lo - Vector2.ONE * margin, hi + Vector2.ONE * margin)
	pad.level = level
	pad.bank_slope = slope
	pad.activities = pad_ids if not pad_ids.is_empty() else pit_ids
	out.append(pad)

	var pit_lo := Vector2(INF, INF)
	var pit_hi := Vector2(-INF, -INF)
	var pit_bottom := INF
	var drawn := false
	for row in rows:
		var box: AABB = row.box
		if box.position.y >= level - 0.25:
			continue
		pit_lo = pit_lo.min(Vector2(box.position.x, box.position.z))
		pit_hi = pit_hi.max(Vector2(box.end.x, box.end.z))
		pit_bottom = minf(pit_bottom, box.position.y)
		drawn = drawn or row.dig
	if pit_bottom < INF:
		var room := 0.0 if drawn else 0.5
		var pit := TerrainPlatform.new()
		pit.name = "Excavación"
		pit.footprint = _rectangle(pit_lo - Vector2.ONE * room, pit_hi + Vector2.ONE * room)
		pit.level = pit_bottom
		pit.bank_slope = minf(slope, 0.5)
		pit.activities = pit_ids if not pit_ids.is_empty() else pad_ids
		out.append(pit)
	return out

## A part's box in the container's space at its rest placement. While a
## timeline runs (Play, or the dock's preview) parts sit wherever their
## animation starts -- 10 m under for rise_up, 15 m up for drop_in, scale 0 for
## scale_up -- and SequenceManager keeps the real placement in these metas.
static func _rest_aabb(part: Node3D, container: Node3D) -> AABB:
	if part.get_parent() != container or not part.has_meta("original_pos") or not part.has_meta("original_scale"):
		return TerrainBuilder._local_aabb(part, container)
	var own := TerrainBuilder._local_aabb(part, part)
	var basis := Basis.from_euler(part.rotation, part.rotation_order) * Basis.from_scale(part.get_meta("original_scale"))
	return Transform3D(basis, part.get_meta("original_pos")) * own

static func _rectangle(lo: Vector2, hi: Vector2) -> PackedVector2Array:
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
