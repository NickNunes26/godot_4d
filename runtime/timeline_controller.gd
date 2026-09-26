## Virtual clock + playback state machine. Owns current_day and is the only
## thing that changes part state -- both manual scrubbing (via a UI slider)
## and forward Play route through scrub_to(), so the two can never visually
## diverge (see 01_ARCHITECTURE.md, "Single Source of Truth").
## @tool: lets the Phase 3 editor dock (addons/construction_4d_tool) drive
## _process() for live in-editor scrubbing/playback. No runtime behavior
## change -- @tool scripts run identically in Play/exported builds.
@tool
class_name TimelineController
extends Node

var current_day: float = 0.0
var is_playing: bool = false
var playback_speed: float = 1.0  # days per second
## True when playback most recently stopped because _process() detected a
## live collision (Phase 2 safety gate), as opposed to a manual pause() or
## reaching the end of the date range. Cleared by scrub_to() (so any
## deliberate scrub/reset/manual-pause action clears it) and re-set true by
## _process() the instant it auto-pauses for a collision. UI-facing: lets
## TimelineUI show "blocked by collision" distinctly from an ordinary pause.
var collision_paused: bool = false

## Movie Maker Mode: set once by SequenceManager via begin_movie_run(), never
## by the Phase 3 dock (which must never quit the editor -- see
## _tick_movie_end_hold()). Two behaviour changes only, both about the
## *reaction* to a collision rather than the query: the pause-on-collision gate
## in _process() is bypassed, and reaching the end of the schedule quits the
## app instead of simply stopping. get_collisions() itself is untouched, so a
## recording still reports clashes to anything that asks -- it just doesn't
## freeze the video at the first one, which is what a hard gate would do with
## nobody there to press Play again.
var movie_mode: bool = false
var _movie_finished: bool = false
var _movie_end_hold_remaining: float = 0.0

var _schedule: ConstructionSchedule = null
var _building_parts: Dictionary = {}
# crane name -> Crane, from SequenceManager._find_all_cranes() (or {} for the
# Phase 3 dock's editor preview, which deliberately previews with no crane --
# see addons/construction_4d_tool/docs/README.md's Phase 3 section). Which crane services which
# install unit is decided once, in ConstructionSchedule._init() (nearest-by-
# distance, or an action's explicit crane_id) -- this dictionary is only used
# here to look a unit's already-resolved crane_id back up to its live Crane
# node, and to retract every crane on a manual scrub/reset.
var _cranes: Dictionary = {}

## Wires up the schedule/parts/cranes and applies the initial (min_day)
## state. Call once after building the ConstructionSchedule.
## The resolved root "pour_stream" block, or {} for "no stream" (the default --
## see AnimationApplier.pour_stream_config()). Held here rather than looked up
## per pour because this class is the only caller of fire_fill_up_particles()
## and it has no sequence_data of its own; SequenceManager and the dock both set
## it right after set_schedule(). See 08_POUR_STREAM.md.
var pour_stream: Dictionary = {}

func set_schedule(schedule: ConstructionSchedule, building_parts: Dictionary, cranes: Dictionary = {}) -> void:
	_schedule = schedule
	_building_parts = building_parts
	_cranes = cranes
	# retract_crane=false: nothing has moved yet at initial setup, so there's
	# nothing to park. This also sidesteps a node-readiness ordering issue â€”
	# this runs inside SequenceManager._ready(), and if a crane is a later
	# sibling in the scene tree its own _ready() (which sets up _arm/_hook/
	# _rope) may not have run yet.
	scrub_to(schedule.get_date_range().min_day, false)

# Jump to a specific day and apply every part's state at that moment.
# retract_crane defaults to true (manual scrub/reset); Play drives this with
# false so no crane is yanked back to neutral on every frame.
func scrub_to(target_day: float, retract_crane: bool = true) -> void:
	if not _schedule:
		return
	collision_paused = false
	var date_range = _schedule.get_date_range()
	current_day = clampf(target_day, date_range.min_day, date_range.max_day)

	var states = _schedule.get_part_states(current_day)
	for part_name in states.keys():
		var part = _building_parts.get(part_name)
		if not part:
			continue
		var state = states[part_name]
		AnimationApplier.apply_instant(part, state.anim_type, state.progress)

	# Any GeoSun in the scene follows the calendar date (it ignores repeats of
	# the same day, so calling this every Play frame costs nothing).
	if _schedule.has_calendar_dates() and is_inside_tree():
		GeoSun.update_all(get_tree(), _schedule.day_to_epoch(current_day))

	if retract_crane:
		for crane in _cranes.values():
			crane.retract()
		if get_tree():
			get_tree().call_group("fill_up_particles", "queue_free")

