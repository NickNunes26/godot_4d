## The 4D engine: maps "what calendar day is it?" to "what state is every
## part in?". Pure logic (RefCounted, no scene-tree/EditorPlugin
## dependencies) so it's reusable from a Phase 3 EditorPlugin dock without
## rewriting.
##
## Day 0 is normalized to the earliest start_date found across all actions,
## not the unix epoch -- so get_date_range() always starts near 0 regardless
## of what real-world dates construction_steps.json uses.
##
## An action's start day comes from one of three sources, in priority order:
## an explicit start_date; the LATEST finish day among every depends_on
## predecessor (+ a uniform lag_days), for finish-to-start planning
## ("beams can't start until every column is installed" -- or, with multiple
## predecessors, "...and every slab too"); or day 0 if
## neither is present. depends_on accepts a single id string or an array of
## them (_depends_on_ids()); actions are identified by an explicit id field if
## present, else their commander_prefix/target_prefix (_action_id()). See
## _resolve_action_start_day() and _topo_order_actions().
##
## Multi-crane: each install unit (one commander, see _init()'s commander
## loop) is assigned to whichever Crane in the `cranes` Dictionary passed to
## _init() is nearest by horizontal (XZ) distance to the commander's world
## position -- a real crane's reach is fundamentally a radial/horizontal
## limit, so height differences between crane base and part don't factor in.
## An action can override this with an explicit `crane_id` field (matched
## against a Crane node's own `.name`); an unresolvable crane_id is warned
## about once and falls back to nearest-by-distance, the same "don't block,
## just warn and use the sensible default" posture depends_on/id resolution
## already takes elsewhere in this class. See _assign_crane().
class_name ConstructionSchedule
extends RefCounted

var _part_schedules: Dictionary = {} # part_name -> { start_day, end_day, anim_type }
var _min_day: float = INF
var _max_day: float = -INF
# Only the most recent day is kept: scrub_to() and get_collisions() ask for the
# same day back to back, which is all the cache is for. Keeping every day ever
# asked for grew without bound -- a full scan_collisions() over a ~330-day
# schedule is ~33,000 days x one entry per part, several GB.
var _state_cache_key: int = -1
var _state_cache: Dictionary = {}
# Day 0's real-world unix epoch (the earliest start_date across all actions) --
# lets day_to_date_string() convert any resolved day number back to a real
# calendar date. Set once in _init(), read-only after.
var _min_epoch: float = 0.0
# action_id -> start_day / finish_day, populated in _init() as each action is
# processed in topological order. Exposed via get_action_day_range() so a
# Depends On row in the Phase 3 dock can show its actual resolved calendar
# dates (not just do local start+duration arithmetic, which only works for an
# action with a literal start_date).
var _action_start_days: Dictionary = {}
var _action_finish_days: Dictionary = {}
# One entry per commander unit whose action type is "install", used by
# TimelineController to trigger one crane swing per unit during forward Play.
# crane_id is "" when `cranes` was empty at _init() time (e.g. the Phase 3
# dock's editor preview, which deliberately passes no cranes -- see
# addons/construction_4d_tool/docs/README.md's Phase 3 section) -- TimelineController simply skips
# swinging a unit whose crane_id doesn't resolve to a live Crane, the same
# way it already skips everything when _crane was null pre-multi-crane.
var _install_units: Array = [] # [{start_day, pickup_pos, target_pos, tracked_part_name, lift_dur, slide_dur, crane_id}]
var _fill_up_units: Array = [] # [{start_day, part_name, duration}]
# part_name -> Array[String] of other part names installed as the same unit
# (e.g. a column and its rebar cage). Collision checks skip these pairs --
# they're intentionally coincident, not a real clash.
var _sibling_groups: Dictionary = {}
# part_name -> its commander's name (commander maps to itself). Used to roll
# collision reports up to "beam unit vs column unit" instead of every rebar
# bar/formwork piece in the unit reporting its own separate collision.
var _part_to_commander: Dictionary = {}

# Phase 2 collision detection: shape setup/registration and the exact-
# geometry query live in CollisionQuery (collision_query.gd), a single
# instance owned here -- split out once this file grew too large mixing
# schedule/dependency resolution with that fairly self-contained concern.
# See get_collisions() below.
var _collision_query := CollisionQuery.new()

