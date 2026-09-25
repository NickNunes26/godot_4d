@tool
class_name IfcGeoref
extends RefCounted

## Reads where an IFC model sits on Earth straight from its STEP text, without
## loading its geometry. Three shapes occur in practice and all are handled:
##
## 1. IfcMapConversion (+ IfcProjectedCRS): the model is in local coordinates
##    and the conversion says where local (0,0,0) is on the map, how the local
##    x axis is rotated relative to grid east, and at what scale.
## 2. Map coordinates in the root placement: the root IfcLocalPlacement's point
##    carries e.g. (452300, 4461200, 650) and there is no map conversion.
## 3. Both, or neither (a model that is simply not georeferenced).
##
## A best-effort text reader, not a full STEP parser (same stance as
## GDIFCRecenter): it only looks at the handful of entities involved.

## Everything found, as plain 64-bit floats:
## {
##   "map_conversion": {} or {"e","n","h","abscissa","ordinate","scale"},
##   "crs_name": String, "crs_zone": int (0 = not declared),
##   "root_points": Array of {"id": String, "coords": PackedFloat64Array},
## }
static func read(text: String) -> Dictionary:
	var out := {"map_conversion": {}, "crs_name": "", "crs_zone": 0, "root_points": []}

	var entities := _entities(text, ["IFCMAPCONVERSION", "IFCMAPCONVERSIONSCALED", "IFCPROJECTEDCRS"])
	for ent in entities:
		var args := split_args(ent.args)
		if ent.type.begins_with("IFCMAPCONVERSION") and out.map_conversion.is_empty() and args.size() >= 5:
			var mc := {
				"e": _num(args, 2, 0.0), "n": _num(args, 3, 0.0), "h": _num(args, 4, 0.0),
				"abscissa": _num(args, 5, 1.0), "ordinate": _num(args, 6, 0.0), "scale": _num(args, 7, 1.0),
			}
			if is_zero_approx(mc.scale):
				mc.scale = 1.0
			out.map_conversion = mc
			var target := String(args[1]).strip_edges()
			var crs := _entity_by_id(text, target)
			if not crs.is_empty() and crs.type == "IFCPROJECTEDCRS":
				_read_crs(split_args(crs.args), out)
	if out.crs_zone == 0:
		for ent in entities:
			if ent.type == "IFCPROJECTEDCRS":
				_read_crs(split_args(ent.args), out)
				if out.crs_zone != 0:
					break

	for root in root_placement_points(text):
		out.root_points.append(root)
	return out

## Every root placement's point: IfcLocalPlacement($, #axis) ->
## IfcAxis2Placement3D(#point, ...) -> IfcCartesianPoint((x, y, z)).
static func root_placement_points(text: String) -> Array:
	var out: Array = []
	var seen := {}
	var root_re := RegEx.new()
	root_re.compile("(?im)^#\\d+\\s*=\\s*IFCLOCALPLACEMENT\\(\\s*\\$\\s*,\\s*#(\\d+)\\s*\\)")
	for m in root_re.search_all(text):
		var axis := _entity_by_id(text, "#" + m.get_string(1))
		if axis.is_empty() or axis.type != "IFCAXIS2PLACEMENT3D":
			continue
		var point_id := String(split_args(axis.args)[0]).strip_edges()
		if seen.has(point_id):
			continue
		seen[point_id] = true
		var point := _entity_by_id(text, point_id)
		if point.is_empty() or point.type != "IFCCARTESIANPOINT":
			continue
		var coords := parse_float_list(point.args)
		while coords.size() < 3:
			coords.append(0.0)
		out.append({"id": point_id, "coords": coords})
	return out

## "(1.,2.,3.)" (optionally wrapped in the entity's own parentheses) -> floats.
static func parse_float_list(s: String) -> PackedFloat64Array:
	var inner := s.strip_edges()
	while inner.begins_with("("):
		inner = inner.substr(1)
	while inner.ends_with(")"):
		inner = inner.substr(0, inner.length() - 1)
	var out := PackedFloat64Array()
	for part in inner.split(",", false):
		out.append(_step_float(part))
	return out

## Top-level comma split of a STEP argument list (nested parentheses and
## quoted strings are kept whole).
static func split_args(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var in_str := false
	var cur := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if in_str:
			cur += ch
			if ch == "'":
				if i + 1 < s.length() and s[i + 1] == "'":
					cur += "'"
					i += 1
				else:
					in_str = false
		elif ch == "'":
			in_str = true
			cur += ch
		elif ch == "(":
			depth += 1
			cur += ch
		elif ch == ")":
			depth -= 1
			cur += ch
		elif ch == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
		i += 1
	if not cur.strip_edges().is_empty() or not out.is_empty():
		out.append(cur.strip_edges())
	return out

static func _read_crs(args: PackedStringArray, out: Dictionary) -> void:
	var name := _unquote(args[0]) if args.size() > 0 else ""
	var zone_text := _unquote(args[5]) if args.size() > 5 else ""
	if out.crs_name == "":
		out.crs_name = name
	for candidate in [zone_text, name]:
		var z := Utm.zone_from_crs_text(candidate)
		if z != 0:
			out.crs_zone = z
			return

static func _unquote(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with("'") and t.ends_with("'") and t.length() >= 2:
		return t.substr(1, t.length() - 2).replace("''", "'")
	return ""

## A STEP number, tolerating "$"/"*" (unset) and typed wrappers such as
## IFCLENGTHMEASURE(12.5).
static func _step_float(s: String) -> float:
	var t := s.strip_edges()
	var open := t.find("(")
	if open >= 0 and t.ends_with(")"):
		t = t.substr(open + 1, t.length() - open - 2)
	return t.to_float()

static func _num(args: PackedStringArray, i: int, default: float) -> float:
	if i >= args.size():
		return default
	var t := args[i].strip_edges()
	if t == "$" or t == "*" or t.is_empty():
		return default
	return _step_float(t)

## All entities of the given types: [{id, type, args}], args without the outer
## parentheses. Entities may span lines.
static func _entities(text: String, types: Array) -> Array:
	var re := RegEx.new()
	re.compile("(?im)^(#\\d+)\\s*=\\s*(%s)\\s*\\(([^;]*)\\)\\s*;" % "|".join(types))
	var out: Array = []
	for m in re.search_all(text):
		out.append({"id": m.get_string(1), "type": m.get_string(2).to_upper(), "args": m.get_string(3)})
	return out

static func _entity_by_id(text: String, id: String) -> Dictionary:
	if not id.begins_with("#"):
		return {}
	var re := RegEx.new()
	re.compile("(?im)^%s\\s*=\\s*([A-Z0-9_]+)\\s*\\(([^;]*)\\)\\s*;" % id)
	var m := re.search(text)
	if not m:
		return {}
	return {"id": id, "type": m.get_string(1).to_upper(), "args": m.get_string(2)}
