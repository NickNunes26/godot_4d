@tool
class_name IfcMapping
extends RefCounted

## Which IFC properties mean what, as chosen by the user for their own model.
##
## The plugin ships no property names: every IFC authoring convention is
## different, so the user looks at the properties their file actually carries
## (IfcPropertyScanner) and picks one per role in IfcMappingDialog. This class
## is only the record of that choice, plus (de)serialisation.
##
## A property is addressed by its **exact path** -- `[property_set, property]`
## (deeper if the file nests further) -- never by suffix or substring, so two
## property sets that share a property name can never be confused.

## Saved beside the schedule JSON: `construction_steps.json` ->
## `construction_steps.ifc_profile.json`.
const FILE_SUFFIX := ".ifc_profile.json"

## Value names each part and becomes the action's `id` and `target_prefix`;
## parts sharing a value form one action. Required.
var element_id: Array = []
## Action start date. Required.
var start: Array = []
## Action end date. One of `end` / `duration` is required; `end` wins if both set.
var end: Array = []
## Action length in days.
var duration: Array = []
## Human label, written into the action's `comment`. Optional.
var display_name: Array = []
## Property whose value the `type_rules` are matched against. Optional.
var type_source: Array = []
## Animation type for an action no rule matches.
var default_type: String = "scale_up"
## Ordered `{"contains": String, "type": String}`; first match wins. Case-insensitive.
var type_rules: Array = []
## Date values to treat as "no date" (placeholders a model uses for "not scheduled").
## Empty unless the user adds some.
var ignore_dates: Array = []
## `{action_id: {"type": String, "batch": bool}}` as last derived from the rules,
## so a later regeneration can tell a hand-edited type from one it wrote itself
## (see IFCScheduleGenerator.generate()).
var last_generated: Dictionary = {}


static func profile_path_for(json_path: String) -> String:
	return json_path.get_basename() + FILE_SUFFIX


## Which required roles are still unset, as human-readable names.
func missing_roles() -> Array[String]:
	var missing: Array[String] = []
	if element_id.is_empty():
		missing.append("Element ID")
	if start.is_empty():
		missing.append("Start date")
	if end.is_empty() and duration.is_empty():
		missing.append("End date or Duration")
	return missing


func is_valid() -> bool:
	return missing_roles().is_empty()


## Every property path this mapping refers to, for checking against a scan.
func referenced_paths() -> Array:
	var out: Array = []
	for path in [element_id, start, end, duration, display_name, type_source]:
		if not path.is_empty():
			out.append(path)
	return out


static func path_to_string(path: Array) -> String:
	return " / ".join(path.map(func(p): return str(p)))


## The value at an exact path inside a (nested) property-set dictionary, or
## null when any step is missing.
static func get_value(props: Dictionary, path: Array):
	if path.is_empty():
		return null
	var node = props
	for key in path:
		if not (node is Dictionary) or not (node as Dictionary).has(key):
			return null
		node = node[key]
	if node is Dictionary:
		return null
	return node


## `YYYY-MM-DD` from an ISO-looking value (a trailing time part is dropped),
## or "" when the value is not a date. Only ISO dates are understood, since
## day/month order is otherwise ambiguous.
static func to_date_string(value) -> String:
	if not (value is String):
		return ""
	var s := (value as String).strip_edges()
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}")
	if re.search(s) == null:
		return ""
	return s.substr(0, 10)


func to_dict() -> Dictionary:
	return {
		"element_id": element_id,
		"start": start,
		"end": end,
		"duration": duration,
		"display_name": display_name,
		"type_source": type_source,
		"default_type": default_type,
		"type_rules": type_rules,
		"ignore_dates": ignore_dates,
		"last_generated": last_generated,
	}


static func from_dict(d: Dictionary) -> IfcMapping:
	var m := IfcMapping.new()
	m.element_id = _path(d.get("element_id"))
	m.start = _path(d.get("start"))
	m.end = _path(d.get("end"))
	m.duration = _path(d.get("duration"))
	m.display_name = _path(d.get("display_name"))
	m.type_source = _path(d.get("type_source"))
	m.default_type = str(d.get("default_type", "scale_up"))
	if not m.default_type in AnimationApplier.TYPES:
		m.default_type = "scale_up"
	var rules = d.get("type_rules")
	if rules is Array:
		for r in rules:
			if r is Dictionary and str(r.get("contains", "")).strip_edges() != "" and str(r.get("type", "")) in AnimationApplier.TYPES:
				m.type_rules.append({"contains": str(r["contains"]).strip_edges(), "type": str(r["type"])})
	var ign = d.get("ignore_dates")
	if ign is Array:
		for v in ign:
			var s := str(v).strip_edges()
			if not s.is_empty():
				m.ignore_dates.append(s)
	var lg = d.get("last_generated")
	if lg is Dictionary:
		m.last_generated = lg
	return m


static func _path(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for step in raw:
			out.append(str(step))
	return out


## The saved mapping at `path`, or null when there is none or it is unreadable.
static func load_from(path: String) -> IfcMapping:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return from_dict(parsed) if parsed is Dictionary else null


func save_to(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return OK
