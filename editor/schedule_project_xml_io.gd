## Microsoft Project XML Interchange format export/import for the Phase 3
## dock -- a sibling to schedule_csv_io.gd, NOT related to the legacy binary
## .mpp format (an OLE/Compound-File container whose internal task encoding
## is proprietary and undocumented; reverse-engineering it is what dedicated
## projects like MPXJ exist for -- not something to hand-roll here). The
## Project XML schema (xmlns="http://schemas.microsoft.com/project"), by
## contrast, is genuinely documented and just XML -- parseable/writable with
## Godot's built-in XMLParser, no external dependency.
##
## Export writes every action as a Manually Scheduled Task (<Manual>1</Manual>)
## with a literal Start/Finish -- MS Project displays exactly the dates given
## rather than recomputing them through its own working-time calendar, which
## matters because our schedule is continuous-calendar-day based, not
## calendar-aware like Project's own duration engine. Task Name is the
## resolved action id (ConstructionSchedule._action_id()), not a human label
## -- this is what makes re-importing our own export a zero-friction exact
## match (see TimelineDock._import_project_xml()).
##
## Import (parse_xml()) only extracts task data -- it does NOT decide which
## Project task corresponds to which of our actions. That matching step
## lives in TimelineDock: an exact Task Name == our action id auto-matches
## (the round-trip-our-own-export case); anything left over is a genuinely
## foreign file (e.g. hand-authored in Project, or a different project's
## export) with no natural key to match on, and needs a human to map it via
## ProjectXmlMappingDialog. apply_task_onto_action() is what actually writes
## a matched task's fields onto an action, once the dock has resolved that
## mapping (auto and/or manual).
##
## Phase groups: one external task can correspond to a whole internal chain
## of actions (e.g. "Pile 2" = rebar_f1 -> pour_f1 -> rebar_f2 -> ... in
## construction_steps.json, each linked by hand-authored depends_on/lag_days
## capturing real cure/wait times that don't come from -- and can't be
## derived from -- the task's own Start/Finish). A mapping is therefore
## {anchor_id, terminal_id}, not a single id: only the anchor (the chain's
## first action) has its start_date overwritten from the task's literal
## Start on import -- everything after it already cascades automatically
## through the existing depends_on chain, untouched. The terminal (the
## chain's last action) is never written to; its *computed* finish is only
## read back, to compare against the task's own Finish and report a
## mismatch (see TimelineDock._apply_project_xml_import()) -- deliberately
## reported, not silently corrected, since a real discrepancy usually means
## either the phase template or the Project estimate needs a human look, not
## an automatic rescale of real cure/wait days that don't compress.
## anchor_id == terminal_id is the ordinary case (a task with no phase
## breakdown, mapped to exactly one action).
##
## load_mapping()/save_mapping() persist this {task_name: {anchor_id,
## terminal_id}} correlation to its own file, separate from
## construction_steps.json, keyed by Task Name (not Project's UID, which
## isn't guaranteed stable across re-exports of an updated plan) -- so a
## task mapped once, including a multi-action phase group, never needs
## re-mapping through ProjectXmlMappingDialog again, even after the source
## file's dates change. A future revision may key this by a stable
## model-derived id (e.g. an IFC element-id property carried through a Project
## custom field) instead of Name -- the mapping file format and anchor/
## terminal mechanics here don't need to change for that, only what gets
## matched against what in TimelineDock.
##
## Only Finish-to-Start (Type == 1) predecessor links are honored, matching
## this codebase's existing depends_on model -- Start-to-Start/Finish-to-
## Finish/Start-to-Finish links are silently dropped (not approximated),
## since forcing a non-FS relationship into an FS field would misrepresent
## the source schedule rather than just omit part of it.
class_name ScheduleProjectXmlIO
extends RefCounted

func _xml_escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")

