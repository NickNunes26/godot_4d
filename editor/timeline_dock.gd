## Phase 3 editor dock: live-scrubs the 4D construction timeline in the
## currently edited scene's 3D viewport, without entering Play mode.
##
## Reuses ConstructionSchedule/TimelineController/AnimationApplier/
## SpatialGrouper exactly as they run at runtime -- no core logic is
## duplicated here, only the editor-specific wiring (target detection,
## preview lifecycle, and the pre/post-preview material snapshot needed to
## make preview safely reversible). See addons/construction_4d_tool/docs/README.md's Phase 3
## section for the full design rationale, especially why the dock passes no crane.
##
## This file is the orchestrator only: preview lifecycle, target detection,
## and button wiring. The schedule inspector grid lives in
## ScheduleInspector (schedule_inspector.gd) and CSV export/import logic in
## ScheduleCsvIO (schedule_csv_io.gd) -- both owned here as plain instances,
## split out once this file grew past 1100 lines mixing all three concerns.
@tool
extends Control

const SequenceManagerScript = preload("res://addons/construction_4d_tool/runtime/sequence_manager.gd")
const TimelineUIScene = preload("res://addons/construction_4d_tool/runtime/timeline_ui.tscn")

@onready var _target_label: Label = $VBox/TargetLabel
@onready var _start_button: Button = $VBox/Buttons/StartButton
@onready var _stop_button: Button = $VBox/Buttons/StopButton
@onready var _warning_label: Label = $VBox/WarningLabel
@onready var _dirty_label: Label = $VBox/DirtyLabel
@onready var _ui_container: Control = $VBox/UIContainer
@onready var _inspector_list: GridContainer = $VBox/InspectorScroll/InspectorList
@onready var _formwork_check: CheckBox = $VBox/FormworkBar/FormworkCheck
@onready var _formwork_pour_spin: SpinBox = $VBox/FormworkBar/FormworkPourSpin
@onready var _pour_check: CheckBox = $VBox/PourBar/PourCheck
@onready var _pour_grid: GridContainer = $VBox/PourGrid
@onready var _recalculate_button: Button = $VBox/InspectorButtons/RecalculateButton
@onready var _reload_button: Button = $VBox/InspectorButtons/ReloadButton
@onready var _save_button: Button = $VBox/InspectorButtons/SaveButton
@onready var _capture_camera_button: Button = $VBox/InspectorButtons/CaptureCameraButton
@onready var _export_csv_button: Button = $VBox/InspectorButtons/ExportCsvButton
@onready var _import_csv_button: Button = $VBox/InspectorButtons/ImportCsvButton
@onready var _export_project_xml_button: Button = $VBox/InspectorButtons/ExportProjectXmlButton
@onready var _import_project_xml_button: Button = $VBox/InspectorButtons/ImportProjectXmlButton

var _sequence_manager: Node = null
var _controller: TimelineController = null
var _timeline_ui: TimelineUI = null

# Parts collected read-only before initialize_parts() runs, purely so the
# material snapshot below is captured pre-duplication. Uses
# SequenceManager.collect_part_nodes(), the same read-only selection
# initialize_parts() uses (parts_container_path + extra_part_containers).
var _preview_parts: Array = []
var _material_snapshot: Dictionary = {} # MeshInstance3D -> Array[Material]

var _preview_active: bool = false
var _last_edited_root: Node = null

# Shared with _rebuild_schedule() and ScheduleInspector so unit-count lookups
# for the inspector's Units/Day <-> Duration (days) conversion and schedule
# rebuilds hit the same per-prefix group cache instead of recomputing it from
# scratch each time.
var _grouper := SpatialGrouper.new()

# The most recently built schedule (also passed to _controller/_timeline_ui),
# kept here too so ScheduleInspector/ScheduleCsvIO can query
# get_action_day_range()/day_to_date_string() for Depends On rows' read-only
# dates and CSV export's resolved End Date without threading the schedule
# through every call site.
var _current_schedule: ConstructionSchedule = null

# Owns the inspector grid (schedule_inspector.gd) and CSV export/import logic
# (schedule_csv_io.gd) -- created in _ready() once the @onready refs above
# are available.
var _inspector: ScheduleInspector = null
var _csv_io := ScheduleCsvIO.new()
var _project_xml_io := ScheduleProjectXmlIO.new()

# True whenever sequence_data has been edited since the last schedule
# rebuild -- see _set_schedule_dirty()/_on_recalculate_pressed(). Field
# edits used to call _rebuild_schedule() directly on every keystroke, which
# reconstructs a whole ConstructionSchedule -- including
# CollisionQuery.setup() (collision_query.gd), which rebuilds a convex hull +
# trimesh PhysicsServer3D shape for every MeshInstance3D part in the project,
# from scratch, every time. That's real, unavoidable-per-call geometry work with
# no caching, so on a project with many parts it made every keystroke
# noticeably slow. Edits now just mark the schedule dirty (via the Callable
# ScheduleInspector is constructed with, see _ready()); rebuilding (and with
# it, the 3D preview / dependency-resolved dates) only happens on demand via
# the Recalculate button.
var _schedule_dirty: bool = false

# Lazily-created shared file dialogs -- one per format (CSV / Project XML),
# each reused for both its Export and Import button (see _ensure_csv_dialog()/
# _ensure_project_xml_dialog()). The _mode fields record which action the
# next file_selected signal should perform.
var _csv_dialog: EditorFileDialog = null
var _csv_dialog_mode: String = ""
var _project_xml_dialog: EditorFileDialog = null
var _project_xml_dialog_mode: String = ""

# The active manual-mapping popup for a Project XML import with unmatched
# tasks (see _import_project_xml()) -- null when no import is pending one.
# Kept as a field (not a local closure variable) purely so it's reachable if
# ever needed for debugging; the dialog frees itself via queue_free() in both
# its confirmed/canceled handlers.
var _mapping_dialog: ProjectXmlMappingDialog = null

var _ifc_manager = null
var _ifc_file_dialog: EditorFileDialog = null
# What GDIFCRecenter stripped from the file being imported, and the framing
# shift _recenter_to_origin() applied after load: together they say where the
# imported parts are on the map (GeoOrigin.from_ifc_import()).
var _ifc_import_info: Dictionary = {}
var _ifc_framing_shift := Vector3.ZERO
# The file the user picked (the one GDIFC reads may be a recentered copy):
# names the model's container, so importing it again replaces it.
var _ifc_source_path := ""

