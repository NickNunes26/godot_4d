## Stateless animation library shared by live playback and instant-apply
## (scrubbing). Every method reads its start/end state from part metas set
## by SequenceManager.initialize_parts() (original_pos, original_scale,
## original_transform, original_aabb) -- never from the part's live
## transform -- so playing, scrubbing, and re-scrubbing all agree.
class_name AnimationApplier

## Every anim_type the match statements below (and apply_instant()'s below
## that) actually handle -- the single source of truth for what's a valid
## "type" value in construction_steps.json, so the Phase 3 editor dock's
## animation-type dropdown (timeline_dock.gd) can populate itself from this
## instead of hardcoding a second copy that could drift out of sync.
const TYPES: Array[String] = [
	"scale_up", "drop_in", "rise_up", "sink_down", "fill_up", "build_up", "fade_in", "fade_out", "install"
]

## "formwork" is deliberately NOT in TYPES, even though apply_instant() handles
## it. TYPES is what the dock's type dropdown offers for an *element*, and
## formwork is not something an element can be -- it is the lifecycle
## ConstructionSchedule assigns to the panels FormworkBuilder generates. Listing
## it would let someone set a pier's type to "formwork", which means nothing and
## would read its phase meta off a part that has none.
##
## What an author does choose is how panels assemble and how they come off, via
## formwork.type / formwork.strip_type -- and those are ordinary TYPES entries,
## composed by _formwork_instant() rather than reimplemented. See 07_FORMWORK.md.
const FORMWORK_TYPE := "formwork"
## Set per panel by ConstructionSchedule._schedule_formwork(): where the three
## phases sit inside that panel's own 0-1 window, plus which animation each end
## uses. Per-part because panels assemble staggered but strip together, so no
## two panels share the same boundaries.
const FORMWORK_PHASES_META := "formwork_phases"

## fill_up's concrete-pour stream. Its drop height, stream width and grain are
## all derived from the element being poured -- elements run from well under a metre to over twenty, and a camera framing one is much
## further away than a camera framing the other, so a single fixed size reads
## wrong at one end or the other. The clamps keep both extremes sane: below
## POUR_FALL_MIN a stream is too short to read as falling concrete at all,
## above POUR_FALL_MAX it reads as debris dropped from the sky rather than
## placed from a chute. POUR_SPEED/POUR_GRAVITY are what the particle lifetime
## is solved against -- see fire_fill_up_particles().
const POUR_FALL_MIN := 1.5
const POUR_FALL_MAX := 5.0
const POUR_SPEED := 2.0
const POUR_GRAVITY := 9.8
## How many grain-radii long each particle is stretched along its fall. The
## stream is what sells this as a fluid rather than as falling gravel: enough
## particles that the column reads as continuous, each one smeared along its
## own velocity so consecutive particles overlap into a stream instead of
## resolving as separate balls.
const POUR_STREAK := 3.0
const POUR_AMOUNT := 800
## Concrete arriving at the surface spreads; without this the stream just
## stops dead at a point, which is the single most artificial-looking part of
## a pour. Rides on the emitter, so it stays at the fill surface for free.
const POUR_SPLASH_AMOUNT := 220

## drop_in lowers a piece onto its place from just above it -- the last few
## metres of a crane lift, which is the part of one anybody watches. The height
## follows the piece: DROP_CLEARANCE plus DROP_PER_METRE times its own height,
## kept within [DROP_MIN, DROP_MAX]. It used to fall from a fixed 15 m with a
## cubic ease-out, i.e. fastest at the top and appearing out of nothing in
## mid-air, which read as things thrown at the building rather than set on it.
const DROP_MIN := 2.5
const DROP_MAX := 8.0
const DROP_PER_METRE := 1.5
const DROP_CLEARANCE := 1.5
## Share of a drop_in spent fading in, so a piece never pops into existence
## above the building.
const DROP_FADE := 0.2

## Per material, what its alpha and transparency mode were before any animation
## touched them. Fades scale *that* alpha instead of assuming 1.0, so glass
## (alpha 0.3, alpha-blended) ends a fade_in as glass, not as an opaque pane.
const _ORIGINAL_ALPHA_META := "_c4d_original_alpha"
const _ORIGINAL_TRANSPARENCY_META := "_c4d_original_transparency"

## Builds a tween that plays anim_type on part over dur seconds, starting
## from now. Used for live playback (crane swings, particle bursts).
static func apply(pt: Tween, part: Node3D, anim_type: String, dur: float):
	match anim_type:
		"scale_up":  _scale_up(pt, part, dur)
		"drop_in":   _drop_in(pt, part, dur)
		"rise_up":   _rise_up(pt, part, dur)
		"sink_down": _sink_down(pt, part, dur)
		"fill_up":   _fill_up(pt, part, dur)
		"build_up":  _grow_from_base(pt, part, dur)
		"fade_in":   _fade_in(pt, part, dur)
		"fade_out":  _fade_out(pt, part, dur)
		"install":   _install(pt, part, dur)

## scale_up, drop_in and the fades play by driving their instant functions, so
## live playback and scrubbing can never disagree about what they look like.
static func _scale_up(pt: Tween, part: Node3D, dur: float):
	pt.tween_method(func(p: float): AnimationApplier._scale_up_instant(part, p), 0.0, 1.0, dur)

