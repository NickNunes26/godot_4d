# Changelog

Notable changes per release. The design reasoning behind each subsystem lives in the numbered
docs in this folder; `README.md` is the as-built reference.

## Unreleased

**Site equipment: a tower crane, a mobile crane, an excavator and a truck, with no setup**
(`equipment/equipment_models.gd`, `equipment/site_equipment.gd`, `runtime/sequence_manager.gd`,
`runtime/timeline_controller.gd`, `editor/timeline_dock.gd`, `core/construction_schedule.gd`,
`terrain/construction_terrain.gd`, `tests/test_equipment.gd`). Item 2 of `12_FUTURE_WORK.md`;
design and measurements in the new `docs/13_SITE_EQUIPMENT.md`. `EquipmentModels` builds the four
machines from boxes and cylinders (660–3,072 triangles, flat colours, no assets). `SiteEquipment`
places them from the model — tower crane off the building's back-right corner with its jib (30–75 m)
and height (tallest part in reach + 10 m) sized to it, excavator at the pit's edge with its truck
beside it, mobile crane per lift — and brings them on and off site from the `TaskClassifier`
categories: the tower crane goes up mast section by section before the first structural activity,
lowers every `drop_in` piece it can reach on its hook, and comes down after the roof; the mobile
crane sets up on outriggers for lifts out of reach or after the tower crane has gone; the excavator
digs and loads the truck (reverse in, four buckets, drive off) during excavation and earth fill.
The tower crane is a real `Crane`, so `install` lifts use it and start from its laydown area
(`PickupZone`) instead of 15 m to the side. `SequenceManager.auto_equipment` (default on) creates it
at Play; the dock's new **Maquinaria** button adds it to the scene with two movable markers
(`TowerCraneSite`, `ExcavatorSite`). Driven from `TimelineController.scrub_to()`, so scrubbing, the
dock preview and Movie Maker all show it. New: `ConstructionSchedule.source_data`,
`get_part_window()`; `ConstructionTerrain.world_height_at()`, `ground_y()`. On the test project:
crane at the back-right corner, 55 m jib, on site 2027-03-31 → 2027-11-13 following 120 pieces;
mobile crane for the pergola, granary and cross; 33 ms to build, 24 µs per frame. 69 new checks
(487 in all). Docs: `13_SITE_EQUIPMENT.md`; `12_FUTURE_WORK.md` marks item 2 built; both guides get
a *Site equipment* / *Maquinaria de obra* section (sections 10–12 renumbered 11–13); README,
`docs/README.md`, `01_ARCHITECTURE.md`, `04_API_REFERENCE.md` updated.

**`drop_in` and `scale_up` look like construction** (`core/animation_applier.gd`,
`tests/test_animations.gd`). `drop_in` fell a fixed 15 m with a cubic ease-out — fastest at the
top — and appeared opaque out of nothing; it is now lowered from just above (1.5 m + 1.5 × the
piece's height, within 2.5–8 m), slow off the hook and slow on landing, fading in over the first
20 %. `scale_up` grew about the part's centre with an overshoot to ~110 %; it now grows uniformly
from the middle of its base, never larger than finished (base drift on a rotated part in an
offset container: 2.86 m before, under 1 mm now). Formwork panels assemble with `scale_up`, so
they now rise from the ground. **Fades respect the material**: alpha runs to and from each
material's own alpha on every surface, and its transparency mode is restored at full opacity —
glass used to finish `fade_in` opaque. `fade_in` is hidden until it starts. The live tweens of
these four types now drive the instant functions, so Play and scrubbing cannot differ.
27 new checks; 10 of them fail on the previous code.

**Documentation**: `docs/11_TYPES_REALISM_CLASHES.md` (as-built: inference rules table generated
from the code, the animation set, the clash changes with measurements, bottom-up placement) and
`docs/12_FUTURE_WORK.md` (the to-do list: robust scaffolding/formwork, support equipment — tower
crane, mobile crane, truck, excavator — and smaller open items). `docs/README.md`,
`01_ARCHITECTURE.md`, `04_API_REFERENCE.md`, `05_IFC_INTEGRATION.md`, the README and both guides
point to them.

**Animation types inferred from the activity name** (`core/task_classifier.gd`,
`ifc/ifc_schedule_generator.gd`, `editor/ifc_mapping_dialog.gd`, `editor/timeline_dock.gd`). A
schedule already says what each task is ("Hormigonado de zapatas", "Mampostería de granito",
"Excavación de zanjas"), so the type no longer has to be typed against every row or carried as an
IFC property. `TaskClassifier` reads the action's code and label (Spanish, Galician, Portuguese,
English; accents, case and `CamelCase_codes` normalised) and picks type and cadence; what is done
(demolish, dig, pour) outranks what it is done to (a footing, a roof). Used by Generate 4D Schedule
between the explicit sources (rules, a property whose values are type names) and the fallback
type, controlled by the mapping's new `infer_types` (on; old profiles read as on). The dock's new
**Auto types** button applies it to every row of a loaded schedule and logs each change. On the
Galician test model it recognises all 47 activities and changes the type of 17 whose saved type
contradicted the name, several plainly wrong (lean concrete fading out, scaffolding "poured").

