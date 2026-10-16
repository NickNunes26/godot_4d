## Headless test for the pour (fill_up / build_up): a level rising in world Y,
## the part whole and unscaled, and MeshPrep's outward winding the cap needs.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_fill.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

## A box as an indexed ArrayMesh, with every other triangle wound the wrong way
## round -- the kind of mix an IFC exporter leaves.
func _scrambled_box(size: Vector3) -> ArrayMesh:
	var src := BoxMesh.new()
	src.size = size
	var arrays := src.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in idx.size() / 3:
		if t % 2 == 0:
			var b := idx[t * 3 + 1]
			idx[t * 3 + 1] = idx[t * 3 + 2]
			idx[t * 3 + 2] = b
	var clean := []
	clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
	clean[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean)
	return m

func _part(mesh: Mesh, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot_deg
	root.add_child(m)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	m.set_surface_override_material(0, mat)
	m.set_meta("original_pos", m.position)
	m.set_meta("original_scale", m.scale)
	m.set_meta("original_quaternion", m.quaternion)
	m.set_meta("original_transform", m.global_transform)
	m.set_meta("original_aabb", mesh.get_aabb())
	return m

func _run() -> void:
	print("=== MeshPrep.outward: one winding, front outside")
	var prepared := MeshPrep.outward(_scrambled_box(Vector3(2, 4, 2)))
	var pa := prepared.surface_get_arrays(0)
	var v: PackedVector3Array = pa[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = pa[Mesh.ARRAY_NORMAL]
	var vol := 0.0
	var outward := true
	for t in v.size() / 3:
		var a := v[t * 3]
		var b := v[t * 3 + 1]
		var c := v[t * 3 + 2]
		vol += a.dot(b.cross(c))
		var centroid := (a + b + c) / 3.0
		# Front of a clockwise triangle, and its stored normals, point away from the centre.
		if (c - a).cross(b - a).dot(centroid) <= 0.0 or n[t * 3].dot(centroid) <= 0.0:
			outward = false
	_check("every face fronts outward, normals out", outward, true)
	_check("so the signed volume is negative (%.2f; -6 x 16 m3)" % vol, absf(vol + 96.0) < 1e-3, true)
	_check("a prepared mesh is handed back as it is", MeshPrep.outward(prepared), prepared)

	print("\n=== fill_up: the level rises in world Y, the part whole")
	# A 2 x 4 x 2 box lying on its side (90 deg about Z): 2 m tall in world Y,
	# from 9 to 11, its own Y horizontal.
	var lying := _part(BoxMesh.new(), Vector3(0, 10, 0), Vector3(0, 0, 90))
	(lying.mesh as BoxMesh).size = Vector3(2, 4, 2)
	lying.set_meta("original_aabb", lying.mesh.get_aabb())
	var own: Material = lying.get_surface_override_material(0)
	AnimationApplier.apply_instant(lying, "fill_up", 0.0)
	_check("not started: hidden", lying.visible, false)
	_check("and wearing its own material", lying.get_surface_override_material(0), own)
	AnimationApplier.apply_instant(lying, "fill_up", 0.5)
	_check("half way: shown", lying.visible, true)
	_check("at its own size (no squash)", lying.scale, Vector3.ONE)
	_check("in its own place", lying.position, Vector3(0, 10, 0))
	var fill := lying.get_surface_override_material(0) as ShaderMaterial
	_check("drawn with the pour shader", fill != null and fill.shader == AnimationApplier.FILL_SHADER, true)
	_check("level half way up in world Y: 10 m (%.3f)" % float(fill.get_shader_parameter("fill_y")), absf(float(fill.get_shader_parameter("fill_y")) - 10.0) < 1e-3, true)
	_check("its colour carried over", fill.get_shader_parameter("albedo"), Color(0.8, 0.2, 0.2))
	AnimationApplier.apply_instant(lying, "fill_up", 0.25)
	_check("a quarter: 9.5 m", absf(float(fill.get_shader_parameter("fill_y")) - 9.5) < 1e-3, true)
	AnimationApplier.apply_instant(lying, "fill_up", 1.0)
	_check("done: its own material back", lying.get_surface_override_material(0), own)
	_check("and its mesh prepared for the next time", lying.mesh.has_meta(MeshPrep.PREPARED_META), true)

	print("\n=== build_up goes the same way")
	var wall := _part(BoxMesh.new(), Vector3(5, 3, 0), Vector3(30, 0, 0))
	AnimationApplier.apply_instant(wall, "build_up", 0.5)
	var ext := AnimationApplier.fill_extent(wall)
	var wf := wall.get_surface_override_material(0) as ShaderMaterial
	_check("level at the middle of its world height", absf(float(wf.get_shader_parameter("fill_y")) - (ext.x + ext.y) * 0.5) < 1e-3, true)
	_check("no squash", wall.scale, Vector3.ONE)

	print("\n=== a hinged part: measured as it stands, after the swing")
	var dovela := _part(BoxMesh.new(), Vector3(10, 1, 0), Vector3.ZERO)
	(dovela.mesh as BoxMesh).size = Vector3(6, 2, 2)
	dovela.set_meta("original_aabb", dovela.mesh.get_aabb())
	# Stood up 90 deg about Z through (7, 0, 0): 6 m tall, from y = 0 to 6.
	var hinge := {"pivot": Vector3(7, 0, 0), "axis": Vector3(0, 0, 1), "angle": PI / 2}
	AnimationApplier.apply_instant_hinged(dovela, "fill_up", 0.5, hinge)
	var df := dovela.get_surface_override_material(0) as ShaderMaterial
	var dext := AnimationApplier.fill_extent(dovela)
	_check("standing 6 m tall (%.2f to %.2f)" % [dext.x, dext.y], absf(dext.y - dext.x - 6.0) < 1e-3, true)
	_check("level half way up the standing piece: 3 m (%.3f)" % float(df.get_shader_parameter("fill_y")), absf(float(df.get_shader_parameter("fill_y")) - (dext.x + dext.y) * 0.5) < 1e-3, true)

	print("\n=== a hollow section stays hollow: its missing face put back as a ring, poured as walls")
	var tube := _hollow_tube()
	_check("the tube as exported: open (%d open edges)" % _open_edges(tube), _open_edges(tube) > 0, true)
	var closed := MeshPrep.outward(tube, 0.0, true)
	_check("closed: no open edge left (%d)" % _open_edges(closed), _open_edges(closed), 0)
	_check("its top put back as the ring, 16 - 4 = 12 m2 (%.2f)" % _facing_area(closed, Vector3.UP, 3.0), absf(_facing_area(closed, Vector3.UP, 3.0) - 12.0) < 1e-3, true)
	_check("its bottom ring as it was, 12 m2 down (%.2f)" % _facing_area(closed, Vector3.DOWN, 0.0), absf(_facing_area(closed, Vector3.DOWN, 0.0) - 12.0) < 1e-3, true)
	var cut := MeshPrep.section_cap(tube, Transform3D(), 1.5)
	_check("the section at 1.5 m: the walls' ring, core open (%.2f m2)" % _facing_area(cut, Vector3.UP, 1.5), absf(_facing_area(cut, Vector3.UP, 1.5) - 12.0) < 1e-3, true)
	var octo := MeshPrep.section_cap(_hollow_tube(true), Transform3D(), 1.0)
	_check("an octagonal hollow pier's section: its ring (%.2f m2)" % _facing_area(octo, Vector3.UP, 1.0), absf(_facing_area(octo, Vector3.UP, 1.0) - _octagon_ring_area()) < 1e-2, true)
	var pier := _part(tube, Vector3(20, 0, 0), Vector3.ZERO)
	AnimationApplier.apply_instant(pier, "fill_up", 0.5)
	var top := pier.get_node_or_null(AnimationApplier.POUR_CAP) as MeshInstance3D
	_check("pouring it: a top at the level", top != null and top.visible, true)
	_check("over the walls only (%.2f m2 at 1.5 m)" % (_facing_area(top.mesh, Vector3.UP, 1.5) if top else 0.0), top != null and absf(_facing_area(top.mesh, Vector3.UP, 1.5) - 12.0) < 1e-3, true)
	AnimationApplier.apply_instant(pier, "fill_up", 1.0)
	_check("poured: the top is gone", pier.get_node_or_null(AnimationApplier.POUR_CAP), null)
	AnimationApplier.apply_instant(pier, "fill_up", 0.3)
	AnimationApplier.end_fill(pier)
	_check("a pour cut short (Stop Preview) leaves no top behind", pier.get_node_or_null(AnimationApplier.POUR_CAP) == null, true)
	_check("and its own material back", pier.get_surface_override_material(0) is ShaderMaterial, false)

	print("\n" + ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)

## A 4 x 4 m square tube with a 2 x 2 m core, 3 m tall: walls inside and out and
## a bottom ring, its top ring missing -- a hollow pier lift as the IFC has it.
## `octagon`: an octagonal one (outer radius 3, core radius 2), like the piers.
func _hollow_tube(octagon := false) -> ArrayMesh:
	var v := PackedVector3Array()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3):
		v.append_array([a, b, c, a, c, d])
	var o := [Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(2, 0, 2), Vector3(-2, 0, 2)]
	var i := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	if octagon:
		o = []
		i = []
		for k in 8:
			var a := TAU * k / 8.0
			o.append(Vector3(cos(a), 0, sin(a)) * 3.0)
			i.append(Vector3(cos(a), 0, sin(a)) * 2.0)
	var up := Vector3(0, 3, 0)
	var n := o.size()
	for k in n:
		var k2 := (k + 1) % n
		quad.call(o[k], o[k2], o[k2] + up, o[k] + up)      # outer wall
		quad.call(i[k2], i[k], i[k] + up, i[k2] + up)      # core wall
		quad.call(o[k2], o[k], i[k], i[k2])                # bottom ring
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Open edges, leaving out those within `ignore_within` of the axis in plan.
## A regular octagon's area is 2 sqrt(2) r^2: radius 3 minus radius 2.
func _octagon_ring_area() -> float:
	return 2.0 * sqrt(2.0) * (9.0 - 4.0)

func _open_edges(mesh: Mesh, ignore_within: float = -1.0) -> int:
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var count := {}
	for t in v.size() / 3:
		for k in 3:
			var a := v[t * 3 + k].snappedf(0.001)
			var b := v[t * 3 + (k + 1) % 3].snappedf(0.001)
			var key := [a, b] if str(a) < str(b) else [b, a]
			count[str(key)] = count.get(str(key), 0) + 1
	var open := 0
	for key in count:
		if count[key] == 1:
			open += 1
	if ignore_within > 0.0:
		open = 0
		for t in v.size() / 3:
			for k in 3:
				var a := v[t * 3 + k].snappedf(0.001)
				var b := v[t * 3 + (k + 1) % 3].snappedf(0.001)
				var key := [a, b] if str(a) < str(b) else [b, a]
				if count[str(key)] == 1 and maxf(maxf(absf(a.x), absf(a.z)), maxf(absf(b.x), absf(b.z))) > ignore_within:
					open += 1
	return open

## Area of the triangles at height `y` whose front faces `dir` (clockwise front).
func _facing_area(mesh: Mesh, dir: Vector3, y: float) -> float:
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for t in v.size() / 3:
		var a := v[t * 3]
		var b := v[t * 3 + 1]
		var c := v[t * 3 + 2]
		if absf(a.y - y) > 1e-3 or absf(b.y - y) > 1e-3 or absf(c.y - y) > 1e-3:
			continue
		var n := (c - a).cross(b - a)
		if n.normalized().dot(dir) > 0.99:
			area += n.length() * 0.5
	return area
	quit(_fails)