static func _drop_in(pt: Tween, part: Node3D, dur: float):
	pt.tween_method(func(p: float): AnimationApplier._drop_in_instant(part, p), 0.0, 1.0, dur)

static func _rise_up(pt: Tween, part: Node3D, dur: float):
	var orig_pos = part.get_meta("original_pos")
	part.visible = true
	part.scale = part.get_meta("original_scale")
	part.position = orig_pos - Vector3(0, 10, 0)
	pt.tween_property(part, "position", orig_pos, dur)\
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func _sink_down(pt: Tween, part: Node3D, dur: float):
	var orig_pos = part.get_meta("original_pos")
	pt.tween_property(part, "position", orig_pos - Vector3(0, 10, 0), dur)\
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	pt.tween_callback(func(): part.visible = false)

static func _fill_up(pt: Tween, part: Node3D, dur: float):
	_grow_from_base(pt, part, dur)
	AnimationApplier.fire_fill_up_particles(part, dur, {})

## fill_up's growth without the pour: the element comes up from its lowest
## point, the way a wall goes up course by course. build_up is exactly this,
## and exists because rise_up -- the only other "comes up" type -- moves the
## *whole* element up from 10 m below, i.e. through the slab and foundations it
## is built on.
static func _grow_from_base(pt: Tween, part: Node3D, dur: float):
	pt.tween_method(func(p: float): AnimationApplier._fill_up_instant(part, p), 0.0, 1.0, dur)

## The root "pour_stream" block, or {} -- sibling of formwork_defaults, and
## placed there for the same reason: it describes how the *project* renders a
## pour, not one task. See 08_POUR_STREAM.md.
##
## **Off by default**, which deliberately breaks this project's usual rule that a
## new feature leaves an untouched JSON behaving exactly as before. The feedback
## was about the default, not about one project: leaving the stream on would keep
## the disliked thing as what you get for doing nothing, and make "make it
## optional" a job that is never finished. Absent block -> no stream, and no
## particle nodes built at all.
static func pour_stream_config(sequence_data: Dictionary) -> Dictionary:
	var raw = sequence_data.get("pour_stream")
	if raw == null:
		return {}
	if not (raw is Dictionary):
		push_warning("AnimationApplier: 'pour_stream' is not a dictionary, ignoring")
		return {}
	if raw.get("enabled", true) == false:
		return {}
	# {} is this function's "no stream" sentinel, which collides with a project
	# that opted in explicitly and supplied no fields -- "pour_stream": {} would
	# otherwise read as off, which is precisely the trap 07_FORMWORK.md decision
	# 10 records for the formwork block. Same resolution: materialise the flag
	# rather than introduce a second sentinel.
	if raw.is_empty():
		return {"enabled": true}
	return raw

## One numeric pour_stream field, falling back when absent or non-numeric.
## `derive_on_zero` marks the two fields (grain, fall) where 0 means "work it out
## from the element" rather than "use zero" -- that derivation is the pre-tuning
## behaviour and stays the default, because elements run from well under a metre to over twenty and one fixed size reads wrong at one end.
static func _pour_number(cfg: Dictionary, key: String, fallback: float) -> float:
	var v = cfg.get(key)
	if v is float or v is int:
		return float(v)
	return fallback

