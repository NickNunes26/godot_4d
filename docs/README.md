# 4D Construction Tool

*Using the tool rather than changing it? Read the step-by-step guide instead:
[GUIDE.md](../GUIDE.md) (English) · [GUIA.md](../GUIA.md) (español).*

**Release 0.4.0** is the first standalone, self-contained addon. Layout: `core/` (schedule maths,
animations, collision, formwork), `runtime/` (SequenceManager, controller, UI, cranes, cameras),
`editor/` (dock, inspector, CSV/XML I/O), `ifc/` (optional IFC import), `examples/`, `tests/`.
The history below ("Phase 1/2/3") describes the original build order; `09_GENERICIZATION.md`
records the generalisation work.

Status: **Phase 1 complete** (Milestones -1 through 8), **Phase 2 complete** except
crane geometry (in-transit collision detection via exact shape queries, a live
warning indicator, pause-on-collision during Play, a full-schedule collision scan +
report with a hoverable slider overlay, and a live 3D collision marker; see below),
**Phase 3 in progress** (an `EditorPlugin` dock with live in-editor scrubbing,
`units_per_day` frequency-based duration entry, finish-to-start action dependencies with
multiple predecessors and explicit action ids (`id`/`depends_on`/`lag_days`), an
Anchor-driven Start/Duration/End trial-and-fit scheduling system, a schedule
inspector panel (id/type/anchor/start/end date/duration_days/units_per_day/depends_on/
lag_days editing, a Recalculate button so field edits don't rebuild on every keystroke,
+ JSON save/reload), CSV export/import of the same scheduling fields (id-matched,
round-trips through spreadsheet/Gantt tools), and Microsoft Project XML export/import
(id-matched with a persisted, self-healing task→action mapping and a one-time manual-mapping
fallback for foreign files, including multi-action phase groups for a single external task
that corresponds to several internal actions; see below — not the legacy binary `.mpp`
format, which isn't feasible to support directly) are built,
plus **multi-crane support** (outside the phased roadmap — any number of cranes,
auto-discovered, nearest-by-distance assignment with an explicit `crane_id` override;
see below), a **free-fly spectator camera** (also outside the phased roadmap, purely a
debugging/inspection convenience), and a **movie mode date label** that ensures the timeline date is visible during video recording without the overhead of the full UI.

**Formwork (encofrado)** is the current work, specified in `07_FORMWORK.md` and outside the
phased roadmap like multi-crane and IFC input. An action's window splits into a formwork
phase and the pour that follows it, with forms assembled around each element, held through
the pour, and stripped afterwards — generated as a generic wood slab, instanced from a panel
asset, or taken from the scene's own geometry. **Steps 1–5 of its six-step build order are
built**, so it is authorable from the dock; only the generator rule is open. See
"Formwork (encofrado)" below for what works today.

See `CHANGELOG.md` for a session-by-session log of
what changed and why, `02_ROADMAP_MILESTONES.md` for the
Phase 1 milestone history, and the other files in this folder for the original design
docs this implementation follows.

**Where things live.** This file is the as-built source of truth and sits in
`addons/construction_4d_tool/docs/`, alongside the five original design docs
(`00`–`04`) and the two later feature specs (`05`–`07`). Runtime code is in `runtime/`; editor-side (dock, inspector, CSV and
Project XML I/O) is in `addons/construction_4d_tool/`. Paths in this document are
relative to the project root unless they name a sibling `.md`, which is relative to
this folder.

| Document | What it covers |
|---|---|
| `README.md` (this file) | As-built status, data model, every shipped subsystem |
| `00_4D_TOOL_OVERVIEW.md` | Original vision and the Phase 1–4 split |
| `01_ARCHITECTURE.md` | Class contracts and data flow, with as-built callouts |
| `02_ROADMAP_MILESTONES.md` | Phase 1 milestone history and acceptance criteria |
| `03_PLUGIN_DISTRIBUTION.md` | Packaging, distribution channels, anti-patterns |
| `04_API_REFERENCE.md` | Method signatures and parameters |
| `05_IFC_INTEGRATION.md` | Driving the tool from a GDIFC-imported IFC model |
| `06_PLANNED_FEATURES.md` | The five feature specs — **all now built**; kept for the reasoning |
| `07_FORMWORK.md` | Formwork (encofrado) spec — decisions + build order; steps 1–5 + 7 built |
| `08_POUR_STREAM.md` | Concrete pour stream — making it optional and tunable |
| `09_GENERICIZATION.md` | Generalisation status — what was made generic, what was left, what is open |
| `CHANGELOG.md` | Notable changes per release |

## What this is

A Godot 4 tool that turns a sequential, tween-based construction animation into a
scrubbable, date-aware 4D timeline: drag a slider to any calendar day and the building
snaps instantly to its state on that day, or hit Play to watch construction unfold.

## Quick start

1. Open `examples/demo.tscn`, or any scene with the same structure: a
   `SequenceManager` node with `runtime/sequence_manager.gd` attached, a container of named
   parts as its child at `parts_container_path` (`@export NodePath`, **required, no
   default** — point it at whatever node holds your model's parts), and
   optionally any number of sibling `crane.gd`-scripted nodes, auto-discovered.
   **Loading parts from an IFC file instead of a `.glb`?** The container that
   `parts_container_path` expects doesn't exist until the GDIFC dock's import builds it
   (the dock's **Load IFC (4D)** button, which needs the separate GDIFC addon enabled in
   Project Settings → Plugins) — see `05_IFC_INTEGRATION.md` before anything else.
2. Run the scene. `SequenceManager._ready()` loads `construction_steps.json`, builds a
   `ConstructionSchedule`, and mounts a `TimelineController` + `TimelineUI` automatically
   — no manual wiring needed.
3. Use the UI bar at the top: drag the **slider** to scrub, **Play/Pause** to run time
   forward, the **speed spinbox** to change how many schedule-days pass per real second
   (default 1.0), **Reset** to jump back to day 0.
4. **Camera**: left-click in the 3D viewport to capture the mouse and fly around
   (WASD move, mouse to look, Shift to sprint, Q/E down/up), Escape to release the
   mouse back to the UI. See `free_look_camera.gd`, attached to the scene's `Camera3D`.

## Data model

Each action in `construction_steps.json` optionally carries:
- `start_date`: `"YYYY-MM-DD"` — when this action begins in the project calendar
- `duration_days`: how many calendar days it's scheduled to span (default 1, clamped
  to >= 1)
- `units_per_day`: alternative to `duration_days` — a rate (e.g. `2` for "2 columns/
  day") that `ConstructionSchedule` derives `duration_days` from:
  `ceil(unit_count / units_per_day)`, where `unit_count` is the number of installable
  units in the action (commanders for a `commander_prefix` action, matching parts for
  a `target_prefix` action). Only used when `duration_days` is absent — an explicit
  `duration_days` always wins, so this is purely a convenience on top of the existing
  schema (`ConstructionSchedule._resolve_duration_days()`), not a breaking change.
- `id`: an optional explicit identifier for this action, so other actions can
  `depends_on` it by name instead of by geometry prefix. Resolution order
  (`ConstructionSchedule._action_id()`, `static`): `id` if present, else
  `commander_prefix`, else `target_prefix`, else `""`. Actions were originally
  identified purely by prefix; `id` exists for actions that share a prefix, or a future
  action with no matching parts yet (e.g. a milestone), or simply when a more readable
  name is wanted for CSV/authoring purposes than a geometry prefix provides.
- `depends_on`: a finish-to-start dependency — this action can't start until the
  referenced action(s) finish. Accepts either a single id string (the original schema)
  or an array of id strings (`ConstructionSchedule._depends_on_ids()`, `static`, accepts
  both) for **multiple predecessors** — "beams can't start until every column unit
  AND every slab unit is installed." With multiple predecessors, this action's start
  is the *latest* of every resolved predecessor's finish day (+ `lag_days`, applied
  uniformly to all of them, not per-predecessor — see below). Only consulted when
  `start_date` is absent on this action; an explicit `start_date` always wins over
  `depends_on`, the same precedence rule `units_per_day` already follows against
  `duration_days`. An id that can't be resolved (typo, or part of a dependency cycle) is
  warned about individually and simply excluded from the "latest" calculation — it
  doesn't block the other predecessors from being honored.
- `lag_days`: days after the (latest, if multiple) `depends_on` predecessor finishes
  before this action starts (default 0). Ignored if `depends_on` is absent. Can be
  **negative** — a lead/overlap, starting before the predecessor finishes (e.g. formwork
  stripping starting partway through a pour). `_resolve_action_start_day()` just adds it
  with no sign restriction; the inspector's Lag (days) spinbox has no lower bound
  either, only `0` is treated as "unset." Applied once, uniformly, to whichever
  predecessor ends up being the latest — not a separate lag per predecessor (a real CPM
  tool would support that; it wasn't asked for here, and it would need each dependency
  edge to carry its own lag rather than one scalar per action).
- `batch`: whether this action's parts move **together** (`true`) or **one after another**
  (`false`, the default). See "Per-action cadence" below — this is the difference between
  a concrete pour split into four meshes for modelling convenience and four columns that
  are genuinely erected one at a time.
- `crane_id`: only relevant to an `install`-type action with 2+ cranes in the scene —
  overrides `ConstructionSchedule`'s default nearest-by-distance crane assignment,
  matched against a `Crane` node's own `.name`. An id that doesn't match any crane in
  the scene is warned about once and falls back to nearest-by-distance rather than
  blocking. See "Multi-crane support" below.

Two lists live at the **root** of `construction_steps.json`, siblings of `"steps"` rather
than fields on an action — see "Static and excluded geometry" below:
- `static_prefixes`: parts that are present from the first frame and never animate
- `excluded_prefixes`: parts hidden for the whole run and left out of the tool entirely

An action's finish day, for a dependent to resolve `depends_on` against, is simply
`action_start_day + duration_days` — the cadence normalization inside
`ConstructionSchedule._init()` already guarantees the last-processed part's
`part_end_day` reaches exactly that value, so no separate per-part bookkeeping is
needed. Actions are processed in dependency order (a topological sort over `depends_on`
edges, `ConstructionSchedule._topo_order_actions()`), not JSON order, so every
predecessor's finish day is known before a dependent needs it. A dependency cycle is
warned about (`push_warning`) and broken by falling back to `start_date`/day 0 for the
actions involved — it never raises or hangs.

`ConstructionSchedule` keeps `_min_epoch` (day 0's real-world unix epoch) and each
action's resolved `_action_start_days`/`_action_finish_days` as instance state (set once
in `_init()`, previously local/discarded), exposed via `get_action_day_range(action_id)`
→ `{start_day, finish_day}` and `day_to_date_string(day)` → a real `"YYYY-MM-DD"` for any
relative day number. Added so the Phase 3 dock's inspector can show a Depends On row's
*actual resolved* End Date, not just do local `start_date + duration_days` arithmetic
(which only works when a literal `start_date` exists) — see the inspector's Anchor/End
Date section below. `parse_date_to_epoch()`/`format_epoch_as_date()` (both `static`) are
the epoch↔date-string conversions those rely on, extracted from what was inline in
`_resolve_epoch()`.

Day 0 in the timeline is normalized to the earliest `start_date` across all actions —
it is **not** the unix epoch. `duration_days` (explicit or derived from `units_per_day`)
directly controls how long `ConstructionSchedule.get_part_states()` takes to move a
part's `progress` from 0 to 1; it's a planning input, not a cosmetic label, so if a
pour or install feels too slow/fast on the timeline the fix is editing this field, not
the animation code.

Missing `start_date`/`duration_days` fall back to day 0 / 1 day respectively, so
pre-4D JSON files still load without changes (see `01_ARCHITECTURE.md`,
"Backwards Compatibility"). Files with no `depends_on` fields are entirely unaffected by
that logic (identical output to before it existed).

## Architecture at a glance

```
construction_steps.json → ConstructionSchedule → TimelineController → AnimationApplier.apply_instant()
       (+ static_prefixes                                  ↕
          / excluded_prefixes,                        TimelineUI (slider/Play/speed)
          read by SequenceManager)                         ⋮
                                                     CameraDriver ← camera_track.json
                                                     (movie mode only; TimelineUI and
                                                      CollisionVisualizer are not built
                                                      there, CameraDriver only is)
```

**File split (2026-08-18):** `construction_schedule.gd` and the Phase 3 dock's
`timeline_dock.gd` had each grown to mix multiple concerns in one file (699 and 1109
lines respectively). Split along existing seams, composition rather than inheritance
(all `RefCounted`, owned as plain instances by whichever class already used them) --
no public API changed:
- `core/collision_query.gd` (`class_name CollisionQuery`): Phase 2 collision
  shape setup/registration and the exact-geometry query, owned by
  `ConstructionSchedule` as `_collision_query`. `ConstructionSchedule.get_collisions()`
  still exists with the same signature, now just computing `get_part_states()` and
  delegating to `_collision_query.query()`.
- `addons/construction_4d_tool/editor/schedule_inspector.gd` (`class_name
  ScheduleInspector`): the inspector grid (10 columns at the time of the split, 13
  today) -- building rows, Anchor/Start/
  End/Duration/Units math, every field's edit handler. This was `timeline_dock.gd`'s
  single biggest concern, and the file `03_PLUGIN_DISTRIBUTION.md`'s original
  planning doc already anticipated as its own file.
- `addons/construction_4d_tool/editor/schedule_csv_io.gd` (`class_name
  ScheduleCsvIO`): CSV export/import's read/write/matching logic (the
  `EditorFileDialog` itself stays in `timeline_dock.gd`, since it needs a `Node` to
  parent it to).
- Three composite date-math helpers (`end_date_from_start_and_duration()`,
  `duration_from_start_and_end()`, `start_date_from_end_and_duration()`) moved onto
  `ConstructionSchedule` as `static` functions, alongside the `parse_date_to_epoch()`/
  `format_epoch_as_date()` they build on -- both `ScheduleInspector` and
  `ScheduleCsvIO` need the same "Start + Duration = End" arithmetic, so centralizing
  it there avoided duplicating it in each.

That split took `timeline_dock.gd` to ~380 lines and `construction_schedule.gd` to ~510.
Both have grown since — ~675 and ~605 today, from Project XML import/export, the camera
capture button, and the five features below — but along the same seams: the dock still
owns `ScheduleInspector`/`ScheduleCsvIO`/`ScheduleProjectXmlIO` as plain instances and
holds only lifecycle, target detection and button wiring.

`ConstructionSchedule.get_part_states(day)` is the single source of truth for "what
does the building look like on day X" — both scrubbing and Play route through it, so
they can never visually diverge. See `01_ARCHITECTURE.md` for the full class
contracts.

## Multi-crane support

Any number of `Crane`-scripted nodes can exist in one scene — built for bridge-style
projects (diagonal beams, spans far enough apart that one crane can't reasonably reach
all of them), where a single fixed crane was never going to be enough. `crane.gd` itself
needed **zero changes** for this: every `Crane` instance was already fully self-contained
(no shared/static state, only reads its own `Arm`/`Track`/`Hook`/`Rope`/`PickupZone`
children), so instantiating several was already safe — the actual work was entirely in
how `SequenceManager`/`ConstructionSchedule`/`TimelineController` discover, assign, and
drive multiple cranes instead of assuming exactly one.

**Discovery**: `SequenceManager._resolve_cranes()` auto-discovers every `Crane`-scripted
node anywhere in the scene (script-identity match, not a fixed relative path or node
name — the same anti-pattern this codebase has avoided since `SequenceManager` first
resolved a single crane via an exported `NodePath` rather than
`get_tree().find_child()`). An optional `crane_paths: Array[NodePath]` export overrides
this for the rare case auto-discovery picks up something that shouldn't be wired in (a
decorative/preview crane prop), or when explicit control is wanted. Cranes are keyed by
node `.name` in the `Dictionary` (`crane name → Crane`) passed to
`ConstructionSchedule.new()` and `TimelineController.set_schedule()` — two cranes sharing
a name collide (last one found wins), so give each a distinct name, the same expectation
building parts already have via their prefixes.

