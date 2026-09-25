## CSV export/import for the Phase 3 dock's schedule inspector -- split out of
## timeline_dock.gd (see schedule_inspector.gd's header comment for why that
## file had grown too large). Pure file/Dictionary logic with no Control-tree
## dependency: TimelineDock owns the EditorFileDialog and calls export_csv()/
## import_csv() with a resolved path; this class never touches the dialog
## itself, which keeps it usable/testable independent of the dock's UI.
##
## Round-trips the same scheduling fields ScheduleInspector's grid edits --
## id, action (a read-only human-readable label), type, start_date, end_date,
## duration_days, units_per_day, depends_on, lag_days, comment -- not the full
## action Dictionary: geometry (commander_prefix/child_prefixes) and animation
## tuning (stagger*/dur_accel etc.) stay JSON-only, untouched by either
## direction. "end_date" is derived-only on export and only consulted on
## import as a fallback to compute duration_days when both duration_days and
## units_per_day are blank.
##
## Import matches each row to an existing action by its resolved id
## (ConstructionSchedule._action_id() -- explicit id, else commander_prefix/
## target_prefix). A row whose id has no match is warned about and skipped;
## import never creates a new action, since a new action needs a prefix/
## geometry link CSV alone can't safely supply.
class_name ScheduleCsvIO
extends RefCounted

const HEADER := ["id", "action", "type", "start_date", "end_date", "duration_days", "units_per_day", "formwork_mode", "pour_days", "strip_days", "depends_on", "lag_days", "comment"]

## The formwork_mode column's four values, matching ScheduleInspector's
## Encofrado dropdown. English keys, like every other CSV cell -- the Spanish
## in the inspector is display-only.
const _FORMWORK_MODES := ["none", "generic", "model", "prefix"]

## Sentinel returned by _csv_cell() when a column is absent from the CSV's
## header entirely -- distinct from "" (column present, cell blank), which
## means "clear this field," the same convention ScheduleInspector's own
## LineEdit fields already use (a blank Start Date erases start_date, etc.).
## Letting a column be omitted lets a hand-trimmed CSV (e.g. just id +
## start_date + duration_days) safely leave every other field untouched on
## import.
const _COLUMN_ABSENT := "<absent>"

## Writes sequence_manager.sequence_data out as CSV. Returns the number of
## rows written, or -1 if the file couldn't be opened (already push_error'd).
func export_csv(path: String, sequence_manager: Node, current_schedule: ConstructionSchedule) -> int:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Timeline dock: could not open '%s' for writing" % path)
		return -1
	file.store_csv_line(PackedStringArray(HEADER))

	var row_count := 0
	for step in sequence_manager.sequence_data.get("steps", []):
		var step_index = step.get("index", 0)
		for action in step.get("actions", []):
			var own_id: String = ConstructionSchedule._action_id(action)
			if own_id == "":
				continue # no id, commander_prefix, or target_prefix -- not addressable by CSV
			var display_prefix: String = action.get("commander_prefix", action.get("target_prefix", "?"))
			var action_label: String = "#%d %s" % [step_index, own_id]
			if action.get("id", "") != "" and own_id != display_prefix:
				action_label += " (%s)" % display_prefix
			file.store_csv_line(PackedStringArray([
				own_id,
				action_label,
				action.get("type", "scale_up"),
				action.get("start_date", ""),
				_resolved_end_date_for_export(action, current_schedule),
				str(action["duration_days"]) if action.has("duration_days") else "",
				str(action["units_per_day"]) if action.has("units_per_day") else "",
				_formwork_mode_for_export(action, sequence_manager),
				_formwork_number_for_export(action, "pour_days"),
				_formwork_number_for_export(action, "strip_days"),
				", ".join(ConstructionSchedule._depends_on_ids(action)),
				str(action["lag_days"]) if action.has("lag_days") else "",
				action.get("comment", ""),
			]))
			row_count += 1
	file.close()
	return row_count

## The action's *resolved* formwork tier, so a row inheriting a project-wide
## formwork_defaults exports as what it actually does rather than as "none" --
## the same rule ScheduleInspector's dropdown follows, and the same reason
## end_date below exports its resolved value.
func _formwork_mode_for_export(action: Dictionary, sequence_manager: Node) -> String:
	var defaults: Dictionary = ConstructionSchedule.formwork_defaults(sequence_manager.sequence_data)
	var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, defaults)
	if cfg.is_empty():
		return "none"
	if String(cfg.get("prefix", "")) != "":
		return "prefix"
	if String(cfg.get("model", "")) != "":
		return "model"
	return "generic"