## Resumes time advancement; _process() takes over from here.
func play() -> void:
	is_playing = true

## Pauses time advancement; current_day stays where it is.
func pause() -> void:
	is_playing = false

## Sets days-of-schedule advanced per real second (clamped to [0.1, 10.0]).
func set_speed(days_per_sec: float) -> void:
	playback_speed = clampf(days_per_sec, 0.1, 10.0)

## Switches this controller into Movie Maker Mode and starts the run: back to
## day 0, playing immediately. Nobody is there to press Play during a
## recording, so playback has to start itself.
##
## end_hold_sec is how long to sit on the completed structure before quitting.
## Held rather than cut because Movie Maker keeps writing frames until the app
## exits: quitting on the exact frame the last part lands makes the video stop
## dead the instant it finishes, which reads as a truncated export rather than
## an ending.
func begin_movie_run(end_hold_sec: float = 2.0) -> void:
	movie_mode = true
	_movie_finished = false
	_movie_end_hold_remaining = maxf(end_hold_sec, 0.0)
	reset()
	play()

## Jumps back to the start of the schedule (min_day), all parts reset.
func reset() -> void:
	if not _schedule:
		return
	scrub_to(_schedule.get_date_range().min_day)

## Phase 2: collisions at current_day, using the parts' live transforms
## (which already reflect current_day since scrub_to() applies state before
## this would typically be called). See ConstructionSchedule.get_collisions()
## for what counts as a collision.
func get_collisions() -> Array:
	if not _schedule:
		return []
	return _schedule.get_collisions(current_day, _building_parts)

## Phase 2: walks the whole schedule in sample_step-day increments looking
## for collisions, merges consecutive hits on the same part-pair into a
## single {part1, part2, start_day, end_day} window, and returns all windows
## sorted by start_day -- a summary of every collision in the project instead
## of having to scrub around hoping to spot one live.
##
## sample_step defaults to 0.01 to match get_part_states()'s internal cache
## granularity (int(round(day * 100))) -- a coarser step risks stepping over
## a short in-transit window entirely, e.g. when many parts are staggered
## within a single bucketed day, each one's transit window can be a small
## fraction of that day.
##
## This teleports every part through the full range via apply_instant() (no
## tweens, no crane movement -- scrub_to(day, false)) and restores current_day
## afterward, so it's silent to anything watching current_day/is_playing, but
## it does move parts through their full range synchronously; for a large
## project this is a deliberate one-shot scan, not something to call per frame.
func scan_collisions(sample_step: float = 0.01) -> Array:
	if not _schedule:
		return []
	# Nothing can collide without an install mover, and stepping every part
	# through every 0.01 day to prove it takes minutes on a large model.
	if not _schedule.has_install_parts():
		return []
	var date_range = _schedule.get_date_range()
	var saved_day = current_day

	# pair_key ("A|B", A < B) -> {part1, part2, days: Array[float]}
	var hits_by_pair: Dictionary = {}

	var day = date_range.min_day
	var reached_max = false
	while true:
		scrub_to(day, false)
		for c in _schedule.get_collisions(day, _building_parts):
			var pair_key = (c.part1 + "|" + c.part2) if c.part1 < c.part2 else (c.part2 + "|" + c.part1)
			if not hits_by_pair.has(pair_key):
				hits_by_pair[pair_key] = { "part1": c.part1, "part2": c.part2, "days": [] }
			hits_by_pair[pair_key].days.append(day)

		if reached_max:
			break
		day += sample_step
		if day >= date_range.max_day:
			day = date_range.max_day
			reached_max = true

	scrub_to(saved_day, false)

	var windows: Array = []
	for pair_key in hits_by_pair.keys():
		var entry = hits_by_pair[pair_key]
		var days: Array = entry.days
		days.sort()
		var window_start = days[0]
		var window_end = days[0]
		for i in range(1, days.size()):
			if days[i] - window_end <= sample_step * 1.5:
				window_end = days[i]
			else:
				windows.append({ "part1": entry.part1, "part2": entry.part2, "start_day": window_start, "end_day": window_end })
				window_start = days[i]
				window_end = days[i]
		windows.append({ "part1": entry.part1, "part2": entry.part2, "start_day": window_start, "end_day": window_end })

	windows.sort_custom(func(a, b): return a.start_day < b.start_day)
	return windows

