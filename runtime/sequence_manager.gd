## Scene root script: orchestrates the 4D tool. Loads construction_steps.json,
## registers/preps building_parts, builds a ConstructionSchedule, and mounts
## a TimelineController + TimelineUI. Expects a child holding the model's
## parts at parts_container_path (no default -- it must be set per scene; the
## IFC import in the editor dock sets it for you) and (optionally) any number of
## Crane-scripted nodes anywhere in the scene, auto-discovered by
## _resolve_cranes() -- see its doc comment, and crane_paths below for the
## explicit-override escape hatch.
## @tool: lets the Phase 3 editor dock (addons/construction_4d_tool) call
## load_json()/initialize_parts() on this node directly -- without @tool,
## Godot substitutes an inert placeholder for any script attached to a node
## in the currently edited scene, and every method call on it fails (see
## timeline_dock.gd's start_preview()). _ready() is guarded with
## Engine.is_editor_hint() so this doesn't also make the full runtime setup
## (formwork generation, hiding/zero-scaling every part, mounting a
## TimelineController/TimelineUI/CollisionVisualizer) fire just from opening
## the scene in the editor -- that side-effecting setup must only happen at
## actual Play/export runtime, or via the dock's explicit Start Preview
## button, never as a side effect of the scene merely being open for editing.
@tool
extends Node3D

var sequence_data = {}
var building_parts = {}
var _spatial_grouper = SpatialGrouper.new()
# crane name -> Crane, resolved by _resolve_cranes(). Multi-crane: any number
# of Crane-scripted nodes anywhere in the scene are found automatically (see
# _resolve_cranes()'s doc comment) -- which crane services which install unit
# is then ConstructionSchedule's decision (nearest-by-distance, or an
# action's explicit crane_id), not this file's.
var _cranes: Dictionary = {}
var _timeline_controller: TimelineController = null

@export var construction_json_path: String = "res://construction_steps.json"
## Name/path of the child node holding the model's parts, relative to this
## node. **Required, no default**: point it at whatever node holds your model's
## parts (a `.glb`'s root group, the `IFCParts` node from an IFC import, ...).
## Left empty, the tool reports a clear error instead of guessing.
@export var parts_container_path: NodePath = NodePath()
## Optional further nodes whose children are also parts (e.g. site props or
## safety elements that live outside the main model), relative to this node.
@export var extra_part_containers: Array[NodePath] = []
## Optional explicit override for which crane(s) to use -- leave empty (the
## default) to auto-discover every Crane-scripted node in the scene instead
## (see _resolve_cranes()). Only needed if auto-discovery would pick up a
## node that shouldn't be wired in (e.g. a decorative/preview crane prop) or
## if explicit control over exactly which nodes count is wanted.
@export var crane_paths: Array[NodePath] = []

@export_group("Movie Maker Mode")
## Forces movie mode on without actually recording. Movie mode is normally
## detected automatically (see movie_mode below), which means the only way to
## see what a recording will do is to record one -- slow, and it writes a file
## every time. Turn this on to run the same start-to-finish, no-UI,
## no-clash-gate playback in a plain Play session.
@export var movie_mode_override: bool = false
## How long day 0 -> last day should take, in seconds. The finished video is
## this plus movie_end_hold_sec.
##
## Playback speed is derived from this and the schedule's own length, rather
## than reusing the interactive speed spinbox: "how long is the video" is the
## question anyone recording one is actually asking, and days-per-second
## answers it only after arithmetic that changes every time the schedule does.
## A target the speed range can't reach is warned about, not silently
## delivered as a different length -- see _resolve_movie_speed().
@export var movie_duration_sec: float = 60.0
## Seconds to hold on the finished structure before quitting. A hard cut on the
## frame the last part lands reads as a truncated export rather than an ending.
@export var movie_end_hold_sec: float = 2.0
## Optional camera keyframe track (see CameraTrack). Applied in movie mode
## only; with no file, or a file with no keyframes, the camera stays exactly
## where the scene put it. Authored with the Phase 3 dock's "Capturar cámara"
## button -- its own file, so regenerating the schedule can't destroy it.
@export var camera_track_path: String = "res://camera_track.json"

## True when this run is producing a video: either Godot was launched in Movie
## Maker Mode (Engine.get_write_movie_path() returns the output path, and "" in
## every other case -- verified against 4.6.2) or movie_mode_override is set.
##
## Resolved once, here, and handed to whatever needs it rather than having each
## subsystem query Engine for itself -- that is what makes the override work at
## all, and it keeps "are we recording?" a single answer per run.
var movie_mode: bool = false