## Writes sequence_manager.sequence_data out as a Project XML file. Returns
## the number of tasks written, or -1 if the file couldn't be opened
## (already push_error'd). Actions with no resolvable start date (no
## start_date, no depends_on-derived date, and no current_schedule to
## resolve one from) are skipped -- an undated Task would just confuse
## whoever opens this in Project.
func export_xml(path: String, sequence_manager: Node, current_schedule: ConstructionSchedule) -> int:
	var actions: Array = [] # ordered [{id, action}]
	for step in sequence_manager.sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var id: String = ConstructionSchedule._action_id(action)
			if id != "":
				actions.append({"id": id, "action": action})

	var uid_by_id: Dictionary = {}
	for i in range(actions.size()):
		uid_by_id[actions[i].id] = i + 1

	var lines: Array = []
	lines.append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
	lines.append('<Project xmlns="http://schemas.microsoft.com/project">')
	lines.append("\t<SaveVersion>14</SaveVersion>")
	lines.append("\t<Name></Name>")
	lines.append("\t<Title>%s</Title>" % _xml_escape(sequence_manager.construction_json_path.get_file()))
	lines.append("\t<ScheduleFromStart>1</ScheduleFromStart>")
	lines.append("\t<CalendarUID>1</CalendarUID>")
	lines.append("\t<DefaultStartTime>09:00:00</DefaultStartTime>")
	lines.append("\t<DefaultFinishTime>18:00:00</DefaultFinishTime>")
	lines.append("\t<MinutesPerDay>480</MinutesPerDay>")
	lines.append("\t<MinutesPerWeek>2400</MinutesPerWeek>")
	lines.append("\t<DaysPerMonth>20</DaysPerMonth>")
	# A minimal base calendar -- Project's XML importer expects at least one
	# to exist even though every Task here is Manually Scheduled (and so
	# doesn't actually get driven by it).
	lines.append("\t<Calendars>")
	lines.append("\t\t<Calendar>")
	lines.append("\t\t\t<UID>1</UID>")
	lines.append("\t\t\t<Name>Standard</Name>")
	lines.append("\t\t\t<IsBaseCalendar>1</IsBaseCalendar>")
	lines.append("\t\t\t<WeekDays>")
	for day in range(1, 8): # MS Project convention: 1=Sunday .. 7=Saturday
		var working: bool = day != 1 and day != 7
		lines.append("\t\t\t\t<WeekDay>")
		lines.append("\t\t\t\t\t<DayType>%d</DayType>" % day)
		lines.append("\t\t\t\t\t<DayWorking>%d</DayWorking>" % (1 if working else 0))
		if working:
			lines.append("\t\t\t\t\t<WorkingTimes>")
			lines.append("\t\t\t\t\t\t<WorkingTime>")
			lines.append("\t\t\t\t\t\t\t<FromTime>09:00:00</FromTime>")
			lines.append("\t\t\t\t\t\t\t<ToTime>18:00:00</ToTime>")
			lines.append("\t\t\t\t\t\t</WorkingTime>")
			lines.append("\t\t\t\t\t</WorkingTimes>")
		lines.append("\t\t\t\t</WeekDay>")
	lines.append("\t\t\t</WeekDays>")
	lines.append("\t\t</Calendar>")
	lines.append("\t</Calendars>")

	lines.append("\t<Tasks>")
	var written := 0
	for entry in actions:
		var id: String = entry.id
		var action: Dictionary = entry.action

		var start_date: String = action.get("start_date", "")
		var duration_days: float = action.get("duration_days", 1.0)
		if current_schedule:
			var day_range: Dictionary = current_schedule.get_action_day_range(id)
			if not day_range.is_empty():
				start_date = current_schedule.day_to_date_string(day_range.start_day)
		var end_date: String = ConstructionSchedule.end_date_from_start_and_duration(start_date, duration_days) if start_date != "" else ""
		if start_date == "" or end_date == "":
			continue

		var uid: int = uid_by_id[id]
		lines.append("\t\t<Task>")
		lines.append("\t\t\t<UID>%d</UID>" % uid)
		lines.append("\t\t\t<ID>%d</ID>" % uid)
		lines.append("\t\t\t<Name>%s</Name>" % _xml_escape(id))
		lines.append("\t\t\t<Type>0</Type>")
		lines.append("\t\t\t<IsNull>0</IsNull>")
		lines.append("\t\t\t<Manual>1</Manual>")
		lines.append("\t\t\t<Start>%sT09:00:00</Start>" % start_date)
		lines.append("\t\t\t<Finish>%sT18:00:00</Finish>" % end_date)
		lines.append("\t\t\t<Duration>PT%dH0M0S</Duration>" % int(round(duration_days * 24.0)))
		lines.append("\t\t\t<DurationFormat>7</DurationFormat>")
		lines.append("\t\t\t<Milestone>%d</Milestone>" % (1 if duration_days <= 0.0 else 0))
		lines.append("\t\t\t<Summary>0</Summary>")
		lines.append("\t\t\t<Active>1</Active>")
		if action.get("comment", "") != "":
			lines.append("\t\t\t<Notes>%s</Notes>" % _xml_escape(action["comment"]))

		var dep_ids: Array = ConstructionSchedule._depends_on_ids(action)
		var lag_days: float = action.get("lag_days", 0.0)
		for dep_id in dep_ids:
			if not uid_by_id.has(dep_id):
				continue
			lines.append("\t\t\t<PredecessorLink>")
			lines.append("\t\t\t\t<PredecessorUID>%d</PredecessorUID>" % uid_by_id[dep_id])
			lines.append("\t\t\t\t<Type>1</Type>") # Finish-to-Start -- the only type this codebase's depends_on models
			lines.append("\t\t\t\t<CrossProject>0</CrossProject>")
			if lag_days != 0.0:
				# Tenths of a minute -- see _task_duration_days()'s doc
				# comment for the same convention read back on import.
				lines.append("\t\t\t\t<LinkLag>%d</LinkLag>" % int(round(lag_days * 24.0 * 60.0 * 10.0)))
				lines.append("\t\t\t\t<LinkLagFormat>7</LinkLagFormat>")
			lines.append("\t\t\t</PredecessorLink>")
		lines.append("\t\t</Task>")
		written += 1
	lines.append("\t</Tasks>")
	lines.append("</Project>")

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Timeline dock: could not open '%s' for writing" % path)
		return -1
	file.store_string("\n".join(lines))
	file.close()
	return written

