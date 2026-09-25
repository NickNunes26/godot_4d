## Draws red zones over TimelineUI's slider marking collision windows found by
## TimelineController.scan_collisions(). Sits as a full-rect sibling of the
## HSlider inside a small wrapper Control (see timeline_ui.tscn's
## "SliderStack") -- mouse_filter is IGNORE so it's completely transparent to
## input and can never interfere with dragging the slider underneath. (An
## earlier version used PASS to also support a hover tooltip, but that still
## intercepted the slider's drag-start.)
##
## The hover tooltip (TimelineUI._update_hover_tooltip()) doesn't need PASS:
## it reads the mouse position via get_local_mouse_position(), a pure
## coordinate conversion that works regardless of mouse_filter since it's not
## an input event, and calls find_window_at() below to hit-test using the
## exact same pixel math _draw() uses -- so the hoverable zone always matches
## what's visibly drawn.
## @tool: this is a child node inside timeline_ui.tscn, which the Phase 3
## editor dock (addons/construction_4d_tool) instantiates directly in the
## editor process. Without @tool, Godot substitutes an inert placeholder for
## this script there and every access to `windows`/etc. from timeline_ui.gd
## fails (see sequence_manager.gd's doc comment for the same underlying
## placeholder-instance issue). _ready() only sets mouse_filter, so there's
## no runtime-only side effect to guard against running in-editor.
@tool
class_name CollisionOverlay
extends Control

var windows: Array = [] # [{part1, part2, start_day, end_day}, ...]
var min_day: float = 0.0
var max_day: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_range(new_min_day: float, new_max_day: float) -> void:
	min_day = new_min_day
	max_day = new_max_day
	queue_redraw()

func set_windows(new_windows: Array) -> void:
	windows = new_windows
	queue_redraw()

func _draw() -> void:
	var span = max_day - min_day
	if span <= 0.0:
		return
	for w in windows:
		var rect = _window_rect(w, span)
		draw_rect(rect, Color(1.0, 0.2, 0.2, 0.55))

## Returns the window dict whose drawn red-zone rect contains local_x (this
## control's local coordinate space), or {} if none -- shared with _draw()'s
## pixel math so the hover hit-zone always matches what's visibly painted.
func find_window_at(local_x: float) -> Dictionary:
	var span = max_day - min_day
	if span <= 0.0:
		return {}
	for w in windows:
		var rect = _window_rect(w, span)
		if local_x >= rect.position.x and local_x <= rect.position.x + rect.size.x:
			return w
	return {}

func _window_rect(w: Dictionary, span: float) -> Rect2:
	var x_start = ((w.start_day - min_day) / span) * size.x
	var x_end = ((w.end_day - min_day) / span) * size.x
	var width = maxf(x_end - x_start, 3.0)
	return Rect2(x_start, 0.0, width, size.y)
