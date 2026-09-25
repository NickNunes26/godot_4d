## Phase 3 editor dock's schedule inspector: the one-row-per-action grid
## (ID/Type/Cadencia/Escalonado/Anchor/Start Date/End Date/Duration/Units per
## Day/Encofrado/Días vertido/Depends On/Lag/Remove) that lets an author edit construction_steps.json's
## without hand-editing JSON. Split out of timeline_dock.gd (which had grown
## to mix preview lifecycle, this grid, and CSV import/export in one
## 1100+ line file) -- this was the single biggest concern in that file, and
## matches the "editor/schedule_inspector.gd" file the original
## docs/03_PLUGIN_DISTRIBUTION.md planning doc anticipated.
##
## Owned by TimelineDock, which passes in the GridContainer to render into
## and a SpatialGrouper shared with its own schedule rebuilds (so unit-count
## lookups hit the same per-prefix group cache instead of recomputing it).
## This class never rebuilds a ConstructionSchedule itself or touches
## _schedule_dirty directly -- every field edit calls the dock-supplied
## _on_dirty Callable instead, keeping the "mark dirty, Recalculate rebuilds
## on demand" policy owned by the dock (see timeline_dock.gd's
## _schedule_dirty doc comment for why).
class_name ScheduleInspector
extends RefCounted

## Cosmetic-only display labels for the Type dropdown -- construction-domain
## Spanish terms for the crew authoring schedules day to day, since names like
## "scale_up"/"drop_in" mean little without English. Purely presentational:
## the underlying AnimationApplier.TYPES keys (what's actually read/written
## to the "type" field in construction_steps.json, and what animation_applier.gd's
## match statements key off of) stay in English/unchanged -- see
## _on_type_edited(), which always writes the OptionButton item's metadata
## (the real key), never its display text. A type with no entry here falls
## back to showing its raw English key (see _add_action_row()), so adding a
## new AnimationApplier.TYPES entry never breaks the dropdown, it's just
## unlabeled until a translation is added here.
const _TYPE_DISPLAY_NAMES := {
	"scale_up": "Aparecer",
	"drop_in": "Caer",
	"rise_up": "Subir",
	"sink_down": "Bajar",
	"fill_up": "Hormigonar",
	"fade_in": "Emerger",
	"fade_out": "Desvanecer",
	"install": "Instalar",
}

## The Cadencia dropdown's two states, in item order -- the JSON "batch" field
## is a plain bool, so unlike Type/Anchor there is no English key to translate
## and the item metadata IS the value written. Same cosmetic-Spanish treatment
## regardless: "Simultáneo" is a single pour whose several meshes rise
## together, "Escalonado" is discrete units arriving one after another.
const _BATCH_DISPLAY_NAMES := [
	{"batch": true, "es": "Simultáneo", "en": "batch: true -- all parts move together (one pour)"},
	{"batch": false, "es": "Escalonado", "en": "batch: false -- parts move one after another"},
]

## Same cosmetic-only treatment as _TYPE_DISPLAY_NAMES above, for the Anchor
## dropdown's 3 items. Metadata (see _add_action_row()) stays "start"/
## "duration"/"end" -- everything _apply_time_edit()/_update_row_editable_states()
## key off of -- only the displayed text is Spanish.
const _ANCHOR_DISPLAY_NAMES := {
	"start": "Inicio",
	"duration": "Duración",
	"end": "Fin",
}

## The Encofrado dropdown's four items, in item order (07_FORMWORK.md build
## order step 5). Same cosmetic-Spanish treatment as _TYPE_DISPLAY_NAMES: the
## metadata is the mode key this file's own handlers switch on, never the
## displayed text.
##
## The last two are the explicit-geometry tiers, and they are **shown but
## disabled unless the action already carries that field** (decision 8).
## formwork.model / formwork.prefix are geometry links, and geometry links stay
## JSON-only here exactly as commander_prefix/child_prefixes do -- but dropping
## the items entirely would make a JSON-authored tier-2 row report as
## "Genérico", which is the one thing this column must never do.
const _FORMWORK_DISPLAY_NAMES := [
	{"mode": "none", "es": "No", "en": "No formwork -- the whole window is one pour, as before this feature existed"},
	{"mode": "generic", "es": "Genérico", "en": "formwork (tier 3) -- generated wood-slab boards around each part"},
	{"mode": "model", "es": "Modelo", "en": "formwork.model (tier 2) -- a panel asset placed at every computed position. Set the res:// path in construction_steps.json"},
	{"mode": "prefix", "es": "Prefijo", "en": "formwork.prefix (tier 1) -- parts already in the scene are the forms. Set the prefix in construction_steps.json"},
]

## Column header labels: Spanish display text with the English field name as
## a tooltip (same pattern as Type/Anchor's dropdown items) -- for anyone
## cross-referencing against construction_steps.json's actual field names or
## this file's code.
const _HEADER_LABELS := [
	{"es": "ID", "en": "ID"},
	{"es": "Acción", "en": "Action"},
	{"es": "Tipo", "en": "Type"},
	{"es": "Cadencia", "en": "Batch"},
	{"es": "Escalonado (s)", "en": "Stagger (s)"},
	{"es": "Ancla", "en": "Anchor"},
	{"es": "Fecha Inicio", "en": "Start Date"},
	{"es": "Fecha Fin", "en": "End Date"},
	{"es": "Duración (días)", "en": "Duration (days)"},
	{"es": "Unidades/Día", "en": "Units/Day"},
	{"es": "Encofrado", "en": "Formwork"},
	{"es": "Días vertido", "en": "formwork.pour_days"},
	{"es": "Depende De", "en": "Depends On"},
	{"es": "Retraso (días)", "en": "Lag (days)"},
	{"es": "", "en": "Remove"},
]

var _grid: GridContainer
var _grouper: SpatialGrouper
var _on_dirty: Callable

var _sequence_manager: Node = null

# Kept so a self-triggered rebuild (an id edit, see _on_id_edited()) and
# refresh_dependency_dates() (called externally by the dock after every
# _rebuild_schedule()) always resolve Depends On rows against whatever
# schedule is currently live.
var _current_schedule: ConstructionSchedule = null

