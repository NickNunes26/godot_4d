## Generates formwork (encofrado) geometry for the actions that ask for it --
## build order step 2 of addons/construction_4d_tool/docs/07_FORMWORK.md.
##
## A pour is not a five-day pour; it is four days of building the forms and one
## day of filling them. ConstructionSchedule already splits an action's window
## into those two phases (step 1); this class builds the geometry that occupies
## the first one, and stamps each panel with the part it wraps so the schedule
## can find it again.
##
## **Idempotent, which is the whole point.** Generated geometry lands in the same
## container as the scene's own parts, so a second call would otherwise duplicate
## everything. The dock preview *is* the authoring flow and Start Preview re-runs
## setup on every press, so build() sweeps its own
## previous output before generating, and running it any number of times leaves
## the same scene as running it once.
##
## **Nothing generated here is owned**, so Godot never writes it into the .tscn.
## Formwork is derived from the schedule plus the model; persisting it would mean
## a saved scene and a saved JSON that can disagree, and re-deriving it costs
## milliseconds. This is the opposite of GDIFC4DAdapter's import, which sets
## owner precisely so it *does* survive a save -- that is real imported geometry,
## this is a view of it.
class_name FormworkBuilder
extends RefCounted

## Stamped on every generated panel, naming the part it wraps. Read by
## ConstructionSchedule to schedule panels, to roll them up to their element,
## and -- critically -- to keep them out of target_prefix matching, which is
## begins_with() and would otherwise be one rename away from scheduling an
## element's own forms as concrete. See _index_formwork_panels() there.
const META_OWNER := "formwork_of"
const GROUP := "generated_formwork"

## Defaults in **world metres**, converted into each part's local space before
## use -- a part whose transform carries scale would otherwise get boards sized
## in its own arbitrary units.
const DEFAULT_BOARD_WIDTH := 2.5
const DEFAULT_THICKNESS := 0.05
## Boards per face. The floor keeps a very small element from getting a
## fractional board; the ceiling keeps a very large footing from becoming
## a hundred nodes for a wall nobody looks at that closely.
const MIN_BOARDS := 1
const MAX_BOARDS := 8

const WOOD_COLOR := Color(0.55, 0.38, 0.21)

## Removes every panel this class previously generated under `container`.
## Returns how many were freed.
static func sweep(container: Node) -> int:
	if not container:
		return 0
	var removed := 0
	for child in container.get_children():
		if child.has_meta(META_OWNER):
			container.remove_child(child)
			child.queue_free()
			removed += 1
	return removed

## Sweeps, then generates panels for every action carrying a formwork config.
## Returns the number of panels created.
##
## Must run **before** SequenceManager.initialize_parts(), so the panels are
## registered as ordinary parts and hidden with everything else. It reads each
## part's original_transform/original_aabb metas when they exist and its live
## state when they don't -- on a first run there are no metas and the live state
## is untouched, and on every run after that initialize_parts() has left metas
## behind and the live state is the previous preview's hidden, zero-scaled one.
## Preferring the metas is what makes a second Start Preview place forms
## identically to the first instead of collapsing them to nothing.
static func build(sequence_data: Dictionary, container: Node) -> int:
	sweep(container)
	if not container or not (sequence_data is Dictionary):
		return 0

	var defaults: Dictionary = ConstructionSchedule.formwork_defaults(sequence_data)
	var created := 0
	# res:// path -> {scene, aabb} or {} for one that failed to resolve. Shared
	# across the whole build because formwork_defaults.model means every action
	# typically names the same asset, and a failure is worth warning about per
	# action but only worth *loading* once.
	var model_cache: Dictionary = {}
	# Every tier-1 prefix in the file, so no action generates boards around
	# *another* action's scene-modelled forms. ConstructionSchedule makes the
	# same guarantee on the scheduling side (_parts_excluding_formwork()); this
	# is its generation-side half, and it has to be collected across all actions
	# before any of them builds, for the same reason.
	var scene_formwork_prefixes: Array = _scene_formwork_prefixes(sequence_data, defaults)

	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			created += _build_for_action(action, defaults, container, model_cache, scene_formwork_prefixes)
	return created

static func _scene_formwork_prefixes(sequence_data: Dictionary, defaults: Dictionary) -> Array:
	var out: Array = []
	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, defaults)
			var prefix: String = String(cfg.get("prefix", "")) if not cfg.is_empty() else ""
			if prefix != "" and not out.has(prefix):
				out.append(prefix)
	return out

