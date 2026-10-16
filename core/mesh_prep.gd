@tool
class_name MeshPrep
extends RefCounted

## Puts a part's mesh in order for rendering that depends on which side of a
## face is outside -- the pour (fill_up), whose cut is capped by the faces seen
## from inside: every triangle wound so that its front (Godot: clockwise, seen
## from the front) faces out, and normals that point out.
##
## IFC meshes as GDIFC builds them are wound the other way round (front inside),
## which double-sided materials hide, and some -- most of an Allplan arch's
## dovelas, on VTO Río Zadorra -- mix both within one mesh. So the winding is
## made consistent across shared edges first, then each connected piece is
## turned the right way by the sign of its volume.

## A copy of `mesh` with every surface oriented outward (see above) and normals
## recomputed: a vertex normal averages the faces round it whose normals are
## within `smooth_deg` of its own face's -- 0 keeps faces flat, 30 shades
## curved faces smoothly while keeping real edges. Vertices are split per
## triangle corner; positions and materials are kept, other arrays (UVs,
## colours) are dropped. The result is marked, and handing a marked mesh back
## returns it as it is.
##
## With `close_openings`, faces the export left out are put back (see
## _closed_openings()): a flat opening is filled as the face it was -- for a
## hollow section's end, the ring between its outline and its void, the void
## staying open.
static func outward(mesh: Mesh, smooth_deg: float = 0.0, close_openings: bool = false) -> ArrayMesh:
	var mark := "%s|%s" % [smooth_deg, close_openings]
	if mesh is ArrayMesh and mesh.has_meta(PREPARED_META) and str(mesh.get_meta(PREPARED_META)) == mark:
		return mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var tris := _oriented(verts, idx)
		if close_openings:
			tris.append_array(_closed_openings(verts, tris))
		var surf := []
		surf.resize(Mesh.ARRAY_MAX)
		var flat := _corner_arrays(verts, tris, smooth_deg)
		surf[Mesh.ARRAY_VERTEX] = flat[0]
		surf[Mesh.ARRAY_NORMAL] = flat[1]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf)
		out.surface_set_material(s, mesh.surface_get_material(s))
	out.set_meta(PREPARED_META, mark)
	return out

const PREPARED_META := "_c4d_outward"