# One {action, date_edit, end_date_edit} entry per inspector row, populated
# by _add_action_row(). refresh_dependency_dates() walks this after every
# schedule rebuild to keep a Depends On row's Start/End dates showing the
# actually-resolved calendar dates (they can change when *any* upstream
# action's duration changes, not just this row's own fields) -- rows without
# depends_on are skipped, since their dates are already kept current by
# their own field handlers via local start+duration arithmetic.
var _resolved_date_fields: Array = []

# One {action, unit_count, button, spin} entry per row, for the Encofrado /
# Días vertido pair. Walked by refresh_formwork_states() after any edit that
# can change a row's resolved tier or its "no room" state -- which includes
# edits made on a *different* row (the project-wide toggle) and edits to a
# field that isn't formwork at all (Duration, Units/Day: shortening an action
# below its pour length is exactly how a row loses its formwork phase).
var _formwork_fields: Array = []

## grid: the GridContainer to render rows into (15 columns -- see
## timeline_dock.tscn's InspectorList). grouper: shared with the dock's own
## schedule rebuilds so Units/Day <-> Duration conversions hit the same
## per-prefix group cache. on_dirty: called with no arguments whenever a
## field edit changes sequence_data -- the dock's hook into
## _set_schedule_dirty(true).
func _init(grid: GridContainer, grouper: SpatialGrouper, on_dirty: Callable) -> void:
	_grid = grid
	_grouper = grouper
	_on_dirty = on_dirty

## Rebuilds the inspector's one-row-per-action grid from
## sequence_manager.sequence_data. Each row edits its action Dictionary
## in place (GDScript Dictionaries are references, so this mutates the same
## object ConstructionSchedule reads from -- no separate write-back step is
## needed before the dock's next _rebuild_schedule()).
##
## _grid is a GridContainer (15 columns) rather than a VBox of
## HBoxContainers so every column -- ID/Action/Type/Batch/Stagger/Anchor/Start
## Date/End Date/Duration/Units per Day/Encofrado/Días vertido/Depends On/Lag (days)/Remove -- sizes itself to its
## widest cell across ALL rows at once. A per-row HBoxContainer can't do
## that: each row picks its own widths independently, which is what clipped
## the date field before (a fixed per-row width that didn't account for what
## other rows needed).
func build(sequence_manager: Node, current_schedule: ConstructionSchedule) -> void:
	_sequence_manager = sequence_manager
	_current_schedule = current_schedule
	clear()
	_resolved_date_fields.clear()
	_formwork_fields.clear()
	if not _sequence_manager:
		return
	_add_header_row()
	var all_ids: Array = _collect_action_ids()
	for step in _sequence_manager.sequence_data.get("steps", []):
		for action in step.get("actions", []):
			_add_action_row(step.get("index", 0), action, all_ids)
	refresh_dependency_dates(_current_schedule)

## Detached immediately, then freed at the end of the frame. queue_free() alone
## leaves the old rows parented for the rest of the frame, so a rebuild would
## briefly lay out both the old grid and the new one beneath it -- harmless but
## visible as a flicker, and now routine rather than rare: the Remove button
## rebuilds on every press.
func clear() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

func _add_header_row() -> void:
	for header in _HEADER_LABELS:
		var label := Label.new()
		label.text = header.es
		label.tooltip_text = header.en
		label.add_theme_font_size_override("font_size", 11)
		_grid.add_child(label)

## Every action's identity (ConstructionSchedule._action_id() -- an explicit
## id if present, else commander_prefix/target_prefix) -- so the Depends On
## field can list what's available to reference.
func _collect_action_ids() -> Array:
	var ids: Array = []
	for step in _sequence_manager.sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var id: String = ConstructionSchedule._action_id(action)
			if id != "" and not ids.has(id):
				ids.append(id)
	return ids

