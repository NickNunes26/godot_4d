## "Which IFC property means what?" popup, shown by TimelineDock after an IFC
## is imported (and by its Edit IFC mapping button). The plugin knows no
## property names, so the user picks, per role, from the properties the model
## actually carries -- listed with how many parts have each one and sample
## values, which is usually enough to tell a date from a code from a note.
##
## A ConfirmationDialog so Cancel is free; OK is disabled until the three
## required roles (Element ID, Start, End-or-Duration) are set.
@tool
class_name IfcMappingDialog
extends ConfirmationDialog

## Emitted on confirm with the finished IfcMapping.
signal mapping_confirmed(mapping: IfcMapping)

var _total := 0
var _properties: Array = []
var _base: IfcMapping = null

var _element_id: OptionButton
var _start: OptionButton
var _end: OptionButton
var _duration: OptionButton
var _display_name: OptionButton
var _type_source: OptionButton
var _default_type: OptionButton
var _rules_box: VBoxContainer
var _ignore_dates: LineEdit
var _rule_rows: Array = [] # [{contains: LineEdit, type: OptionButton, row: Control}]


func _init() -> void:
	title = "Map IFC Properties"
	min_size = Vector2i(720, 560)
	confirmed.connect(_on_confirmed)


## `scan` is IfcPropertyScanner.scan()'s result; `initial` pre-fills the pickers
## (a saved mapping). `lock_element_id` is for re-editing after parts were
## already named: changing Element ID then would orphan every schedule prefix,
## so it is shown but not editable -- re-import the model to change it.
func setup(scan: Dictionary, initial: IfcMapping, lock_element_id: bool = false) -> void:
	_total = scan.get("total", 0)
	_properties = scan.get("properties", [])
	_base = initial if initial else IfcMapping.new()

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var intro := Label.new()
	intro.text = "%d part(s) scanned, %d distinct properties found. Pick the property that carries each piece of information in YOUR model.\nEach entry shows how many parts have it, and sample values." % [_total, _properties.size()]
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_element_id = _picker(box, "Element ID *", "Names each part; parts sharing a value become one schedule action.", _base.element_id, "text", false)
	if lock_element_id:
		_element_id.disabled = true
		_element_id.tooltip_text = "Locked: parts are already named from this property. Re-import the model to change it."
	_start = _picker(box, "Start date *", "ISO dates (YYYY-MM-DD) only.", _base.start, "date", false)
	_end = _picker(box, "End date", "Use this OR Duration.", _base.end, "date", true)
	_duration = _picker(box, "Duration (days)", "Use this OR End date.", _base.duration, "number", true)
	_display_name = _picker(box, "Display name", "Optional label written into each action's comment.", _base.display_name, "text", true)

	box.add_child(HSeparator.new())
	var type_title := Label.new()
	type_title.text = "Animation type (optional)"
	box.add_child(type_title)
	_type_source = _picker(box, "Decide type from", "Rules below are matched against this property's value.", _base.type_source, "text", true)

	var default_row := HBoxContainer.new()
	var default_label := Label.new()
	default_label.text = "Default type"
	default_label.custom_minimum_size.x = 160
	default_row.add_child(default_label)
	_default_type = OptionButton.new()
	for t in AnimationApplier.TYPES:
		_default_type.add_item(t)
		_default_type.set_item_metadata(_default_type.item_count - 1, t)
		if t == _base.default_type:
			_default_type.select(_default_type.item_count - 1)
	default_row.add_child(_default_type)
	box.add_child(default_row)

	var rules_title := Label.new()
	rules_title.text = "Rules: if the value contains ... use type (first match wins)"
	box.add_child(rules_title)
	_rules_box = VBoxContainer.new()
	box.add_child(_rules_box)
	var add_rule := Button.new()
	add_rule.text = "Add rule"
	add_rule.pressed.connect(func(): _add_rule_row("", "scale_up"))
	box.add_child(add_rule)
	for r in _base.type_rules:
		_add_rule_row(str(r["contains"]), str(r["type"]))

	box.add_child(HSeparator.new())
	var ign_row := HBoxContainer.new()
	var ign_label := Label.new()
	ign_label.text = "Ignore dates equal to"
	ign_label.custom_minimum_size.x = 160
	ign_row.add_child(ign_label)
	_ignore_dates = LineEdit.new()
	_ignore_dates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ignore_dates.placeholder_text = "comma-separated placeholder dates, e.g. models that use a fixed date for 'not scheduled'"
	_ignore_dates.text = ", ".join(_base.ignore_dates)
	ign_row.add_child(_ignore_dates)
	box.add_child(ign_row)

	for picker in [_element_id, _start, _end, _duration]:
		picker.item_selected.connect(func(_i): _refresh_ok())
	_refresh_ok()