## Streams a Project XML file into a flat Array of task Dictionaries:
## {uid: String, name: String, start: String, finish: String, milestone: bool,
## summary: bool, is_null: bool, predecessors: [{uid: String, type: int,
## lag: int}, ...]}. Purely mechanical extraction -- no matching/filtering
## decisions are made here (see this class's header comment for why that's
## the dock's job, not this class's). Returns [] on a file that can't be
## opened (already push_error'd) or that genuinely has no tasks.
##
## Godot's XMLParser is a streaming/pull parser, not a DOM -- this walks a
## simple element-name stack so a leaf field's text (e.g. a <Name>) is only
## captured when its immediate parent is <Task> or <PredecessorLink>,
## letting deeper nesting (e.g. <ExtendedAttribute><Value>) fall through
## unrecognized rather than needing to be special-cased. A self-closing tag
## (`<Foo/>`) reports NODE_ELEMENT with is_empty() true and -- unlike a
## `<Foo></Foo>` pair -- never gets a matching NODE_ELEMENT_END event of its
## own, so _close_element() is called inline for it too; without that, one
## self-closing tag anywhere in the file would leave the stack permanently
## one entry too deep, silently corrupting every parent-lookup after it.
func parse_xml(path: String) -> Array:
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		push_error("Timeline dock: could not open '%s' for reading" % path)
		return []

	var tasks: Array = []
	var stack: Array = []
	var current_task: Dictionary = {}
	var current_pred: Dictionary = {}
	var in_task := false
	var in_pred := false

	while parser.read() == OK:
		var node_type: int = parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var name: String = parser.get_node_name()
			stack.append(name)
			if name == "Task" and stack.size() >= 2 and stack[-2] == "Tasks":
				current_task = {"predecessors": []}
				in_task = true
			elif name == "PredecessorLink" and in_task:
				current_pred = {}
				in_pred = true
			if parser.is_empty():
				# Self-closing tag (`<Foo/>`) -- no NODE_ELEMENT_END will
				# follow for it, so close it out right here instead.
				_close_element(name, stack, current_task, current_pred, in_task, in_pred, tasks)
				if name == "PredecessorLink" and in_pred:
					current_pred = {}
					in_pred = false
				elif name == "Task" and in_task:
					current_task = {}
					in_task = false
		elif node_type == XMLParser.NODE_TEXT:
			var text: String = parser.get_node_data().strip_edges()
			if text != "" and stack.size() >= 2:
				_capture_field(current_task, current_pred, stack[-2], stack[-1], text)
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var name: String = parser.get_node_name()
			_close_element(name, stack, current_task, current_pred, in_task, in_pred, tasks)
			if name == "PredecessorLink" and in_pred:
				current_pred = {}
				in_pred = false
			elif name == "Task" and in_task:
				current_task = {}
				in_task = false

	return tasks