## sequence_data: parsed construction_steps.json ({"steps": [...]})
## building_parts: name -> Node3D, from SequenceManager.initialize_parts()
## spatial_grouper: cached SpatialGrouper instance for commander/child
## resolution. cranes: crane name -> Crane node, from
## SequenceManager._find_all_cranes() -- defaults to {} for callers with no
## crane at all (the Phase 3 dock's editor preview; see _install_units'
## doc comment above). Never raises -- invalid dates/durations are warned and
## clamped to sane defaults (see 02_ROADMAP_MILESTONES.md, Milestone 6).
func _init(sequence_data: Dictionary, building_parts: Dictionary, spatial_grouper: SpatialGrouper, cranes: Dictionary = {}):
	var min_epoch: float = INF
	var epoch_cache: Dictionary = {} # start_date string -> epoch (float), NAN if unparseable

	# Pass 1: find the minimum epoch so day 0 is the start of the project
	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var start_date = action.get("start_date")
			if start_date:
				var epoch = _resolve_epoch(start_date, epoch_cache)
				if not is_nan(epoch) and epoch < min_epoch:
					min_epoch = epoch

	if is_inf(min_epoch):
		min_epoch = 0.0
	_min_epoch = min_epoch

	# Pass 2: order actions so every depends_on predecessor is processed
	# before its dependent (see _topo_order_actions()), then resolve each
	# action's schedule exactly as before, except action_start_day now also
	# considers depends_on/lag_days (_resolve_action_start_day()), and every
	# action records its own finish day (action_start_day + duration_days)
	# for later dependents to read.
	var ordered_actions: Array = _topo_order_actions(sequence_data)
	# Formwork (07_FORMWORK.md): project-wide defaults for the formwork/pour
	# split, overridden key by key per action. Absent -> {} -> no action gets a
	# formwork phase unless it carries its own block.
	var fw_defaults: Dictionary = formwork_defaults(sequence_data)
	# panel name -> the part it wraps, and the reverse -- built once from the
	# metas FormworkBuilder stamped on every panel it generated. Empty when no
	# formwork geometry exists (build order step 1 only, or a project that
	# doesn't use formwork at all).
	var formwork_panels: Dictionary = _index_formwork_panels(building_parts)
	# Tier 1 (07_FORMWORK.md): part name -> the id of the action whose
	# formwork.prefix claimed it. Resolved for every action up front, before any
	# is scheduled, so that action B's target_prefix can't match action A's
	# scene-modelled formwork any more than it can match its own.
	var prefix_formwork: Dictionary = _index_prefix_formwork(sequence_data, building_parts, fw_defaults)
	# building_parts minus everything that is formwork, generated or tier-1.
	# Prefix matching is begins_with() on both sides of this file's two
	# branches, and formwork is named after the element it wraps by every
	# sensible convention -- so without this an action pours its own forms.
	var work_parts: Dictionary = _parts_excluding_formwork(building_parts, formwork_panels, prefix_formwork)

	for entry in ordered_actions:
		var action: Dictionary = entry.action
		var action_id: String = entry.action_id
		var action_start_day: float = _resolve_action_start_day(action, action_id, epoch_cache, min_epoch, _action_finish_days)
		var duration_days: float = 1.0 # resolved inside each branch below, once target_parts is known
		if action_id != "":
			_action_start_days[action_id] = action_start_day

		var anim_type = action.get("type", "scale_up")

		var target_parts = []
		if action.has("commander_prefix"):
			var cmd_prefix = action["commander_prefix"]
			var child_prefixes = action.get("child_prefixes", [])
			# work_parts, not building_parts: SpatialGrouper does its own bare
			# begins_with() over whatever dictionary it is handed, so this is
			# the commander branch's half of the "prefix matching can never eat
			# the forms" guard the target_prefix branch has below.
			var groups = spatial_grouper.get_groups(cmd_prefix, child_prefixes, work_parts)
			target_parts = SpatialGrouper.sort_by_position(groups.keys(), building_parts)
			# unit_count for units_per_day is the number of installable
			# units -- commanders here, not their grouped children.
			duration_days = _resolve_duration_days(action, target_parts.size())
			# Formwork: the action's own animation occupies only the tail of its
			# window; the head belongs to the forms going up. Without a formwork
			# block this is the whole window, exactly as before.
			var split: Dictionary = _resolve_formwork_split(action, fw_defaults, duration_days, action_id)
			var pour_start_day: float = action_start_day + split.formwork_days
			var pour_days: float = split.pour_days
			var fw_parts: Array = _formwork_parts_for(target_parts, formwork_panels, prefix_formwork, action_id)
			if not fw_parts.is_empty():
				_schedule_formwork(fw_parts, formwork_panels, split.config, action_id,
					action_start_day, split.formwork_days,
					action_start_day + duration_days, building_parts)

			# Compute timings for commanders
			var timings = Cadence.compute_timings(target_parts, action, 1.0, 0.75)
			var last_offset = 0.0
			var last_dur = 0.0
			if timings.size() > 0:
				last_offset = timings[-1].offset_sec
				last_dur = timings[-1].duration_sec
			var total_cadence_sec = maxf(last_offset + last_dur, 0.01)

			var explicit_crane_id: String = action.get("crane_id", "")

			for i in range(timings.size()):
				var timing = timings[i]
				var cmd_name = timing.part_name
				var group_parts = [cmd_name]
				group_parts.append_array(groups[cmd_name])

				var normalized_start = timing.offset_sec / total_cadence_sec
				var normalized_end = (timing.offset_sec + timing.duration_sec) / total_cadence_sec

				var part_start_day = pour_start_day + (normalized_start * pour_days)
				var part_end_day = pour_start_day + (normalized_end * pour_days)

				# Assigned once per commander (not per action): a widely-spread
				# project (e.g. a bridge with a crane per span) can have
				# different commanders in the same action nearest to different
				# cranes, so this can't be hoisted above the loop.
				var world_pos: Vector3 = _resolve_commander_world_pos(building_parts[cmd_name])
				var assignment: Dictionary = _assign_crane(world_pos, cranes, explicit_crane_id)
				var assigned_crane: Crane = assignment.crane

				for p in group_parts:
					_part_schedules[p] = {
						"start_day": part_start_day,
						"end_day": part_end_day,
						"anim_type": anim_type
					}
					_update_bounds(part_start_day, part_end_day)
					_cache_ground_start(p, world_pos, assigned_crane, building_parts)
					_part_to_commander[p] = cmd_name

					if not _sibling_groups.has(p):
						_sibling_groups[p] = []
					var siblings: Array = _sibling_groups[p]
					for other_p in group_parts:
						if other_p != p and not siblings.has(other_p):
							siblings.append(other_p)

				# One swing per commander unit (not per child part).
				if anim_type == "install":
					var pickup_pos: Vector3 = _crane_pickup_position(world_pos, assigned_crane)
					_install_units.append({
						"start_day": part_start_day,
						"pickup_pos": pickup_pos,
						"target_pos": world_pos,
						"tracked_part_name": cmd_name,
						"lift_dur": timing.duration_sec * 0.3,
						"slide_dur": timing.duration_sec * 0.4,
						"crane_id": assignment.crane_id
					})
				elif anim_type == "fill_up":
					_fill_up_units.append({
						"start_day": part_start_day,
						"part_name": cmd_name,
						"duration": part_end_day - part_start_day
					})
		else:
			# work_parts, not building_parts: formwork can never be matched as
			# work. Prefix matching is begins_with(), so a form wrapping "Col_1"
			# is one rename away from starting with "Col_1" too -- at which point
			# the action would schedule its own forms as concrete and pour them.
			# Guarding on the meta and on the resolved tier-1 index rather than
			# on a naming convention is what makes that impossible rather than
			# merely unlikely. See _parts_excluding_formwork().
			for part_name in work_parts.keys():
				if part_name.begins_with(action["target_prefix"]):
					target_parts.append(part_name)
			target_parts = SpatialGrouper.sort_by_position(target_parts, building_parts)
			duration_days = _resolve_duration_days(action, target_parts.size())
			# See the commander branch above -- same split, same reasoning.
			var split: Dictionary = _resolve_formwork_split(action, fw_defaults, duration_days, action_id)
			var pour_start_day: float = action_start_day + split.formwork_days
			var pour_days: float = split.pour_days
			var fw_parts: Array = _formwork_parts_for(target_parts, formwork_panels, prefix_formwork, action_id)
			if not fw_parts.is_empty():
				_schedule_formwork(fw_parts, formwork_panels, split.config, action_id,
					action_start_day, split.formwork_days,
					action_start_day + duration_days, building_parts)

			var timings = Cadence.compute_timings(target_parts, action, 1.0, 0.75)
			var last_offset = 0.0
			var last_dur = 0.0
			if timings.size() > 0:
				last_offset = timings[-1].offset_sec
				last_dur = timings[-1].duration_sec
			var total_cadence_sec = maxf(last_offset + last_dur, 0.01)

			for i in range(timings.size()):
				var timing = timings[i]
				var part_name = timing.part_name

				var normalized_start = timing.offset_sec / total_cadence_sec
				var normalized_end = (timing.offset_sec + timing.duration_sec) / total_cadence_sec

				var part_start_day = pour_start_day + (normalized_start * pour_days)
				var part_end_day = pour_start_day + (normalized_end * pour_days)

				_part_schedules[part_name] = {
					"start_day": part_start_day,
					"end_day": part_end_day,
					"anim_type": anim_type
				}
				_update_bounds(part_start_day, part_end_day)
				# target_prefix actions never get crane choreography (no
				# _install_units entry above, matching pre-existing
				# behavior) -- no crane to assign here either, so this
				# always falls back to the plain (15,0,0) offset.
				var world_pos: Vector3 = _resolve_commander_world_pos(building_parts[part_name])
				_cache_ground_start(part_name, world_pos, null, building_parts)

				if anim_type == "fill_up":
					_fill_up_units.append({
						"start_day": part_start_day,
						"part_name": part_name,
						"duration": part_end_day - part_start_day
					})

		# Record this action's finish day (its start plus its full duration --
		# the last-processed part's part_end_day above always reaches exactly
		# action_start_day + duration_days, since normalized_end maxes out at
		# 1.0 for the last timing entry) so a later-processed dependent can
		# resolve depends_on against it.
		if action_id != "":
			_action_finish_days[action_id] = action_start_day + duration_days

	if _min_day == INF:
		_min_day = 0.0
		_max_day = 1.0

	_collision_query.setup(building_parts)