func _process(delta: float) -> void:
	if not _schedule:
		return
	if not is_playing:
		if _movie_finished:
			_tick_movie_end_hold(delta)
		return

	var prev_day = current_day
	var target_day = current_day + playback_speed * delta
	var date_range = _schedule.get_date_range()
	if target_day >= date_range.max_day:
		target_day = date_range.max_day
		is_playing = false
		_movie_finished = movie_mode

	scrub_to(target_day, false)
	_detect_install_actions(prev_day, current_day)
	_detect_fill_up_actions(prev_day, current_day)

	# Phase 2 safety gate: stop forward playback the instant a live collision
	# is present, rather than animating through it. Deliberately a hard gate,
	# not a one-time warning -- pressing Play again while the same collision
	# is still there re-triggers it next frame (scrub_to() above clears
	# collision_paused, this immediately re-sets it), so the only way past is
	# to actually resolve the schedule or manually scrub through the window.
	# A "revert" alternative (roll back to just before the clash) was
	# considered and rejected: it would hide the very state
	# CollisionVisualizer exists to let you inspect.
	# Bypassed entirely in movie mode: with nobody to press Play again, the
	# gate wouldn't pause the recording at the first clash, it would end it --
	# Movie Maker keeps writing frames, so the video would run out its length
	# on a frozen picture.
	if is_playing and not movie_mode and not get_collisions().is_empty():
		is_playing = false
		collision_paused = true

## Counts the post-run hold down and then quits, which is what actually stops
## Movie Maker writing frames -- it records until the application exits, so a
## run that merely stops playing produces a video that continues over a static
## final frame for as long as the process happens to live.
##
## Counted in `delta`, deliberately, not against the wall clock: under Movie
## Maker `delta` is a fixed synthetic frame time derived from the target FPS,
## so this is exactly `end_hold_sec` seconds *of video* however fast or slow
## the machine renders it. That is the same property that makes playback
## itself deterministic under recording, and it would be lost the moment this
## used a real-time timer.
##
## Only ever reached with movie_mode true (_movie_finished is set from it), so
## the Phase 3 dock -- which shares this class -- can never quit the editor.
func _tick_movie_end_hold(delta: float) -> void:
	_movie_end_hold_remaining -= delta
	if _movie_end_hold_remaining <= 0.0:
		_movie_finished = false
		print("Movie mode: schedule complete, quitting to close the recording.")
		get_tree().quit()

# Fires one crane.swing() per install unit the first time forward playback
# crosses its start day, on whichever crane ConstructionSchedule._init()
# assigned that unit to (unit.crane_id -- "" if `cranes` was empty at
# schedule-build time, in which case _cranes.get("") finds nothing and the
# unit is silently skipped, same as when there was no crane at all pre-
# multi-crane). Compares this frame's [prev_day, current_day) window rather
# than a single "last triggered" scalar so multiple units starting on the
# same calendar day (e.g. several commanders bucketed into one day, possibly
# serviced by different cranes) each still get their own swing.
func _detect_install_actions(prev_day: float, cur_day: float) -> void:
	if _cranes.is_empty():
		return
	for unit in _schedule.get_install_units():
		if prev_day < unit.start_day and unit.start_day <= cur_day:
			var crane: Crane = _cranes.get(unit.crane_id)
			if not crane:
				continue
			var tracked_part = _building_parts.get(unit.tracked_part_name)
			if tracked_part:
				crane.swing(unit.pickup_pos, unit.target_pos, unit.lift_dur, unit.slide_dur, tracked_part)

# Fires concrete pour particle burst when forward playback crosses a fill_up action's start_day.
func _detect_fill_up_actions(prev_day: float, cur_day: float) -> void:
	if not _schedule.has_method("get_fill_up_units"):
		return
	for unit in _schedule.get_fill_up_units():
		if prev_day < unit.start_day and unit.start_day <= cur_day:
			var part = _building_parts.get(unit.part_name)
			if part:
				# Use duration in seconds equivalent to the schedule duration in days,
				# capped/scaled. Since we are in Play mode, the actual time taken is
				# duration_days / playback_speed.
				var actual_sec = unit.duration / playback_speed
				if actual_sec <= 0: actual_sec = 1.0
				AnimationApplier.fire_fill_up_particles(part, actual_sec, pour_stream)
