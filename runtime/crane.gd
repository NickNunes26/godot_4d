class_name Crane
extends Node3D

## Verbose per-frame/per-swing diagnostics used while debugging the arm/hook/
## rope math. Off by default -- with Play routing through many install units
## per run, the every-30-frames block alone can produce thousands of lines.
## Flip to true only when actively debugging crane motion.
var debug_logging: bool = false

var _arm_tween:    Tween  = null
var _tracked_part: Node3D = null
var _track_arm:    bool   = false

var _arm_x_scale:                  float       = 1.0
var _arm_fwd_angle0:               float       = 0.0
var _arm_initial_global_transform: Transform3D = Transform3D.IDENTITY

var _hook_initial_world_y:   float   = 0.0
var _hook_height:            float   = 0.0
var _hook_initial_local_pos: Vector3 = Vector3.ZERO
var _track_initial_local_pos: Vector3 = Vector3.ZERO
var _rope_initial_scale_y:   float   = 1.0
var _rope_world_y_per_scale: float   = 1.0

var _dbg_frame:       int  = 0
var _swing_count:     int  = 0
var _track_arm_frame: int  = -1  # frame when _track_arm last became true

@onready var _arm:   Node3D = find_child("Arm",   true, false)
@onready var _track: Node3D = find_child("Track", true, false)
@onready var _hook:  Node3D = find_child("Hook",  true, false)
@onready var _rope:  Node3D = find_child("Rope",  true, false)

## Optional child marking this crane's material staging/laydown area (a
## multi-crane scene's equivalent of "where the truck drops materials for
## this crane specifically") -- searched recursively with owned: false to
## reach imported model nodes, same as Arm/Track/Hook/Rope above. Absent by
## default; see get_pickup_position()'s doc comment for the fallback when
## it's not present.
@onready var _pickup_zone: Node3D = find_child("PickupZone", true, false)

func _ready():
	if not _arm:
		push_warning("Crane: Arm not found"); return

	var forward := _arm.global_transform.basis.x
	_arm_x_scale                  = forward.length()
	_arm_fwd_angle0               = atan2(forward.x, forward.z)
	_arm_initial_global_transform = _arm.global_transform

	if _track:
		_track_initial_local_pos = _track.position
	else:
		push_warning("Crane: Track not found")

	if _hook:
		_hook_initial_world_y    = _hook.global_position.y
		_hook_initial_local_pos  = _hook.position
		_hook_height = _hook.global_position.y - _mesh_subtree_min_world_y(_hook)
		if debug_logging:
			print("  hook_height = ", _hook_height, "  (pivot to bottom, world units)")
	else:
		push_warning("Crane: Hook not found")

	if _rope and _rope.scale.y != 0.0:
		_rope_initial_scale_y = _rope.scale.y
		var mesh_height := 1.0
		if _rope is MeshInstance3D and _rope.mesh:
			mesh_height = _rope.mesh.get_aabb().size.y
		_rope_world_y_per_scale = mesh_height * (_rope.global_transform.basis.y.length() / _rope.scale.y)
	else:
		push_warning("Crane: Rope not found or has zero scale.y")

	if debug_logging:
		print(">>> CRANE READY")
		print("  arm.global_pos  = ", _arm.global_position)
		print("  arm.basis.x     = ", _arm.global_transform.basis.x, "  len=", _arm_x_scale)
		print("  arm.basis.y     = ", _arm.global_transform.basis.y)
		print("  arm.basis.z     = ", _arm.global_transform.basis.z)
		print("  arm.rotation.y  = ", _arm.rotation.y, "  (local, parent space)")
		print("  track.position  = ", str(_track.position) if _track else "n/a")
		print("  track.global_pos= ", str(_track.global_position) if _track else "n/a")
		print("  hook.global_pos = ", str(_hook.global_position) if _hook else "n/a")
		print("  arm_x_scale     = ", _arm_x_scale, "  (world units per local-X unit)")
		print("  rope_world_y_per_scale = ", _rope_world_y_per_scale)
		print("<<< CRANE READY")

