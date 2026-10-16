# Build4D — as-built reference

*Using the tool rather than changing it? Read the step-by-step guide instead:
[GUIDE.md](../GUIDE.md) (English) · [GUIA.md](../GUIA.md) (español).*

This file describes **what the addon does today and why it is built that way**, subsystem by
subsystem. It is the source of truth when it disagrees with the older planning documents. Exact
signatures are in `04_API_REFERENCE.md`; the history of every change is in `CHANGELOG.md`.

**Version 0.7.0.** Tested with Godot 4.6.2 and 4.7.2 (517 checks in nine headless suites, see
"Verifying changes" at the end).

## The documents

| Document | Kind | What it covers |
|---|---|---|
| `README.md` (this file) | as built | Every shipped subsystem, the data model, how to verify changes |
| `04_API_REFERENCE.md` | as built | Classes, methods and signatures |
| `05_IFC_INTEGRATION.md` | as built | Driving the tool from an IFC model (GDIFC), property mapping, schedule generation |
| `07_FORMWORK.md` | spec + as built | Formwork (encofrado): decisions and build order; steps 1–5 and 7 built, 6 open |
| `08_POUR_STREAM.md` | as built | The concrete pour stream: why it is off by default and how it is tuned |
| `10_TERRAIN.md` | as built | Terrain download, placement, levelled platforms, the date's sun |
| `11_TYPES_REALISM_CLASHES.md` | as built | Animation types read from activity names, the animation set, clash-detection rules |
| `13_SITE_EQUIPMENT.md` | as built | Tower crane, mobile crane, excavator, truck: models, measurements, placement, schedule |
| `12_FUTURE_WORK.md` | to do | **What is next**, in priority order |
| `09_GENERICIZATION.md` | record | What was made generic when the addon left its first project, what is left |
| `00_4D_TOOL_OVERVIEW.md` … `03_PLUGIN_DISTRIBUTION.md`, `06_PLANNED_FEATURES.md` | historical | The original design and plans. Built largely as designed; where they differ, this file wins |
| `CHANGELOG.md` | log | Notable changes per release |

## Layout

```
core/       schedule maths, animations, collision query, formwork generation, type inference
runtime/    SequenceManager (scene root), TimelineController, TimelineUI, Crane, cameras, GeoSun
equipment/  site plant: procedural models, measurements (specs/), placement and schedule
editor/     the dock, schedule inspector, CSV and Project XML import/export, terrain panel
ifc/        IFC import through GDIFC: property scan, mapping, adapter, schedule generator
geo/        UTM, IFC georeference, the model's map origin, sun position
terrain/    terrain providers, download and build, the terrain node, levelling, ground shader
examples/   demo scene and annotated schedule
tests/      headless test suites
```

## What this is

A Godot 4 addon that turns a construction schedule into a scrubbable, date-aware 4D model: drag
a slider to any calendar day and the building snaps to its state on that day, or press Play to
watch it being built — live in the editor or at runtime, on the real terrain of the site, with
the site's plant at work, and as a recorded video.

## Quick start

1. Open `examples/demo.tscn`, or any scene with a `SequenceManager` node
   (`runtime/sequence_manager.gd`) whose `parts_container_path` (**required, no default**)
   points at the node holding the model's parts. Loading an IFC model? The dock's **Load IFC
   (4D)** creates both the container and the `SequenceManager` — see `05_IFC_INTEGRATION.md`.
2. Run the scene. `SequenceManager._ready()` loads `construction_steps.json`, builds the
   schedule and mounts the timeline UI; a scene without a camera, sky or sun gets default ones
   for the run, and a scene without site equipment gets it automatically.
3. Use the bar at the top: drag the **slider** to scrub, **Play/Pause**, the **speed** box
   (schedule days per real second, 0.1–5, default 1), **Reset**. Clashes are scanned for by
   themselves (see "Collision detection").
4. Click in the view to fly (WASD, mouse, Q/E down/up, Shift faster); Escape releases the mouse.

## Data model

`construction_steps.json` holds `"steps"`, each with a list of `"actions"`. An action names its
parts by **prefix** — part names are matched with `begins_with()`:

- `target_prefix`: every part whose name starts with it, or
- `commander_prefix` + `child_prefixes`: one unit per commander, each child part attached to the
  nearest commander in plan (`SpatialGrouper`) — a column and its rebar cage, installed together.

Every other field is optional:

| Field | Meaning |
|---|---|
| `id` | Explicit identifier for `depends_on`, CSV and Project XML. Resolution (`ConstructionSchedule._action_id()`): `id`, else `commander_prefix`, else `target_prefix` |
| `type` | Animation: `scale_up` (default), `drop_in`, `rise_up`, `sink_down`, `fill_up`, `build_up`, `fade_in`, `fade_out`, `install` — see `11_TYPES_REALISM_CLASHES.md` |
| `start_date` | `"YYYY-MM-DD"`. Wins over `depends_on` |
| `duration_days` | Calendar days the action spans (default 1; a value ≤ 0 is read as 1) |
| `units_per_day` | Alternative to `duration_days`: `ceil(unit_count / units_per_day)`, where `unit_count` is commanders for a `commander_prefix` action and matching parts for a `target_prefix` one. An explicit `duration_days` wins |
| `depends_on` | Finish-to-start predecessor(s): one id or an array. The action starts at the **latest** predecessor finish + `lag_days` |
| `lag_days` | Days after that finish; may be negative (a lead). One lag for all predecessors |
| `batch` | `true`: all parts move together (one pour in several meshes). `false` (default): one after another |
| `stagger`, `stagger_accel`, `stagger_min`, `dur`, `dur_accel`, `dur_min` | Cadence tuning — see "Per-action cadence" |
| `formwork` | Formwork block or `true`/`false` — see "Formwork" |
| `crane_id` | `install`: which crane, by node name, instead of the nearest. On any action it also sets that crane's on-site window (see "Cranes") |
| `crane_stand` | With `crane_id`, on a crane with stands: the stand (marker name) the lift is made from, instead of the nearest |
| `rotate` | Built in one pose, then swung into place about a hinge: `{"group", "duration_days", "lag_days", "angle_deg"}` — see `11_TYPES_REALISM_CLASHES.md`, "`rotate`" |
| `comment` | Free text; the generator writes the activity's label and dates here |