## A labelled OptionButton listing every scanned property, `prefer_kind` ones
## first. Item metadata is the property path (an empty Array for "(none)").
func _picker(parent: Control, label: String, tip: String, selected: Array, prefer_kind: String, optional: bool) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 160
	l.tooltip_text = tip
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.clip_text = true
	ob.tooltip_text = tip
	row.add_child(ob)
	parent.add_child(row)

	if optional:
		ob.add_item("(none)")
		ob.set_item_metadata(0, [])
	else:
		ob.add_item("(choose...)")
		ob.set_item_metadata(0, [])

	var ordered: Array = []
	for p in _properties:
		if p.kind == prefer_kind:
			ordered.append(p)
	for p in _properties:
		if p.kind != prefer_kind:
			ordered.append(p)
	for p in ordered:
		ob.add_item("%s   (%d of %d)  e.g. %s" % [IfcMapping.path_to_string(p.path), p.count, _total, "; ".join(p.samples)])
		var idx := ob.item_count - 1
		ob.set_item_metadata(idx, p.path)
		if p.path == selected:
			ob.select(idx)
	return ob


func _add_rule_row(contains: String, type: String) -> void:
	var row := HBoxContainer.new()
	var le := LineEdit.new()
	le.placeholder_text = "text the value contains"
	le.text = contains
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	var ob := OptionButton.new()
	for t in AnimationApplier.TYPES:
		ob.add_item(t)
		if t == type:
			ob.select(ob.item_count - 1)
	row.add_child(ob)
	var rm := Button.new()
	rm.text = "x"
	row.add_child(rm)
	_rules_box.add_child(row)
	var entry := {"contains": le, "type": ob, "row": row}
	_rule_rows.append(entry)
	rm.pressed.connect(func():
		_rule_rows.erase(entry)
		row.queue_free())


func _selected_path(ob: OptionButton) -> Array:
	return ob.get_item_metadata(ob.selected)


func _build_mapping() -> IfcMapping:
	var m := IfcMapping.new()
	m.element_id = _selected_path(_element_id)
	m.start = _selected_path(_start)
	m.end = _selected_path(_end)
	m.duration = _selected_path(_duration)
	m.display_name = _selected_path(_display_name)
	m.type_source = _selected_path(_type_source)
	m.default_type = str(_default_type.get_item_metadata(_default_type.selected))
	for entry in _rule_rows:
		var text := (entry.contains as LineEdit).text.strip_edges()
		if not text.is_empty():
			var ob: OptionButton = entry.type
			m.type_rules.append({"contains": text, "type": ob.get_item_text(ob.selected)})
	for piece in _ignore_dates.text.split(","):
		var s := piece.strip_edges()
		if not s.is_empty():
			m.ignore_dates.append(s)
	# Keep the derivation record so hand-edit detection survives re-editing.
	m.last_generated = _base.last_generated
	return m


func _refresh_ok() -> void:
	var m := _build_mapping()
	var missing := m.missing_roles()
	get_ok_button().disabled = not missing.is_empty()
	get_ok_button().tooltip_text = "" if missing.is_empty() else "Still needed: %s" % ", ".join(missing)


func _on_confirmed() -> void:
	mapping_confirmed.emit(_build_mapping())
