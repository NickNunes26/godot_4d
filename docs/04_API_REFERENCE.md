# 4D Construction Tool — API Reference

Quick reference for all public APIs in the 4D Construction Tool. For implementation details, see `01_ARCHITECTURE.md`.

> **Synced 2026-08-19.** Signatures below were re-verified against the source. The pre-multi-crane API this file used to document is corrected: `ConstructionSchedule._init()` takes a fourth `cranes: Dictionary` argument, `TimelineController.set_schedule()` takes `cranes: Dictionary` rather than a single `Crane`, and `scrub_to()` takes a second `retract_crane` argument. The `SequenceManager` section was rewritten around its three `@export`s (`construction_json_path`, `parts_container_path`, `crane_paths`) and its `@tool` / `Engine.is_editor_hint()` guard; a phantom `current_step` member was removed. Newly documented: `get_action_day_range()`, `day_to_date_string()`, `get_install_units()`, the `static` date helpers, `CollisionQuery`, the editor-side classes, and the `id` / `depends_on` / `lag_days` / `units_per_day` / `crane_id` schema fields.
>
> **Status**: this doc covered Phase 1 only when written. Phase 1 is now complete and Phase 2 (collision detection, complete except crane geometry) has shipped real APIs not originally planned here — added below (`ConstructionSchedule.get_collisions()`, `TimelineController.get_collisions()`/`scan_collisions()`/`collision_paused`, `CollisionVisualizer`, `CollisionOverlay.find_window_at()`) plus the out-of-roadmap `FreeLookCamera`. See `README.md` for full as-built detail. **One deliberate gap**: `get_collisions()`'s entry below stays to a stable public signature/return shape rather than describing its internal implementation — that internal detail drifted stale twice as the collision code was refactored (most recently into `collision_query.gd`), so it's documented once, in `README.md`, instead of being duplicated and re-drifting here. Any future addition to this file should follow the same rule: signature/params/return/example belong here, internal design rationale belongs in README.md only.

---

## Table of Contents