**`build_up` animation type** (`core/animation_applier.gd`). Grows the element from its own base,
like `fill_up` without the pour. `rise_up`, the only other type for something going up, moves the
*whole* element up from 10 m below -- through the slab and foundations it stands on -- which is
what masonry was getting.

**Clash detection no longer flags designed contact; lifts start in the right place**
(`core/collision_query.gd`, `core/construction_schedule.gd`, `core/spatial_grouper.gd`,
`runtime/timeline_controller.gd`). Measured on the 663-part Galician model with its `drop_in`
pieces turned into crane lifts: 189 clash windows over 39 activity pairs before, 79 over 16 after,
and the full scan went from 159 s to 2.4 s. What changed:
- Parts a lifted piece touches or overlaps in the *finished* model (a corbel set into its cornice,
  cornice ends on the roof timbers, neighbouring segments) are recorded once and never reported:
  that is the design, not the sequence.
- The mover's hull is inset by 2 cm (`CONTACT_TOLERANCE`), so grazing and coincident faces don't
  count.
- Parts at near-zero scale (`scale_up` just starting) are skipped. Jolt replaces a singular
  basis with identity, so they were checked at full size (and logged tens of thousands of
  warnings per scan).
- `install_ground_start` is now the part's local start position. It was the world pickup point,
  assigned as a local position: in any offset container (a georeferenced second model, a model
  set onto the terrain) every lift started that offset away, metres underground, and every child
  of a commander unit started on the same point.
- Staggered parts are placed bottom-up (0.5 m levels), then by plan position. Ordering by plan
  alone placed upper pieces before lower ones, which a lift then had to pass through.
- `scan_collisions()` samples only the days a lift is in progress (`get_install_windows()`), and
  `intersect_shape()` results are no longer silently capped at the number of active parts.

**Animation types from the model and the plan, and no more phantom crane lifts**
(`ifc/ifc_schedule_generator.gd`, `editor/schedule_project_xml_io.gd`). A "Decide type from"
property whose values already are type names (`fill_up`, `rise_up`...) now gives those types with no
rules. Before, such a model with no rules got the default type for every action; with `install` as
the default that made every action a crane lift, and every crane lift is clash-checked, so
excavation, rebar and everything else reported clashes against each other. Import Project XML now
also sets each action's type (and its batching) from the plan's custom text column whose values are
type names, found by its values rather than its name.

**Load IFC (4D) creates the SequenceManager** (`editor/timeline_dock.gd`). The node is a
`Node3D` carrying `runtime/sequence_manager.gd` with no `class_name`, so it cannot be found in
Add Child Node, and a scene without one used to get its parts under the scene root, where
Generate 4D Schedule and Edit IFC mapping could not find them (both only warned in the Output).
The import now adds a `SequenceManager` under the scene root when there is none and imports into
it as usual.

**The dock no longer draws over the Scene tree** (`editor/timeline_dock.tscn`). Its root was a
plain `Control` whose `VBox` was anchored to fill it and allowed to grow both ways, with nothing
clipping it. Once Start Preview added the timeline and the inspector grid, the content needed more
height than the dock had, and spilled upwards over the Scene tree and downwards past the dock. The
root is now a `ScrollContainer` (vertical scroll only, clips its content), so the dock keeps its
size and scrolls instead. Node paths are unchanged (`$VBox/...`), so no code changed.

**Instructions for everybody, in English and Spanish.** The README is now bilingual: each section
is an English paragraph followed by its Spanish version, with the developer material kept in
English. Two complete step-by-step guides, [GUIDE.md](../GUIDE.md) and [GUIA.md](../GUIA.md),
cover installation, preparing the scene, the IFC mapping dialog field by field, the three ways to
get a schedule (IFC only, IFC + Project XML, an existing JSON), terrain and levelling, the editor
preview and Schedule Inspector, formwork and scaffolding, playing, recording and sharing a video,
and a troubleshooting table.