static func _build_for_action(action: Dictionary, defaults: Dictionary, container: Node,
		model_cache: Dictionary, scene_formwork_prefixes: Array) -> int:
	var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, defaults)
	if cfg.is_empty():
		return 0

	var action_id: String = ConstructionSchedule._action_id(action)

	# Tier 1: the formwork is already modelled in the scene, so generate nothing
	# and let the named parts be the forms. ConstructionSchedule resolves the
	# prefix and schedules those parts itself (_index_prefix_formwork()); there
	# is nothing for a *builder* to do, and no warning to give -- an action that
	# says "my forms are already here" is fully served by generating nothing.
	if String(cfg.get("prefix", "")) != "":
		return 0

	# Tier 2: a panel asset placed at every position tier 3 would have put a box
	# at. {} when the path is unusable -- warned once per action, then the
	# generic slab, because a mistyped path should cost the forms' *look*, not
	# their existence, and an empty formwork phase reads far less like a typo
	# than brown boxes where panels were expected.
	var model: Dictionary = _resolve_model(String(cfg.get("model", "")), action_id, model_cache)

	var prefix: String = String(action.get("commander_prefix", action.get("target_prefix", "")))
	if prefix == "":
		return 0

	# Commanders only for a commander_prefix action: the commander is the
	# concrete, its grouped children are rebar and similar, already inside it.
	# A plain begins_with(commander_prefix) yields exactly the commanders, since
	# the children match child_prefixes instead.
	var owners: Array = []
	for child in container.get_children():
		if child.has_meta(META_OWNER):
			continue # a panel from an earlier action this same run
		if _matches_any(String(child.name), scene_formwork_prefixes):
			continue # another action's tier-1 forms -- forms don't get forms
		if child is MeshInstance3D and child.mesh and String(child.name).begins_with(prefix):
			owners.append(child)
	if owners.is_empty():
		return 0

	# Ask ConstructionSchedule the same question it will ask itself, so the scene
	# we build and the schedule that drives it can't disagree about whether this
	# action has room for forms. Quietly -- it will warn for real at schedule time.
	var duration_days: float = ConstructionSchedule._resolve_duration_days(action, owners.size())
	var split: Dictionary = ConstructionSchedule._resolve_formwork_split(action, defaults, duration_days, action_id, false)
	if split.formwork_days <= 0.0:
		return 0 # no formwork phase -- generating panels nothing schedules would leave them invisible forever

	var board_width: float = maxf(_number(cfg, "board_width", DEFAULT_BOARD_WIDTH), 0.05)
	var thickness: float = maxf(_number(cfg, "thickness", DEFAULT_THICKNESS), 0.001)
	var material := StandardMaterial3D.new()
	material.albedo_color = WOOD_COLOR
	material.roughness = 0.9

	var created := 0
	for owner_part in owners:
		created += _build_for_part(owner_part, container, board_width, thickness, material, model)
	return created

static func _build_for_part(part: Node3D, container: Node, board_width: float,
		thickness: float, material: Material, model: Dictionary) -> int:
	var aabb: AABB = part.get_meta("original_aabb") if part.has_meta("original_aabb") else part.mesh.get_aabb()
	var world_tf: Transform3D = part.get_meta("original_transform") if part.has_meta("original_transform") else part.global_transform
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
		return 0

	# The mesh's own vertical faces, in world space. The bounding box was the
	# wrong surface: on a real model, elements filled as little as 4% of their
	# own AABB, so box-face boards sat metres away from the concrete they were
	# meant to hold. See 07_FORMWORK.md, "The bounding box was the wrong surface".
	var specs: Array = _face_specs(part, aabb, world_tf, board_width, thickness)
	if specs.is_empty():
		# Fallback for a part whose mesh yields no usable vertical face at all --
		# the old box behaviour, reached only where the new one has nothing to
		# say, so a degenerate part still gets forms rather than none.
		specs = _box_specs(aabb, world_tf, board_width, thickness)

	var created := 0
	for spec in specs:
		# Tiers 2 and 3 differ *only* here -- the placement above is shared, which
		# is what keeps "I have a panel asset" one JSON field away from the
		# default rather than a second code path through the geometry math.
		var panel: Node3D
		var fit := Transform3D()
		if model.is_empty():
			var mesh_panel := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = spec.size
			box.material = material
			mesh_panel.mesh = box
			panel = mesh_panel
		else:
			panel = model.scene.instantiate()
			fit = _fit_model_transform(model.aabb, spec.size)
		panel.name = "ENC_%s_%s" % [part.name, spec.id]
		panel.set_meta(META_OWNER, String(part.name))
		panel.add_to_group(GROUP)
		container.add_child(panel)
		# After add_child, so the container's own transform is accounted for.
		# spec.transform is already world-space (the faces were extracted there),
		# so unlike the old box path it is not composed with the part's transform
		# a second time. Deliberately not setting owner -- see the header comment.
		panel.global_transform = spec.transform * fit
		created += 1
	return created

