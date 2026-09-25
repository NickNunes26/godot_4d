## Phase 2 collision detection's physics-shape bookkeeping and query, split
## out of construction_schedule.gd (which had grown to mix schedule/
## dependency resolution with this -- collision shape setup/registration and
## the exact-geometry query are a fairly self-contained ~150-line concern on
## their own). Owned by ConstructionSchedule as a single instance
## (_collision_query), created once in _init() via setup() and queried by
## get_collisions() via query() -- see that method's doc comment there for
## why get_part_states() itself stays on ConstructionSchedule (it needs
## _part_schedules/_state_cache, which are core schedule state, not
## collision-specific).
##
## Registers one PhysicsServer3D area per MeshInstance3D part, in the scene's
## own physics space. query() uses these for exact shape-vs-shape queries
## (PhysicsDirectSpaceState3D.intersect_shape()) instead of AABB overlap --
## an axis-aligned box is a loose fit for a rotated/diagonal member (e.g. a
## skewed bridge beam), which produces false-positive "collisions" on
## near-misses.
##
## Each part gets *two* shapes, used for different roles:
## - concave_shape (ConcavePolygonShape3D / trimesh): registered as the
##   area's own shape, i.e. what a part presents as a target when some
##   *other* part queries against it. Exact geometry, including concave
##   features (an L-bracket, a beam with a cut-out/notch) that a convex hull
##   would over-include as solid.
## - convex_shape (ConvexPolygonShape3D): kept as a plain Resource, not
##   registered to any area. Used only as the *query* shape when this part
##   is itself the mover (query() reads it directly from _collision_shapes,
##   not from the area). Required because Godot's physics engine doesn't
##   support a concave shape as the query parameter of intersect_shape() --
##   concave-vs-concave queries aren't supported, but convex-vs-concave (a
##   moving part's hull against another part's exact trimesh) is, so this is
##   the accurate combination available.
##
## Uses raw PhysicsServer3D calls, not Area3D/CollisionShape3D nodes, so no
## extra scene-tree nodes are needed and area transforms can be pushed
## synchronously right before every query. This assumes physics runs on the
## main thread (Godot's default -- the "Physics > 3D > Run on Separate
## Thread" project setting must stay off, or area_set_transform()'s effect
## may not be visible to the same-frame intersect_shape() call).
class_name CollisionQuery
extends RefCounted

# A dedicated PhysicsServer3D collision layer so the raw areas created below
# never interact with any other physics content a project might add later.
# Bit 20 is arbitrary but unlikely to collide with anything else in use.
const _COLLISION_LAYER: int = 1 << 19

var _collision_shapes: Dictionary = {} # part_name -> {area_rid: RID, convex_shape: ConvexPolygonShape3D, concave_shape: ConcavePolygonShape3D}
var _area_rid_to_part: Dictionary = {} # RID -> part_name
var _space_rid: RID

func setup(building_parts: Dictionary) -> void:
	var any_node: Node3D = null
	for n in building_parts.values():
		if n is Node3D and n.is_inside_tree():
			any_node = n
			break
	if not any_node:
		push_warning("CollisionQuery: no part in the scene tree, collision detection disabled")
		return
	_space_rid = any_node.get_world_3d().space

	for part_name in building_parts.keys():
		var node = building_parts[part_name]
		if not (node is MeshInstance3D) or not node.mesh:
			continue
		# Generated formwork is deliberately not clash-checked (07_FORMWORK.md,
		# decision 3). It multiplies the part count 3-5x, and every part costs a
		# convex hull *and* a trimesh built from scratch here with no caching --
		# which is already why the dock needs an explicit Recalculate button. In
		# exchange it would detect clashes against temporary scaffolding, and on
		# a model with no `install` actions at all nothing is ever a mover, so
		# the value is currently zero. Re-enabling is deleting this check;
		# _part_to_commander already rolls panels up to their element, so they
		# would not flag against the concrete they hold.
		if node.has_meta(FormworkBuilder.META_OWNER):
			continue
		var convex_shape: ConvexPolygonShape3D = node.mesh.create_convex_shape(true, false)
		var concave_shape: ConcavePolygonShape3D = node.mesh.create_trimesh_shape()
		if not convex_shape or convex_shape.points.is_empty() or not concave_shape:
			push_warning("CollisionQuery: could not build a collision shape for '%s', skipped" % part_name)
			continue

		var area_rid := PhysicsServer3D.area_create()
		PhysicsServer3D.area_set_space(area_rid, _space_rid)
		PhysicsServer3D.area_add_shape(area_rid, concave_shape.get_rid())
		PhysicsServer3D.area_set_collision_layer(area_rid, _COLLISION_LAYER)
		PhysicsServer3D.area_set_collision_mask(area_rid, _COLLISION_LAYER)

		_collision_shapes[part_name] = {
			"area_rid": area_rid,
			"convex_shape": convex_shape,
			"concave_shape": concave_shape
		}
		_area_rid_to_part[area_rid] = part_name