## Resolves an action's identity: an explicit id if present, else its
## commander_prefix, else its target_prefix, else "". static (uses no
## instance state) so both _topo_order_actions() and the Phase 3 editor dock
## (timeline_dock.gd) can call ConstructionSchedule._action_id(action)
## directly instead of each re-deriving the same fallback chain.
static func _action_id(action: Dictionary) -> String:
	return action.get("id", action.get("commander_prefix", action.get("target_prefix", "")))

## Normalizes an action's depends_on field -- absent, a single String (the
## original schema), or an Array of Strings (multiple predecessors) -- into a
## plain Array[String], dropping empty/non-string entries. static for the
## same reason as _action_id() above; the dock's inspector also calls this
## directly to render/parse the Depends On field.
static func _depends_on_ids(action: Dictionary) -> Array:
	var raw = action.get("depends_on")
	if raw is String:
		return [raw] if raw != "" else []
	if raw is Array:
		var ids: Array = []
		for v in raw:
			if v is String and v != "":
				ids.append(v)
		return ids
	return []

## Flattens sequence_data into one entry per action -- {step_index, action,
## action_id} -- ordered so every action's depends_on predecessors are all
## guaranteed to appear before it (Kahn's algorithm over the depends_on
## edges -- a node only dequeues once every incoming edge has been processed,
## which is exactly the "wait for ALL predecessors" semantics
## _resolve_action_start_day() needs). action_id comes from _action_id()
## above.
## Never raises: a dependency cycle is warned about and the involved actions
## are appended in file order instead. Their depends_on then resolves
## best-effort, per action, in _resolve_action_start_day() -- whichever one
## in the cycle happens to process first still falls back to day 0 (its
## predecessor's finish day isn't recorded yet), but this never hangs.
func _topo_order_actions(sequence_data: Dictionary) -> Array:
	var entries: Array = []
	var by_id: Dictionary = {} # action_id -> entry (first occurrence wins)
	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var action_id: String = _action_id(action)
			var entry = {"step_index": step.get("index", 0), "action": action, "action_id": action_id}
			entries.append(entry)
			if action_id == "":
				continue
			if by_id.has(action_id):
				push_warning("ConstructionSchedule: duplicate action id '%s' -- depends_on referencing it resolves to the first occurrence only" % action_id)
			else:
				by_id[action_id] = entry

	var in_degree: Dictionary = {} # entry index -> int
	var dependents: Dictionary = {} # action_id -> Array[entry index], edges FROM this id TO its dependents
	for i in range(entries.size()):
		in_degree[i] = 0
	for i in range(entries.size()):
		var action: Dictionary = entries[i].action
		for dep_id in _depends_on_ids(action):
			if dep_id == entries[i].action_id:
				push_warning("ConstructionSchedule: action '%s' depends_on itself -- ignoring that predecessor" % dep_id)
				continue
			if not by_id.has(dep_id):
				continue # unresolvable id -- _resolve_action_start_day() warns about this per-action
			in_degree[i] += 1
			if not dependents.has(dep_id):
				dependents[dep_id] = []
			dependents[dep_id].append(i)

	var queue: Array = []
	for i in range(entries.size()):
		if in_degree[i] == 0:
			queue.append(i)

	var ordered: Array = []
	var visited: Dictionary = {}
	while not queue.is_empty():
		var i = queue.pop_front()
		visited[i] = true
		ordered.append(entries[i])
		for dep_i in dependents.get(entries[i].action_id, []):
			in_degree[dep_i] -= 1
			if in_degree[dep_i] == 0:
				queue.append(dep_i)

	if ordered.size() < entries.size():
		var stuck_ids: Array = []
		for i in range(entries.size()):
			if not visited.has(i):
				stuck_ids.append(entries[i].action_id)
				ordered.append(entries[i])
		push_warning("ConstructionSchedule: dependency cycle detected among actions %s -- processing in file order; any that still can't resolve depends_on fall back to start_date or day 0" % [stuck_ids])

	return ordered