## Duration (days) and Units/Day are two views of the same underlying rate --
## unlike the raw JSON schema (where an explicit duration_days always wins
## over units_per_day, see ConstructionSchedule._resolve_duration_days()),
## the inspector keeps them mutually in sync and always normalizes back to
## duration_days: editing either field recomputes and writes the other's
## displayed value, but only duration_days is ever persisted onto the action
## Dictionary. This avoids the two fields silently disagreeing (e.g. a stale
## units_per_day sitting in the JSON having no actual effect because
## duration_days is present) and matches how an author actually wants to
## work: think in whichever unit is convenient, get one authoritative value
## out the other end. See _on_duration_edited()/_on_units_per_day_edited().
## Start Date and Depends On are mutually exclusive at the schedule level
## (ConstructionSchedule._resolve_action_start_day(): an explicit start_date
## always wins over depends_on) -- the inspector enforces that visibly, the
## same way it does for Duration/Units per Day above: setting one erases the
## other from the action Dictionary and resets that field's control, so a row
## never shows a date and a dependency that silently don't agree about which
## one is actually driving the schedule.
func _add_action_row(step_index: int, action: Dictionary, all_ids: Array) -> void:
	var own_id: String = ConstructionSchedule._action_id(action)
	var unit_count: int = _unit_count_for_action(action)

	var id_edit := LineEdit.new()
	id_edit.text = action.get("id", "")
	id_edit.placeholder_text = "(uses prefix)"
	id_edit.custom_minimum_size = Vector2(90, 0)
	id_edit.tooltip_text = "Optional explicit id, so other actions can depends_on this one by name instead of by commander_prefix/target_prefix. Blank falls back to the prefix."

	var display_prefix: String = action.get("commander_prefix", action.get("target_prefix", "?"))
	var name_label := Label.new()
	name_label.text = "#%d %s" % [step_index, own_id if own_id != "" else "?"]
	if own_id != "" and own_id != display_prefix:
		name_label.text += " (%s)" % display_prefix
	name_label.tooltip_text = action.get("comment", "")
	name_label.custom_minimum_size = Vector2(100, 0)

	# An action whose prefix matches nothing is otherwise completely silent:
	# target_prefix matching simply finds no parts, the action contributes
	# nothing to the timeline, and the row sits in the inspector looking
	# exactly like one that works. That happens whenever geometry is deleted
	# from the scene, renamed by a model revision, or -- now -- excluded via
	# excluded_prefixes. Flagged here rather than warned at load time so it is
	# visible next to the row you would actually fix or remove.
	if unit_count == 0:
		name_label.text = "⚠ " + name_label.text
		name_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		name_label.tooltip_text = "No part in the scene starts with \"%s\", so this action animates nothing.\n\nEither the geometry is gone/renamed, or the prefix is covered by excluded_prefixes. Fix the prefix or remove the row.%s" % [
			display_prefix,
			"\n\n" + name_label.tooltip_text if name_label.tooltip_text != "" else ""]

	var type_button := OptionButton.new()
	type_button.custom_minimum_size = Vector2(100, 0)
	type_button.tooltip_text = "Which built-in animation this action plays. Labels are cosmetic (Spanish) -- the underlying JSON \"type\" value stays in English; hover a menu item to see it."
	var current_type: String = action.get("type", "scale_up")
	for i in range(AnimationApplier.TYPES.size()):
		var t: String = AnimationApplier.TYPES[i]
		type_button.add_item(_TYPE_DISPLAY_NAMES.get(t, t))
		type_button.set_item_metadata(i, t)
		type_button.get_popup().set_item_tooltip(i, t)
		if t == current_type:
			type_button.select(i)

	# Cadencia: does this action's geometry move together or one piece at a
	# time. Only meaningful for a multi-part action -- a single-part action is
	# shown disabled rather than hidden, so the column stays aligned and the
	# reason is in the tooltip (see _update_cadence_editable_states()).
	var batch_button := OptionButton.new()
	batch_button.custom_minimum_size = Vector2(105, 0)
	# bool() rather than a bare typed assignment: Cadence reads this field
	# leniently (`if not action.get("batch", false)`), so a hand-edited
	# "batch": 1 works there and must not hard-error the whole inspector here.
	var current_batch := bool(action.get("batch", false))
	for i in range(_BATCH_DISPLAY_NAMES.size()):
		var entry: Dictionary = _BATCH_DISPLAY_NAMES[i]
		batch_button.add_item(entry.es)
		batch_button.set_item_metadata(i, entry.batch)
		batch_button.get_popup().set_item_tooltip(i, entry.en)
		if entry.batch == current_batch:
			batch_button.select(i)

	var stagger_spin := SpinBox.new()
	stagger_spin.min_value = 0
	stagger_spin.max_value = 999
	stagger_spin.step = 0.05
	stagger_spin.value = action.get("stagger", 0.0)
	stagger_spin.custom_minimum_size = Vector2(95, 0)

	var date_edit := LineEdit.new()
	date_edit.text = action.get("start_date", "")
	date_edit.placeholder_text = "YYYY-MM-DD"
	date_edit.custom_minimum_size = Vector2(110, 0)
	date_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var duration_spin := SpinBox.new()
	duration_spin.min_value = 0
	duration_spin.max_value = 9999
	duration_spin.step = 0.01
	duration_spin.custom_minimum_size = Vector2(100, 0)
	duration_spin.tooltip_text = "How many calendar days this action spans (0 = unset, defaults to 1 day). Editing Units/Day recomputes this precisely (no rounding), so the two fields always round-trip."

	var units_spin := SpinBox.new()
	units_spin.min_value = 0
	units_spin.max_value = 9999
	units_spin.step = 0.1
	units_spin.custom_minimum_size = Vector2(100, 0)
	units_spin.tooltip_text = "Installable units per day (e.g. 2 columns/day), derived from Duration (days) for this action's %d unit(s). Edit this to recompute Duration (days) instead." % unit_count

	duration_spin.value = action.get("duration_days", 0.0)
	units_spin.value = _initial_units_per_day(action, unit_count)

	# Anchor: which of Start/Duration/End never moves -- editing either of the
	# other two recomputes the third. Default "Duration" reproduces exactly
	# today's behavior (Start + Duration/Units editable, End is a derived
	# display), so nobody has to touch this to keep working as before.
	var anchor_button := OptionButton.new()
	anchor_button.custom_minimum_size = Vector2(85, 0)
	anchor_button.tooltip_text = "Which of Start Date / Duration / End Date is protected when you edit one of the other two (that one recomputes to keep them consistent). All three stay editable regardless -- this doesn't lock anything. Disabled (and irrelevant) when Depends On is set -- Start Date there comes from the dependency, not from this row."
	var anchor_keys := ["start", "duration", "end"]
	for i in range(anchor_keys.size()):
		var key: String = anchor_keys[i]
		anchor_button.add_item(_ANCHOR_DISPLAY_NAMES.get(key, key))
		anchor_button.set_item_metadata(i, key)
		anchor_button.get_popup().set_item_tooltip(i, key.capitalize())
	anchor_button.select(1)

	var end_date_edit := LineEdit.new()
	end_date_edit.placeholder_text = "YYYY-MM-DD"
	end_date_edit.custom_minimum_size = Vector2(110, 0)
	end_date_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_date_edit.tooltip_text = "Start Date + Duration (days). Editing this recomputes Start Date or Duration per Anchor. Read-only when Depends On is set (shows the actually-resolved schedule date) or Start Date is blank."
	if not action.get("start_date", "").is_empty():
		end_date_edit.text = ConstructionSchedule.end_date_from_start_and_duration(date_edit.text, duration_spin.value)

	# Encofrado / Días vertido: does this action's window split into a formwork
	# phase and the pour that follows it (07_FORMWORK.md). The dropdown shows the
	# *resolved* tier, not the action's own block -- with a root
	# formwork_defaults present an action carrying no "formwork" key still has
	# formwork, and a row reading "No" there would be a lie. Same reason a
	# Depends On row shows its resolved dates instead of doing local arithmetic.
	var formwork_button := OptionButton.new()
	formwork_button.custom_minimum_size = Vector2(95, 0)
	formwork_button.tooltip_text = "Whether this action builds forms before it pours. Labels are cosmetic (Spanish); hover a menu item for the JSON field it maps to.\n\nModelo/Prefijo need a res:// path or a scene prefix, which stay JSON-only -- they are selectable only once construction_steps.json sets one."
	var current_mode: String = _resolve_formwork_mode(action)
	for i in range(_FORMWORK_DISPLAY_NAMES.size()):
		var entry: Dictionary = _FORMWORK_DISPLAY_NAMES[i]
		formwork_button.add_item(entry.es)
		formwork_button.set_item_metadata(i, entry.mode)
		formwork_button.get_popup().set_item_tooltip(i, entry.en)
		if entry.mode == current_mode:
			formwork_button.select(i)

	var pour_spin := SpinBox.new()
	pour_spin.min_value = 0
	pour_spin.max_value = 9999
	pour_spin.step = 0.25
	pour_spin.custom_minimum_size = Vector2(95, 0)
	pour_spin.value = _resolved_pour_days(action)

	var depends_edit := LineEdit.new()
	depends_edit.text = ", ".join(ConstructionSchedule._depends_on_ids(action))
	depends_edit.placeholder_text = "id, id, ..."
	depends_edit.custom_minimum_size = Vector2(130, 0)
	depends_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depends_edit.tooltip_text = "Comma-separated ids this action can't start until ALL of them finish (see the ID/Action columns for what's available). Setting this clears Start Date."

	var lag_spin := SpinBox.new()
	lag_spin.min_value = -9999
	lag_spin.max_value = 9999
	lag_spin.step = 0.5
	lag_spin.value = action.get("lag_days", 0.0)
	lag_spin.custom_minimum_size = Vector2(90, 0)
	lag_spin.tooltip_text = "Days after the (latest) dependency finishes before this action starts. Negative = starts before that (lead/overlap). Only used when Depends On is set."

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.tooltip_text = "Remove this action from the schedule.\n\nIn memory only -- the JSON file is untouched until Save to JSON, and Reload from JSON undoes it. To stop geometry appearing at all rather than just unscheduling it, use excluded_prefixes; to have it present from day 0 without being work, use static_prefixes."
	remove_button.custom_minimum_size = Vector2(28, 0)

	_update_row_editable_states(action, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	_update_cadence_editable_states(action, unit_count, batch_button, stagger_spin)
	# Registered before the first refresh so this row is included in it, and so
	# a later duration edit on ANY row can re-evaluate every row's "no room"
	# marker without each handler having to thread these two controls through.
	_formwork_fields.append({"action": action, "unit_count": unit_count,
		"button": formwork_button, "spin": pour_spin})
	_update_formwork_states(_formwork_fields[-1])

	id_edit.text_submitted.connect(func(_t): _on_id_edited(action, id_edit))
	id_edit.focus_exited.connect(func(): _on_id_edited(action, id_edit))
	type_button.item_selected.connect(func(idx): _on_type_edited(action, type_button.get_item_metadata(idx)))
	batch_button.item_selected.connect(func(idx): _on_batch_edited(action, unit_count, batch_button.get_item_metadata(idx), batch_button, stagger_spin))
	stagger_spin.value_changed.connect(func(v): _on_stagger_edited(action, v))
	anchor_button.item_selected.connect(func(_idx): _on_anchor_changed(action, anchor_button, date_edit, end_date_edit, duration_spin, units_spin))
	date_edit.text_submitted.connect(func(_t): _on_date_edited(action, unit_count, date_edit, depends_edit, anchor_button, end_date_edit, duration_spin, units_spin))
	date_edit.focus_exited.connect(func(): _on_date_edited(action, unit_count, date_edit, depends_edit, anchor_button, end_date_edit, duration_spin, units_spin))
	end_date_edit.text_submitted.connect(func(_t): _on_end_date_edited(action, unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin))
	end_date_edit.focus_exited.connect(func(): _on_end_date_edited(action, unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin))
	duration_spin.value_changed.connect(func(v): _on_duration_edited(action, v, unit_count, units_spin, anchor_button, date_edit, end_date_edit, duration_spin))
	units_spin.value_changed.connect(func(v): _on_units_per_day_edited(action, v, unit_count, duration_spin, anchor_button, date_edit, end_date_edit, units_spin))
	depends_edit.text_submitted.connect(func(_t): _on_depends_on_edited(action, depends_edit, date_edit, anchor_button, end_date_edit, duration_spin, units_spin))
	depends_edit.focus_exited.connect(func(): _on_depends_on_edited(action, depends_edit, date_edit, anchor_button, end_date_edit, duration_spin, units_spin))
	formwork_button.item_selected.connect(func(idx): _on_formwork_mode_edited(action, formwork_button.get_item_metadata(idx), pour_spin))
	pour_spin.value_changed.connect(func(v): _on_pour_days_edited(action, v))
	lag_spin.value_changed.connect(func(v): _on_lag_edited(action, v))
	remove_button.pressed.connect(func(): _on_remove_pressed(action))

	_resolved_date_fields.append({"action": action, "date_edit": date_edit, "end_date_edit": end_date_edit})

	_grid.add_child(id_edit)
	_grid.add_child(name_label)
	_grid.add_child(type_button)
	_grid.add_child(batch_button)
	_grid.add_child(stagger_spin)
	_grid.add_child(anchor_button)
	_grid.add_child(date_edit)
	_grid.add_child(end_date_edit)
	_grid.add_child(duration_spin)
	_grid.add_child(units_spin)
	_grid.add_child(formwork_button)
	_grid.add_child(pour_spin)
	_grid.add_child(depends_edit)
	_grid.add_child(lag_spin)
	_grid.add_child(remove_button)

## unit_count mirrors ConstructionSchedule._init()'s own resolution: number
## of commanders for a commander_prefix action (spatial grouping doesn't
## change how many there are, only which children ride with which), or the
## count of matching parts for a target_prefix action.
func _unit_count_for_action(action: Dictionary) -> int:
	if not _sequence_manager:
		return 0
	var building_parts: Dictionary = _sequence_manager.building_parts
	if action.has("commander_prefix"):
		var groups = _grouper.get_groups(action["commander_prefix"], action.get("child_prefixes", []), building_parts)
		return groups.size()
	var prefix: String = action.get("target_prefix", "")
	var count := 0
	for part_name in building_parts.keys():
		if part_name.begins_with(prefix):
			count += 1
	return count

func _initial_units_per_day(action: Dictionary, unit_count: int) -> float:
	if action.has("units_per_day"):
		return action["units_per_day"]
	var duration: float = action.get("duration_days", 0.0)
	if duration > 0.0 and unit_count > 0:
		return snappedf(float(unit_count) / duration, 0.01)
	return 0.0

## Unlike the other fields, "type" has no "unset" state to erase back to --
## an OptionButton always has some selection, and ConstructionSchedule's own
## fallback ("scale_up" if the key is absent) is just where new actions start
## out, not a meaningfully different state from writing "scale_up" explicitly
## -- so this always writes the selected value.
func _on_type_edited(action: Dictionary, selected_type: String) -> void:
	action["type"] = selected_type
	_on_dirty.call()

# --- Cadencia (batch) / Escalonado (stagger) ------------------------------
#
# Which of the two real construction methods an action represents: a single
# concrete pour whose several meshes exist only because the model was split
# for convenience (Simultáneo -- they must rise as one), or discrete units
# genuinely placed one after another (Escalonado). Cadence.compute_timings()
# has honored the "batch" field since Phase 1 and both action paths call it;
# what was missing was any way to see or set it outside a text editor.
#
# Escalonado (s) is the per-part delay -- Cadence's "stagger" field. It is
# only consulted when batch is false, so it is disabled in the Simultáneo
# case rather than silently accepting a value that does nothing.

## Unlike Type, "batch" has a real unset state (absent = Cadence's own `false`
## default), but it is written explicitly either way: the two states are a
## genuine authoring decision about how the work is done, and a row reading
## "Escalonado" because nobody ever considered it is indistinguishable from
## one that was deliberately set that way. IFCScheduleGenerator writes the
## field explicitly for the same reason.
# ---------------------------------------------------------------------------
# Encofrado / Días vertido -- 07_FORMWORK.md build order step 5
# ---------------------------------------------------------------------------

## The root "formwork_defaults" block, or {}. Read live rather than cached: the
## dock's project-wide toggle writes it, and every row has to re-resolve
## against whatever it currently says.
func _root_formwork_defaults() -> Dictionary:
	if not _sequence_manager:
		return {}
	return ConstructionSchedule.formwork_defaults(_sequence_manager.sequence_data)

## Which of the dropdown's four modes this action actually resolves to, asking
## the same resolve_formwork_config() the schedule asks. Tier order matches the
## table in 07_FORMWORK.md: prefix, then model, then generic.
func _resolve_formwork_mode(action: Dictionary) -> String:
	var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, _root_formwork_defaults())
	if cfg.is_empty():
		return "none"
	if String(cfg.get("prefix", "")) != "":
		return "prefix"
	if String(cfg.get("model", "")) != "":
		return "model"
	return "generic"

