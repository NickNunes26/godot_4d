## Runtime timeline UI: slider, Play/Pause, speed control, date label, Reset.
## Talks only to TimelineController (never to ConstructionSchedule/parts
## directly), so a future EditorPlugin dock can reuse this same script.
## @tool: reused as-is inside the Phase 3 editor dock (addons/construction_4d_tool)
## for live in-editor scrubbing. No runtime behavior change.
@tool
class_name TimelineUI
extends Control

@onready var _date_label: Label = $VBoxContainer/DateLabel
@onready var _collision_label: Label = $VBoxContainer/CollisionWarningLabel
@onready var _slider: HSlider = $VBoxContainer/HBoxContainer/SliderStack/Slider
@onready var _collision_overlay: CollisionOverlay = $VBoxContainer/HBoxContainer/SliderStack/CollisionOverlay
@onready var _play_button: Button = $VBoxContainer/HBoxContainer/PlayButton
@onready var _speed_spinbox: SpinBox = $VBoxContainer/HBoxContainer/SpeedSpinBox
@onready var _reset_button: Button = $VBoxContainer/HBoxContainer/ResetButton
@onready var _scan_button: Button = $VBoxContainer/HBoxContainer/ScanCollisionsButton
@onready var _hover_tooltip: PanelContainer = $HoverTooltip
@onready var _hover_tooltip_label: Label = $HoverTooltip/HoverTooltipLabel

var _timeline_controller: TimelineController = null
var _schedule: ConstructionSchedule = null
# Runs one automatic scan on the first _process() frame after wiring (not
# during set_timeline_controller()/_ready() directly -- the physics space
# backing get_collisions() needs at least one frame to be queryable, and
# ConstructionSchedule.get_collisions() already fails safe (returns []) if
# queried too early, so a same-frame scan could silently find nothing).
var _auto_scanned: bool = false