## Fires the concrete-pour stream for a fill_up action, over dur seconds.
## Live-play only -- apply_instant() deliberately skips it, since a one-shot
## burst makes no sense at an arbitrary scrub position.
##
## The stream is aimed to *land on* the concrete rather than to be stopped by
## it. The emitter sits POUR_FALL_* metres above the fill surface and rises
## with it (the fill is linear in progress, so one linear tween tracks it
## exactly), and the particle lifetime is solved from that drop height so a
## particle's last frame is at the surface. Everything is sized from the part
## itself: elements run from well under a metre to over twenty, so a single hardcoded drop height and grain size cannot read
## correctly at both ends.
##
## Previously this emitted 8 m above the part's *centre* with a fixed 1.2 s
## lifetime -- which carries a particle 14-19 m under default gravity, i.e.
## straight through the element and out the bottom (measured on a real model:
## a 1.8 m tall element, particles dying ~5 m below its base), leaving the pour visibly
## clipping through the thing it was pouring. The GPUParticlesCollisionBox3D
## below was meant to catch that and demonstrably did not, so nothing here
## depends on it any more; it is kept only as a backstop for the case where
## playback speed changes mid-pour and the concrete outruns the emitter.
static func fire_fill_up_particles(part: Node3D, dur: float = 1.0, cfg: Dictionary = {}) -> void:
	# Nothing is built when the stream is off -- not built and hidden. A
	# GPUParticles3D plus a collision box per pour is real per-frame cost for
	# something invisible, and TimelineController fires this once per pour.
	if cfg.is_empty():
		return
	var basis: Basis = part.get_meta("original_transform").basis
	var aabb: AABB = part.get_meta("original_aabb")
	var center_local: Vector3 = aabb.get_center()

	# Where the fill surface starts and ends: the part's lowest and highest
	# points as it stands now (a hinged part may be standing up), straight up in
	# world space like the level _fill_up_instant() raises; over its centre. In
	# the parent's space, where the emitter goes.
	var span_y := fill_extent(part)
	var centre_w: Vector3 = part.global_transform * center_local
	var to_parent: Transform3D = (part.get_parent() as Node3D).global_transform.affine_inverse() if part.get_parent() is Node3D else Transform3D.IDENTITY
	var bottom: Vector3 = to_parent * Vector3(centre_w.x, span_y.x, centre_w.z)
	var top: Vector3 = to_parent * Vector3(centre_w.x, span_y.y, centre_w.z)

	# Sized off the element's overall span, not just the height being filled: a
	# 10 m footing only 1.8 m thick is viewed from far enough away that a drop
	# scaled to its thickness alone is barely visible.
	var world_size: Vector3 = (basis.get_scale() * aabb.size).abs()
	var span: float = maxf(world_size.x, maxf(world_size.y, world_size.z))
	var footprint: float = minf(world_size.x, world_size.z)
	# 0 means "derive from the element", which is the pre-tuning behaviour and
	# stays the default; any other value is an absolute world-metre override,
	# which is what someone tuning by eye on one element actually wants.
	var fall: float = _pour_number(cfg, "fall", 0.0)
	if fall <= 0.0:
		fall = clampf(span * 0.4, POUR_FALL_MIN, POUR_FALL_MAX)
	var grain: float = _pour_number(cfg, "grain", 0.0)
	if grain <= 0.0:
		grain = clampf(footprint * 0.025, 0.07, 0.22)
	var spray: float = clampf(footprint * 0.09, 0.25, 1.0)
	var speed: float = maxf(_pour_number(cfg, "speed", POUR_SPEED), 0.0)
	var gravity: float = maxf(_pour_number(cfg, "gravity", POUR_GRAVITY), 0.01)
	var streak_mult: float = maxf(_pour_number(cfg, "streak", POUR_STREAK), 0.01)

	# Solve `drop` = v0*t + g*t^2/2 for t: a particle's lifetime then ends
	# exactly at the surface. Velocity is a single value rather than a range so
	# no particle can overshoot the surface it was solved against. The solve is
	# against `fall` minus half a streak, because a velocity-aligned particle is
	# drawn smeared around its own position -- it is the streak's leading tip,
	# not its centre, that has to land on the concrete.
	var streak: float = grain * streak_mult
	var drop: float = maxf(fall - streak, 0.3)
	var lifetime: float = (-speed + sqrt(speed * speed + 2.0 * gravity * drop)) / gravity

	var p_sys = GPUParticles3D.new()
	var p_mat = ParticleProcessMaterial.new()
	# A flattened box rather than a sphere: concrete leaves a chute as a column
	# with a cross-section, not as a ball of independently falling lumps.
	p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p_mat.emission_box_extents = Vector3(spray, spray * 0.15, spray)
	p_mat.direction = Vector3(0, -1, 0)
	# A slight fan, so the streaks aren't all exactly parallel and the column
	# doesn't resolve into vertical stripes. Kept small: at 8 degrees a particle
	# still covers 99% of the solved drop vertically.
	p_mat.spread = maxf(_pour_number(cfg, "spread_deg", 8.0), 0.0)
	p_mat.gravity = Vector3(0, -gravity, 0)
	p_mat.initial_velocity_min = speed
	p_mat.initial_velocity_max = speed
	# Size and shade variation, so the column doesn't resolve into a grid of
	# identical spheres once it is dense enough to read as a mass.
	p_mat.scale_min = 0.6
	p_mat.scale_max = 1.35
	p_mat.color_initial_ramp = _pour_shade_ramp()
	p_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT if cfg.get("collide", true) != false else ParticleProcessMaterial.COLLISION_DISABLED
	p_sys.process_material = p_mat

	p_sys.draw_pass_1 = _pour_grain_mesh(grain, streak_mult)
	# Align each particle's Y axis to its velocity so the elongated mesh smears
	# along the fall rather than pointing a fixed direction.
	p_sys.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY

	p_sys.amount = maxi(int(_pour_number(cfg, "amount", POUR_AMOUNT)), 1)
	p_sys.lifetime = lifetime
	p_sys.collision_base_size = grain
	# Default is 30, which visibly steps against a 60 fps recording; 0 means
	# simulate at the render frame rate.
	p_sys.fixed_fps = 0
	# Explicit, since the default box is sized for a particle system that
	# doesn't move -- this one is tweened upward as the pour rises.
	var half_w: float = spray + grain + fall * 0.3
	p_sys.visibility_aabb = AABB(
		Vector3(-half_w, -fall - streak, -half_w),
		Vector3(half_w * 2.0, fall + streak * 2.0, half_w * 2.0))
	p_sys.add_to_group("fill_up_particles")

	# Start above the empty form; the tween below carries it up with the fill.
	p_sys.position = Vector3(top.x, bottom.y + fall, top.z)
	part.get_parent().add_child(p_sys)

	# The landing spread, parented to the emitter so it tracks the surface with
	# no bookkeeping of its own -- it sits exactly `fall` below, which is where
	# the stream's tip is by construction.
	var splash_amount: int = maxi(int(_pour_number(cfg, "splash_amount", POUR_SPLASH_AMOUNT)), 0)
	var splash: GPUParticles3D = null
	if splash_amount > 0:
		splash = _pour_splash(grain, spray, footprint, splash_amount)
		splash.position = Vector3(0, -fall + grain, 0)
		p_sys.add_child(splash)

	var p_col = GPUParticlesCollisionBox3D.new()
	p_col.size = aabb.size
	p_col.position = center_local
	p_col.add_to_group("fill_up_particles")
	part.add_child(p_col)

	var pour_pt = part.get_tree().create_tween()
	pour_pt.tween_property(p_sys, "position:y", top.y + fall, maxf(dur, 0.01))\
	  .set_trans(Tween.TRANS_LINEAR)
	pour_pt.tween_callback(func():
		if is_instance_valid(p_sys):
			p_sys.emitting = false
			if is_instance_valid(splash):
				splash.emitting = false
			var end_pt = part.get_tree().create_tween()
			end_pt.tween_interval(maxf(p_sys.lifetime, splash.lifetime if is_instance_valid(splash) else 0.0))
			end_pt.tween_callback(func():
				if is_instance_valid(p_sys): p_sys.queue_free()
				if is_instance_valid(p_col): p_col.queue_free()
			)
		elif is_instance_valid(p_col):
			p_col.queue_free()
	)

