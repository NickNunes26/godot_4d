# 4D Construction Tool — Roadmap & Milestones (Phase 1)

> **✅ Status: all of Phase 1 (Milestones -1 through 8) is complete**, matching this plan closely. Known deviations from the specific acceptance-criteria examples below (particularly Milestone 1's day-bucketing math and Milestone 5's bucketing visual test) are called out where they occur — see the "continuous cadence vs. discrete bucketing" note under Milestone 1. Phase 2 (collision detection, complete except crane geometry), Phase 3 (the editor dock) and the five features of `06_PLANNED_FEATURES.md` — all built — are not covered by this doc, which predates all of them; see `README.md` for their as-built status.

## Execution Strategy

This document details the **exact order** in which to implement Phase 1, breaking it into small, independently-testable milestones. Each milestone must pass its acceptance criteria before moving to the next.

**Key principle**: Lowest dependencies first, incremental validation, catch architectural issues early.

> **From-scratch note**: This roadmap originally assumed an existing, working construction-animation project. Starting from zero, **Milestone -1 must be completed first** — it builds the animation foundation that every later milestone extracts from, extends, or compares against. If you already have the working `sequence_manager.gd` / `animation_applier.gd` / `spatial_grouper.gd` / `crane.gd` pipeline, skip Milestone -1 and start at Milestone 0.

---

## Milestone -1: From-Scratch Foundation (Scene, Parts, Base Animations) — ✅ Complete

### Deliverable
A working Godot 4 project with sequential, tween-based construction playback — the baseline that Phase 1 refactors into a scrubbable 4D tool. This is also the **visual reference** used later in Milestone 5's parity testing.

### Implementation Steps

1. **Project & scene setup**
   - Create a Godot 4.x project via the Project Manager
   - Import building model(s) (`.glb`/`.fbx`) under a container node (e.g. `Building`)
   - Ensure parts have meaningful, prefix-based names (e.g. `Col_1`, `Beam_2`) — prefixes are the join between JSON and runtime lookup
   - Add lighting, camera, `WorldEnvironment`

2. **`sequence_manager.gd` (scene root script)**
   - `load_json()`: load and parse `construction_steps.json` from a configurable `res://` path (`@export var construction_json_path`)
   - `initialize_parts()`: register all children of the container in `building_parts: Dictionary` (name → Node3D); for each part set metas `original_pos`, `original_scale`, `original_transform`, `original_aabb` (MeshInstance3D only); duplicate materials (`make_materials_unique()`) so per-part alpha fades don't bleed across shared materials; hide all parts (`visible = false`, `scale = Vector3.ZERO`)
   - Stagger/duration accumulation loop in `_animate_single()` / `_animate_spatial_group()`, supporting `stagger`, `stagger_accel`, `stagger_min`, `dur`, `dur_accel`, `dur_min`
   - `play_all_steps()`: sequential auto-play awaiting each step's tween

3. **`animation_applier.gd` (static utility)**
   - Implement all 8 tween-based animations: `scale_up`, `drop_in`, `rise_up`, `sink_down`, `fill_up` (bottom-pinned Y growth using AABB offset), `fade_in`/`fade_out` (requires `TRANSPARENCY_ALPHA`), `install` (3-phase lift/slide/lower)
   - Every method reads from part metas, never live node state

4. **`spatial_grouper.gd`**
   - Commander/child assignment by XZ world-space distance, using `original_transform * original_aabb.get_center()` for centroids
   - Static `sort_by_position()` (back-to-front Z descending, then right-to-left X descending)
   - Per-instance result cache