## What the Días vertido spinner shows: the resolved pour_days, or the engine
## default when formwork is on and nothing overrides it. 0 for a row with no
## formwork at all, where the spinner is disabled anyway.
func _resolved_pour_days(action: Dictionary) -> float:
	var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, _root_formwork_defaults())
	if cfg.is_empty():
		return 0.0
	var raw = cfg.get("pour_days", ConstructionSchedule.DEFAULT_POUR_DAYS)
	return float(raw) if (raw is float or raw is int) else ConstructionSchedule.DEFAULT_POUR_DAYS

## This action's own "formwork" block as a Dictionary, creating it if the action
## has none or carries the `false` shorthand. Deliberately left empty rather
## than seeded from the root defaults: resolve_formwork_config() already merges
## those in, so copying them onto the action would only freeze a snapshot of
## whatever the project-wide toggle happened to say at the time.
func _formwork_block(action: Dictionary) -> Dictionary:
	var raw = action.get("formwork")
	if raw is Dictionary:
		raw.erase("enabled") # any explicit mode is an opt back IN
		return raw
	var block: Dictionary = {}
	action["formwork"] = block
	return block

func _on_formwork_mode_edited(action: Dictionary, mode: String, pour_spin: SpinBox) -> void:
	if mode == "none":
		# An explicit opt-out is the only way to say no to a project-wide
		# default; with no default, erasing the key leaves the action
		# byte-identical to a pre-formwork one, which is the better of the two.
		if _root_formwork_defaults().is_empty():
			action.erase("formwork")
		else:
			action["formwork"] = false
	else:
		var block: Dictionary = _formwork_block(action)
		# Genérico has to actively clear a geometry link, or the resolved tier
		# wouldn't change and the dropdown would snap straight back. An empty
		# string rather than an erase when the link came from the root defaults:
		# erasing a key the action never had cannot shadow a default.
		var defaults: Dictionary = _root_formwork_defaults()
		for key in ["prefix", "model"]:
			if mode == key:
				continue
			if String(defaults.get(key, "")) != "":
				block[key] = ""
			else:
				block.erase(key)
	# no_signal: assigning .value re-enters _on_pour_days_edited(), which would
	# write the resolved default back as an explicit per-action override -- the
	# same reason _on_duration_edited() uses it on units_spin.
	pour_spin.set_value_no_signal(_resolved_pour_days(action))
	refresh_formwork_states()
	_on_dirty.call()