## The concrete grain: a sphere stretched along Y, which becomes the fall
## direction once the emitter aligns particles to their velocity.
static func _pour_grain_mesh(grain: float, streak: float) -> Mesh:
	var mesh = SphereMesh.new()
	mesh.radius = grain
	mesh.height = grain * 2.0 * streak
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.58, 0.56)
	mat.roughness = 0.85
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	return mesh

## Per-particle shade variation. color_initial_ramp samples this at a random
## point per particle, so it is a palette, not a gradient over lifetime -- wet
## concrete is not one flat grey.
static func _pour_shade_ramp() -> GradientTexture1D:
	var grad = Gradient.new()
	grad.set_color(0, Color(0.72, 0.72, 0.70))
	grad.set_color(1, Color(0.42, 0.42, 0.41))
	var tex = GradientTexture1D.new()
	tex.gradient = grad
	return tex

## The spread where the stream meets the concrete. Zero gravity and an upward
## bias: these must never drift below the surface they are landing on, which is
## the one thing this whole function exists to guarantee.
static func _pour_splash(grain: float, spray: float, footprint: float, amount: int) -> GPUParticles3D:
	var sys = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = spray * 0.6
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 88.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = footprint * 0.12
	mat.initial_velocity_max = footprint * 0.35
	mat.damping_min = 1.0
	mat.damping_max = 2.5
	mat.scale_min = 0.35
	mat.scale_max = 0.9
	mat.color_initial_ramp = _pour_shade_ramp()
	sys.process_material = mat
	sys.draw_pass_1 = _pour_grain_mesh(grain, 1.0)
	sys.amount = amount
	sys.lifetime = 0.45
	sys.fixed_fps = 0
	var reach: float = maxf(footprint * 0.3, spray)
	sys.visibility_aabb = AABB(
		Vector3(-reach, -grain, -reach), Vector3(reach * 2.0, reach, reach * 2.0))
	sys.add_to_group("fill_up_particles")
	return sys

static func _fade_in(pt: Tween, part: Node3D, dur: float):
	pt.tween_method(func(p: float): AnimationApplier._fade_in_instant(part, p), 0.0, 1.0, dur)

static func _fade_out(pt: Tween, part: Node3D, dur: float):
	pt.tween_method(func(p: float): AnimationApplier._fade_out_instant(part, p), 0.0, 1.0, dur)

static func _install(pt: Tween, part: Node3D, dur: float):
	var orig_pos = part.get_meta("original_pos")
	part.visible = true
	part.scale = part.get_meta("original_scale")
	var ground_start = Vector3(orig_pos.x + 15, 0, orig_pos.z)
	part.position = ground_start
	var hover_height = orig_pos.y + 5.0
	pt.tween_property(part, "position", Vector3(ground_start.x, hover_height, ground_start.z), dur * 0.3)\
	  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pt.tween_property(part, "position", Vector3(orig_pos.x, hover_height, orig_pos.z), dur * 0.4)\
	  .set_trans(Tween.TRANS_SINE)
	pt.tween_property(part, "position", orig_pos, dur * 0.3)\
	  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ---------------------------------------------------------------------------
# Instant-apply (Milestone 2): set a part's state at a given progress [0, 1]
# without creating a Tween. Uses Tween.interpolate_value() so easing math is
# identical to the live-play methods above. Every method reads from part
# metas only, matching the live-play convention.
# ---------------------------------------------------------------------------