## 0.6.0

Levelled terrain platforms, IFC + MS Project workflow verified end to end from a fresh project,
and fixes for a startup memory leak, a grey screen in camera-less scenes, hidden id-only static
parts and garbled accented IFC text. Each item below.

**Default camera framed on the work, not the whole site** (`runtime/sequence_manager.gd`,
`_action_box()`). The camera `SequenceManager` adds to a scene without one framed the whole
model's box. On a building with site works (boundary wall, trees in the plot's corners) that put
it 74 m out, with the house small in the middle. It now frames the middle 80 % of part centres
from 1.6× their radius: 31 m on the Galicia sample.

**Movie recordings carry the terrain credit** (`_start_movie_run()`). The data licences (IGN's
CC BY 4.0 for Spain) require the credit wherever the ground is shown. Movie mode now draws
`TerrainData.attribution` bottom right, under the date, whenever the scene has a terrain.

**Documentation brought up to date with everything below.** `04_API_REFERENCE.md` covers
`has_install_parts()`, the one-day `get_part_states()` cache, the scan's early return,
`scrub_to()`'s sun and terrain steps, `_ensure_view()`, `repair_text()`,
`position_check(..., ground)`, `ConstructionTerrain.platforms`, `TerrainPlatform` and
`TerrainGrading`. `01_ARCHITECTURE.md`'s caching section and `docs/README.md`'s collision scan
describe the code as it is now. The README's feature list and limitations are current. The IFC +
MS Project workflow was re-run from GitHub `main` (`a87c025`) in a fresh project with nothing
but the `.ifc` and `.xml`. It passed with no intervention: all five test suites, 46/46 dates
matching the hand-made schedule, no garbled text, and memory flat at ~430 MB during Play.

**Accented IFC text is repaired on import** (`ifc/gdifc_4d_adapter.gd`,
`repair_text()` / `repair_string()`, called from the dock right after GDIFC reads the file).
GDIFC 1.1.0-alpha reads IFC text as UTF-8 bytes taken for Latin-1, so every accented label
arrived garbled ("FormigÃ³n de limpeza"). It showed in the mapping dialog, in 21 of the Galicia
schedule's comments and throughout the saved scene. The IFC itself is correct (`\X2\00F3\X0\`).
Only strings with exactly that signature are decoded again; tests cover two- and three-byte
sequences, text that is already right, and genuine Latin-1.