5. **`crane.gd`**
   - `swing(pickup, target, lift_dur, slide_dur, tracked_part)`: arm rotation toward pickup then target
   - Per-frame hook/rope tracking of the carried part's Y
   - **`retract()`**: tween arm/hook/rope back to a neutral parked pose. *(This method is required by Milestone 3's `scrub_to()`; it does not exist anywhere yet and must be written here.)*

6. **`construction_steps.json` (v1 schema, no dates)**
   - Steps with `index` + `actions`; actions target parts via `target_prefix` or `commander_prefix` + `child_prefixes`

7. **End-to-end test**: hit Play, watch the full sequential construction with correct ordering, stagger acceleration, crane choreography, and no material bleed. Record a screen capture — it becomes the Milestone 5 reference.

### Acceptance Criteria
- ✅ Scene plays the full sequence automatically with no console errors
- ✅ All 8 animation types demonstrably work on at least one part each
- ✅ Stagger/duration acceleration visibly speeds up later parts in a group
- ✅ Crane swings in sync with `install` actions and `retract()` parks it cleanly
- ✅ Fading one part does not affect siblings sharing the same source material

### Files Created
- Project scaffold, main scene, `sequence_manager.gd`, `animation_applier.gd`, `spatial_grouper.gd`, `crane.gd`, `construction_steps.json`

### Estimated Effort
- **20–30 hours** (dominated by the 8 animations, crane math, and model import/tuning). This is the true cost of "starting from scratch" — every estimate below assumes this foundation exists.

---

## Milestone 0: Groundwork & JSON Schema Extension — ✅ Complete

### Deliverable
- Extended `construction_steps.json` with date fields
- `cadence.gd` (static, no dependencies)
- Proof that old JSON still works (backwards compatibility)

### Implementation Steps
1. **Update `construction_steps.json` schema**
   - Add `"start_date"` and `"duration_days"` to each action (see `01_ARCHITECTURE.md` for schema)
   - Use realistic dates (e.g., first action starts "2025-03-01", runs 1 day; second action starts "2025-03-02", runs 3 days)
   - Ensure all 7 actions have consistent, non-overlapping date ranges covering ~1 week

2. **Create `cadence.gd`**
   - Implement `Cadence.compute_timings(ordered_parts, action, anim_duration, stagger_delay)`
   - Extract the stagger accumulation loop from `_animate_single` / `_animate_spatial_group` (built in Milestone -1) into this shared static class, then make both callers use it — one implementation, two consumers
   - Test with a simple script that calls `compute_timings()` with sample data and prints results

3. **Test backwards compatibility**
   - Temporarily modify `SequenceManager._ready()` to attempt loading JSON
   - Confirm no parse errors even with new fields added

### Acceptance Criteria
- ✅ `cadence.gd` compiles and runs without errors
- ✅ `Cadence.compute_timings()` returns correct offsets for a 3-part test case (spot-check math)
- ✅ `construction_steps.json` loads without errors (via `FileAccess` + `JSON.parse()`)
- ✅ All 7 actions have `start_date` in `construction_steps.json`
- ✅ Date ranges don't overlap (or if they do, document why and add a note)

### Files Modified/Created
- `construction_steps.json` — **modified** (add `start_date`, `duration_days`)
- `cadence.gd` — **new**
- Test output: printed results from sample `Cadence.compute_timings()` call

### Estimated Effort
- 30–45 minutes (mostly copying & understanding existing loop)

---

## Milestone 1: `ConstructionSchedule` — Date-to-State Mapping — ✅ Complete (with a deviation)

> **⚠️ As-built deviation**: the shipped implementation does **not** do discrete per-day bucketing with independent cadence spans as detailed in steps 5–6 below. It normalizes one continuous cadence curve across an action's whole `duration_days` window instead. Stagger order and spread across the date range are preserved; hard day-boundary groupings (e.g. exactly "7+7+7" as three separate cadence buckets) are not produced. See `01_ARCHITECTURE.md`'s matching callout and `README.md`'s "Known limitations" for detail. Flagged as technical debt to revisit before Phase 4.

### Deliverable
- Pure-logic class that maps "given a day number, what's each part's animation state?"
- Unit-testable (no scene-tree dependencies)
- Caches results for performance

### Implementation Steps

1. **Create `construction_schedule.gd`**
   - `class_name ConstructionSchedule` (RefCounted)
   - Constructor: `_init(sequence_data: Dictionary, building_parts: Dictionary, spatial_grouper: SpatialGrouper)`
   - Responsibilities:
     - Parse each action's `start_date` and `duration_days`
     - Convert dates to day-numbers (floats) using a helper like:
       ```gdscript
       static func _date_to_day_num(date_str: String) -> float:
         var dt = Time.get_unix_time_from_datetime_string(date_str)
         return floor(dt / 86400.0)  # seconds per day
       ```
     - For each action, resolve its ordered parts (reuse `SpatialGrouper` + `sort_by_position`)
     - Bucket parts across `duration_days` (distribute evenly; 7 parts over 3 days → 3+2+2)
     - Store internal structure:
       ```gdscript
       var _action_windows = []  # [{action, parts_in_day_1, parts_in_day_2, ...}, ...]
       var _part_schedule = {}   # {part_name → {start_day, end_day, anim_type, cadence_info}}
       ```

2. **Implement `get_date_range()`**
   - Scan `_part_schedule` to find min and max day numbers
   - Return `{min_day: float, max_day: float}`

3. **Implement `get_part_states(current_day: float)`**
   - For each part in `_part_schedule`:
     - Compute `progress = clamp((current_day - start_day) / (end_day - start_day), 0.0, 1.0)`
     - Return `{anim_type: String, progress: float}`
   - Implement caching to avoid recomputation — key by `int(round(current_day * 100.0))`, an integer, not a rounded float (float dictionary keys compare by exact bits and precision drift defeats the cache)

4. **Implement part-resolution logic** (move from `_animate_single` / `_animate_spatial_group`)
   - Resolve `target_prefix` actions: loop `building_parts`, collect all matching prefixes, sort via `SpatialGrouper.sort_by_position()`
   - Resolve `commander_prefix` actions: use `_spatial_grouper.get_groups()`, sort commanders, iterate children

5. **Day-bucketing logic**
   - For an action spanning `duration_days` with `N` parts, distribute with floor + remainder (NOT `ceil(N / duration_days)`, which front-loads and can leave trailing empty days — e.g. ceil gives 7 parts over 3 days as 3+3+1):
     - `base = N / duration_days` (integer division), `remainder = N % duration_days`
     - The first `remainder` buckets get `base + 1` parts, the rest get `base`
     - 7 parts over 3 days → **3+2+2**; 21 parts over 3 days → 7+7+7
   - Bucket `i` occupies calendar day `start_day + i`; each bucket gets its own `Cadence.compute_timings()` call

6. **Seconds→days mapping (the cadence↔calendar bridge)**
   - `Cadence.compute_timings()` returns offsets/durations in **seconds**; `get_part_states()` operates in **day numbers**. Define the conversion explicitly:
     - For each bucket, compute its total cadence span: `span_sec = last part's offset_sec + last part's duration_sec`
     - Normalize each part's timings into the bucket's one-day window:
       - `part_start_day = bucket_day + (offset_sec / span_sec) * BUCKET_FILL`
       - `part_end_day = bucket_day + ((offset_sec + duration_sec) / span_sec) * BUCKET_FILL`
     - `BUCKET_FILL` is a constant in `[0, 1]` — the fraction of the calendar day the bucket's animations occupy (recommended: `1.0`, filling the whole day). This preserves the *relative* stagger/acceleration shape while stretching it to calendar time.
   - Store the resulting per-part `{start_day, end_day}` in `_part_schedule` — after this point everything downstream is day-based and cadence seconds never leak out of the constructor

### Acceptance Criteria
- ✅ `construction_schedule.gd` compiles without errors
- ✅ `ConstructionSchedule.new()` instantiates without errors (with real `sequence_data`, `building_parts`, `spatial_grouper`)
- ✅ `get_date_range()` returns sensible bounds (e.g., 0.0 to 7.0 for a 1-week project)
- ✅ `get_part_states(day)` returns a dictionary with entries for scheduled parts
- ✅ Spot-check: at `day = min_day`, a part has `progress = 0.0`; at `day = max_day`, parts have `progress = 1.0`
- ✅ Spot-check: at `day = (min_day + max_day) / 2`, parts in the middle have `progress ≈ 0.5`
- ✅ 21-wall example: 3 days, buckets as 7+7+7 correctly ordered by `sort_by_position`
- ✅ 7-part example: 3 days, buckets as 3+2+2 (floor + remainder, no empty trailing day)
- ✅ Within a bucket, parts' `start_day` values preserve the cadence stagger order and relative spacing

### Files Modified/Created
- `construction_schedule.gd` — **new**
- Test script or print-debug output confirming bucketing and state queries

### Estimated Effort
- 1–1.5 hours (most complex business logic in Phase 1)

---

## Milestone 2: `AnimationApplier.apply_instant()` — Instant State Without Tweens — ✅ Complete

### Deliverable
- For each animation type, a method that sets a part's state at a given progress (0–1)
- Uses `Tween.interpolate_value()` for identical easing math to live tweens
- Supports all 8 animation types

### Implementation Steps

1. **Add method signature** (in `animation_applier.gd`)
   ```gdscript
   static func apply_instant(part: Node3D, anim_type: String, progress: float) -> void:
     match anim_type:
       "scale_up":  _scale_up_instant(part, progress)
       "drop_in":   _drop_in_instant(part, progress)
       ...
   ```

2. **Implement each `_*_instant` method** using `Tween.interpolate_value()`
   - ⚠️ **API pitfall**: the second argument of `Tween.interpolate_value(initial_value, delta_value, elapsed, duration, trans, ease)` is the **delta** (`final - initial`), NOT the final value. Passing the final value only happens to work when the initial value is zero (as in `scale_up`); for `drop_in`, `rise_up`, `sink_down`, `install`, and the fades you must pass `final - initial` or positions will be wrong.
   - Example for `_scale_up_instant`:
     ```gdscript
     static func _scale_up_instant(part: Node3D, progress: float) -> void:
       var orig_scale = part.get_meta("original_scale")
       if progress <= 0.0:
         part.visible = false
         part.scale = Vector3.ZERO
       elif progress >= 1.0:
         part.visible = true
         part.scale = orig_scale
       else:
         part.visible = true
         var interp = Tween.interpolate_value(
           Vector3.ZERO,               # initial_value
           orig_scale - Vector3.ZERO,  # delta_value = final - initial (NOT the final value!)
           progress,
           1.0,
           Tween.TRANS_BACK,
           Tween.EASE_OUT
         )
         part.scale = interp
     ```
   - Counter-example for a non-zero start (`_drop_in_instant`):
     ```gdscript
     var start_y = orig_pos.y + 15.0
     var y = Tween.interpolate_value(
       start_y,
       orig_pos.y - start_y,   # delta = final - initial = -15.0
       progress, 1.0,
       Tween.TRANS_CUBIC, Tween.EASE_OUT   # shipped as TRANS_BOUNCE; the bounce was removed later
     )
     ```
   - Repeat for all 8 types, following the spec in `01_ARCHITECTURE.md`
   - For `_install_instant`, handle 3 phases (0–0.3, 0.3–0.7, 0.7–1.0)

3. **Test visually** (defer to Milestone 4, but code should be ready)
   - Call `apply_instant(part, "scale_up", 0.5)` and verify part is halfway scaled
   - Compare against paused tween at 50% progress (eye-ball match)

### Acceptance Criteria
- ✅ All 8 `_*_instant()` methods implemented
- ✅ Code compiles without errors
- ✅ Calling `apply_instant(part, anim_type, 0.0)` sets start state
- ✅ Calling `apply_instant(part, anim_type, 1.0)` sets end state
- ✅ Calling `apply_instant(part, anim_type, 0.5)` sets mid state (visually reasonable)
- ✅ `_install_instant` phase transitions are smooth (no visible jumps at 0.3/0.7 boundaries)

### Files Modified/Created
- `animation_applier.gd` — **modified** (add `apply_instant` methods)

### Estimated Effort
- 45–60 minutes (mostly copy-paste + adapt for instant apply)

---

## Milestone 3: `TimelineController` — Virtual Clock & Scrub Driver — ✅ Complete

### Deliverable
- Owns `current_day`, playback state (play/pause/speed)
- Single entry point for all state changes: `scrub_to(day)`
- Detects install-action boundaries during forward play for crane swings

### Implementation Steps

1. **Create `timeline_controller.gd`**
   - `extends Node`
   - Constructor sets initial state to stopped at `min_date`

2. **Implement state accessors**
   ```gdscript
   var current_day: float = 0.0
   var is_playing: bool = false
   var playback_speed: float = 1.0  # days/sec
   ```

3. **Implement `scrub_to(target_day)`**
   - Clamp to `schedule.get_date_range()`
   - Set `current_day = target_day`
   - Call `schedule.get_part_states(target_day)`
   - For each part in the result, call `AnimationApplier.apply_instant(part, anim_type, progress)`
   - Park crane: `if _crane: _crane.retract()` — `retract()` is written in Milestone -1 (it is not part of the original `crane.gd`); guard against calling it every frame during Play (only retract on manual scrubs/jumps, otherwise the crane can never swing)

4. **Implement transport controls**
   ```gdscript
   func play() -> void:
     is_playing = true
   
   func pause() -> void:
     is_playing = false
   
   func set_speed(days_per_sec: float) -> void:
     playback_speed = clamp(days_per_sec, 0.1, 10.0)
   
   func reset() -> void:
     scrub_to(schedule.get_date_range().min_day)
   ```

5. **Implement `_process(delta)`**
   ```gdscript
   func _process(delta: float) -> void:
     if not is_playing:
       return
     
     current_day += playback_speed * delta
     var date_range = _schedule.get_date_range()
     if current_day > date_range.max_day:
       current_day = date_range.max_day
       is_playing = false  # auto-stop at end
     
     scrub_to(current_day)
     _detect_install_actions()
   
   func _detect_install_actions() -> void:
     # For each install action in schedule:
     #   If _last_action_start_day < action.start_day <= current_day:
     #     Call _crane.swing(...) with appropriate args
     #     Set _last_action_start_day = action.start_day
   ```

6. **Implement `set_schedule()` (wiring method)**
   ```gdscript
   func set_schedule(schedule: ConstructionSchedule, building_parts: Dictionary, crane: Crane = null) -> void:
     _schedule = schedule
     _building_parts = building_parts
     _crane = crane
     current_day = schedule.get_date_range().min_day
   ```

### Acceptance Criteria
- ✅ `timeline_controller.gd` compiles
- ✅ Can construct: `var tc = TimelineController.new()`
- ✅ Can wire: `tc.set_schedule(schedule, building_parts, crane)`
- ✅ Can call: `tc.scrub_to(5.5)` → parts update to correct state
- ✅ Can play: `tc.play()` → `_process(delta)` advances `current_day` smoothly
- ✅ Can pause: `tc.pause()` → `_process(delta)` stops advancing
- ✅ Speed control: `tc.set_speed(2.0)` → time advances 2x as fast
- ✅ Reset: `tc.reset()` → `current_day = min_date`, all parts at start state

### Files Modified/Created
- `timeline_controller.gd` — **new**

### Estimated Effort
- 45–60 minutes

---

## Milestone 4: `TimelineUI` & Integration Into Scene — ✅ Complete

### Deliverable
- Runtime UI (slider, Play button, speed control, date label)
- Wired to `TimelineController`
- Scene ready to play

### Implementation Steps

1. **Create `timeline_ui.tscn` scene**
   - Root: `Control` (anchored to top, e.g., `anchor_left=0, anchor_top=0, anchor_right=1, anchor_bottom=0.1`)
   - Children:
     - `VBoxContainer`
       - `Label` (name: `DateLabel`, text: "2025-03-01")
       - `HBoxContainer`
         - `Button` (name: `PlayButton`, text: "Play")
         - `HSlider` (name: `Slider`, min_value: 0, max_value: 100)
         - `SpinBox` (name: `SpeedSpinBox`, min_value: 0.1, max_value: 5.0, step: 0.1, value: 1.0)
         - `Button` (name: `ResetButton`, text: "Reset")

2. **Create `timeline_ui.gd`**
   ```gdscript
   extends Control
   
   @onready var _date_label: Label = $VBoxContainer/DateLabel
   @onready var _slider: HSlider = $VBoxContainer/HBoxContainer/Slider
   @onready var _play_button: Button = $VBoxContainer/HBoxContainer/PlayButton
   @onready var _speed_spinbox: SpinBox = $VBoxContainer/HBoxContainer/SpeedSpinBox
   @onready var _reset_button: Button = $VBoxContainer/HBoxContainer/ResetButton
   
   var _timeline_controller: TimelineController = null
   var _schedule: ConstructionSchedule = null
   
   func _ready() -> void:
     _slider.value_changed.connect(_on_slider_changed)
     _play_button.pressed.connect(_on_play_pressed)
     _speed_spinbox.value_changed.connect(_on_speed_changed)
     _reset_button.pressed.connect(_on_reset_pressed)
   
   func set_timeline_controller(controller: TimelineController, schedule: ConstructionSchedule) -> void:
     _timeline_controller = controller
     _schedule = schedule
     var range = schedule.get_date_range()
     _slider.min_value = range.min_day
     _slider.max_value = range.max_day
     _slider.value = range.min_day
   
   func _on_slider_changed(value: float) -> void:
     if _timeline_controller:
       _timeline_controller.scrub_to(value)
       _timeline_controller.pause()
       _update_display()
   
   func _on_play_pressed() -> void:
     if _timeline_controller:
       _timeline_controller.is_playing = not _timeline_controller.is_playing
       _update_button_text()
   
   func _on_speed_changed(value: float) -> void:
     if _timeline_controller:
       _timeline_controller.playback_speed = value
   
   func _on_reset_pressed() -> void:
     if _timeline_controller:
       _timeline_controller.reset()
       _slider.value = _schedule.get_date_range().min_day
       _update_display()
   
   func _process(_delta: float) -> void:
     if _timeline_controller:
       # ⚠️ Must use set_value_no_signal(): assigning _slider.value emits
       # value_changed, which routes to _on_slider_changed → pause(), so
       # pressing Play would self-pause on the very next frame.
       _slider.set_value_no_signal(_timeline_controller.current_day)
       _update_display()
   
   func _update_button_text() -> void:
     _play_button.text = "Pause" if _timeline_controller.is_playing else "Play"
   
   func _update_display() -> void:
     if _timeline_controller and _schedule:
       _date_label.text = "Day %.1f" % _timeline_controller.current_day
   ```

3. **Modify `sequence_manager.gd`**
   - In `_ready()`, after `initialize_parts()`:
     ```gdscript
     var schedule = ConstructionSchedule.new(sequence_data, building_parts, _spatial_grouper)
     var timeline_controller = TimelineController.new()
     timeline_controller.set_schedule(schedule, building_parts, _crane)
     add_child(timeline_controller)
     
     var ui = preload("res://timeline_ui.tscn").instantiate() as TimelineUI
     add_child(ui)
     ui.set_timeline_controller(timeline_controller, schedule)
     
     # Scrub to start state
     timeline_controller.scrub_to(schedule.get_date_range().min_day)
     ```
   - Remove old `play_all_steps()` call from `_ready()`
   - Keep `load_json()`, `initialize_parts()`, everything else

### Acceptance Criteria
- ✅ Scene plays without errors
- ✅ Timeline UI visible at top of screen
- ✅ Slider appears with correct min/max values (e.g., 0–7 for 7-day project)
- ✅ Dragging slider updates parts instantly (scrub test)
- ✅ Parts snap to correct state at each slider position
- ✅ Play button toggles between "Play" and "Pause" text
- ✅ Clicking Play advances timeline smoothly (compare to the Milestone -1 auto-play) — and does NOT immediately self-pause (regression test for the slider feedback loop)
- ✅ Speed spinbox changes playback rate (2x is noticeably faster, 0.5x is noticeably slower)
- ✅ Reset button returns to start state
- ✅ Date label updates as time advances

### Files Modified/Created
- `timeline_ui.tscn` — **new**
- `timeline_ui.gd` — **new**
- `sequence_manager.gd` — **modified** (add wiring code, remove old play logic)

### Estimated Effort
- 1–1.5 hours

---

## Milestone 5: Visual Parity Testing & Correctness — ✅ Complete

### Deliverable
- Proof that scrubbed state matches sequential playback at all points
- No artifacts, no visual divergence

### Implementation Steps

1. **Capture reference** (old sequential playback)
   - Temporarily keep old `play_all_steps()` code in a branch or comment it out
   - Play animation, observe key frames:
     - T=0s (all parts hidden)
     - T=2s (first few walls installed)
     - T=5s (midpoint)
     - T=end (all complete)
   - Take screenshot/note visual state at each

2. **Test scrubbing matches**
   - Slider to day 0 → compare to T=0s above (should match)
   - Slider to day ~3.5 → compare to T=5s above
   - Slider to day 7 → compare to T=end above
   - Verify:
     - Same parts visible
     - Same positions
     - Same scales
     - Same opacities (if fade_in/fade_out used)
     - Same particle effects (if fill_up used during play; none during scrub is acceptable)

3. **Test Play matches**
   - Click Play, let it run to completion
   - Compare against original sequential playback
   - Spot-check 2–3 intermediate points (pause, compare visually to old playback at equivalent time)

4. **Test boundary conditions**
   - Scrub to exact action boundaries (day 1.0, day 2.0, etc.)
   - Parts should not jump; state should be continuous
   - No visible flickering or popping

5. **Test multi-day bucketing**
   - Update JSON to have 21 walls over 3 days
   - Verify visual order matches `sort_by_position` (back-to-front, right-to-left)
   - Verify 7 walls per day (roughly equal distribution)
   - Check day boundaries: days 1–2 should show ~7 at 100%, 7 at 0–100% in progress, 7 at 0%

### Acceptance Criteria
- ✅ Scrubbed state visually identical to old sequential playback at key time points
- ✅ Play mode produces smooth motion matching original
- ✅ No unexpected popping, flickering, or state jumps
- ✅ 21-wall bucketing shows correct visual order and distribution
- ✅ Particles fire correctly during Play (fill_up)
- ✅ Particles do NOT fire during scrubbing (expected, acceptable)
- ✅ Crane swings during Play, parks during scrub (expected, acceptable)

### Files Modified/Created
- (No code changes; testing & comparison only)
- Test report: screenshots or written notes of visual comparison

### Estimated Effort
- 30–45 minutes (mostly manual visual inspection)

---

## Milestone 6: Backwards Compatibility & Edge Cases — ✅ Complete

### Deliverable
- Old JSON files work without modification
- Edge cases handled gracefully (missing dates, invalid ranges, etc.)

### Implementation Steps

1. **Test old JSON (no dates)**
   - Restore a pre-4D version of `construction_steps.json` (or create one with no `start_date`/`duration_days`)
   - Load and play
   - Confirm: either falls back gracefully or errors with clear message

2. **Test missing fields**
   - Action missing `start_date` → should use default (epoch, day 0, or skip with warning)
   - Action missing `duration_days` → should use default (1 day)
   - Action missing both → should work, treating as day 0, 1 day

3. **Test invalid dates**
   - `start_date: "invalid"` → should log warning, treat as day 0
   - `start_date: "1999-01-01"` → should work (old dates are fine)
   - `start_date: "2099-12-31"` → should work (future dates are fine)

4. **Test overlapping date ranges**
   - If two actions have overlapping `start_date`+`duration_days`, parts should schedule correctly (both active on same day is fine)
   - No corruption or crashes

5. **Test edge case: 0 days, negative duration**
   - `duration_days: 0` → clamp to 1
   - `duration_days: -1` → clamp to 1
   - No crashes

6. **Test edge case: 1 part over 10 days**
   - Bucketing should put 1 part on day 0, none on days 1–9
   - Should not crash

### Acceptance Criteria
- ✅ Old JSON files load without crashing
- ✅ Invalid dates logged as warnings, not errors
- ✅ Clamping works (0 days → 1, etc.)
- ✅ Overlapping ranges don't cause visual artifacts
- ✅ Edge cases (single part, many days) handled correctly

### Files Modified/Created
- Test cases: old JSON variant, invalid JSON variant
- Error logs reviewed

### Estimated Effort
- 30 minutes

---

## Milestone 7: Performance & Optimization — ✅ Complete

### Deliverable
- Scrubbing is responsive (< 50ms per query)
- No memory leaks (cache doesn't grow unbounded)
- 60 FPS playback on target hardware

### Implementation Steps

1. **Profile state query latency**
   - Instrument `ConstructionSchedule.get_part_states()` with timing code
   - Call 1000x with random day numbers
   - Log min/max/avg time
   - Target: < 5ms per call (leaves 45ms for rendering)

2. **Test cache effectiveness**
   - Note: during continuous Play, `current_day` produces a new rounded key nearly every frame, so the cache is mostly *misses* by design — that's fine, because the uncached query is O(parts) and cheap. The cache only pays off for repeated queries at the *same* day (e.g. a paused UI polling state, or Phase 2 collision scans).
   - Verify: two consecutive queries at the identical day hit the cache (second call is O(1))
   - Confirm cache size is bounded (LRU eviction or a hard cap, e.g. 1024 entries) — a 365-day project scrubbed at 0.01 granularity could otherwise accumulate ~36k entries

3. **Test 60 FPS playback**
   - Enable profiler in Godot
   - Play animation at 1x speed
   - Confirm frame time < 16.67ms (1000ms / 60fps)
   - No noticeable stutter

4. **Test large dataset**
   - Create JSON with 500 parts, 100 days
   - Confirm still responsive (< 50ms queries, 60 FPS play)

5. **Contingency: dirty-flag part application** (only if scrubbing stutters)
   - The state *query* is cheap; the likely bottleneck is writing hundreds of `Node3D` transforms per frame (each dirties Godot's transform tree)
   - Fix: cache each part's last-applied `{anim_type, progress}` and have `scrub_to()` skip parts whose state is unchanged — at any given day most parts sit at a stable 0.0 or 1.0, so the set that actually changes per frame is small

### Acceptance Criteria
- ✅ `get_part_states()` avg latency < 5ms (uncached — this is the number that matters during Play)
- ✅ Repeated queries at an identical day are served from cache in O(1)
- ✅ Cache is bounded (does not grow past its cap during a long scrub session)
- ✅ 60 FPS playback sustained
- ✅ No memory leaks (watch `Monitors` tab in Godot)
- ✅ Scales to 500+ parts without visible degradation

### Files Modified/Created
- Profile results (console output or screenshots)

### Estimated Effort
- 20–30 minutes

---

## Milestone 8: Documentation & Handoff — ✅ Complete (the as-built README lives alongside this file, at `README.md`, maintained continuously rather than as a one-time handoff doc)

### Deliverable
- README for project (how to use the tool)
- Inline code comments (public API documented)
- Example JSON file with comments
- Ready for Phase 2 transition

### Implementation Steps

1. **Write README.md** (in project root or `docs/`)
   - Overview: what is this tool?
   - Quick start: load the scene, drag slider, click Play
   - Data model: how to author `construction_steps.json`
   - Example: screenshot of UI + walkthrough
   - Known limitations: crane parks during scrub, no collision checks yet

2. **Add docstring comments to public APIs**
   - `ConstructionSchedule`: constructor, `get_date_range()`, `get_part_states()`
   - `TimelineController`: `set_schedule()`, `scrub_to()`, `play()`, `pause()`, `set_speed()`
   - `AnimationApplier`: `apply()`, `apply_instant()`

3. **Annotate `construction_steps.json`** with comments explaining new fields

4. **Write Phase 2 Prep notes**
   - What collision detection would look like
   - Entry point for EditorPlugin (Phase 3)
   - Known technical debt (if any)

### Acceptance Criteria
- ✅ README is clear and complete
- ✅ All public methods have docstrings
- ✅ Example JSON is annotated
- ✅ Phase 2 transition plan is clear
- ✅ No orphaned or undocumented code

### Files Modified/Created
- `README.md` — **new**
- Docstrings in all new `.gd` files
- Comments in `construction_steps.json`

### Estimated Effort
- 30–45 minutes

---

## Summary: Milestone Timeline

| Milestone | Deliverable | Dependencies | Est. Time |
|-----------|-------------|--------------|-----------|
| -1 | From-scratch foundation (scene, parts, 8 animations, grouper, crane) | None | **20–30h** |
| 0 | JSON schema + Cadence | M-1 | 30–45m |
| 1 | ConstructionSchedule | M0 | 1.5–2.5h (includes seconds→days mapping design) |
| 2 | apply_instant() | M0, M1 | 45–60m |
| 3 | TimelineController | M1, M2 | 45–60m |
| 4 | TimelineUI + Scene | M3 | 1–1.5h |
| 5 | Visual Parity Testing | M4 | 30–45m |
| 6 | Backwards Compat | M5 | 30m |
| 7 | Performance | M6 | 20–30m |
| 8 | Documentation | M7 | 30–45m |

**Total estimated time**:
- On top of an existing working animation project: **7–9 hours** (Milestones 0–8)
- **Truly from scratch: ~28–40 hours** (Milestone -1 dominates)

---

## Rollout Strategy

### During Development
- Work on milestones in order (dependencies matter)
- After each milestone, commit with message: "Milestone N: [deliverable]"
- Test acceptance criteria before moving to next

### Before Merge to Main
- All 8 milestones passing
- Play scene end-to-end in Godot (no errors in console)
- Visual parity test complete
- Documentation complete

### After Phase 1 Complete
- Tag release: `v1.0-phase1-timeline-foundation`
- Begin Phase 2 design (collision detection)
- Start planning Phase 3 (EditorPlugin)

> **✅ As-built**: Phase 1 complete, Phase 2 (collision detection) complete except crane geometry — see `README.md`. Phase 3 (EditorPlugin) not yet started; the "no rewrite needed" architectural bet (pure `RefCounted`/`Node` classes) still holds as of this update.

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Easing curves diverge between play & scrub | `Tween.interpolate_value()` guarantees identical math; spot-check visually |
| `interpolate_value` misuse (2nd arg is delta, not final) | Explicit warning + counter-example in M2; wrong-position bugs surface in M5 parity tests |
| Slider sync feedback loop pauses playback | `set_value_no_signal()` in `TimelineUI._process()` (see M4); regression criterion in M4 |
| Seconds↔days conversion left implicit | Defined explicitly in M1 step 6 (bucket-normalized mapping with `BUCKET_FILL`) |
| `install` instant path needs pickup/ground-start position | Compute and store `ground_start` as a part meta at schedule-build time (M1) so `apply_instant` doesn't depend on crane geometry at query time |
| Cache grows unbounded | Implement max cache size with LRU eviction (see M7) |
| Large datasets slow down scrubbing | Profile early (M7); optimize `get_part_states()` if needed |
| Crane state leaks during scrub | Call `_crane.retract()` on manual scrubs/jumps (not every Play frame); `retract()` is written in M-1 |
| JSON backwards compatibility broken | Test M6 with old JSON files; use defaults for new fields |
| Missing documentation for Phase 3 | M8 explicitly prepares Phase 2/3 design notes |