## Identity of the free-fly camera script, matched the same way _resolve_cranes()
## matches cranes -- by script, not by node name or a fixed path.
const _FREE_LOOK_SCRIPT := preload("res://addons/construction_4d_tool/runtime/free_look_camera.gd")

var _movie_date_label: Label = null
var _schedule: ConstructionSchedule = null

func _ready():
	if Engine.is_editor_hint():
		return
	movie_mode = movie_mode_override or Engine.get_write_movie_path() != ""
	load_json()
	_generate_formwork()
	initialize_parts()
	_cranes = _resolve_cranes()
	if _cranes.is_empty():
		push_warning("SequenceManager: no crane found in the scene")

	_schedule = ConstructionSchedule.new(sequence_data, building_parts, _spatial_grouper, _cranes)

	_timeline_controller = TimelineController.new()
	add_child(_timeline_controller)
	_timeline_controller.set_schedule(_schedule, building_parts, _cranes)
	_timeline_controller.pour_stream = AnimationApplier.pour_stream_config(sequence_data)

	if movie_mode:
		_start_movie_run(_schedule)
		return

	var ui = preload("res://addons/construction_4d_tool/runtime/timeline_ui.tscn").instantiate() as TimelineUI
	add_child(ui)
	ui.set_timeline_controller(_timeline_controller, _schedule)

	var collision_visualizer = CollisionVisualizer.new()
	add_child(collision_visualizer)
	collision_visualizer.set_timeline_controller(_timeline_controller)

## Configures and starts a recording run.
##
## Neither TimelineUI nor CollisionVisualizer is created at all, rather than
## created and hidden. Both are invisible either way, but both also do real
## per-frame work that a recording has no use for and would pay for on every
## written frame: TimelineUI._update_display() runs a live get_collisions()
## query every frame, CollisionVisualizer does the same to place its markers,
## and TimelineUI's first frame kicks off a full-schedule collision scan that
## teleports every part through the entire date range. Not building them is a
## simpler way to say "no UI in frame" than building them and switching all of
## that off from the inside.
func _start_movie_run(schedule: ConstructionSchedule) -> void:
	_resolve_movie_speed(schedule)
	_disable_free_look()
	_start_camera_track(schedule)
	var date_range = schedule.get_date_range()
	var span: float = date_range.max_day - date_range.min_day
	# Reports the length this run will actually produce, derived back out of
	# the speed that was actually set -- not movie_duration_sec, which
	# _resolve_movie_speed() may have been unable to honor.
	var actual_sec: float = (span / _timeline_controller.playback_speed) + movie_end_hold_sec
	print("Movie mode: %s. %.1f day(s) at %.2f day(s)/sec -> ~%.1fs of video (incl. %.1fs end hold)." % [
		"recording to '%s'" % Engine.get_write_movie_path() if Engine.get_write_movie_path() != "" else "override, not recording",
		span, _timeline_controller.playback_speed, actual_sec, movie_end_hold_sec])
	
	# Instantiate movie date label
	var canvas = CanvasLayer.new()
	_movie_date_label = Label.new()
	_movie_date_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_movie_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_movie_date_label.add_theme_font_size_override("font_size", 32)
	_movie_date_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_movie_date_label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(_movie_date_label)
	add_child(canvas)

	_timeline_controller.begin_movie_run(movie_end_hold_sec)

func _process(delta: float) -> void:
	if movie_mode and _movie_date_label and _timeline_controller and _schedule:
		var day = _timeline_controller.current_day
		_movie_date_label.text = _schedule.day_to_date_string(day) if _schedule.has_calendar_dates() else "Day " + str(int(day))

## Turns "I want a 60-second video" into days-per-second. set_speed() clamps to
## [0.1, 10.0] -- a sane range for the interactive spinbox that a target length
## can easily fall outside of -- so the resulting length is checked against the
## requested one and any difference is reported rather than silently delivered.
func _resolve_movie_speed(schedule: ConstructionSchedule) -> void:
	var date_range = schedule.get_date_range()
	var span: float = date_range.max_day - date_range.min_day
	var target: float = maxf(movie_duration_sec, 0.1)
	if span <= 0.0:
		return # single-instant schedule: speed is irrelevant, it's already over
	var wanted: float = span / target
	_timeline_controller.set_speed(wanted)
	if not is_equal_approx(_timeline_controller.playback_speed, wanted):
		push_warning("SequenceManager: a %.1fs video of a %.1f-day schedule needs %.2f day(s)/sec, outside the supported [0.1, 10.0] -- the video will be about %.1fs instead." % [
			target, span, wanted, span / _timeline_controller.playback_speed])