- [Cadence](#cadence)
- [ConstructionSchedule](#constructionschedule)
- [AnimationApplier](#animationapplier)
- [TimelineController](#timelinecontroller)
- [TimelineUI](#timelineui)
- [SequenceManager](#sequencemanager)
- [CollisionVisualizer](#collisionvisualizer) *(Phase 2, new)*
- [CollisionOverlay](#collisionoverlay) *(Phase 2, new)*
- [CollisionQuery](#collisionquery) *(Phase 2, new)*
- [FormworkBuilder](#formworkbuilder) *(07_FORMWORK.md, new)*
- [FreeLookCamera](#freelookcamera) *(outside roadmap, new)*
- [CameraTrack](#cameratrack) *(feature 5, new)*
- [CameraDriver](#cameradriver) *(feature 5, new)*
- [Editor-side classes](#editor-side-classes) *(Phase 3)*
- [Data Types](#data-types)

---

## Cadence

**File**: `cadence.gd`  
**Type**: Static utility class (no instances)  
**Purpose**: Extract stagger/duration math for animation sequencing

### Methods

#### `compute_timings(ordered_parts: Array[String], action: Dictionary, anim_duration: float, stagger_delay: float) -> Array[Dictionary]`

**Description**:
Compute per-part animation offsets and durations for an action, respecting acceleration and minimum constraints.

**Parameters**:
- `ordered_parts: Array[String]` — sorted part names (from `SpatialGrouper.sort_by_position()`)
- `action: Dictionary` — action config from JSON, containing:
  - `batch: bool` (optional, default `false`) — `true` makes every part animate
    simultaneously: no offset ever accumulates, so all parts get `offset_sec = 0` and an
    identical duration, and the remaining fields below have no effect. This is the "one
    concrete pour split into several meshes" case; see `README.md`, "Per-action cadence"
  - `stagger: float` (optional) — initial delay between parts
  - `stagger_accel: float` (optional, default 1.0) — multiply stagger each iteration
  - `stagger_min: float` (optional, default `stagger_delay`) — minimum stagger
  - `dur: float` (optional) — initial animation duration
  - `dur_accel: float` (optional, default 1.0) — multiply duration each iteration
  - `dur_min: float` (optional, default `anim_duration`) — minimum duration
- `anim_duration: float` — base animation duration (seconds)
- `stagger_delay: float` — base stagger delay (seconds)

**Returns**: Array of dictionaries:
```gdscript
[
  {part_name: String, offset_sec: float, duration_sec: float},
  {part_name: String, offset_sec: float, duration_sec: float},
  ...
]
```

**Example**:
```gdscript
var timings = Cadence.compute_timings(
  ["Wall1", "Wall2", "Wall3"],
  {"stagger_accel": 0.95, "stagger_min": 0.1, "dur_accel": 0.95, "dur_min": 0.1},
  1.0,
  0.75
)
# Result: [{part_name: "Wall1", offset_sec: 0.0, duration_sec: 1.0}, ...]
```

---

## ConstructionSchedule

**File**: `construction_schedule.gd`  
**Type**: RefCounted (garbage-collected)  
**Purpose**: Map "what date/time is it?" to "what's the state of each part?"

### Constructor

#### `_init(sequence_data: Dictionary, building_parts: Dictionary, spatial_grouper: SpatialGrouper, cranes: Dictionary = {}) -> void`

**Description**:
Initialize the schedule from parsed JSON, building parts dictionary, spatial grouper, and the scene's cranes. Resolves action start days (in topological `depends_on` order), buckets parts, assigns a crane to each install unit, and caches each part's `install_ground_start`.

**Parameters**:
- `sequence_data: Dictionary` — parsed JSON from `construction_steps.json`, containing:
  ```json
  {
    "steps": [
      {
        "index": 1,
        "actions": [
          {"type": "install", "start_date": "2025-03-01", "duration_days": 1, ...},
          ...
        ]
      },
      ...
    ]
  }
  ```
- `building_parts: Dictionary` — name → Node3D mapping (from `SequenceManager.initialize_parts()`)
- `spatial_grouper: SpatialGrouper` — cached grouper instance for resolving commander/child assignments
- `cranes: Dictionary` (optional) — crane node name → `Crane`, from `SequenceManager._resolve_cranes()`. Defaults to `{}` for callers with no crane at all (the Phase 3 dock's editor preview deliberately passes none). Each install unit is assigned the crane nearest by horizontal (XZ) distance, unless the action carries an explicit `crane_id`

**Raises**: None (logs warnings for invalid data, continues gracefully)

### Methods

#### `get_date_range() -> Dictionary`

**Description**:
Get the minimum and maximum day numbers for the entire construction sequence.

**Returns**:
```gdscript
{
  min_day: float,  # earliest day any part starts animating
  max_day: float   # latest day any part finishes animating
}
```

**Example**:
```gdscript
var schedule = ConstructionSchedule.new(...)
var range = schedule.get_date_range()
print(range)  # {min_day: 0.0, max_day: 7.0}
```

**Throws**: Never

---

#### `get_part_states(current_day: float) -> Dictionary[String, Dictionary]`

**Description**:
Query the state of all scheduled parts at a specific day number. **This is the core 4D query function.**

**Parameters**:
- `current_day: float` — day number to query (typically in range `[get_date_range().min_day, get_date_range().max_day]`)

**Returns**: Dictionary mapping part names to state info:
```gdscript
{
  "Col_1": {anim_type: "install", progress: 0.8},
  "Col_2": {anim_type: "install", progress: 0.0},
  "Beam_1": {anim_type: "install", progress: 0.3},
  ...
}
```

**State dictionary fields**:
- `anim_type: String` — animation type ("install", "scale_up", "drop_in", etc.)
- `progress: float` — animation progress in [0.0, 1.0]
  - 0.0 = animation not yet started
  - 1.0 = animation complete
  - 0.0 < progress < 1.0 = mid-animation

**Behavior**:
- Internally caches results, keyed by `int(round(current_day * 100.0))` — an **integer** key, not a rounded float (GDScript compares float keys by exact bits, so precision drift would silently defeat the cache)
- Returns an entry for every part in `_part_schedules`; empty only if nothing is scheduled at all
- Does **not** clamp `current_day`, and never errors on an out-of-range value — `progress` simply saturates at `0.0` before a part's start day and `1.0` after its end day. Clamping to the date range happens one level up, in `TimelineController.scrub_to()`
- The cache is **unbounded**: it holds one entry per distinct 0.01-day key ever queried, and is only discarded when the `ConstructionSchedule` itself is freed (a fresh one is built by Recalculate / Reload from JSON / Start Preview). `01_ARCHITECTURE.md` recommended an LRU or hard cap; that was not implemented

**Example**:
```gdscript
var schedule = ConstructionSchedule.new(...)
var states = schedule.get_part_states(3.5)  # Day 3.5
for part_name in states:
  var state = states[part_name]
  print("%s: %s at progress %.2f" % [part_name, state.anim_type, state.progress])
  # Output: "Col_1: install at progress 0.80"
```

**Throws**: Never

---

#### `get_collisions(current_day: float, building_parts: Dictionary) -> Array[Dictionary]` *(Phase 2, new)*

See `README.md`'s "Collision detection" section for the current, maintained
description of this method (design rationale, physics-shape setup, return shape) — the
internals it delegates to (`CollisionQuery`) have already moved once since this doc was
last synced, and README.md is where that detail is kept accurate going forward. Quick
signature reference: returns `[{part1: String, part2: String, overlap_volume: float,
overlap_aabb: AABB}, ...]`, one entry per commander pair with a real geometric overlap.

`building_parts` must already reflect `current_day`'s state — call this right after
`TimelineController.scrub_to(current_day)`, not standalone.

**Throws**: Never

---

#### `get_action_day_range(action_id: String) -> Dictionary`

**Description**:
Returns `{start_day, finish_day}` for a resolved action id (see `_action_id()`: explicit `id`, else `commander_prefix`, else `target_prefix`), or `{}` if the id is unknown.

Exists so the Phase 3 inspector can show a **Depends On** row's *actually resolved* End Date. An explicit-date row can compute its own end locally from `start_date + duration_days`; a dependency-driven action has no literal `start_date` to do that arithmetic from.

**Throws**: Never

---

#### `day_to_date_string(day: float) -> String`

**Description**:
Converts a relative day number — day 0 is the project's earliest `start_date`, **not** the unix epoch — back to a real `"YYYY-MM-DD"` calendar date. Returns `""` if `day` is NAN or infinite.

**Throws**: Never

---

#### `get_install_units() -> Array`

**Description**:
One entry per commander unit whose action type is `install`:
```gdscript
{start_day: float, pickup_pos: Vector3, target_pos: Vector3,
 tracked_part_name: String, lift_dur: float, slide_dur: float, crane_id: String}
```
Consumed by `TimelineController._detect_install_actions()` to fire one `Crane.swing()` per unit as forward playback crosses its `start_day` (never during scrub). `crane_id` is `""` when `cranes` was empty at schedule-build time; such units are silently skipped.

**Throws**: Never

---

#### Date helpers (all `static`)

Pure epoch/date-string arithmetic, on `ConstructionSchedule` so `ScheduleInspector` and `ScheduleCsvIO` share one implementation of "Start + Duration = End" rather than duplicating it.

```gdscript
static func parse_date_to_epoch(date_str: String) -> float
static func format_epoch_as_date(epoch: float) -> String
static func end_date_from_start_and_duration(start_date: String, duration_days: float) -> String
static func duration_from_start_and_end(start_date: String, end_date: String) -> float
static func start_date_from_end_and_duration(end_date: String, duration_days: float) -> String
```

**Throws**: Never

---

## AnimationApplier

**File**: `animation_applier.gd`  
**Type**: Static utility class (no instances)  
**Purpose**: Apply animations to parts, both via tweens (live) and instant (scrubbing)

### Animation Types

Supported animation types:
- `"scale_up"` — grow from zero scale to full size
- `"drop_in"` — fall from above
- `"rise_up"` — rise from below
- `"sink_down"` — descend below ground
- `"fill_up"` — grow in Y while keeping bottom pinned (with particle effects in live mode)
- `"fade_in"` — fade alpha from 0 to 1
- `"fade_out"` — fade alpha from 1 to 0

Both fades walk **descendant** `MeshInstance3D`s when the part itself isn't one, so a composite part (a `.glb` instance, e.g. a formwork tier-2 panel asset) fades instead of popping. They previously returned early on anything that wasn't a `MeshInstance3D`, so this is additive — see `07_FORMWORK.md`, decision 7.
- `"install"` — 3-phase lift/slide/lower (used for crane-assisted installation)

Plus one type `apply_instant()` handles that is **not** in `TYPES`, and deliberately so:

- `"formwork"` — a formwork part's assemble → hold → strip lifecycle, mapped onto one 0–1 window with per-panel boundaries in a `formwork_phases` meta. Assigned by `ConstructionSchedule._schedule_formwork()`, never authored. It stays out of `TYPES` because `TYPES` is what the dock's dropdown offers for an *element*, and setting a pier's type to `formwork` would read a phase meta off a part that has none. What an author picks is `formwork.type` / `formwork.strip_type`, both ordinary entries above, which this composes. See `README.md`, "Formwork (encofrado)"

### Methods

#### `apply(pt: Tween, part: Node3D, anim_type: String, dur: float) -> void`

**Description**:
Apply a live animation (via tween) to a part. **Used for Play mode.**

**Parameters**:
- `pt: Tween` — active tween to append animation to
- `part: Node3D` — the part node to animate
- `anim_type: String` — one of the animation types listed above
- `dur: float` — animation duration in seconds

**Behavior**:
- Sets up initial state (position, scale, visibility)
- Appends tween properties and callbacks to `pt`
- For `fill_up`: also creates particle effects and attaches to part's parent
- For `install`: assumes part starts at ground level (15 units away) and lifts/slides/lowers

**Example**:
```gdscript
var part = building_parts["Col_1"]
var tween = create_tween()
AnimationApplier.apply(tween, part, "install", 1.0)
await tween.finished
```

**Throws**: Never

---

#### `apply_instant(part: Node3D, anim_type: String, progress: float) -> void`

**Description**:
Apply animation state at a specific progress point, without tweens. **Used for scrubbing.**

**Parameters**:
- `part: Node3D` — the part node to animate
- `anim_type: String` — one of the animation types listed above
- `progress: float` — animation progress in [0.0, 1.0]

**Behavior**:
- Computes interpolated state using `Tween.interpolate_value()` (same easing as live tweens) — note its second argument is the **delta** (`final - initial`), not the final value
- Sets part properties directly (position, scale, material alpha, etc.)
- For `fill_up`: skips particle effects (live-only side effect)
- For `install`: maps progress into 3-phase windows and interpolates within each phase
- Handles edge cases:
  - `progress <= 0.0`: sets "animation not started" state (invisible, zero scale, etc.)
  - `progress >= 1.0`: sets final state (visible, full scale/position, opaque, etc.)

**Example**:
```gdscript
var part = building_parts["Col_1"]
AnimationApplier.apply_instant(part, "install", 0.5)  # Mid-install
AnimationApplier.apply_instant(part, "install", 1.0)  # Fully installed
```

**Throws**: Never

---

#### `fire_fill_up_particles(part: Node3D, dur: float = 1.0) -> void`

**Description**:
Spawns the concrete-pour stream for a `fill_up` action over `dur` **seconds** (not days).
Live playback only — `apply_instant()` deliberately never calls it.

**Parameters**:
- `part: Node3D` — the part being poured; must carry the `original_*` metas
- `dur: float` — how long the pour lasts in real seconds. Callers converting from schedule
  days must divide by playback speed, as `TimelineController._detect_fill_up_actions()`
  does

**Behavior**:
- Adds a `GPUParticles3D` as a sibling of `part` (with a second one parented to it for the
  landing splash) and a `GPUParticlesCollisionBox3D` as a child of `part` — all in the
  `"fill_up_particles"` group, so `TimelineController.scrub_to()` can clear them wholesale
  on a manual scrub
- Drop height, stream width, grain and splash reach are all derived from the part's own
  dimensions; particle lifetime is solved from the drop height so the stream lands on the
  fill surface rather than passing through the part. See `README.md`'s "Concrete pour
  stream" section for the rules and the reasoning
- Frees the nodes once the pour plus one particle lifetime has elapsed

**Throws**: Never

---

## TimelineController

**File**: `timeline_controller.gd`  
**Type**: Node (scene tree node)  
**Purpose**: Own the virtual clock and drive playback/scrubbing

### Members

```gdscript
var current_day: float             # Current day number
var is_playing: bool                # Whether time is advancing
var playback_speed: float          # Days per second (can be < 1 for slow-mo)
var collision_paused: bool         # (Phase 2, new) True if is_playing was just set
                                    # false because a live collision was detected,
                                    # as opposed to a manual pause() or reaching the
                                    # end of the date range. Cleared by scrub_to().
```

### Methods

#### `set_schedule(schedule: ConstructionSchedule, building_parts: Dictionary, cranes: Dictionary = {}) -> void`

**Description**:
Wire up the schedule, parts dictionary, and the scene's cranes for this controller.

**Parameters**:
- `schedule: ConstructionSchedule` — the 4D schedule engine
- `building_parts: Dictionary` — name → Node3D mapping
- `cranes: Dictionary` (optional) — crane node name → `Crane`. Used only to look a unit's already-resolved `crane_id` back up to its live node, and to retract every crane on a manual scrub. Empty means no crane control; install animations still play

**Behavior**:
- Stores references for use in `scrub_to()` and `_process()`
- Calls `scrub_to(schedule.get_date_range().min_day, false)` to initialize parts to start state. The `retract_crane = false` is deliberate: nothing has moved yet, and this runs inside `SequenceManager._ready()`, where a crane that is a later sibling in the scene tree may not have run its own `_ready()` yet

**Example**:
```gdscript
var controller = TimelineController.new()
controller.set_schedule(schedule, building_parts, cranes)
add_child(controller)
```

**Throws**: Never

---

#### `scrub_to(target_day: float, retract_crane: bool = true) -> void`

**Description**:
Jump to a specific day and apply all parts' states at that moment. **Used for both manual scrubbing and per-frame playback.**

**Parameters**:
- `target_day: float` — day number to scrub to; clamped to valid range
- `retract_crane: bool` (optional, default `true`) — whether to park every crane. Manual scrubs/resets leave this `true`; `_process()` passes `false` so cranes aren't yanked back to neutral on every frame of playback, which would prevent them from ever completing a swing

**Behavior**:
1. Returns immediately if no schedule is set
2. Clears `collision_paused` — any deliberate scrub/reset clears the Phase 2 gate
3. Clamps `target_day` to `[min_day, max_day]` and stores it in `current_day`
4. Calls `schedule.get_part_states(current_day)`
5. For each part in the result that exists in `_building_parts`, calls `AnimationApplier.apply_instant(part, anim_type, progress)`
6. If `retract_crane`, calls `retract()` on **every** crane in `_cranes`

**Side effects**:
- All parts instantly assume their state at `target_day`
- Cranes retract to neutral, unless `retract_crane` is `false`
- No tweens created or destroyed (existing tweens, if any, are unaffected)

**Example**:
```gdscript
controller.scrub_to(3.5)         # manual jump — cranes park
controller.scrub_to(3.5, false)  # playback-style step — cranes keep swinging
```

**Throws**: Never

---

#### `play() -> void`

**Description**:
Resume time advancement.

**Behavior**:
- Sets `is_playing = true`
- `_process(delta)` will advance `current_day` by `playback_speed * delta` each frame
- Crane swing detection begins — `_detect_install_actions()` fires one `Crane.swing()` per install unit whose `start_day` falls inside the frame's `[prev_day, current_day)` window, on whichever crane the schedule assigned it

**Example**:
```gdscript
controller.play()
```

**Throws**: Never

---

#### `pause() -> void`

**Description**:
Pause time advancement.

**Behavior**:
- Sets `is_playing = false`
- `_process(delta)` exits early, `current_day` unchanged
- Crane does not swing

**Example**:
```gdscript
controller.pause()
```

**Throws**: Never

---

#### `set_speed(days_per_sec: float) -> void`

**Description**:
Set playback speed (can be fractional for slow-motion or fast-forward).

**Parameters**:
- `days_per_sec: float` — days advanced per second of real time; clamped to [0.1, 10.0]

**Behavior**:
- 0.5 = half speed (0.5 days per real second)
- 1.0 = normal speed
- 2.0 = double speed
- Outside [0.1, 10.0] clamped to range

**Example**:
```gdscript
controller.set_speed(2.0)  # 2x speed
controller.play()
```

**Throws**: Never

---

#### `reset() -> void`

**Description**:
Return to the start state (first day, all parts at progress 0).

**Behavior**:
- Calls `scrub_to(schedule.get_date_range().min_day)`
- Equivalent to `scrub_to(0.0)` in most cases

**Example**:
```gdscript
controller.reset()
```

**Throws**: Never

---

#### `begin_movie_run(end_hold_sec: float = 2.0) -> void` *(Movie Maker Mode)*

**Description**:
Switches this controller into Movie Maker Mode and starts the run — back to day 0, playing immediately. Called by `SequenceManager._start_movie_run()`; nobody is there to press Play during a recording.

**Parameters**:
- `end_hold_sec: float` — seconds to sit on the completed structure before quitting. Held rather than cut because Movie Maker keeps writing frames until the app exits, so quitting on the frame the last part lands makes the video stop dead the instant it finishes.

**Behavior**:
- Sets `movie_mode = true`, then `reset()` + `play()`
- Two behaviour changes follow, both about the *reaction* to a collision rather than the query: `_process()`'s pause-on-collision gate is bypassed, and reaching the end quits the app after the hold (`_tick_movie_end_hold()`) instead of simply stopping
- `get_collisions()` is untouched — a recording still reports clashes to anything that asks

> **The hold is counted in `delta`, not against the wall clock.** Under Movie Maker, `delta` is a fixed synthetic frame time derived from the target FPS, so the hold is exactly `end_hold_sec` seconds *of video* however fast the machine renders. A real-time timer would discard the determinism that makes recorded playback frame-rate independent in the first place.

> **The editor can never be quit by this.** `_tick_movie_end_hold()` is only reachable with `movie_mode` true, which the Phase 3 dock — which shares this class — never sets.

**Throws**: Never

---

#### `get_collisions() -> Array[Dictionary]` *(Phase 2, new — not in original design)*

**Description**:
Convenience wrapper reading the controller's own `current_day` and `_building_parts`, delegating to `ConstructionSchedule.get_collisions()`. Called every display update by `TimelineUI`, which shows a red warning line with the colliding pair when non-empty.

**Example**:
```gdscript
var collisions = controller.get_collisions()
```

**Throws**: Never

---

#### `scan_collisions(sample_step: float = 0.01) -> Array[Dictionary]` *(Phase 2, new — not in original design)*

**Description**:
Steps through the *entire* date range (not just the current day), collecting every collision and merging consecutive hits on the same part-pair into windows. Teleports every part through the full range via `apply_instant()` (no tweens, no crane movement) and restores wherever the timeline was before returning — a one-shot, self-contained operation.

**Parameters**:
- `sample_step: float` — day-granularity to step at; defaults to `0.01` to match `get_part_states()`'s internal cache granularity (coarser steps risk stepping over a short in-transit window)

**Returns**: Array of merged collision windows:
```gdscript
[
  {part1: String, part2: String, start_day: float, end_day: float},
  ...
]
```

**Behavior**:
- Called by the "Scan Collisions" button in `TimelineUI`, which also prints a console report (e.g. `Day 3.10–3.40: Beam_02 ↔ Col_01`) and feeds the windows into `CollisionOverlay`
- The overlay does not auto-refresh — re-run after editing `construction_steps.json`

**Example**:
```gdscript
var windows = controller.scan_collisions()
```

**Throws**: Never

---

### `_process(delta: float) -> void` (Private, but important to understand)

**Internal behavior** (you don't call this, but understanding it helps):
- If `is_playing`:
  1. Advance `current_day += playback_speed * delta`
  2. Clamp to date range
  3. Call `scrub_to(current_day)` (unifies scrub & play code paths)
  4. Detect install-action boundaries and trigger crane swings if applicable
  5. **(Phase 2)** Call `get_collisions()`; if non-empty, set `is_playing = false` and `collision_paused = true` — a hard safety gate, not a one-time warning. Pressing Play again while the same collision is still present re-triggers it the very next frame.
- Else: return early

---

## TimelineUI

**File**: `timeline_ui.gd` + `timeline_ui.tscn`  
**Type**: Control (UI node)  
**Purpose**: Runtime UI for timeline scrubbing and playback control

### Scene Structure

> **As-built** (Phase 2 additions marked): the shipped `timeline_ui.tscn` adds a
> collision warning label, a `SliderStack` wrapper so `CollisionOverlay` can sit as a
> full-rect sibling of the slider, a "Scan Collisions" button, and a top-level hover
> tooltip — not present in the original Phase 1 design below.

```
TimelineUI (Control)
├── VBoxContainer
│   ├── DateLabel (Label, displays current date/day)
│   ├── CollisionWarningLabel (Label, Phase 2 — live "⚠ N collision(s): A ↔ B" text)
│   └── HBoxContainer
│       ├── PlayButton (Button, toggles Play/Pause; shows "Play (blocked)" — Phase 2 —
│       │   when TimelineController.collision_paused is true)
│       ├── SliderStack (Control, Phase 2 — wraps Slider + CollisionOverlay as full-rect
│       │   siblings, since HBoxContainer lays children out side by side, not stacked)
│       │   ├── Slider (HSlider, date/day scrubber)
│       │   └── CollisionOverlay (Control, Phase 2 — paints scan_collisions() red zones)
│       ├── SpeedSpinBox (SpinBox, playback speed 0.1–5.0x)
│       ├── ResetButton (Button, returns to start)
│       └── ScanCollisionsButton (Button, Phase 2 — runs scan_collisions() manually)
└── HoverTooltip (PanelContainer, Phase 2 — top_level=true, follows the mouse when
    hovering a CollisionOverlay red zone; see CollisionOverlay.find_window_at())
    └── HoverTooltipLabel (Label)
```

### Methods

#### `set_timeline_controller(controller: TimelineController, schedule: ConstructionSchedule) -> void`

**Description**:
Wire up the UI to a timeline controller and schedule.

**Parameters**:
- `controller: TimelineController` — the clock engine
- `schedule: ConstructionSchedule` — the schedule (for date range)

**Behavior**:
- Configures slider min/max from `schedule.get_date_range()`
- Connects UI signals (slider, buttons) to controller methods
- Displays initial date/day

**Example**:
```gdscript
var ui = preload("res://addons/construction_4d_tool/runtime/timeline_ui.tscn").instantiate()
add_child(ui)
ui.set_timeline_controller(controller, schedule)
```

**Throws**: Never

---

### UI Signals

**Emitted by buttons/slider** (you typically don't listen to these; they're internal):
- Slider value changed → `controller.scrub_to()` + `controller.pause()` — during playback the UI syncs the slider with `set_value_no_signal()` so this handler only fires on genuine user drags (a plain `value =` assignment would emit the signal and self-pause playback)
- Play button pressed → `controller.is_playing = !controller.is_playing` — but if a collision is still live, `TimelineController._process()` immediately flips it back to `false` and sets `collision_paused = true` the next frame (Phase 2 hard gate; see `TimelineController._process()`)
- Speed spinbox changed → `controller.set_speed()`
- Reset button pressed → `controller.reset()`
- Scan Collisions button pressed → `controller.scan_collisions()` *(Phase 2)* — also run once automatically on `TimelineUI`'s first `_process()` frame, not just on press

---

## SequenceManager

**File**: `sequence_manager.gd`  
**Type**: `@tool` Node3D (scene root script)  
**Purpose**: Orchestrate loading, setup, and wiring of the 4D tool

> **`@tool`**: the script runs in the editor so the Phase 3 dock can call `load_json()` / `initialize_parts()` on this node directly — without it, Godot substitutes an inert placeholder for any script on a node in the currently edited scene and every method call fails. `_ready()` is therefore guarded with `if Engine.is_editor_hint(): return`, so the side-effecting runtime setup (formwork generation, registering and hiding parts, mounting the controller/UI/visualizer) fires only at real Play/export runtime or via the dock's explicit **Start Preview**, never just from opening the scene.

### Exported properties

```gdscript
@export var construction_json_path: String = "res://construction_steps.json"
@export var parts_container_path: NodePath = NodePath()
@export var extra_part_containers: Array[NodePath] = []
@export var crane_paths: Array[NodePath] = []

@export_group("Movie Maker Mode")
@export var movie_mode_override: bool = false
@export var movie_duration_sec: float = 60.0
@export var movie_end_hold_sec: float = 2.0
@export var camera_track_path: String = "res://camera_track.json"
```

- `parts_container_path` — the child node whose **direct children** are the parts. **Required, no default**: point it at whatever node holds your model's parts. An unset path logs an error and a missing node a warning, but neither stops — the rest of `_ready()` still runs
- `extra_part_containers` — optional further nodes (relative to this one) whose direct children are also parts, e.g. props or safety elements outside the main model
- `crane_paths` — optional explicit override. Leave empty (the default) to auto-discover every `Crane`-scripted node in the scene instead; see `_resolve_cranes()`
- `movie_mode_override` — force movie mode on without actually recording, so a recording's behaviour can be checked in a plain Play session
- `movie_duration_sec` — how long day 0 → last day should take. Playback speed is derived from this and the schedule's span; the finished video is this plus `movie_end_hold_sec`. A target outside `set_speed()`'s `[0.1, 10.0]` range is warned about, not silently delivered as a different length
- `movie_end_hold_sec` — seconds to hold on the finished structure before quitting
- `camera_track_path` — optional `CameraTrack` file, applied in movie mode only. Absent or empty: the camera stays exactly where the scene put it. Its own file, so regenerating the schedule can't destroy it

### Members

```gdscript
var sequence_data: Dictionary           # Parsed JSON
var building_parts: Dictionary          # name → Node3D
var movie_mode: bool = false            # Resolved once in _ready()
var _spatial_grouper: SpatialGrouper    # Cached grouper
var _cranes: Dictionary = {}            # crane node name → Crane
var _timeline_controller: TimelineController = null
```

- `movie_mode` — true when this run is producing a video: `movie_mode_override`, or `Engine.get_write_movie_path() != ""` (that returns the output path when Godot was launched in Movie Maker Mode and `""` otherwise — verified against 4.6.2). Resolved **once**, in `_ready()`, and handed to whatever needs it rather than each subsystem querying `Engine` for itself; that single resolution point is what makes the override work. When true, `_ready()` calls `_start_movie_run()` and returns — **neither `TimelineUI` nor `CollisionVisualizer` is created at all**, since both run a live `get_collisions()` query every frame that a recording has no use for, and `TimelineUI`'s first frame would kick off a full-schedule `scan_collisions()`. See `README.md`, "Movie Maker Mode"

### Methods

#### `load_json() -> void`

**Description**:
Load and parse the schedule JSON named by `construction_json_path`.

**Behavior**:
- Opens `construction_json_path` (default `res://construction_steps.json`) via `FileAccess`
- Parses via `JSON.parse()` and stores the result in `sequence_data`

> **Fails silently.** If the file can't be opened, the method does nothing and `sequence_data` keeps its previous value. The `JSON.parse()` return code is not checked either, so a malformed file leaves `sequence_data` as `null` rather than raising. Callers that care should validate `sequence_data` themselves.

**Throws**: None

---

#### `initialize_parts() -> void`

**Description**:
Register all building parts and set up their metadata for animation.

**Behavior**:
1. Collects the direct children of the node at `parts_container_path`
2. Also collects the direct children of every `extra_part_containers` entry (both via `collect_part_nodes()`)
3. Clears `building_parts`, then resolves the two root-level prefix lists from
   `sequence_data` (`static_prefixes`, `excluded_prefixes` — see the Schedule JSON
   section below). Both match by `begins_with()`; empty-string entries are dropped with a
   warning, as they would match every part
4. For each part, by category:
   - **excluded** (matches `excluded_prefixes`): `visible = false` and **not** added to
     `building_parts` — no action can match it, no collision shape is built, it can never
     appear in a schedule. Not freed: the node stays in the scene so the decision is
     reversible
   - **otherwise**: restores `position`/`scale` from the `original_*` metas if present,
     then adds to `building_parts` (keyed by name), sets metas `original_pos`,
     `original_scale`, `original_transform`, `original_aabb` (if MeshInstance3D), and
     duplicates materials (so per-part alpha/color fades don't affect siblings)
     - **static** (matches `static_prefixes`): `visible = true`, left at full scale —
       present from the first frame, never animated, still collision-checked as a target
     - **everything else**: `visible = false`, `scale = Vector3.ZERO`
5. Warns for any prefix in either list that matched no part, and for any part matching
   both lists (excluded wins)

> **Idempotent.** This function mutates the parts it also reads the `original_*` metas from, so it restores from them before re-capturing — otherwise a second run records the first run's hidden, zero-scaled state as a part's original. That matters because re-running is normal: every **Start Preview** calls it, and it is how an edited `static_prefixes`/`excluded_prefixes` takes effect.

> **Input-shape assumptions.** One flat level of children, and each part's placement held in its own node transform. The `original_aabb` step guards on `child is MeshInstance3D` but not on `child.mesh != null`, so a mesh-less group node registered as a part is a null-instance crash. Both matter for IFC input — see `05_IFC_INTEGRATION.md`.

**Side effects**:
- All parts hidden at startup, except static ones
- Part state reset to pre-animation
- `building_parts` rebuilt from scratch

**Throws**: None

---

#### `pour_stream_config(sequence_data: Dictionary) -> Dictionary` *(static, AnimationApplier)*

**Description**:
The root `"pour_stream"` block, or `{}` meaning no stream. **Off by default** — an absent block yields `{}`, and `fire_fill_up_particles()` builds nothing at all in that case. `"enabled": false` also yields `{}`; an explicitly present but empty block yields `{"enabled": true}`, since `{}` is the "off" sentinel and an explicit opt-in must not collide with it. See `08_POUR_STREAM.md`.

#### `fire_fill_up_particles(part: Node3D, dur: float = 1.0, cfg: Dictionary = {}) -> void` *(static, AnimationApplier)*

**Description**:
Spawns the pour stream over `dur` seconds. `cfg` is a resolved `pour_stream_config()` result; an empty one returns immediately without constructing any node. Live playback only — `apply_instant()` never calls it. Reads `amount`, `grain`, `spread_deg`, `speed`, `gravity`, `fall`, `streak`, `splash_amount` and `collide`; `grain` and `fall` treat `0` as "derive from the element". Particle lifetime is solved from `speed`/`gravity`/`fall` and is deliberately not settable.

`TimelineController.pour_stream` holds the resolved config and is what actually passes it here — `SequenceManager._ready()` and the dock both set it. Changing it takes effect on the next pour, with no rebuild.

#### `make_materials_unique(node: Node) -> void`

**Description**:
Duplicate the materials a part draws with, so animating one part doesn't affect another sharing the same source material. Recurses into descendant `MeshInstance3D`s when `node` isn't one itself — a composite part (a `.glb` instance, e.g. a formwork tier-2 panel asset) would otherwise have every placement share a single material and fade in unison. Picks the same node set as `AnimationApplier._fade_targets()`, which is the other side of this; the dock's `_snapshot_materials()` walks it too, so a preview restores what it duplicated. See `07_FORMWORK.md`, decision 7.

**Parameters**:
- `mesh_instance: MeshInstance3D` — the mesh to isolate

**Behavior**:
- Loops over all surface override materials
- Calls `.duplicate()` on each and re-applies

**Throws**: None

---

### `_ready() -> void` (Called by Godot on startup)

**Behavior** (as shipped):
```gdscript
func _ready():
  if Engine.is_editor_hint():
    return                       # editor: the dock drives setup explicitly instead
  load_json()
  _generate_formwork()
  initialize_parts()
  _cranes = _resolve_cranes()    # crane_paths override, else auto-discovery
  if _cranes.is_empty():
    push_warning("SequenceManager: no crane found in the scene")

  var schedule = ConstructionSchedule.new(
    sequence_data, building_parts, _spatial_grouper, _cranes)

  _timeline_controller = TimelineController.new()
  add_child(_timeline_controller)
  _timeline_controller.set_schedule(schedule, building_parts, _cranes)
  # set_schedule() already scrubs to min_day — no separate scrub_to() needed.

  var ui = preload("res://addons/construction_4d_tool/runtime/timeline_ui.tscn").instantiate() as TimelineUI
  add_child(ui)
  ui.set_timeline_controller(_timeline_controller, schedule)

  var collision_visualizer = CollisionVisualizer.new()
  add_child(collision_visualizer)
  collision_visualizer.set_timeline_controller(_timeline_controller)
```

---

#### `_resolve_cranes() -> Dictionary`

**Description**:
Resolves every crane this scene should drive, keyed by node name — the same name an action's optional `crane_id` references.

**Behavior**:
- If `crane_paths` is non-empty, uses **only** those nodes; each missing or wrong-type entry is warned about individually rather than silently dropped
- Otherwise auto-discovers every node running `crane.gd` anywhere in the current scene, by **script identity** — not node name, not a fixed relative path. Any number of cranes, placed anywhere, are found with zero configuration
- Two cranes sharing a name collide in the returned Dictionary (last one found wins); give each a distinct name

**Throws**: Never

---

## CollisionVisualizer

**File**: `collision_visualizer.gd`
**Type**: Node3D, mounted by `SequenceManager._ready()`
**Purpose**: Draw a translucent red box at each live collision's exact location, every frame *(Phase 2, new — not in original design)*

**Behavior**:
- Reads `overlap_aabb` from each entry returned by `TimelineController.get_collisions()`
- Markers are pooled `MeshInstance3D`s (grown as needed, hidden rather than freed when unused)
- `size_padding` (`@export`, default 0.3m) adds margin around the actual `overlap_aabb` on every axis; `min_marker_size` (`@export`, default 0.6m) enforces a floor so even a razor-thin graze is visible
- Material is unshaded, emissive, `no_depth_test = true` (collision markers usually sit inside solid clashing parts, so depth testing would hide them)
- Distinct from `CollisionOverlay`: this is 3D and always reflects whatever the timeline is showing *right now* (appears/disappears while scrubbing/playing); `CollisionOverlay` is 2D and reflects a one-shot full-schedule scan

**Throws**: Never

---

## CollisionOverlay

**File**: `collision_overlay.gd`
**Type**: Control, lives in a `SliderStack` wrapper in `timeline_ui.tscn`
**Purpose**: Paint red zones directly on the timeline slider from a full-schedule collision scan *(Phase 2, new — not in original design)*

**Behavior**:
- Fed by `TimelineController.scan_collisions()`'s merged windows, triggered by the "Scan Collisions" button in `TimelineUI`, and also run once automatically on `TimelineUI`'s first `_process()` frame (`_auto_scanned`) so the overlay is populated without a manual click
- `mouse_filter = IGNORE` so it's completely transparent to input and never interferes with dragging the slider underneath (an earlier `PASS`-based approach with a `_get_tooltip()` hover override was abandoned because `PASS` still intercepted the slider's drag-start)
- `find_window_at(local_x: float) -> Dictionary`: hit-tests a local x-coordinate against the same pixel math `_draw()` uses, returning the matching window dict or `{}`. Used by `TimelineUI._update_hover_tooltip()` to show a hover tooltip (colliding pair + day range) without needing `mouse_filter = PASS` at all — the tooltip reads the mouse position via `Control.get_local_mouse_position()`, a coordinate conversion rather than an input event, so the overlay never has to give up `IGNORE`
- Does not auto-refresh mid-session — only reflects the last scan (automatic or manual); re-scan (or restart the scene) after editing `construction_steps.json`

**Throws**: Never

---

## FreeLookCamera

**File**: `free_look_camera.gd`
**Type**: attached directly to the scene's existing `Camera3D` node
**Purpose**: Free-fly spectator camera for debugging/inspection *(outside the phased roadmap entirely — a convenience addition, not planned in `00_4D_TOOL_OVERVIEW.md` or any milestone)*

**Behavior**:
- **Left-click** in the 3D viewport captures the mouse and starts flying; **Escape** releases it back to `Input.MOUSE_MODE_VISIBLE` so `TimelineUI` controls are clickable again
- **WASD** move, **Q/E** down/up, **Shift** sprints (`sprint_multiplier`, default 3x), mouse looks around (yaw/pitch, pitch clamped to ±89°); roll is dropped once at `_ready()`
- Speed/sensitivity are `@export`ed (`move_speed`, `vertical_speed`, `mouse_sensitivity`, `sprint_multiplier`) — tune in the Inspector, not the script
- Reads input via `_unhandled_input()` (not `_input()`) specifically so a click already consumed by a `TimelineUI` `Control` never falls through and triggers mouse capture
- Fully independent of `TimelineController`, parts, and collisions — would work in any scene with a `Camera3D`, no wiring through `SequenceManager`
- **Switched off in movie mode** by `SequenceManager._disable_free_look()` (`set_process(false)` / `set_process_unhandled_input(false)`, found by script identity). A recording must not be steerable by a stray keypress, and `CameraDriver` writes the same node's `global_transform` every frame — the two are never live at once

**Throws**: Never

---

## CameraTrack

**File**: `runtime/camera_track.gd`
**Type**: RefCounted — pure data + interpolation, no scene-tree or `Camera3D` reference
**Purpose**: The keyframe list behind camera keyframes *(feature 5)*

```gdscript
static func load_from(path: String) -> CameraTrack
func save_to(path: String) -> Error
func resolve(schedule: ConstructionSchedule) -> void
func sample(day: float) -> Dictionary   # {position: Vector3, basis: Basis, fov} or {}
func add_keyframe(day: float, date: String, transform: Transform3D,
                  fov: float, comment: String = "") -> Dictionary
func sort_by_day(schedule: ConstructionSchedule) -> void
func is_empty() -> bool
func size() -> int
```

- `resolve()` must be called before `sample()` — it converts `"date"` strings into the relative day numbers `TimelineController.current_day` speaks in, euler degrees into a `Basis`, defaults every optional field, sorts by day, and forward-fills `fov`. A keyframe whose date can't be resolved is **dropped with a warning**, not defaulted to day 0, where it would drag the camera to the start of the project and look like an interpolation bug
- `sample()` holds the nearest keyframe outside the authored range rather than extrapolating; honors `hold_days` and `cut`; lerps position, slerps rotation through a `Quaternion`, and smoothsteps `t`
- Raw JSON dictionaries are kept alongside the resolved list so `save_to()` round-trips fields this class doesn't understand (comments, future keys) instead of dropping them
- File shape and the reasoning are in `README.md`'s "Camera keyframes" section

---

## CameraDriver

**File**: `runtime/camera_driver.gd`
**Type**: `@tool` Node, created by `SequenceManager._start_camera_track()` in movie mode only
**Purpose**: Applies a `CameraTrack` sample to a real `Camera3D` each frame *(feature 5)*

```gdscript
func setup(track: CameraTrack, controller: TimelineController, camera: Camera3D) -> void
```

- Reads `controller.current_day` rather than keeping its own clock, so the camera is locked to the same virtual time as the geometry by construction — and inherits Movie Maker's fixed synthetic delta for free, with no frame-rate handling of its own
- `setup()` applies the opening pose immediately instead of waiting for the first `_process()`: in a recording that frame is already in the video, and would otherwise show the scene's authored camera before snapping to the track
- Any keyframe with no `fov` uses the camera's own value at `setup()`, so a track authored without fov in mind leaves the scene's framing alone
- Created **only** when a track exists and is non-empty — with no track, movie mode leaves the camera exactly where the scene put it

---

## FormworkBuilder

**File**: `core/formwork_builder.gd`
**Type**: RefCounted, all `static` — no instances, no state
**Purpose**: Generates the formwork geometry an action's formwork phase animates *(07_FORMWORK.md, build order steps 2 and 4)*

```gdscript
static func build(sequence_data: Dictionary, container: Node) -> int   # panels created
static func sweep(container: Node) -> int                              # panels freed
const META_OWNER := "formwork_of"    # stamped on every panel, names the part it wraps
const GROUP := "generated_formwork"
```

- **Call `build()` before `SequenceManager.initialize_parts()`**, so panels are registered and hidden like any other part. `SequenceManager._generate_formwork()` does this at runtime; the dock does it in Start Preview and Recalculate
- **Idempotent** — `build()` sweeps its own previous output first, so calling it repeatedly leaves the same scene as calling it once. This matters because the dock preview re-runs setup on every Start Preview
- Generated nodes are deliberately **never `owner`ed**, so Godot cannot write them into the `.tscn`. Formwork is a view of the schedule plus the model, not scene content
- Reads each part's `original_transform`/`original_aabb` metas when present and its live state when not — the first run has no metas and untouched parts; every run after has metas and mutated parts
- Skips an action with no room for a formwork phase, asking `ConstructionSchedule._resolve_formwork_split()` rather than replicating the rule
- Derives boards from the part's **own vertical mesh faces**, not from its AABB: triangles within ~14° of vertical cluster into planar patches (merged by normal, split by plane offset, bounded in metres off the seed plane, then split into laterally contiguous runs), and each patch's rectangle subdivides into boards. Inward-facing clusters are dropped; the largest 40 per part survive. Measured on a real model, this took the mean board-to-surface gap from 5.0 m to 0.10 m
- Boards carry a full `Basis(tangent, up, normal)`, so skewed and curved faces get boards lying flat against them
- Falls back to the four AABB faces only when a part's mesh yields no usable vertical face
- Generates **nothing** for a `formwork.prefix` (tier 1) action — those parts are already in the scene, and `ConstructionSchedule` schedules them itself
- Places an instance of `formwork.model` (tier 2) at every position the generic slab (tier 3) would have used, scaled to fill that board, centred on its own AABB rather than its origin, and rotated 90° about Y when the asset's thin axis disagrees with the slot's. Loaded and measured once per path. Any unusable path warns once per action and falls back to the generic slab
- Skips parts matching *any* action's `formwork.prefix`, so forms never get forms of their own
- Design rationale (placement, board subdivision, corner butting, tier fitting) lives in `07_FORMWORK.md`

---

## CollisionQuery

**File**: `core/collision_query.gd`
**Type**: RefCounted, owned by `ConstructionSchedule` as `_collision_query`
**Purpose**: Physics-shape setup and the exact-geometry overlap query behind `ConstructionSchedule.get_collisions()` *(Phase 2; split out of `construction_schedule.gd` on 2026-08-18)*

```gdscript
func setup(building_parts: Dictionary) -> void
func query(building_parts: Dictionary, states: Dictionary,
           sibling_groups: Dictionary, part_to_commander: Dictionary) -> Array
```

Not called directly by application code — `ConstructionSchedule.get_collisions()` is the public entry point. Registers raw `PhysicsServer3D` areas (no `Area3D` scene nodes), freed on `NOTIFICATION_PREDELETE`. Design rationale lives in `README.md`'s "Collision detection" section, deliberately in one place rather than duplicated here.

---

## Editor-side classes

Phase 3, all under `addons/construction_4d_tool/editor/`. Documented in depth in `README.md`'s Phase 3 section; listed here so this reference names everything that ships.

| Class | File | Role |
|---|---|---|
| *(dock)* | `timeline_dock.gd` | Orchestrator: preview lifecycle, target detection, button wiring. Extends `Control`, not `EditorPlugin` |
| `ScheduleInspector` | `schedule_inspector.gd` | The 15-column action grid and every field's edit handler, plus the zero-match and no-room-for-formwork warning markers and per-row remove |
| `ScheduleCsvIO` | `schedule_csv_io.gd` | CSV export/import of the scheduling fields, matched by resolved action id |

`ScheduleInspector`'s **Encofrado** dropdown and **Días vertido** spinner resolve through `ConstructionSchedule.resolve_formwork_config()`, so a row always reports the tier the schedule will actually use — including one inherited from the root `formwork_defaults` that `TimelineDock`'s project-wide checkbox writes. `refresh_formwork_states()` re-evaluates every row and is what that checkbox calls. Tier 1/2 items are listed but disabled unless the action already carries `formwork.prefix`/`formwork.model`; geometry links stay JSON-only. See `07_FORMWORK.md`, decisions 8 and 9.

`ScheduleCsvIO.HEADER` carries `formwork_mode` (`none`/`generic`/`model`/`prefix`, exported *resolved*), `pour_days` and `strip_days` (exported from the action's **own** block only, so a project-wide default doesn't become 24 per-action overrides on re-import). Geometry links are never written from CSV.
| `ScheduleProjectXmlIO` | `schedule_project_xml_io.gd` | Microsoft Project **XML Interchange** export/import (not the binary `.mpp` format) |
| `ProjectXmlMappingDialog` | `project_xml_mapping_dialog.gd` | One-time manual task→action mapping for foreign Project files |

`plugin.gd` is the `EditorPlugin` entry point and is deliberately thin — it only instantiates the dock scene and adds it to `DOCK_SLOT_LEFT_BR`.

---

## IFC classes (`ifc/`)

Optional IFC import. Only the dock's Load IFC button needs the GDIFC addon; these classes do not.
See `05_IFC_INTEGRATION.md` for the workflow.

### `IfcMapping` (`RefCounted`)
The user's choice of which IFC properties mean what. A property path is an `Array` of `String`,
`[property_set, property]`, matched exactly.

- Fields: `element_id`, `start`, `end`, `duration`, `display_name`, `type_source` (paths);
  `default_type: String` (default `"scale_up"`); `type_rules: Array[{contains, type}]`;
  `ignore_dates: Array[String]`; `last_generated: Dictionary` (`{id: {type, batch}}`).
- `is_valid() -> bool`, `missing_roles() -> Array[String]` — Element ID, Start, and End-or-Duration are required.
- `referenced_paths() -> Array`
- `static get_value(props: Dictionary, path: Array) -> Variant` — `null` if any step is missing.
- `static to_date_string(value) -> String` — `YYYY-MM-DD` from an ISO-looking value, else `""`.
- `static path_to_string(path) -> String`, `static profile_path_for(json_path) -> String`
  (`x.json` -> `x.ifc_profile.json`).
- `to_dict()`, `static from_dict(d)`, `static load_from(path) -> IfcMapping` (null if absent),
  `save_to(path) -> Error`.

### `IfcPropertyScanner` (`RefCounted`)
- `static scan(root: Node) -> Dictionary` — `{total: int, properties: Array[{path, count, samples, kind}]}`;
  `kind` is `"date"`, `"number"` or `"text"`; sorted by coverage.

### `GDIFC4DAdapter` (`RefCounted`)
- `static adapt(ifc_root: Node, mapping: IfcMapping = null) -> Node3D` — flat container of named parts
  (named from the Element ID; fallback `<zone>_<name>`), placement moved into node transforms.
- `static get_property_sets(leaf: MeshInstance3D) -> Dictionary`

### `IFCScheduleGenerator` (`RefCounted`)
- `static generate(parts_container: Node, mapping: IfcMapping, existing: Dictionary = {}) -> Dictionary` —
  a `{steps, static_prefixes, excluded_prefixes}` schedule, or `{}` with an error if the mapping is
  incomplete. Carries forward the two prefix lists and any hand-edited `type`/`batch`. Updates
  `mapping.last_generated`; save the mapping afterwards.
- `static read_existing(path) -> Dictionary`, `static write_data(data, path) -> Error`

### `IfcMappingDialog` (`ConfirmationDialog`, editor)
- `setup(scan: Dictionary, initial: IfcMapping, lock_element_id := false)`; signal
  `mapping_confirmed(mapping: IfcMapping)`. OK stays disabled until the required roles are chosen.

### `SequenceManager` additions
- `extra_part_containers: Array[NodePath]`, `collect_part_nodes() -> Array`.

---

## Data Types

### Schedule JSON root

```gdscript
{
  "steps": [ {"actions": [ ... ]} ],   # The work -- see Action Dictionary below

  # Geometry, not work. Both match by begins_with(), the same rule target_prefix
  # uses; both are optional and default to empty. Read by
  # SequenceManager.initialize_parts(), and carried across regeneration by
  # IFCScheduleGenerator.read_existing(). See README.md, "Static and excluded
  # geometry"
  "static_prefixes": ["ZoneA_"],   # Visible from frame 0, never animated,
                                              #   still collision-checked (as a target)
  "excluded_prefixes": ["Survey_marker_"],    # Hidden for the whole run and never
                                              #   registered in building_parts at all

  # Formwork defaults for every action, overridden key by key by an action's own
  # "formwork" block. A non-empty block turns formwork on project-wide; an action
  # opts back out with "formwork": false. See 07_FORMWORK.md
  "formwork_defaults": {"pour_days": 1.0}
}
```

### Action Dictionary (from JSON)

```gdscript
{
  # Animation type (required)
  "type": "install",  # or "scale_up", "drop_in", etc.
  
  # Part targeting (required; either target_prefix OR commander_prefix + child_prefixes)
  "target_prefix": "Col_",  # Single prefix mode
  # OR:
  "commander_prefix": "Col_",
  "child_prefixes": ["Rebar_Col"],
  
  # Identity & dependencies (Phase 3)
  "id": "cols_2",                 # Optional explicit id; else commander_prefix,
                                      #   else target_prefix (ConstructionSchedule._action_id())
  "depends_on": "cols_1",         # Finish-to-start. A single id string OR an array
                                      #   of them; with several, this action starts after
                                      #   the LATEST predecessor finishes. Only consulted
                                      #   when start_date is absent — start_date always wins
  "lag_days": 2,                      # Days after the predecessor finishes (default 0).
                                      #   May be negative (a lead/overlap). Applied once,
                                      #   uniformly, not per-predecessor. Ignored without
                                      #   depends_on
  
  # Timing (new in Phase 1)
  "start_date": "2025-03-01",        # ISO 8601 date string
  "duration_days": 1,                 # How many days this action spans (clamped to >= 1)
  "units_per_day": 2,                 # Alternative to duration_days — a rate, from which
                                      #   duration_days = ceil(unit_count / units_per_day).
                                      #   Only used when duration_days is absent
  
  # Crane selection (multi-crane)
  "crane_id": "CraneNorth",           # Optional override of nearest-by-distance assignment,
                                      #   matched against a Crane node's own .name. Only
                                      #   meaningful for an "install" action with 2+ cranes.
                                      #   An unresolvable id warns and falls back
  
  # Cadence control (optional) -- all values are RELATIVE: the whole cadence is
  #   normalized onto duration_days, so these set the spacing *within* an action,
  #   never its total length. See README.md, "Per-action cadence"
  "batch": false,                     # true = all parts animate together, one pour.
                                      #   Set by IFCScheduleGenerator from the action's
                                      #   type (true unless install/drop_in), and editable
                                      #   per row in the inspector's Cadencia column.
                                      #   When true, every field below has no effect
  "stagger": 1.02,                    # Initial delay between parts (seconds)
  "stagger_accel": 0.95,              # Multiply stagger each iteration
  "stagger_min": 0.11,                # Minimum stagger value
  "dur": 1,                           # Initial duration (seconds)
  "dur_accel": 0.95,                  # Multiply duration each iteration
  "dur_min": 0.1,                     # Minimum duration
  
  # Formwork (encofrado) -- 07_FORMWORK.md. Splits this action's window into a
  #   formwork phase and the pour that follows it. Absent -> the whole window is
  #   the pour, exactly as before this existed. Geometry resolves in three tiers,
  #   first match wins: "prefix", then "model", then the generic wood slab
  "formwork": {
    "pour_days": 1.0,                 # Formwork gets duration_days minus this (default 1.0)
    "formwork_days": 4.0,             # Explicit alternative; WINS if both are present
    "strip_days": 0.0,                # Cure days after the pour before the forms come off
    "strip": true,                    # false keeps them forever (encofrado perdido)
    "type": "scale_up",               # How a panel appears (any AnimationApplier.TYPES)
    "strip_type": "fade_out",         # How it comes off (likewise)
    "batch": false,                   # Panels stagger even when the action batches
    "board_width": 2.5,               # Target board width, world m, before a face subdivides
    "thickness": 0.05,                # Panel thickness, world m
    "prefix": "A1_FORM",             # Tier 1: these scene parts ARE the forms; nothing generated
    "model": "res://.../panel.glb",   # Tier 2: this asset at every computed placement
    "enabled": true                   # false opts this action out of formwork_defaults;
                                      #   "formwork": false is the shorthand
  },

  # Optional
  "comment": "Install pillars"        # Human-readable description (ignored by parser)
}
```

### Part State Dictionary (returned by `get_part_states()`)

```gdscript
{
  "anim_type": "install",  # Animation type
  "progress": 0.75         # 0.0 = not started, 1.0 = complete
}
```

### Date Range Dictionary (returned by `get_date_range()`)

```gdscript
{
  "min_day": 0.0,
  "max_day": 7.0
}
```

---

## Common Patterns

### Pattern 1: Set up and play

```gdscript
var schedule = ConstructionSchedule.new(sequence_data, building_parts, spatial_grouper, cranes)
var controller = TimelineController.new()
controller.set_schedule(schedule, building_parts, cranes)
add_child(controller)

var ui = preload("res://addons/construction_4d_tool/runtime/timeline_ui.tscn").instantiate()
add_child(ui)
ui.set_timeline_controller(controller, schedule)

controller.play()
```

### Pattern 2: Scrub to a specific date

```gdscript
controller.scrub_to(5.5)  # Jump to day 5.5
```

### Pattern 3: Check building state at a date

```gdscript
var states = schedule.get_part_states(3.0)
for part_name in states:
  var state = states[part_name]
  var part = building_parts[part_name]
  if state.progress > 0.0:
    print("%s is visible at day 3.0 (progress %.2f)" % [part_name, state.progress])
```

### Pattern 4: Change playback speed during play

```gdscript
controller.set_speed(2.0)  # 2x speed
# (no need to call play() again, already playing)
```

---

## Error Handling

The APIs are designed to fail gracefully:
- Invalid dates → logged warning, treated as day 0
- Missing parts → logged warning, skipped
- Out-of-range `current_day` → clamped silently
- JSON parse errors → logged, construction continues with partial data

**No exceptions are thrown** — the tool is defensive and tries to work with whatever data it gets.

---

## Performance Notes

- `get_part_states()` is O(num_actions + num_parts); caching makes repeated calls O(1)
- `scrub_to()` is O(num_parts) — calls `apply_instant()` for each scheduled part
- 60 FPS playback expected with < 500 parts
- Profiling tools available in Godot editor (Monitors tab)

For detailed performance guidance, see `02_ROADMAP_MILESTONES.md` (Milestone 7).

---

## Versioning

This API reference originally covered **Phase 1** (`v1.0.0`) only; it has been extended in place with the Phase 2 (partial) and out-of-roadmap APIs that have since shipped, rather than versioned separately. See `README.md` for the authoritative current status.

Breaking changes in future versions will be noted with deprecation warnings.
