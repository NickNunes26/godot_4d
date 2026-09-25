@tool
class_name IfcPropertyScanner
extends RefCounted

## Lists every property an IFC model's parts actually carry, so the user can
## choose which one means what (see IfcMapping).
##
## Works on either the raw GDIFC tree or the flat container the adapter
## builds: both hold the same `properties` dictionaries on the same
## mesh-bearing nodes.

const MAX_SAMPLES := 3


## Returns `{"total": int, "properties": Array[Dictionary]}` where each
## property is `{path: Array, count: int, samples: Array[String], kind: String}`.
## `total` is the number of parts scanned; `count` is how many carry the
## property. `kind` is "date" (every value ISO-date-like), "number", or "text".
## Sorted by coverage, then name, so the properties present on most parts come first.
static func scan(root: Node) -> Dictionary:
	var by_key := {}
	var total := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var leaf := node as MeshInstance3D
		if leaf.mesh == null:
			continue
		total += 1
		_flatten(GDIFC4DAdapter.get_property_sets(leaf), [], by_key)

	var props: Array[Dictionary] = []
	for entry in by_key.values():
		var kind := "text"
		if entry.dates == entry.count:
			kind = "date"
		elif entry.numbers == entry.count:
			kind = "number"
		props.append({"path": entry.path, "count": entry.count, "samples": entry.samples, "kind": kind})

	props.sort_custom(func(a, b):
		if a.count != b.count:
			return a.count > b.count
		return IfcMapping.path_to_string(a.path) < IfcMapping.path_to_string(b.path))
	return {"total": total, "properties": props}


static func _flatten(dict: Dictionary, prefix: Array, out: Dictionary) -> void:
	for key in dict.keys():
		var value = dict[key]
		var path := prefix.duplicate()
		path.append(str(key))
		if value is Dictionary:
			_flatten(value, path, out)
			continue
		if value == null:
			continue
		var id := JSON.stringify(path)
		if not out.has(id):
			out[id] = {"path": path, "count": 0, "samples": [], "dates": 0, "numbers": 0}
		var entry: Dictionary = out[id]
		entry.count += 1
		var text := str(value)
		if not text.is_empty() and entry.samples.size() < MAX_SAMPLES and not entry.samples.has(text):
			entry.samples.append(text)
		if IfcMapping.to_date_string(value) != "":
			entry.dates += 1
		if value is int or value is float or (value is String and (value as String).is_valid_float()):
			entry.numbers += 1