## Resolves one action's start day: an explicit start_date always wins (same
## behavior as before depends_on existed, so existing JSON files are
## unaffected); otherwise the LATEST of (predecessor finish day + lag_days)
## across every depends_on id that resolves -- "can't start until ALL
## predecessors are done", not just one -- with lag_days applied uniformly to
## every predecessor rather than per-edge (a real CPM tool would support a
## separate lag per relationship; not needed for what was asked here, and it
## would mean a bigger schema change -- see the plan/CHANGELOG for this
## session); otherwise day 0. Any depends_on id that doesn't resolve is
## warned about individually but doesn't block the others. finish_days is
## populated incrementally by the _init() loop above as it processes actions
## in topological order, so by the time a dependent action is resolved,
## every predecessor's entry is already there (unless a cycle prevented one
## -- see _topo_order_actions()).
func _resolve_action_start_day(action: Dictionary, action_id: String, epoch_cache: Dictionary, min_epoch: float, finish_days: Dictionary) -> float:
	var start_date = action.get("start_date")
	if start_date:
		var epoch = _resolve_epoch(start_date, epoch_cache)
		if not is_nan(epoch):
			return (epoch - min_epoch) / 86400.0
		# else: unparseable, already warned in _resolve_epoch(); fall through

	var dep_ids: Array = _depends_on_ids(action)
	if dep_ids.is_empty():
		return 0.0

	var lag: float = action.get("lag_days", 0.0)
	var latest_start: float = -INF
	var any_resolved := false
	for dep_id in dep_ids:
		if finish_days.has(dep_id):
			any_resolved = true
			latest_start = maxf(latest_start, finish_days[dep_id] + lag)
		else:
			push_warning("ConstructionSchedule: action '%s' depends_on '%s', which wasn't found or couldn't be resolved (missing id or a dependency cycle?) -- ignoring that predecessor" % [action_id, dep_id])

	if any_resolved:
		return latest_start
	push_warning("ConstructionSchedule: action '%s' has no resolvable depends_on predecessors -- treating '%s' as day 0" % [action_id, action_id])
	return 0.0

## Resolves an action's duration_days, supporting the Phase 3 units_per_day
## convenience field (e.g. "2 columns/day") as an alternative to hand-
## computing duration_days: duration_days = ceil(unit_count / units_per_day).
## unit_count is the number of installable units for this action --
## commanders for a commander_prefix action, matching parts for a
## target_prefix action (passed in by the caller, which already resolved
## target_parts/groups). Explicit duration_days always takes precedence when
## both are present, so this is purely additive to the existing schema, not
## a breaking change -- see addons/construction_4d_tool/docs/00_4D_TOOL_OVERVIEW.md's Phase 3 section.
## static: uses no instance state, and FormworkBuilder needs the exact same
## answer to decide whether an action has room for a formwork phase at all.
## Sharing the function rather than replicating the rule is what keeps the
## scene it builds and the schedule that drives it from drifting apart.
static func _resolve_duration_days(action: Dictionary, unit_count: int) -> float:
	if action.has("duration_days"):
		var explicit_days: float = action["duration_days"]
		return explicit_days if explicit_days > 0.0 else 1.0
	if action.has("units_per_day"):
		var units_per_day: float = action["units_per_day"]
		if units_per_day > 0.0 and unit_count > 0:
			return ceil(float(unit_count) / units_per_day)
	return 1.0

## How long the pour itself takes when nothing says otherwise. Formwork gets
## whatever is left of the action's window (07_FORMWORK.md): the tail is
## specified rather than the head because a pour is a fixed short operation
## whose length is a property of the element, while the prep expands to fill
## whatever the programme allows -- so when a revised IFC moves an element from
## 5 days to 8, "the pour takes 1 day" is still true and formwork absorbs the
## change, where "formwork takes 4 days" would silently leave a 4-day pour.
const DEFAULT_POUR_DAYS := 1.0

## Formwork lifecycle defaults (07_FORMWORK.md, decision 1). Forms come off at
## the end of the pour: strip_days is a *cure* delay, and defaulting it to 0
## is deliberate -- a real 7-day deck cure is available per action, but as a
## default a cure that outlives the next action's start reads as a scheduling
## bug to anyone watching rather than as concrete setting.
const DEFAULT_STRIP_DAYS := 0.0
const DEFAULT_FORMWORK_TYPE := "scale_up"
const DEFAULT_STRIP_TYPE := "fade_out"
## Bounds on the derived strip animation length, so a very long element doesn't
## spend four days stripping and a one-day form set doesn't vanish in a frame.
const MIN_STRIP_SPAN_DAYS := 0.25
const MAX_STRIP_SPAN_DAYS := 1.0

## The root-level "formwork_defaults" block, or {} -- a sibling of "steps",
## same placement and same reasoning as static_prefixes/excluded_prefixes: it
## describes the project, not one task, so a model path or a pour length is
## written once instead of onto every action.
##
## Note that a non-empty block turns formwork *on* for every action by default;
## that is what "defaults for every action" means. An action opts back out with
## "formwork": {"enabled": false} (or a bare false).
static func formwork_defaults(sequence_data: Dictionary) -> Dictionary:
	var raw = sequence_data.get("formwork_defaults")
	if raw == null:
		return {}
	if not (raw is Dictionary):
		push_warning("ConstructionSchedule: 'formwork_defaults' is not a dictionary, ignoring")
		return {}
	return raw

## Merges the root defaults with this action's own "formwork" block, key by key,
## the action winning. Returns {} when this action has no formwork at all --
## either nothing anywhere, or an explicit opt-out.
##
## static so the Phase 3 dock can ask the same question about a row without
## building a whole ConstructionSchedule, the same reason _action_id() and
## _depends_on_ids() are static.
static func resolve_formwork_config(action: Dictionary, defaults: Dictionary) -> Dictionary:
	var raw = action.get("formwork")
	if raw is bool:
		# "formwork": false -- the shorthand opt-out. "formwork": true is the
		# shorthand opt-IN, so it must not resolve to {} just because there are
		# no defaults to inherit -- see _explicit() below.
		return {} if not raw else _explicit(defaults.duplicate(true))
	if not (raw is Dictionary):
		if raw != null:
			push_warning("ConstructionSchedule: action '%s' has a 'formwork' field that is neither a dictionary nor a bool, ignoring it" % _action_id(action))
		return defaults.duplicate(true) if not defaults.is_empty() else {}

	var cfg: Dictionary = defaults.duplicate(true)
	for key in raw.keys():
		cfg[key] = raw[key]
	if cfg.get("enabled", true) == false:
		return {}
	return _explicit(cfg)