## How far from vertical a face can lean and still be formed. cos-free: this is
## |n.y| for a unit normal, so 0.25 is about 14 degrees off plumb. A sloped
## abutment wing still gets forms; a deck's top and soffit do not.
const VERTICAL_TOL := 0.25
## Normals within this of each other merge into one board spanning them
## (decision 11). Straight faces are unaffected -- a box's four normals are 90
## degrees apart -- while the facets of a rounded pier or a curved deck edge
## collapse from dozens into a handful.
const MERGE_ANGLE_COS := 0.966 # 15 degrees
## How far a triangle may sit off its cluster's seed plane and still join it --
## in metres, and therefore an upper bound on how far any finished board can end
## up from the concrete. This is the constant that actually controls fit; the
## merge angle only controls how the surface is carved up.
const FLATNESS_TOL := 0.15
## Per-part face ceiling, applied to the largest clusters by area. A rounded
## pier yields 76 raw patches and a curved deck edge 61; real formwork is built
## from flat panels, but not that many on one pier. Each surviving face still
## subdivides into boards of board_width, so this caps faces, not panels.
const MAX_FACES := 40
## A cluster carrying less than this share of the largest one's area is noise --
## triangle slivers, not a face anybody forms.
const MIN_AREA_FRACTION := 0.02

