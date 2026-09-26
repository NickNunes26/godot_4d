# 4D Construction Tool — Detailed Architecture

> **⚠️ Status update**: this is the original pre-implementation design. It shipped largely as designed, with the deviations called out inline below (search for "As-built" callouts). See `README.md` for the full current picture, including Phase 2 (collision detection, complete except crane geometry), the Phase 3 editor dock, the free-fly camera (outside this roadmap), and the five features of `06_PLANNED_FEATURES.md` — all now built.
>
> **The core bet in this document held.** None of those five needed a rewrite of anything designed here: they were edits to existing functions, two new root-level JSON keys, a flag, and one self-contained camera subsystem that reads `current_day` and writes a `Camera3D`. The one thing not anticipated is that new features make *latent* bugs load-bearing — the static/excluded geometry feature forced `SequenceManager.initialize_parts()` to become idempotent, which nothing had previously required.
>
> **Formwork (`07_FORMWORK.md`) is the first feature to add to the core rather than only around it**, and it is worth being precise about how. `ConstructionSchedule` gained the formwork/pour window split and panel scheduling, and `AnimationApplier` gained a `formwork` type. But **`get_part_states()` was not touched** — the design deliberately routed around it, because a part's three-phase lifecycle folds into one 0–1 window (exactly as `_install_instant()` already folds lift/slide/lower) rather than needing `_part_schedules` to become multi-phase. The structural insight is that formwork is *more parts with their own window*, not a new timeline concept: nothing in this document ever required an action's parts to share one. Everything downstream — scrub/play parity, the collision query, the dock, movie mode — needed no changes, so the bet still holds, just less trivially than for the five before it.

> **Module layout (0.4.0):** `core/` holds the schedule maths, animation, collision and formwork
> classes; `runtime/` the scene-facing nodes and UI; `editor/` the dock; `ifc/` the optional IFC
> import. File names in the class contracts below map as `<name>.gd` -> `core/` or `runtime/`
> (see `09_GENERICIZATION.md`, "Path mapping").

## System Overview Diagram

```
construction_steps.json (extended schema)
        ↓
SequenceManager._ready()
    ├─ load_json()
    ├─ initialize_parts() → building_parts: Dict[name → Node3D]
    ├─ ConstructionSchedule.new() → resolves parts + dates
    └─ TimelineController.new() → owns virtual clock
        ├─ holds reference to ConstructionSchedule
        ├─ holds reference to building_parts
        └─ instances TimelineUI

User interaction:
  - Drag slider → TimelineUI._on_slider_changed(value) → TimelineController.scrub_to(day)
  - Click Play → TimelineController.play() → _process(delta) advances current_day
  - Both paths → TimelineController.scrub_to(current_day) → ConstructionSchedule.get_part_states(day)
    → returns {part_name → {anim_type, progress}} → AnimationApplier.apply_instant(part, anim_type, progress)
```

---

## Class Contracts & Responsibilities

### `Cadence` (class_name Cadence, static utility)

**Purpose**: Extract the stagger/duration accumulation loop into shared logic so both live-playback and instant-apply use identical cadence math.

**Input**:
```gdscript
static func compute_timings(
  ordered_parts: Array[String],    # sorted part names from SpatialGrouper.sort_by_position()
  action: Dictionary,               # action from construction_steps.json
  anim_duration: float,             # base animation duration (e.g., 1.0 seconds)
  stagger_delay: float              # base stagger delay (e.g., 0.75 seconds)
) -> Array[{part_name: String, offset_sec: float, duration_sec: float}]
```

