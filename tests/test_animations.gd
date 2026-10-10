## Headless test for how drop_in, scale_up and the fades look at any progress.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_animations.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _init() -> void:
	call_deferred("_run")

## A box part with the metas SequenceManager.initialize_parts() records, its
## material made unique as make_materials_unique() would.
func _part(parent: Node3D, size: Vector3, pos: Vector3, rot_y_deg := 0.0, alpha := 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.7, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.set_surface_override_material(0, mat)
	m.position = pos
	m.rotation_degrees.y = rot_y_deg
	parent.add_child(m)
	m.set_meta("original_pos", m.position)
	m.set_meta("original_scale", m.scale)
	m.set_meta("original_transform", m.global_transform)
	m.set_meta("original_aabb", b.get_aabb())
	return m

func _mat(part: MeshInstance3D) -> StandardMaterial3D:
	return part.get_active_material(0)

## World position of the middle of a part's base, given its live transform.
func _base_world(part: MeshInstance3D) -> Vector3:
	var box: AABB = part.mesh.get_aabb()
	return part.global_transform * Vector3(box.get_center().x, box.position.y, box.get_center().z)

func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)

	print("=== drop_in: lowered from just above, scaled to the piece")
	var stone := _part(root3d, Vector3(1, 0.4, 0.5), Vector3(2, 5, 0))     # 0.4 m tall
	var truss := _part(root3d, Vector3(8, 3, 0.2), Vector3(0, 9, 0))       # 3 m tall
	var column := _part(root3d, Vector3(0.4, 6, 0.4), Vector3(4, 3, 0))    # 6 m tall
	_check("small piece: minimum height", AnimationApplier.drop_height(stone), AnimationApplier.DROP_MIN)
	_check("3 m truss: 1.5 + 1.5 x 3", AnimationApplier.drop_height(truss), 6.0)
	_check("tall piece: capped", AnimationApplier.drop_height(column), AnimationApplier.DROP_MAX)
	AnimationApplier.apply_instant(truss, "drop_in", 0.0)
	_check("not started: hidden", truss.visible, false)
	AnimationApplier.apply_instant(truss, "drop_in", 0.001)
	_check("just started: visible, 6 m up", [truss.visible, snappedf(truss.position.y - 9.0, 0.01)], [true, 6.0])
	_check("just started: nearly transparent", _mat(truss).albedo_color.a < 0.05, true)
	AnimationApplier.apply_instant(truss, "drop_in", AnimationApplier.DROP_FADE)
	_check("faded in by DROP_FADE, back to opaque rendering",
		[_mat(truss).albedo_color.a, _mat(truss).transparency], [1.0, BaseMaterial3D.TRANSPARENCY_DISABLED])
	var heights: Array = []
	var monotonic := true
	for i in range(0, 101):
		AnimationApplier.apply_instant(truss, "drop_in", i / 100.0)
		heights.append(truss.position.y)
		if i > 0 and heights[i] > heights[i - 1] + 1e-6:
			monotonic = false
	_check("only ever goes down", monotonic, true)
	_check("never below its place", heights.min() >= 9.0 - 1e-6, true)
	var first_step: float = heights[1] - heights[2]
	var mid_step: float = heights[50] - heights[51]
	var last_step: float = heights[98] - heights[99]
	_check("slow off the hook, steady, slow on landing", first_step < mid_step and last_step < mid_step, true)
	AnimationApplier.apply_instant(truss, "drop_in", 1.0)
	_check("lands exactly on its place", truss.position, Vector3(0, 9, 0))

	print("=== scale_up: grows from its base, no overshoot")
	var holder := Node3D.new()
	holder.position = Vector3(100, -20, 40)
	holder.rotation_degrees.y = 15.0
	root3d.add_child(holder)
	var tree := _part(holder, Vector3(2, 6, 2), Vector3(3, 3, -1), 30.0)
	var base_at_rest := _base_world(tree)
	var orig_scale: Vector3 = tree.get_meta("original_scale")
	var overshoot := false
	var drift := 0.0
	var prev_k := 0.0
	var growing := true
	for i in range(1, 100):
		AnimationApplier.apply_instant(tree, "scale_up", i / 100.0)
		var k: float = tree.scale.y / orig_scale.y
		if k > 1.0 + 1e-6:
			overshoot = true
		if k < prev_k:
			growing = false
		prev_k = k
		drift = maxf(drift, _base_world(tree).distance_to(base_at_rest))
	_check("never larger than finished", overshoot, false)
	_check("only ever grows", growing, true)
	_check("base stays put (rotated part, offset + rotated parent): drift %.5f m" % drift, drift < 0.001, true)
	AnimationApplier.apply_instant(tree, "scale_up", 0.5)
	_check("uniform growth", is_equal_approx(tree.scale.x / orig_scale.x, tree.scale.y / orig_scale.y), true)
	AnimationApplier.apply_instant(tree, "scale_up", 0.0)
	_check("not started: hidden", tree.visible, false)
	AnimationApplier.apply_instant(tree, "scale_up", 1.0)
	_check("finished: exact placement", [tree.position, tree.scale], [tree.get_meta("original_pos"), orig_scale])

	print("=== fades keep a material's own transparency")
	var glass := _part(root3d, Vector3(1, 1.5, 0.02), Vector3(0, 1, 5), 0.0, 0.3)
	AnimationApplier.apply_instant(glass, "fade_in", 0.0)
	_check("fade_in not started: hidden", glass.visible, false)
	AnimationApplier.apply_instant(glass, "fade_in", 0.5)
	_check("fade_in half way: half of glass's alpha", is_equal_approx(_mat(glass).albedo_color.a, 0.15), true)
	AnimationApplier.apply_instant(glass, "fade_in", 1.0)
	_check("fade_in done: glass is still glass", [snappedf(_mat(glass).albedo_color.a, 0.001), _mat(glass).transparency],
		[0.3, BaseMaterial3D.TRANSPARENCY_ALPHA])
	AnimationApplier.apply_instant(glass, "fade_out", 0.0)
	_check("fade_out not started: glass", snappedf(_mat(glass).albedo_color.a, 0.001), 0.3)
	AnimationApplier.apply_instant(glass, "fade_out", 1.0)
	_check("fade_out done: hidden", glass.visible, false)
	var wall := _part(root3d, Vector3(4, 3, 0.3), Vector3(0, 1.5, 8))
	AnimationApplier.apply_instant(wall, "fade_out", 0.5)
	_check("opaque part mid-fade is alpha-blended", _mat(wall).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	AnimationApplier.apply_instant(wall, "fade_out", 0.0)
	_check("opaque part at rest leaves the transparent pass",
		[_mat(wall).transparency, _mat(wall).albedo_color.a], [BaseMaterial3D.TRANSPARENCY_DISABLED, 1.0])

	print("=== live playback ends where scrubbing does")
	var live_drop := _part(root3d, Vector3(1, 1, 1), Vector3(-5, 2, 0))
	var live_tree := _part(root3d, Vector3(1, 3, 1), Vector3(-8, 1.5, 0))
	var tw := create_tween().set_parallel(true)
	AnimationApplier.apply(tw, live_drop, "drop_in", 0.2)
	AnimationApplier.apply(tw, live_tree, "scale_up", 0.2)
	await create_timer(0.5).timeout
	_check("drop_in tween lands on its place", live_drop.position.distance_to(Vector3(-5, 2, 0)) < 1e-4, true)
	_check("scale_up tween ends at full size", live_tree.scale.distance_to(Vector3.ONE) < 1e-4, true)
	_check("drop_in tween ends opaque", _mat(live_drop).albedo_color.a, 1.0)

	print("\n" + ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