**Assignment**: which crane services which install unit is decided once, per commander,
inside `ConstructionSchedule._init()` — `_assign_crane()` picks whichever crane's own
`global_position` is nearest by **horizontal (XZ) distance** to the commander's world
position (a crane's reach is fundamentally a radial/horizontal limit; height differences
between crane base and part don't factor in). This can't be hoisted above the per-action
loop: a widely-spread project (a bridge with roughly one crane per span) can have
different commanders in the *same action* nearest to different cranes. An action's
optional `crane_id` field (see Data model, above) overrides the auto-pick; an
unresolvable `crane_id` is warned about once and falls back to nearest-by-distance rather
than blocking, the same "warn and use the sensible default" posture `depends_on`/`id`
resolution already takes elsewhere in this class. Each `_install_units` entry now carries
the resolved `crane_id` (`""` when `cranes` was empty at schedule-build time — e.g. the
Phase 3 dock's editor preview, which deliberately previews with no crane at all);
`TimelineController._detect_install_actions()` looks that id up in its own `_cranes`
Dictionary and simply skips a unit whose id doesn't resolve to a live crane, the same way
it already skipped everything when there was no crane at all pre-multi-crane.

**Pickup position**: `Crane.get_pickup_position(target_pos)` replaces the old hardcoded
`target + Vector3(15, 0, 0)` math that used to live in `ConstructionSchedule` — if the
assigned crane has an optional `PickupZone` child node (searched recursively, same
pattern as `Arm`/`Track`/`Hook`/`Rope`), every install unit that crane services shares
that single fixed world point as its staging area, matching how a real crane has one
material laydown zone rather than parts materializing next to wherever they'll be
installed. This is visually fine even with many parts staged at the same point
simultaneously, since a staged-but-not-yet-installed part is invisible/zero-scale (see
`SequenceManager.initialize_parts()`) until its own turn. A crane with no `PickupZone`
falls back to exactly the old `target + (15, 0, 0)` formula, so an existing single-crane
scene with no `PickupZone` node keeps working completely unchanged.

**Scope note**: crane arm/hook/rope geometry still isn't part of collision detection
(`get_collisions()` only checks `building_parts`) — a two-crane clash scenario isn't
covered, same gap that existed pre-multi-crane, now with the added case of two cranes'
own geometry potentially clashing with each other. Deliberately deferred to a follow-up,
not attempted in this pass.

## Camera

`free_look_camera.gd` is attached to the scene's existing `Camera3D` node (as in
`examples/demo.tscn`) — no new node, no wiring through `SequenceManager`. It's
independent of everything else here (doesn't touch `TimelineController`, parts, or
collisions) and would work in any scene with a `Camera3D`.

**No camera in the scene.** A scene built from the documented steps (a `SequenceManager` and an
imported model) has no `Camera3D`, and used to run as an empty grey screen under a working
timeline. `SequenceManager._ensure_view()` now runs at the start of `_ready()` at runtime, before
any part is hidden or moved. It adds, as children of the `SequenceManager`, only what the scene
lacks:

- a `Camera3D` with this script, framed on where the work is: `_action_box()`, the per-axis span
  of the middle 80 % of part centres (from `collect_part_nodes()`) grown by half the median part
  size. It looks from the south-east and above, at 1.6× that box's radius, with `far` at 3000 m or
  more and `move_speed` scaled to it. Framing the whole model's box let the outermost parts (a
  boundary wall, corner trees, a crane) push the camera back until the building was small in the
  middle of the picture: 74 m out on the Galicia sample, 31 m now;
- a `WorldEnvironment` with a procedural sky, when the world has no environment and the project
  sets no default one;
- a `DirectionalLight3D` with shadows, when the tree has no directional light (a `GeoSun`
  counts).

It prints `SequenceManager: the scene has no ... of its own -- added a default one for this run.`
Nothing is saved into the scene, the editor preview is untouched, and a scene that has any of
these keeps its own. Movie mode's `CameraDriver` drives the added camera like any other.

**In movie mode it is switched off** and `CameraDriver` takes the same node over — see
"Camera keyframes" below. Interactive sessions, which is everything else, behave exactly
as described here.

- **Left-click** anywhere in the 3D viewport to capture the mouse and start flying.
- **WASD** to move (forward/back/strafe, relative to where the camera is facing),
  **Q/E** for down/up, **Shift** to sprint (`sprint_multiplier`, default 3x).
- **Mouse movement** to look around (yaw/pitch, pitch clamped to ±89° to avoid the
  gimbal flip at ±90°); roll is dropped once at `_ready()` so looking around never
  introduces unwanted tilt regardless of how the camera's transform was authored in
  the editor.
- **Escape** releases the mouse back to the OS cursor (`Input.MOUSE_MODE_VISIBLE`) so
  the `TimelineUI` buttons/slider are clickable again.

Movement/look speed are `@export`ed (`move_speed`, `vertical_speed`,
`mouse_sensitivity`, `sprint_multiplier`) — tweak them in the Inspector on the
`Camera3D` node rather than editing the script. Input is read via
`_unhandled_input()`, not `_input()`, specifically so a click already consumed by a
`TimelineUI` `Control` (a button, the slider) never falls through and triggers mouse
capture.

## Collision detection (Phase 2, complete except crane geometry)

`ConstructionSchedule.get_collisions(day, building_parts)` flags parts actively
mid-`install` (0 < progress < 1 — lifting/sliding/lowering) whose actual mesh
geometry overlaps any other currently-present part's actual mesh geometry, using
a synchronous `PhysicsDirectSpaceState3D.intersect_shape()` query: the in-transit
mover's convex hull against every other part's exact triangle-mesh (trimesh) shape.

**Not AABB, and not `Area3D`.** An earlier version used axis-aligned bounding-box
intersection, which is fine for box-like parts but produces false-positive flags
for diagonal/skewed members (e.g. bridge beams not aligned to X/Z) whose AABB is
much larger than their actual footprint — for projects where near-miss noise
would bury real clashes, that wasn't acceptable. `Area3D.get_overlapping_bodies()`
was also ruled out since it lags a physics tick behind teleported/instant-applied
parts. The shipped approach instead: `CollisionQuery.setup()` (`collision_query.gd`,
owned by `ConstructionSchedule` as `_collision_query` — see "File split" above) builds both a
`ConvexPolygonShape3D` (via `Mesh.create_convex_shape()`) and a
`ConcavePolygonShape3D`/trimesh (via `Mesh.create_trimesh_shape()`) per
`MeshInstance3D` part, and registers the **trimesh** as a raw `PhysicsServer3D`
area (not an `Area3D` node — no scene tree footprint) in the scene's own physics
space, on a dedicated collision layer. The convex hull is kept as a plain
`Resource`, not registered to any area — it's used only as the *query* shape when
that part is itself the mover, since Godot's physics engine doesn't support a
concave shape as a query parameter (concave-vs-concave isn't supported; convex-vs-
concave is). Every `get_collisions()` call pushes each currently-visible part's
live transform to its area via `area_set_transform()` immediately before querying,
so there's no tick lag. This assumes physics runs on the main thread (Godot's
default — leave "Physics > 3D > Run on Separate Thread" off, or same-frame
transform pushes won't be visible to the query yet).

**Convex hull vs. exact trimesh**: the mover always queries with its own convex
hull (exact for convex parts regardless of rotation — a skewed beam's hull is
still its true footprint, just rotated), but every part it might hit is checked
against its **exact trimesh**, not a convex approximation — so a concave target
(an L-bracket, a beam with a cut-out/notch) no longer gets treated as solid across
its concave region. This was originally shipped as convex-vs-convex only, with the
trimesh-hybrid noted as future work "if concave geometry becomes common" — it
became common (bridge beams), so the hybrid is now built rather than deferred.

**Bug fixed**: `get_collisions()` used to query the physics space for hits against
*every* registered area, but only synced the live transform of currently-active
parts (`progress > 0`) beforehand — a part that hadn't started yet (or had already
finished and gone invisible) kept whatever transform its area was created with,
which defaults to world origin `(0,0,0)`, never explicitly set. A mover sweeping
anywhere near the origin could register a "collision" against a part that wasn't
really there, with no real geometry behind it — the collision marker would show up
floating in empty space, unrelated to anything on screen. `get_collisions()` now
discards any hit whose part isn't in the current frame's active set. A related bug
in `AnimationApplier._install_instant()` was fixed alongside it: it set
`part.visible = true` unconditionally, before checking progress, so every future
`install` part was actually visible and staged at its ground pickup position from
day 0 onward instead of hidden until its own day (every other `_*_instant` method
already followed the correct hidden-until-progress>0 convention).

`overlap_volume`/`overlap_aabb` in the returned entries are **not** exact —
`intersect_shape()` only answers "do they overlap", not "by how much" or "where
precisely" — so those two fields remain an AABB-intersection *approximation*,
used only to size the `CollisionVisualizer` marker and to pick the largest hit
among a commander pair's several leaf-level checks. The collision boolean itself
(whether a pair overlaps at all) is exact.

Deliberate scope narrowing:
- **Only in-transit parts are checked as movers**, not every visible part against
  every other. Steady-state touching (a wall resting on a slab, rebar sitting inside
  a column) is normal building geometry, not a collision — checking everything against
  everything would flag it constantly.
- **Parts installed together as one unit are excluded from each other** (a commander
  and its grouped children, e.g. a column + its rebar cage, are meant to be
  coincident). Tracked via `ConstructionSchedule._sibling_groups`.
- **Only parts with a registered collision shape participate** (a `MeshInstance3D`
  with a mesh a convex hull could be built from, via `CollisionQuery.setup()`);
  other node types, or meshes a hull can't be built from, are silently skipped
  with a warning.
- **Reported and deduplicated at the commander level**, not per leaf part.
  Geometry is still checked leaf-by-leaf (a commander's overall shape can miss a
  clash one of its smaller children actually has), but a beam's dozen rebar/
  formwork children each overlapping a column's dozen equivalents collapses into
  one `"beam unit ↔ column unit"` entry instead of a dozen near-identical ones.
  Tracked via `ConstructionSchedule._part_to_commander`. Parts with no commander
  (a plain `target_prefix` action) report under their own name.

