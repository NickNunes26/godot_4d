@tool
class_name IFCScheduleGenerator
extends RefCounted

## Builds a `construction_steps.json` schedule from the IFC property values the
## adapter's parts still carry, using the properties the user selected
## (IfcMapping) -- no property name is known to this class.
##
## One action is emitted per distinct Element ID value, matched by
## `target_prefix`. That works because the adapter names each part after its
## Element ID and de-duplicates collisions with a numeric suffix (`A`, `A_2`,
## ...), while schedule matching is `begins_with()` -- so a single prefix picks
## up every part sharing that id.

const SECONDS_PER_DAY := 86400.0

## The two animation types that describe placing a discrete manufactured unit,
## and are therefore the exception to automatic batching (see _batch_for()).
## Everything else is treated as one pour split into several meshes, which
## must move together.
const _STAGGERED_TYPES: Array = ["install", "drop_in"]


## Returns a `{"steps": [...], "static_prefixes": [...], "excluded_prefixes":
## [...]}` Dictionary ready to be written as construction_steps.json, or {}
## (with an error logged) when `mapping` is missing a required role.
## `parts` is the flat container the adapter produced, or an Array of parts
## (SequenceManager.collect_part_nodes(): every model in the scene).
##
## `existing` is the previously-parsed contents of the file about to be
## overwritten (read_existing()). Generation is wholesale, so anything
## hand-authored that cannot be re-derived from the IFC must be carried across
## or it is destroyed on every re-import:
##   - the two geometry lists (decisions about the model, not the schedule);
##   - an action's `type` and `batch`, **when the author changed them** -- see
##     _resolve_type_and_batch().
##
## Mutates `mapping.last_generated`; the caller should save the mapping again.
static func generate(parts: Variant, mapping: IfcMapping, existing: Dictionary = {}) -> Dictionary:
	if mapping == null or not mapping.is_valid():
		push_error("IFCScheduleGenerator: mapping incomplete (missing: %s)" % ", ".join(mapping.missing_roles() if mapping else ["everything"]))
		return {}

	var groups := {}      # element id -> aggregated action data
	var contextual := {}  # ifc_zone -> part count, for parts with no schedule

	var excluded: Array = _carry_forward(existing, "excluded_prefixes")
	var carried_static: Array = _carry_forward(existing, "static_prefixes")
	var existing_actions := _actions_by_id(existing)

	var part_nodes: Array = parts.get_children() if parts is Node else parts
	for part in part_nodes:
		# Excluded geometry is dropped here rather than at load time, so it
		# produces neither an action nor a static entry even when it carries a
		# perfectly good id and dates. That is the point of the list: "this
		# part is not in this project," not "this part is not scheduled."
		if _has_prefix(String(part.name), excluded):
			continue

		var props = part.get("properties")
		if not (props is Dictionary):
			props = {}

		var id_value = IfcMapping.get_value(props, mapping.element_id)
		var dates := _dates_for(props, mapping)

		# No id, or no usable date, means nothing to schedule -- record its
		# zone as static context instead of dropping it (initialize_parts()
		# hides and zero-scales every *registered, non-static* part, so a part
		# left out of the JSON entirely would stay invisible for the whole run).
		if id_value == null or str(id_value).strip_edges().is_empty() or dates.is_empty():
			var zone := _zone_prefix_of(part)
			contextual[zone] = contextual.get(zone, 0) + 1
			continue

		var key := str(id_value)
		if not groups.has(key):
			groups[key] = {
				"start": dates.start,
				"end": dates.end,
				"label": IfcMapping.get_value(props, mapping.display_name),
				"type_value": IfcMapping.get_value(props, mapping.type_source),
				"count": 0,
			}
		# Several parts can share one id with slightly different dates -- take
		# the widest window they span.
		var g: Dictionary = groups[key]
		if _epoch(dates.start) < _epoch(g.start):
			g.start = dates.start
		if _epoch(dates.end) > _epoch(g.end):
			g.end = dates.end
		g.count += 1

	var actions: Array = []
	var derived := {}
	for key in groups.keys():
		var g: Dictionary = groups[key]
		var derived_type := _type_for(g.type_value, mapping)
		var resolved := _resolve_type_and_batch(key, derived_type, existing_actions, mapping)
		derived[key] = {"type": derived_type, "batch": _batch_for(derived_type)}
		actions.append({
			"id": key,
			"target_prefix": key,
			"type": resolved.type,
			"batch": resolved.batch,
			"start_date": g.start,
			"duration_days": _calendar_days(g.start, g.end),
			"comment": "%s -- %d part(s), %s..%s" % [
				g.label if g.label != null else key, g.count, g.start, g.end,
			],
		})
	mapping.last_generated = derived

	actions.sort_custom(func(a, b):
		var ea := _epoch(a["start_date"])
		var eb := _epoch(b["start_date"])
		if ea == eb:
			return String(a["id"]) < String(b["id"])
		return ea < eb)

	# Context geometry -- parts with no id or no dates -- becomes a
	# static_prefixes entry per structural zone, not an action: it renders from
	# the first frame and never animates.
	var static_prefixes: Array = []
	for zone in contextual.keys():
		static_prefixes.append(zone)
	for prefix in carried_static:
		if not static_prefixes.has(prefix):
			static_prefixes.append(prefix)
	# Excluded wins: a prefix the author moved from static to excluded must not
	# reappear as static the next time the model is re-imported.
	static_prefixes = static_prefixes.filter(func(p): return not _has_prefix(p, excluded))
	static_prefixes.sort()
	excluded.sort()

	# Both lists are always written, even when empty: there is no UI for adding
	# a prefix, so an empty array sitting in the file is what tells an author
	# hand-editing it that the option exists and where it goes.
	return {
		"steps": [{"actions": actions}],
		"static_prefixes": static_prefixes,
		"excluded_prefixes": excluded,
	}