## Mounts a CameraDriver when a camera track exists, so the recording moves
## through the authored shots instead of sitting on the scene's one fixed
## viewpoint. Absent or empty track: nothing is created and the camera stays
## exactly where the scene put it -- movie mode has to keep working for anyone
## who never authored a track.
##
## Runs after _disable_free_look(), which is what frees the camera up: the
## driver writes global_transform every frame, so free-fly reading input at the
## same time would be two things steering one node.
func _start_camera_track(schedule: ConstructionSchedule) -> void:
	var track := CameraTrack.load_from(camera_track_path)
	track.resolve(schedule)
	if track.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		push_warning("SequenceManager: a camera track is present but the scene has no active Camera3D -- not applied.")
		return
	var driver := CameraDriver.new()
	add_child(driver)
	driver.setup(track, _timeline_controller, camera)
	print("Movie mode: driving '%s' from %d camera keyframe(s) in %s." % [
		camera.name, track.size(), camera_track_path])

## Movie mode takes the camera away from the keyboard: a recording must not be
## steerable by a stray keypress, and feature 5 (camera keyframes) will drive
## this same Camera3D. Interactive runs are untouched -- free-fly is how
## clashes get inspected.
func _disable_free_look() -> void:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	var cameras: Array = []
	_find_free_look_cameras(scene_root, cameras)
	for camera in cameras:
		camera.set_process(false)
		camera.set_process_unhandled_input(false)
	if not cameras.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _find_free_look_cameras(node: Node, out: Array) -> void:
	if node.get_script() == _FREE_LOOK_SCRIPT:
		out.append(node)
	for child in node.get_children():
		_find_free_look_cameras(child, out)

func load_json():
	var file = FileAccess.open(construction_json_path, FileAccess.READ)
	if file:
		var json = JSON.new()
		json.parse(file.get_as_text())
		sequence_data = json.get_data()

## Resolves every crane this scene should drive, keyed by node name (the
## same name an action's optional crane_id field would reference). If
## crane_paths is explicitly set, only those exact nodes are used (each
## missing/wrong-type entry warned about individually, not silently
## dropped). Otherwise auto-discovers every node running crane.gd anywhere
## in the current scene -- script-identity match, not node name or a fixed
## relative path, the same pattern TimelineDock._find_sequence_manager()
## uses to locate its own target -- so any number of cranes, placed anywhere
## in the scene, are found with zero configuration. Two cranes sharing a
## name would collide in this Dictionary (last one found wins); scenes
## should give each crane a distinct name, same expectation building parts
## already have via their prefixes.
func _resolve_cranes() -> Dictionary:
	var cranes: Dictionary = {}
	if not crane_paths.is_empty():
		for path in crane_paths:
			var node = get_node_or_null(path)
			if node is Crane:
				cranes[node.name] = node
			else:
				push_warning("SequenceManager: no Crane found at '%s'" % path)
		return cranes

	_find_all_cranes(get_tree().current_scene, cranes)
	return cranes

func _find_all_cranes(node: Node, out: Dictionary) -> void:
	if node is Crane:
		out[node.name] = node
	for child in node.get_children():
		_find_all_cranes(child, out)

## Every node that counts as a part: the children of parts_container_path plus
## the children of each extra_part_containers entry. Read-only, so the editor
## dock can call it to see what a preview is about to touch.
func collect_part_nodes() -> Array:
	var parts: Array = []
	var container = _parts_container()
	if container:
		parts.append_array(container.get_children())
	for path in extra_part_containers:
		var extra = get_node_or_null(path)
		if extra:
			parts.append_array(extra.get_children())
		else:
			push_warning("SequenceManager: no node found at extra_part_containers entry '%s'" % path)
	return parts