## One board spec per placement: {id, size, transform}, transform in WORLD space
## with its basis oriented (tangent, up, outward normal) so the board lies flat
## against its face. size.z is the panel thickness, always.
##
## Works in world space throughout rather than in the part's local space, because
## "vertical" is a world question -- a part whose transform carries rotation has
## no meaningful local up -- and because it removes the local-to-world unit
## conversion the box path needed for thickness and board width.
static func _face_specs(part: Node3D, aabb: AABB, world_tf: Transform3D,
		board_width: float, thickness: float) -> Array:
	if not (part is MeshInstance3D) or not part.mesh:
		return []
	var tris: PackedVector3Array = part.mesh.get_faces()
	if tris.is_empty():
		return []
	var part_center: Vector3 = world_tf * aabb.get_center()

	var clusters: Array = []
	for t in range(tris.size() / 3):
		var a: Vector3 = world_tf * tris[t * 3]
		var b: Vector3 = world_tf * tris[t * 3 + 1]
		var c: Vector3 = world_tf * tris[t * 3 + 2]
		var cross: Vector3 = (b - a).cross(c - a)
		var area: float = cross.length() * 0.5
		if area < 1e-7:
			continue
		var n: Vector3 = cross / (area * 2.0)
		if absf(n.y) > VERTICAL_TOL:
			continue # a top or soffit face, not something you form
		var placed := false
		for cl in clusters:
			# Measured against the cluster's SEED plane, never a running average.
			# Averaging lets a gentle curve merge without bound: each facet is
			# within tolerance of the drifting mean, so a 47 m deck edge collapsed
			# into one cluster and got flattened onto a single plane, leaving
			# boards up to 41 m from the concrete. The seed is fixed, so a
			# cluster can only ever span one tolerance.
			if cl.n.dot(n) < MERGE_ANGLE_COS:
				continue
			# And bounded in metres, not only in degrees. A large-radius curve
			# stays inside 15 degrees for tens of metres, so the angle alone does
			# not bound the sagitta -- this does, and it bounds exactly the
			# quantity that matters: how far a flat board ends up from the
			# surface it is supposed to be holding.
			if absf(cl.n.dot(a) - cl.d) > FLATNESS_TOL \
				or absf(cl.n.dot(b) - cl.d) > FLATNESS_TOL \
				or absf(cl.n.dot(c) - cl.d) > FLATNESS_TOL:
				continue
			cl.area += area
			cl.pts.append_array([a, b, c])
			placed = true
			break
		if not placed:
			clusters.append({"n": n, "d": n.dot(a), "area": area, "pts": [a, b, c]})

	if clusters.is_empty():
		return []
	clusters.sort_custom(func(x, y): return x.area > y.area)
	var floor_area: float = clusters[0].area * MIN_AREA_FRACTION

	var specs: Array = []
	var index := 0
	for cl in clusters:
		if specs.size() >= MAX_FACES or cl.area < floor_area:
			break
		# A cluster facing inward is an interior surface -- a hollow box girder's
		# inner wall. Forming it would put boards inside the concrete.
		var cluster_center: Vector3 = _mean(cl.pts)
		if cl.n.dot(cluster_center - part_center) <= 0.0:
			continue
		# Plane basis: a horizontal tangent, world up, and the outward normal.
		# The normal is within VERTICAL_TOL of horizontal by construction, so
		# crossing it with UP is always well conditioned.
		var tangent: Vector3 = Vector3.UP.cross(cl.n)
		if tangent.length() < 1e-5:
			continue
		tangent = tangent.normalized()
		var up: Vector3 = cl.n.cross(tangent).normalized()

		# Project every triangle onto the plane's (u, v) axes, keeping them as
		# triangles rather than as loose points -- the split below needs to know
		# which stretches of u a triangle actually *covers*, and a 10 m triangle
		# has no vertices anywhere in its middle.
		var min_u := INF
		var max_u := -INF
		var spans: Array = []
		for t in range(cl.pts.size() / 3):
			var u0 := INF
			var u1 := -INF
			var v0 := INF
			var v1 := -INF
			for k in range(3):
				var rel: Vector3 = cl.pts[t * 3 + k] - cluster_center
				var u: float = rel.dot(tangent)
				var v: float = rel.dot(up)
				u0 = minf(u0, u); u1 = maxf(u1, u)
				v0 = minf(v0, v); v1 = maxf(v1, v)
			spans.append({"u0": u0, "u1": u1, "v0": v0, "v1": v1})
			min_u = minf(min_u, u0); max_u = maxf(max_u, u1)
		var width: float = max_u - min_u
		if width <= 1e-4:
			continue

		# The face's own plane, not the cluster centroid's: a triangulated face
		# has its centroid pulled toward wherever the triangles are denser.
		var plane_origin: Vector3 = cluster_center + cl.n * (cl.d - cl.n.dot(cluster_center))

		# Split into laterally contiguous runs. Coplanarity says nothing about
		# adjacency: the two ends of a long deck edge share a plane while the
		# middle curves away from it, and without this one board spanned the 40 m
		# of fresh air between them. Bins are marked by triangle coverage, so a
		# genuinely continuous face is never split by its own tessellation.
		var bins: int = clampi(int(ceil(width / maxf(width / 64.0, 0.05))), 1, 256)
		var bin_w: float = width / bins
		var covered: Array = []
		covered.resize(bins)
		covered.fill(false)
		for sp in spans:
			var b0: int = clampi(int(floor((sp.u0 - min_u) / bin_w)), 0, bins - 1)
			var b1: int = clampi(int(floor((sp.u1 - min_u) / bin_w)), 0, bins - 1)
			for b in range(b0, b1 + 1):
				covered[b] = true

		var run_start := -1
		var run := 0
		for b in range(bins + 1):
			var is_covered: bool = b < bins and covered[b]
			if is_covered and run_start < 0:
				run_start = b
			elif not is_covered and run_start >= 0:
				var u_lo: float = min_u + float(run_start) * bin_w
				var u_hi: float = min_u + float(b) * bin_w
				# This run's own height, not the whole cluster's -- a stepped
				# face is shorter at one end, and one height across all of it
				# would bury the short end or leave the tall one open.
				var v_lo := INF
				var v_hi := -INF
				for sp in spans:
					if sp.u1 >= u_lo and sp.u0 <= u_hi:
						v_lo = minf(v_lo, sp.v0); v_hi = maxf(v_hi, sp.v1)
				var height: float = v_hi - v_lo
				if height > 1e-4 and (u_hi - u_lo) > 1e-4:
					var boards: int = _board_count(u_hi - u_lo, board_width)
					var board_w: float = (u_hi - u_lo) / boards
					for i in range(boards):
						var b_lo: float = u_lo + board_w * float(i)
						var b_hi: float = b_lo + board_w
						# Each board takes the v-range of the surface *under it*,
						# not the run's overall one. A face that steps or tapers
						# is shorter at one end, and a single height across the
						# whole run would bury the short end and leave the tall
						# end open above the concrete.
						var bv_lo := INF
						var bv_hi := -INF
						for sp in spans:
							if sp.u1 >= b_lo and sp.u0 <= b_hi:
								bv_lo = minf(bv_lo, sp.v0); bv_hi = maxf(bv_hi, sp.v1)
						if bv_hi - bv_lo <= 1e-4:
							continue
						var cu: float = (b_lo + b_hi) * 0.5
						var cv: float = (bv_lo + bv_hi) * 0.5
						# Half a thickness proud of the face, so the board sits
						# against the concrete rather than half inside it.
						specs.append({
							"id": "F%d_%d_%d" % [index, run, i],
							"size": Vector3(board_w, bv_hi - bv_lo, thickness),
							"transform": Transform3D(Basis(tangent, up, cl.n),
								plane_origin + tangent * cu + up * cv + cl.n * (thickness * 0.5)),
						})
					run += 1
				run_start = -1
		index += 1
	return specs