## An empty Dictionary is this file's sentinel for "no formwork at all", which
## collides with an action that opted in *explicitly* but supplied no fields:
## "formwork": {} and "formwork": true both merge to {} when there is no root
## formwork_defaults to inherit, and so behaved identically to having no
## formwork key at all -- silently, and contrary to what README.md documented as
## the way to turn the feature on for one action.
##
## Resolved by materialising the documented default rather than by introducing a
## second sentinel: every consumer already treats {} as off (_resolve_formwork_
## split(), FormworkBuilder._build_for_action(), _index_prefix_formwork()), and
## a non-empty cfg carrying exactly the pour length it would have defaulted to
## is both correct and the thing an author would have written by hand.
static func _explicit(cfg: Dictionary) -> Dictionary:
	if cfg.is_empty():
		cfg["pour_days"] = DEFAULT_POUR_DAYS
	return cfg

## Splits an action's window into a formwork phase and the pour that follows it,
## returning {formwork_days, pour_days} which always sum to duration_days.
##
## Without formwork this is {0.0, duration_days} -- i.e. the whole window is the
## action's own animation, byte-identical to the behaviour before this existed.
## That is the path every pre-formwork construction_steps.json takes.
##
## formwork_days wins over pour_days when both are given, the same precedence
## duration_days already has over units_per_day and start_date over depends_on.
##
## Two degenerate cases, both warned about rather than silently repaired into
## something that looks deliberate:
## - No room (duration_days <= pour_days): there is no formwork phase to show,
##   so the action falls back to its pre-formwork behaviour. A one-day element
##   genuinely has no visible prep phase, and stealing half its window to invent
##   one would be worse than showing nothing. This is expected output, not a fault.
## - Formwork longer than the whole window: an authoring error. Clamped to the
##   window, leaving a zero-length pour that snaps in at the end -- visibly
##   wrong, which is the point, and matched by a warning naming both numbers.
## `warn` is false when FormworkBuilder asks the same question while building
## the scene -- both callers need the identical answer, but only one of them
## should say so out loud, or every warning below appears twice per rebuild.
static func _resolve_formwork_split(action: Dictionary, defaults: Dictionary, duration_days: float, action_id: String, warn: bool = true) -> Dictionary:
	var cfg: Dictionary = resolve_formwork_config(action, defaults)
	# `config` carries the resolved block even on the no-room path, where the
	# window isn't split at all. Tier 1 needs it there: an action with
	# scene-modelled forms and no room for a formwork phase still schedules
	# those forms (see _schedule_formwork()), and it must still honour their
	# strip_days/strip_type while doing it.
	var whole: Dictionary = {"formwork_days": 0.0, "pour_days": duration_days, "config": cfg}
	if cfg.is_empty():
		return whole

	var formwork_days: float
	if cfg.has("formwork_days"):
		formwork_days = _formwork_number(cfg, "formwork_days", action_id, NAN, warn)
		if is_nan(formwork_days):
			return whole
	else:
		var pour: float = _formwork_number(cfg, "pour_days", action_id, DEFAULT_POUR_DAYS, warn)
		if is_nan(pour):
			pour = DEFAULT_POUR_DAYS
		formwork_days = duration_days - pour

	if formwork_days <= 0.0:
		if warn:
			push_warning("ConstructionSchedule: action '%s' is only %.2f day(s) long, which leaves no room for a formwork phase -- pouring across the whole window instead" % [action_id, duration_days])
		return whole
	if formwork_days >= duration_days:
		if warn:
			push_warning("ConstructionSchedule: action '%s' asks for %.2f day(s) of formwork in a %.2f-day window -- clamping, which leaves the pour no time at all" % [action_id, formwork_days, duration_days])
		formwork_days = duration_days

	return {"formwork_days": formwork_days, "pour_days": duration_days - formwork_days, "config": cfg}

## One numeric formwork field, or NAN if it is present but not a number (JSON
## gives numbers as float/int; anything else is an authoring mistake worth
## naming rather than coercing, since float("cuatro") is a perfectly quiet 0.0).
static func _formwork_number(cfg: Dictionary, key: String, action_id: String, fallback: float = NAN, warn: bool = true) -> float:
	if not cfg.has(key):
		return fallback
	var value = cfg[key]
	if value is float or value is int:
		return float(value)
	if warn:
		push_warning("ConstructionSchedule: action '%s' has a non-numeric formwork '%s' (%s), ignoring it" % [action_id, key, value])
	return NAN

## panel name -> the part it wraps, from the meta FormworkBuilder stamps on
## everything it generates. Doubles as the "is this part generated formwork?"
## set the target_prefix loop guards on.
static func _index_formwork_panels(building_parts: Dictionary) -> Dictionary:
	var index: Dictionary = {}
	for part_name in building_parts.keys():
		var node = building_parts[part_name]
		if node and node.has_meta(FormworkBuilder.META_OWNER):
			index[part_name] = String(node.get_meta(FormworkBuilder.META_OWNER))
	return index