## Resolves parts_container_path, warning once (not failing -- the rest of
## _ready() still needs to run, e.g. cranes/UI, even for a scene that's
## missing/misconfigured this) if nothing is found there.
func _parts_container() -> Node:
	if parts_container_path.is_empty():
		push_error("SequenceManager: parts_container_path is not set -- select this node and point it at the node that holds your model's parts.")
		return null
	var container = get_node_or_null(parts_container_path)
	if not container:
		push_warning("SequenceManager: no parts container found at '%s' -- check parts_container_path" % parts_container_path)
	return container

## Registers every part and puts the scene into its day-0 state.
##
## Three categories, decided by the two root-level prefix lists in
## construction_steps.json (see _prefix_list()):
##
## - **excluded** (`excluded_prefixes`): hidden for the entire run and *not*
##   registered in building_parts at all, so no action can match it, no
##   collision shape is built for it, and it never appears in a schedule.
##   Deliberately not freed -- the node stays in the scene, so the decision is
##   reversible by editing one JSON list rather than by re-importing the model.
## - **static** (`static_prefixes`): registered like any other part but never
##   hidden, so it is present from the first frame and stays put forever. This
##   is what the generator's old placeholder `contexto_*` actions were faking;
##   expressing it directly means unscheduled geometry stops occupying rows in
##   a work schedule it isn't part of. It still gets collision shapes -- a
##   permanently-present footing should absolutely still flag a clash against
##   an in-transit beam, and CollisionQuery only treats in-transit parts as
##   movers, so static geometry participates as a target only.
## - **everything else**: hidden and zero-scaled, as before, waiting for its
##   action to animate it in.
##
## building_parts is cleared first: this runs again on every Start Preview, and
## a part that has since been excluded must actually disappear from the
## registry rather than linger from the previous run.
func initialize_parts():
	var all_parts := collect_part_nodes()

	building_parts.clear()
	var static_prefixes := _prefix_list("static_prefixes")
	var excluded_prefixes := _prefix_list("excluded_prefixes")
	var matched: Dictionary = {} # prefix -> true, for the unused-prefix warning below

	for child in all_parts:
		var part_name := String(child.name)
		var excluded_by := _matching_prefix(part_name, excluded_prefixes, matched)
		var static_by := _matching_prefix(part_name, static_prefixes, matched)

		if excluded_by != "":
			if static_by != "":
				push_warning("SequenceManager: '%s' matches both excluded_prefixes '%s' and static_prefixes '%s' -- excluded wins" % [part_name, excluded_by, static_by])
			child.visible = false
			continue

		building_parts[part_name] = child
		# Restore before capturing. This function runs again on every Start
		# Preview, and it *mutates* what it is about to read: a second run
		# would otherwise record the first run's hidden, zero-scaled state as
		# the part's "original" and hand that to every later restore. It shows
		# up the moment a part is added to static_prefixes and the lists are
		# re-applied -- the part correctly stops being hidden, and is still
		# scaled to nothing. Restoring first makes initialize_parts()
		# idempotent, so re-running it is always safe.
		if child.has_meta("original_pos"):
			child.position = child.get_meta("original_pos")
		if child.has_meta("original_scale"):
			child.scale = child.get_meta("original_scale")

		child.set_meta("original_pos", child.position)
		child.set_meta("original_scale", child.scale)
		child.set_meta("original_transform", child.global_transform)  # stored before scale is zeroed
		if child is MeshInstance3D and child.mesh:
			child.set_meta("original_aabb", child.mesh.get_aabb())
		make_materials_unique(child)

		if static_by != "":
			child.visible = true
			continue

		child.visible = false
		child.scale = Vector3.ZERO

	_warn_unused_prefixes("static_prefixes", static_prefixes, matched)
	_warn_unused_prefixes("excluded_prefixes", excluded_prefixes, matched)

## One of construction_steps.json's two root-level geometry lists, siblings of
## "steps". They live at the root rather than as a flag on each action because
## they describe *geometry*, not *work*: an excluded part has no dates, no
## duration and no dependencies, so modelling it as an action would force every
## consumer (CSV export, Project XML export, the topological sort) to
## special-case a row that isn't a task. Keeping them out of "steps" means
## those subsystems need no changes at all.
##
## A missing key is simply an empty list, so every pre-existing JSON keeps
## behaving exactly as it did. Empty-string entries are dropped with a warning:
## begins_with("") matches every part, which would silently make the entire
## model static or excluded.
func _prefix_list(key: String) -> Array:
	var raw = sequence_data.get(key, [])
	if not (raw is Array):
		push_warning("SequenceManager: '%s' in the schedule JSON is not an array, ignoring" % key)
		return []
	var out: Array = []
	for entry in raw:
		var prefix := String(entry).strip_edges()
		if prefix.is_empty():
			push_warning("SequenceManager: ignoring an empty entry in '%s' -- it would match every part in the scene" % key)
			continue
		out.append(prefix)
	return out