func _on_pour_days_edited(action: Dictionary, value: float) -> void:
	var raw = action.get("formwork")
	if not (raw is Dictionary):
		return # spinner is disabled for a row with no formwork; nothing to write
	# 0 = unset, the same convention Escalonado / Retraso / Duración already use
	# in this grid -- it erases the key so DEFAULT_POUR_DAYS applies again.
	if value <= 0.0:
		raw.erase("pour_days")
	else:
		raw["pour_days"] = value
	refresh_formwork_states()
	_on_dirty.call()

## Re-evaluates every row's Encofrado/Días vertido pair. Cheap (24 rows on this
## model) and called after anything that can change a resolved tier, which is
## why it walks all rows rather than being threaded through each handler: the
## project-wide toggle changes every row at once, and a Duration edit changes
## whether *this* row still has room for a formwork phase.
func refresh_formwork_states() -> void:
	for entry in _formwork_fields:
		_update_formwork_states(entry)

func _update_formwork_states(entry: Dictionary) -> void:
	var action: Dictionary = entry.action
	var button: OptionButton = entry.button
	var spin: SpinBox = entry.spin
	var mode: String = _resolve_formwork_mode(action)
	var cfg: Dictionary = ConstructionSchedule.resolve_formwork_config(action, _root_formwork_defaults())

	for i in range(_FORMWORK_DISPLAY_NAMES.size()):
		var item_mode: String = _FORMWORK_DISPLAY_NAMES[i].mode
		if item_mode == mode:
			button.select(i)
		# Tier 1/2 are selectable only once a path/prefix exists to select them
		# with -- see _FORMWORK_DISPLAY_NAMES and 07_FORMWORK.md decision 8.
		if item_mode == "model" or item_mode == "prefix":
			button.get_popup().set_item_disabled(i, String(cfg.get(item_mode, "")) == "")

	spin.editable = mode != "none"
	spin.set_value_no_signal(_resolved_pour_days(action))

	# A row with no room falls back to one continuous pour and generates no
	# geometry at all. That is correct behaviour, but it looks exactly like a
	# broken row, so it is flagged where it happens rather than only in a
	# console warning nobody reads while authoring. Same reasoning as the
	# zero-match prefix marker in _add_action_row().
	var no_room := false
	if mode != "none":
		var duration: float = ConstructionSchedule._resolve_duration_days(action, entry.unit_count)
		var split: Dictionary = ConstructionSchedule._resolve_formwork_split(
			action, _root_formwork_defaults(), duration, ConstructionSchedule._action_id(action), false)
		no_room = split.formwork_days <= 0.0
	if no_room:
		spin.get_line_edit().add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		spin.tooltip_text = "⚠ This action is only %.2f day(s) long, which leaves no room for a formwork phase -- it pours across the whole window and generates no forms.\n\nLengthen Duration (días) or shorten Días vertido." % ConstructionSchedule._resolve_duration_days(action, entry.unit_count)
	else:
		spin.get_line_edit().remove_theme_color_override("font_color")
		spin.tooltip_text = "How long the pour itself takes. The forms get Duration (días) minus this. 0 = unset (defaults to %.1f)." % ConstructionSchedule.DEFAULT_POUR_DAYS

