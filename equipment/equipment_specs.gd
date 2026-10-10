@tool
class_name EquipmentSpecs
extends RefCounted

## Published measurements of real machines, kept as JSON next to this script
## (equipment/specs/<id>.json): every figure in millimetres as the
## manufacturer prints it, with the document it came from, the configuration
## it applies to and the date it was retrieved.
##
## The procedural models are sized from them (the test checks the model
## against its sheet), and clash detection can use them directly -- a
## machine's working range, tail swing radius and transport envelope are
## exactly the volumes a check needs, and they are the manufacturer's, not the
## model's. See docs/13_SITE_EQUIPMENT.md, "Measurements".

const DIR := "res://addons/construction_4d_tool/equipment/specs/"
const EXCAVATOR := "excavator_cat_320"

static var _cache: Dictionary = {}


## The whole spec for `id` (a file name in DIR without .json), or {} with an
## error when it is missing or unreadable.
static func load_spec(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := DIR + id + ".json"
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text) if text != "" else null
	if not (data is Dictionary):
		push_error("EquipmentSpecs: cannot read %s" % path)
		return {}
	_cache[id] = data
	return data


## One figure, converted from millimetres to metres: `section` is "dimensions",
## "front" or "working_ranges". NAN when absent.
static func metres(id: String, section: String, key: String) -> float:
	var value = load_spec(id).get(section, {}).get(key)
	return float(value) / 1000.0 if value is float or value is int else NAN


## Every id in DIR.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out