And at the **root**, siblings of `"steps"` because they describe the project rather than one task:

| Key | Meaning |
|---|---|
| `static_prefixes` | Parts present from the first frame, never animated |
| `excluded_prefixes` | Parts hidden for the whole run and left out of the tool |
| `formwork_defaults` | Formwork for every action unless an action opts out |
| `pour_stream` | The concrete stream's settings; absent = no stream |

**How a schedule resolves.** Day 0 is the earliest `start_date` in the file, not the unix
epoch. Actions are processed in dependency order (Kahn's algorithm over `depends_on`,
`_topo_order_actions()`), so every predecessor's finish day is known before a dependent needs
it. An unresolvable id is warned about and ignored; a cycle is warned about and broken by
falling back to `start_date` or day 0 — the schedule never raises. An action's finish day is
`start + duration_days`; each part gets its own `[start_day, end_day]` window inside that span
from the cadence (below). `get_part_states(day)` turns those windows into `{anim_type,
progress}` per part, and **both scrubbing and Play go through it**, so they cannot disagree.

`ConstructionSchedule` also exposes what the dock and the other subsystems need:
`get_action_day_range(id)`, `get_part_window(part)`, `day_to_date_string(day)`,
`day_to_epoch(day)`, `has_calendar_dates()`, `source_data` (the JSON it was built from), and
the static date helpers `parse_date_to_epoch()`, `format_epoch_as_date()`,
`end_date_from_start_and_duration()`, `duration_from_start_and_end()`,
`start_date_from_end_and_duration()`.

A file with none of the optional fields still loads: missing dates fall back to day 0, missing
durations to one day.

## How a frame is drawn

```
construction_steps.json ─► ConstructionSchedule ─► TimelineController.scrub_to(day)
                                                         │
          ┌──────────────────────────┬──────────────────┼───────────────────────┬──────────────────────┐
          ▼                          ▼                  ▼                       ▼                      ▼
 AnimationApplier.apply_instant()  GeoSun.update_all()  ConstructionTerrain     SiteEquipment          Crane.retract()
 (every part's state on that day)  (the date's sun)     .update_all()           .update_all()          (manual scrub only)
                                                        (platforms' progress)   (plant on that day)
```

`TimelineController` owns `current_day`. Play is `scrub_to()` every frame with the day advanced
by `playback_speed × delta`; on top of that, forward Play alone fires the one-shot effects —
a `Crane.swing()` when an `install` unit starts, the pour stream when a `fill_up` part starts
(`_detect_install_actions()`, `_detect_fill_up_actions()`). Scrubbing never fires them.
`TimelineUI` (slider, Play, speed, Reset, date) only talks to the controller.

`SequenceManager` is the scene root's script. At runtime `_ready()`: adds a default camera, sky
and sun where the scene has none (`_ensure_view()`); loads the JSON; generates formwork;
registers and hides the parts (`initialize_parts()`); builds or finds the site equipment
(`SiteEquipment.ensure()`); collects the cranes; builds the `ConstructionSchedule`; mounts the
`TimelineController`, then either the `TimelineUI` and `CollisionVisualizer` or, in movie mode,
the movie run. In the editor `_ready()` does nothing — the dock drives the same calls explicitly.

`AnimationApplier.apply()` builds live tweens for the same types. The runtime does not use it
(Play goes through `apply_instant()`); it is kept for callers that want a one-shot tweened
animation and is exercised by the tests.

## Parts: registration, static and excluded geometry

`initialize_parts()` registers every child of `parts_container_path` and of each node in
`extra_part_containers` (`collect_part_nodes()`, the same read-only selection the dock uses),
records each part's `original_pos`, `original_scale`, `original_transform` and `original_aabb`
as metas, gives it its own copy of every material (so fading one part never fades another), and
hides and zero-scales it. It restores from the metas before re-capturing them, so running it
again — every Start Preview does — is safe.

| Root key | Effect on a matching part |
|---|---|
| `static_prefixes` | Registered but **never hidden**: visible from the first frame, never animated. Still a collision target |
| `excluded_prefixes` | **Hidden for the whole run** and never registered: no action can match it, no collision shape is built |

Both match by `begins_with()`. They are lists at the root rather than flags on an action
because they describe geometry, not work: an excluded part has no dates, so making it an action
would force CSV, Project XML and the dependency sort to special-case a row that isn't a task.
Excluded parts are hidden, not freed, so the decision is reversible by editing the JSON. A
prefix that matches nothing, or a part matching both lists, is warned about (excluded wins).
`IFCScheduleGenerator` carries both lists forward when it regenerates the schedule.

In the dock, a row whose prefix matches **no** part is marked ⚠ in amber, and every row has a
**✕** to remove the action (no confirmation: stopping the preview and answering *Descartar* is
the undo; dependents of a removed action are listed in a warning).

## Animation types