func _on_batch_edited(action: Dictionary, unit_count: int, batch: bool, batch_button: OptionButton, stagger_spin: SpinBox) -> void:
	action["batch"] = batch
	_update_cadence_editable_states(action, unit_count, batch_button, stagger_spin)
	_on_dirty.call()

## 0 erases rather than storing a literal zero, matching Duration/Lag's
## "0 = unset" convention elsewhere in this grid. A zero stagger would in any
## case just be a second, less obvious spelling of Simultáneo.
func _on_stagger_edited(action: Dictionary, value: float) -> void:
	if value <= 0.0:
		action.erase("stagger")
	else:
		action["stagger"] = value
	_on_dirty.call()

## Greys out whichever cadence control currently has no effect: the whole
## choice for a single-part action (nothing to order), and the stagger delay
## whenever the action batches. Tooltips carry the reason -- a disabled
## control with no explanation reads as a bug.
func _update_cadence_editable_states(action: Dictionary, unit_count: int, batch_button: OptionButton, stagger_spin: SpinBox) -> void:
	var batch := bool(action.get("batch", false))
	var multi_part: bool = unit_count > 1

	batch_button.disabled = not multi_part
	if multi_part:
		batch_button.tooltip_text = "Simultáneo: this action's %d parts all move together (one pour split into several meshes). Escalonado: they arrive one after another, %s apart. Writes the JSON \"batch\" field." % [
			unit_count, _stagger_description(action)]
	else:
		batch_button.tooltip_text = "Only one part matches this action, so there is nothing to order -- cadence has no effect either way."

	stagger_spin.editable = multi_part and not batch
	if batch:
		stagger_spin.tooltip_text = "Delay between consecutive parts, in cadence seconds. Unused while Cadencia is Simultáneo."
	else:
		stagger_spin.tooltip_text = "Delay between consecutive parts, in cadence seconds (0 = unset, defaults to 0.75). Relative only: the whole cadence is normalized to fit the action's Duration (días), so this sets the spacing *within* the action, not its total length."

func _stagger_description(action: Dictionary) -> String:
	return "%.2fs" % action.get("stagger", 0.75)

# --- Start Date / End Date / Duration (days) / Units per Day / Anchor -----
#
# Three quantities, one invariant: End = Start + Duration. Duration and Units
# per Day are already one linked slot (editing either recomputes the other,
# only duration_days is ever persisted -- see _on_duration_edited()/
# _on_units_per_day_edited() below), so there are really 3 independent slots:
# start, duration, end. Anchor names the slot that's protected -- held fixed
# -- when you edit one of the OTHER two; editing either of those recomputes
# the third via _apply_time_edit(). Anchor does NOT lock any field: all
# three stay editable all the time (_update_row_editable_states() no longer
# toggles .editable based on Anchor at all -- it originally did, which read
# as "picking Duration as Anchor greys out Duration," backwards from what
# Anchor is for). Editing the field that's *currently* the Anchor is a
# perfectly normal action (it's how you tell the row "I want to change
# Duration/Units" in the first place) -- there's no third slot left to
# protect by elimination in that case, so _apply_time_edit() falls back to a
# fixed default: editing Duration/Units or Start pushes End (same start,
# different pace/finish); editing End pushes Start (new deadline, same
# pace).
#
# None of this applies to a Depends On row: Start there comes from the
# resolved schedule, not a free value, so Start Date (as a placeholder) and
# End Date (as real text) are always read-only there (kept current by
# refresh_dependency_dates(), not by this system) and Anchor is disabled/
# irrelevant (_update_row_editable_states() handles both).
#
# The three date-math primitives (end/duration/start from the other two) live
# on ConstructionSchedule now (end_date_from_start_and_duration() etc.) --
# shared with ScheduleCsvIO, which needs the same arithmetic for its
# end_date fallback on import.