`TimelineController.get_collisions()` is a convenience wrapper reading the
controller's own `current_day`/`_building_parts`. `TimelineUI` calls it every display
update and shows a red warning line with the colliding pair when non-empty
(`CollisionWarningLabel` in `timeline_ui.tscn`), and it's also what the pause-on-
collision gate (below) checks during Play. `get_collisions()` entries carry
`overlap_aabb` (world-space, axis-aligned) alongside `overlap_volume` — an
AABB-intersection *approximation* of the overlap region, not the exact shape
intersection (see above) — which `CollisionVisualizer` (`collision_visualizer.gd`,
mounted by `SequenceManager._ready()`) uses to draw a translucent red box near each
live collision's location in the 3D scene every frame. Distinct from the slider's
`CollisionOverlay`: that one is 2D and reflects a one-shot full-schedule scan; this
one is 3D and always reflects whatever the timeline is showing *right now* (so it
appears/disappears as you scrub or play through a collision window).

Markers are pooled `MeshInstance3D`s (grown as needed, hidden rather than freed when
unused), sized generously rather than exactly, since a real overlap is often only a
few centimeters and would otherwise be nearly impossible to spot: `size_padding`
(default 0.3m) adds a margin around the actual `overlap_aabb` on every axis, then
`min_marker_size` (default 0.6m) enforces a floor so even a razor-thin graze still
shows up as a visible box, not a sliver. Both are `@export`ed on `CollisionVisualizer`
for tuning. The material is unshaded, emissive, and sets `no_depth_test = true` —
collision markers are, by definition, usually sitting *inside* the solid parts that
are clashing, so without disabling depth testing they'd typically be fully hidden
behind whatever they're marking.

**Full-schedule scan**: `TimelineController.scan_collisions(sample_step = 0.01)` steps
through the *entire* date range (not just the current day), collecting every
collision and merging consecutive hits on the same part-pair into
`{part1, part2, start_day, end_day}` windows — a report of every collision in the
project instead of having to scrub around hoping to spot one live. It teleports every
part through the full range via `apply_instant()` (no tweens, no crane movement) and
restores wherever the timeline was before returning, so it's a one-shot, self-contained
operation. The **"Scan Collisions" button** in `TimelineUI` runs it, prints a report to
the console (e.g. `Day 3.10–3.40: Beam_02 ↔ Col_01`), and feeds the
windows into `CollisionOverlay` (`collision_overlay.gd`), which paints red zones
directly on the slider. `sample_step` defaults to `0.01`, the granularity
`get_part_states()` keys its one-day cache on; coarser steps risk stepping over a
short in-transit window entirely when many parts are staggered within one bucketed
day. **A schedule with no `install` part returns `[]` at once** without stepping at all
(`ConstructionSchedule.has_install_parts()`): `CollisionQuery` only ever checks
`install` movers, so nothing could be found, and the walk took over a minute on a
real model. `get_part_states()` keeps only the last day it computed. It used to keep
every day it was ever asked for, and this scan asks for all of them: about 33,000 ×
one entry per part, several GB. **`TimelineUI` also runs one scan automatically** on its first `_process()` frame
after being wired up (`_auto_scanned`, deferred one frame past `_ready()` since the
physics space `get_collisions()` depends on needs at least one frame to be
queryable) — so the overlay is already populated the moment the scene starts, not
only after a manual button press. Re-run the button manually after editing
`construction_steps.json` and restarting the scene.

The overlay lives in a small `SliderStack` wrapper `Control` in `timeline_ui.tscn`
(the `HSlider` and `CollisionOverlay` as full-rect siblings, since `HBoxContainer`
lays children out side by side rather than stacked) with `mouse_filter = IGNORE`, so
it's completely transparent to input and can never interfere with dragging the
slider underneath. **Hover tooltip**: `TimelineUI._update_hover_tooltip()` reads the
mouse position via `Control.get_local_mouse_position()` — a coordinate conversion,
not an input event — so it needs no `mouse_filter` change on the overlay at all; it
hit-tests via `CollisionOverlay.find_window_at()`, which shares `_draw()`'s exact
pixel math, so the hoverable region always matches the visibly painted red zone. This
replaces an earlier attempt that used `PASS` plus a `_get_tooltip()` override, which
broke the slider's drag-start.

**What's not built**: pause/revert-on-collision during Play is now **built** —
`TimelineController._process()` stops `is_playing` the instant a live collision is
present (a hard gate: pressing Play again while the same collision is still there
re-triggers it next frame, by design — see the code comment in `timeline_controller.gd`
for why "revert" was rejected in favor of pausing in place). The gate is bypassed in
movie mode, where with nobody to press Play again it wouldn't pause a recording but end
it; the collision *query* still runs there. `TimelineUI` shows
"Play (blocked)" and appends "— playback paused" to the warning label via
`TimelineController.collision_paused`. The one remaining gap: **crane geometry**
(arm/hook/rope) isn't part of the collision system — `get_collisions()` only checks
`building_parts` (the building), not the crane — so a second-crane clash scenario
isn't covered. Deliberately deferred, not attempted.

## IFC input and property mapping

The dock's **Load IFC (4D)** imports an IFC model through the third-party GDIFC addon. Because
every company stores its schedule in different properties, the plugin ships no property names:
`IfcPropertyScanner` lists what the model carries and `IfcMappingDialog` asks the user to pick the
element id, start, end-or-duration, display name and animation-type rules (`IfcMapping`, saved as
`<schedule>.ifc_profile.json`). `GDIFC4DAdapter.adapt(root, mapping)` names parts from the element
id and `IFCScheduleGenerator.generate(parts, mapping, existing)` writes the schedule; a
hand-corrected `type`/`batch` survives regeneration. Full workflow and limits are in
`05_IFC_INTEGRATION.md`; signatures are in `04_API_REFERENCE.md`.

`SequenceManager.parts_container_path` is required (no default), and `extra_part_containers` lists
any further nodes whose children are also parts; `collect_part_nodes()` is the single read-only
selection the runtime and the dock preview both use. Several IFC files can be loaded into one
scene: each later model gets its own container in `extra_part_containers`, placed relative to the
first by its georeference (`IfcSceneModels`, see `05_IFC_INTEGRATION.md`).

The import also keeps the model's position on Earth (`SequenceManager.geo_origin`), which the
terrain and the date-driven sun use; see `10_TERRAIN.md`.

Headless tests live in `tests/` (`test_ifc_mapping.gd`, `test_geo.gd`, `test_terrain.gd`,
`test_ifc_georef_gdifc.gd`, `test_ifc_scene_models.gd`).

## Known limitations (Phase 1)

- **Every crane parks (retracts) on every manual scrub/jump**, and each only swings once
  per install *unit* it's assigned (one commander + its grouped children) during forward
  Play — none of them chase a scrubbed-to state. See `_detect_install_actions()` in
  `timeline_controller.gd` (unchanged behavior, now applied per-crane instead of to a
  single crane — see "Multi-crane support" above).
- **The `fill_up` concrete-pour stream only exists during forward Play**, not while
  scrubbing. `apply_instant()` deliberately skips it — it can be called every frame, or at
  an arbitrary scrub position where a one-shot burst wouldn't make sense — so
  `TimelineController._detect_fill_up_actions()` acts as a boundary-crossing trigger
  during forward Play instead, spawning a `GPUParticles3D` stream matching the action's
  duration. See "Concrete pour stream" below for what it actually looks like.
- **Cadence is stretched continuously across an action's full `duration_days` window**,
  not partitioned into discrete per-day buckets with their own cadence
  (`ConstructionSchedule._init()`). The original roadmap describes explicit per-day
  bucketing (e.g. 7 parts over 3 days → 3+2+2); the shipped implementation instead
  normalizes one continuous cadence curve across the whole multi-day span. Visually
  this still preserves stagger order and spreads parts across the date range — it
  just doesn't produce hard day-boundary groupings. Worth knowing if you're debugging
  against the roadmap doc's specific bucketing examples.

## Phase 3: Editor Plugin (in progress — dock + live in-editor scrubbing)

`addons/construction_4d_tool/` is a minimal Godot addon (`plugin.cfg` + `plugin.gd`)
whose sole job is to mount `editor/timeline_dock.gd` — a dock (enable via Project
Settings → Plugins → "Construction 4D Tool") that scrubs the construction timeline
**live in the 3D viewport of the currently edited scene, without entering Play mode**.
It reuses `ConstructionSchedule`, `TimelineController`, `AnimationApplier`, and
`SpatialGrouper` exactly as they run at runtime — this is a new front-end, not a core
rewrite, confirming the "no rewrite needed" bet `01_ARCHITECTURE.md` made back in
Phase 1. The only changes to existing files are `@tool` added to `timeline_controller.gd`
and `timeline_ui.gd`, since Godot skips non-`@tool` script lifecycle callbacks
(`_process()`, `_ready()`) in the editor — without it, neither scrubbing nor the
embedded `timeline_ui.tscn` UI would run at edit time. `@tool` has no effect on runtime/
exported behavior.

**Target detection**: the dock searches the edited scene root for a node running
`sequence_manager.gd`, matched by script identity rather than node name (per
`03_PLUGIN_DISTRIBUTION.md`'s anti-pattern list — no assumption about scene
layout).

**Preview lifecycle and its restore guarantee**: `AnimationApplier.apply_instant()`
mutates real node properties (position, scale, visibility, material alpha) — exactly as
it does at runtime — which means doing this against the *actual edited scene* risks
baking preview state into the `.tscn` file if the user saves mid-preview. "Start
Preview" snapshots each part's pre-duplication `surface_override_material` array (the
one piece of state `SequenceManager.initialize_parts()`'s own metas don't cover — that
function already captures `original_pos`/`original_scale`/`original_transform` before
touching anything, so those metas double as the position/scale restore snapshot with no
separate bookkeeping needed), then calls `sequence_manager.load_json()` and
`initialize_parts()` exactly as `_ready()` would, builds a scratch
`ConstructionSchedule`/`TimelineController`, and embeds `timeline_ui.tscn` in the dock.
"Stop Preview" — an explicit button, and automatic on switching scene tabs
(`_process()` polls `EditorInterface.get_edited_scene_root()`) or on disabling the
plugin — restores position/scale/visibility from the metas and material references from
the snapshot, then frees the scratch controller/UI. A persistent warning label is shown
for the entire duration preview is active, matching this codebase's existing style of
surfacing real risk (e.g. the collision-pause label) rather than hiding it.

**Deliberate scope narrowing for this slice**:
- **No crane preview** — the dock passes `null` for the crane to `set_schedule()`.
  Avoids needing `@tool` on `crane.gd` and install-swing choreography in-editor;
  building-part scrubbing was the goal. A later increment could add it.
- **Extra part containers** — nodes listed in `SequenceManager.extra_part_containers` are collected through `SequenceManager.collect_part_nodes()`, the same read-only selection `initialize_parts()` uses, so they animate in editor preview like any other part.
- **No collision visualization in the dock** — `CollisionVisualizer` would need
  `@tool` plus a working `PhysicsServer3D` space in the editor process; left for a
  follow-up once basic scrubbing is proven out.

**`units_per_day` frequency-based duration entry — built** (not just an editor-dock
feature; it's a `ConstructionSchedule` change, so it works from plain JSON too, with or
without the dock). An action can specify `units_per_day` (e.g. `2` for "2 columns/day")
instead of hand-computing `duration_days`: `ConstructionSchedule._resolve_duration_days()`
derives `duration_days = ceil(unit_count / units_per_day)`, where `unit_count` is the
number of installable units (commanders for `commander_prefix`, matching parts for
`target_prefix`). An explicit `duration_days` always takes precedence when both are
present — purely additive to the schema, not a breaking change. See the Data model
section above.

**Schedule inspector panel — built.** `ScheduleInspector.build()` (`schedule_inspector.gd`,
owned by `TimelineDock` as `_inspector` — see "File split" above) renders
a 15-column `GridContainer` (ID / Action / Type / Cadencia / Escalonado (s) / Anchor /
Start Date / End Date / Duration (días) / Unidades/Día / Depende De / Retraso (días) /
remove), one row per action across
all steps, once "Start Preview" is pressed — the grid sizes each column to its widest
cell across every row, so a long date string doesn't get clipped by a fixed per-row
width. Each row edits its action `Dictionary` in place — GDScript `Dictionary`s are
references, so no separate write-back step is needed.