## One numeric formwork field from the action's OWN block -- deliberately not
## the resolved value, unlike the mode above. A blank cell means "inherit",
## and exporting a project default onto all 24 rows would turn one root edit
## into 24 per-action overrides on the next import.
func _formwork_number_for_export(action: Dictionary, key: String) -> String:
	var raw = action.get("formwork")
	if not (raw is Dictionary) or not raw.has(key):
		return ""
	var value = raw[key]
	return str(value) if (value is float or value is int) else ""

## End Date is derived-only for export: prefer the actually-resolved schedule
## date (current_schedule.get_action_day_range(), the same source
## ScheduleInspector's Depends On rows use for their read-only End Date) when
## a schedule is available, since that's the only way a Depends On action's
## real end date is known at all -- falling back to local start+duration
## arithmetic otherwise (e.g. no preview schedule built yet, or a plain
## explicit-date action). current_schedule may lag one edit behind
## sequence_data between an edit and the dock's next Recalculate -- the same
## accepted tradeoff already documented on TimelineDock's _current_schedule.
func _resolved_end_date_for_export(action: Dictionary, current_schedule: ConstructionSchedule) -> String:
	if current_schedule:
		var action_id: String = ConstructionSchedule._action_id(action)
		var day_range: Dictionary = current_schedule.get_action_day_range(action_id)
		if not day_range.is_empty():
			return current_schedule.day_to_date_string(day_range.finish_day)
	var start: String = action.get("start_date", "")
	if start == "":
		return ""
	return ConstructionSchedule.end_date_from_start_and_duration(start, action.get("duration_days", 1.0))

## Reads CSV rows from path and applies them onto sequence_manager's existing
## actions in place, matched by resolved id. Returns {"updated": int,
## "skipped": int} on success, or {} if the file couldn't be opened or the
## CSV has no "id" column (both cases already push_error'd).
func import_csv(path: String, sequence_manager: Node) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Timeline dock: could not open '%s' for reading" % path)
		return {}

	var header: PackedStringArray = file.get_csv_line()
	var col: Dictionary = {}
	for i in range(header.size()):
		col[header[i].strip_edges()] = i
	if not col.has("id"):
		push_error("Timeline dock: CSV missing required 'id' column, import aborted")
		file.close()
		return {}

	var actions_by_id: Dictionary = {}
	for step in sequence_manager.sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var id: String = ConstructionSchedule._action_id(action)
			if id != "":
				actions_by_id[id] = action

	var updated := 0
	var skipped := 0
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue
		var row_id: String = row[col["id"]].strip_edges() if col["id"] < row.size() else ""
		if row_id == "":
			continue
		if not actions_by_id.has(row_id):
			push_warning("Timeline dock: CSV row id '%s' has no matching action, skipped" % row_id)
			skipped += 1
			continue
		_apply_csv_row(actions_by_id[row_id], row, col)
		updated += 1
	file.close()

	return {"updated": updated, "skipped": skipped}

## Reads one CSV cell by column name, _COLUMN_ABSENT if that column wasn't in
## the header at all -- see this class's header comment for why "absent" and
## "present but blank" are handled differently.
func _csv_cell(row: PackedStringArray, col: Dictionary, key: String) -> String:
	if not col.has(key):
		return _COLUMN_ABSENT
	var idx: int = col[key]
	return row[idx].strip_edges() if idx < row.size() else ""