# The "Terreno" section (terrain_panel.gd).
var _terrain_panel: TerrainPanel = null
# GeoSun transforms before Start Preview, so the preview's date-driven sun
# never leaks into the saved scene (same guarantee as the parts' snapshot).
var _sun_snapshot: Dictionary = {} # GeoSun -> Transform3D

func _ready() -> void:
	_inspector = ScheduleInspector.new(_inspector_list, _grouper, _on_schedule_edited)
	_start_button.pressed.connect(_on_start_pressed)
	_stop_button.pressed.connect(_on_stop_pressed)
	_recalculate_button.pressed.connect(_on_recalculate_pressed)
	_reload_button.pressed.connect(_on_reload_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_capture_camera_button.pressed.connect(_on_capture_camera_pressed)
	_capture_camera_button.tooltip_text = "Adds a camera keyframe at the currently previewed date, using wherever the editor's 3D viewport camera is right now.\n\nWritten straight to camera_track.json (its own file -- regenerating the schedule can't touch it). Applied only when recording in Movie Maker Mode, or with SequenceManager's movie_mode_override on; the free-fly camera is unaffected otherwise."
	_formwork_check.toggled.connect(_on_formwork_defaults_toggled)
	_formwork_check.tooltip_text = "Turns formwork on for every action at once, by writing \"formwork_defaults\" at the root of construction_steps.json.

Individual rows can still opt out with their own Encofrado dropdown. Actions shorter than the pour length have no room for a formwork phase and are marked in the grid."
	_formwork_pour_spin.tooltip_text = "Project-wide pour length in days -- the forms get each action's duration minus this. A row can override it in its own Días vertido column."
	_formwork_pour_spin.value_changed.connect(_on_formwork_defaults_pour_changed)
	_pour_check.tooltip_text = "The falling concrete stream a fill_up action spawns while playing.

Off unless a project turns it on -- see 08_POUR_STREAM.md. Live playback only; scrubbing never spawns one."
	_pour_check.toggled.connect(_on_pour_toggled)
	for field in _POUR_FIELDS:
		var spin: SpinBox = _pour_grid.get_node(field.node)
		spin.tooltip_text = field.tip
		spin.value_changed.connect(func(v): _on_pour_field_changed(field.key, v))
	_export_csv_button.pressed.connect(_on_export_csv_pressed)
	_import_csv_button.pressed.connect(_on_import_csv_pressed)
	_export_project_xml_button.pressed.connect(_on_export_project_xml_pressed)
	_import_project_xml_button.pressed.connect(_on_import_project_xml_pressed)

	var buttons_container = $VBox/InspectorButtons
	var load_ifc_button = Button.new()
	load_ifc_button.text = "Load IFC (4D)"
	load_ifc_button.pressed.connect(_on_load_ifc_pressed)
	buttons_container.add_child(load_ifc_button)

	var generate_schedule_button = Button.new()
	generate_schedule_button.text = "Generate 4D Schedule"
	generate_schedule_button.tooltip_text = "Writes the schedule JSON from the IFC properties you selected (see Edit IFC mapping) on the imported parts."
	generate_schedule_button.pressed.connect(_on_generate_schedule_pressed)
	buttons_container.add_child(generate_schedule_button)

	var edit_mapping_button = Button.new()
	edit_mapping_button.text = "Edit IFC mapping"
	edit_mapping_button.tooltip_text = "Choose which IFC properties are the element id, dates and animation type."
	edit_mapping_button.pressed.connect(_on_edit_ifc_mapping_pressed)
	buttons_container.add_child(edit_mapping_button)

	_terrain_panel = TerrainPanel.new()
	$VBox.add_child(_terrain_panel)

	_dirty_label.visible = false
	_warning_label.visible = false
	_stop_button.disabled = true
	_refresh_formwork_bar()
	_refresh_pour_bar()
	_refresh_target()

func _process(_delta: float) -> void:
	var root = EditorInterface.get_edited_scene_root()
	if root == _last_edited_root:
		return
	_last_edited_root = root
	# Switching scene tabs out from under an active preview would otherwise
	# leave the previous scene's parts mutated with no way to restore them
	# from this dock anymore -- always restore first.
	if _preview_active:
		stop_preview()
	_refresh_target()
	if _terrain_panel:
		_terrain_panel.refresh()

func _refresh_target() -> void:
	var root = EditorInterface.get_edited_scene_root()
	_sequence_manager = _find_sequence_manager(root) if root else null
	if _sequence_manager:
		_target_label.text = "Target: %s" % _sequence_manager.name
	else:
		_target_label.text = "No SequenceManager found in the open scene."
	_start_button.disabled = _sequence_manager == null or _preview_active

# Identifies the target by script identity, not node name, so it isn't tied
# to a specific scene layout (see addons/construction_4d_tool/docs/03_PLUGIN_DISTRIBUTION.md's
# anti-pattern list -- "assume a specific scene structure").
func _find_sequence_manager(node: Node) -> Node:
	if node.get_script() == SequenceManagerScript:
		return node
	for child in node.get_children():
		var found = _find_sequence_manager(child)
		if found:
			return found
	return null

func _on_start_pressed() -> void:
	start_preview()

func _on_stop_pressed() -> void:
	stop_preview()

func start_preview() -> void:
	if _preview_active or not _sequence_manager:
		return

	var scene_root = EditorInterface.get_edited_scene_root()
	_preview_parts = _collect_preview_parts(_sequence_manager, scene_root)
	_material_snapshot = _snapshot_materials(_preview_parts)
	_sun_snapshot.clear()
	for sun in get_tree().get_nodes_in_group(GeoSun.GROUP):
		_sun_snapshot[sun] = (sun as Node3D).transform

	# Reuses SequenceManager's own setup exactly as Play mode does: parses
	# the JSON, registers building_parts, sets the original_pos/scale/
	# transform/aabb metas (which double as this preview's restore
	# snapshot), duplicates materials, and hides/zero-scales every part.
	_sequence_manager.load_json()
	# Before initialize_parts(), so generated panels are registered and hidden
	# like any other part. Safe to call on every Start Preview -- FormworkBuilder
	# sweeps its own previous output first.
	_sequence_manager._generate_formwork()
	_sequence_manager.initialize_parts()

	var schedule = ConstructionSchedule.new(
		_sequence_manager.sequence_data,
		_sequence_manager.building_parts,
		_grouper
	)
	_current_schedule = schedule

	_controller = TimelineController.new()
	add_child(_controller)
	# No crane(s) in editor preview -- deliberately out of scope for this
	# slice, see addons/construction_4d_tool/docs/README.md's Phase 3 section.
	_controller.set_schedule(schedule, _sequence_manager.building_parts, {})

	_timeline_ui = TimelineUIScene.instantiate()
	_ui_container.add_child(_timeline_ui)
	_timeline_ui.set_timeline_controller(_controller, schedule)
	_push_pour_stream()

	_preview_active = true
	_warning_label.visible = true
	_start_button.disabled = true
	_stop_button.disabled = false
	_recalculate_button.disabled = false
	_reload_button.disabled = false
	_save_button.disabled = false
	_capture_camera_button.disabled = false
	_export_csv_button.disabled = false
	_import_csv_button.disabled = false
	_export_project_xml_button.disabled = false
	_import_project_xml_button.disabled = false
	_set_schedule_dirty(false)
	_refresh_formwork_bar()
	_refresh_pour_bar()
	_inspector.build(_sequence_manager, _current_schedule)

func stop_preview() -> void:
	if not _preview_active:
		return

	for part in _preview_parts:
		if not is_instance_valid(part):
			continue
		if part.has_meta("original_pos"):
			part.position = part.get_meta("original_pos")
		if part.has_meta("original_scale"):
			part.scale = part.get_meta("original_scale")
		part.visible = true
	_restore_materials(_material_snapshot)
	_material_snapshot.clear()
	_preview_parts.clear()
	for sun in _sun_snapshot:
		if is_instance_valid(sun):
			sun.transform = _sun_snapshot[sun]
			sun.set("_date", {})
	# The edited scene shows the finished ground, not wherever preview left it.
	ConstructionTerrain.reset_all(get_tree())
	_sun_snapshot.clear()

	# Generated formwork is a view of the schedule, not part of the scene, and
	# is deliberately never owned -- so it would not be saved, but it would sit
	# in the tree looking like real geometry until the next Start Preview swept
	# it. Remove it with the rest of the preview state instead.
	FormworkBuilder.sweep(_sequence_manager._parts_container() if _sequence_manager else null)

	if _timeline_ui:
		_timeline_ui.queue_free()
		_timeline_ui = null
	if _controller:
		_controller.queue_free()
		_controller = null

	_preview_active = false
	_warning_label.visible = false
	_stop_button.disabled = true
	_start_button.disabled = _sequence_manager == null
	_recalculate_button.disabled = true
	_reload_button.disabled = true
	_save_button.disabled = true
	_capture_camera_button.disabled = true
	_export_csv_button.disabled = true
	_import_csv_button.disabled = true
	_export_project_xml_button.disabled = true
	_import_project_xml_button.disabled = true
	_set_schedule_dirty(false)
	_refresh_formwork_bar()
	_refresh_pour_bar()
	_inspector.clear()

# ---------------------------------------------------------------------------
# Project-wide formwork (07_FORMWORK.md build order step 5, decision 9)
# ---------------------------------------------------------------------------

## Syncs the checkbox and its pour spinner from whatever the JSON currently
## says, without re-firing their own handlers. Called wherever the inspector is
## (re)built, since Reload from JSON and CSV/XML import can all change the root
## block underneath the control.
## The Vertido spinners, in grid order: which SpinBox writes which JSON key.
## Driven from one table rather than six handlers, since every one of them does
## the identical "write this number into the root pour_stream block" job.
const _POUR_FIELDS := [
	{"node": "Amount", "key": "amount", "def": 800.0, "tip": "Particles in the falling column. More reads as a denser, more continuous stream; fewer reads as gravel."},
	{"node": "Grain", "key": "grain", "def": 0.0, "tip": "Particle size in world metres. 0 derives it from the element being poured, which is the original behaviour -- this model runs from a 0.71 m pier to a very large footing, so one fixed size reads wrong at one end."},
	{"node": "Spread", "key": "spread_deg", "def": 8.0, "tip": "Emitter cone angle in degrees. A small fan keeps the column from resolving into parallel vertical stripes; a large one makes it a shower rather than a chute."},
	{"node": "Speed", "key": "speed", "def": 2.0, "tip": "Initial downward velocity -- how hard the concrete is pushed out. Particle lifetime is solved against this, so the stream still lands exactly on the surface."},
	{"node": "Fall", "key": "fall", "def": 0.0, "tip": "Drop height above the fill surface, in metres. 0 derives it from the element's own span."},
	{"node": "Splash", "key": "splash_amount", "def": 220.0, "tip": "Particles in the landing spread where the stream meets the concrete. 0 removes the splash entirely."},
]

## Syncs the Vertido controls from the JSON without re-firing their handlers,
## and greys the grid out when the stream is off -- the numbers are meaningless
## with nothing to apply them to.
func _refresh_pour_bar() -> void:
	var enabled := _sequence_manager != null and _preview_active
	_pour_check.disabled = not enabled
	if not _sequence_manager:
		_pour_check.set_pressed_no_signal(false)
		_pour_grid.visible = false
		return
	var cfg: Dictionary = AnimationApplier.pour_stream_config(_sequence_manager.sequence_data)
	var on: bool = not cfg.is_empty()
	_pour_check.set_pressed_no_signal(on)
	_pour_grid.visible = on
	for field in _POUR_FIELDS:
		var spin: SpinBox = _pour_grid.get_node(field.node)
		spin.editable = enabled
		var raw = cfg.get(field.key, field.def)
		spin.set_value_no_signal(float(raw) if (raw is float or raw is int) else field.def)

## Writes or erases the root "pour_stream" block. Erasing on the way off rather
## than storing {"enabled": false}: with no block at all there is no stream and
## no particle node is ever built, which is the state this feature defaults to
## and the one worth being able to get back to exactly.
func _on_pour_toggled(pressed: bool) -> void:
	if not _sequence_manager:
		return
	if pressed:
		var block: Dictionary = {"enabled": true}
		for field in _POUR_FIELDS:
			block[field.key] = (_pour_grid.get_node(field.node) as SpinBox).value
		_sequence_manager.sequence_data["pour_stream"] = block
	else:
		_sequence_manager.sequence_data.erase("pour_stream")
	_push_pour_stream()
	_refresh_pour_bar()
	_on_schedule_edited()

func _on_pour_field_changed(key: String, value: float) -> void:
	if not _sequence_manager:
		return
	var block = _sequence_manager.sequence_data.get("pour_stream")
	if not (block is Dictionary):
		return
	block[key] = value
	_push_pour_stream()
	_on_schedule_edited()

## Hands the live controller the new settings immediately, so the next pour in
## the running preview uses them. Without this a tuning pass would need a
## Recalculate (or a restart) to show anything, which is exactly the slow loop
## putting these controls in the dock is meant to remove.
func _push_pour_stream() -> void:
	if _controller:
		_controller.pour_stream = AnimationApplier.pour_stream_config(_sequence_manager.sequence_data)

func _refresh_formwork_bar() -> void:
	var enabled := _sequence_manager != null and _preview_active
	_formwork_check.disabled = not enabled
	_formwork_pour_spin.editable = enabled
	if not _sequence_manager:
		_formwork_check.set_pressed_no_signal(false)
		return
	var defaults: Dictionary = ConstructionSchedule.formwork_defaults(_sequence_manager.sequence_data)
	_formwork_check.set_pressed_no_signal(not defaults.is_empty())
	var raw = defaults.get("pour_days", ConstructionSchedule.DEFAULT_POUR_DAYS)
	_formwork_pour_spin.set_value_no_signal(float(raw) if (raw is float or raw is int) else ConstructionSchedule.DEFAULT_POUR_DAYS)

## Writes or erases the root "formwork_defaults" block -- the project-wide
## switch. A sibling of static_prefixes/excluded_prefixes, and placed there for
## the same reason: it describes the project, not one task.
##
## Erasing rather than writing {"enabled": false} on the way off: with no root
## block at all, an action carrying no "formwork" key is byte-identical to a
## pre-formwork one, which is the backwards-compatibility bar this feature set
## for itself. Per-row opt-outs ("formwork": false) are deliberately left alone
## -- they are the author's statement about that row, and they become live again
## the moment the project default comes back.
func _on_formwork_defaults_toggled(pressed: bool) -> void:
	if not _sequence_manager:
		return
	if pressed:
		_sequence_manager.sequence_data["formwork_defaults"] = {"pour_days": _formwork_pour_spin.value}
	else:
		_sequence_manager.sequence_data.erase("formwork_defaults")
	_inspector.refresh_formwork_states()
	_on_schedule_edited()

func _on_formwork_defaults_pour_changed(value: float) -> void:
	if not _sequence_manager or not _formwork_check.button_pressed:
		return
	var defaults = _sequence_manager.sequence_data.get("formwork_defaults")
	if not (defaults is Dictionary):
		return
	defaults["pour_days"] = value
	_inspector.refresh_formwork_states()
	_on_schedule_edited()

func _collect_preview_parts(sequence_manager: Node, scene_root: Node) -> Array:
	return sequence_manager.collect_part_nodes()

## Records every surface override the preview is about to overwrite, keyed by
## the MeshInstance3D that carries it -- so stop_preview() can put the edited
## scene back exactly as it found it.
##
## Keyed by mesh node rather than by part because a part is not necessarily a
## MeshInstance3D: SequenceManager.make_materials_unique() duplicates materials
## on a composite part's mesh *children* too (07_FORMWORK.md, decision 7), and
## a snapshot that only looked at parts that were themselves MeshInstance3Ds
## would leave those duplicates behind in the scene when the preview ended.
func _snapshot_materials(parts: Array) -> Dictionary:
	var snapshot: Dictionary = {}
	for part in parts:
		var mesh_nodes: Array = [part] if part is MeshInstance3D else part.find_children("*", "MeshInstance3D", true, false)
		for mesh_node in mesh_nodes:
			var mats: Array = []
			for i in range(mesh_node.get_surface_override_material_count()):
				mats.append(mesh_node.get_surface_override_material(i))
			snapshot[mesh_node] = mats
	return snapshot

func _restore_materials(snapshot: Dictionary) -> void:
	for part in snapshot.keys():
		if not is_instance_valid(part):
			continue
		var mats: Array = snapshot[part]
		for i in range(mats.size()):
			part.set_surface_override_material(i, mats[i])

## Shows/hides the "schedule out of date" warning and enables/disables the
## Recalculate button. Called both directly by this file's own handlers and,
## via the Callable passed to ScheduleInspector's constructor, by every
## inspector field edit -- see _schedule_dirty's doc comment for why edits
## don't rebuild the schedule immediately.
func _set_schedule_dirty(dirty: bool) -> void:
	_schedule_dirty = dirty
	_dirty_label.visible = dirty

func _on_schedule_edited() -> void:
	_set_schedule_dirty(true)

func _on_recalculate_pressed() -> void:
	_rebuild_schedule()
	_set_schedule_dirty(false)

## Re-derives a ConstructionSchedule from the (just-edited) sequence_data and
## rewires the live preview controller/UI to it, preserving the day the
## timeline was showing. ConstructionSchedule has no incremental-update path
## (everything is computed once in _init), so an edit means building a new
## one -- including CollisionQuery.setup() rebuilding a collision shape
## for every mesh part from scratch, which is real geometry work with no
## caching. Cheap enough for an explicit "I'm ready to see the result" action
## (Recalculate, Start Preview, Reload from JSON); too slow to call on every
## keystroke on a project with many parts, which is why field edits no
## longer call this directly -- see _schedule_dirty's doc comment.
func _rebuild_schedule() -> void:
	if not _preview_active or not _controller or not _timeline_ui:
		return
	var saved_day = _controller.current_day
	# Regenerate formwork too: editing Duration or a formwork field can move an
	# action across the "is there room for a formwork phase" threshold, adding or
	# removing its panels entirely. initialize_parts() has to follow, since the
	# panel set it registered is the one that just changed.
	_sequence_manager._generate_formwork()
	_sequence_manager.initialize_parts()
	var schedule = ConstructionSchedule.new(
		_sequence_manager.sequence_data,
		_sequence_manager.building_parts,
		_grouper
	)
	_current_schedule = schedule
	_controller.set_schedule(schedule, _sequence_manager.building_parts, {})
	_timeline_ui.set_timeline_controller(_controller, schedule)
	_push_pour_stream()
	# set_schedule()/set_timeline_controller() both jump to min_day as part of
	# wiring up the new schedule -- restore where the user was scrubbed to.
	# TimelineUI's own _process() re-syncs the slider from current_day next
	# frame (via set_value_no_signal), so no direct slider access is needed
	# here.
	_controller.scrub_to(saved_day)
	_inspector.refresh_dependency_dates(_current_schedule)

func _on_reload_pressed() -> void:
	if not _sequence_manager:
		return
	_sequence_manager.load_json()
	_refresh_formwork_bar()
	_refresh_pour_bar()
	_inspector.build(_sequence_manager, _current_schedule)
	_rebuild_schedule()
	_set_schedule_dirty(false)

func _on_save_pressed() -> void:
	if not _sequence_manager:
		return
	var path: String = _sequence_manager.construction_json_path
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Timeline dock: could not open '%s' for writing" % path)
		return
	file.store_string(JSON.stringify(_sequence_manager.sequence_data, "\t"))
	file.close()
	print("Timeline dock: saved schedule to %s" % path)

func _on_load_ifc_pressed() -> void:
	if not ClassDB.class_exists("GDIFCManager"):
		push_error("GDIFC plugin is not installed or enabled. Please install the GDIFC addon to import IFC models.")
		return
	if not _ifc_file_dialog:
		_ifc_file_dialog = EditorFileDialog.new()
		_ifc_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_ifc_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_ifc_file_dialog.add_filter("*.ifc", "IFC files")
		_ifc_file_dialog.file_selected.connect(_on_ifc_file_selected)
		add_child(_ifc_file_dialog)
	_ifc_file_dialog.popup_file_dialog()

func _on_ifc_file_selected(path: String) -> void:
	var current_scene_root = EditorInterface.get_edited_scene_root()
	if not current_scene_root:
		push_error("No scene is currently open!")
		return
	if not _ifc_manager:
		_ifc_manager = ClassDB.instantiate("GDIFCManager")
		current_scene_root.add_child(_ifc_manager)
		_ifc_manager.owner = current_scene_root
	# Explicitly off: GDIFCRecenter already strips map-sized offsets, and any
	# shift GDIFC made on its own would be one nobody recorded.
	if ClassDB.class_exists("GDIFCLoaderSettings"):
		var settings = ClassDB.instantiate("GDIFCLoaderSettings")
		settings.set("coordinate_to_origin", false)
		_ifc_manager.set_gdifc_settings(settings)

	_ifc_import_info = GDIFCRecenter.recenter_with_info(path)
	_ifc_framing_shift = Vector3.ZERO
	_ifc_source_path = path
	# Connect before reading: a small model can finish loading quickly.
	if not _ifc_manager.ifc_read.is_connected(_on_readed_file):
		_ifc_manager.ifc_read.connect(_on_readed_file)
	# The third argument is the list of IFC classes to build collision for (an
	# Array); passing an int here raised a script error that aborted the import.
	var err = _ifc_manager.read_ifc(_ifc_import_info.path, false, [])
	if err != OK:
		push_error("4D dock: GDIFC could not start reading '%s' (error %s)." % [path, err])
		return
	_ifc_manager.set_display_folded(true)

func _on_readed_file() -> void:
	_recenter_to_origin()
	# Before anything reads the properties: GDIFC hands accented text over
	# mis-decoded ("FormigÃ³n"), see GDIFC4DAdapter.repair_text().
	var repaired := GDIFC4DAdapter.repair_text(_ifc_manager)
	if repaired > 0:
		print("4D dock: repaired accented text GDIFC mis-decoded on %d part(s)." % repaired)
	# The plugin knows no property names: scan what this model carries and let
	# the user say which property is the element id, the dates, etc. A saved
	# mapping that still fits this model is reused silently.
	var scan := IfcPropertyScanner.scan(_ifc_manager)
	var saved := IfcMapping.load_from(_ifc_mapping_path())
	if saved and saved.is_valid() and _mapping_fits_scan(saved, scan):
		_adapt_for_4d_tool(saved)
		return
	var dialog := IfcMappingDialog.new()
	add_child(dialog)
	dialog.setup(scan, saved)
	dialog.mapping_confirmed.connect(func(mapping: IfcMapping):
		mapping.save_to(_ifc_mapping_path())
		_adapt_for_4d_tool(mapping)
		dialog.queue_free())
	dialog.canceled.connect(func():
		push_warning("4D dock: IFC import cancelled -- no properties were mapped.")
		if _ifc_manager:
			_ifc_manager.queue_free()
			_ifc_manager = null
		dialog.queue_free())
	dialog.popup_centered()

## Where the mapping is saved: beside the schedule JSON.
func _ifc_mapping_path() -> String:
	var root = EditorInterface.get_edited_scene_root()
	var sm = _find_sequence_manager(root) if root else null
	var json_path: String = sm.get("construction_json_path") if sm else "res://construction_steps.json"
	return IfcMapping.profile_path_for(json_path)

## Whether every property a saved mapping refers to exists in this model's scan.
func _mapping_fits_scan(mapping: IfcMapping, scan: Dictionary) -> bool:
	var present := {}
	for p in scan.get("properties", []):
		present[JSON.stringify(p.path)] = true
	for path in mapping.referenced_paths():
		if not present.has(JSON.stringify(path)):
			return false
	return true

func _on_edit_ifc_mapping_pressed() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var sm = _find_sequence_manager(scene_root) if scene_root else null
	var container = sm.get_node_or_null(sm.get("parts_container_path")) if sm and not sm.get("parts_container_path").is_empty() else null
	if not container or container.get_child_count() == 0:
		push_warning("4D dock: import an IFC model first -- there are no parts to read properties from.")
		return
	var dialog := IfcMappingDialog.new()
	add_child(dialog)
	# Parts are already named from Element ID, so that one role is locked.
	dialog.setup(IfcPropertyScanner.scan(container), IfcMapping.load_from(_ifc_mapping_path()), true)
	dialog.mapping_confirmed.connect(func(mapping: IfcMapping):
		mapping.save_to(_ifc_mapping_path())
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _recenter_to_origin() -> void:
	var aabb := AABB()
	var first := true
	for node in _ifc_manager.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)

	if first:
		return

	_ifc_framing_shift = aabb.get_center()
	_ifc_manager.global_position -= _ifc_framing_shift

func _adapt_for_4d_tool(mapping: IfcMapping) -> void:
	var current_scene_root = EditorInterface.get_edited_scene_root()
	var sequence_manager := _find_sequence_manager(current_scene_root)
	var source_file := _ifc_source_path.get_file()
	# Names other models in the scene already use (none without a SequenceManager).
	var taken := IfcSceneModels.taken_part_names(sequence_manager, source_file) if sequence_manager else {}
	var container := GDIFC4DAdapter.adapt(_ifc_manager, mapping, taken)
	_ifc_manager.queue_free()
	_ifc_manager = null

	if not sequence_manager:
		push_warning("4D dock: no SequenceManager found in the open scene -- parented parts under the scene root instead. Add a SequenceManager node and re-import, or move 'IFCParts' under one and set its parts_container_path yourself.")
		current_scene_root.add_child(container, true)
		_own_recursive(container, current_scene_root)
		print("4D dock: imported %d part(s) into '%s'. Save the scene to persist them." % [
			container.get_child_count(), current_scene_root.get_path_to(container)])
		return

	var fresh := GeoOrigin.from_ifc_import(_ifc_import_info, _ifc_framing_shift)
	if not _ifc_import_info.get("map_conversion", {}).is_empty() and _ifc_framing_shift.length() > 100000.0:
		push_warning("4D dock: '%s' loaded at map coordinates although its offset is in IfcMapConversion -- this GDIFC applies the map conversion, so the recorded origin counts it twice. Check the model's position." % source_file)
	var result := IfcSceneModels.attach(sequence_manager, container, fresh, source_file)
	_own_recursive(container, current_scene_root)
	if result.message != "":
		push_warning("4D dock: " + result.message)

	var models := IfcSceneModels.containers(sequence_manager)
	print("4D dock: imported %d part(s) into '%s' (%s%s)%s. Save the scene to persist them." % [
		container.get_child_count(),
		sequence_manager.get_path_to(container),
		"replaced the earlier import, " if result.replaced else "",
		"parts_container_path" if result.role == "primary" else "extra_part_containers",
		"; placed %s relative to the scene's first model, %d models in the scene" % [
			"by the georeference" if result.placement == "map" else "at the origin", models.size()] if models.size() > 1 else ""])
	if models.size() > 1 and models.any(func(c): return not c.has_meta(IfcSceneModels.SOURCE_META)):
		print("4D dock: the scene holds a model imported before 0.5.0 (no source file recorded). If '%s' is a newer version of it, delete the old container and remove it from the SequenceManager." % source_file)
	_store_geo_origin(sequence_manager, result.geo_changed)

## Points the terrain at the (possibly new) primary container and origin, then
## lets the Terreno section act on the import.
func _store_geo_origin(sequence_manager: Node, origin_changed: bool) -> void:
	var geo: GeoOrigin = sequence_manager.get("geo_origin")
	print("4D dock: %s origin %s (%s)." % [
		"model" if origin_changed else "scene keeps its",
		geo.describe(), geo.source if geo.source != "" else "not georeferenced"])
	var terrain = null
	for child in sequence_manager.get_children():
		if child is ConstructionTerrain:
			terrain = child
	if terrain:
		var container = sequence_manager.get_node_or_null(sequence_manager.get("parts_container_path"))
		if container:
			terrain.anchor_path = terrain.get_path_to(container)
		terrain.geo_origin = geo
	if _terrain_panel:
		_terrain_panel.on_ifc_imported()

func _own_recursive(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for child in node.get_children():
		_own_recursive(child, owner)

func _on_generate_schedule_pressed() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		print("No scene is currently open!")
		return

	var sequence_manager := _find_sequence_manager(scene_root)
	if not sequence_manager:
		push_warning("4D dock: no SequenceManager in the open scene -- import an IFC model first.")
		return

	var container := sequence_manager.get_node_or_null(sequence_manager.get("parts_container_path"))
	if not container or container.get_child_count() == 0:
		push_warning("4D dock: SequenceManager.parts_container_path points at nothing (or an empty node) -- import an IFC model first.")
		return

	var json_path: String = sequence_manager.get("construction_json_path")
	var mapping := IfcMapping.load_from(IfcMapping.profile_path_for(json_path))
	if mapping == null or not mapping.is_valid():
		push_warning("4D dock: no complete IFC mapping saved -- press Edit IFC mapping (or re-import the model) and choose the element id and date properties first.")
		return
	# Every model in the scene, not only the primary container.
	var data := IFCScheduleGenerator.generate(
		sequence_manager.collect_part_nodes(), mapping, IFCScheduleGenerator.read_existing(json_path))
	if data.is_empty():
		return
	# generate() recorded what it derived, so a later run can tell a hand-edited type from its own.
	mapping.save_to(IfcMapping.profile_path_for(json_path))

	var err := IFCScheduleGenerator.write_data(data, json_path)
	if err != OK:
		push_error("4D dock: could not write '%s' (error %d)" % [json_path, err])
		return

	print("4D dock: wrote %d action(s) to %s (%d static prefix(es), %d excluded) -- open the 4D TimelineDock and press Start Preview." % [
		data["steps"][0]["actions"].size(), json_path,
		data["static_prefixes"].size(), data["excluded_prefixes"].size()])

# --- Camera keyframes -------------------------------------------------
#
# Authoring a camera track by hand is unusable -- nobody writes a Transform3D
# literal and then reasons about whether it points at the pier. So it's done
# the same way everything else in this dock is: visually, then persisted.
# Scrub to a date, fly the editor's own 3D viewport camera to the shot you
# want, press the button.
#
# Unlike every other control here, this writes to disk immediately rather than
# marking the schedule dirty. camera_track.json is a separate file that
# sequence_data knows nothing about, so it has no part in the dock's
# "mark dirty -> Recalculate -> Save to JSON" cycle; routing it through that
# would mean Save to JSON silently saving two different files.

## Reads wherever the editor viewport camera currently is and appends it as a
## keyframe at the previewed date.
##
## EditorInterface.get_editor_viewport_3d(0).get_camera_3d() is the editor's
## own camera -- the one being flown around with the standard viewport
## controls, which is the whole point: the author already knows how to
## position it, and what they see is exactly what the keyframe records.
func _on_capture_camera_pressed() -> void:
	if not _sequence_manager or not _controller:
		return
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport else null
	if not camera:
		push_warning("Timeline dock: no editor 3D viewport camera found -- open a 3D view and try again.")
		return

	var path: String = _sequence_manager.camera_track_path
	var track := CameraTrack.load_from(path)
	var day: float = _controller.current_day
	# Prefer the date: it's what the schedule is discussed in, and it survives
	# day 0 moving when an earlier action is added. A schedule with no calendar
	# dates at all has nothing to convert against, so the day number is written
	# instead -- CameraTrack accepts either.
	var date := ""
	if _current_schedule and _current_schedule.has_calendar_dates():
		date = _current_schedule.day_to_date_string(day)

	track.add_keyframe(day, date, camera.global_transform, camera.fov,
		"capturado desde el dock")
	track.sort_by_day(_current_schedule)
	var err := track.save_to(path)
	if err != OK:
		push_error("Timeline dock: could not write '%s' (error %d)" % [path, err])
		return
	print("Timeline dock: camera keyframe at %s captured -> %s (%d total)." % [
		date if date != "" else "día %.2f" % day, path, track.keyframes.size()])

# --- CSV Export/Import ------------------------------------------------
#
# The dialog lives here (EditorFileDialog needs a Node to be added as a
# child of); the actual read/write/matching logic is in ScheduleCsvIO
# (_csv_io), which operates on plain Node/Dictionary state so it doesn't need
# to know about this dock's Control tree. Both directions round-trip through
# _sequence_manager.sequence_data in memory, exactly like every other dock
# control: Export writes out sequence_data as it currently stands (including
# unsaved inspector edits), Import writes into sequence_data and marks the
# schedule dirty, same as any single field edit -- Save to JSON / Recalculate
# remain separate, explicit steps.

func _ensure_csv_dialog() -> EditorFileDialog:
	if _csv_dialog:
		return _csv_dialog
	_csv_dialog = EditorFileDialog.new()
	_csv_dialog.add_filter("*.csv", "CSV Files")
	_csv_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_csv_dialog.file_selected.connect(_on_csv_dialog_file_selected)
	add_child(_csv_dialog)
	return _csv_dialog

func _default_csv_path() -> String:
	if not _sequence_manager:
		return "res://schedule.csv"
	var json_path: String = _sequence_manager.construction_json_path
	return json_path.get_basename() + ".csv"

func _on_export_csv_pressed() -> void:
	var dialog := _ensure_csv_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.current_path = _default_csv_path()
	_csv_dialog_mode = "export"
	dialog.popup_centered_ratio()

func _on_import_csv_pressed() -> void:
	var dialog := _ensure_csv_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.current_path = _default_csv_path()
	_csv_dialog_mode = "import"
	dialog.popup_centered_ratio()

func _on_csv_dialog_file_selected(path: String) -> void:
	if _csv_dialog_mode == "export":
		_export_schedule_csv(path)
	elif _csv_dialog_mode == "import":
		_import_schedule_csv(path)
	_csv_dialog_mode = ""

func _export_schedule_csv(path: String) -> void:
	if not _sequence_manager:
		return
	var row_count: int = _csv_io.export_csv(path, _sequence_manager, _current_schedule)
	if row_count < 0:
		return # _csv_io already push_error'd
	print("Timeline dock: exported %d action(s) to %s" % [row_count, path])

func _import_schedule_csv(path: String) -> void:
	if not _sequence_manager:
		return
	var result: Dictionary = _csv_io.import_csv(path, _sequence_manager)
	if result.is_empty():
		return # _csv_io already push_error'd
	_refresh_formwork_bar()
	_refresh_pour_bar()
	_inspector.build(_sequence_manager, _current_schedule)
	_set_schedule_dirty(true)
	print("Timeline dock: imported %d action(s) from CSV (%d skipped, no match)" % [result.updated, result.skipped])

# --- Project XML Export/Import -----------------------------------------
#
# Same split as CSV above: the dialog(s) live here, the actual read/write
# logic is in ScheduleProjectXmlIO (_project_xml_io). Import additionally
# needs a matching step this file owns (not ScheduleProjectXmlIO) -- see
# that class's header comment for why matching a foreign Project file's
# tasks to our action ids is inherently a UI concern.
#
# Matching, in priority order, per task: (1) the persisted mapping file
# (_default_project_mapping_path()) -- a task mapped once, including a
# multi-action phase group via an {anchor_id, terminal_id} pair, never
# prompts again; (2) exact Task Name == an existing action id -- the
# round-trip-our-own-export case, anchor_id == terminal_id; (3) anything
# left over is genuinely new/foreign and needs a human, via
# ProjectXmlMappingDialog. See ScheduleProjectXmlIO's header comment for the
# anchor/terminal design itself (why only the anchor's fields are written,
# and why a terminal mismatch is reported rather than silently corrected).

func _ensure_project_xml_dialog() -> EditorFileDialog:
	if _project_xml_dialog:
		return _project_xml_dialog
	_project_xml_dialog = EditorFileDialog.new()
	_project_xml_dialog.add_filter("*.xml", "Project XML Files")
	_project_xml_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_project_xml_dialog.file_selected.connect(_on_project_xml_dialog_file_selected)
	add_child(_project_xml_dialog)
	return _project_xml_dialog

func _default_project_xml_path() -> String:
	if not _sequence_manager:
		return "res://schedule.xml"
	var json_path: String = _sequence_manager.construction_json_path
	return json_path.get_basename() + ".xml"

## Where the task-name -> {anchor_id, terminal_id} mapping persists across
## imports (see ScheduleProjectXmlIO.load_mapping()/save_mapping()) --
## silent, automatic, no file dialog of its own; this is bookkeeping the
## user should never have to think about, not another artifact to manage.
func _default_project_mapping_path() -> String:
	if not _sequence_manager:
		return "res://schedule.project_mapping.json"
	var json_path: String = _sequence_manager.construction_json_path
	return json_path.get_basename() + ".project_mapping.json"

func _on_export_project_xml_pressed() -> void:
	var dialog := _ensure_project_xml_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.current_path = _default_project_xml_path()
	_project_xml_dialog_mode = "export"
	dialog.popup_centered_ratio()

func _on_import_project_xml_pressed() -> void:
	var dialog := _ensure_project_xml_dialog()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.current_path = _default_project_xml_path()
	_project_xml_dialog_mode = "import"
	dialog.popup_centered_ratio()

func _on_project_xml_dialog_file_selected(path: String) -> void:
	if _project_xml_dialog_mode == "export":
		_export_project_xml(path)
	elif _project_xml_dialog_mode == "import":
		_import_project_xml(path)
	_project_xml_dialog_mode = ""

func _export_project_xml(path: String) -> void:
	if not _sequence_manager:
		return
	var written: int = _project_xml_io.export_xml(path, _sequence_manager, _current_schedule)
	if written < 0:
		return # _project_xml_io already push_error'd
	print("Timeline dock: exported %d action(s) to %s" % [written, path])

## action id -> action Dictionary for every action with a resolvable identity
## -- same lookup ScheduleCsvIO.import_csv() builds internally, duplicated
## here (not shared) since this file has no existing dependency on that
## class and the four lines aren't worth coupling over.
func _actions_by_id() -> Dictionary:
	var by_id: Dictionary = {}
	for step in _sequence_manager.sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var id: String = ConstructionSchedule._action_id(action)
			if id != "":
				by_id[id] = action
	return by_id

## Parses the file, filters out WBS summary rows and null tasks (neither is
## a schedulable unit for us), then resolves each remaining task to an
## {anchor_id, terminal_id} mapping via the persisted mapping file, then
## exact Task Name == action id (anchor_id == terminal_id -- the round-trip-
## our-own-export case), in that order (see this section's header comment).
## Anything still unresolved needs a human, via ProjectXmlMappingDialog. If
## every actionable task resolved without it, applies immediately with no
## dialog at all.
func _import_project_xml(path: String) -> void:
	if not _sequence_manager:
		return
	var tasks: Array = _project_xml_io.parse_xml(path)
	if tasks.is_empty():
		return # _project_xml_io already push_error'd, or the file genuinely has no tasks

	var actions_by_id: Dictionary = _actions_by_id()
	var existing_ids: Array = actions_by_id.keys()
	var persisted: Dictionary = _project_xml_io.load_mapping(_default_project_mapping_path())

	var matched: Dictionary = {} # task_index -> {anchor_id, terminal_id}
	var unmatched: Array = [] # [{task_index, task}]
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		if task.get("summary", false) or task.get("is_null", false):
			continue
		var name: String = task.get("name", "")

		var saved = persisted.get(name)
		if saved is Dictionary and actions_by_id.has(saved.get("anchor_id", "")) and actions_by_id.has(saved.get("terminal_id", "")):
			# A previously-saved mapping whose action(s) still exist -- if
			# either id was since renamed/removed from construction_steps.json,
			# this falls through to re-resolution below instead of silently
			# applying onto a stale/missing action.
			matched[i] = saved
			continue
		if actions_by_id.has(name):
			matched[i] = {"anchor_id": name, "terminal_id": name}
			continue
		unmatched.append({"task_index": i, "task": task})

	if unmatched.is_empty():
		_apply_project_xml_import(tasks, matched)
		return

	_mapping_dialog = ProjectXmlMappingDialog.new()
	_mapping_dialog.setup(unmatched, existing_ids)
	add_child(_mapping_dialog)
	_mapping_dialog.mapping_confirmed.connect(func(manual_mapping: Dictionary):
		for task_index in manual_mapping.keys():
			matched[task_index] = manual_mapping[task_index]
		_apply_project_xml_import(tasks, matched)
		_mapping_dialog.queue_free()
		_mapping_dialog = null
	)
	_mapping_dialog.canceled.connect(func():
		_mapping_dialog.queue_free()
		_mapping_dialog = null
	)
	_mapping_dialog.popup_centered_ratio()

## Applies every matched task onto its anchor action, in one batch, persists
## the full resulting mapping (so none of these tasks ever need
## ProjectXmlMappingDialog again), and reports any anchor/terminal group
## whose computed finish disagrees with the task's own Finish. Only anchors
## can ever resolve as a predecessor for another matched task's
## PredecessorLink (uid_to_action_id is built from `matched`'s anchor_ids
## alone) -- a dependency on a skipped/unmapped task is silently dropped by
## ScheduleProjectXmlIO.apply_task_onto_action(), the same "don't guess,
## just omit" posture CSV import takes for an unresolved depends_on id.
##
## A mismatch check needs an up-to-date ConstructionSchedule (the terminal's
## finish is *computed*, cascading through whatever depends_on/lag_days
## chain sits between anchor and terminal -- it's not a field this function
## writes anywhere), so this forces a real _rebuild_schedule() whenever at
## least one matched entry has anchor_id != terminal_id, rather than just
## marking the schedule dirty and waiting for an explicit Recalculate like
## every other field edit in this dock. Skipped entirely when every matched
## task is the ordinary single-action case (anchor_id == terminal_id),
## preserving the usual "edits are cheap, Recalculate is explicit" behavior.
func _apply_project_xml_import(tasks: Array, matched: Dictionary) -> void:
	var actions_by_id: Dictionary = _actions_by_id()
	var uid_to_action_id: Dictionary = {}
	for task_index in matched.keys():
		uid_to_action_id[tasks[task_index].get("uid", "")] = matched[task_index].anchor_id

	var needs_finish_check: Array = [] # [{task_index, terminal_id}]
	var updated := 0
	for task_index in matched.keys():
		var entry: Dictionary = matched[task_index]
		var anchor_id: String = entry.anchor_id
		var terminal_id: String = entry.terminal_id
		if not actions_by_id.has(anchor_id):
			continue
		_project_xml_io.apply_task_onto_action(actions_by_id[anchor_id], tasks[task_index], uid_to_action_id)
		updated += 1
		if terminal_id != anchor_id:
			needs_finish_check.append({"task_index": task_index, "terminal_id": terminal_id})

	var mismatches: Array = []
	if not needs_finish_check.is_empty():
		_rebuild_schedule()
		for check in needs_finish_check:
			if not _current_schedule:
				continue
			var day_range: Dictionary = _current_schedule.get_action_day_range(check.terminal_id)
			if day_range.is_empty():
				continue
			var task: Dictionary = tasks[check.task_index]
			var computed_finish: String = _current_schedule.day_to_date_string(day_range.finish_day)
			var expected_finish: String = _project_xml_io.task_finish_date(task)
			if expected_finish != "" and computed_finish != expected_finish:
				mismatches.append("'%s': computed finish %s vs Project's Finish %s" % [task.get("name", "?"), computed_finish, expected_finish])

	_refresh_formwork_bar()
	_refresh_pour_bar()
	_inspector.build(_sequence_manager, _current_schedule)
	_set_schedule_dirty(needs_finish_check.is_empty())

	var mapping_path: String = _default_project_mapping_path()
	var persisted: Dictionary = _project_xml_io.load_mapping(mapping_path)
	for task_index in matched.keys():
		var name: String = tasks[task_index].get("name", "")
		if name != "":
			persisted[name] = matched[task_index]
	_project_xml_io.save_mapping(mapping_path, persisted)

	print("Timeline dock: imported %d action(s) from Project XML" % updated)
	if not mismatches.is_empty():
		print("Timeline dock: %d finish mismatch(es) -- phase template or Project estimate may need a look:" % mismatches.size())
		for m in mismatches:
			print("  - %s" % m)