## Triangles as [a, b, c] index triples into `verts`, wound consistently and
## outward-front (clockwise from outside).
static func _oriented(verts: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var n_tris := idx.size() / 3
	# Weld by position: GDIFC splits vertices along creases.
	var weld := {}
	var wid := PackedInt32Array()
	wid.resize(verts.size())
	for i in verts.size():
		var k := verts[i].snappedf(0.0005)
		if not weld.has(k):
			weld[k] = weld.size()
		wid[i] = weld[k]
	# Undirected edge -> [[tri, +1 if the tri walks it low->high, else -1], ...]
	var edges := {}
	for t in n_tris:
		for k in 3:
			var a := wid[idx[t * 3 + k]]
			var b := wid[idx[t * 3 + (k + 1) % 3]]
			if a == b:
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(key):
				edges[key] = []
			edges[key].append([t, 1 if a < b else -1])
	# Flood each connected piece, flipping neighbours that walk a shared edge the
	# same way (only through edges shared by exactly two triangles).
	var flip := PackedInt32Array()
	flip.resize(n_tris)
	flip.fill(0) # 0 = unvisited, 1 = keep, -1 = flip
	var tri_edges: Array = []
	tri_edges.resize(n_tris)
	for t in n_tris:
		tri_edges[t] = []
	for key in edges:
		var users: Array = edges[key]
		if users.size() == 2:
			tri_edges[users[0][0]].append([users[0], users[1]])
			tri_edges[users[1][0]].append([users[1], users[0]])
	for seed in n_tris:
		if flip[seed] != 0:
			continue
		var piece: Array = [seed]
		flip[seed] = 1
		var stack: Array = [seed]
		while not stack.is_empty():
			var t: int = stack.pop_back()
			for pair in tri_edges[t]:
				var mine: Array = pair[0]
				var other: Array = pair[1]
				var n: int = other[0]
				# Consistent when the two walk the edge in opposite directions.
				var want: int = -(mine[1] * flip[t]) * other[1]
				if flip[n] == 0:
					flip[n] = want
					piece.append(n)
					stack.append(n)
		# Outward-front means clockwise from outside: a negative signed volume.
		var vol := 0.0
		for t in piece:
			var a := verts[idx[t * 3]]
			var b := verts[idx[t * 3 + 1]]
			var c := verts[idx[t * 3 + 2]]
			vol += a.dot(b.cross(c)) * flip[t]
		if vol > 0.0:
			for t in piece:
				flip[t] = -flip[t]
	var out: Array = []
	for t in n_tris:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		out.append([a, b, c] if flip[t] >= 0 else [a, c, b])
	return out

## [vertices, normals], one per triangle corner. Front-facing normal of a
## clockwise triangle (a, b, c) is (c - a) x (b - a); corners average their
## neighbours' (area-weighted) within `smooth_deg`.
static func _corner_arrays(verts: PackedVector3Array, tris: Array, smooth_deg: float) -> Array:
	var cos_limit := cos(deg_to_rad(smooth_deg)) - 1e-5
	var face_n := PackedVector3Array()
	face_n.resize(tris.size())
	var by_pos := {}
	for t in tris.size():
		var tri: Array = tris[t]
		face_n[t] = (verts[tri[2]] - verts[tri[0]]).cross(verts[tri[1]] - verts[tri[0]])
		for k in 3:
			var key := verts[tri[k]].snappedf(0.0005)
			if not by_pos.has(key):
				by_pos[key] = []
			by_pos[key].append(t)
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	pos.resize(tris.size() * 3)
	nor.resize(tris.size() * 3)
	for t in tris.size():
		var tri: Array = tris[t]
		var own := face_n[t].normalized()
		for k in 3:
			var p := verts[tri[k]]
			var sum := Vector3.ZERO
			for u in by_pos[p.snappedf(0.0005)]:
				if face_n[u].normalized().dot(own) >= cos_limit:
					sum += face_n[u]
			pos[t * 3 + k] = p
			nor[t * 3 + k] = sum.normalized() if sum.length_squared() > 0.0 else own
	return [pos, nor]

# --- Missing faces ----------------------------------------------------------------

## Triangles for the faces an oriented mesh is missing: its openings (loops of
## edges used by one triangle only) that are flat, grouped by plane and filled
## as faces with holes -- an outer loop minus the loops inside it. A hollow
## section's missing end becomes its ring; the void stays open, as it is in
## the structure. Each new triangle runs round its loop the other way to the
## triangles beside it, which keeps the winding outward-front. Only existing
## vertices are used.
static func _closed_openings(verts: PackedVector3Array, tris: Array) -> Array:
	var weld := {}
	var wid := PackedInt32Array()
	wid.resize(verts.size())
	var rep: Array = [] # welded id -> a vertex index with that position
	for i in verts.size():
		var k := verts[i].snappedf(0.0005)
		if not weld.has(k):
			weld[k] = rep.size()
			rep.append(i)
		wid[i] = weld[k]
	var info: Array = []
	for loop in _loops(tris, wid):
		var pts: Array = loop.map(func(w): return verts[rep[w]])
		var c := Vector3.ZERO
		for q in pts:
			c += q
		c /= pts.size()
		var n := Vector3.ZERO
		for k in pts.size():
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[(k + 1) % pts.size()]
			n += Vector3((p0.y - p1.y) * (p0.z + p1.z), (p0.z - p1.z) * (p0.x + p1.x), (p0.x - p1.x) * (p0.y + p1.y))
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var flat := true
		for q in pts:
			if absf((q - c).dot(n)) > 0.01:
				flat = false
				break
		if flat:
			info.append({"ids": loop.map(func(w): return rep[w]), "pts": pts, "c": c, "n": n})
	var out: Array = []
	var used := {}
	for a in info.size():
		if used.has(a):
			continue
		# Everything on this loop's plane.
		var group: Array = [a]
		for b in range(a + 1, info.size()):
			if not used.has(b) and absf(absf(info[b].n.dot(info[a].n)) - 1.0) < 1e-3 \
					and absf((info[b].c - info[a].c).dot(info[a].n)) < 0.02:
				group.append(b)
		for g in group:
			used[g] = true
		var basis := _plane_basis(info[a].n)
		var polys: Array = []
		for g in group:
			polys.append({"pts": _to_2d(info[g].pts, info[a].c, basis), "ids": info[g].ids})
		for face in _faces_with_holes(polys):
			var outer_poly: PackedVector2Array = face.outer.pts
			var want := -signf(_signed_area_2d(outer_poly)) # the outer loop, reversed
			for tri in _triangulate_with_holes(face.outer, face.holes):
				var pa: Vector2 = tri[0][0]
				var pb: Vector2 = tri[1][0]
				var pc: Vector2 = tri[2][0]
				var ids := [tri[0][1], tri[1][1], tri[2][1]]
				if signf((pb - pa).cross(pc - pa)) != want:
					ids = [ids[0], ids[2], ids[1]]
				out.append(ids)
	return out

## Loops of the edges walked by exactly one of `tris`, each as a list of welded
## ids in the direction those triangles walk them.
static func _loops(tris: Array, wid: PackedInt32Array) -> Array:
	var used := {}
	var walk := {}
	for tri in tris:
		for k in 3:
			var a := wid[tri[k]]
			var b := wid[tri[(k + 1) % 3]]
			if a == b:
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			used[key] = used.get(key, 0) + 1
			walk[key] = Vector2i(a, b)
	var next := {}
	for key in used:
		if used[key] == 1:
			var d: Vector2i = walk[key]
			next[d.x] = d.y
	var loops: Array = []
	var seen := {}
	for s in next:
		if seen.has(s):
			continue
		var loop: Array = []
		var cur = s
		while not seen.has(cur) and next.has(cur):
			seen[cur] = true
			loop.append(cur)
			cur = next[cur]
		if loop.size() >= 3 and cur == s:
			loops.append(loop)
	return loops

## Coplanar loops ({pts: PackedVector2Array, ids: Array}) sorted into faces:
## [{outer, holes: [...]}] -- a loop nested an even number of times is an outer
## boundary, one nested an odd number of times a hole of the loop just around it.
static func _faces_with_holes(polys: Array) -> Array:
	var depth: Array = []
	var parent: Array = []
	for i in polys.size():
		var d := 0
		var best := -1
		for j in polys.size():
			if j != i and _area_2d(polys[j].pts) > _area_2d(polys[i].pts) \
					and Geometry2D.is_point_in_polygon(polys[i].pts[0], polys[j].pts):
				d += 1
				if best < 0 or _area_2d(polys[j].pts) < _area_2d(polys[best].pts):
					best = j
		depth.append(d)
		parent.append(best)
	var faces: Array = []
	for i in polys.size():
		if depth[i] % 2 == 0:
			var holes: Array = []
			for j in polys.size():
				if parent[j] == i and depth[j] % 2 == 1:
					holes.append(polys[j])
			faces.append({"outer": polys[i], "holes": holes})
	return faces

## Triangles of a polygon with holes, as [[point, id], [point, id], [point, id]].
## Each hole is joined to the outline by a cut (a "keyhole": from the hole's
## rightmost vertex to the nearest outline vertex it can see), making one
## polygon Geometry2D can triangulate. If that fails, a Delaunay triangulation
## of all the points, keeping the triangles inside the face.
static func _triangulate_with_holes(outer: Dictionary, holes: Array) -> Array:
	var pts := PackedVector2Array(outer.pts)
	var ids: Array = outer.ids.duplicate()
	if _signed_area_2d(pts) < 0.0: # outline counter-clockwise
		pts.reverse()
		ids.reverse()
	var hs: Array = []
	for h in holes:
		var hp := PackedVector2Array(h.pts)
		var hi: Array = h.ids.duplicate()
		if _signed_area_2d(hp) > 0.0: # holes clockwise
			hp.reverse()
			hi.reverse()
		var right := 0
		for k in hp.size():
			if hp[k].x > hp[right].x:
				right = k
		hs.append({"pts": hp, "ids": hi, "right": right})
	hs.sort_custom(func(x, y): return x.pts[x.right].x > y.pts[y.right].x)
	var ok := true
	for h in hs:
		var hp: PackedVector2Array = h.pts
		var hv: Vector2 = hp[h.right]
		var order: Array = range(pts.size())
		order.sort_custom(func(x, y): return pts[x].distance_squared_to(hv) < pts[y].distance_squared_to(hv))
		var bridge := -1
		for o in order:
			if _sees(hv, pts[o], pts, hs):
				bridge = o
				break
		if bridge < 0:
			ok = false
			break
		var np := PackedVector2Array()
		var ni: Array = []
		for k in bridge + 1:
			np.append(pts[k])
			ni.append(ids[k])
		for k in hp.size() + 1:
			var m: int = (h.right + k) % hp.size()
			np.append(hp[m])
			ni.append(h.ids[m])
		for k in range(bridge, pts.size()):
			np.append(pts[k])
			ni.append(ids[k])
		pts = np
		ids = ni
	var out: Array = []
	if ok:
		var tri := Geometry2D.triangulate_polygon(pts)
		for k in range(0, tri.size(), 3):
			out.append([[pts[tri[k]], ids[tri[k]]], [pts[tri[k + 1]], ids[tri[k + 1]]], [pts[tri[k + 2]], ids[tri[k + 2]]]])
		if not out.is_empty():
			return out
	# Fallback: Delaunay over every point, keeping what lies inside the face.
	var all_p := PackedVector2Array(outer.pts)
	var all_i: Array = outer.ids.duplicate()
	for h in holes:
		all_p.append_array(h.pts)
		all_i.append_array(h.ids)
	var d := Geometry2D.triangulate_delaunay(all_p)
	for k in range(0, d.size(), 3):
		var cen := (all_p[d[k]] + all_p[d[k + 1]] + all_p[d[k + 2]]) / 3.0
		if not Geometry2D.is_point_in_polygon(cen, outer.pts):
			continue
		var in_hole := false
		for h in holes:
			if Geometry2D.is_point_in_polygon(cen, h.pts):
				in_hole = true
				break
		if not in_hole:
			out.append([[all_p[d[k]], all_i[d[k]]], [all_p[d[k + 1]], all_i[d[k + 1]]], [all_p[d[k + 2]], all_i[d[k + 2]]]])
	return out

## Whether the segment a-b crosses no edge of the outline or of the holes
## (edges that end at a or b don't count).
static func _sees(a: Vector2, b: Vector2, outline: PackedVector2Array, holes: Array) -> bool:
	var rings: Array = [outline]
	for h in holes:
		rings.append(h.pts)
	for ring in rings:
		for k in ring.size():
			var p: Vector2 = ring[k]
			var q: Vector2 = ring[(k + 1) % ring.size()]
			if p.is_equal_approx(a) or p.is_equal_approx(b) or q.is_equal_approx(a) or q.is_equal_approx(b):
				continue
			if Geometry2D.segment_intersects_segment(a, b, p, q) != null:
				return false
	return true

static func _plane_basis(n: Vector3) -> Array:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	return [u, n.cross(u).normalized()]

static func _to_2d(pts: Array, origin: Vector3, basis: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2((q - origin).dot(basis[0]), (q - origin).dot(basis[1])))
	return out

static func _signed_area_2d(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s * 0.5

static func _area_2d(poly: PackedVector2Array) -> float:
	return absf(_signed_area_2d(poly))

# --- The pour's top ---------------------------------------------------------------

## The horizontal section of `mesh` (placed by `xf`) at world height `level`,
## as a flat mesh in the mesh's own space, front faces up: what the plane cuts
## through, filled -- for a hollow section the ring of its walls, the void left
## open. null when the plane misses the mesh.
##
## `topo` is welded(mesh), for a caller cutting the same mesh again and again.
static func section_cap(mesh: Mesh, xf: Transform3D, level: float, topo: Array = []) -> ArrayMesh:
	if topo.is_empty():
		topo = welded(mesh)
	var wp: PackedVector3Array = topo[0]
	var ids: PackedInt32Array = topo[1]
	var world := PackedVector3Array()
	world.resize(wp.size())
	for i in wp.size():
		world[i] = xf * wp[i]
		if absf(world[i].y - level) < 1e-5:
			level += 2e-5 # never exactly through a vertex
	# Each triangle the plane crosses gives a segment between two crossed edges.
	var hit := {} # edge key -> Vector2 (x, z) of the crossing
	var adj := {} # edge key -> [edge keys]
	for t in ids.size() / 3:
		var keys: Array = []
		for k in 3:
			var a := ids[t * 3 + k]
			var b := ids[t * 3 + (k + 1) % 3]
			var ya := world[a].y - level
			var yb := world[b].y - level
			if (ya < 0.0) == (yb < 0.0):
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not hit.has(key):
				var f := ya / (ya - yb)
				var q := world[a].lerp(world[b], f)
				hit[key] = Vector2(q.x, q.z)
			keys.append(key)
		if keys.size() == 2:
			for e in [[keys[0], keys[1]], [keys[1], keys[0]]]:
				if not adj.has(e[0]):
					adj[e[0]] = []
				adj[e[0]].append(e[1])
	var loops: Array = []
	var seen := {}
	for s in adj:
		if seen.has(s):
			continue
		var loop := PackedVector2Array()
		var prev = null
		var cur = s
		while cur != null and not seen.has(cur):
			seen[cur] = true
			loop.append(hit[cur])
			var nxt = null
			for c in adj[cur]:
				if c != prev and not seen.has(c):
					nxt = c
					break
			prev = cur
			cur = nxt
		if loop.size() >= 3:
			loops.append(loop)
	if loops.is_empty():
		return null
	var polys: Array = []
	var next_id := 0
	for loop in loops:
		var loop_ids: Array = []
		for q in loop:
			loop_ids.append(next_id)
			next_id += 1
		polys.append({"pts": loop, "ids": loop_ids})
	var to_local := xf.affine_inverse()
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var up_local := (to_local.basis * Vector3.UP).normalized()
	for face in _faces_with_holes(polys):
		for tri in _triangulate_with_holes(face.outer, face.holes):
			var pa := Vector3(tri[0][0].x, level, tri[0][0].y)
			var pb := Vector3(tri[1][0].x, level, tri[1][0].y)
			var pc := Vector3(tri[2][0].x, level, tri[2][0].y)
			# Front up: clockwise seen from above, i.e. (c - a) x (b - a) points +Y.
			if (pc - pa).cross(pb - pa).y < 0.0:
				var sw := pb
				pb = pc
				pc = sw
			for q in [pa, pb, pc]:
				pos.append(to_local * q)
				nor.append(up_local)
	if pos.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## [welded positions, triangle ids into them] of a mesh's surfaces.
static func welded(mesh: Mesh) -> Array:
	var weld := {}
	var wp := PackedVector3Array()
	var ids := PackedInt32Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for i in count:
			var p := v[idx[i]] if not idx.is_empty() else v[i]
			var k := p.snappedf(0.0005)
			if not weld.has(k):
				weld[k] = wp.size()
				wp.append(p)
			ids.append(weld[k])
	return [wp, ids]