## Tier 1 (07_FORMWORK.md): part name -> the action id whose formwork.prefix
## claimed it, across every action in the file.
##
## Resolved **before any action is scheduled**, and project-wide rather than per
## action, because the hazard is not an action matching its own forms -- it is
## action B's target_prefix matching action A's. A per-action check would run
## too late and see too little.
##
## Deliberately *not* the formwork_of meta that generated panels carry, even
## though that is the guard the rest of this file already has. Two reasons, both
## fatal: FormworkBuilder.sweep() deletes everything carrying that meta, so
## stamping it on scene-resident geometry would make Start Preview delete the
## user's model; and CollisionQuery.setup() skips it, whereas tier-1 formwork is
## an ordinary scene part that stays clash-checked (decision 3).
static func _index_prefix_formwork(sequence_data: Dictionary, building_parts: Dictionary, defaults: Dictionary) -> Dictionary:
	var index: Dictionary = {}
	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var cfg: Dictionary = resolve_formwork_config(action, defaults)
			if cfg.is_empty():
				continue
			var prefix: String = String(cfg.get("prefix", ""))
			if prefix == "":
				continue
			var action_id: String = _action_id(action)
			var matched := 0
			for part_name in building_parts.keys():
				if not part_name.begins_with(prefix):
					continue
				# A generated panel is never also tier-1 formwork, however the
				# prefix happens to be spelled.
				var node = building_parts[part_name]
				if node and node.has_meta(FormworkBuilder.META_OWNER):
					continue
				if index.has(part_name):
					push_warning("ConstructionSchedule: part '%s' matches the formwork.prefix of both '%s' and '%s' -- keeping the first" % [part_name, index[part_name], action_id])
					continue
				index[part_name] = action_id
				matched += 1
			if matched == 0:
				# Warned, but the window is still split: the author asked for a
				# formwork phase and a short pour, and quietly re-lengthening the
				# pour would hide the typo instead of surfacing it.
				push_warning("ConstructionSchedule: action '%s' has formwork.prefix '%s', which matches no part in the scene -- its formwork phase will be empty" % [action_id, prefix])
	return index

## building_parts with every kind of formwork removed -- generated panels by
## their meta, tier-1 forms by the index above. Both prefix-matching branches of
## _init() run against this instead of the full dictionary, which is what makes
## "an action can never pour its own forms" a property of the data rather than
## of what anything happens to be named.
static func _parts_excluding_formwork(building_parts: Dictionary, generated: Dictionary, tier1: Dictionary) -> Dictionary:
	if generated.is_empty() and tier1.is_empty():
		return building_parts
	var out: Dictionary = {}
	for part_name in building_parts.keys():
		if generated.has(part_name) or tier1.has(part_name):
			continue
		out[part_name] = building_parts[part_name]
	return out

## Which parts are this action's formwork: its tier-1 parts if it has any, else
## the panels FormworkBuilder generated around its own target parts.
##
## Tier 1 wins outright rather than merging, matching "first match wins" in the
## tier table -- and FormworkBuilder generates nothing for a tier-1 action, so
## the two sets are never both populated in practice anyway.
static func _formwork_parts_for(target_parts: Array, generated: Dictionary,
		tier1: Dictionary, action_id: String) -> Array:
	var names: Array = []
	for part_name in tier1.keys():
		if tier1[part_name] == action_id:
			names.append(part_name)
	if not names.is_empty():
		return names
	var owners: Dictionary = {}
	for p in target_parts:
		owners[p] = true
	for panel_name in generated.keys():
		if owners.has(generated[panel_name]):
			names.append(panel_name)
	return names

## Gives every part in `panel_names` a window inside
## [start_day, start_day + span_days] -- the head of the action, before its own
## animation begins.
##
## `span_days` is 0 for a tier-1 action with no room for a formwork phase, which
## collapses the assemble into an instant at the action's start and leaves hold
## and strip intact. That case is the one place tiers diverge, and the asymmetry
## is forced: geometry that was never generated is simply absent, but geometry
## already in the scene and excluded from work matching would otherwise be left
## with no window at all -- hidden and zero-scaled for the entire run, invisible
## forever. _formwork_instant() already guards its assemble branch on
## `assemble_end > 0.0`, so it costs nothing.
##
## Panels stagger **even when the action batches**. That inversion is
## deliberate: `batch: true` is correct for the concrete (one pour split into
## several meshes must rise together) and wrong for the forms, which genuinely
## go up one after another. Concrete pours usually batch, so inheriting it
## would pop an entire form set into existence in a single frame and waste the
## days it was given. Override per action with "formwork": {"batch": true}.
func _schedule_formwork(panel_names: Array, panels_by_part: Dictionary, cfg: Dictionary,
		action_id: String, start_day: float, span_days: float, action_end_day: float,
		building_parts: Dictionary) -> void:
	if panel_names.is_empty():
		return

	panel_names = SpatialGrouper.sort_by_position(panel_names, building_parts)
	var cadence_action: Dictionary = {"batch": cfg.get("batch", false)}
	for key in ["stagger", "stagger_accel", "stagger_min", "dur", "dur_accel", "dur_min"]:
		if cfg.has(key):
			cadence_action[key] = cfg[key]

	var timings: Array = Cadence.compute_timings(panel_names, cadence_action, 1.0, 0.75)
	if timings.is_empty():
		return
	var total_cadence_sec: float = maxf(timings[-1].offset_sec + timings[-1].duration_sec, 0.01)
	var assemble_type: String = cfg.get("type", DEFAULT_FORMWORK_TYPE)
	var strip_type: String = cfg.get("strip_type", DEFAULT_STRIP_TYPE)

	# Lost formwork (encofrado perdido) genuinely stays in the finished
	# structure, so "the forms always come off" is a default rather than a law.
	# With stripping off a panel is a plain one-shot animation over the formwork
	# window, which is exactly what it was before this lifecycle existed.
	var strip_enabled: bool = cfg.get("strip", true) != false

	# Cure first, then come off. strip_days extends past the action's finish on
	# purpose -- a dependent action starting while its predecessor's forms are
	# still standing is realistic, and it is why only _update_bounds() is fed
	# here and never _action_finish_days, which depends_on resolves against.
	var strip_days: float = _formwork_number(cfg, "strip_days", action_id, DEFAULT_STRIP_DAYS)
	if is_nan(strip_days):
		strip_days = DEFAULT_STRIP_DAYS
	# Derived rather than another mandatory field: a quarter of however long the
	# forms took to build, bounded so a very long element doesn't spend four days
	# stripping and a short lift doesn't vanish in a single frame.
	var strip_span: float = _formwork_number(cfg, "strip_span_days", action_id,
		clampf(span_days * 0.25, MIN_STRIP_SPAN_DAYS, MAX_STRIP_SPAN_DAYS))
	if is_nan(strip_span) or strip_span <= 0.0:
		strip_span = clampf(span_days * 0.25, MIN_STRIP_SPAN_DAYS, MAX_STRIP_SPAN_DAYS)

	var strip_start_day: float = action_end_day + strip_days
	var strip_end_day: float = strip_start_day + strip_span

	for timing in timings:
		var panel_start: float = start_day + (timing.offset_sec / total_cadence_sec) * span_days
		var panel_end: float = start_day + ((timing.offset_sec + timing.duration_sec) / total_cadence_sec) * span_days

		var anim_type: String = assemble_type
		var window_end: float = panel_end
		if strip_enabled:
			anim_type = AnimationApplier.FORMWORK_TYPE
			window_end = strip_end_day
			# Panels assemble staggered but strip together, so every panel has a
			# different total span and therefore its own phase boundaries --
			# which is why these live on the part rather than on the action.
			var total: float = maxf(window_end - panel_start, 0.0001)
			building_parts[timing.part_name].set_meta(AnimationApplier.FORMWORK_PHASES_META, {
				"assemble_end": clampf((panel_end - panel_start) / total, 0.0, 1.0),
				"strip_start": clampf((strip_start_day - panel_start) / total, 0.0, 1.0),
				"assemble_type": assemble_type,
				"strip_type": strip_type,
			})

		_part_schedules[timing.part_name] = {
			"start_day": panel_start,
			"end_day": window_end,
			"anim_type": anim_type
		}
		_update_bounds(panel_start, window_end)
		# Roll a *generated* panel up to the element it wraps. Generated panels
		# carry no collision shape today (see CollisionQuery.setup()), so nothing
		# reads this yet -- but it is the correct answer, and it is what makes
		# re-enabling their collision a one-line change rather than a redesign.
		#
		# Tier-1 forms are deliberately left out: they are real scene parts that
		# are collision-registered today, and giving them a commander would
		# change how a clash involving them is reported -- for geometry whose
		# behaviour this step is otherwise not touching.
		if panels_by_part.has(timing.part_name):
			_part_to_commander[timing.part_name] = panels_by_part[timing.part_name]