## Sets part directly to its state at progress (0-1) through anim_type, with
## no tween and no side effects that only make sense during live playback
## (e.g. fill_up's particle burst, or crane swings -- those are handled by
## TimelineController._detect_install_actions(), not here). Used by
## TimelineController.scrub_to() for both manual scrubbing and Play mode.
static func apply_instant(part: Node3D, anim_type: String, progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	match anim_type:
		"scale_up":  _scale_up_instant(part, progress)
		"drop_in":   _drop_in_instant(part, progress)
		"rise_up":   _rise_up_instant(part, progress)
		"sink_down": _sink_down_instant(part, progress)
		"fill_up":   _fill_up_instant(part, progress)
		"build_up":  _fill_up_instant(part, progress)
		"fade_in":   _fade_in_instant(part, progress)
		"fade_out":  _fade_out_instant(part, progress)
		"install":   _install_instant(part, progress)
		FORMWORK_TYPE: _formwork_instant(part, progress)

## apply_instant() for a part in a "rotate" group: its own animation, then the
## group's swing on top -- a rotation by hinge.angle about hinge.axis through
## hinge.pivot, all world space (ConstructionSchedule.get_part_states() gives
## the hinge). The part's own rotation is put back first: every animation sets
## position and scale and keeps whatever rotation the node has, so without the
## reset each frame's swing would pile onto the last one's.
static func apply_instant_hinged(part: Node3D, anim_type: String, progress: float, hinge: Dictionary) -> void:
	reset_rotation(part)
	apply_instant(part, anim_type, progress)
	var angle: float = hinge.get("angle", 0.0)
	if is_zero_approx(angle):
		return
	var pivot: Vector3 = hinge.pivot
	var turn := Basis(hinge.axis, angle)
	var swing := Transform3D(turn, pivot - turn * pivot)
	var parent := part.get_parent() as Node3D
	var to_world := parent.global_transform if parent else Transform3D.IDENTITY
	part.transform = to_world.affine_inverse() * swing * to_world * part.transform
	# A pour's level is straight up from where the part stands *now*.
	if anim_type in ["fill_up", "build_up"]:
		_update_fill(part)

## Puts a part's own rotation back, keeping its position and scale -- the
## rotation SequenceManager.initialize_parts() recorded ("original_quaternion"),
## else the one in "original_transform".
static func reset_rotation(part: Node3D) -> void:
	var q: Quaternion
	if part.has_meta("original_quaternion"):
		q = part.get_meta("original_quaternion")
	elif part.has_meta("original_transform"):
		var world: Transform3D = part.get_meta("original_transform")
		var parent := part.get_parent() as Node3D
		if parent:
			world = parent.global_transform.affine_inverse() * world
		q = world.basis.get_rotation_quaternion()
	else:
		return
	part.transform = Transform3D(Basis(q) * Basis.from_scale(part.scale), part.position)

## Formwork's assemble -> hold -> strip lifecycle, mapped onto the single 0-1
## progress window every other animation uses.
##
## Three phases in one progress value is exactly what _install_instant() already
## does with lift/slide/lower, and doing it here is what keeps
## ConstructionSchedule._part_schedules at one window per part -- the alternative
## was making it multi-phase, which would have modified get_part_states(), the
## single source of truth both scrubbing and Play route through, for one
## feature's benefit. See 07_FORMWORK.md, decision 2.
##
## The phases compose existing animations rather than reimplementing them: the
## meta names an assemble type and a strip type, both ordinary TYPES entries, and
## this remaps progress into each one's own 0-1 range.
##
## **Each phase re-establishes the other's boundary state first**, which is not
## redundant -- it is what makes scrubbing backwards correct. _scale_up_instant()
## never touches material alpha, so scrubbing back from a fade_out strip into the
## hold or assemble phase would otherwise leave a panel stuck at alpha 0:
## fully assembled, correctly positioned, and invisible. Applying the strip type
## at progress 0 ("present, not yet stripped") first resets whatever the strip
## owns; applying the assemble type at 1 before a strip does the same in reverse.
static func _formwork_instant(part: Node3D, progress: float) -> void:
	var phases: Dictionary = part.get_meta(FORMWORK_PHASES_META, {})
	var assemble_end: float = phases.get("assemble_end", 1.0)
	var strip_start: float = phases.get("strip_start", 1.0)
	var assemble_type: String = phases.get("assemble_type", "scale_up")
	var strip_type: String = phases.get("strip_type", "fade_out")
	# A panel whose meta named "formwork" for either end would recurse forever.
	# Can't happen from ConstructionSchedule, which never writes it -- but this
	# is read off a node meta, so it is worth not trusting.
	if assemble_type == FORMWORK_TYPE:
		assemble_type = "scale_up"
	if strip_type == FORMWORK_TYPE:
		strip_type = "fade_out"

	if progress < assemble_end and assemble_end > 0.0:
		apply_instant(part, strip_type, 0.0)
		apply_instant(part, assemble_type, progress / assemble_end)
		return
	if progress < strip_start or strip_start >= 1.0:
		# Hold: assembled and standing, waiting for the pour and any cure.
		apply_instant(part, strip_type, 0.0)
		return
	apply_instant(part, assemble_type, 1.0)
	apply_instant(part, strip_type, (progress - strip_start) / (1.0 - strip_start))

## Grows from the middle of its own base, the way a plant comes up out of the
## ground: uniform scale, base pinned, decelerating, never larger than finished.
##
## It used to scale about the node origin with TRANS_BACK -- i.e. from the
## part's *centre* (IFC parts are re-origined to their bounding-box centre), so
## everything inflated in mid-air, and overshot to ~110 % before settling back,
## a cartoon "pop" no construction element does.
static func _scale_up_instant(part: Node3D, progress: float) -> void:
	var orig_pos: Vector3 = part.get_meta("original_pos")
	var orig_scale: Vector3 = part.get_meta("original_scale")
	if progress <= 0.0:
		part.visible = false
		part.scale = Vector3.ZERO
		part.position = orig_pos
		return
	part.visible = true
	if progress >= 1.0:
		part.scale = orig_scale
		part.position = orig_pos
		return
	var k: float = Tween.interpolate_value(0.0, 1.0, progress, 1.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	part.scale = orig_scale * k
	part.position = orig_pos + _base_pin_offset(part, orig_scale, orig_scale * k)

## How far to move a part's origin, in its parent's space, so that the middle of
## its base stays where it is at full size while its scale is `now` instead of
## `full`. The rotation comes from the recorded original_transform rather than
## the live node: at scale zero a basis has no rotation left to read.
static func _base_pin_offset(part: Node3D, full: Vector3, now: Vector3) -> Vector3:
	if not part.has_meta("original_aabb"):
		return Vector3.ZERO
	var box: AABB = part.get_meta("original_aabb")
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var rot := Basis()
	if part.has_meta("original_transform"):
		rot = (part.get_meta("original_transform") as Transform3D).basis
		var parent := part.get_parent() as Node3D
		if parent:
			rot = parent.global_transform.basis.inverse() * rot
		rot = rot.orthonormalized()
	return rot * ((full - now) * base)

## Lowered onto its place from drop_height() above it: fades in over the first
## DROP_FADE of the window, then a controlled descent that eases in and eases
## out -- slow off the hook, steady, slow again as it is set down.
static func _drop_in_instant(part: Node3D, progress: float) -> void:
	var orig_pos: Vector3 = part.get_meta("original_pos")
	part.scale = part.get_meta("original_scale")
	var height := drop_height(part)
	if progress <= 0.0:
		part.visible = false
		part.position = orig_pos + Vector3(0, height, 0)
		_set_opacity(part, 1.0)
		return
	part.visible = true
	if progress >= 1.0:
		part.position = orig_pos
		_set_opacity(part, 1.0)
		return
	var lowered: float = Tween.interpolate_value(0.0, 1.0, progress, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	part.position = orig_pos + Vector3(0, height * (1.0 - lowered), 0)
	_set_opacity(part, clampf(progress / DROP_FADE, 0.0, 1.0))

## How far above its place a drop_in starts, in metres: scaled to the piece's
## own height so a cornice stone and a roof truss both read, clamped so neither
## starts implausibly close or out of frame.
static func drop_height(part: Node3D) -> float:
	var h := 0.0
	if part.has_meta("original_aabb"):
		var basis := Basis()
		if part.has_meta("original_transform"):
			basis = (part.get_meta("original_transform") as Transform3D).basis
		h = (Transform3D(basis, Vector3.ZERO) * (part.get_meta("original_aabb") as AABB)).size.y
	return clampf(DROP_CLEARANCE + DROP_PER_METRE * h, DROP_MIN, DROP_MAX)

static func _rise_up_instant(part: Node3D, progress: float) -> void:
	var orig_pos: Vector3 = part.get_meta("original_pos")
	part.scale = part.get_meta("original_scale")
	var start_y = orig_pos.y - 10.0
	if progress <= 0.0:
		part.visible = false
		part.position = Vector3(orig_pos.x, start_y, orig_pos.z)
		return
	part.visible = true
	if progress >= 1.0:
		part.position = orig_pos
		return
	var y = Tween.interpolate_value(start_y, orig_pos.y - start_y, progress, 1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	part.position = Vector3(orig_pos.x, y, orig_pos.z)

static func _sink_down_instant(part: Node3D, progress: float) -> void:
	var orig_pos: Vector3 = part.get_meta("original_pos")
	part.scale = part.get_meta("original_scale")
	if progress <= 0.0:
		part.visible = true
		part.position = orig_pos
		return
	if progress >= 1.0:
		part.visible = false
		part.position = orig_pos - Vector3(0, 10, 0)
		return
	part.visible = true
	var y = Tween.interpolate_value(orig_pos.y, -10.0, progress, 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
	part.position = Vector3(orig_pos.x, y, orig_pos.z)

## The pour: the part stays whole, in place and at its own size, and is drawn
## only up to a level that rises in world +Y from its lowest point to its
## highest -- whatever its orientation, so a tilted or standing dovela fills
## from the bottom like concrete in a form, never along its own axis. The cut
## is closed by a flat top at the level (core/fill_clip.gdshader). It used to
## scale the part along its *local* Y from a sliver, which on anything not
## upright read as a squashed piece being stretched sideways.
##
## The level is measured on the part as it stands: apply_instant_hinged()
## measures it again after the swing (_update_fill()).
static func _fill_up_instant(part: Node3D, progress: float) -> void:
	part.scale = part.get_meta("original_scale")
	part.position = part.get_meta("original_pos")
	part.visible = progress > 0.0
	part.set_meta(_FILL_META, progress)
	_update_fill(part)
	# Particle burst is a live-only side effect; skipped here.

const _FILL_META := "_c4d_fill_progress"
const _FILL_ORIGINAL_META := "_c4d_fill_original"
const _FILL_POINTS_META := "_c4d_fill_points"
const _FILL_WELD_META := "_c4d_fill_weld"
const FILL_SHADER := preload("res://addons/construction_4d_tool/core/fill_clip.gdshader")

## Puts the clip on while the part is part-filled (0 < progress < 1) -- its
## materials swapped for fill_clip ones, the level set from its current pose --
## and takes it off otherwise, the part's own materials back.
static func _update_fill(part: Node3D) -> void:
	var progress: float = part.get_meta(_FILL_META, 1.0)
	var meshes := _fade_targets(part)
	if progress <= 0.0 or progress >= 1.0:
		for m in meshes:
			var cap := m.get_node_or_null(POUR_CAP) as MeshInstance3D
			if cap:
				m.remove_child(cap)
				cap.free()
			if m.has_meta(_FILL_ORIGINAL_META):
				var originals: Array = m.get_meta(_FILL_ORIGINAL_META)
				for s in mini(originals.size(), m.get_surface_override_material_count()):
					m.set_surface_override_material(s, originals[s])
				m.remove_meta(_FILL_ORIGINAL_META)
		return
	var span_y := fill_extent(part)
	var level := lerpf(span_y.x, span_y.y, progress)
	for m in meshes:
		if not m.has_meta(_FILL_ORIGINAL_META):
			# The cap needs outward-front faces (MeshPrep); once per mesh.
			m.mesh = MeshPrep.outward(m.mesh)
			var originals: Array = []
			for s in m.get_surface_override_material_count():
				originals.append(m.get_surface_override_material(s))
				m.set_surface_override_material(s, _fill_material(m.get_active_material(s)))
			m.set_meta(_FILL_ORIGINAL_META, originals)
		for s in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(s) as ShaderMaterial
			if mat:
				mat.set_shader_parameter("fill_y", level)
		_update_pour_cap(m, level)

## Ends a pour wherever it is: the part's own materials back, its top taken
## away. The editor's Stop Preview calls it, a pour being cut short there.
##
## Also drops what the pour kept on the part and its meshes (vertex lists,
## topology), which would otherwise be saved with the scene.
static func end_fill(part: Node3D) -> void:
	if part.has_meta(_FILL_META):
		part.set_meta(_FILL_META, 1.0)
		_update_fill(part)
		part.remove_meta(_FILL_META)
	for m in _fade_targets(part):
		for key in [_FILL_POINTS_META, _FILL_WELD_META]:
			if m.has_meta(key):
				m.remove_meta(key)

## The top of the pour: the part's horizontal section at the level, filled
## (MeshPrep.section_cap()) -- for a hollow section the ring of its walls, the
## core left open. A child mesh the pour adds and takes away; never saved (no
## owner). Drawn with the part's fill material, unclipped and a little darker.
static func _update_pour_cap(m: MeshInstance3D, level: float) -> void:
	var cap := m.get_node_or_null(POUR_CAP) as MeshInstance3D
	if not m.has_meta(_FILL_WELD_META):
		m.set_meta(_FILL_WELD_META, MeshPrep.welded(m.mesh))
	var section := MeshPrep.section_cap(m.mesh, m.global_transform, level, m.get_meta(_FILL_WELD_META))
	if not section:
		if cap:
			cap.visible = false
		return
	if not cap:
		cap = MeshInstance3D.new()
		cap.name = POUR_CAP
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.add_child(cap)
		var src := m.get_surface_override_material(0) as ShaderMaterial
		var mat: ShaderMaterial = src.duplicate() if src else _fill_material(null)
		mat.set_shader_parameter("fill_y", 1e9)
		var shade: float = mat.get_shader_parameter("top_shade") if mat.get_shader_parameter("top_shade") != null else 0.85
		mat.set_shader_parameter("albedo", (mat.get_shader_parameter("albedo") as Color) * Color(shade, shade, shade, 1.0))
		cap.material_override = mat
	cap.mesh = section
	cap.visible = true

const POUR_CAP := "_PourCap"

## The part's lowest and highest points in world Y as it stands now (x = min,
## y = max), from its meshes' vertices, read once per part and kept.
static func fill_extent(part: Node3D) -> Vector2:
	var lo := INF
	var hi := -INF
	for m in _fade_targets(part):
		var mesh_node := m as MeshInstance3D
		if not mesh_node.mesh:
			continue
		if not mesh_node.has_meta(_FILL_POINTS_META):
			var pts := PackedVector3Array()
			for s in mesh_node.mesh.get_surface_count():
				pts.append_array(mesh_node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
			mesh_node.set_meta(_FILL_POINTS_META, pts)
		var xf: Transform3D = mesh_node.global_transform
		for v in mesh_node.get_meta(_FILL_POINTS_META):
			var y: float = (xf * v).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return Vector2(lo, hi) if lo <= hi else Vector2.ZERO

## A fill_clip material reproducing `src` (a StandardMaterial3D/ORM; anything
## else gets its albedo grey).
static func _fill_material(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FILL_SHADER
	var b := src as BaseMaterial3D
	if not b:
		m.set_shader_parameter("albedo", Color(0.7, 0.7, 0.68))
		return m
	m.set_shader_parameter("albedo", b.albedo_color)
	if b.albedo_texture:
		m.set_shader_parameter("has_albedo_tex", true)
		m.set_shader_parameter("albedo_tex", b.albedo_texture)
	m.set_shader_parameter("roughness", b.roughness)
	if b.roughness_texture:
		m.set_shader_parameter("has_roughness_tex", true)
		m.set_shader_parameter("roughness_tex", b.roughness_texture)
	m.set_shader_parameter("metallic", b.metallic)
	m.set_shader_parameter("specular", b.metallic_specular)
	m.set_shader_parameter("triplanar", b.uv1_triplanar)
	m.set_shader_parameter("world_triplanar", b.uv1_world_triplanar)
	m.set_shader_parameter("uv1_scale", b.uv1_scale)
	m.set_shader_parameter("uv1_offset", b.uv1_offset)
	m.set_shader_parameter("uv1_sharpness", b.uv1_triplanar_sharpness)
	if b.detail_enabled and b.detail_albedo:
		m.set_shader_parameter("has_detail", true)
		m.set_shader_parameter("detail_tex", b.detail_albedo)
		m.set_shader_parameter("uv2_triplanar", b.uv2_triplanar)
		m.set_shader_parameter("uv2_scale", b.uv2_scale)
		m.set_shader_parameter("uv2_offset", b.uv2_offset)
		m.set_shader_parameter("uv2_sharpness", b.uv2_triplanar_sharpness)
	return m

## Every MeshInstance3D whose material the fade animations should drive: the
## part itself when it is one, else its descendants.
##
## A part is usually a single MeshInstance3D, and was assumed to be one until
## formwork tier 2 (07_FORMWORK.md, decision 7): a .glb or .tscn panel asset
## instantiates as a Node3D *with* MeshInstance3D children, so a tier-2 panel
## whose strip_type is the default fade_out would have popped out of existence
## rather than faded. Both fades previously returned early on anything that
## wasn't a MeshInstance3D, i.e. composite parts got no fade at all -- so
## recursing can only ever improve them, never change an existing fade.
static func _fade_targets(part: Node3D) -> Array:
	if part is MeshInstance3D:
		return [part]
	return part.find_children("*", "MeshInstance3D", true, false).filter(func(n): return n.name != POUR_CAP)

## Hidden until it starts (like every other type -- it used to sit visible at
## alpha 0 from day 0, paying for a transparent pass for nothing).
static func _fade_in_instant(part: Node3D, progress: float) -> void:
	part.scale = part.get_meta("original_scale")
	part.position = part.get_meta("original_pos")
	part.visible = progress > 0.0
	_set_opacity(part, clampf(progress, 0.0, 1.0) if progress > 0.0 else 1.0)

static func _fade_out_instant(part: Node3D, progress: float) -> void:
	part.scale = part.get_meta("original_scale")
	part.position = part.get_meta("original_pos")
	part.visible = progress < 1.0
	_set_opacity(part, 1.0 - clampf(progress, 0.0, 1.0) if progress < 1.0 else 1.0)

## Sets every material on the part (all surfaces, all descendant meshes) to
## `fraction` of its own original opacity. At 1.0 the material gets its original
## transparency mode back, so a fully-present opaque part leaves the transparent
## render pass -- formwork made that matter: a panel holding through the pour
## sits at progress 0 of its strip for most of the schedule, and leaving ~160 of
## them alpha-blended costs a sorted transparent pass for solid geometry.
##
## Materials are per-part (SequenceManager.make_materials_unique()), so the
## original values can live on the material itself; Resource.duplicate() carries
## them along on the next Start Preview.
static func _set_opacity(part: Node3D, fraction: float) -> void:
	for mesh_node in _fade_targets(part):
		for i in mesh_node.get_surface_override_material_count():
			var mat = mesh_node.get_active_material(i)
			if not (mat is BaseMaterial3D):
				continue
			if not mat.has_meta(_ORIGINAL_ALPHA_META):
				mat.set_meta(_ORIGINAL_ALPHA_META, mat.albedo_color.a)
				mat.set_meta(_ORIGINAL_TRANSPARENCY_META, mat.transparency)
			var base_alpha: float = mat.get_meta(_ORIGINAL_ALPHA_META)
			if fraction >= 1.0:
				mat.transparency = mat.get_meta(_ORIGINAL_TRANSPARENCY_META)
				mat.albedo_color.a = base_alpha
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = base_alpha * maxf(fraction, 0.0)

static func _install_instant(part: Node3D, progress: float) -> void:
	var orig_pos: Vector3 = part.get_meta("original_pos")
	var orig_scale: Vector3 = part.get_meta("original_scale")

	part.scale = orig_scale
	var ground_start: Vector3 = part.get_meta("install_ground_start", orig_pos + Vector3(15, 0, 0))
	var hover_height = orig_pos.y + 5.0

	if progress <= 0.0:
		# Matches every other _*_instant method's convention: not-yet-started
		# parts are hidden, not staged-and-visible at their pickup point.
		# (This was previously unconditional `visible = true`, which made
		# every future install part visible at ground_start from day 0.)
		part.visible = false
		part.position = ground_start
		return
	part.visible = true
	if progress >= 1.0:
		part.position = orig_pos
		return

	# A path planned round what stands there (ConstructionSchedule._plan_lifts()).
	if part.has_meta("install_path"):
		part.position = LiftPlanner.sample(part.get_meta("install_path"), progress)
		return

	if progress < 0.3:
		# Phase 1 (0-0.3): lift straight up to hover height.
		var t = progress / 0.3
		var y = Tween.interpolate_value(ground_start.y, hover_height - ground_start.y, t, 1.0, Tween.TRANS_SINE, Tween.EASE_OUT)
		part.position = Vector3(ground_start.x, y, ground_start.z)
	elif progress < 0.7:
		# Phase 2 (0.3-0.7): slide horizontally at hover height.
		var t = (progress - 0.3) / 0.4
		var pos = Tween.interpolate_value(
			Vector3(ground_start.x, hover_height, ground_start.z),
			Vector3(orig_pos.x - ground_start.x, 0.0, orig_pos.z - ground_start.z),
			t, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT
		)
		part.position = pos
	else:
		# Phase 3 (0.7-1.0): lower to final position.
		var t = (progress - 0.7) / 0.3
		var y = Tween.interpolate_value(hover_height, orig_pos.y - hover_height, t, 1.0, Tween.TRANS_SINE, Tween.EASE_IN)
		part.position = Vector3(orig_pos.x, y, orig_pos.z)