**Behavior**:
- Extract the `_animate_single` / `_animate_spatial_group` stagger accumulation loop (built in Milestone -1's `sequence_manager.gd`) into this shared class
- Respects `action.stagger_accel`, `action.stagger_min`, `action.dur_accel`, `action.dur_min`
- Returns array of `{part_name, offset_sec, duration_sec}` — each part's start time within the action's window and its animation duration
- Deterministic: given the same inputs, always returns the same result

**Example**:
```gdscript
# 3 walls, base 1.0 sec duration, 0.75 sec stagger, accel 0.95
var timings = Cadence.compute_timings(
  ["Wall1", "Wall2", "Wall3"],
  {"stagger_accel": 0.95, "stagger_min": 0.1, "dur_accel": 0.95, "dur_min": 0.1},
  1.0,
  0.75
)
# Result:
# [
#   {part_name: "Wall1", offset_sec: 0.0, duration_sec: 1.0},
#   {part_name: "Wall2", offset_sec: 0.75, duration_sec: 0.95},
#   {part_name: "Wall3", offset_sec: 1.41, duration_sec: 0.90},
# ]
```

---

### `ConstructionSchedule` (class_name ConstructionSchedule, RefCounted)

**Purpose**: The 4D engine — map "what date is it?" to "what state is each part in?".

**Constructor**:
```gdscript
func _init(
  sequence_data: Dictionary,          # already-parsed JSON
  building_parts: Dictionary,         # name → Node3D
  spatial_grouper: SpatialGrouper     # cached instance from SequenceManager
):
  # Parse dates, bucket parts, resolve cadence for each action
```

**Public API**:

#### `get_date_range() -> {min_day: float, max_day: float}`
- Scans all actions' `start_date` + `duration_days` to find earliest start and latest end
- Returns day-numbers (floats, days since epoch or arbitrary reference date)
- Used to set scrubber slider bounds

**Example**:
```gdscript
var range = schedule.get_date_range()
# {min_day: 0.0, max_day: 30.0}  # 30-day project
slider.min_value = range.min_day
slider.max_value = range.max_day
```

#### `get_part_states(current_day: float) -> Dictionary[String, {anim_type: String, progress: float}]`
- **The core query**: given a day number, return the state of every scheduled part
- For each part:
  - If `current_day < part_start_day`: `{anim_type: "...", progress: 0.0}` (not yet started)
  - If `current_day > part_end_day`: `{anim_type: "...", progress: 1.0}` (fully complete)
  - Otherwise: `{anim_type: "...", progress: (current_day - part_start) / (part_end - part_start)}` (in progress, 0–1)
- Parts not involved in any scheduled action are omitted or returned with `progress: 0` and `visible: false` by convention

**Example**:
```gdscript
var states = schedule.get_part_states(15.5)
# {
#   "Col_1": {anim_type: "install", progress: 0.8},
#   "Col_2": {anim_type: "install", progress: 0.3},
#   "Beam_1": {anim_type: "install", progress: 0.0},
#   ...
# }
```

**Implementation detail**: internally caches resolved action→parts mappings to avoid re-scanning the JSON on every call.

**Seconds→days mapping** (resolved at construction time, in `_init`): `Cadence.compute_timings()` yields per-part offsets/durations in *seconds*, but `get_part_states()` is queried in *day numbers*. The bridge: for each day-bucket, take its cadence span (`span_sec = last offset + last duration`) and normalize every part's window into the bucket's calendar day — `part_start_day = bucket_day + (offset_sec / span_sec) * BUCKET_FILL` (and analogously for `end_day`), with `BUCKET_FILL = 1.0` recommended (animations fill the whole day). This preserves the relative stagger/acceleration shape while stretching it to calendar time. Cadence seconds never escape the constructor; `_part_schedule` stores only day numbers. Bucketing uses floor + remainder distribution (7 parts / 3 days → 3+2+2), not `ceil`.

> **⚠️ As-built deviation**: the shipped `ConstructionSchedule._init()` does **not** partition an action into discrete per-day buckets with independent cadence spans as described above. Instead it normalizes **one continuous cadence curve across the entire multi-day span** — so a 7-part/3-day action doesn't produce hard 3+2+2 day-boundary groupings, it stretches one stagger sequence across the full window. Visually this still preserves stagger order and spreads parts across the date range; it just doesn't match this doc's specific bucketing math or the Milestone 1/5 acceptance examples below (e.g. "21 walls / 3 days → 7+7+7" as *separate buckets*). Flagged as technical debt to revisit before Phase 4 packaging — see `README.md`'s "Known limitations" section.

---

### `AnimationApplier` (class_name AnimationApplier, static)

**Existing API** (unchanged):
```gdscript
static func apply(pt: Tween, part: Node3D, anim_type: String, dur: float)
```

**New API** (instant-apply variants):
```gdscript
static func apply_instant(part: Node3D, anim_type: String, progress: float) -> void
```

where `progress ∈ [0, 1]` represents how far through the animation we are.

**Behavior per animation type** (all using `Tween.interpolate_value` for easing):

##### `scale_up`
- **Start**: `part.visible = false`, `part.scale = Vector3.ZERO`
- **Mid** (progress 0–1): interpolate `part.scale` from `ZERO` to `original_scale` with `TRANS_BACK` + `EASE_OUT`
- **End**: `part.visible = true`, `part.scale = original_scale`

##### `drop_in`
- **Start**: `part.visible = false`, `part.position = original_pos + Vector3(0, 15, 0)` (high up)
- **Mid** (0–1): interpolate `part.position.y` from `original_pos.y + 15` to `original_pos.y` with `TRANS_CUBIC` + `EASE_OUT` (settles without rebounding)
- **End**: `part.visible = true`, `part.position = original_pos`

##### `rise_up`
- **Start**: `part.visible = false`, `part.position = original_pos - Vector3(0, 10, 0)` (below ground)
- **Mid** (0–1): interpolate `part.position.y` from `original_pos.y - 10` to `original_pos.y` with `TRANS_CUBIC` + `EASE_OUT`
- **End**: `part.visible = true`, `part.position = original_pos`

##### `sink_down`
- **Start**: `part.visible = true`, `part.position = original_pos`
- **Mid** (0–1): interpolate `part.position.y` from `original_pos.y` to `original_pos.y - 10` with `TRANS_CUBIC` + `EASE_IN`
- **End**: `part.visible = false`, `part.position = original_pos - Vector3(0, 10, 0)`

##### `fill_up`
- **Start**: `part.visible = true`, `part.scale.y = 0.01`, `part.position.y` adjusted for bottom-pin
- **Mid** (0–1): 
  - `part.scale.y` interpolates from `0.01` to `original_scale.y`
  - `part.position.y` interpolates from start offset to `original_pos.y` (keeps bottom pinned)
- **End**: `part.scale = original_scale`, `part.position = original_pos`
- **Particle burst**: skipped in instant path (it's a play-only side effect). As-built: this gap has now been closed — a boundary-crossing trigger (`TimelineController._detect_fill_up_actions()`) fires the pour burst during forward Play in the timeline system.

##### `fade_in`
- **Start**: `part.visible = true`, `part.scale = original_scale`, `part.position = original_pos`, `material.albedo_color.a = 0.0`
- **Mid** (0–1): interpolate `material.albedo_color.a` from `0.0` to `1.0`
- **End**: `material.albedo_color.a = 1.0`

##### `fade_out`
- **Start**: `part.visible = true`, `material.albedo_color.a = 1.0`
- **Mid** (0–1): interpolate `material.albedo_color.a` from `1.0` to `0.0`
- **End**: `part.visible = false`, `material.albedo_color.a = 0.0`

##### `install` (3-phase: lift 30%, slide 40%, lower 30%)
- **Start**: `part.visible = true`, `part.scale = original_scale`, `part.position = ground_start` (15 units away, ground level)
- **Phase 1** (progress 0–0.3): lift to hover height
  - `part.position.y` interpolates from `ground_start.y` to `hover_height` with `TRANS_SINE` + `EASE_OUT`
- **Phase 2** (progress 0.3–0.7): slide horizontally to final XZ
  - `part.position.xy` interpolates from `ground_start.xy` to `final_pos.xy` with `TRANS_SINE`
- **Phase 3** (progress 0.7–1.0): lower to final position
  - `part.position.y` interpolates from `hover_height` to `original_pos.y` with `TRANS_SINE` + `EASE_IN`
- **End**: `part.position = original_pos`

**Implementation**: use `Tween.interpolate_value(start, delta, progress, 1.0, trans_type, ease_type)` for all interpolations so easing math is identical to live tweens.

> ⚠️ The second argument is the **delta** (`final - initial`), not the final value. Passing the final value only works by accident when the start is zero. See Milestone 2 in `02_ROADMAP_MILESTONES.md` for a correct and an incorrect example.

**`install` data dependency**: the instant path needs each part's `ground_start` (pickup-side starting position, today derived from crane/commander geometry inside `SequenceManager`). Compute it once when `ConstructionSchedule` is built and store it as a part meta (e.g. `install_ground_start`), so `apply_instant` reads it like any other meta and has no runtime dependency on the crane.

---

### `TimelineController` (class_name TimelineController, extends Node)

**Purpose**: Virtual clock + playback state machine. Owns the current date/time and drives scrubbing/playing.

**Members**:
```gdscript
var _construction_schedule: ConstructionSchedule
var _building_parts: Dictionary  # name → Node3D
var _crane: Crane = null

var current_day: float = 0.0
var is_playing: bool = false
var playback_speed: float = 1.0  # days per second (can be < 1 for slow-mo)
var _last_install_action_day: float = -999.0  # to detect day boundary crossings
```

**Public API**:

#### `set_schedule(schedule: ConstructionSchedule, building_parts: Dictionary, crane: Crane = null) -> void`
- Wire up the schedule, parts, and crane (all set after construction)

#### `scrub_to(target_day: float) -> void`
- Clamp `target_day` to `schedule.get_date_range()`
- Call `schedule.get_part_states(target_day)` to get all part states
- For each part in the result, call `AnimationApplier.apply_instant(part, anim_type, progress)`
- Park crane if it was tracking (call `_crane.retract()` if applicable)
- Update internal state so Play knows to recalculate crane swings if resumed

#### `play() -> void`
- Set `is_playing = true`
- Record current `current_day` as the "play start" for crane swing detection

#### `pause() -> void`
- Set `is_playing = false`

#### `set_speed(days_per_sec: float) -> void`
- `playback_speed = days_per_sec`

#### `_process(delta: float) -> void`
- If not playing, return early
- Advance: `current_day += playback_speed * delta`
- Clamp to date range
- Call `scrub_to(current_day)` (unifies scrub and play code paths)
- **Crane swing detection**: (only during Play, not scrub)
  - For each action in schedule with `type == "install"`:
    - If `_last_install_action_day < action_start_day <= current_day`:
      - Action boundary crossed (entering this install window for the first time)
      - Call `_crane.swing(pickup_pos, target_pos, lift_dur, slide_dur, tracked_part)`
      - Set `_last_install_action_day = action_start_day`
  - This mirrors today's behavior: one swing per install action, triggered on first entry during forward play

---

### `TimelineUI` (extends Control, file: timeline_ui.gd)

**Purpose**: Runtime UI — slider, date label, Play/Pause, speed control.

**Scene structure** (`timeline_ui.tscn`):
```
TimelineUI (Control, anchored to top/bottom)
├── HBoxContainer
│   ├── Label (date display)
│   ├── HSlider (min=0, max=100 initially, connects to _on_slider_changed)
│   ├── Button "Play" (toggles is_playing)
│   ├── SpinBox (playback speed, 0.1–5.0x)
│   └── Button "Reset" (scrub_to(min_date))
```

**Implementation**:
```gdscript
extends Control

@onready var _slider: HSlider = ...
@onready var _date_label: Label = ...
@onready var _play_button: Button = ...
@onready var _speed_spinbox: SpinBox = ...

var _timeline_controller: TimelineController = null

func _ready():
  _slider.value_changed.connect(_on_slider_changed)
  _play_button.pressed.connect(_on_play_pressed)
  _speed_spinbox.value_changed.connect(_on_speed_changed)

func set_timeline_controller(controller: TimelineController, schedule: ConstructionSchedule):
  _timeline_controller = controller
  var range = schedule.get_date_range()
  _slider.min_value = range.min_day
  _slider.max_value = range.max_day
  _slider.value = range.min_day

func _on_slider_changed(value: float):
  if _timeline_controller:
    _timeline_controller.scrub_to(value)
    _timeline_controller.pause()  # auto-pause when manual scrub
    _update_display()

func _on_play_pressed():
  if _timeline_controller:
    _timeline_controller.is_playing = not _timeline_controller.is_playing
    _play_button.text = "Pause" if _timeline_controller.is_playing else "Play"

func _on_speed_changed(value: float):
  if _timeline_controller:
    _timeline_controller.playback_speed = value

func _process(_delta):
  if _timeline_controller:
    # set_value_no_signal() is mandatory here: plain `_slider.value = ...` emits
    # value_changed, which calls _on_slider_changed → pause(), so playback would
    # self-pause one frame after pressing Play.
    _slider.set_value_no_signal(_timeline_controller.current_day)
    _update_display()

func _update_display():
  if _timeline_controller:
    var day = _timeline_controller.current_day
    _date_label.text = _format_day(day)

func _format_day(day_num: float) -> String:
  # Convert day number back to YYYY-MM-DD (if dates are used)
  # or "Day X" (if using step-based numbering)
  ...
```

**Design rationale**: Minimal UI, talks *only* to `TimelineController` (not directly to schedule/parts). This ensures an EditorPlugin dock can reuse the same `TimelineController` without reimplementing UI logic.

---

### `SequenceManager` (extends Node3D, refactored)

> **Input-shape assumption, satisfied for IFC too now**: everything below assumes parts
> arrive as a flat container of nodes, each carrying its placement in its own transform —
> what a `.glb` import gives you directly, and what an IFC model loaded via GDIFC does
> *not* (nested hierarchy, identity transforms, geometry offset baked into mesh
> vertices). `GDIFC4DAdapter` (`ifc/gdifc_4d_adapter.gd`) now sits in front of
> `SequenceManager` for the IFC case, producing exactly this shape before
> `initialize_parts()` ever runs; the one guard change `initialize_parts()` itself needed
> (mesh-less container nodes) is also done. See `05_IFC_INTEGRATION.md`.

**What stays**:
- `load_json()`: loads `construction_steps.json`
- `initialize_parts()`: populates `building_parts`, sets metas, duplicates materials
- `make_materials_unique()`: duplicates materials for per-part fade/color control
- `_get_local_aabb()`: computes bounding boxes

**What's removed**:
- `_animate_single()` and `_animate_spatial_group()`: tween-building logic (replaced by `Cadence` + `ConstructionSchedule`)
- `play_next_step()`, `play_all_steps()`: auto-play loop (replaced by `TimelineController`)
- `_has_future_install_steps()`: no longer needed

**What's added**:
```gdscript
func _ready():
  load_json()
  _generate_formwork()
  initialize_parts()
  # Explicit wiring (plugin-safe): the crane is referenced via an exported
  # NodePath instead of get_tree().current_scene.find_child(), which
  # 03_PLUGIN_DISTRIBUTION.md forbids (it assumes a specific scene layout).
  _crane = get_node_or_null(crane_path) as Crane  # @export var crane_path: NodePath
  
  # NEW: Build 4D tool
  var schedule = ConstructionSchedule.new(sequence_data, building_parts, _spatial_grouper)
  var timeline_controller = TimelineController.new()
  timeline_controller.set_schedule(schedule, building_parts, _crane)
  add_child(timeline_controller)
  
  # NEW: Attach UI
  var ui = preload("res://timeline_ui.tscn").instantiate() as TimelineUI
  add_child(ui)
  ui.set_timeline_controller(timeline_controller, schedule)
  
  # Scrub to start state
  timeline_controller.scrub_to(schedule.get_date_range().min_day)
```

---

## JSON Schema Extension

### Before (current structure)
```json
{
  "steps": [
    {
      "index": 1,
      "actions": [
        {
          "type": "install",
          "commander_prefix": "Col_",
          "child_prefixes": ["Rebar_Col"],
          "stagger": 1.02,
          "stagger_accel": 0.95,
          "stagger_min": 0.11,
          "dur": 1,
          "dur_accel": 0.95,
          "dur_min": 0.1
        }
      ]
    },
    ...
  ]
}
```

### After (4D-aware structure)
```json
{
  "steps": [
    {
      "index": 1,
      "actions": [
        {
          "type": "install",
          "commander_prefix": "Col_",
          "child_prefixes": ["Rebar_Col"],
          "start_date": "2025-03-01",
          "duration_days": 1,
          "stagger": 1.02,
          "stagger_accel": 0.95,
          "stagger_min": 0.11,
          "dur": 1,
          "dur_accel": 0.95,
          "dur_min": 0.1
        }
      ]
    },
    {
      "index": 2,
      "actions": [
        {
          "type": "install",
          "commander_prefix": "Beam_",
          "child_prefixes": ["Rebar_Beam"],
          "start_date": "2025-03-02",
          "duration_days": 3,
          "stagger": 1.02,
          "stagger_accel": 0.90,
          "stagger_min": 0.11,
          "dur": 1,
          "dur_accel": 0.90,
          "dur_min": 0.1
        }
      ]
    },
    ...
  ]
}
```

**New fields** (per action):
- `start_date`: ISO 8601 date string (YYYY-MM-DD), or `null` to skip this action during 4D playback
- `duration_days`: float, how many calendar days the action spans (default: 1 if omitted)

**Backwards compatibility**: if `start_date` is missing, treat the action as instantaneous in the 4D timeline (all parts animate at day 0), and use only sequential ordering for cadence.

---

## State Consistency & Correctness

### The "Single Source of Truth" Pattern

**Problem**: With tweens, state lives in the tween itself. Scrubbing must recompute state from scratch without tweens. These two paths must never diverge visually.

**Solution**: `ConstructionSchedule.get_part_states()` is the *only* place that decides "what state is this part in?" — both Play and scrub call it.

1. **During Play**: `_process(delta)` → advance `current_day` → call `scrub_to(current_day)` → call `get_part_states()` → apply instantly
2. **During Scrub**: slider → call `scrub_to(target_day)` → call `get_part_states()` → apply instantly

Both paths are identical code. The only difference is how `current_day` is set (automatically vs. manually).

### No Leftover Tween State

**Risk**: old tweens still running from previous scrubs, overlaying state on top of instant-applied state.

**Mitigation**: `TimelineController.scrub_to()` does **not** create tweens. It only calls `apply_instant()`, which sets properties directly. There are no tweens to leak.

### Crane Parking

**Risk**: crane arm is mid-swing during scrub; we jump to a date; crane is now stuck in a weird orientation.

**Mitigation**: `scrub_to()` calls `_crane.retract()` to park the crane. **`retract()` is a NEW method** (written in Milestone -1; it does not exist in the original `crane.gd`, which only has `swing()` and per-frame tracking) that tweens arm/hook/rope back to neutral. Only call it on manual scrubs/jumps — calling it on every `_process`-driven `scrub_to()` during Play would prevent the crane from ever swinging. This is a play-only side effect and fine for Phase 1.

> **As-built confirmation**: this limitation shipped exactly as designed and is still current — the crane parks on every manual scrub/jump and swings once per install unit during forward Play; it does not "chase" a scrubbed-to state. The "Phase 2/3 may add smarter chase behavior" possibility mentioned above has not been picked up.

---

## Extensibility for Phases 2–4

### Phase 2 (Collision Detection)
- `ConstructionSchedule.get_part_states()` returns each part's state; Phase 2 adds collision queries at each scrubbed point
- New method: `ConstructionSchedule.get_collisions(current_day: float) -> Array[{part1, part2, overlap_volume}]`
- Timeline UI adds visual indicator (red zone on slider for collision days)
- **Implementation caution**: `Area3D.get_overlapping_bodies()` only updates after a physics tick — teleporting parts during a scrub and querying overlaps the same frame returns stale results. Prefer direct space-state queries (`PhysicsDirectSpaceState3D.intersect_shape()`) or plain AABB intersection math on the parts' transformed bounding boxes, both of which work synchronously with instant-applied state.

> **✅ As-built** (see `README.md`'s "Collision detection" section for full detail): shipped as `ConstructionSchedule.get_collisions(day, building_parts)` using exactly the `PhysicsDirectSpaceState3D.intersect_shape()` alternative this doc names above — not `Area3D`, and not plain AABB either (an AABB-based version was tried first but replaced: axis-aligned boxes are a loose fit for diagonal/rotated members, e.g. bridge beams, producing false-positive flags on near-misses). Each `MeshInstance3D` part gets a `ConvexPolygonShape3D` hull (`Mesh.create_convex_shape()`) registered as a raw `PhysicsServer3D` area (no `Area3D` scene nodes) on a dedicated collision layer; `get_collisions()` pushes each visible part's live transform to its area via `area_set_transform()` immediately before querying, avoiding the tick-lag `Area3D.get_overlapping_bodies()` would have. Scope was narrowed further than sketched here: only in-transit (mid-`install`) parts are checked as movers, commander+child sibling groups are excluded from flagging each other, only parts with a buildable convex hull participate, and results are deduplicated/reported at the commander level (tracked via `_sibling_groups` / `_part_to_commander`). `get_collisions()` entries still carry `overlap_aabb`/`overlap_volume`, but these are now an AABB-intersection *approximation* of the exact-shape hit (`intersect_shape()` answers "do they overlap", not "by how much") — used only to size the live 3D marker (`CollisionVisualizer`) and break ties among a commander pair's leaf hits, not for the collision boolean itself, which is exact. **Update (trimesh hybrid)**: convex hulls alone couldn't represent concave geometry (an L-bracket, a cut-out) exactly, over-including the concave region as solid. Since concave targets became common in practice (bridge beams with notches/cutouts), each part now also gets a `ConcavePolygonShape3D`/trimesh (`Mesh.create_trimesh_shape()`), registered as the area's shape (the exact target geometry any *other* mover queries against); the convex hull is kept separately and used only as the query shape when that part is itself the mover — Godot's physics engine still doesn't support concave-vs-concave queries, but convex-vs-concave is supported, so this combination is both exact and within engine limits. A related bug was fixed at the same time: `get_collisions()` only synced live transforms for currently-active parts before querying, but didn't filter query *hits* the same way — a part that hadn't started yet kept its area at the default world-origin transform, so a mover sweeping near the origin could register a phantom collision against a part that wasn't really there. **Update**: pause-on-collision during Play and the slider hover tooltip are now both built (Phase 2 is complete except one item — see below). **Not built**: crane geometry isn't in the collision system (only `building_parts` are checked); deliberately deferred, not attempted.

### Phase 3 (EditorPlugin)
- `EditorPlugin.gd` creates an instance of `ConstructionSchedule` and `TimelineController` in the editor scene
- Editor dock instantiates `timeline_ui.gd` (or a variant) and connects to the `TimelineController`
- No changes to core logic; just a new front-end

### Phase 4 (Plugin Distribution)
- Copy Phase 1–3 files into `addons/construction_4d_tool/`
- Add `plugin.cfg` metadata
- Add `addon_entry.gd` (EditorPlugin entry point for Phase 3)
- Bundle examples
- GitHub release with `.pck` or source distribution

All require only *additions*, not modifications to existing Phase 1 architecture.

---

## Performance Considerations

### `get_part_states()` Caching
- Internal cache keyed by the day number quantized to an **integer** key: `int(round(current_day * 100.0))`. Do NOT key the dictionary by a rounded float — GDScript compares float keys by exact bits, so precision drift (`1.01` stored as `1.0100000381...`) silently defeats the cache
- Cache invalidates only if JSON is reloaded
- Expected: O(num_actions + num_parts) on first call per day, O(1) on cache hit
- **Honest expectation**: during continuous Play, `current_day` yields a new key nearly every frame, so the cache is mostly missed — acceptable because the uncached query is cheap. The cache pays off for repeated same-day queries (paused UI, Phase 2 collision scans). Bound the cache (LRU or hard cap) so long scrub sessions don't accumulate tens of thousands of entries.

### Material Duplication
- Done in `initialize_parts()` (built in Milestone -1)
- Ensures per-part alpha/color fades don't affect other parts
- Phase 1 unchanged — fine at the < 500-part scope (note: Godot 4 issues one draw call per `MeshInstance3D` regardless of material sharing, so duplication does not "break batching"; its real costs are memory, render-state sorting, and foreclosing future MultiMesh strategies)
- **Scaling path (10k+ parts, Phase 2+)**: replace duplicated `StandardMaterial3D`s with a shared custom `ShaderMaterial` using **instance shader parameters** (`instance uniform float fade_alpha` in the shader, set per part via `GeometryInstance3D.set_instance_shader_parameter()`). One shared material, per-instance alpha. Caveats: requires writing a shader (loses StandardMaterial3D conveniences), and instance uniforms are only supported in the Forward+ and Mobile renderers — not Compatibility

### Rendering Cost
- No change from today: same 3D geometry, same number of draw calls
- Instant-apply sets properties directly; no performance cliff vs. tween-based playback

### Worst-case Timeline
- 500 parts, 365 days, scrubbing at 60 FPS: `500 × 60 ≈ 30k state updates/sec`
- `get_part_states()` is O(parts), so `30k × const ≈ sub-millisecond on modern hardware`
- Should comfortably hit 60 FPS
- **If scrubbing ever stutters**: the likely cost is not the state math but writing 500 `Node3D` transforms per frame (each write dirties Godot's internal transform tree). Contingency: have `scrub_to()` skip parts whose `{anim_type, progress}` is unchanged since the previous application — most parts sit at a stable 0.0 or 1.0 at any given day, so the dirty set is typically small (see Milestone 7)

---

## Error Handling & Validation

### Invalid Dates
- If `start_date` cannot be parsed, log a warning and treat as `date 0` (epoch)
- If `duration_days` is 0 or negative, clamp to `1`

### Missing Parts
- If a part referenced in an action doesn't exist in `building_parts`, log a warning and skip
- Animation continues for parts that do exist

### JSON Parse Errors
- Existing `load_json()` already handles this via `JSON.new().parse()`
- No changes needed

---

## Testing Strategy (See Milestones Doc)

See `02_ROADMAP_MILESTONES.md` for detailed per-milestone test criteria and acceptance thresholds.