func _process(_delta):
	if not _hook or not _tracked_part:
		return

	_dbg_frame += 1

	# --- Compute part's world AABB center and top ---
	var part_xz: Vector2
	var part_top_y: float
	if _tracked_part.has_meta("original_aabb"):
		var aabb: AABB = _tracked_part.get_meta("original_aabb")
		var world_center := _tracked_part.global_transform * aabb.get_center()
		part_xz = Vector2(world_center.x, world_center.z)
		var aabb_center := aabb.get_center()
		part_top_y = (_tracked_part.global_transform * Vector3(aabb_center.x, aabb.end.y, aabb_center.z)).y
	else:
		part_xz = Vector2(_tracked_part.global_position.x, _tracked_part.global_position.z)
		part_top_y = _tracked_part.global_position.y

	# --- Arm rotation ---
	if _track_arm and _arm:
		var dir := part_xz - Vector2(_arm.global_position.x, _arm.global_position.z)
		_set_arm_world_angle(atan2(dir.x, dir.y))

	# --- Track slide ---
	var dist_world := 0.0
	if _track and _arm:
		var arm_xz := Vector2(_arm.global_position.x, _arm.global_position.z)
		dist_world = arm_xz.distance_to(part_xz)
		var new_pos := _track.position
		new_pos.x = dist_world / _arm_x_scale
		_track.position = new_pos

	# --- Hook Y ---
	# hook_pivot_y: position hook so its BOTTOM (not pivot) aligns with part_top_y
	var rope_top_y   := _track.global_position.y if _track else _hook_initial_world_y
	var hook_pivot_y := minf(part_top_y + _hook_height, rope_top_y)
	var descent      := maxf(rope_top_y - hook_pivot_y, 0.0)

	var desired_world := Vector3(_hook.global_position.x, hook_pivot_y, _hook.global_position.z)
	_hook.position = _hook.get_parent().global_transform.affine_inverse() * desired_world

	if _rope:
		_rope.scale.y = maxf(descent / _rope_world_y_per_scale, _rope_initial_scale_y)

	# ================================================================
	# COMPREHENSIVE DIAGNOSTICS — every 30 frames (~0.5s at 60fps)
	# ================================================================
	if not debug_logging or _dbg_frame % 30 != 1:
		return

	var arm_xz_v2  := Vector2(_arm.global_position.x, _arm.global_position.z)
	var hook_xz    := Vector2(_hook.global_position.x, _hook.global_position.z)
	var track_xz   := Vector2(_track.global_position.x, _track.global_position.z) if _track else Vector2.ZERO

	# Actual arm forward direction in world XZ (after this frame's rotation)
	var arm_fwd_world    := Vector2(_arm.global_transform.basis.x.x, _arm.global_transform.basis.x.z).normalized()
	# Expected direction: from arm pivot to part
	var arm_to_part      := (part_xz - arm_xz_v2)
	var expected_fwd     := arm_to_part.normalized() if arm_to_part.length() > 0.001 else Vector2.ZERO
	# Angle error between actual arm forward and expected
	var fwd_angle_deg    := rad_to_deg(arm_fwd_world.angle_to(expected_fwd))

	# XZ error: hook vs part
	var hook_xz_err      := hook_xz - part_xz
	# XZ error: track vs part
	var track_xz_err     := track_xz - part_xz

	# Part's raw global_position (node pivot, not AABB center)
	var part_pivot_xz    := Vector2(_tracked_part.global_position.x, _tracked_part.global_position.z)

	print("==[F", _dbg_frame, " swing#", _swing_count, " part=", _tracked_part.name, "]==")
	print("  _track_arm         = ", _track_arm,
		"  (became true at frame ", _track_arm_frame, ")")
	print("  part_pivot_xz      = ", part_pivot_xz,    "  (node origin, not AABB center)")
	print("  part_xz (AABB ctr) = ", part_xz)
	print("  part_top_y         = ", snappedf(part_top_y, 0.001))
	print("  arm_pivot_xz       = ", arm_xz_v2)
	print("  dist_arm→part      = ", snappedf(dist_world, 0.001))
	print("  arm_fwd_actual     = ", arm_fwd_world,    "  (world XZ, normalized)")
	print("  arm_fwd_expected   = ", expected_fwd,     "  (toward part)")
	print("  arm_fwd_angle_err  = ", snappedf(fwd_angle_deg, 0.01), " deg  ← 0 = perfect aim")
	print("  track_xz           = ", track_xz)
	print("  track_xz_err       = ", track_xz_err,     "  ← should be ~(0,0)")
	print("  hook_xz            = ", hook_xz)
	print("  hook_xz_err        = ", hook_xz_err,      "  ← should be ~(0,0)")
	print("  hook_world_y       = ", snappedf(_hook.global_position.y, 0.001),
		"  pivot_target=", snappedf(hook_pivot_y, 0.001),
		"  hook_bottom=", snappedf(_hook.global_position.y - _hook_height, 0.001),
		"  part_top=", snappedf(part_top_y, 0.001))
	var arm_fwd_angle := atan2(_arm.global_transform.basis.x.x, _arm.global_transform.basis.x.z)
	print("  arm_fwd_angle      = ", snappedf(arm_fwd_angle, 0.0001), "  (world, atan2 of basis.x)")
	print("  arm.basis.x        = ", _arm.global_transform.basis.x,
		"  (changes each frame as arm rotates)")
	print("  track.position.x   = ", snappedf(_track.position.x if _track else 0.0, 0.1))