## Applies one CSV row's columns onto an existing action Dictionary, mirroring
## exactly the mutual-exclusion rules ScheduleInspector's own field handlers
## enforce (Start Date clears Depends On and vice versa; Duration (days) and
## Units per Day are two views of one rate, only one is ever persisted). Blank
## cells (as opposed to an absent column, see _csv_cell()) erase that field,
## the same convention every inspector LineEdit already follows.
func _apply_csv_row(action: Dictionary, row: PackedStringArray, col: Dictionary) -> void:
	var action_id: String = ConstructionSchedule._action_id(action)

	var type_val := _csv_cell(row, col, "type")
	if type_val != _COLUMN_ABSENT and type_val != "":
		if AnimationApplier.TYPES.has(type_val):
			action["type"] = type_val
		else:
			push_warning("Timeline dock: CSV row '%s' has unknown type '%s', ignored" % [action_id, type_val])

	var depends_val := _csv_cell(row, col, "depends_on")
	var applied_depends := false
	if depends_val != _COLUMN_ABSENT:
		if depends_val == "":
			action.erase("depends_on")
		else:
			var ids: Array = []
			for part in depends_val.split(","):
				var trimmed: String = part.strip_edges()
				if trimmed != "" and not ids.has(trimmed):
					ids.append(trimmed)
			if not ids.is_empty():
				action["depends_on"] = ids[0] if ids.size() == 1 else ids
				action.erase("start_date")
				applied_depends = true

	var start_val := _csv_cell(row, col, "start_date")
	if start_val != _COLUMN_ABSENT and not applied_depends:
		if start_val == "":
			action.erase("start_date")
		else:
			action["start_date"] = start_val
			action.erase("depends_on")

	var duration_val := _csv_cell(row, col, "duration_days")
	var units_val := _csv_cell(row, col, "units_per_day")
	if duration_val != _COLUMN_ABSENT and duration_val != "":
		if duration_val.is_valid_float():
			action["duration_days"] = duration_val.to_float()
			action.erase("units_per_day")
		else:
			push_warning("Timeline dock: CSV row '%s' has invalid duration_days '%s', ignored" % [action_id, duration_val])
	elif units_val != _COLUMN_ABSENT and units_val != "":
		if units_val.is_valid_float():
			action["units_per_day"] = units_val.to_float()
			action.erase("duration_days")
		else:
			push_warning("Timeline dock: CSV row '%s' has invalid units_per_day '%s', ignored" % [action_id, units_val])
	elif duration_val == "" or units_val == "":
		# At least one of the two columns is present and explicitly blank,
		# the other absent or also blank -- clear the rate entirely rather
		# than falling through to the end_date fallback below, matching the
		# "blank erases" convention for every other field in this row.
		action.erase("duration_days")
		action.erase("units_per_day")
	else:
		# Both columns absent (not just blank) -- fall back to deriving
		# duration_days from start_date + end_date, the only case where
		# end_date is actually consulted on import (see this class's header
		# comment: it's otherwise export/derived-only).
		var end_val := _csv_cell(row, col, "end_date")
		if end_val != _COLUMN_ABSENT and end_val != "" and action.get("start_date", "") != "":
			var derived: float = ConstructionSchedule.duration_from_start_and_end(action["start_date"], end_val)
			if derived > 0.0:
				action["duration_days"] = derived
				action.erase("units_per_day")

	_apply_csv_formwork(action, row, col, action_id)

	var lag_val := _csv_cell(row, col, "lag_days")
	if lag_val != _COLUMN_ABSENT:
		if lag_val == "":
			action.erase("lag_days")
		elif lag_val.is_valid_float():
			# 0 means "unset," same convention as ScheduleInspector's own lag
			# SpinBox -- a negative lag is legitimate (lead time/overlap),
			# only exactly 0.0 erases the key.
			if lag_val.to_float() == 0.0:
				action.erase("lag_days")
			else:
				action["lag_days"] = lag_val.to_float()
		else:
			push_warning("Timeline dock: CSV row '%s' has invalid lag_days '%s', ignored" % [action_id, lag_val])

	var comment_val := _csv_cell(row, col, "comment")
	if comment_val != _COLUMN_ABSENT:
		if comment_val == "":
			action.erase("comment")
		else:
			action["comment"] = comment_val

## formwork_mode / pour_days / strip_days.
##
## Geometry links (formwork.model, formwork.prefix) are never written from CSV,
## matching the inspector: "model"/"prefix" here mean "leave this row's existing
## geometry alone", and a row asking for one it doesn't have is warned about and
## left as it is rather than being given an empty link that resolves to nothing.
func _apply_csv_formwork(action: Dictionary, row: PackedStringArray, col: Dictionary, action_id: String) -> void:
	var mode_val := _csv_cell(row, col, "formwork_mode")
	if mode_val != _COLUMN_ABSENT and mode_val != "":
		if not _FORMWORK_MODES.has(mode_val):
			push_warning("Timeline dock: CSV row '%s' has unknown formwork_mode '%s', ignored" % [action_id, mode_val])
		elif mode_val == "none":
			# Matches ScheduleInspector._on_formwork_mode_edited(): the explicit
			# opt-out only exists to override a project-wide default, and with no
			# default the cleanest "no" is no key at all.
			action["formwork"] = false
		else:
			var raw = action.get("formwork")
			var block: Dictionary = raw if raw is Dictionary else {}
			block.erase("enabled")
			if mode_val == "generic":
				block.erase("prefix")
				block.erase("model")
			elif not block.has(mode_val):
				push_warning("Timeline dock: CSV row '%s' asks for formwork_mode '%s' but has no formwork.%s set (that field is JSON-only), left unchanged" % [action_id, mode_val, mode_val])
			action["formwork"] = block

	for key in ["pour_days", "strip_days"]:
		var cell := _csv_cell(row, col, key)
		if cell == _COLUMN_ABSENT:
			continue
		var raw2 = action.get("formwork")
		if not (raw2 is Dictionary):
			continue # no formwork block to write into; formwork_mode governs that
		if cell == "":
			raw2.erase(key)
		elif cell.is_valid_float():
			raw2[key] = cell.to_float()
		else:
			push_warning("Timeline dock: CSV row '%s' has invalid %s '%s', ignored" % [action_id, key, cell])