## The first prefix in `prefixes` that `part_name` starts with, or "" for no
## match. Records the hit in `matched` so _warn_unused_prefixes() can report
## the ones that never matched anything.
func _matching_prefix(part_name: String, prefixes: Array, matched: Dictionary) -> String:
	for prefix in prefixes:
		if part_name.begins_with(prefix):
			matched[prefix] = true
			return prefix
	return ""

## A prefix matching nothing is almost always a typo or a stale entry left
## behind by a model revision -- and it fails silently, which is exactly the
## problem this feature exists to fix for actions. Warned rather than errored:
## a list carrying one dead entry should still apply its other entries.
func _warn_unused_prefixes(key: String, prefixes: Array, matched: Dictionary) -> void:
	for prefix in prefixes:
		if not matched.has(prefix):
			push_warning("SequenceManager: '%s' in %s matches no part in the scene" % [prefix, key])

## Gives a part its own copy of every material it draws with, so fading one
## part never fades another that happens to share a source material.
##
## Recurses into descendant MeshInstance3Ds when the part itself isn't one --
## a composite part (a .glb instance, e.g. a formwork tier-2 panel asset) is a
## Node3D with mesh children, and every placement of the same asset would
## otherwise share one material and fade in unison. Matches
## AnimationApplier._fade_targets(), which picks the same set of nodes on the
## other side of this. See 07_FORMWORK.md, decision 7.
func make_materials_unique(node: Node) -> void:
	var mesh_nodes: Array = [node] if node is MeshInstance3D else node.find_children("*", "MeshInstance3D", true, false)
	for mesh_instance in mesh_nodes:
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat = mesh_instance.get_active_material(i)
			if mat:
				mesh_instance.set_surface_override_material(i, mat.duplicate())

## Builds formwork geometry for the actions that ask for it, before
## initialize_parts() registers everything (see FormworkBuilder.build()).
##
## Safe to call repeatedly -- the builder sweeps its own previous output first.
## That is load-bearing: formwork has to work in the dock preview, which
## re-runs setup on every Start Preview.
func _generate_formwork() -> void:
	var container = _parts_container()
	if not container:
		return
	var created := FormworkBuilder.build(sequence_data, container)
	if created > 0:
		print("SequenceManager: generated %d formwork panel(s)." % created)

func _get_local_aabb(node: Node3D) -> AABB:
	if node is MeshInstance3D and node.mesh:
		return node.mesh.get_aabb()
	
	var min_pt = Vector3(INF, INF, INF)
	var max_pt = Vector3(-INF, -INF, -INF)
	var has_mesh = false
	
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and child.mesh:
			has_mesh = true
			var child_aabb = child.mesh.get_aabb()
			var local_tf = node.global_transform.affine_inverse() * child.global_transform
			var corners = [
				local_tf * Vector3(child_aabb.position.x, child_aabb.position.y, child_aabb.position.z),
				local_tf * Vector3(child_aabb.position.x, child_aabb.position.y, child_aabb.end.z),
				local_tf * Vector3(child_aabb.position.x, child_aabb.end.y, child_aabb.position.z),
				local_tf * Vector3(child_aabb.position.x, child_aabb.end.y, child_aabb.end.z),
				local_tf * Vector3(child_aabb.end.x, child_aabb.position.y, child_aabb.position.z),
				local_tf * Vector3(child_aabb.end.x, child_aabb.position.y, child_aabb.end.z),
				local_tf * Vector3(child_aabb.end.x, child_aabb.end.y, child_aabb.position.z),
				local_tf * Vector3(child_aabb.end.x, child_aabb.end.y, child_aabb.end.z)
			]
			for pt in corners:
				min_pt.x = minf(min_pt.x, pt.x)
				min_pt.y = minf(min_pt.y, pt.y)
				min_pt.z = minf(min_pt.z, pt.z)
				max_pt.x = maxf(max_pt.x, pt.x)
				max_pt.y = maxf(max_pt.y, pt.y)
				max_pt.z = maxf(max_pt.z, pt.z)
				
	if has_mesh:
		return AABB(min_pt, max_pt - min_pt)
	return AABB()