static func _mean(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / maxf(float(points.size()), 1.0)

## Loads and measures a tier-2 panel asset, or returns {} to mean "fall back to
## the generic slab". Cached by path across the whole build, since one
## formwork_defaults.model is typically shared by every action.
##
## Every failure mode ends the same way -- warn once, return {} -- because the
## alternative is an action whose formwork phase is silently empty, and an empty
## gap in the middle of the animation is much harder to recognise as a mistyped
## path than a set of brown boxes is.
static func _resolve_model(path: String, action_id: String, cache: Dictionary) -> Dictionary:
	if path == "":
		return {}
	if not cache.has(path):
		cache[path] = _load_model(path)
	var model: Dictionary = cache[path]
	if model.is_empty():
		push_warning("FormworkBuilder: action '%s' names formwork.model '%s', which couldn't be used -- generating the generic wood slab instead" % [action_id, path])
	return model

static func _load_model(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		push_warning("FormworkBuilder: formwork.model '%s' does not exist" % path)
		return {}
	var res = load(path)
	if not (res is PackedScene):
		push_warning("FormworkBuilder: formwork.model '%s' is not a PackedScene (.glb/.tscn)" % path)
		return {}
	# Measured once, from a probe that is thrown away -- every placement of the
	# same asset has the same local AABB, and instantiating one per panel just
	# to ask it its size would be the expensive way to learn the same number.
	var probe = res.instantiate()
	if not (probe is Node3D):
		push_warning("FormworkBuilder: formwork.model '%s' has a root that isn't a Node3D, so it can't be placed" % path)
		if probe:
			probe.queue_free()
		return {}
	var aabb: AABB = _model_aabb(probe)
	probe.queue_free()
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
		push_warning("FormworkBuilder: formwork.model '%s' has no mesh geometry to size a panel from" % path)
		return {}
	return {"scene": res, "aabb": aabb}

## The union of a model's mesh AABBs in its own root's local space. The same
## walk SequenceManager._get_local_aabb() does, done without the scene tree --
## the probe above is never added to it, so global_transform is unavailable and
## the transform relative to the root has to be accumulated by hand.
static func _model_aabb(node_root: Node3D) -> AABB:
	if node_root is MeshInstance3D and node_root.mesh:
		return node_root.mesh.get_aabb()
	var out := AABB()
	var found := false
	for child in node_root.find_children("*", "MeshInstance3D", true, false):
		if not child.mesh:
			continue
		var tf := Transform3D()
		var walk: Node = child
		while walk and walk != node_root:
			if walk is Node3D:
				tf = (walk as Node3D).transform * tf
			walk = walk.get_parent()
		var child_aabb: AABB = tf * child.mesh.get_aabb()
		out = child_aabb if not found else out.merge(child_aabb)
		found = true
	return out

## Where one model instance sits so that it fills a computed board.
##
## The board's own basis already puts its thin axis on local Z and its height on
## local Y (see _face_specs()), so the asset only has to be turned to match that
## convention: whichever of its horizontal extents is thinner becomes Z. Before
## faces carried orientation this had to compare against each slot's axis; now
## there is one convention and one comparison.
##
## Then scale to fill the board -- the same argument the generic slab and the
## pour stream already make: elements run from well under a metre to over twenty, so one fixed
## size reads wrong at one end or the other. Board width is already adaptive (set
## board_width to the asset's real width and the horizontal scale stays near 1),
## but height is the element's and has to scale regardless.
static func _fit_model_transform(model_aabb: AABB, size: Vector3) -> Transform3D:
	var basis := Basis()
	var extent: Vector3 = model_aabb.size
	if extent.z > extent.x:
		# Modelled thin-in-X; turn it so the thin axis is Z like the board's.
		basis = Basis(Vector3.UP, PI * 0.5)
		extent = Vector3(extent.z, extent.y, extent.x)
	basis = basis.scaled(Vector3(
		size.x / maxf(extent.x, 0.0001),
		size.y / maxf(extent.y, 0.0001),
		size.z / maxf(extent.z, 0.0001)))
	# Land the model's own AABB centre on the placement, not its origin -- an
	# asset modelled with its pivot at a corner would otherwise sit a half-panel
	# off, differently on every face.
	return Transform3D(basis, -(basis * model_aabb.get_center()))

## The four vertical faces of the AABB -- the pre-face-extraction behaviour, kept
## only as the fallback for a part whose mesh yields no usable vertical face
## (see _build_for_part()). Emits the same {id, size, transform} shape
## _face_specs() does, in world space, so the caller has one code path.
##
## No bottom panel (the element sits on ground, a footing, or the previous lift)
## and no top panel (that is where the concrete goes in).
static func _box_specs(aabb: AABB, world_tf: Transform3D, board_width: float, thickness: float) -> Array:
	var specs: Array = []
	var scale: Vector3 = world_tf.basis.get_scale().abs()
	var h: float = aabb.size.y * (scale.y if scale.y > 0.0001 else 1.0)
	var center: Vector3 = aabb.get_center()

	var sx: float = scale.x if scale.x > 0.0001 else 1.0
	var sz: float = scale.z if scale.z > 0.0001 else 1.0
	# span is the face's own width in world metres: an X-facing face spans Z, a
	# Z-facing one spans X.
	for face in [
		{"id": "X+", "n": Vector3.RIGHT, "half": aabb.size.x * 0.5, "span": aabb.size.z * sz},
		{"id": "X-", "n": Vector3.LEFT, "half": aabb.size.x * 0.5, "span": aabb.size.z * sz},
		{"id": "Z+", "n": Vector3.BACK, "half": aabb.size.z * 0.5, "span": aabb.size.x * sx},
		{"id": "Z-", "n": Vector3.FORWARD, "half": aabb.size.z * 0.5, "span": aabb.size.x * sx},
	]:
		var n: Vector3 = (world_tf.basis * face.n).normalized()
		var tangent: Vector3 = Vector3.UP.cross(n)
		if tangent.length() < 1e-5:
			continue
		tangent = tangent.normalized()
		var up: Vector3 = n.cross(tangent).normalized()
		var plane_center: Vector3 = world_tf * (center + face.n * face.half)
		var span: float = face.span
		var boards: int = _board_count(span, board_width)
		var board_w: float = span / boards
		for i in range(boards):
			var cu: float = -span * 0.5 + board_w * (float(i) + 0.5)
			specs.append({
				"id": "%s%d" % [face.id, i],
				"size": Vector3(board_w, h, thickness),
				"transform": Transform3D(Basis(tangent, up, n),
					plane_center + tangent * cu + n * (thickness * 0.5)),
			})
	return specs

static func _matches_any(part_name: String, prefixes: Array) -> bool:
	for p in prefixes:
		if part_name.begins_with(p):
			return true
	return false

static func _board_count(world_length: float, board_width: float) -> int:
	return clampi(int(round(world_length / board_width)), MIN_BOARDS, MAX_BOARDS)

static func _number(cfg: Dictionary, key: String, fallback: float) -> float:
	var value = cfg.get(key, fallback)
	return float(value) if (value is float or value is int) else fallback
