## EditorPlugin entry point for the 4D construction tool's Phase 3 dock.
## Deliberately thin: all real logic lives in timeline_dock.gd, which wraps
## the same Phase 1/2 classes (ConstructionSchedule, TimelineController,
## AnimationApplier, SpatialGrouper) used at runtime, unmodified -- this
## dock is a new front-end, not a core rewrite (see
## addons/construction_4d_tool/docs/01_ARCHITECTURE.md, "Extensibility for
## Phases 2-4").
@tool
extends EditorPlugin

const TimelineDockScene = preload("res://addons/construction_4d_tool/editor/timeline_dock.tscn")

var _dock: Control = null

func _enter_tree() -> void:
	_dock = TimelineDockScene.instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)

func _exit_tree() -> void:
	if not _dock:
		return
	# Restore any live-previewed scene state before the dock (and its
	# TimelineController/TimelineUI children) are torn down -- otherwise
	# disabling the plugin mid-preview would leave the edited scene mutated.
	if _dock.has_method("stop_preview"):
		_dock.stop_preview()
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