## Parses a "YYYY-MM-DD" date string into a unix epoch, or NAN if unparseable.
## static -- no instance state involved -- so both _resolve_epoch() below and
## the Phase 3 dock's local Start+Duration -> End Date arithmetic (an
## explicit-date row's End Date doesn't need a full ConstructionSchedule
## instance, just this conversion) can share it.
static func parse_date_to_epoch(date_str: String) -> float:
	var epoch = Time.get_unix_time_from_datetime_string(date_str + "T00:00:00")
	return NAN if epoch < 0 else epoch

## Inverse of parse_date_to_epoch(): formats a unix epoch back to "YYYY-MM-DD",
## or "" for NAN/infinite input. static for the same reason as
## parse_date_to_epoch() -- shared by day_to_date_string() below and directly
## by the dock for explicit-date rows.
static func format_epoch_as_date(epoch: float) -> String:
	if is_nan(epoch) or is_inf(epoch):
		return ""
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(epoch))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

## Composite date-math helpers built on the two above -- the "Start + Duration
## = End" invariant the Phase 3 dock's inspector (ScheduleInspector) and CSV
## import/export (ScheduleCsvIO) both need. Centralized here rather than
## duplicated in each of those, since both already depend on this class for
## parse_date_to_epoch()/format_epoch_as_date(). "" / -1.0 signal an
## unparseable input, same NAN-propagation convention the two functions above
## already use.
static func end_date_from_start_and_duration(start_date: String, duration_days: float) -> String:
	var start_epoch: float = parse_date_to_epoch(start_date)
	if is_nan(start_epoch):
		return ""
	return format_epoch_as_date(start_epoch + duration_days * 86400.0)

static func duration_from_start_and_end(start_date: String, end_date: String) -> float:
	var start_epoch: float = parse_date_to_epoch(start_date)
	var end_epoch: float = parse_date_to_epoch(end_date)
	if is_nan(start_epoch) or is_nan(end_epoch):
		return -1.0
	return (end_epoch - start_epoch) / 86400.0

static func start_date_from_end_and_duration(end_date: String, duration_days: float) -> String:
	var end_epoch: float = parse_date_to_epoch(end_date)
	if is_nan(end_epoch):
		return ""
	return format_epoch_as_date(end_epoch - duration_days * 86400.0)

## Parses a "YYYY-MM-DD" start_date into a unix epoch, caching by string so
## a bad date is only warned about once even though it's parsed in both
## passes above. Returns NAN if unparseable.
func _resolve_epoch(start_date: String, cache: Dictionary) -> float:
	if cache.has(start_date):
		return cache[start_date]
	var epoch = parse_date_to_epoch(start_date)
	if is_nan(epoch):
		push_warning("ConstructionSchedule: invalid start_date '%s', treating as day 0" % start_date)
	cache[start_date] = epoch
	return epoch

func _update_bounds(s: float, e: float):
	if s < _min_day: _min_day = s
	if e > _max_day: _max_day = e

# Shared by _cache_ground_start() (per-part install fallback position) and
# the install-unit recording above (crane swing target) -- pure geometry,
# resolved once per commander before crane assignment even happens (nearest-
# crane assignment needs this world position as an input, see _assign_crane()).
func _resolve_commander_world_pos(cmd: Node3D) -> Vector3:
	var cmd_orig_transform: Transform3D = cmd.get_meta("original_transform")
	var world_pos: Vector3 = cmd_orig_transform.origin
	if cmd.has_meta("original_aabb"):
		var aabb_center: Vector3 = cmd.get_meta("original_aabb").get_center()
		world_pos = cmd_orig_transform * aabb_center
	return world_pos

## Where this commander's parts get lifted from -- crane.get_pickup_position()
## if a crane was assigned, else the pre-multi-crane fallback (target + 15
## units on X) so an action with no crane available (cranes Dictionary empty,
## e.g. the Phase 3 dock's editor preview) or that a crane_id/nearest-distance
## search genuinely couldn't resolve still gets a sane, deterministic pickup
## point instead of erroring.
func _crane_pickup_position(world_pos: Vector3, crane: Crane) -> Vector3:
	if crane:
		return crane.get_pickup_position(world_pos)
	return world_pos + Vector3(15.0, 0, 0)