## Shared close-out logic for one element, used both by a genuine
## NODE_ELEMENT_END and inline for a self-closing NODE_ELEMENT (see
## parse_xml()'s doc comment). Mutates current_task/tasks/stack directly
## (Dictionaries and Arrays are passed by reference in GDScript) -- the
## caller is still responsible for resetting current_task/current_pred and
## clearing in_task/in_pred afterward, since those are local value-typed
## flags in parse_xml() this function has no way to reassign for the caller.
func _close_element(name: String, stack: Array, current_task: Dictionary, current_pred: Dictionary, in_task: bool, in_pred: bool, tasks: Array) -> void:
	if name == "PredecessorLink" and in_pred:
		current_task.predecessors.append(current_pred)
	elif name == "Task" and in_task:
		tasks.append(current_task)
	if not stack.is_empty() and stack[-1] == name:
		stack.pop_back()

func _capture_field(task: Dictionary, pred: Dictionary, parent: String, field: String, text: String) -> void:
	if parent == "PredecessorLink":
		match field:
			"PredecessorUID": pred["uid"] = text
			"Type": pred["type"] = text.to_int()
			"LinkLag": pred["lag"] = text.to_int()
	elif parent == "ExtendedAttribute" and task.has("predecessors"):
		# A task's custom field (Text1, Text2...): <FieldID> comes before its
		# <Value>. The project-level definitions (FieldID/FieldName/Alias) sit
		# outside any Task, where `task` is still the empty placeholder.
		match field:
			"FieldID": task["_field_id"] = text
			"Value":
				if not task.has("extended"):
					task["extended"] = {}
				task["extended"][task.get("_field_id", "")] = text
	elif parent == "Task":
		match field:
			"UID": task["uid"] = text
			"Name": task["name"] = text
			"Start": task["start"] = text
			"Finish": task["finish"] = text
			"Milestone": task["milestone"] = (text == "1")
			"Summary": task["summary"] = (text == "1")
			"IsNull": task["is_null"] = (text == "1")

## The custom field (by FieldID) holding each task's animation type: the one
## whose every non-empty value is an AnimationApplier type name. Found by its
## values, not its name, so it works whatever the column is called or in
## whatever language ("Tipo de animación", "Animation"...). "" when no field
## qualifies.
static func animation_type_field(tasks: Array) -> String:
	var candidates: Dictionary = {} # field_id -> still qualifies
	for task in tasks:
		for field_id in task.get("extended", {}):
			var value := str(task["extended"][field_id]).strip_edges().to_lower()
			if value == "":
				continue
			candidates[field_id] = candidates.get(field_id, true) and value in AnimationApplier.TYPES
	for field_id in candidates:
		if candidates[field_id]:
			return field_id
	return ""

func _task_start_date(task: Dictionary) -> String:
	var start: String = task.get("start", "")
	return start.split("T")[0] if start != "" else ""

## Public counterpart to _task_start_date() -- used by the dock outside this
## class (mismatch reporting for a phase-group's terminal action, see
## TimelineDock._apply_project_xml_import()), so it doesn't need to duplicate
## the "T"-split.
func task_finish_date(task: Dictionary) -> String:
	var finish: String = task.get("finish", "")
	return finish.split("T")[0] if finish != "" else ""

## Finish - Start, in whole/fractional days, rounded to the same 0.0001
## precision ScheduleInspector's own Units/Day <-> Duration conversion uses.
## 0.0 (not negative/NAN) if either date is missing or unparseable -- treated
## by apply_task_onto_action() as "don't touch duration_days".
func _task_duration_days(task: Dictionary) -> float:
	var start: String = task.get("start", "")
	var finish: String = task.get("finish", "")
	if start == "" or finish == "":
		return 0.0
	var start_epoch: float = Time.get_unix_time_from_datetime_string(start.replace("T", " "))
	var finish_epoch: float = Time.get_unix_time_from_datetime_string(finish.replace("T", " "))
	if start_epoch < 0 or finish_epoch < 0:
		return 0.0
	return snappedf((finish_epoch - start_epoch) / 86400.0, 0.0001)