## Start Date and Duration (days)/Units per Day are always editable -- Anchor
## never locks them (see the header comment above). Only End Date's
## editability is conditional: locked (and showing the resolved schedule
## date) on a Depends On row, since Start there isn't a free value at all;
## locked with a "(set Start Date first)" placeholder if Start Date is blank,
## since there's no real calendar date to compute from/into yet; editable
## otherwise. Anchor itself is disabled on a Depends On row (irrelevant --
## there's no local start+duration arithmetic to steer).
func _update_row_editable_states(action: Dictionary, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	var has_depends: bool = not ConstructionSchedule._depends_on_ids(action).is_empty()
	anchor_button.disabled = has_depends
	date_edit.editable = true
	duration_spin.editable = true
	units_spin.editable = true

	if has_depends:
		end_date_edit.editable = false
		end_date_edit.placeholder_text = "YYYY-MM-DD"
		return

	if date_edit.text.strip_edges().is_empty():
		end_date_edit.editable = false
		end_date_edit.placeholder_text = "(set Start Date first)"
	else:
		end_date_edit.editable = true
		end_date_edit.placeholder_text = "YYYY-MM-DD"

## The core recompute: edited_slot ("start"/"duration"/"end") just changed;
## find whichever of the remaining two slots ISN'T the current Anchor and
## recompute it so Start + Duration = End keeps holding. Only no-ops if
## Start Date is blank/unparseable (nothing to compute real calendar
## arithmetic against) -- editing the field that's currently the Anchor is
## normal (see the header comment above), not a case to reject: with no
## third slot left to protect by elimination, it falls back to a fixed
## default (editing Duration/Units or Start pushes End; editing End pushes
## Start).
func _apply_time_edit(action: Dictionary, edited_slot: String, unit_count: int, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	var anchor: String = anchor_button.get_item_metadata(anchor_button.get_selected())
	var start_text: String = date_edit.text.strip_edges()
	if start_text.is_empty():
		end_date_edit.text = ""
		return

	var recompute: String = ""
	if anchor == edited_slot:
		recompute = "start" if edited_slot == "end" else "end"
	else:
		for slot in ["start", "duration", "end"]:
			if slot != anchor and slot != edited_slot:
				recompute = slot
				break

	match recompute:
		"end":
			end_date_edit.text = ConstructionSchedule.end_date_from_start_and_duration(start_text, duration_spin.value)
		"duration":
			var new_duration: float = ConstructionSchedule.duration_from_start_and_end(start_text, end_date_edit.text.strip_edges())
			if new_duration > 0.0:
				action.erase("units_per_day")
				action["duration_days"] = new_duration
				duration_spin.set_value_no_signal(new_duration)
				if unit_count > 0:
					units_spin.set_value_no_signal(snappedf(float(unit_count) / new_duration, 0.01))
		"start":
			var new_start: String = ConstructionSchedule.start_date_from_end_and_duration(end_date_edit.text.strip_edges(), duration_spin.value)
			if new_start != "":
				action["start_date"] = new_start
				date_edit.text = new_start

func _on_anchor_changed(action: Dictionary, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	_update_row_editable_states(action, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)

func _on_date_edited(action: Dictionary, unit_count: int, date_edit: LineEdit, depends_edit: LineEdit, anchor_button: OptionButton, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	var text = date_edit.text.strip_edges()
	if text.is_empty():
		action.erase("start_date")
	else:
		action["start_date"] = text
		# Explicit start_date always wins over depends_on (see
		# ConstructionSchedule._resolve_action_start_day()) -- clear the
		# dependency here too so the row doesn't show a date and a dependency
		# that silently disagree about what's actually driving the schedule.
		action.erase("depends_on")
		depends_edit.text = ""
	_apply_time_edit(action, "start", unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	_update_row_editable_states(action, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	_on_dirty.call()

func _on_end_date_edited(action: Dictionary, unit_count: int, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	_apply_time_edit(action, "end", unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	_on_dirty.call()

## Parses a comma-separated id list. 0 ids erases depends_on; 1 id writes a
## plain string (keeps the common single-predecessor case's JSON identical to
## before multi-predecessor support existed); 2+ writes an Array -- both
## forms are read back by ConstructionSchedule._depends_on_ids().
func _on_depends_on_edited(action: Dictionary, depends_edit: LineEdit, date_edit: LineEdit, anchor_button: OptionButton, end_date_edit: LineEdit, duration_spin: SpinBox, units_spin: SpinBox) -> void:
	var ids: Array = []
	for part in depends_edit.text.split(","):
		var trimmed: String = part.strip_edges()
		if trimmed != "" and not ids.has(trimmed):
			ids.append(trimmed)

	if ids.is_empty():
		action.erase("depends_on")
	else:
		action["depends_on"] = ids[0] if ids.size() == 1 else ids
		# Mirror of _on_date_edited() above: a dependency only takes effect
		# once no explicit start_date is present to override it.
		action.erase("start_date")
		date_edit.text = ""
	_update_row_editable_states(action, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	_on_dirty.call()

## An id change can affect every other row's Depends On options and this
## row's own Action label, so this rebuilds the whole inspector grid
## immediately (not the schedule, like every other field's handler -- just
## the grid, which is cheap; it doesn't touch ConstructionSchedule) -- safe
## to call from inside id_edit's own signal handler since clear()
## uses queue_free(), which defers the actual deletion past this frame.
## Drops an action out of sequence_data entirely, then rebuilds the grid.
##
## No confirmation dialog: this only mutates the in-memory sequence_data that
## every other field edit in this grid already mutates, so the existing
## "Save to JSON / Reload from JSON" pair is the undo -- the same safety net a
## mistyped date has. A modal here would be the only one in the dock.
##
## Located by identity (is_same()) rather than by index or by value: the row
## holds a direct reference to the action Dictionary, `step_index` is the
## JSON's own "index" field rather than an array position, and two actions with
## identical contents would be indistinguishable by value.
func _on_remove_pressed(action: Dictionary) -> void:
	var removed_id: String = ConstructionSchedule._action_id(action)
	for step in _sequence_manager.sequence_data.get("steps", []):
		var actions: Array = step.get("actions", [])
		for i in range(actions.size()):
			if is_same(actions[i], action):
				actions.remove_at(i)
				_warn_orphaned_dependents(removed_id)
				build(_sequence_manager, _current_schedule)
				_on_dirty.call()
				return

## A removed action can still be named by another action's depends_on.
## ConstructionSchedule already handles that gracefully (an unresolvable id is
## warned about individually and excluded from the "latest predecessor"
## calculation, without blocking the others), so this doesn't cascade the
## delete -- it just says so at the moment of removal, when the author can
## still tell whether that dependency mattered.
func _warn_orphaned_dependents(removed_id: String) -> void:
	if removed_id == "":
		return
	var dependents: Array = []
	for step in _sequence_manager.sequence_data.get("steps", []):
		for other in step.get("actions", []):
			if ConstructionSchedule._depends_on_ids(other).has(removed_id):
				dependents.append(ConstructionSchedule._action_id(other))
	if not dependents.is_empty():
		push_warning("Schedule inspector: removed '%s', still referenced by depends_on in: %s" % [
			removed_id, ", ".join(dependents)])

func _on_id_edited(action: Dictionary, id_edit: LineEdit) -> void:
	var text = id_edit.text.strip_edges()
	if text.is_empty():
		action.erase("id")
	else:
		action["id"] = text
	build(_sequence_manager, _current_schedule)
	_on_dirty.call()

func _on_lag_edited(action: Dictionary, value: float) -> void:
	# 0 means "unset" (matches every other 0-means-unset field in this
	# inspector); unlike Duration/Units per Day, a *negative* lag is a
	# legitimate value here -- lead time / overlap with the predecessor -- so
	# only exactly 0.0 erases the key.
	if value == 0.0:
		action.erase("lag_days")
	else:
		action["lag_days"] = value
	_on_dirty.call()

func _on_duration_edited(action: Dictionary, value: float, unit_count: int, units_spin: SpinBox, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, duration_spin: SpinBox) -> void:
	action.erase("units_per_day")
	if value <= 0.0:
		action.erase("duration_days")
		units_spin.set_value_no_signal(0.0)
	else:
		action["duration_days"] = value
		if unit_count > 0:
			units_spin.set_value_no_signal(snappedf(float(unit_count) / value, 0.01))
	_apply_time_edit(action, "duration", unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	# Shortening an action below its pour length is exactly how a row silently
	# loses its formwork phase -- re-mark it while the edit is in view.
	refresh_formwork_states()
	_on_dirty.call()

func _on_units_per_day_edited(action: Dictionary, value: float, unit_count: int, duration_spin: SpinBox, anchor_button: OptionButton, date_edit: LineEdit, end_date_edit: LineEdit, units_spin: SpinBox) -> void:
	action.erase("units_per_day")
	if value <= 0.0 or unit_count <= 0:
		duration_spin.set_value_no_signal(action.get("duration_days", 0.0))
	else:
		# No ceil() here, unlike ConstructionSchedule._resolve_duration_days()
		# (which rounds a hand-authored units_per_day up to a whole calendar
		# day -- a reasonable convention for raw JSON, but lossy for this
		# inspector's own round-trip: rounding duration_days up on save meant
		# reloading recomputed a *different* units_per_day than what was
		# typed, e.g. 5 units/day for 24 units saved as 5 days (ceil(4.8)),
		# which reloaded back as 4.8 units/day, not 5). Storing the exact
		# fractional value here keeps Duration (days) <-> Units/Day lossless.
		var derived_duration: float = snappedf(float(unit_count) / value, 0.0001)
		action["duration_days"] = derived_duration
		duration_spin.set_value_no_signal(derived_duration)
	_apply_time_edit(action, "duration", unit_count, anchor_button, date_edit, end_date_edit, duration_spin, units_spin)
	# Shortening an action below its pour length is exactly how a row silently
	# loses its formwork phase -- re-mark it while the edit is in view.
	refresh_formwork_states()
	_on_dirty.call()

## Updates every Depends On row's read-only dates to the given schedule's
## actually-resolved calendar dates -- needed because a dependent row's dates
## can change from an edit made on a *different* row entirely (e.g. its
## predecessor's duration changed), which that other row's own handlers have
## no way to know about. Rows without depends_on are skipped; their dates are
## already kept current by their own field handlers (_apply_time_edit()) via
## local start+duration arithmetic. Called both internally (after build())
## and externally by the dock after every _rebuild_schedule().
##
## Start Date stays genuinely empty (.text) even on a Depends On row -- it
## must, so the existing "type a date to override the dependency" flow (see
## _on_date_edited()) keeps working, and so this function doesn't
## misinterpret its own display text as a user edit on the next pass. The
## resolved value is shown as a placeholder instead
## (LineEdit.placeholder_text), which is purely visual and never read back as
## input. End Date has no such constraint -- it's always non-editable on a
## Depends On row, so showing the resolved value as real .text is safe and
## is what actually gets displayed (a placeholder only shows when text is
## empty).
func refresh_dependency_dates(current_schedule: ConstructionSchedule) -> void:
	_current_schedule = current_schedule
	if not _current_schedule:
		return
	for entry in _resolved_date_fields:
		var action: Dictionary = entry.action
		if ConstructionSchedule._depends_on_ids(action).is_empty():
			continue
		var action_id: String = ConstructionSchedule._action_id(action)
		var day_range: Dictionary = _current_schedule.get_action_day_range(action_id)
		var date_edit: LineEdit = entry.date_edit
		var end_date_edit: LineEdit = entry.end_date_edit
		if day_range.is_empty():
			date_edit.placeholder_text = "YYYY-MM-DD"
			end_date_edit.text = ""
			continue
		date_edit.placeholder_text = _current_schedule.day_to_date_string(day_range.start_day)
		end_date_edit.text = _current_schedule.day_to_date_string(day_range.finish_day)