**Recalculate button — field edits no longer rebuild the schedule on every keystroke.**
Every field handler originally called `_rebuild_schedule()` directly, which constructs a
whole new `ConstructionSchedule` — including `CollisionQuery.setup()`, which rebuilds
a convex hull + trimesh `PhysicsServer3D` shape for *every* `MeshInstance3D` part in the
project, from scratch, with no caching. That's real, unavoidable-per-call geometry work,
and on a project with many parts it made every single keystroke in the inspector
noticeably slow. Field handlers now call `_set_schedule_dirty(true)` instead, which just
shows a warning label ("⚠ Schedule out of date...") and enables a **Recalculate**
button — the schedule (and with it, the 3D preview, the embedded `TimelineUI`, and any
Depends On row's resolved dates) only actually rebuilds when Recalculate is pressed, or
via the other actions that already implied a full refresh (Start Preview, Reload from
JSON). Typing/editing stays fast regardless of project size; seeing the result costs one
click. `_current_schedule` and `_resolved_date_fields` (see below) may lag behind
`sequence_data` between an edit and the next Recalculate — that's the accepted tradeoff.

**Layout: buttons wrap instead of forcing the dock wide.** The Start/Stop Preview row
and the Recalculate/Reload/Save row (`timeline_dock.tscn`'s `Buttons`/`InspectorButtons`)
are `HFlowContainer`s, not `HBoxContainer`s, and their buttons no longer set
`size_flags_horizontal = 3` (expand-to-fill) — each button now sizes to its own text and
the row wraps onto a second line if the dock panel is narrower than all of them laid out
side by side, instead of stretching the whole dock wider to fit them on one line. The
dock's own `custom_minimum_size` dropped from 880 to 340 accordingly — that 880 had been
sized to fit the then-10-column inspector grid on one line too, which was never necessary
since `InspectorScroll` already scrolls horizontally (`horizontal_scroll_mode = 1`) for
whatever doesn't fit; the grid no longer needs to dictate the panel's minimum width.

**ID** — a `LineEdit` for the optional `id` field (see Data model, above); blank falls
back to the prefix. The Action column's label shows the resolved identity
(`ConstructionSchedule._action_id()`) and, if an explicit `id` differs from the
underlying geometry prefix, both — e.g. `#2 FoundationDone (Col_)` — so it's still
obvious which parts the row actually animates. Editing ID calls `ScheduleInspector.build()`
again (a full grid rebuild, not `TimelineDock._rebuild_schedule()`) since a new id can
change what every other row's Depends On field is allowed to reference and how this row's
own Action label reads; `ScheduleInspector.clear()`'s `queue_free()` defers the actual
node deletion, so this is safe to call from inside the very `LineEdit`'s own signal handler.

**Type** — an `OptionButton` listing every built-in animation
(`AnimationApplier.TYPES` — `scale_up`, `drop_in`, `rise_up`, `sink_down`, `fill_up`,
`fade_in`, `fade_out`, `install`; see `animation_applier.gd`), so an action's `type`
field can be set without hand-editing JSON. `TYPES` is a single source of truth shared
between the dock's dropdown and `AnimationApplier.apply()`/`apply_instant()`'s own
`match` statements, so the dropdown can't drift out of sync with what's actually
implemented. Unlike every other field in this inspector, there's no "unset" state to
erase back to — an `OptionButton` always has some selection, and
`ConstructionSchedule`'s own fallback (`"scale_up"` if `type` is absent) is just where a
brand-new action starts out, not a meaningfully different state from writing
`"scale_up"` explicitly — so selecting a type always writes it.

The dropdown's visible labels are **cosmetic Spanish translations**
(`ScheduleInspector`'s `_TYPE_DISPLAY_NAMES`), not the values actually read/written —
`scale_up`→"Aparecer", `drop_in`→"Caer", `rise_up`→"Subir", `sink_down`→"Bajar",
`fill_up`→"Hormigonar" (concrete pour — matches what that animation actually depicts),
`fade_in`→"Emerger", `fade_out`→"Desvanecer", `install`→"Instalar". Requested because
most of the authoring crew doesn't read English and names like "scale_up"/"drop_in"
convey nothing on their own. Purely presentational: each dropdown item stores the real
English key as its metadata (`OptionButton.set_item_metadata()`) and that's what
`_on_type_edited()` always writes — `construction_steps.json`'s `"type"` values,
`AnimationApplier`'s `match` statements, and every other part of the engine stay in
English, untouched. Hovering a menu item shows its underlying English key as a tooltip.
A type with no entry in `_TYPE_DISPLAY_NAMES` (e.g. a future addition to
`AnimationApplier.TYPES` before its translation is added) falls back to showing its raw
English key, so the dropdown never breaks for an untranslated type.

The same cosmetic-Spanish treatment extends to the **Anchor** dropdown's 3 items
(`_ANCHOR_DISPLAY_NAMES`: `start`→"Inicio", `duration`→"Duración", `end`→"Fin" — metadata
stays the English key, exactly like Type above) and to every **column header**
(`_HEADER_LABELS`, e.g. "Fecha Inicio"/"Fecha Fin"/"Duración (días)"/"Unidades/Día"/
"Depende De"/"Retraso (días)" — the English field name is kept as each header's
`tooltip_text` rather than dropped). Both were added in response to the same "most of my
co-workers don't speak English" need the Type labels were requested for.

**Anchor / End Date — trial-and-fit scheduling.** Start Date, Duration (days) (and its
linked Units per Day), and End Date satisfy one invariant: `End = Start + Duration`.
That's 3 independent slots, not 4 — Duration/Units already act as one slot together (see
below). **Anchor** is a 3-item `OptionButton` per row (Start / Duration / End) naming
the slot that's *protected* — held fixed — when you edit one of the other two; editing
either of those recomputes the third (`ScheduleInspector._apply_time_edit()`):

| Anchor | Edit | Recomputed |
|---|---|---|
| Start | Duration/Units | End = Start + Duration |
| Start | End | Duration = End − Start |
| Duration | Start | End = Start + Duration |
| Duration | End | Start = End − Duration |
| End | Start | Duration = End − Start |
| End | Duration/Units | Start = End − Duration |

**Anchor never locks any field** — Start Date, Duration (days), and Units per Day are
always editable, and End Date is editable whenever Start Date has a value (see below).
An earlier version made the selected Anchor's own field non-editable (the idea being "no
ambiguity about editing the thing that's not supposed to move"), but that reads
backwards — picking Duration as Anchor greyed out Duration itself, when picking it is
naturally how you tell the row "I want to change Duration." Editing the field that's
currently the Anchor is a normal action; with no third slot left to protect by
elimination in that case, `_apply_time_edit()` falls back to a fixed default: editing
Duration/Units or Start pushes End (same start, different pace/finish); editing End
pushes Start (new deadline, same pace). Default Anchor is **Duration** on every row,
which reproduces the original pre-Anchor default behavior (edit Start or Duration/Units,
End is a derived display) — nobody has to touch this control to keep working that way. A
blank Start Date leaves End Date disabled ("(set Start Date first)") regardless of
Anchor, since day 0 is project-relative, not a literal calendar date, and there's
nothing real to compute from/into yet.

A **Depends On** row is a special case: Start there is resolved from the predecessor(s),
not a free value, so the whole Anchor/edit system doesn't apply — Anchor is disabled, and
both Start Date and End Date show the *actually resolved* calendar dates rather than
local arithmetic (`ConstructionSchedule.get_action_day_range()` +
`day_to_date_string()`, both new instance methods reading `_action_start_days`/
`_action_finish_days`/`_min_epoch`, which `_init()` now keeps as instance state instead
of discarding after construction). The two fields show it differently, though: **End
Date** is always non-editable there, so its resolved value is written as real `.text`.
**Start Date stays genuinely empty** (`.text`) even on a Depends On row — emptying it is
what lets the existing "type a date to override the dependency" flow keep working (see
`_on_date_edited()`) — so its resolved value is shown as `LineEdit.placeholder_text`
instead: informative, but never read back as if the user had typed it. Because a
dependent's resolved dates can change from an edit made on a *different* row (e.g. its
predecessor's duration changes), `ScheduleInspector` keeps a lightweight
`_resolved_date_fields` registry (one `{action, date_edit, end_date_edit}` per row, built
by `build()`) and exposes `refresh_dependency_dates()`, which `TimelineDock._rebuild_schedule()`
calls at the end of every rebuild to keep those specific fields current — cheap, and
doesn't touch focus or rebuild the grid.
Explicit-date rows don't need this: their End Date is kept current locally, by their own
field handlers, via `ConstructionSchedule.parse_date_to_epoch()`/`format_epoch_as_date()`
(`static`, also used internally by `_resolve_epoch()`) — simple epoch arithmetic that
doesn't need a `ConstructionSchedule` instance at all.

**Depends On / Lag (days)** — Depends On is a `LineEdit` holding a comma-separated list
of ids (`ConstructionSchedule._depends_on_ids()` parses/renders both the legacy
single-string form and the array form — see Data model, above); a `SpinBox` sets
`lag_days`. A true multi-select widget would be nicer but is a heavier component for a
first pass — a text field matches the existing Start Date pattern, and splitting/joining
a comma list is a few lines (`_on_depends_on_edited()`): 0 ids erases `depends_on`, 1 id
writes a plain string (keeping the common single-predecessor case's JSON unchanged from
before multi-predecessor support existed), 2+ writes an array. Mirroring how Duration/
Units per Day are kept mutually exclusive (below): setting a non-empty Depends On erases
`start_date` from the action and clears the Start Date field, and typing a Start Date
erases `depends_on` and clears the Depends On field — a row can never display a date and
a dependency that silently disagree about which one is actually driving the schedule
(`ConstructionSchedule._resolve_action_start_day()` gives `start_date` priority, so
leaving both set would make the Depends On field lie about what's really happening).

**Duration (days) and Units/Day are kept mutually in sync**, unlike the raw JSON schema
where an explicit `duration_days` always wins over `units_per_day` if both are present
(see Data model, above). The inspector instead treats them as two views of the same
rate and always normalizes back to `duration_days`: editing either field recomputes and
displays the other (`unit_count` — commanders for a `commander_prefix` action, matching
parts for `target_prefix` — is resolved via a `SpatialGrouper` shared with schedule
rebuilds, `_unit_count_for_action()`), but only `duration_days` is ever written onto the
action `Dictionary`; `units_per_day` is erased on every edit so the two fields can never
silently disagree. This means the inspector doesn't roundtrip a hand-authored
`units_per_day` field as-is — editing an action through the inspector (even just its
date) converts that action to explicit `duration_days`. Hand-editing the JSON directly
still supports `units_per_day` on its own exactly as documented above; this only affects
what the inspector itself writes back.

Editing Units/Day writes the **exact** `unit_count / units_per_day` to `duration_days`
(`snappedf(..., 0.0001)`, just to keep the JSON free of binary-float noise), not
`ceil(unit_count / units_per_day)` — unlike `ConstructionSchedule._resolve_duration_days()`,
which does round up to a whole calendar day when resolving a hand-authored
`units_per_day` field directly (a reasonable convention for raw JSON — you can't schedule
a fractional calendar day of work). Rounding here would be lossy for the inspector's own
round-trip: typing `5` units/day for 24 units, saving the rounded `ceil(24/5) = 5` days,
then reloading, would recompute `24/5 = 4.8` units/day — not the `5` that was typed. The
`duration_spin`'s step was also loosened from `1` to `0.01` for the same reason: Godot's
`Range` (the base of `SpinBox`) snaps any assigned `value` to the nearest multiple of
`step`, so a `step = 1` silently rounded a precise fractional duration back to a whole
number the instant it was displayed, independent of the ceiling issue above.

Every edit marks the schedule dirty rather than rebuilding it immediately — see the
Recalculate button paragraph above for why and what that means in practice.
`_rebuild_schedule()` (called by Recalculate, and internally by Start Preview/Reload
from JSON) constructs a fresh `ConstructionSchedule` (it has no incremental-update path;
everything is computed once in `_init`) and rewires the live `_controller`/`_timeline_ui`
to it, restoring whatever day the timeline was scrubbed to beforehand. **"Save to JSON"**
writes `sequence_data` back to `construction_json_path` via `JSON.stringify(..., "\t")`;
**"Reload from JSON"** discards in-memory edits and re-reads the file, rebuilding both
the inspector rows and the schedule. Recalculate/Reload/Save are all enabled only while
a preview is active (same lifecycle as Start/Stop Preview) and disabled by
`stop_preview()`, which also clears the inspector rows.

**CSV export/import — built.** `TimelineDock`'s **"Export CSV"**/**"Import CSV"** buttons
(same lifecycle as Recalculate/Reload/Save — enabled only during an active preview) open an
`EditorFileDialog` (`ACCESS_FILESYSTEM`, so the file can live anywhere, not just `res://`,
for handing off to spreadsheet/Gantt tools outside the project) and round-trip through
`_sequence_manager.sequence_data` in memory, exactly like every other dock control — Export
writes out whatever's currently in memory (including unsaved inspector edits), Import writes
into it and calls `_set_schedule_dirty(true)`, same as any single field edit; Save to JSON
and Recalculate remain separate, explicit steps.

The CSV is deliberately scoped to the same fields the inspector grid itself edits — `id`,
`action` (a read-only human-readable label, ignored on import), `type`, `start_date`,
`end_date`, `duration_days`, `units_per_day`, `depends_on`, `lag_days`, `comment` — not the
full action `Dictionary`: geometry (`commander_prefix`/`child_prefixes`) and animation tuning
(`stagger*`/`dur_accel` etc.) stay JSON-only, untouched by either direction. `end_date` is
derived/export-only in the general case (preferring `_current_schedule.get_action_day_range()`'s
actually-resolved date for a Depends On row, falling back to local start+duration arithmetic
otherwise) and is only read back on import as a fallback to compute `duration_days` when both
`duration_days` and `units_per_day` columns are absent from the CSV entirely.

**Import matches each row to an existing action by its resolved id**
(`ConstructionSchedule._action_id()` — explicit `id`, else `commander_prefix`/`target_prefix`)
— a row whose id doesn't match any current action is warned about and skipped; import never
creates a new action, since a new action needs a prefix/geometry link CSV alone can't safely
supply (mirrors the same "don't create, only close gaps" caution `depends_on`/`id` resolution
already applies elsewhere). `_apply_csv_row()` mirrors the inspector's own mutual-exclusion
rules exactly: a non-blank `start_date` cell clears `depends_on` and vice versa; `duration_days`
and `units_per_day` are two views of one rate, so only one is ever persisted (an explicit
`duration_days` column wins over `units_per_day` if both are non-blank in the same row, same
precedence as raw JSON). A **present-but-blank** cell erases that field (the same "blank clears
it" convention every inspector `LineEdit` already follows); an **absent column** (e.g. a
hand-trimmed CSV with only `id`/`start_date`/`duration_days`) leaves that field untouched —
`_csv_cell()`'s `"<absent>"` sentinel is what distinguishes the two. Uses `FileAccess.store_csv_line()`/
`get_csv_line()`, so a `depends_on` cell with multiple comma-separated ids round-trips through
standard CSV quoting with no custom parsing needed.

Round-tripping the full action `Dictionary` (geometry/animation-tuning fields too) was
considered and explicitly deferred — this slice covers only what the inspector already
exposes, matching its scope rather than becoming a second, wider authoring format.

**Project XML export/import — built.** `TimelineDock`'s **"Export Project XML"**/
**"Import Project XML"** buttons round-trip through Microsoft Project's *XML Interchange*
format (`xmlns="http://schemas.microsoft.com/project"`) — a real, documented, open schema,
**not** the legacy binary `.mpp` file format. `.mpp` is an OLE/Compound-File container whose
internal task encoding is proprietary and was never fully published by Microsoft;
reverse-engineering it well enough to read/write reliably is what a dedicated project like
MPXJ (Java, ~15 years of work) exists for — not something to hand-roll in GDScript. Project
XML, by contrast, is genuinely parseable/writable with Godot's built-in `XMLParser`, no
external dependency, staying consistent with every other export/import in this dock.
`ScheduleProjectXmlIO` (`schedule_project_xml_io.gd`) does the actual read/write; a second
new file, `ProjectXmlMappingDialog` (`project_xml_mapping_dialog.gd`), handles the one part
of this that CSV didn't need — see below.

Export writes every action as a **Manually Scheduled** Task (`<Manual>1</Manual>`) with a
literal `<Start>`/`<Finish>`, so Project displays exactly the dates given rather than
recomputing them through its own working-time calendar — our schedule is continuous-
calendar-day based, not calendar-aware like Project's own duration engine, so letting
Project "help" would silently drift the dates. Task `<Name>` is the resolved action id
(`ConstructionSchedule._action_id()`), not a human label — this is what makes re-importing
our own export a zero-friction exact match (see Import below). `depends_on` predecessors
are written as `<PredecessorLink>` entries with `Type=1` (Finish-to-Start, the only
relationship type this codebase's schema models); `lag_days` is written as `<LinkLag>` in
tenths of a minute (Project's convention for that field). Actions with no resolvable start
date are skipped rather than exported undated.

**Import's real complication, and why it needed a dialog CSV didn't**: CSV import always
matches by resolved id because *we* generate the CSV from our own ids — there's always a
natural key. A genuine Project file (hand-authored in Project, or exported from a different
project entirely) has no such key: its Task Names are human descriptions with no relation to
our `commander_prefix`/`id` scheme. `_import_project_xml()` resolves each task to an
`{anchor_id, terminal_id}` mapping (see "Anchor/terminal phase groups" below) via, in
priority order: (1) a **persisted mapping file** (`construction_steps.project_mapping.json`
— same basename as the JSON, silent/automatic, no dialog of its own) so a task mapped once
never prompts again; (2) **exact** `Task Name == resolved action id` (`anchor_id ==
terminal_id`) — the round-trip-our-own-export case; (3) anything still unresolved needs a
human, via `ProjectXmlMappingDialog`. If every actionable task resolved without it, import
applies immediately with no dialog at all. Otherwise the dialog pops up — one row per
unmatched task (Project Name, UID/dates as a tooltip) with **two** `OptionButton`s, Anchor
and Terminal (see below) — and only proceeds on Confirm (Cancel drops the whole import, not
just the unmapped rows, since silently applying a partial match without telling the user
would be a surprising outcome). Every resolution this import makes — persisted-carryover,
auto-matched, and freshly dialog-mapped alike — gets written back to the mapping file
afterward, so it stays a complete, self-healing record rather than an incremental diff.

**Anchor/terminal phase groups.** One external Project task doesn't always correspond to
exactly one action — e.g. a "Pile 2" task spanning 2 weeks in Project might actually be
`rebar_f1 → pour_f1 → rebar_f2 → pour_f2 → rebar_f3 → pour_f3` internally, each phase linked
by hand-authored `depends_on`/`lag_days` capturing real cure/wait times (a concrete cure
doesn't compress to fit whatever duration an external estimate happens to say — see
`CHANGELOG.md`'s "Project XML phase-group mapping" entry for the full worked example and the
rejected alternative of proportionally scaling phases to force an exact fit). A mapping
is therefore `{anchor_id, terminal_id}`, not a single id — for an ordinary task with no phase
breakdown they're the same action. Only the **anchor** (the chain's first action) ever has
its `start_date` (and `duration_days`/`depends_on`/predecessor-derived fields) overwritten,
via the same `apply_task_onto_action()` used for a plain 1:1 match — everything after it in
the phase chain is never touched by import at all, since it already cascades automatically
through whatever `depends_on`/`lag_days` chain was hand-authored once in
`construction_steps.json`. The **terminal** (the chain's last action) is never written to;
only its *computed* finish (`ConstructionSchedule.get_action_day_range()`, after a real
`_rebuild_schedule()` forced specifically for this check) is read back and compared against
the task's own `<Finish>`. A mismatch is **reported, not silently corrected** — printed to the
console as `'<task name>': computed finish <X> vs Project's Finish <Y>` — since a real
discrepancy almost always means either the phase template or the Project estimate needs a
human look, not an automatic rescale of real calendar days that don't compress. This check
(and the forced rebuild it needs) is skipped entirely when every matched task in a given
import is the ordinary `anchor_id == terminal_id` case, preserving the usual "edits are cheap,
Recalculate is explicit" behavior for the common path.

Once every task is resolved (persisted, auto-matched, and/or dialog-mapped),
`ScheduleProjectXmlIO.apply_task_onto_action()` writes each anchor's fields: `duration_days`
from `Finish − Start`; **only `Type=1` (Finish-to-Start) predecessor links are honored** —
Start-to-Start/Finish-to-Finish/Start-to-Finish links are silently dropped, not approximated,
since forcing them into an FS-only field would misrepresent the source schedule rather than
just omit part of it. A predecessor link only counts if its own task's *anchor* was also
resolved this import (`uid_to_action_id` is built from every matched task's `anchor_id`) —
unresolved/skipped predecessors are dropped the same way an unresolved CSV `depends_on` id is.
When at least one predecessor resolves, `depends_on` drives the anchor's schedule and
`start_date` is erased (mirroring the inspector's own Start Date/Depends On mutual exclusion —
leaving both would make the imported dependency graph inert, since an explicit `start_date`
always wins in `ConstructionSchedule`); otherwise the task's own literal `Start` date is used.

**Not yet built**: matching by a stable model-derived identifier (e.g. an IFC group id/
element id field carried through a Project custom `<ExtendedAttribute>` — Project's own
custom-field mechanism, already visible in real exports) instead of Task Name. The IFC
import pipeline now exists (`05_IFC_INTEGRATION.md`) and those ids land as the part's own
node name (`GDIFC4DAdapter`, since that's also what schedule prefixes match against), so
what's blocking this is now only the Project XML side — extending
`_import_project_xml()` to also try matching a task's `<ExtendedAttribute>` value against
a resolved action id, alongside the existing Task Name match. The mapping file format and
anchor/terminal mechanics above don't need to change for that.

`XMLParser` is a streaming/pull parser, not a DOM — `parse_xml()` walks a simple element-name
stack so a leaf field's text is only captured when its immediate parent is `<Task>` or
`<PredecessorLink>`, letting unrelated nesting (e.g. `<ExtendedAttribute><Value>`) fall
through unrecognized. One correctness detail worth knowing if this is ever touched: a
self-closing tag (`<Foo/>`) reports `NODE_ELEMENT` with `is_empty()` true and — unlike a
`<Foo></Foo>` pair — never gets a matching `NODE_ELEMENT_END`; `_close_element()` is called
inline for that case too, or one such tag anywhere in the file would leave the parser's
element stack permanently one entry too deep for everything after it.

## Phase 3 prep notes (both resolved)

- **EditorPlugin**: every class so far (`Cadence`, `ConstructionSchedule`,
  `TimelineController`) is `RefCounted`/pure `Node` with no `EditorPlugin`
  dependency, so a dock can instantiate them directly and reuse `timeline_ui.gd`
  as-is or with minor changes. No rewrite needed. **Built** — see the Phase 3 section
  above.
- **Known technical debt to revisit before Phase 4 packaging**: the continuous-cadence
  vs. discrete-bucketing deviation above, and crane geometry not being part of the
  collision system, are the open gaps between this implementation and the original design
  docs (or, for the collision tooling, beyond what the docs originally scoped for Phase
  2). Pause-on-collision, the slider hover tooltip, and the pour-particle trigger during
  Play, all previously listed here, are now built.

## Calendar dates

The scrubber reads a real date — `mar 14/abr/2026 · día 0.0` — not a relative day count.
`TimelineUI._format_day()` builds it from two new one-line accessors on
`ConstructionSchedule`: `has_calendar_dates()` (is `_min_epoch` real?) and
`day_to_epoch(day)` (the conversion `day_to_date_string()` already did internally, exposed
so callers wanting a weekday or a localized format don't have to parse a `"YYYY-MM-DD"`
string back). Day 0's epoch has been instance state since the Phase 3 inspector work; the
comment claiming otherwise in `_format_day()` was simply stale.

Format is `<weekday> dd/<mes>/yyyy`, Spanish abbreviations (`_WEEKDAYS_ES`/`_MONTHS_ES`),
matching the cosmetic-Spanish convention the inspector's dropdowns and headers already
use. **The weekday is deliberate**: the model's own duration fields count *working*
days while this timeline counts *calendar* days (see `05_IFC_INTEGRATION.md`), so being
able to see at a glance that an action spans a weekend is worth the four characters.

The raw day number is kept as a secondary detail because the collision subsystem still
speaks in days — `scan_collisions()` samples at 0.01-day granularity, so two windows on
the same calendar date are otherwise indistinguishable. The scan report and the slider's
hover tooltip now show both (`mar 14/abr/2026 (3.10)`) and share one formatter,
`_describe_window()`, rather than duplicating format strings as before.

**Undated schedules still work.** A JSON whose actions carry no parseable `start_date`
leaves `_min_epoch` at `0.0`; `has_calendar_dates()` returns false and every label falls
back to the original `Day %.1f`. Without that guard day 0 would render as `1970-01-01`,
which is meaningless rather than merely approximate. Verified against a schedule built
with no dates at all.

Since the Phase 3 dock embeds `timeline_ui.tscn` rather than drawing its own label, the
in-editor preview gets dates from the same change with no extra work.

## Per-action cadence

**The animation should show the construction method, not just activity.** A concrete pour
modelled as four separate meshes is *one* operation and its parts must rise together;
four precast columns are four operations and must arrive one at a time. That distinction
is the `batch` field, read by `Cadence.compute_timings()` (`cadence.gd`) — which both
action paths call (`construction_schedule.gd:126` for `commander_prefix`, `:192` for
`target_prefix`), so it applies to either kind of action.

The full set of per-action cadence fields, all optional:

| Field | Default | Effect |
|---|---|---|
| `batch` | `false` | `true` = every part moves simultaneously (a single pour) |
| `stagger` | `0.75` | Delay between consecutive parts |
| `stagger_accel` | `1.0` | Multiplier applied to the delay after each part |
| `stagger_min` | `stagger` | Floor for the accelerating delay |
| `dur` | `1.0` | Per-part animation duration |
| `dur_accel` | `1.0` | Multiplier applied to duration after each part |
| `dur_min` | `dur` | Floor for the accelerating duration |

These are all **relative**. `ConstructionSchedule` normalizes the whole cadence to
`total_cadence_sec` and maps it onto the action's `duration_days`, so `stagger` sets the
spacing *within* an action, never its total length — changing it redistributes the parts
across the same calendar window. To make an action take longer, edit `duration_days`.

**In the inspector**: the *Cadencia* column, a two-state dropdown reading *Simultáneo* /
*Escalonado*, with *Escalonado (s)* next to it for the delay (`stagger`). The delay is
greyed out while Simultáneo is selected — it has no effect there — and the whole choice
is greyed out for a single-part action, which has no ordering to control. `0` means unset
(falls back to `0.75`), matching Duration and Lag's convention in the same grid.

**The generator sets it from the IFC.** `IFCScheduleGenerator._batch_for()` writes
`batch` explicitly on every action: `true` unless `type` is `install` or `drop_in`, the
two types that describe placing a discrete manufactured unit. No new IFC metadata was
needed — part-name property → `type` already encodes it. Writing it explicitly rather than
relying on Cadence's `false` default matters because that default is the wrong answer for
almost everything in an IFC-derived schedule: one element id covering several meshes
means one pour split for modelling convenience (a slab modelled as four meshes), not four
separate operations. Explicit also means the value is visible in the JSON and one toggle
away in the inspector, so any case the rule gets wrong is trivially fixed *and the fix
survives* — it is a plain field, not an inferred default.

A model that is entirely cast in-situ therefore batches every action and contains no
`install`/`drop_in`; those entries exist for precast work.

**Play and scrub agree**, which is the failure mode worth guarding against here — a pour
that rises together during Play but staggers while scrubbing would be a subtle and ugly
bug. They can't diverge: both go through `TimelineController._process()` →
`get_part_states()` → `apply_instant()`, with `Cadence` feeding the `_part_schedules`
windows that query reads. Verified headless anyway — with `batch: true`, a four-part
action's parts all hold the window `[73.0000..80.0000]` and 900 scrub samples across it produce
zero divergence in reported progress; with `batch: false` they spread to
`[73.0000..75.1538]` … `[77.8462..80.0000]`.

**Grouping and batching are separate questions.** Which parts form one action is decided
by element id (or the coarser group id); whether those parts move together is
`batch`. Precast columns therefore have two routes in — group at group id level so all
the columns land in one action, or set `type` to `install` (*Instalar*) so the batching
exception applies. Inferring `batch` from geometry was considered and rejected: measured
pairwise centre distances on a real model put two genuinely separate footings (12 m apart)
*closer* together than three contiguous girder segments (19 m apart), because
element size varies more than the gaps between elements. No distance threshold separates
those cases, so no such heuristic ships.

## Formwork (encofrado)

**A five-day element is not a five-day pour.** It is four days of building the forms and one
day of filling them. An action's window therefore splits in two:

```
   S                                   S+F        S+D              strip
   |------------- formwork -------------|-- pour --|--- cure ---|--------|
   |  boards go up one after another    |  fill_up |            | fade   |
```

Add `"formwork": {}` to an action (or `"formwork_defaults": {}` at the root of
`construction_steps.json`, applying to every action) and its parts get forms. Absent, an
action behaves exactly as it did before this existed.

| Field | Default | Effect |
|---|---|---|
| `pour_days` | `1.0` | The pour's length. Formwork gets `duration_days` minus this |
| `formwork_days` | — | Explicit alternative; **wins** if both are present |
| `strip_days` | `0.0` | Cure days after the pour before the forms come off |
| `strip` | `true` | `false` keeps them permanently — lost formwork (*encofrado perdido*) |
| `type` | `scale_up` | How a panel appears |
| `strip_type` | `fade_out` | How it comes off |
| `batch` | `false` | Panels stagger even when the action batches — see below |
| `board_width` | `2.5` | Target board width (world m) before a face subdivides |
| `thickness` | `0.05` | Panel thickness (world m) |
| `prefix` | — | Tier 1: formwork already modelled in the scene. Those parts *are* the forms; nothing is generated |
| `model` | — | Tier 2: a `res://` `.glb`/`.tscn` panel asset placed at each computed position |
| `enabled` | `true` | `false` opts one action out of `formwork_defaults`; `"formwork": false` is the shorthand |

**`pour_days` is the primary field, not `formwork_days`** — the tail rather than the head. A
pour is a fixed short operation whose length is a property of the element, while the prep
expands to fill whatever the programme allows. When a revised IFC moves an element from 5
days to 8, `pour_days: 1` is still true and the formwork absorbs the change; `formwork_days:
4` would silently leave a 4-day pour.

**This is not a new animation type — it is more parts with their own window.**
`_part_schedules` is `part_name → {start_day, end_day, anim_type}` and nothing requires an
action's parts to share a window, so the concrete keeps doing `fill_up` on a shortened window
and the panels are ordinary parts scheduled on the front of it. Scrub/play parity, the
collision query, the dock preview and movie mode all needed no changes. `AnimationApplier`
was the wrong seam: it moves one node given one progress value, with nowhere to put "and also
these eight panels."

**Geometry resolves in three tiers, first match wins.** `formwork.prefix` means the forms are
already in the scene and nothing is generated; `formwork.model` places a panel asset at every
computed position; neither means the generic wood slab. **Tiers 2 and 3 differ only in what
gets placed** — the placement math below is shared, which is what keeps "I have a panel asset"
one JSON field away from the default rather than a separate code path.

**Geometry comes off the mesh's own vertical faces, not its bounding box.**
`FormworkBuilder` (`core/formwork_builder.gd`) reads each part's triangles, keeps the
ones within ~14° of vertical, and clusters them into planar patches; each patch becomes a
board rectangle that subdivides into boards of `board_width`, clamped to 1–8 per patch.

The bounding box was the original approach and it was visibly wrong, because these elements
are not boxes: `B2`'s mesh fills **4 %** of its own AABB, `B1` 11 %, `A1` 22 %. Measured
against the real model, box-face boards sat a mean of **5.0 m** from the concrete they were
supposed to be holding (max 22.0 m, with 500 of 508 boards more than 0.5 m out); face-derived
boards sit a mean of **0.10 m** out (max 1.5 m, 17 of 385). Height was never wrong — panel
heights matched element heights exactly — only horizontal placement.

Clusters merge by normal within ~15°, split when the same normal appears more than 0.75 m
away in its own direction (a U-shaped wing wall's two parallel faces must not become one board
bridging the gap), and are bounded in *metres* off their seed plane, not only in degrees — a
large-radius curve stays inside 15° for tens of metres, so the angle alone does not bound how
far a flat board ends up from a curved surface. Each cluster then splits into laterally
contiguous runs by triangle coverage, so a board is never emitted across a stretch where the
surface isn't. A cluster whose normal points *inward* is dropped, which keeps a hollow box
girder's inner walls from getting forms on the wrong side of the concrete. The largest 40
clusters by area survive per part; the rest are triangle slivers.

Boards carry a full orientation (`Basis(tangent, up, normal)`), so a skewed or curved face
gets boards lying flat against it rather than axis-aligned ones. The AABB path survives as the
**fallback** for a part whose mesh yields no usable vertical face at all. Formwork is generated
**per part**, not per element — a three-segment girder can span ~19 m, and one box
around all three would enclose mostly air.

**It is idempotent, and that is the whole reason it is its own class.**
Generated geometry lands in the parts container, so running it twice would duplicate it,
and the dock preview *is* the authoring flow: Start Preview re-runs setup on every press.
`build()` sweeps its own prior output first,
so running it any number of times leaves the same scene as running it once.

**Nothing generated is `owner`ed**, so Godot never writes panels into the `.tscn` — formwork
is a view of the schedule plus the model, not scene content, and persisting it would mean a
saved scene and a saved JSON that can disagree. `stop_preview()` sweeps as well, so the tree
is clean the moment a preview ends. This is the deliberate opposite of `GDIFC4DAdapter`,
which sets `owner` precisely so a real import survives a save.

**Panels stagger even when the action batches.** `batch: true` is right for the concrete (one
pour split across several meshes must rise together) and wrong for the forms, which genuinely
go up one after another. Concrete pours usually batch, so inheriting it would pop an
entire form set into existence in one frame and waste the days it was given.

**The lifecycle is one window, three phases.** A panel's `anim_type` is `formwork`, and
`AnimationApplier._formwork_instant()` maps assemble → hold → strip onto the same 0–1 progress
value everything else uses, reading per-panel boundaries from a `formwork_phases` meta (panels
assemble staggered but strip together, so no two share the same boundaries). The phases
**compose** existing animations rather than reimplementing them — `type` and `strip_type` are
ordinary `AnimationApplier.TYPES` entries with progress remapped into each one's range.

`formwork` is deliberately **not in `TYPES`**: that list is what the dock's dropdown offers
for an *element*, and formwork is not something an element can be. Listing it would let
someone set a pier's type to `formwork`, which would then read a phase meta off a part that
has none.

Each phase re-establishes the other's boundary state before applying its own, which is not
redundant — it is what makes scrubbing backwards correct. `_scale_up_instant()` never touches
material alpha, so scrubbing back out of a `fade_out` strip would otherwise leave a panel at
alpha 0: fully assembled, correctly placed, and invisible.

**Stripping extends the date range but never an action's finish day.** The last action ends
day 161 and its forms come off over day 162 — without that the final frame of a recording
shows a bridge wearing plywood. `depends_on` resolves against `_action_finish_days`, which is
untouched, so no downstream date moves; a dependent starting while its predecessor's forms are
still standing is realistic. The strip animation's own length is derived (a quarter of the
formwork span, bounded to 0.25–1.0 days) rather than being another mandatory field.

**Generated panels are not clash-checked** (`CollisionQuery.setup()` skips anything carrying a
`formwork_of` meta). They multiply the part count 3–5×, and every part costs a convex hull
*and* a trimesh built from scratch with no caching — already the reason the dock needs an
explicit Recalculate. In exchange they would detect clashes against temporary scaffolding, and
on a model with no `install` actions nothing is ever a mover, so the value is currently zero.
Re-enabling is deleting that check; `_part_to_commander` already rolls panels up to their
element, so they would not flag against the concrete they hold.

**A model panel is fitted to the board, not placed at its natural size.** Each computed board
is a box, and the instance is scaled so its own AABB fills it and translated so its AABB
*centre* (not its origin — assets are often pivoted at a corner) lands on the placement. Same
argument the generic slab already makes: elements run from well under a metre to over twenty, so one fixed
size reads wrong at one end or the other. Set `board_width` to the asset's real width and the
horizontal scale stays near 1; height is the element's and has to scale regardless. Since
boards carry their own orientation, the asset only has to be turned to one convention —
whichever of its horizontal extents is thinner becomes the board's local Z — rather than
compared against each slot's axis. Assets are loaded and measured once per path, not per
placement.

**A bad `model` path falls back to the generic slab and warns once per action** — a missing
file, a resource that isn't a `PackedScene`, a root that isn't a `Node3D`, a model with no mesh.
Falling back to tier 3 rather than to nothing is deliberate: a mistyped path should cost the
forms' *look*, not their existence, and an empty formwork phase is much harder to read as a
typo than brown boxes where panels were expected.

**Composite panels fade because both fades recurse.** A `.glb` root is a `Node3D` with
`MeshInstance3D` children, and `_fade_out_instant()` — the default `strip_type` — used to
return early on anything that wasn't itself a `MeshInstance3D`. Both fades and
`SequenceManager.make_materials_unique()` now walk descendant meshes, so a model panel strips
properly and each placement owns its own material instead of the whole form set fading in
unison. Purely additive: composite parts got *no* fade at all before. The dock's
`_snapshot_materials()` walks the same set, or a preview would leave its duplicates behind in
the edited scene.

**Tier-1 forms are ordinary scene parts.** They stay collision-registered (unlike generated
panels), they carry no `formwork_of` meta, and they are not rolled up through
`_part_to_commander` — this step doesn't change how a clash involving them is reported. What
they do get is the same `_schedule_formwork()` everything else goes through: same cadence, same
stagger-even-when-batching inversion, same lifecycle, same strip.

**A tier-1 action with no room for a formwork phase still schedules its forms**, with a
zero-length assemble at the action's start. This is the one place the tiers diverge, and it is
forced: geometry that was never generated is simply absent, but geometry already in the scene
*and excluded from work matching* would otherwise have no window at all — hidden and
zero-scaled for the entire run, invisible forever. A `prefix` that matches nothing warns and
leaves the phase empty, but does not undo the window split; re-lengthening the pour would hide
the typo rather than surface it.

**Prefix matching can never eat the forms.** Schedule matching is `begins_with()`, so a form
wrapping `A1` is one rename away from starting with `A1` too — at which point the action
would schedule its own forms as concrete and pour them. Generated panels are guarded by their
`formwork_of` meta; tier-1 forms by a **project-wide index resolved before any action is
scheduled**, because the real hazard is not an action matching its own forms but action B's
`target_prefix` matching action A's. That index is deliberately *not* the `formwork_of` meta:
`sweep()` deletes everything carrying it, so stamping it on scene geometry would make Start
Preview delete the user's model.

Both guards now cover the **`commander_prefix` branch** as well. `SpatialGrouper._compute()`
does its own bare `begins_with()` over whatever dictionary it is handed, so it had been
bypassing the guard entirely — never observed in practice, but tier 1 makes `commander_prefix: "A1"` alongside scene forms named `A1_FORM…` the
obvious way to author this. Both branches now match against `building_parts` filtered of all
formwork.

**An action with no room gets no forms.** If `duration_days <= pour_days` there is no formwork
phase to show, so the action falls back to its pre-formwork behaviour and warns once — and no
panels are generated, since geometry nothing schedules would be invisible forever. Each
one-day element therefore produces one such warning, which is the expected output of
turning formwork on, not a fault.

**An explicitly empty block still turns formwork on.** `{}` is the internal sentinel for "no
formwork", which used to collide with an action opting in and supplying no fields:
`"formwork": {}` and `"formwork": true` both merged to `{}` with no root defaults to inherit,
and so did nothing at all — silently, and contrary to what this file documented.
`resolve_formwork_config()` now materialises the documented `pour_days: 1.0` in that case.

**Formwork settings do not survive the next Generate 4D Schedule**, however they were
authored — the dock's own columns included — for the same reason an inspector `type`
correction doesn't (see `05_IFC_INTEGRATION.md`). Carry-forward is build order step 6.

### Turning it on

Nothing is enabled by default, so an action with no `formwork` block animates exactly as it
did before this existed. Three ways to opt in, in rough order of convenience:

- **The dock's "Encofrado en todo el proyecto" checkbox** — writes the root
  `formwork_defaults` block, turning formwork on for every action at once, with a *Días
  vertido* spinner for the project-wide pour length.
- **A row's *Encofrado* dropdown** — *No* / *Genérico* / *Modelo* / *Prefijo*, per action,
  with its own *Días vertido*. The dropdown shows the **resolved** tier, so a row inheriting
  the project-wide default reads *Genérico* rather than *No*, and *No* on such a row writes
  the explicit `"formwork": false` opt-out rather than erasing a key that isn't there.
  *Modelo* and *Prefijo* are shown but selectable only once the JSON supplies a `model` path
  or a `prefix` — geometry links stay JSON-only, as `commander_prefix` already does.
- **By hand in `construction_steps.json`** — `"formwork": {}` on an action, or
  `"formwork_defaults": {}` at the root.

A row whose action is too short to have a formwork phase (`duration_days <= pour_days`) shows
its *Días vertido* in amber with a tooltip saying so, because an action that silently pours
across its whole window and generates nothing otherwise looks exactly like a broken row.

CSV export/import carries `formwork_mode`, `pour_days` and `strip_days`. Geometry links are
never written from CSV, matching the inspector. A CSV that predates these columns leaves an
action's formwork untouched on import — an absent column and a blank cell mean different
things (`_COLUMN_ABSENT`).

**Not yet built**: the `IFCScheduleGenerator` rule with carry-forward. See `07_FORMWORK.md`'s
build order.

**Verifying changes here**: a throwaway headless `SceneTree` harness covered all five built
steps (167 checks) during development; see "Verifying changes headless" below for the gotchas.

## Concrete pour stream

A `fill_up` action spawns a falling stream of concrete above the part it is pouring
(`AnimationApplier.fire_fill_up_particles()`). Forward Play only — see "Known
limitations" above for why scrubbing has no stream.

**It is off unless a project turns it on.** With no `"pour_stream"` block at the root of
`construction_steps.json` there is no stream, and no particle node is built at all — not built
and hidden, since a `GPUParticles3D` plus a collision box per pour is real per-frame cost for
something invisible. This deliberately breaks the rule every other feature here follows (leave
an untouched JSON behaving exactly as before): the feedback was about the *default*, so
leaving it on would keep the disliked thing as what you get for doing nothing. A recording made
before this change and re-made after it will differ, which is the intended outcome. See
`08_POUR_STREAM.md`.

**Tuning lives in the dock**, in a **Vertido (chorro de hormigón)** section above the schedule
inspector: a checkbox plus *Cantidad*, *Grano*, *Ángulo*, *Velocidad*, *Altura caída* and
*Salpicadura*. Changes are pushed to the live controller immediately, so the next pour in a
running preview uses them — particle appearance is judged by eye, and an edit-JSON →
restart-preview loop is slow enough that in practice nobody does more than one pass. That is
how the original values shipped without anyone liking them.

| Field | Default | Effect |
|---|---|---|
| `enabled` | `true` when the block exists | `false` is the explicit opt-out; an absent block is the real default |
| `amount` | `800` | Particles in the falling column |
| `grain` | `0` | Particle size in world metres; **0 derives it from the element** |
| `spread_deg` | `8.0` | Emitter cone angle — the fan of the column |
| `speed` | `2.0` | Initial downward velocity: how hard it is pushed |
| `gravity` | `9.8` | Fall acceleration |
| `fall` | `0` | Drop height above the fill surface; **0 derives it from the element** |
| `streak` | `3.0` | Grain-radii each particle is smeared along its velocity |
| `splash_amount` | `220` | Particles in the landing spread; `0` removes it |
| `collide` | `true` | Hide particles on contact with the element |

`grain` and `fall` keep `0` meaning "derive", because that derivation is what makes one stream
read correctly on both a very small element and a very large footing. A non-zero value is
an absolute world-metre override, which is what tuning by eye on one element actually wants.

**Particle lifetime is derived, not exposed.** It is solved from `speed`, `gravity` and `fall`
so a particle's life ends exactly at the surface; a settable lifetime would let someone make
the stream overshoot through the concrete or stop short in mid-air, and there is no reason to
want either.

**Verifying changes here**: a headless harness (31 checks) covered the pour stream during development.

**It is aimed to land on the concrete, not to be stopped by it.** The emitter sits a
computed drop height above the *current* fill surface and rises with it, and the particle
lifetime is solved from that same drop height — `fall = v₀t + gt²/2` for `t` — so a
particle's last frame is exactly at the surface. The rise is one linear tween over the
action's duration, which tracks the fill exactly because `_fill_up_instant()` interpolates
`scale:y` linearly in progress. Consequently the stream's tip is confined to the element's
own vertical span *by construction*: the emitter never goes below `bottom + fall`, so a
particle can never die below the part's bottom face, whatever the frame rate or playback
speed. The solve is against `fall` minus half a streak (below), since a velocity-aligned
particle is drawn smeared around its own position — it is the streak's leading tip, not
its centre, that has to land on the concrete.

**Reading as a fluid rather than as falling gravel** is mostly density and shape:

| | |
|---|---|
| `POUR_AMOUNT` = 800 particles | enough that the column is continuous rather than a scatter of separate lumps |
| `POUR_STREAK` = 3 | each grain is a sphere stretched 3× along its own velocity (`TRANSFORM_ALIGN_Y_TO_VELOCITY`), so consecutive particles overlap into a stream instead of resolving as balls |
| Flat box emission | concrete leaves a chute as a column with a cross-section, not as a ball of independently falling lumps |
| 8° spread | a slight fan, so the streaks aren't all exactly parallel and the column doesn't resolve into vertical stripes |
| `scale_min/max`, `color_initial_ramp` | per-particle size and shade variation — wet concrete is not one flat grey |
| `POUR_SPLASH_AMOUNT` = 220 | a landing spread where the stream meets the surface; without it the stream stops dead at a point, which is the most artificial-looking part of a pour |
| `fixed_fps = 0` | the default 30 visibly steps against a 60 fps recording |

The splash is a child of the stream emitter, sitting exactly `fall` below it — which is
where the stream's tip is, by construction — so it tracks the rising surface with no
bookkeeping of its own. It runs at zero gravity with an upward bias specifically so its
particles can never drift below the surface they are landing on.

**This replaced a version that clipped straight through.** It emitted 8 m above the part's
*centre* with a fixed 1.2 s lifetime, which under default gravity carries a particle
14–19 m — through the element and out the bottom, continuing to the ground. Measured on
a real model: an element spanning 1.8 m in height whose particles died 5.4 m below its base. A `GPUParticlesCollisionBox3D` was supposed to catch them and demonstrably did
not. That collider is still registered (as a child of the part, so it tracks the growing
volume automatically) but nothing depends on it any more — it is a backstop for the case
where playback speed changes mid-pour and the concrete outruns the emitter.

**Every dimension scales with the element**, since elements run from well under a metre
to over twenty metres, and the camera framing one is nowhere near as close
as the camera framing the other:

| Quantity | Rule | Observed range |
|---|---|---|
| Drop height | `span × 0.4`, clamped to `POUR_FALL_MIN`/`MAX` | 1.5 m … 5.0 m |
| Grain (particle radius) | `footprint × 0.025`, clamped | 0.07 m … 0.22 m |
| Stream half-width | `footprint × 0.09`, clamped | 0.25 m … 1.0 m |
| Splash reach | scales with `footprint` | — |

where `span` is the element's largest world dimension and `footprint` its smallest
horizontal one. Drop height keys off `span` rather than the height being filled because a
10 m footing only 1.8 m thick is viewed from far enough away that a stream scaled to its
thickness alone is invisible. `POUR_SPEED`/`POUR_GRAVITY` (`animation_applier.gd`) are
what the lifetime is solved against; velocity is a single value, not a range, so no
particle can overshoot the surface its lifetime was solved for.

Verified headless across all 32 `fill_up` parts (every one keeps its whole streak, tip
included, inside its own geometry at both ends of the pour) and by driving two live pours
frame by frame — the tip trails the rising surface by one frame, ~6% of the element's
height at the harness's frame rate and well under 1% at 60 fps, which reads as concrete
entering concrete rather than as a gap. Also checked by rendering frames at close range
and at the movie camera's own distance, where the whole bridge is in shot.

## Static and excluded geometry

Not everything in a model is *work*. A bridge model carries piles, terrain, survey
markers and imported clutter that either should simply be there from day 0, or should not
appear at all — and neither is a task with a start date, a duration and dependencies.

Two root-level arrays in `construction_steps.json`, siblings of `"steps"`:

| Key | Effect on a matching part |
|---|---|
| `static_prefixes` | Registered normally but **never hidden** — visible from the first frame, permanently, never animated |
| `excluded_prefixes` | **Hidden for the whole run** and never registered in `building_parts` at all |

Both match by `begins_with()`, the same rule `target_prefix` uses. A missing key is an
empty list, so every pre-existing JSON behaves exactly as before.

**Why root-level lists rather than a flag on each action**: they describe *geometry*, not
*work*. An excluded part has no dates, no duration and no dependencies, so modelling it as
an action would force every consumer — CSV export, Project XML export, the topological
sort — to special-case a row that isn't a task. Keeping them out of `"steps"` meant those
subsystems needed no changes at all.

**This replaced the generator's `contexto_*` actions.** `initialize_parts()` used to hide
and zero-scale *every* part unconditionally, so anything absent from the JSON stayed
invisible for the entire run. `IFCScheduleGenerator` worked around that by emitting a fake
one-day `contexto_<zone>` action per structural zone, purely to turn that geometry back
on. It worked, and it put non-work in a work schedule: those rows appeared in the
inspector, the CSV export and the Project XML export as though someone had to build them.
`static_prefixes` says the same thing directly, to the one subsystem that needed to hear
it.

**Excluded parts are hidden, not freed.** The node stays in the scene, so the decision is
reversible by editing one line of JSON rather than by re-importing the model — and freeing
saves nothing meaningful at 65 parts. They are excluded from `building_parts`, which means
no action can match them, no collision shape is built, and they can never appear in a
schedule. The generator drops them before grouping too, so an excluded part produces no
action *even when it carries a perfectly good element id and dates* — the list means
"this isn't part of this project," not "this isn't scheduled."

**Static parts are still collision-checked.** They're real geometry: a permanently-present
abutment should absolutely still flag a clash against an in-transit beam. `CollisionQuery`
only treats in-transit parts as movers, so static geometry participates as a target only —
which is exactly the wanted behaviour, at no cost.

**Both lists survive regeneration.** `IFCScheduleGenerator` reads the file it is about to
overwrite (`read_existing()`) and carries both lists forward, so re-importing a revised
model never loses these decisions — the same self-healing persistence the Project XML
mapping file uses. Newly-discovered context zones are merged in rather than replacing what
is there, and **excluded wins over static**: a prefix moved from one list to the other
stays moved, instead of reappearing as static on the next import. Note this made
generation depend on the file's prior contents, so `write_to()` now reads before it
writes, and the GDIFC dock generates once and writes that result rather than calling
`generate()` a second time for its report.

**`initialize_parts()` is now idempotent.** It mutates the parts it also reads originals
from, so a second run used to record the first run's hidden, zero-scaled state as a part's
`original_scale`. That surfaced immediately here: a part added to `static_prefixes` and
re-applied correctly stopped being hidden and was still scaled to nothing. It now restores
from the metas before re-capturing them, and clears `building_parts` first so a
newly-excluded part actually leaves the registry rather than lingering from the run before.

**Prefixes that match nothing are warned about**, in both lists — a dead entry is almost
always a typo or a leftover from a model revision, and it otherwise fails completely
silently. A part matching *both* lists is warned about too, and excluded wins.

### Flagging and removing actions

The inspector marks any row whose prefix currently matches **zero** parts with a `⚠` and
an amber label, explaining in the tooltip that the geometry is gone, renamed, or covered
by `excluded_prefixes`. This was the third silent failure in the same area: `target_prefix`
matching just finds nothing, and the row looks exactly like one that works.

Each row also gets a **✕ remove** button. No confirmation dialog — it mutates the same
in-memory `sequence_data` every other field edit mutates, so Save to JSON / Reload from
JSON is already the undo, the same safety net a mistyped date has. If the removed action
was named by another action's `depends_on`, the dependents are listed in a warning;
`ConstructionSchedule` already tolerates an unresolvable id (warns individually, excludes
it from the "latest predecessor" calculation, doesn't block the others), so the delete
doesn't cascade — it just says so while the author can still judge whether it mattered.

## Movie Maker Mode

Launching the project in Godot's Movie Maker Mode makes it record itself: playback starts
at day 0 on its own, runs to the last day without stopping, and quits when it's done —
with no UI in frame and nothing that can freeze the recording partway.

**Detection is automatic.** `Engine.get_write_movie_path()` returns the output path when
the editor was launched in Movie Maker Mode and `""` in every other case (verified against
4.6.2 — no project setting or manual flag needed). `SequenceManager._ready()` resolves it
**once** into `movie_mode` and hands that to whatever needs it, rather than having each
subsystem ask `Engine` for itself. That single resolution point is what makes the override
below possible at all.

| Export (on `SequenceManager`) | Default | Effect |
|---|---|---|
| `movie_mode_override` | `false` | Force movie mode on without recording |
| `movie_duration_sec` | `60.0` | How long day 0 → last day should take |
| `movie_end_hold_sec` | `2.0` | Hold on the finished structure before quitting |

**What is drawn over the picture**: the date, top centre, and, when the scene has a
`ConstructionTerrain`, its data credit (`TerrainData.attribution`, e.g. IGN's CC BY 4.0 line)
bottom right. The terrain licences require that credit wherever the ground is shown, so every
recording carries it without anyone remembering to add it.

**`movie_mode_override` exists because otherwise the only way to see what a recording will
do is to record one** — slow, and it writes a file every time. With it on, a plain Play
session behaves identically: same start-to-finish playback, same hidden UI, same clash-gate
bypass, same quit at the end.

**Speed comes from a target length, not days-per-second.** "How long is the video" is the
question anyone recording one is actually asking; days-per-second only answers it after
arithmetic that changes every time the schedule does. `_resolve_movie_speed()` divides the
schedule's span by `movie_duration_sec` — 161 days over 60 s is 2.68 days/sec.
`set_speed()` clamps to `[0.1, 10.0]`, a sane range for the interactive spinbox that a
target length can fall outside of, so the achievable length is compared against the
requested one and any difference is **warned about rather than silently delivered**. The
startup line reports the length the run will actually produce, derived back out of the
speed that was really set.

**Playback under recording is deterministic.** Movie Maker drives `_process(delta)` with a
fixed synthetic delta derived from the target FPS, not real elapsed time, so
`current_day += delta * speed` depends only on the speed setting and never on how fast the
machine renders. Measured: a 20-second target played day 0 → 161 in exactly 1200 frames at
1/60 s — 20.00 s. **The end hold is counted in `delta` for the same reason**; a wall-clock
timer there would have thrown that property away for the sake of two seconds of video.

**Quitting is what actually stops the recording.** Movie Maker writes frames until the
application exits, so a run that merely stops playing produces a video that continues over
a static final frame for as long as the process happens to live.
`TimelineController._tick_movie_end_hold()` counts the hold down and calls
`get_tree().quit()`. It is only ever reached with `movie_mode` true, so the Phase 3 dock —
which shares this class — can never quit the editor.

**The pause-on-collision gate is bypassed, the collision query is not.** The gate is a hard
stop by design (see "Collision detection"), and with nobody there to press Play again it
wouldn't pause a recording, it would end it. `get_collisions()` itself is untouched, so a
recording still reports clashes to anything that asks — it's the *reaction* that's
suppressed, not the query. Verified with a stubbed controller that always reports a
collision: interactive playback stops on the first frame with `collision_paused` set, movie
playback runs the full 161 days.

**Neither `TimelineUI` nor `CollisionVisualizer` is created**, rather than created and
hidden. Both are invisible either way, but both also do real per-frame work a recording has
no use for and would pay for on every written frame: each runs a live `get_collisions()`
query every frame, and `TimelineUI`'s first frame kicks off a full-schedule
`scan_collisions()` that teleports every part through the entire date range. Not building
them is a simpler way to say "no UI in frame" than building them and switching all of that
off from the inside — and it makes skipping the auto-scan fall out for free rather than
needing its own flag.

**Keep the output path outside `res://`.** If
`editor/movie_writer/movie_file` points inside `res://`, Godot's
movie writer emits **one PNG per frame** plus a WAV — so the editor then imports every
single one as a texture. A 60-second recording at 60 fps is 3600 files; a partial run of
a thousand frames means hundreds of MB and thousands of entries in `.godot/imported`,
and the `movie.wav` throws import errors on every editor start. Point `movie_file` at a
directory outside the project, or drop an empty `.gdignore` file in `movie/` so Godot skips
it entirely.

**The free-fly camera is switched off** (`set_process(false)` /
`set_process_unhandled_input(false)`, found by script identity the same way
`_resolve_cranes()` finds cranes). A recording must not be steerable by a stray keypress,
and feature 5 will drive this same `Camera3D`. Interactive runs are untouched — free-fly is
how clashes get inspected.

## Camera keyframes

"On this date the camera is here, on that date it's there" — so a recording can cut to a
close-up of a specific operation instead of watching the whole bridge from one fixed
viewpoint. **Movie mode only**: interactive runs keep the free-fly camera untouched, since
that's how clashes get inspected.

**Its own file, `camera_track.json`** (`SequenceManager.camera_track_path`), not a key
inside `construction_steps.json`. That file is regenerated wholesale from the IFC, and
camera work is hand-authored — the two geometry lists from feature 2 already have to be
explicitly carried across a regeneration to survive it, and a camera track is far more
laborious to author. A separate file removes the hazard instead of managing it.

```json
{
  "keyframes": [
    {
      "date": "2026-04-14",              // or "day": 0.0
      "position": [40.0, 25.0, 60.0],
      "rotation": [-15.0, 33.0, 0.0],    // euler degrees, YXZ (Godot's default)
      "fov": 70.0,                       // optional
      "hold_days": 5.0,                  // optional, default 0
      "cut": false,                      // optional, default false
      "comment": "wide establishing shot"
    }
  ]
}
```

Euler degrees rather than a `Transform3D` literal or a quaternion, because the file is
meant to stay hand-editable: nudging a shot ten degrees left shouldn't mean recomputing a
basis. Dates are the authored form; a bare `day` number is accepted for a schedule with no
calendar dates at all, where there's nothing to convert against.

**Authoring is the hard part, and it's done visually.** Nobody writes a `Transform3D`
literal and then reasons about whether it points at the pier. In the Phase 3 dock: scrub to
a date, fly the editor's own 3D viewport camera to the shot you want, press **Capturar
cámara**. It reads `EditorInterface.get_editor_viewport_3d(0).get_camera_3d()` and appends a
keyframe at the previewed date — what you see is exactly what gets recorded. Unlike every
other control in the dock this writes to disk immediately rather than marking the schedule
dirty: `camera_track.json` is a separate file `sequence_data` knows nothing about, so
routing it through the "mark dirty → Recalculate → Save to JSON" cycle would mean Save to
JSON silently saving two different files. Keyframes are re-sorted by date on every capture,
so the file reads in the order the shots happen however they were added.

**Preview without recording** is `movie_mode_override` (see "Movie Maker Mode") — run the
scene normally with it on and the driver plays the track against the scene's real camera.
That was the spec's third open decision, and it needed no new work: the override built for
feature 3 already answers it. Driving the *editor* viewport camera as you scrub would be
the more integrated answer, but it fights the authoring flow directly — the camera being
positioned is the same camera the preview would be moving.

**Interpolation.** Position lerps; rotation slerps through a `Quaternion` rather than
blending basis vectors component-wise, which wouldn't stay orthonormal and would shear the
view partway through every move. `t` is smoothstepped, so a move eases in and out instead
of changing velocity abruptly at each key — with linear `t` a track of several keyframes
reads as a series of jerks even though each segment is individually smooth. Verified:
quarter-way through a segment lands at 15.6%, not 25%, and the basis determinant stays
1.0000 throughout.

**Two semantics the spec left open, both resolved by supporting both explicitly** — the
same trade the resolved cuts-vs-moves decision made:
- `hold_days` — a keyframe means *be here on this date* (the standard keyframe reading, and
  what "on day X the camera is here" says literally), and `hold_days` then keeps it there
  that many days before the move to the next one begins. Default 0, so a track authored
  without thinking about it behaves the obvious way.
- `cut: true` on a keyframe holds the previous pose right up to its date and then jumps,
  instead of gliding. A glide across the site to reach a close-up would waste ten seconds
  of video.

**Edges are held, not extrapolated.** Before the first keyframe and after the last, the
nearest one applies — a camera drifting off into space either side of the authored range is
nobody's intent. `fov` is forward-filled: a keyframe that doesn't mention it keeps whatever
the last one that did set, so a track that pulls in to 30° doesn't silently pop back to the
scene's own fov at the next keyframe. Keyframes before *any* fov is specified leave the
camera's own value alone.

**With no track present, nothing is created** and movie mode leaves the camera exactly
where the scene put it — `camera_track.json` doesn't ship, so recording works out of the box
without one. `CameraDriver` applies the opening pose immediately on setup rather than
waiting for its first `_process()`, since in a recording that frame is already in the video.
It reads `current_day` rather than keeping its own clock, so the camera is locked to the
same virtual time as the geometry by construction — and inherits Movie Maker's deterministic
synthetic delta for free.

**Not built: look-at targets.** `"look_at": "<part name>"` — keeping a part framed while it's
built, surviving the model moving — is more useful than a fixed rotation and is the obvious
next increment. It needs the driver to resolve part names to live positions each frame and
to reconcile that against the authored rotation, which is real complexity; the spec already
flagged it as possibly separate, and it isn't in the acceptance criteria.

## Verifying changes headless

Much of this codebase can't be checked by reading it — GDIFC is a GDExtension whose bound
API isn't documented anywhere, and several statements in these docs turned out to be wrong
when actually executed (`get_ifc_property_sets()` doesn't exist; `_format_day()`'s comment
about day 0's epoch had been stale for a whole phase). Running a throwaway script against
the real model settles those in seconds.

Write a script extending `SceneTree` and run it against the project:

```bash
godot --headless --path . --script res://diag.gd
```

```gdscript
extends SceneTree
func _initialize() -> void:
    ...           # runs before the first frame
func _process(_d: float) -> bool:
    return true   # true = quit
```

Things that will otherwise cost time:

- **GDIFC loaded twice never finishes a load.** If a second copy of `gdifc.gdextension` sits
  anywhere inside the project (and in `.godot/extension_list.cfg`), Godot prints hundreds of
  `Attempt to register extension class ... already registered` errors and `read_ifc()` returns
  `OK` but `ifc_read` never fires. Put a `.gdignore` in the stray copy's folder and drop its line
  from `extension_list.cfg`. With a single copy, headless loads work in `--script` runs too.

- **`read_ifc()` is asynchronous.** It returns `OK` immediately and emits `ifc_read`
  roughly 17 frames later, so a check written entirely inside `_initialize()` sees no
  geometry. Wait for the signal in `_process()`.
- **A new `class_name` isn't visible to `--script`** until the editor rescans and writes
  `.godot/global_script_class_cache.cfg`. Force it with `--headless --path . --editor --quit`.
- **Building a `ConstructionSchedule` outside `SequenceManager`** needs the metas
  `initialize_parts()` sets (`original_pos`, `original_scale`, `original_transform`,
  `original_aabb`); without them it fails with `Trying to assign value of type 'Nil'`.
- **Filter engine noise** with `grep -vE "Invalid tag|doc_tools"` — an unrelated
  doc-parsing error prints on every single run.
- **`Range.value_changed` does not emit during `_initialize()`.** Setting `.value` on a
  SpinBox before the first frame updates the value silently, so a script exercising an
  inspector field there sees the control change and the handler never run — which looks
  exactly like a broken signal connection. From frame 1 (`_process()`) it emits normally.
  Drive UI controls from `_process()`, not `_initialize()`.
- **A node `add_child()`ed during `_initialize()` isn't in the tree yet**, so any
  `get_tree()` inside the code under test fails on it. Same fix: build the scene in
  `_process()`. If the code under test reads `get_tree().current_scene` (or discovers
  cranes through it), assign `current_scene` — it's a property of the `SceneTree` itself,
  i.e. `self`, not of `root`.
- **`set()` of a property that doesn't exist is a silent no-op.** A GDIFC part exposes
  `properties` from GDExtension; a plain `MeshInstance3D` stand-in does not, so
  `set("properties", …)` does nothing and every fake part looks like it carries no
  property sets at all — the generator then reports zero actions, which reads as a bug in
  the generator. Give the fake a one-line script declaring the property.

Cross-check anything date-related against an independent implementation. Godot's
`Time.get_datetime_dict_from_unix_time()` returns `weekday` as **0=Sunday**, while
Python's `date.weekday()` is 0=Monday — an off-by-one there produces dates that look
entirely plausible and are silently wrong.

## Next features

**All five features specified in `06_PLANNED_FEATURES.md` are built** — calendar dates,
static/excluded geometry, Movie Maker Mode, per-action cadence, and camera keyframes. That
document is now kept for the reasoning behind each; this file describes what they do.

**Formwork is the current work** — `07_FORMWORK.md`, steps 1–5 of 6 built. See "Formwork
(encofrado)" above for what works and "Known gaps" immediately below for what doesn't.

**Phase 4 (packaging) is done as of 0.4.0**: the addon is self-contained and installs into any project. `09_GENERICIZATION.md` records what was generalised and what remains open.

Known gaps, in rough order of how much they'd be missed:

- **Formwork step 6** — the `IFCScheduleGenerator` rule with carry-forward. Until it lands,
  formwork settings are destroyed by the next Generate 4D Schedule, however they were
  authored — the dock's own columns included.
- **Look-at camera targets** (`"look_at": "D4"`) — the one deliberately deferred piece of
  feature 5; see "Camera keyframes" above.
- **Crane geometry isn't collision-checked** — `get_collisions()` only checks
  `building_parts`, so a crane arm sweeping through a finished pier is invisible to the
  clash system. Open since Phase 2; see "Collision detection".
- **GDIFC can drop a mesh on import.** A `[GetMesh()] unexpected mesh type` line in the import log means a member is missing from the video *and* from collision detection, so check the log before signing off a schedule.
- **Continuous-cadence vs. discrete-bucketing** — the one remaining deviation from the
  original design docs. (The pour-particle trigger during Play, previously listed here
  alongside it, is built — see "Concrete pour stream".)