## Applies one parsed task's fields onto an existing action Dictionary, once
## the dock has already decided (via exact-name auto-match or
## ProjectXmlMappingDialog) which action this task corresponds to.
## uid_to_action_id resolves this task's predecessor UIDs to our own action
## ids -- built by the dock from the same matched/mapped set, so a
## predecessor only counts if it was ALSO matched/mapped to one of our
## actions. Only Finish-to-Start (Type == 1) links are honored (see this
## class's header comment); everything else is silently dropped.
##
## When at least one predecessor resolves, depends_on drives this action's
## start (start_date is erased) -- mirroring ScheduleInspector's own Start
## Date/Depends On mutual exclusion (an explicit start_date always wins over
## depends_on in ConstructionSchedule, so leaving both would make depends_on
## inert and silently ignore the imported dependency graph). Otherwise the
## task's own literal Start date is used. duration_days is always set from
## Finish - Start when both parse, regardless of which start-source won.
##
## type_field (from animation_type_field()) also sets the action's type, and
## its batch the way the IFC generator derives it -- the plan is where the
## method of each activity is decided (a pour is fill_up), so it wins.
func apply_task_onto_action(action: Dictionary, task: Dictionary, uid_to_action_id: Dictionary, type_field: String = "") -> void:
	var anim_type := str(task.get("extended", {}).get(type_field, "")).strip_edges().to_lower()
	if type_field != "" and anim_type in AnimationApplier.TYPES:
		action["type"] = anim_type
		action["batch"] = IFCScheduleGenerator.batch_for(anim_type)
	var start_date: String = _task_start_date(task)
	var duration_days: float = _task_duration_days(task)
	if duration_days > 0.0:
		action["duration_days"] = duration_days
		action.erase("units_per_day")

	var own_id: String = ConstructionSchedule._action_id(action)
	var dep_ids: Array = []
	# Seeded from the first link that resolves, NOT from 0: a lead (negative lag, e.g.
	# formwork stripping starting partway through a pour, or quoins laid while the wall
	# they trim is still rising) is a perfectly ordinary Finish-to-Start link, and
	# maxi(0, -259200) silently turned every one of them into no lag at all.
	var max_lag_tenths_min: int = 0
	var have_lag: bool = false
	for pred in task.get("predecessors", []):
		if pred.get("type", -1) != 1:
			continue # not Finish-to-Start -- unsupported relationship type here
		var pred_uid = pred.get("uid", "")
		if not uid_to_action_id.has(pred_uid):
			continue # predecessor wasn't itself matched/mapped to one of our actions
		var dep_id: String = uid_to_action_id[pred_uid]
		if dep_id == own_id or dep_ids.has(dep_id):
			continue
		dep_ids.append(dep_id)
		var pred_lag: int = pred.get("lag", 0)
		max_lag_tenths_min = pred_lag if not have_lag else maxi(max_lag_tenths_min, pred_lag)
		have_lag = true

	if not dep_ids.is_empty():
		action["depends_on"] = dep_ids[0] if dep_ids.size() == 1 else dep_ids
		action.erase("start_date")
		# Tenths of a minute -> days: 24 h * 60 min * 10, the same factor export_xml()
		# writes with. This read 600 (tenths of a minute -> *hours*), so every lag came
		# back 24x too long -- a 2-day lag re-imported as 48 days, silently, and the
		# addon's own export could not survive its own import.
		var lag_days: float = max_lag_tenths_min / 14400.0
		if lag_days != 0.0:
			action["lag_days"] = lag_days
		else:
			action.erase("lag_days")
	elif start_date != "":
		action["start_date"] = start_date
		action.erase("depends_on")

## Reads the persisted task-name -> {anchor_id, terminal_id} mapping file
## (see this class's header comment). Returns {} if the file doesn't exist
## yet (the ordinary case on a project's first-ever import -- not an error)
## or is malformed (warned about, since a mapping file that fails to parse
## silently would otherwise re-trigger ProjectXmlMappingDialog for every
## task with no explanation of why the "remembered" mapping vanished).
func load_mapping(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("Timeline dock: could not open mapping file '%s' for reading" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("Timeline dock: mapping file '%s' is not valid JSON, ignoring it" % path)
		return {}
	file.close()
	var data = json.get_data()
	return data.get("mappings", {}) if data is Dictionary else {}

## Writes the task-name -> {anchor_id, terminal_id} mapping back out,
## wrapped in a small envelope ({"mappings": {...}}) so the file has room to
## grow a schema version or other metadata later without breaking existing
## files. Called after every Project XML import with the full accumulated
## mapping (persisted-carryover entries plus whatever was newly auto-matched
## or mapped via ProjectXmlMappingDialog this time), so the file is a
## complete, self-healing record of every task ever successfully resolved --
## not just an incremental diff.
func save_mapping(path: String, mapping: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Timeline dock: could not open '%s' for writing" % path)
		return
	file.store_string(JSON.stringify({"mappings": mapping}, "\t"))
	file.close()