func _set_arm_world_angle(angle: float):
	var delta := angle - _arm_fwd_angle0
	var new_global := _arm_initial_global_transform
	new_global.basis = Basis(Vector3.UP, delta) * _arm_initial_global_transform.basis
	_arm.global_transform = new_global

## Where this crane's materials appear before being lifted -- called by
## ConstructionSchedule (once per install unit assigned to this crane, at
## _init() time, not per frame) to resolve both the crane.swing() pickup
## argument and the part's own "ground start" staging position
## (SequenceManager/AnimationApplier position the invisible part there before
## its own install animation begins). If PickupZone is present, every unit
## this crane services shares that single fixed world point -- perfectly
## fine visually since a staged-but-not-yet-installed part is invisible/
## zero-scale (see SequenceManager.initialize_parts()) until its own turn, so
## multiple parts coinciding there at once is imperceptible. Falls back to
## target_pos + (15, 0, 0) -- the single-crane behavior this codebase shipped
## with before multi-crane support -- when no PickupZone child exists, so an
## existing crane scene with no PickupZone node keeps working unchanged.
func get_pickup_position(target_pos: Vector3) -> Vector3:
	if _pickup_zone:
		return _pickup_zone.global_position
	return target_pos + Vector3(15.0, 0, 0)

func swing(pickup: Vector3, _target: Vector3, lift_dur: float, _slide_dur: float, tracked_part: Node3D):
	if not _arm:
		return
	_swing_count += 1
	var tween_was_running: bool = _arm_tween != null and _arm_tween.is_running()
	var old_part: String = str(_tracked_part.name) if _tracked_part else "none"
	_tracked_part = tracked_part
	_track_arm = false
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween()
	var dir_pickup := Vector2(pickup.x - _arm.global_position.x, pickup.z - _arm.global_position.z)
	var target_fwd   := atan2(dir_pickup.x, dir_pickup.y)
	var current_fwd  := atan2(_arm.global_transform.basis.x.x, _arm.global_transform.basis.x.z)
	var angle_diff   := fmod(target_fwd - current_fwd + PI, TAU) - PI
	_arm_tween.tween_method(_set_arm_world_angle, current_fwd, current_fwd + angle_diff, lift_dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_arm_tween.tween_callback(func():
		_track_arm = true
		_track_arm_frame = _dbg_frame
		if debug_logging:
			print("*** _track_arm=TRUE  frame=", _dbg_frame,
				"  swing#=", _swing_count, "  part=", str(_tracked_part.name) if _tracked_part else "none")
	)
	if debug_logging:
		print(">>> swing#", _swing_count,
			"  prev_part=", old_part,
			"  new_part=", tracked_part.name,
			"  tween_was_running=", tween_was_running,
			"  pickup=", pickup,
			"  lift_dur=", lift_dur,
			"  frame=", _dbg_frame)

func retract(dur: float = 2.0):
	if not _arm:
		return
	_tracked_part = null
	_track_arm    = false
	if _arm_tween:
		_arm_tween.kill()
	var t := create_tween().set_parallel(true)
	var current_fwd := atan2(_arm.global_transform.basis.x.x, _arm.global_transform.basis.x.z)
	var angle_diff  := fmod(_arm_fwd_angle0 - current_fwd + PI, TAU) - PI
	t.tween_method(_set_arm_world_angle, current_fwd, current_fwd + angle_diff, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _track:
		t.tween_property(_track, "position", _track_initial_local_pos, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _hook:
		t.tween_property(_hook, "position", _hook_initial_local_pos, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _rope:
		t.tween_property(_rope, "scale:y", _rope_initial_scale_y, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _mesh_subtree_min_world_y(root: Node3D) -> float:
	var min_y := root.global_position.y
	var nodes: Array = [root] + root.find_children("*", "MeshInstance3D", true, false)
	for n in nodes:
		if not (n is MeshInstance3D) or not (n as MeshInstance3D).mesh:
			continue
		var aabb: AABB = (n as MeshInstance3D).mesh.get_aabb()
		var tf: Transform3D = (n as Node3D).global_transform
		for xi in [aabb.position.x, aabb.end.x]:
			for yi in [aabb.position.y, aabb.end.y]:
				for zi in [aabb.position.z, aabb.end.z]:
					min_y = minf(min_y, (tf * Vector3(xi, yi, zi)).y)
	return min_y