`AnimationApplier.TYPES` lists the types an element can have — `scale_up`, `drop_in`, `rise_up`,
`sink_down`, `fill_up`, `build_up`, `fade_in`, `fade_out`, `install` — and is the single list
the dock's dropdown is built from. What each looks like, which work it suits and how the
activity name chooses it are in `11_TYPES_REALISM_CLASHES.md`. In short:

- `fill_up` (a pour) and `build_up` (masonry, scaffolding) fill the element up to a level that
  rises in world +Y from its lowest point to its highest, whatever its orientation (a flat top
  closes the cut: `core/fill_clip.gdshader`, on meshes `MeshPrep` turns outward);
  `scale_up` grows uniformly from the middle of its base without overshoot; `drop_in` lowers a
  piece from 1.5 m + 1.5 × its height (2.5–8 m) with a fade-in; `rise_up`/`sink_down` move the
  whole element 10 m; the fades respect each material's own transparency; `install` lifts the
  piece from its crane's pickup point, slides it across and lowers it in (30/40/30 % of its
  window), and is the only type checked for clashes.
- `formwork` is a lifecycle the schedule assigns to formwork panels, not a type an element can
  have, and is deliberately not in `TYPES` — see "Formwork".
- Every type is applied from metas only (`original_*`), never from the live transform, so
  playing, scrubbing and re-scrubbing agree.

**Types from activity names.** `TaskClassifier` reads Spanish, Galician, Portuguese and English
construction vocabulary — *hormigonado* pours, *mampostería* builds up, *excavación* sinks — and
gives each action a type and a `batch`. It is used by schedule generation when the model states
no type, and by the dock's **Auto types** button. It never picks `install`.

## Per-action cadence

**The animation shows the construction method, not only the activity.** A pour modelled as four
meshes is one operation — its parts rise together (`batch: true`); four precast columns are four
operations — they arrive one at a time (`batch: false`). `Cadence.compute_timings()` turns the
action's parts, in placement order, into offsets and durations:

| Field | Default | Effect |
|---|---|---|
| `batch` | `false` | `true` = every part moves at once |
| `stagger` | `0.75` | Delay between consecutive parts |
| `stagger_accel` | `1.0` | Multiplier on the delay after each part |
| `stagger_min` | `stagger` | Floor for the accelerating delay |
| `dur` | `1.0` | Per-part animation length |
| `dur_accel` | `1.0` | Multiplier on the length after each part |
| `dur_min` | `dur` | Floor for the accelerating length |

These are **relative**: the whole cadence is normalised onto the action's `duration_days`, so
`stagger` redistributes the parts inside the same window and never changes its length. To make
an action take longer, change `duration_days`. The cadence is one continuous curve across the
window, not per-day buckets.

**Placement order** (`SpatialGrouper.sort_by_position()`): bottom-up by level (bases within
0.5 m count as one level), then across the plan. A quoin is set on the one below it; ordering by
plan alone had pieces placed above ones still to come.

**Where `batch` comes from.** `TaskClassifier` decides it per kind of work (pours, masonry,
earthworks together; stone pieces, windows, framing, planting one by one). A type taken from the
model's own property gets `IFCScheduleGenerator.batch_for()`: `true` unless the type is
`install` or `drop_in`. Either way it is written explicitly into the JSON, one toggle away in the
inspector, and a hand-corrected value survives regeneration. Inferring `batch` from geometry was
measured and rejected: on a real model two separate footings were closer together than three
segments of one girder.

**In the inspector**: *Cadencia* (*Simultáneo* / *Escalonado*) and *Escalonado (s)* for
`stagger`, greyed out where it has no effect (batched, or a single part).

## Calendar dates

The slider reads a date — `mar 14/abr/2026 · día 0.0` — built by `TimelineUI._format_day()` from
`has_calendar_dates()` and `day_to_epoch()`. Spanish abbreviations, matching the dock. The
weekday is deliberate: an IFC model's durations often count working days while the timeline
counts calendar days, and a weekend inside an activity should be visible. The day number stays
as a secondary detail because the collision scan samples at 0.01 day. A schedule with no
parseable `start_date` falls back to `Day 12.0` labels instead of showing 1970.

## Cranes

Any number of nodes running `runtime/crane.gd` can be in a scene; each finds its own `Arm`
(slews, jib along its local +X), `Track` (trolley), `Hook`, `Rope` and optional `PickupZone`
children by name. A scene with no crane of its own gets the tower crane from `SiteEquipment`,
which is a `Crane` like any other.

- **Discovery**: `SequenceManager._resolve_cranes()` finds every `Crane` in the scene by script
  identity; `crane_paths` overrides it. Cranes are keyed by node name, so give each a distinct
  one.
- **Assignment**: per `install` unit (one commander and its children), the crane nearest in plan
  (`ConstructionSchedule._assign_crane()`); an action's `crane_id` overrides it, and an unknown
  id warns and falls back to the nearest.
- **Pickup**: `Crane.get_pickup_position()` — the crane's `PickupZone` when it has one (every unit
  it serves is staged there, invisible until its turn), else 15 m to the side of the piece.
  `_cache_ground_start()` stores it on the part as a *local* position.