func _ready() -> void:
	_slider.value_changed.connect(_on_slider_changed)
	_play_button.pressed.connect(_on_play_pressed)
	_speed_spinbox.value_changed.connect(_on_speed_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_scan_button.pressed.connect(_on_scan_pressed)

## Wires the UI to a controller/schedule and sizes the slider to the
## schedule's date range. Call once after TimelineController.set_schedule().
func set_timeline_controller(controller: TimelineController, schedule: ConstructionSchedule) -> void:
	_timeline_controller = controller
	_schedule = schedule
	var date_range = schedule.get_date_range()
	_slider.min_value = date_range.min_day
	_slider.max_value = date_range.max_day
	_slider.value = date_range.min_day
	_collision_overlay.set_range(date_range.min_day, date_range.max_day)
	_update_display()

func _on_slider_changed(value: float) -> void:
	if _timeline_controller:
		_timeline_controller.pause()
		_timeline_controller.scrub_to(value)
		_update_button_text()
		_update_display()

func _on_play_pressed() -> void:
	if _timeline_controller:
		if _timeline_controller.is_playing:
			_timeline_controller.pause()
		else:
			_timeline_controller.play()
		_update_button_text()

func _on_speed_changed(value: float) -> void:
	if _timeline_controller:
		_timeline_controller.set_speed(value)

func _on_reset_pressed() -> void:
	if _timeline_controller:
		_timeline_controller.reset()
		_update_button_text()
		_update_display()

## Scans the full schedule for collisions, prints a summary to the console,
## and paints red zones + hover tooltips on the slider via CollisionOverlay --
## the timeline briefly steps through every day while scanning (silent to
## current_day/is_playing) and lands back where it started.
func _on_scan_pressed() -> void:
	_run_scan()

func _run_scan() -> void:
	if not _timeline_controller:
		return
	_scan_button.disabled = true
	var windows = _timeline_controller.scan_collisions()
	_scan_button.disabled = false
	_collision_overlay.set_windows(windows)
	_print_collision_report(windows)
	_update_display()

func _print_collision_report(windows: Array) -> void:
	if windows.is_empty():
		print("Collision scan: no collisions found across the full schedule.")
		return
	print("Collision scan: %d collision window(s) found:" % windows.size())
	for w in windows:
		print("  %s" % _describe_window(w))

func _process(_delta: float) -> void:
	if _timeline_controller:
		if not _auto_scanned:
			_auto_scanned = true
			_run_scan()
		# Must use set_value_no_signal(): a plain `_slider.value = ...` emits
		# value_changed, which routes to _on_slider_changed -> pause(), so
		# playback would self-pause one frame after pressing Play.
		_slider.set_value_no_signal(_timeline_controller.current_day)
		_update_display()
		_update_button_text()
	_update_hover_tooltip()

func _update_button_text() -> void:
	if _timeline_controller.collision_paused:
		_play_button.text = "Play (blocked)"
	else:
		_play_button.text = "Pause" if _timeline_controller.is_playing else "Play"

func _update_display() -> void:
	if not _timeline_controller:
		return
	_date_label.text = _format_day(_timeline_controller.current_day)

	# Phase 2: live collision warning at the current day, recomputed every
	# display update. Distinct from CollisionOverlay's red zones, which come
	# from an explicit full-schedule scan_collisions() scan (see
	# _on_scan_pressed()), not from this point-in-time check.
	var collisions = _timeline_controller.get_collisions()
	_collision_label.visible = collisions.size() > 0
	if collisions.size() > 0:
		var suffix = " — playback paused" if _timeline_controller.collision_paused else ""
		_collision_label.text = "⚠ %d collision(s): %s%s" % [collisions.size(), _describe_collision(collisions[0]), suffix]

func _describe_collision(collision: Dictionary) -> String:
	return "%s ↔ %s" % [collision.part1, collision.part2]

## Phase 2: hover tooltip over the slider's red collision zones. Reads the
## mouse position purely via get_local_mouse_position() (a coordinate
## conversion, not an input event) so it never needs to change
## CollisionOverlay's mouse_filter -- the overlay stays fully IGNORE and can
## never intercept the slider's drag-start (see collision_overlay.gd; an
## earlier PASS-based attempt broke dragging for exactly that reason).
func _update_hover_tooltip() -> void:
	if not _collision_overlay or _collision_overlay.windows.is_empty():
		_hover_tooltip.visible = false
		return
	var local_pos = _collision_overlay.get_local_mouse_position()
	# Small vertical padding so the tooltip is forgiving to hover near the
	# thin slider bar, not just exactly on its pixel row.
	if local_pos.x < 0.0 or local_pos.x > _collision_overlay.size.x \
			or local_pos.y < -12.0 or local_pos.y > _collision_overlay.size.y + 12.0:
		_hover_tooltip.visible = false
		return
	var hit = _collision_overlay.find_window_at(local_pos.x)
	if hit.is_empty():
		_hover_tooltip.visible = false
		return
	_hover_tooltip_label.text = _describe_window(hit)
	_hover_tooltip.visible = true
	_hover_tooltip.global_position = get_global_mouse_position() + Vector2(12.0, -32.0)

func _describe_window(w: Dictionary) -> String:
	if w.start_day == w.end_day:
		return "%s: %s ↔ %s" % [_day_label(w.start_day), w.part1, w.part2]
	return "%s – %s: %s ↔ %s" % [_day_label(w.start_day), _day_label(w.end_day), w.part1, w.part2]

## Spanish weekday/month abbreviations, matching the cosmetic-Spanish
## convention the Phase 3 inspector already uses for its type/anchor dropdowns
## and column headers. Time.get_datetime_dict_from_unix_time()'s `weekday` is
## 0=Sunday..6=Saturday, and `month` is 1-based -- hence the leading "" pad.
const _WEEKDAYS_ES: Array = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
const _MONTHS_ES: Array = ["", "ene", "feb", "mar", "abr", "may", "jun",
	"jul", "ago", "sep", "oct", "nov", "dic"]


## The scrubber's main label: a real calendar date rather than a relative day
## count. The day number is kept as a secondary detail because the collision
## scan report and slider overlay still speak in days.
##
## Falls back to the bare day count when the schedule carries no real dates
## (has_calendar_dates() false) -- day 0 would otherwise render as 1970.
func _format_day(day_num: float) -> String:
	if not _schedule or not _schedule.has_calendar_dates():
		return "Day %.1f" % day_num
	return "%s · día %.1f" % [_format_date(day_num), day_num]


## "mar 14/abr/2026" for a relative day number. Weekday included deliberately:
## it makes weekend work visible at a glance, which matters when the model's
## own duration fields count working days while this timeline counts
## calendar days (see 05_IFC_INTEGRATION.md).
func _format_date(day_num: float) -> String:
	if not _schedule or not _schedule.has_calendar_dates():
		return ""
	var epoch := _schedule.day_to_epoch(day_num)
	if is_nan(epoch) or is_inf(epoch):
		return ""
	var d := Time.get_datetime_dict_from_unix_time(int(epoch))
	return "%s %02d/%s/%d" % [_WEEKDAYS_ES[d.weekday], d.day, _MONTHS_ES[d.month], d.year]


## Renders a day number for the collision report/tooltip: the calendar date
## when one is available, always with the raw day in parentheses, since
## scan_collisions() samples at 0.01-day granularity and two windows on the
## same calendar date are otherwise indistinguishable.
func _day_label(day_num: float) -> String:
	if not _schedule or not _schedule.has_calendar_dates():
		return "Day %.2f" % day_num
	return "%s (%.2f)" % [_format_date(day_num), day_num]