## Raw PhysicsServer3D RIDs aren't owned by any scene node, so nothing else
## frees them -- do it ourselves right before this RefCounted is destroyed,
## otherwise they leak at the engine level for the app's lifetime (e.g. every
## scene reload during development would accumulate more). Fires
## automatically when ConstructionSchedule's own reference to this instance
## drops (RefCounted reference counting), no explicit teardown call needed
## from the owner.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry in _collision_shapes.values():
			PhysicsServer3D.free_rid(entry.area_rid)

## Phase 2: flags parts actively being installed (anim_type "install",
## 0 < progress < 1 -- mid lift/slide/lower) whose actual mesh geometry
## overlaps any other currently-present part's actual mesh geometry, using a
## synchronous PhysicsDirectSpaceState3D.intersect_shape() query: the mover's
## convex hull against every other registered part's exact trimesh
## (registered by setup() -- see that function's doc comment for why each
## part carries both a convex and a concave shape). Not AABB intersection: an
## axis-aligned box is a loose fit for rotated/diagonal members (e.g. skewed
## bridge beams), producing false-positive flags on near-misses that don't
## actually touch. Not a plain convex hull on both sides either: a convex
## hull over-includes any concave feature (a notch, an L-bracket cutout) as
## solid, which the mover-convex / target-trimesh split avoids while staying
## within what Godot's physics engine supports (concave-vs-concave queries
## aren't supported; convex-vs-concave is). Not Area3D.get_overlapping_bodies()
## either, since that lags a physics tick behind teleported/instant-applied
## parts (see 01_ARCHITECTURE.md's Phase 2 note); raw PhysicsServer3D areas
## moved via area_set_transform() immediately before the query avoid that lag.
##
## Only in-transit parts are checked as movers, not every currently-visible
## part against every other -- steady-state touching (a wall resting on a
## slab, rebar inside a column) is normal and would otherwise flood this
## with false positives. Parts installed together as one unit (a commander
## and its grouped children, e.g. a column + its rebar cage) are also
## intentionally coincident and excluded via sibling_groups. Hits against
## parts that aren't currently active (not yet started, or already finished
## and hidden) are also discarded -- their physics areas only get their
## transform synced while active, so an inactive part's area would otherwise
## sit at a stale/default transform and produce a nonsensical "collision".
##
## Geometry is checked per leaf part (a commander's overall shape can miss a
## clash a smaller child part actually has, and vice versa), but results are
## reported and deduplicated per *commander pair* (via part_to_commander) --
## e.g. a beam's dozen rebar/formwork children each separately overlapping a
## column's dozen equivalents collapses into one "beam unit vs column unit"
## entry, not a dozen near-identical ones. Parts with no commander (a plain
## target_prefix action) report under their own name.
##
## building_parts must already reflect the current day's state (i.e. call
## this right after TimelineController.scrub_to(current_day), not standalone
## -- this method doesn't move parts itself, it only reads their live
## transform and pushes it to each part's physics area). states comes from
## ConstructionSchedule.get_part_states(current_day) -- {part_name:
## {anim_type, progress}}. Only parts with a registered collision shape
## (MeshInstance3D with a mesh a convex hull could be built from) participate;
## others are silently skipped.
##
## Returns [{part1, part2, overlap_volume, overlap_aabb}, ...], one entry per
## commander pair. The collision itself (whether the pair overlaps at all)
## is exact; overlap_volume/overlap_aabb are an AABB-intersection
## *approximation* of the overlap region -- intersect_shape() only answers
## "do they overlap", not "by how much" -- used to size the
## CollisionVisualizer marker and to pick the largest hit among a
## commander pair's several leaf-level checks.
func query(building_parts: Dictionary, states: Dictionary, sibling_groups: Dictionary, part_to_commander: Dictionary) -> Array:
	var active_names: Array = []
	var active_set: Dictionary = {} # part_name -> true, for O(1) hit filtering below
	for part_name in states.keys():
		var node = building_parts.get(part_name)
		if states[part_name].progress > 0.0 and node and node.visible:
			active_names.append(part_name)
			active_set[part_name] = true

	var movers: Array = []
	for part_name in active_names:
		var sched = states[part_name]
		if sched.anim_type == "install" and sched.progress < 1.0:
			movers.append(part_name)

	if movers.is_empty() or not _space_rid.is_valid():
		return []

	# Sync every currently-visible part's live transform to its physics area
	# before querying -- both movers and the parts they might hit need to be
	# current, since a target could itself be mid-animation (two installs
	# overlapping in time).
	for part_name in active_names:
		var sync_entry = _collision_shapes.get(part_name)
		if sync_entry:
			PhysicsServer3D.area_set_transform(sync_entry.area_rid, building_parts[part_name].global_transform)

	var space_state := PhysicsServer3D.space_get_direct_state(_space_rid)
	if not space_state:
		# Direct space state is briefly unavailable mid physics-step; skip this
		# call rather than erroring -- get_collisions() is polled every frame
		# by CollisionVisualizer, so the next call will simply succeed instead.
		return []
	var collisions_by_commander_pair: Dictionary = {} # "A|B" -> {part1, part2, overlap_volume, overlap_aabb}
	var checked_leaf_pairs: Dictionary = {}

	for mover_name in movers:
		var mover_entry = _collision_shapes.get(mover_name)
		if not mover_entry:
			continue
		var mover_node: Node3D = building_parts[mover_name]
		var siblings: Array = sibling_groups.get(mover_name, [])

		var query_params := PhysicsShapeQueryParameters3D.new()
		query_params.shape_rid = mover_entry.convex_shape.get_rid()
		query_params.transform = mover_node.global_transform
		query_params.collision_mask = _COLLISION_LAYER
		query_params.collide_with_areas = true
		query_params.collide_with_bodies = false
		query_params.exclude = [mover_entry.area_rid]

		var hits = space_state.intersect_shape(query_params, maxi(active_names.size(), 8))

		for hit in hits:
			var other_name = _area_rid_to_part.get(hit.rid)
			if not other_name or other_name == mover_name or siblings.has(other_name):
				continue
			# Areas belonging to parts that haven't started yet (or have
			# already finished and gone invisible) never get their transform
			# synced above -- they sit wherever PhysicsServer3D.area_create()
			# left them (world origin) until the day they actually become
			# active. Without this check a mover sweeping near the origin
			# registers a "collision" against a part that isn't really there.
			if not active_set.has(other_name):
				continue
			var leaf_pair_key = (mover_name + "|" + other_name) if mover_name < other_name else (other_name + "|" + mover_name)
			if checked_leaf_pairs.has(leaf_pair_key):
				continue
			checked_leaf_pairs[leaf_pair_key] = true

			var cmd1 = part_to_commander.get(mover_name, mover_name)
			var cmd2 = part_to_commander.get(other_name, other_name)
			if cmd1 == cmd2:
				continue # both leaves rolled up to the same commander -- not a real clash

			# Approximate overlap region/volume via AABB intersection, purely
			# for the marker size and the largest-hit tie-break -- see the
			# function doc comment above.
			var other_node: Node3D = building_parts[other_name]
			var overlap_aabb := AABB()
			var overlap_volume := 0.0
			if mover_node.has_meta("original_aabb") and other_node.has_meta("original_aabb"):
				var mover_aabb: AABB = mover_node.global_transform * (mover_node.get_meta("original_aabb") as AABB)
				var other_aabb: AABB = other_node.global_transform * (other_node.get_meta("original_aabb") as AABB)
				if mover_aabb.intersects(other_aabb):
					overlap_aabb = mover_aabb.intersection(other_aabb)
					overlap_volume = overlap_aabb.get_volume()

			var cmd_pair_key = (cmd1 + "|" + cmd2) if cmd1 < cmd2 else (cmd2 + "|" + cmd1)
			if not collisions_by_commander_pair.has(cmd_pair_key) or overlap_volume > collisions_by_commander_pair[cmd_pair_key].overlap_volume:
				collisions_by_commander_pair[cmd_pair_key] = {
					"part1": cmd1,
					"part2": cmd2,
					"overlap_volume": overlap_volume,
					"overlap_aabb": overlap_aabb
				}

	return collisions_by_commander_pair.values()
