## Headless test for the IFC property-mapping pipeline, using an invented
## property layout so nothing here depends on any real project's naming.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_mapping.gd
extends SceneTree

class FakePart extends MeshInstance3D:
	var properties: Dictionary = {}

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _part(zone: Node, name: String, props: Dictionary) -> FakePart:
	var p := FakePart.new()
	p.name = name
	p.mesh = BoxMesh.new()
	p.properties = props
	zone.add_child(p)
	return p

func _init() -> void:
	# Invented layout: two property sets that BOTH have a "Label" property, to
	# prove lookup is by exact path and not by name suffix.
	var raw := Node3D.new()
	# Real GDIFC containers are mesh-less MeshInstance3D nodes; the adapter names a part
	# after its nearest such ancestor when it has no Element ID.
	var zone := MeshInstance3D.new(); zone.name = "ZoneOne"
	raw.add_child(zone)
	_part(zone, "m1", {"Ids": {"Code": "K1", "Label": "wrong"}, "Plan": {"Label": "Footing", "Begin": "2026-03-02", "Finish": "2026-03-04T08:00:00", "Days": "3", "Kind": "concrete slab"}})
	_part(zone, "m2", {"Ids": {"Code": "K1"}, "Plan": {"Label": "Footing", "Begin": "2026-03-03", "Finish": "2026-03-06", "Days": "3", "Kind": "concrete slab"}})
	_part(zone, "m3", {"Ids": {"Code": "K2"}, "Plan": {"Label": "Column", "Begin": "2026-03-10", "Finish": "2026-03-10", "Days": "1", "Kind": "steel column"}})
	_part(zone, "m4", {"Ids": {"Code": "K3"}, "Plan": {"Begin": "1900-01-01", "Finish": "1900-01-01", "Days": "1", "Kind": "other"}})
	_part(zone, "m5", {"Plan": {"Kind": "no code here"}})
	root.add_child(raw)   # the adapter reads global transforms, so the tree must be live

	print("=== scanner")
	var scan := IfcPropertyScanner.scan(raw)
	_check("parts scanned", scan.total, 5)
	var by_path := {}
	for p in scan.properties:
		by_path[IfcMapping.path_to_string(p.path)] = p
	_check("Plan / Begin is a date", by_path["Plan / Begin"].kind, "date")
	_check("Plan / Days is a number", by_path["Plan / Days"].kind, "number")
	_check("Ids / Code is text", by_path["Ids / Code"].kind, "text")
	_check("Ids / Code coverage", by_path["Ids / Code"].count, 4)

	print("=== mapping basics")
	var m := IfcMapping.new()
	_check("empty mapping is invalid", m.is_valid(), false)
	m.element_id = ["Ids", "Code"]
	m.start = ["Plan", "Begin"]
	_check("still needs an end or duration", m.is_valid(), false)
	m.end = ["Plan", "Finish"]
	m.display_name = ["Plan", "Label"]
	m.type_source = ["Plan", "Kind"]
	m.type_rules = [{"contains": "slab", "type": "fill_up"}]
	m.ignore_dates = ["1900-01-01"]
	_check("complete mapping is valid", m.is_valid(), true)
	var rt := IfcMapping.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check("round-trips through JSON", rt.to_dict(), m.to_dict())
	_check("exact path: Plan / Label", IfcMapping.get_value({"Ids": {"Label": "wrong"}, "Plan": {"Label": "right"}}, ["Plan", "Label"]), "right")
	_check("missing path is null", IfcMapping.get_value({"Plan": {}}, ["Plan", "Nope"]), null)
	_check("time part dropped from date", IfcMapping.to_date_string("2026-03-04T08:00:00"), "2026-03-04")
	_check("non-ISO is not a date", IfcMapping.to_date_string("04/03/2026"), "")
	_check("incomplete mapping generates nothing", IFCScheduleGenerator.generate(raw, IfcMapping.new()).is_empty(), true)

	print("=== text GDIFC mis-decodes")
	_check("UTF-8 read as Latin-1 is repaired", GDIFC4DAdapter.repair_string("FormigÃ³n de limpeza"), "Formigón de limpeza")
	_check("three-byte sequences too (en dash)", GDIFC4DAdapter.repair_string("Farol 4 â\u0080\u0093 luminaria".c_unescape()), "Farol 4 – luminaria")
	_check("correct text is left alone", GDIFC4DAdapter.repair_string("Formigón"), "Formigón")
	_check("genuine Latin-1 (not valid UTF-8) is left alone", GDIFC4DAdapter.repair_string("Cañón"), "Cañón")
	_check("ASCII is left alone", GDIFC4DAdapter.repair_string("C04_Limpeza"), "C04_Limpeza")
	_check("keys and nested values", GDIFC4DAdapter.repair_value({"Pset": {"Fase": "CimentaciÃ³n", "N": 3}}), {"Pset": {"Fase": "Cimentación", "N": 3}})
	var garbled := MeshInstance3D.new()
	garbled.set_meta("unused", true)
	var holder := Node3D.new()
	holder.add_child(garbled)
	_check("repair_text() on a tree with no text changes nothing", GDIFC4DAdapter.repair_text(holder), 0)
	holder.free()

	print("=== adapter names parts from the chosen property")
	var container := GDIFC4DAdapter.adapt(raw, m)
	var names := []
	for c in container.get_children():
		names.append(String(c.name))
	names.sort()
	_check("parts named by Element ID (dupes suffixed, uncoded by zone)", names, ["K1", "K1_2", "K2", "K3", "ZoneOne_m5"])
	root.add_child(container)

	print("=== generator, end-date mode")
	var data := IFCScheduleGenerator.generate(container, m)
	var actions: Array = data.steps[0].actions
	var by_id := {}
	for a in actions:
		by_id[a.id] = a
	_check("K1 and K2 scheduled, K3 (ignored date) and uncoded are not", by_id.keys().size(), 2)
	_check("K1 window merged over both parts", [by_id["K1"].start_date, by_id["K1"].duration_days], ["2026-03-02", 5])
	_check("K1 type from rule", by_id["K1"].type, "fill_up")
	_check("K1 batched (not a staggered type)", by_id["K1"].batch, true)
	_check("K2 falls back to default type", by_id["K2"].type, "scale_up")
	_check("label comes from the mapped property", String(by_id["K1"].comment).begins_with("Footing"), true)
	# K3 has an id but no usable date: its prefix is its own name, which is what
	# the adapter called it -- not its zone, which would match nothing.
	_check("K3 and the uncoded part become static context, by their names", data.static_prefixes, ["K3", "ZoneOne_"])

	print("=== generator, duration mode")
	var md := IfcMapping.from_dict(m.to_dict())
	md.end = []
	md.duration = ["Plan", "Days"]
	var d2 := IFCScheduleGenerator.generate(container, md)
	var k1 = d2.steps[0].actions.filter(func(a): return a.id == "K1")[0]
	# part 1: 03-02 + 3 days = ..03-04; part 2: 03-03 + 3 days = ..03-05; merged 03-02..03-05
	_check("duration mode: merged K1 window is 4 days", k1.duration_days, 4)

	print("=== hand-edited type survives regeneration; untouched type follows the rules")
	var existing := data.duplicate(true)
	for a in existing.steps[0].actions:
		if a.id == "K2":
			a.type = "rise_up"           # author corrected K2 by hand
	m.type_rules = [{"contains": "slab", "type": "drop_in"}]   # rules changed afterwards
	var d3 := IFCScheduleGenerator.generate(container, m, existing)
	var by3 := {}
	for a in d3.steps[0].actions:
		by3[a.id] = a
	_check("hand-edited K2 kept", by3["K2"].type, "rise_up")
	_check("untouched K1 follows the new rule", by3["K1"].type, "drop_in")
	_check("K1 now staggered (drop_in)", by3["K1"].batch, false)

	print("=== dialog builds, gates OK on required roles, and returns the picks")
	var dlg := IfcMappingDialog.new()
	root.add_child(dlg)
	dlg.setup(scan, null)
	_check("OK disabled with nothing chosen", dlg.get_ok_button().disabled, true)
	var pick := func(ob: OptionButton, path: Array):
		for i in ob.item_count:
			if ob.get_item_metadata(i) == path:
				ob.select(i)
				ob.item_selected.emit(i)
				return
		_check("picker offers %s" % IfcMapping.path_to_string(path), false, true)
	pick.call(dlg._element_id, ["Ids", "Code"])
	pick.call(dlg._start, ["Plan", "Begin"])
	_check("still disabled without end/duration", dlg.get_ok_button().disabled, true)
	pick.call(dlg._duration, ["Plan", "Days"])
	_check("enabled once required roles are set", dlg.get_ok_button().disabled, false)
	dlg._add_rule_row("slab", "fill_up")
	dlg._ignore_dates.text = "1900-01-01, 2000-01-01"
	var got := dlg._build_mapping()
	_check("dialog result: element id", got.element_id, ["Ids", "Code"])
	_check("dialog result: duration", got.duration, ["Plan", "Days"])
	_check("dialog result: rule", got.type_rules, [{"contains": "slab", "type": "fill_up"}])
	_check("dialog result: ignore dates", got.ignore_dates, ["1900-01-01", "2000-01-01"])
	var locked := IfcMappingDialog.new()
	root.add_child(locked)
	locked.setup(scan, m, true)
	_check("element id locked when re-editing", locked._element_id.disabled, true)
	_check("saved mapping pre-selects its properties", locked._build_mapping().start, ["Plan", "Begin"])

	print(("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