- **Motion**: `swing()` when a unit starts during forward Play (the arm slews to the pickup, then
  the trolley and hook track the piece), `retract()` on every manual scrub (its tween is the
  crane's, so a lift starting straight after stops it instead of being pulled back to rest). The
  site equipment's tower crane also follows the `drop_in` pieces it can reach.
- **Luffing boom** (0.7.2): a crane with a `Boom` under `Arm` -- a crawler or lattice-boom crane,
  `Track` being its head -- reaches each lift's radius by pitching the boom about its heel
  (15-85°), so the rope stays at the boom tip, instead of running a trolley out along a jib.
  The heel and length are measured from the boom's mesh at `_ready()`.
- **On site** (0.7.2): a scene crane is shown only inside its window (`ConstructionSchedule.
  crane_window()`): `on_site_from` / `on_site_until` (an action id -- its start / its finish --
  or a `YYYY-MM-DD` date), or else `setup_days` (default 1) before the first and after the last
  action naming it in `crane_id` or lift assigned to it. A crane with neither stands throughout,
  as before. `TimelineController.scrub_to()` applies it; the editor preview does too (the dock
  hands it the scene's cranes with `set_site_cranes()` and Stop Preview restores them).
- **Stands** (0.7.2): a crane's `stands` (NodePaths to markers -- a `Marker3D` shows in the
  editor, and can be moved and turned there) are where it works from. Each lift is made from the
  stand its action names in `crane_stand`, or else the nearest to the piece
  (`ConstructionSchedule.nearest_stand()`); its laydown goes with it (`get_pickup_position(target,
  stand)`). `crane_pose()` puts the crane at the stand of the lift under way, drives it across in
  the gap between lifts from different stands (straight, at constant speed; it is not
  clash-checked), and leaves it at its first stand before and its last after. The arm is kept
  relative to the crane's root (`_arm_rest_local`), so it slews from wherever the crane stands;
  `place_at()` moves it. In the editor preview the placeholder is moved and Stop Preview puts it
  back.
- **Off the piece once it lands**: when none of its lifts is under way
  (`ConstructionSchedule.crane_lifting()`), the timeline retracts a crane still following a
  piece, instead of the hook staying on it (and the boom flattening as a crane with stands drives
  off to the next one).
- **Pickup before `_ready()`**: the schedule asks for `PickupZone` while `SequenceManager` gets
  ready, before a crane later in the tree has run its own `_ready()`; the zone is looked up
  there and then.
- **Not clash-checked**: the cranes' own geometry is not part of the collision query.

## Collision detection

`ConstructionSchedule.get_collisions(day, building_parts)` (delegating to `CollisionQuery`)
reports parts **in transit during an `install`** (0 < progress < 1) whose geometry overlaps
another part that is present that day. The rules that decide what counts, and their measured
effect, are in `11_TYPES_REALISM_CLASHES.md`, section 3; the mechanism:

- **Exact shapes, not boxes.** Each `MeshInstance3D` part gets a trimesh (registered as a raw
  `PhysicsServer3D` area — no scene nodes — on a dedicated layer) and a convex hull (kept as a
  resource). The mover queries with its hull against every other part's trimesh, via
  `PhysicsDirectSpaceState3D.intersect_shape()` — Godot supports convex-vs-concave queries but
  not concave-vs-concave. AABBs flagged near-misses on skewed members; `Area3D` lags a physics
  tick behind instant-applied parts. Transforms are pushed to the areas right before each query,
  which assumes physics on the main thread (the default).
- **Movers only.** Only in-transit `install` parts are checked against the rest; steady-state
  contact is normal building geometry.
- **Designed contact is not a clash.** Pairs that touch or overlap in the *finished* model are
  ignored (computed once from every part's `original_transform`); the mover's hull is inset by
  2 cm (`CONTACT_TOLERANCE`); parts at near-zero scale count as absent.
- **Units, not leaves.** Parts installed together (`_sibling_groups`) are excluded from each
  other; hits are reported once per commander pair (`_part_to_commander`); parts not active that
  day are ignored.
- **Approximate overlap.** `overlap_volume`/`overlap_aabb` are an AABB intersection — the query
  only says *whether* shapes overlap — used to size the marker and pick the largest hit.
- **Generated formwork panels and the site equipment are not registered.**

What the user sees: `TimelineUI` shows a warning line with the clashing pair at the current day;
`CollisionVisualizer` draws a red, always-on-top box at each live clash (pooled meshes,
`min_marker_size` 0.6 m, `size_padding` 0.3 m); forward Play **stops** on a clash
(`collision_paused`, "Play (blocked)") — a hard gate, not a revert, so the state stays
inspectable; and the scan (`TimelineController.scan_collisions()`, run by `TimelineUI` once
each time it is wired to a schedule — at start, and after every rebuild in the dock) steps
through every install window at 0.01 day, merges hits into
`{part1, part2, start_day, end_day}` windows, prints them and paints them red on the slider
(`CollisionOverlay`, with a hover tooltip). There is no scan button: the schedule cannot change
during Play, so a second scan could only repeat the first. A schedule with no `install` parts
skips the scan entirely, and builds no collision shapes at all (`ConstructionSchedule` calls
`CollisionQuery.setup()` only when `has_install_parts()`) — most of what a rebuild costs. In movie mode the gate is bypassed and the UI is not built.

## The editor dock

`plugin.gd` mounts `editor/timeline_dock.gd` as the **Build4D** dock (right side). It reuses
`ConstructionSchedule`, `TimelineController`, `AnimationApplier` and `TimelineUI` exactly as they
run at runtime; `@tool` on those scripts is what lets them run in the editor. The dock finds the
edited scene's `SequenceManager` by script identity.

**Layout: what the work needs, in its order** (0.7.0). Steps that always follow one another are
one control, steps the tool can take itself are not controls, and what only applies while
previewing is hidden rather than greyed out (a dock full of disabled buttons read as clutter).
With the preview off the dock shows one row — **Load IFC (4D)** with a **▾** menu, **Start
Preview**, **Importar…**, **Maquinaria** — and the **Terreno** section.

| Control | Does |
|---|---|
| **Load IFC (4D)** | Imports the model, then writes the schedule: with no JSON yet, the full generation (`IFCScheduleGenerator.generate()`); with one, only the actions of activities nothing in it covers (`add_new_actions()`), leaving every existing action alone. Then the terrain (`TerrainPanel.on_ifc_imported()`) |
| **▾** → **Generate 4D Schedule** | The full regeneration, explicit because it re-reads every date from the IFC (losing Project XML dates) and drops formwork |
| **▾** → **Edit IFC mapping** | The property dialog again |
| **Start Preview** / **Stop Preview** | One toggle. Stopping with unsaved edits asks *Guardar / Descartar / Cancelar* (`_stop_then()`) |
| **Importar…** | Project XML or CSV, by the file's extension. Starts the preview if it is off |
| **Maquinaria** | Site equipment markers (`13_SITE_EQUIPMENT.md`); stops the preview first, through the same question |
| Preview only: **Save to JSON**, **Exportar…**, **Auto types**, **Capturar cámara**, *Vertido*, *Encofrado en todo el proyecto*, the inspector | Below |

Removed in 0.7.0, and why: *Recalculate* (edits rebuild by themselves), *Reload from JSON* (Stop →
Descartar → Start does it, and the question on Stop protects edits instead), four separate
CSV/XML buttons (two, by extension), *Stop Preview* as its own button, *Generate 4D Schedule* and
*Edit IFC mapping* as buttons (in the ▾ menu), *Scan Collisions* on the timeline bar (see
"Collision detection"), and five terrain buttons (`10_TERRAIN.md`, "The dock").

**Preview, and its restore guarantee.** Start Preview snapshots every part's material overrides
(and every `GeoSun`'s transform), runs `load_json()`, `_generate_formwork()` and
`initialize_parts()` exactly as `_ready()` would, builds a schedule and embeds the timeline UI.
Stop Preview — the button, switching scene tabs, or disabling the plugin — restores position,
scale and visibility from the metas, materials from the snapshot, resets terrain and site
equipment, sweeps generated formwork, and frees the scratch controller and UI. A warning label
says not to save while previewing. Switching scene tabs with unsaved edits stops the preview at
once (the scene has already changed) and then offers to save the edits to that scene's JSON;
disabling the plugin only warns. The preview builds the schedule with **no cranes**, so
`install` swings and the tower crane's lifts are runtime-only; a `SiteEquipment` node in the
scene does follow the preview's dates. There is no 3D collision marker in the dock.

**Schedule inspector** (`ScheduleInspector`, one row per action, 15 columns): *ID*, *Acción*,
*Tipo*, *Cadencia*, *Escalonado (s)*, *Ancla*, *Fecha Inicio*, *Fecha Fin*, *Duración (días)*,
*Unidades/Día*, *Encofrado*, *Días vertido*, *Depende De*, *Retraso (días)*, ✕. Labels are
Spanish for the crews who author schedules; every value written to the JSON stays the English
key (each dropdown item stores it as metadata), and headers carry the English field name as a
tooltip. Edits change `sequence_data` in place, mark it **unsaved** and restart a 0.4 s one-shot
timer; when it fires the dock rebuilds the schedule (`_rebuild_schedule()`, keeping the scrubbed
day), so five clicks on a SpinBox arrow rebuild once. Without `install` actions a rebuild builds no
collision shapes, which is what made per-edit rebuilding affordable; it used to be an explicit
*Recalculate* button. **Save to JSON** writes the file and is greyed out when nothing is unsaved.

- **ID** edits rebuild the grid, since other rows' *Depende De* may reference it. *Acción* shows
  the resolved identity and, when an explicit id differs, the prefix too.
- **Ancla** (anchor) keeps `End = Start + Duration` consistent: it names the slot held fixed when
  one of the other two is edited.

  | Anchor | Edit | Recomputed |
  |---|---|---|
  | Start | Duration/Units | End = Start + Duration |
  | Start | End | Duration = End − Start |
  | Duration (default) | Start | End = Start + Duration |
  | Duration (default) | End | Start = End − Duration |
  | End | Start | Duration = End − Start |
  | End | Duration/Units | Start = End − Duration |

  Editing the anchored field itself is allowed (Duration or Start pushes End; End pushes Start).
  *Fecha Fin* needs a start date to compute from.
- **Depende De / Retraso**: a comma-separated list of ids and a lag. Setting a dependency erases
  `start_date` and typing a start date erases `depends_on`, so a row can never show a date and a
  dependency that disagree. A dependent row shows its resolved dates (Start as placeholder text,
  End as text), refreshed after every rebuild (`refresh_dependency_dates()`).
- **Duración / Unidades/Día** are two views of one rate; editing either recomputes the other and
  only `duration_days` is written (exactly, not rounded up, so a typed rate round-trips).
- **Encofrado / Días vertido** — see "Formwork".
- **Auto types** sets every recognised row's *Tipo* and *Cadencia* from its name and prints each
  change.

Other preview controls: **Exportar…** (Project XML or CSV, by extension; a name with neither gets
`.xml`), **Capturar cámara** (camera keyframes), **Encofrado en todo el proyecto** (project-wide
formwork), and **Vertido** (pour stream), whose six tuning fields fold under *▸ Ajustes* since each
has a default derived from the element. Buttons sit in flow containers and wrap in a narrow dock.

### CSV import/export

`ScheduleCsvIO` writes and reads exactly the fields the inspector edits: `id`, `action`
(read-only label), `type`, `start_date`, `end_date`, `duration_days`, `units_per_day`,
`depends_on`, `lag_days`, `formwork_mode`, `pour_days`, `strip_days`, `comment`. Geometry links,
cadence tuning and formwork geometry stay JSON-only. Import matches rows to existing actions by
resolved id and never creates one (an action needs geometry a CSV cannot supply); it applies the
inspector's own exclusions (start date vs dependency, duration vs rate). **A blank cell erases a
field, an absent column leaves it alone.** `end_date` is derived on export and used on import
only when neither duration column exists.

### Microsoft Project XML import/export

`ScheduleProjectXmlIO` reads and writes Project's XML Interchange format (MSPDI), not the binary
`.mpp`, which is proprietary and only writable by Project itself.

- **Export** writes every dated action as a manually scheduled task with literal Start/Finish
  (the schedule is in continuous calendar days and must not be re-flowed through Project's
  working-time engine), Task Name = the resolved id, `depends_on` as Finish-to-Start links and
  `lag_days` as `LinkLag` in tenths of a minute.
- **Import** resolves each task to an action through, in order: the persisted mapping file
  (`<schedule>.project_mapping.json`), an exact Task Name = id match, and otherwise
  `ProjectXmlMappingDialog`, which asks once (Cancel aborts the whole import). Every resolution is
  written back to the mapping file. Only Finish-to-Start links are honoured; a resolved
  dependency erases `start_date`. Duration is read as Finish − Start.
- **Phase groups**: one Project task can map to a chain of actions, `{anchor_id, terminal_id}`.
  Only the anchor's dates are written — the rest of the chain cascades through its own
  `depends_on`/`lag_days` — and the terminal's computed finish is compared with the task's
  Finish; a mismatch is reported, never rescaled.
- `XMLParser` is a pull parser; self-closing tags never emit an end node, so the parser closes
  them inline to keep its element stack right.

## IFC input

The dock's **Load IFC (4D)** imports a model through the separate GDIFC addon. The plugin ships
no property names: `IfcPropertyScanner` lists what the model carries, `IfcMappingDialog` asks
which properties are the element id, the dates, the display name and the type (`IfcMapping`,
saved as `<schedule>.ifc_profile.json` and reused silently when it fits the next file).
`GDIFC4DAdapter` names parts after the element id; `IFCScheduleGenerator` writes the schedule
(**Generate 4D Schedule**), keeping hand-corrected types and batches, and the static/excluded
lists. Several IFC files can share a scene: each later one becomes an extra container placed by
its georeference (`IfcSceneModels`). The import records the model's position on Earth in
`SequenceManager.geo_origin`. Everything else — mapping, recentering, accented-text repair,
limits — is in `05_IFC_INTEGRATION.md`.

## Terrain and sun

`ConstructionTerrain` lays the downloaded ground (Spain: IGN 5 m elevation and 25 cm orthophoto;
elsewhere: elevation only) under the model from `geo_origin`, levels pads and excavation pits
(`TerrainPlatform`, `TerrainGrading`) that follow their earthwork activities on the timeline, and
`GeoSun` places the sun for the schedule's date at a fixed time of day. See `10_TERRAIN.md`.

## Site equipment

`SiteEquipment` puts a tower crane, a mobile crane, an excavator and a tipper truck on site with
no setup, places them from the model (and on the terrain), and brings them on and off site by
the `TaskClassifier` categories of the activities. The excavator is built to Caterpillar's
published 320 measurements (`equipment/specs/`, `EquipmentSpecs`). See `13_SITE_EQUIPMENT.md`.

## Formwork (encofrado)

**A five-day element is not a five-day pour** — it is four days of forms and one of concrete. An
action with formwork has its window split: panels assemble over the head, the element's own
animation runs in the last `pour_days`, and the panels hold through the pour and any cure, then
strip.

```
   S                                   S+F        S+D              strip
   |------------- formwork -------------|-- pour --|--- cure ---|--------|
   |  boards go up one after another    |  fill_up |            | fade   |
```

| Field (`formwork` / `formwork_defaults`) | Default | Effect |
|---|---|---|
| `pour_days` | `1.0` | The pour's length; formwork gets the rest of the window |
| `formwork_days` | — | Explicit alternative; wins if both are present |
| `strip_days` | `0.0` | Cure days after the pour before the forms come off |
| `strip` | `true` | `false` keeps them: lost formwork (*encofrado perdido*) |
| `type` | `scale_up` | How a panel appears |
| `strip_type` | `fade_out` | How it comes off |
| `batch` | `false` | Panels stagger even when the concrete batches |
| `board_width` | `2.5` | Target board width (world m) |
| `thickness` | `0.05` | Board thickness (world m) |
| `prefix` | — | **Tier 1**: the forms are modelled in the scene; those parts are the forms |
| `model` | — | **Tier 2**: a `res://` `.glb`/`.tscn` panel placed at every computed position |
| `enabled` | `true` | `false` (or `"formwork": false`) opts one action out of the defaults |

With neither `prefix` nor `model`, **tier 3**: generated wood boards. `pour_days` is the primary
field because a pour's length is a property of the element while the prep expands to fill the
programme: when a revised model moves an element from 5 to 8 days, `pour_days: 1` is still right.
`"formwork": {}` and `"formwork": true` turn it on with the defaults.

How it works:

- **More parts with their own window, not a new timeline concept.** `FormworkBuilder.build()`
  generates the panels before `initialize_parts()`, so they register as ordinary parts;
  `ConstructionSchedule._schedule_formwork()` gives each a window on the head of the action. A
  panel's `anim_type` is `formwork`: `_formwork_instant()` maps assemble → hold → strip onto one
  0–1 progress, reading per-panel boundaries from a `formwork_phases` meta and composing the
  ordinary `type`/`strip_type` animations. Each phase re-applies the other's boundary state
  first, which is what makes scrubbing backwards correct.
- **Boards follow the mesh's vertical faces**, not its bounding box: triangles within ~14° of
  vertical are clustered into planar patches (normals within 15°, at most 0.15 m off the seed
  plane), split into laterally contiguous runs, and subdivided into 1–8 boards per run; inward
  faces (a hollow girder's inside) are skipped; the 40 largest patches per part survive. On a
  real model, box-face boards sat 5.0 m from the concrete on average and face-derived boards
  0.10 m. The box is the fallback for a mesh with no usable vertical face.
- **Idempotent and never saved.** `build()` sweeps its previous output first, so every Start
  Preview leaves the same scene; panels carry a `formwork_of` meta and no `owner`, so they are
  never written to the `.tscn`; Stop Preview sweeps them.
- **Prefix matching can never eat the forms.** Generated panels are excluded from work matching
  by their meta, tier-1 forms by a project-wide index resolved before any action is scheduled
  (action B's prefix must not match action A's forms either), in both the `target_prefix` and the
  `commander_prefix` branches.
- **No room, no forms.** If `duration_days <= pour_days` the action pours across its whole window,
  generates nothing and warns; a tier-1 action in that case still schedules its forms (with an
  instant assemble), since scene geometry excluded from work would otherwise never appear.
- **Stripping extends the date range, never an action's finish**, so `depends_on` is unaffected.
  The strip itself lasts a quarter of the formwork span, 0.25–1 day.
- **Tier-2 panels** are scaled to fill each board, centred on their own AABB (assets are often
  pivoted at a corner), turned so their thin axis faces out, and loaded once per path; a bad path
  warns and falls back to tier 3. Fades and material duplication recurse into composite panels.
- **Generated panels are not clash-checked** (they multiply the part count 3–5×); tier-1 forms,
  being ordinary scene parts, are.

**In the dock**: *Encofrado en todo el proyecto* writes `formwork_defaults` with a project-wide
*Días vertido*; each row's *Encofrado* (*No* / *Genérico* / *Modelo* / *Prefijo*) shows the
**resolved** tier and has its own *Días vertido*. *Modelo* and *Prefijo* are selectable only once
the JSON supplies the path or prefix. A row too short for a formwork phase shows *Días vertido*
in amber.

**Not yet built**: carrying formwork through Generate 4D Schedule (build order step 6) — today a
regeneration drops it. A later Load IFC does not regenerate, so it keeps formwork. Scaffolding rides on tier 1 as a stopgap; the rework is item 1 of
`12_FUTURE_WORK.md`.

## Concrete pour stream

A `fill_up` part, when its window starts during forward Play, spawns a falling stream of concrete
(`AnimationApplier.fire_fill_up_particles()`). **Off unless the project turns it on**: with no
root `pour_stream` block no particle node is built at all. The dock's **Vertido** section turns it
on and tunes it live (changes reach the running preview immediately). The reasoning is in
`08_POUR_STREAM.md`.

| Field | Default | Effect |
|---|---|---|
| `enabled` | `true` when the block exists | `false` turns it off |
| `amount` | `800` | Particles in the column |
| `grain` | `0` | Particle radius in metres; **0 derives it from the element** |
| `spread_deg` | `8.0` | Fan of the column |
| `speed` | `2.0` | Initial downward velocity |
| `gravity` | `9.8` | Fall acceleration |
| `fall` | `0` | Drop above the fill surface; **0 derives it from the element** |
| `streak` | `3.0` | How far each grain is stretched along its velocity |
| `splash_amount` | `220` | Particles in the landing spread; `0` removes it |
| `collide` | `true` | Hide particles on contact with the element |

**It lands on the concrete by construction.** The emitter sits `fall` above the *current* fill
surface and rises with it (one linear tween, which tracks the linear fill exactly), and the
particle lifetime is solved from that drop (`fall = v₀t + gt²/2`, minus half a streak), so a
particle's last frame is at the surface whatever the frame rate. Derived sizes follow the
element: drop `span × 0.4` (1.5–5 m), grain `footprint × 0.025` (0.07–0.22 m), stream half-width
`footprint × 0.09` (0.25–1 m). The splash is a child of the emitter at zero gravity, so it never
sinks below the surface. Scrubbing has no stream: a one-shot burst has no meaning at an arbitrary
scrub position.

## Movie Maker Mode

Run the project in Godot's Movie Maker Mode and it records itself: playback starts at day 0 by
itself, runs to the last day, holds, and quits — with only the date (and the terrain's data
credit, when there is terrain) drawn over the picture.

| `SequenceManager` export | Default | Effect |
|---|---|---|
| `movie_mode_override` | `false` | Movie behaviour without recording, to check a run in plain Play |
| `movie_duration_sec` | `60.0` | How long day 0 → last day should take |
| `movie_end_hold_sec` | `2.0` | Hold on the finished site before quitting |
| `camera_track_path` | `res://camera_track.json` | Camera keyframes, below |

- **Detection** is `Engine.get_write_movie_path() != ""`, resolved once in `_ready()` into
  `movie_mode` and handed to whatever needs it — which is what makes the override possible.
- **Speed from a target length**: span ÷ `movie_duration_sec`, clamped to 0.1–10 days/s; when the
  target is out of reach the run warns and reports the length it will actually produce.
- **Deterministic**: Movie Maker drives `_process()` with a fixed delta, so playback and the end
  hold (counted in `delta`, not wall time) depend only on the settings.
- **Quitting ends the recording** (`_tick_movie_end_hold()`); only reachable with `movie_mode`
  true, so the dock can never quit the editor.
- **No UI, no clash gate**: `TimelineUI` and `CollisionVisualizer` are not built (each runs a
  collision query every frame, and the UI starts a full scan), the clash gate is bypassed (it
  would end a recording, not pause it), and the free-fly camera is disabled.
- **Keep the output outside `res://`**: a path inside the project makes Godot import every frame
  as a texture.

## Camera keyframes

"On this date the camera is here." Movie mode only (interactive runs keep the free-fly camera).
Keyframes live in their own file, `camera_track.json`, because `construction_steps.json` is
regenerated from the IFC and camera work is hand-authored.

```json
{
  "keyframes": [
    {
      "date": "2026-04-14",
      "position": [40.0, 25.0, 60.0],
      "rotation": [-15.0, 33.0, 0.0],
      "fov": 70.0,
      "hold_days": 5.0,
      "cut": false,
      "comment": "wide establishing shot"
    }
  ]
}
```

`date` or a bare `day`; `rotation` in Euler degrees (YXZ) so the file stays hand-editable; `fov`,
`hold_days` (stay this long before moving on), `cut` (jump instead of glide) and `comment` are
optional. **Authoring**: in the dock, scrub to a date, fly the editor's viewport camera to the
shot, press **Capturar cámara** — written straight to the file (it is not part of
`sequence_data`), sorted by date. **Playback** (`CameraTrack`, `CameraDriver`): position lerps,
rotation slerps through a quaternion, `t` is smoothstepped; edges hold the nearest keyframe; `fov`
carries forward from the last keyframe that set one; the driver reads `current_day`, so it is
locked to the geometry's time. **Preview** with `movie_mode_override`. No track: the camera stays
where the scene put it. **Not built**: look-at targets (`12_FUTURE_WORK.md`).

## Default view and the free-fly camera

A scene made the documented way has no camera, environment or light. At runtime
`SequenceManager._ensure_view()` adds, for that run only and only what is missing: a `Camera3D`
with `free_look_camera.gd`, framed on where the work is (`_action_box()`: the middle 80 % of part
centres, grown by half the median part size, so a boundary wall or a crane does not push it
back); a procedural-sky `WorldEnvironment`; a shadowed `DirectionalLight3D` (a `GeoSun` counts as
one). The free-fly camera: left-click captures the mouse, WASD move, Q/E down/up, Shift ×3,
mouse looks (pitch ±89°), Escape releases; input is read in `_unhandled_input()` so clicks on the
timeline UI never capture the mouse. `move_speed`, `vertical_speed`, `mouse_sensitivity`,
`sprint_multiplier` are exported.

## Known limitations

- **Crane geometry is not clash-checked**, and only `install` lifts are checked at all, along a
  fixed path (up 5 m, across, down).
- **Formwork does not survive Generate 4D Schedule**; scaffolding needs JSON editing
  (`12_FUTURE_WORK.md`, item 1).
- **The pour stream and crane swings exist only during forward Play**; scrubbing applies states
  instantly.
- **Cadence is one continuous curve** across an action's window, not per-day buckets as the
  original roadmap described.
- **Scale**: `rise_up`/`sink_down` move a fixed 10 m and the `install` path is in fixed metres,
  tuned for buildings.
- **GDIFC can drop a mesh on import** (`[GetMesh()] unexpected mesh type` in the log): that member
  is missing from the video and from collision detection.

## Verifying changes

Nine headless suites in `tests/` (517 checks). Register class names once, then run each:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_animations.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_collisions.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_equipment.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_geo.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_mapping.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_scene_models.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_georef_gdifc.gd   # needs GDIFC
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_task_classifier.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_terrain.gd
```

For anything the suites don't cover, a throwaway `SceneTree` script settles it in seconds:

```gdscript
extends SceneTree
func _initialize() -> void:
    ...           # runs before the first frame
func _process(_d: float) -> bool:
    return true   # true = quit
```

Things that otherwise cost time:

- **A new `class_name` is invisible to `--script`** until the editor has rescanned
  (`--headless --editor --quit`).
- **`read_ifc()` is asynchronous**: it returns `OK` at once and emits `ifc_read` about 17 frames
  later. Wait for the signal.
- **GDIFC registered twice never finishes a load.** A second copy of `gdifc.gdextension` inside
  the project (and in `.godot/extension_list.cfg`) prints `already registered` errors and
  `ifc_read` never fires. Add a `.gdignore` to the stray copy and drop its line from that file.
- **A schedule built outside `SequenceManager`** needs the `original_*` metas
  `initialize_parts()` sets.
- **Nodes added in `_initialize()` are not in the tree yet**, and `Range.value_changed` does not
  emit there; build scenes and drive UI from `_process()`. Code that reads
  `get_tree().current_scene` needs `current_scene` assigned on the `SceneTree` (`self`).
- **`set()` of a property a node doesn't have is a silent no-op** — a plain `MeshInstance3D`
  standing in for a GDIFC part has no `properties`; give the stand-in a script declaring it.
- **Visual checks**: run the script *without* `--headless` and save
  `get_root().get_texture().get_image()` as PNG after a few frames.
- **Dates**: Godot's `weekday` is 0 = Sunday, Python's `weekday()` is 0 = Monday.
- **Noise**: `Invalid tag in doc file` prints on every run and is harmless.