## The action's type and batching for this regeneration.
##
## A type is derived from the user's rules, but the author can then correct it
## in the inspector. Regenerating must not undo that. The mapping remembers
## what it derived last time (`last_generated`), so:
##   - existing value == what was derived last time -> the author never touched
##     it, so take the freshly derived value (rule edits take effect);
##   - existing value differs -> the author changed it, keep theirs;
##   - no record of the last derivation -> keep the existing value (conservative).
static func _resolve_type_and_batch(id: String, derived_type: String, existing_actions: Dictionary, mapping: IfcMapping) -> Dictionary:
	var derived_batch := _batch_for(derived_type)
	if not existing_actions.has(id):
		return {"type": derived_type, "batch": derived_batch}
	var ex: Dictionary = existing_actions[id]
	var last: Dictionary = mapping.last_generated.get(id, {})

	var type := derived_type
	if ex.has("type"):
		type = str(ex["type"]) if (not last.has("type") or str(ex["type"]) != str(last["type"])) else derived_type

	var batch := derived_batch
	if ex.has("batch"):
		batch = bool(ex["batch"]) if (not last.has("batch") or bool(ex["batch"]) != bool(last["batch"])) else derived_batch
	return {"type": type, "batch": batch}


static func _actions_by_id(existing: Dictionary) -> Dictionary:
	var out := {}
	var steps = existing.get("steps", [])
	if not (steps is Array):
		return out
	for step in steps:
		if not (step is Dictionary):
			continue
		for action in step.get("actions", []):
			if action is Dictionary and action.has("id"):
				out[str(action["id"])] = action
	return out


## The previously-generated file's contents, or {} when there is none (a first
## run) or it is unreadable/malformed. Never raises: a corrupt file must not
## block regenerating over the top of it, which is the usual way out of one.
static func read_existing(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## One root-level prefix list off a previously-parsed schedule, cleaned up the
## same way SequenceManager._prefix_list() cleans it at load time (strings,
## trimmed, no empties -- begins_with("") matches every part in the scene).
static func _carry_forward(existing: Dictionary, key: String) -> Array:
	var raw = existing.get(key, [])
	if not (raw is Array):
		return []
	var out: Array = []
	for entry in raw:
		var prefix := String(entry).strip_edges()
		if not prefix.is_empty() and not out.has(prefix):
			out.append(prefix)
	return out


static func _has_prefix(name: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if name.begins_with(prefix):
			return true
	return false


## Writes a generate() result to `path` as tab-indented JSON, matching what the
## dock's own "Save to JSON" button produces.
static func write_data(data: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


## The start/end pair for one part, from the selected properties. `end` comes
## from the End property if one is mapped, otherwise from start + Duration.
## Returns {} when a needed value is missing, is not an ISO date, or is one of
## the mapping's `ignore_dates`.
static func _dates_for(props: Dictionary, mapping: IfcMapping) -> Dictionary:
	var raw_start = IfcMapping.get_value(props, mapping.start)
	if raw_start == null or _is_ignored(raw_start, mapping):
		return {}
	var start := IfcMapping.to_date_string(raw_start)
	if start.is_empty():
		return {}

	var end := ""
	if not mapping.end.is_empty():
		var raw_end = IfcMapping.get_value(props, mapping.end)
		if raw_end == null or _is_ignored(raw_end, mapping):
			return {}
		end = IfcMapping.to_date_string(raw_end)
	else:
		var raw_days = IfcMapping.get_value(props, mapping.duration)
		if raw_days == null or not (raw_days is int or raw_days is float or (raw_days is String and (raw_days as String).is_valid_float())):
			return {}
		var days := maxi(int(ceil(float(raw_days))), 1)
		end = ConstructionSchedule.format_epoch_as_date(_epoch(start) + (days - 1) * SECONDS_PER_DAY)
	if end.is_empty():
		return {}
	return {"start": start, "end": end}


static func _is_ignored(raw, mapping: IfcMapping) -> bool:
	var text := str(raw).strip_edges()
	return mapping.ignore_dates.has(text) or mapping.ignore_dates.has(IfcMapping.to_date_string(raw))


## The zone-based name the adapter falls back to when a part has no Element ID
## ("<zone>_<original name>"), reduced to the prefix that matches every part in
## that zone.
static func _zone_prefix_of(part: Node) -> String:
	if part.has_meta("ifc_zone"):
		return "%s_" % part.get_meta("ifc_zone")
	return String(part.name)


## Whether an action's parts move together (`true`) or one after another.
##
## Written explicitly on every emitted action rather than left to Cadence's own
## `false` default, because the default is the wrong answer for most of an
## IFC-derived schedule: one id covering several meshes usually means one pour
## split for modelling convenience, not separate operations. Being explicit
## also makes it visible in the JSON and the inspector, where it is one toggle
## to change.
static func _batch_for(anim_type: String) -> bool:
	return not _STAGGERED_TYPES.has(anim_type)


## First matching user rule wins; otherwise the mapping's default type.
static func _type_for(type_value, mapping: IfcMapping) -> String:
	if type_value == null:
		return mapping.default_type
	var lower := str(type_value).to_lower()
	for rule in mapping.type_rules:
		if lower.contains(str(rule["contains"]).to_lower()):
			return str(rule["type"])
	return mapping.default_type


## Inclusive calendar-day span.
static func _calendar_days(start: String, end: String) -> int:
	var days := int(round((_epoch(end) - _epoch(start)) / SECONDS_PER_DAY)) + 1
	return maxi(days, 1)


static func _epoch(date: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(date))