**IFC + MS Project workflow documented and verified** (README, "From an IFC file and an MS
Project plan"). Starting from only `galicia_model.ifc` and `galicia_model.xml` in a fresh project:
Load IFC → mapping → Generate 4D Schedule → Import Project XML → Recalculate → Save to JSON. All
46 tasks matched by name without a dialog, and 43 dependency links came in. Start and finish
dates were identical to the hand-made schedule for all 46 actions, and so were types and static
parts. The one difference is formwork, which neither format can carry: the README now says so
and lists what to add.

**End-to-end check in a fresh project** (Godot 4.7.2, GDIFC from the Asset Library, the addon
from `main`, `models/galicia_model.ifc`). Every README test suite and the demo pass. So do
Load IFC → mapping → automatic terrain → Generate 4D Schedule → sun → levelling → preview →
Play, driven through the dock's own buttons and dialogs. It turned up the two fixes below; the
README now has the verified IFC sequence and where to get GDIFC.

**Play no longer shows a grey screen in a scene without a camera**
(`runtime/sequence_manager.gd`, `_ensure_view()`). The documented steps never add a
`Camera3D`, environment or light, so a scene built by following them ran as an empty grey
viewport under a working timeline. At runtime `SequenceManager` now adds, for that run only, a
free-fly camera framed on the model, a procedural sky and a sun. Each is added only when the
scene has none of its own, and nothing is saved. See `docs/README.md`, "Camera".

**Dated-less parts with an id are shown again** (`ifc/ifc_schedule_generator.gd`). A part with
an Element ID but no usable date became a `static_prefixes` entry named after its *zone*
(`IfcSite_22_`). The adapter had named the part after its *id* (`Z00_Terreo`), so the prefix
matched nothing and the part stayed hidden all run (the Galicia model's existing ground). The
prefix is now the id when there is one. `test_ifc_mapping.gd` checks the exact list; the old
check (`has("ZoneOne_")`) passed only thanks to a different, uncoded part.

**Levelled platforms** (new, see `10_TERRAIN.md` "Levelled platforms")
- `ConstructionTerrain.platforms`: building pads, excavation pits and the like, cut and filled into
  the downloaded ground with banks at a chosen slope. Empty keeps the natural ground (bridges).
- Each platform can follow schedule activities: natural before, levelled after, morphing in
  between, drawn as bare earth.
- Dock: **Nivelar desde el modelo** proposes a pad and a pit from the model's geometry and the
  schedule's earthwork actions; **Terreno natural** clears them.
- `pazo_xilloi.tscn` now has its pad and pit, tied to C02 and C03.
- `TerrainBuilder.position_check()` takes an optional ground function; **Comprobar posición**
  checks against the levelled ground.

**`drop_in` no longer bounces** (`core/animation_applier.gd`). `TRANS_BOUNCE` became
`TRANS_CUBIC` + `EASE_OUT`, in both live play and scrubbing: the part falls and settles once.

**Memory leak at startup fixed.** `ConstructionSchedule.get_part_states()` cached every day it was
ever asked for, and the automatic first-frame `scan_collisions()` asks for about 33,000 days (every
0.01 day of the schedule) × one entry per part. The Pazo Xilloi scene grew by about 90 MB/s to more
than 7 GB. Now only the last day is kept, which is all scrub-then-query needs. Separately,
`scan_collisions()` returns at once when no part uses `install`: `CollisionQuery` only ever checks
`install` movers, so nothing could be found, and the scan used to walk every part through the
whole schedule for over a minute before the first frame. Memory now stays flat at about 450 MB.

**Project XML import — two fixes** (`editor/schedule_project_xml_io.gd`,
`apply_task_onto_action()`). Both found by round-tripping a real 46-activity plan
(`models/galicia_model.xml`) through the dock's own importer; neither had a test.
- **A `LinkLag` came back 24× too long.** Export writes lag in tenths of a minute
  (`days × 24 × 60 × 10`, correct MSPDI); import divided by `600`, which is tenths of a
  minute to *hours*, not to days. A 2-day lag re-imported as 48 days, silently — so the
  addon's own export could not survive its own import. Now `/ 14400.0`.
- **Negative lags were dropped.** `max_lag_tenths_min` was seeded at `0` and combined with
  `maxi()`, so any lead (`maxi(0, -259200)`) collapsed to no lag at all. Leads are ordinary
  Finish-to-Start links — formwork stripping starting partway through a pour, quoins laid
  while the wall they trim is still rising. Now seeded from the first link that resolves.

Still open, deliberately not changed here: `export_xml()` writes `Start` at 09:00 and
`Finish` at 18:00, while `_task_duration_days()` reads a duration as literally
Finish − Start. Its own output therefore re-imports 0.375 days longer per task (measured:
a 10-day action reads back as 10.375). Writing the same time of day at both ends would fix
it, at the cost of changing the format the exporter has always emitted.

## 0.5.0

**Terrain** (new, see `10_TERRAIN.md`)
- The dock's **Terreno** section downloads the ground around the model and builds it under the
  `SequenceManager`: 5 m elevation and 25 cm / 1 m orthophotos for mainland Spain and the Balearics
  (IGN, CC BY 4.0), elevation only elsewhere (Terrain Tiles). Runs automatically after
  Load IFC (4D) for georeferenced models (optional). Downloads retry, are cached in
  `res://terrain/<site>/`, and are checked for completeness.
- Own data instead of downloads: an `.asc` grid plus JPG/PNG orthophotos with world files.
- `ConstructionTerrain` node: mesh and collision generated on load from a saved `TerrainData`, so
  scenes stay small; follows edits of the georeference. Ground shader with graded orthophoto and
  near-camera leaf/rock PBR textures (Poly Haven, CC0).
- Position check after every build (floating / buried model), and "sit on the ground" for models
  with no real height.
- `GeoSun`: a directional light placed where the sun is over the site on the timeline's date.

**Georeference**
- The model's position on Earth survives IFC import: `SequenceManager.geo_origin` (`GeoOrigin`)
  records it from `IfcMapConversion` (with rotation and scale), `IfcProjectedCRS`, or map
  coordinates in the root placement. Editable in the inspector and the dock.
- `GDIFCRecenter.recenter_with_info()` returns what it stripped (it used to be printed and lost).
  Several root placements with different large offsets now keep their relative positions.
- `GDIFCRecenter` no longer rewrites a file whose only offset is in `IfcMapConversion` (GDIFC ignores
  the map conversion): a model of several hundred MB now loads with no copy. The pass itself takes ~1 s on such a
  file (transient ~1.3 GB while it reads it as text).
- UTM zone read from the IFC, deduced from ground heights (Spain), or entered by hand.
- GDIFC's axis convention is verified and documented (IFC x, y, z → Godot x, z, -y).

**Several models in one scene** (new, see `05_IFC_INTEGRATION.md`)
- Loading a second IFC file no longer replaces the first: each model gets its own
  `IFCParts_<file>` container in `extra_part_containers`, placed relative to the first by its
  georeference (`IfcSceneModels`, `GeoOrigin.relative_transform()`); the scene's origin and the
  terrain are kept. Loading a file again replaces its container in place.
- Part names repeated across models get a suffix instead of shadowing each other.
- Generate 4D Schedule and the terrain position check cover every model.

**Fixed**
- **Load IFC (4D) did nothing past the file dialog**: `read_ifc()` was passed an `int` where GDIFC
  expects an `Array`, which raised a script error before the import callback was connected.
- The dock now sets GDIFC's `coordinate_to_origin` explicitly (off), so no shift can happen
  unrecorded.
- **Files with CRLF line endings kept their map-sized root offset** (so loaded with float32 jitter):
  `GDIFCRecenter`'s patterns only matched LF lines.

**Tests**: `test_geo.gd`, `test_terrain.gd` (no network), `test_ifc_scene_models.gd` (two models of
one site, re-imports, unplaceable models), `test_ifc_georef_gdifc.gd` (end-to-end
through GDIFC on invented fixtures in `tests/fixtures/`).

## 0.4.0

First standalone release of the addon.

**Packaging**
- The addon is self-contained: `core/`, `runtime/`, `editor/`, `ifc/`, `examples/`, `tests/`, `docs/`.
- MIT licence, plugin-facing `README.md`, and an example scene (`examples/demo.tscn`).
- Schedule and camera-track JSON default to `res://construction_steps.json` and
  `res://camera_track.json` (project data no longer lives inside the addon directory).

**IFC**
- The IFC pipeline no longer assumes any property names. After import the tool scans the model's
  properties and you choose the element id, dates, display name and animation-type rules
  (`IfcMapping`, `IfcPropertyScanner`, `IfcMappingDialog`). The choice is saved beside the schedule.
- Regenerating a schedule keeps a hand-corrected action `type` / `batch`.
- `tests/test_ifc_mapping.gd` covers the pipeline with an invented property layout.

**Generalisation**
- `parts_container_path` has no default; an unset path reports a clear error.
- `extra_part_containers` replaces a hard-coded scan for extra part nodes.
- Removed project-specific code: prop generation, prop-specific animation timing, name-based
  special cases.
- Documentation rewritten to be project-neutral (`05_IFC_INTEGRATION.md` is new; this changelog
  was condensed).
- Fixed: the editor dock failed to parse when GDIFC was not installed.

## 0.3.x — editor plugin

- Editor dock: live scrubbing in the 3D viewport without entering Play mode, with a restore
  guarantee for the edited scene.
- Schedule inspector: id, type, anchor, start, end, duration, units/day, dependencies, lag;
  Recalculate, Save, Reload.
- `units_per_day` frequency-based durations; finish-to-start dependencies with multiple
  predecessors and lag; anchor-driven trial-and-fit scheduling.
- CSV and Microsoft Project XML export/import, with persisted task mapping and phase groups.
- Formwork generation (generic, panel asset, or scene geometry) following each part's real faces.
- Optional concrete pour stream, tunable per project.
- Camera keyframes and movie mode.
- Multi-crane support with nearest-by-distance assignment and an explicit `crane_id`.
- Free-fly spectator camera.

## 0.2.x — collision detection

- Exact-geometry collision checks between in-transit parts and everything present.
- Live warning, pause-on-collision during Play, full-schedule scan with a slider overlay, and a
  3D collision marker.

## 0.1.x — timeline

- Date-aware schedule (`start_date`, `duration_days`), scrub and Play, per-action cadence,
  animation types (`scale_up`, `drop_in`, `rise_up`, `sink_down`, `fill_up`, `fade_in`,
  `fade_out`, `install`), crane install choreography, static and excluded geometry.
