## Manual task-to-action(s) mapping popup, shown by TimelineDock when
## importing a Project XML file that has tasks with no exact-name match
## against any current action id, and no entry in the persisted mapping
## file (see ScheduleProjectXmlIO's header comment) -- i.e. a genuinely
## foreign file, or the first time a given task has ever been seen. One row
## per unmatched task: its name (plus UID/dates as tooltip context), an
## Anchor OptionButton (the action whose start_date this task's literal
## Start overwrites), and a Terminal OptionButton (the action whose
## *computed* finish gets compared against this task's Finish for mismatch
## reporting -- left at "(same as anchor)" for the ordinary case of a task
## with no internal phase breakdown).
##
## A ConfirmationDialog (not a bare Window) so Cancel is free -- the dock
## connects both `confirmed`/`canceled`; canceling drops the whole import,
## not just the unmapped rows, since applying only the auto-matched subset
## silently without telling the user would be a surprising partial import.
## Whatever gets confirmed here is also what TimelineDock persists to the
## mapping file, so a given task is never mapped through this dialog twice.
@tool
class_name ProjectXmlMappingDialog
extends ConfirmationDialog

## Emitted on confirm with {task_index (int, index into the `tasks` array
## passed to setup()): {anchor_id: String, terminal_id: String}} -- only for
## rows where Anchor wasn't left at "(skip)". TimelineDock merges this into
## its already-resolved set (persisted-mapping carryover + auto-matches) and
## applies/persists all of it together.
signal mapping_confirmed(mapping: Dictionary)

var _rows: Array = [] # [{task_index: int, anchor: OptionButton, terminal: OptionButton}]

func _init() -> void:
	title = "Map Project Tasks"
	min_size = Vector2i(620, 320)
	confirmed.connect(_on_confirmed)

## unmatched_tasks: Array of {task_index: int, task: Dictionary} -- task_index
## is the row's position in the full parsed-tasks array (not this filtered
## subset), so the dock can merge the resulting mapping back against the
## right task. existing_ids: every current action id, offered as mapping
## targets for each row.
func setup(unmatched_tasks: Array, existing_ids: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var intro := Label.new()
	intro.text = "%d task(s) in this file don't match any current action id (or a saved mapping). Pick an Anchor action for each -- the action whose Start Date this task drives. If a task actually corresponds to a multi-phase chain in construction_steps.json (e.g. \"Pile 2\" = rebar_f1 -> pour_f1 -> ...), also pick a Terminal action -- the chain's last step -- so its computed finish can be checked against this task's Finish. Leave Terminal as \"(same as anchor)\" for an ordinary single-action task. Leave Anchor as \"(skip)\" to ignore a task entirely." % unmatched_tasks.size()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(intro)
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	for header_text in ["Project Task", "Anchor (drives Start)", "Terminal (checks Finish)"]:
		var header := Label.new()
		header.text = header_text
		header.add_theme_font_size_override("font_size", 11)
		grid.add_child(header)

	for entry in unmatched_tasks:
		var task: Dictionary = entry.task
		var name_label := Label.new()
		name_label.text = task.get("name", "(unnamed task)")
		name_label.tooltip_text = "Project UID: %s\nStart: %s\nFinish: %s" % [
			task.get("uid", "?"), task.get("start", "?"), task.get("finish", "?")
		]
		name_label.custom_minimum_size = Vector2(200, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD

		var anchor := OptionButton.new()
		anchor.custom_minimum_size = Vector2(180, 0)
		anchor.add_item("(skip)")
		for id in existing_ids:
			anchor.add_item(id)

		var terminal := OptionButton.new()
		terminal.custom_minimum_size = Vector2(180, 0)
		terminal.add_item("(same as anchor)")
		for id in existing_ids:
			terminal.add_item(id)

		grid.add_child(name_label)
		grid.add_child(anchor)
		grid.add_child(terminal)
		_rows.append({"task_index": entry.task_index, "anchor": anchor, "terminal": terminal})

	add_child(scroll)
	# ConfirmationDialog lays out its own OK/Cancel row; the content passed
	# to add_child() above becomes the dialog body automatically.

func _on_confirmed() -> void:
	var mapping: Dictionary = {}
	for row in _rows:
		var anchor: OptionButton = row.anchor
		var anchor_idx: int = anchor.get_selected()
		if anchor_idx <= 0: # 0 is always "(skip)"
			continue
		var anchor_id: String = anchor.get_item_text(anchor_idx)

		var terminal: OptionButton = row.terminal
		var terminal_idx: int = terminal.get_selected()
		# 0 is always "(same as anchor)" -- resolved lazily here rather than
		# mirrored live as Anchor changes, since a static default needs no
		# signal wiring at all.
		var terminal_id: String = anchor_id if terminal_idx <= 0 else terminal.get_item_text(terminal_idx)

		mapping[row.task_index] = {"anchor_id": anchor_id, "terminal_id": terminal_id}
	mapping_confirmed.emit(mapping)