## Assigns one crane to a commander given its resolved world position, an
## explicit crane_id override (from the action's own "crane_id" field, "" if
## absent), and the full set of cranes available in the scene. Nearest-by-
## horizontal-distance is the default; an explicit override that doesn't
## match any known crane name is warned about once and falls through to
## nearest-by-distance rather than blocking (see this class's header comment
## for why). Returns {"crane": Crane_or_null, "crane_id": String} -- both null/
## "" when `cranes` is empty (no crane in the scene at all, e.g. the Phase 3
## dock's editor preview).
func _assign_crane(world_pos: Vector3, cranes: Dictionary, explicit_crane_id: String) -> Dictionary:
	if cranes.is_empty():
		return {"crane": null, "crane_id": ""}
	if explicit_crane_id != "":
		if cranes.has(explicit_crane_id):
			return {"crane": cranes[explicit_crane_id], "crane_id": explicit_crane_id}
		push_warning("ConstructionSchedule: crane_id '%s' doesn't match any crane in the scene, falling back to nearest-by-distance" % explicit_crane_id)

	var target_xz := Vector2(world_pos.x, world_pos.z)
	var best_id := ""
	var best_crane: Crane = null
	var best_dist := INF
	for id in cranes.keys():
		var crane: Crane = cranes[id]
		var dist: float = target_xz.distance_to(Vector2(crane.global_position.x, crane.global_position.z))
		if dist < best_dist:
			best_dist = dist
			best_id = id
			best_crane = crane
	return {"crane": best_crane, "crane_id": best_id}

func _cache_ground_start(part_name: String, world_pos: Vector3, crane: Crane, building_parts: Dictionary) -> void:
	var part = building_parts.get(part_name)
	if not part: return
	if part.has_meta("install_ground_start"): return

	part.set_meta("install_ground_start", _crane_pickup_position(world_pos, crane))

## Returns {min_day, max_day}: the day-number bounds of the whole schedule.
## Use this to size a timeline slider's min/max range.
func get_date_range() -> Dictionary:
	return { "min_day": _min_day, "max_day": _max_day }

## Returns {start_day, finish_day} for a resolved action_id (see _action_id()),
## or {} if unknown. Lets the Phase 3 dock show a Depends On row's *actual*
## resolved schedule -- as opposed to an explicit-date row, which can compute
## its own End Date locally from start_date + duration_days without needing
## this, since a dependency-driven action has no literal start_date to do
## that arithmetic from.
func get_action_day_range(action_id: String) -> Dictionary:
	if not _action_start_days.has(action_id) or not _action_finish_days.has(action_id):
		return {}
	return { "start_day": _action_start_days[action_id], "finish_day": _action_finish_days[action_id] }

## Converts a relative day number (as used throughout this class -- day 0 is
## the project's earliest start_date, not the unix epoch) back to a real
## "YYYY-MM-DD" calendar date, via the epoch _init() already resolved day 0
## against. "" if day is NAN/infinite.
func day_to_date_string(day: float) -> String:
	if is_nan(day) or is_inf(day):
		return ""
	return format_epoch_as_date(_min_epoch + day * 86400.0)

## Whether day 0 resolved to a real calendar date at all. False for a schedule
## whose actions carry no parseable start_date (every action falls back to day
## 0, leaving _min_epoch at 0.0) -- in which case day_to_date_string() would
## happily report 1970-01-01 for day 0, which is meaningless rather than
## merely approximate. Callers that display dates should fall back to the raw
## relative day number instead.
func has_calendar_dates() -> bool:
	return _min_epoch > 0.0

## Day number -> unix epoch seconds. Same conversion day_to_date_string() does
## internally, exposed so callers needing more than a "YYYY-MM-DD" string (a
## weekday, a localized format) don't have to parse that string back.
func day_to_epoch(day: float) -> float:
	return _min_epoch + day * 86400.0

## Returns one entry per commander unit whose action type is "install":
## {start_day, pickup_pos, target_pos, tracked_part_name, lift_dur,
## slide_dur}. Consumed by TimelineController to fire one Crane.swing() per
## unit as forward playback crosses its start_day (never during scrub).
func get_install_units() -> Array:
	return _install_units

func get_fill_up_units() -> Array:
	return _fill_up_units

## The core query: given a day number, returns every scheduled part's state
## as {anim_type, progress} where progress in [0, 1] (0 = not started yet,
## 1 = complete). Feed this straight into AnimationApplier.apply_instant()
## per part. Clamps and caches internally; never errors on an out-of-range
## current_day.
func get_part_states(current_day: float) -> Dictionary:
	var cache_key = int(round(current_day * 100.0))
	if cache_key == _state_cache_key:
		return _state_cache

	var states = {}
	for part_name in _part_schedules.keys():
		var sched = _part_schedules[part_name]
		var progress = 0.0
		if current_day >= sched.end_day:
			progress = 1.0
		elif current_day > sched.start_day:
			var span = sched.end_day - sched.start_day
			if span <= 0.0:
				progress = 1.0
			else:
				progress = (current_day - sched.start_day) / span

		states[part_name] = {
			"anim_type": sched.anim_type,
			"progress": progress
		}

	_state_cache_key = cache_key
	_state_cache = states
	return states

## Whether any part is animated with "install" -- the only kind of part
## CollisionQuery ever checks as a mover. Without one no collision can exist
## on any day, so a full-schedule scan can be skipped outright.
func has_install_parts() -> bool:
	for sched in _part_schedules.values():
		if sched.anim_type == "install":
			return true
	return false

## Phase 2: flags parts actively being installed whose actual mesh geometry
## overlaps any other currently-present part's actual mesh geometry -- see
## CollisionQuery.query() (collision_query.gd) for the full exact-shape-query
## design rationale (why not AABB, why not Area3D, why a mover's convex hull
## against every other part's exact trimesh). get_part_states() stays here
## since it's core schedule state (_part_schedules/_state_cache); everything
## else about the query -- physics shapes, active/mover filtering, per-
## commander-pair dedup -- is CollisionQuery's job. building_parts must
## already reflect current_day's state (call this right after
## TimelineController.scrub_to(current_day), not standalone).
func get_collisions(current_day: float, building_parts: Dictionary) -> Array:
	var states = get_part_states(current_day)
	return _collision_query.query(building_parts, states, _sibling_groups, _part_to_commander)
