# Changelog

Notable changes per release. The design reasoning behind each subsystem lives in the numbered
docs in this folder; `README.md` is the as-built reference.

## 0.7.3

**The mobile crane drives round what is built.** Between two jobs it first asks whether it has to
move at all -- the next piece may be within its boom from where it stands -- and if it does, it
drives there by the straight line when that is clear, and otherwise by the shortest route round
the parts standing that day and the tower crane's mast (visibility graph + A\*, checked with the
carrier's 11.6 x 2.55 m body swept along each leg and swung at each corner). It drives in from and
out to the road instead of appearing and vanishing, waits parked between close jobs, and leaves
the site between jobs more than `hold_days` (30) apart. `SiteEquipment.show_routes` draws the
drives. `equipment/route_planner.gd` (`RoutePlanner`); `tests/test_route_planner.gd` (22 checks),
`tests/test_equipment.gd`.

**The boom and `install` lifts clear what is built.** The same rule, plan a way that clears rather
than report the clash. *Boom:* the mobile crane's spot is chosen so that its boom and hook line
clear every part standing when each piece goes in -- another spot first, then the tip held higher
(`tip_up`), and a spot it can drive to is preferred to one it cannot. *`install`:* where the usual
lift (up 5 m, across, down) would pass through something, the piece is taken over it, round it, or
in sideways at the level of its place, whichever is the shortest that clears (a tower crane's jib
height, reach and mast bound it); a free default is left exactly as it was. `core/lift_planner.gd`
(`LiftPlanner`), `ConstructionSchedule.lift_plans`; `tests/test_lift_planner.gd` (23 checks),
`tests/test_collisions.gd` (21), `tests/test_equipment.gd` (125), `tests/test_route_planner.gd` (27).
Also: a part the schedule removes (`fade_out`, `sink_down`) no longer counts as standing after
it goes -- the cleared trees were blocking the mobile crane's spots on the test project.

**Sample project in the repo.** `examples/galicia/`: the Galician pazo (house and scaffold IFCs),
its MS Project XML and its `construction_steps.json`.

## 0.7.2

**Controls on screen.** Play shows a translucent panel in the bottom-left corner with what the keys
and the mouse do -- keycaps for W A S D, Q E, Shift, Esc and H that light up while held, a mouse
with its left button marked, and one line saying what to do next (click to fly / Esc to use the
bar). H hides it; it dims while flying; never in a recording. `runtime/controls_hint.gd`
(`ControlsHint`), `SequenceManager.show_controls_hint`.

**Pits that are filled back in.** `TerrainPlatform.backfill_activities`: the ground goes back from
levelled to natural over those actions -- a footing excavation dug before the pour and filled once
the column clears the ground. Up to 32 platforms (was 16). `tests/test_terrain.gd`: the pit's
dig / open / fill / finished states.

**Excavators at the pits.** SiteEquipment's excavator and truck now dig and fill the terrain's pits
(platforms with `activities` / `backfill_activities`), whatever the activities are called and
with no model element needed: standing on natural ground at the top of each pit's banks, facing
it, the truck carting the spoil away or tipping the fill. Pits worked at the same time get a crew
each. `ConstructionTerrain.natural_world_height_at()`; `tests/test_terrain.gd`: the stand.

**`rotate`: hinged on the back edge, stood up clear of what is behind it.** The pivot is now the
middle of the back edge of the group's lowest part (the extrados corner of an arch half's
springing joint, on the pier side) instead of the middle of its base, and the automatic start
angle stands the group up until its back face is vertical instead of turning the line to its
centre vertical. Both changes keep the group, stood up, in front of its springing: on VTO Río
Zadorra the 0.7.1 hinge stood the half-arches up through their piers. `angle_deg` still overrides
the angle. See `11_TYPES_REALISM_CLASHES.md`, "`rotate`".

- `ConstructionSchedule.hinge_geometry()`: reads the parts' mesh vertices (AABB corners for a part
  that is not a single mesh).
- `tests/test_rotate.gd`: 25 checks (the pivot and angle checks rewritten for the new rule).

**The pour fills up, straight up.** `fill_up` and `build_up` no longer stretch the element along
its own Y from a sliver -- which, on a tilted or standing-up arch dovela, looked like a squashed
piece pulled out sideways. The element stays whole and is drawn below a level that rises in world
+Y from its lowest point to its highest as it stands (after a `rotate` swing too), closed by a flat
top. See `11_TYPES_REALISM_CLASHES.md`, "The pour as a level".

- `core/fill_clip.gdshader`, swapped in while a part is part-filled (reproducing its
  StandardMaterial3D), its own materials back when done.
- `core/mesh_prep.gd` (`MeshPrep.outward()`): consistent outward winding and normals (flat, or
  smoothed within an angle), which the cap needs; applied to a mesh the first time it is poured.
- Hollow sections (hollow piers, box-section ribs and decks) pour as their walls: the top is the
  part's horizontal section at the level, outline minus voids (`MeshPrep.section_cap()`, a
  `_PourCap` child, never saved; `AnimationApplier.end_fill()` on Stop Preview).
- `MeshPrep.outward(mesh, smooth_deg, close_openings)`: with `close_openings`, faces an export left
  out are put back -- a hollow section's missing end as its ring.
- `AnimationApplier.fill_extent()`; the pour stream aims at the world-vertical level.
- `tests/test_fill.gd`, 29 checks.

**Cranes: on site only while they work, and a boom that luffs.** A scene crane now appears and
goes with the schedule: `on_site_from` / `on_site_until` (action id or date) on the `Crane`, or by
default `setup_days` around the actions naming it in `crane_id` and the lifts assigned to it; one
with neither stands throughout, as before. Play and the editor preview both follow it. A crane
with a `Boom` under `Arm` (a crawler crane) pitches it to reach each lift instead of sliding its
head along a jib, which used to leave the hook hanging away from the boom. See `README.md`,
"Cranes".

- Fixed: a lift starting within two seconds of a scrub was dragged back towards rest by the
  scrub's `retract()` tween, which nothing stopped.
- Fixed: a crane later in the scene tree than the `SequenceManager` had its `PickupZone` ignored
  (asked for before its `_ready()`), so its lifts started 15 m to the side of the piece instead.
- **Stands**: a crane's `stands` (markers, e.g. `Marker3D`) are where it works from; each lift is
  made from the one its action names in `crane_stand` or the nearest, with the laydown travelling
  along, and the crane drives between stands in the gaps. Markers can be moved in the editor to
  put the crane where it can really stand.
- A crane no longer keeps following a piece once its lift is over: the timeline retracts it.
- `ConstructionSchedule.crane_window()` / `crane_on_site()`; `TimelineController.set_site_cranes()`
  / `restore_site_cranes()`.
- `tests/test_crane_site.gd`, 36 checks.

## 0.7.1

**`rotate`: built in one pose, swung into place.** A block on any action, for elements built in
one position and turned into their modelled one -- an arch half built standing up beside its
pier and lowered onto its springing (*abatimiento*), as on the VTO Río Zadorra viaduct. Every
action naming the same `group` is one rigid body: its parts are built, by their own type, standing
upright about a horizontal hinge at the base of the group's lowest part, and swing down together
once the last one is finished (+ `lag_days`), over `duration_days`, eased in and out. `angle_deg`
sets the start angle instead of upright. See `11_TYPES_REALISM_CLASHES.md`, "`rotate`".

- `ConstructionSchedule`: `hinge_geometry()`, `get_hinge()`; `get_part_states()` adds `"hinge"`
  for the parts of a group. Malformed blocks warn and are ignored.
- `AnimationApplier.apply_instant_hinged()` and `reset_rotation()`; `TimelineController.scrub_to()`
  uses them, and turns back a part whose `rotate` was removed.
- `SequenceManager.initialize_parts()` records and restores `original_quaternion`, and Stop
  Preview restores rotation as well as position and scale: no part is saved mid-swing.
- `tests/test_rotate.gd`, 24 checks. The other nine suites pass unchanged.

## 0.7.0

Animation types read from activity names, animations that look like construction, clash
detection that ignores designed contact, site equipment — a tower crane, a mobile crane, an
excavator built to Caterpillar's published 320 measurements and a truck — that comes and goes with
the schedule, and a much simpler dock. Tested with Godot 4.6.2 and 4.7.2: 517 checks in nine
headless suites, plus the site equipment run end to end on the test project's real, levelled
terrain.

**Upgrading from 0.6.0.**
- **Machines appear on Play.** `SequenceManager.auto_equipment` is on by default, so a scene with
  no `SiteEquipment` gets one at runtime. Untick **Auto Equipment** on the SequenceManager to turn
  it off. A scene that already has a `Crane` of its own gets no tower crane.
- **Nothing to re-import.** Existing schedules keep their types; **Auto types** in the dock
  re-reads them from the activity names when you want it to.
- **The guides gained a section.** *Site equipment* / *Maquinaria de obra* is section 10; *Play*,
  *Record a video* and *Troubleshooting* moved to 11–13.
- **Load IFC (4D) now writes the schedule.** With no `construction_steps.json` it generates it;
  with one, it only adds actions for activities none of yours covers, and changes nothing else.
  **Generate 4D Schedule** and **Edit IFC mapping** moved to the **▾** next to it.
- **No Recalculate.** Edits show in the preview a moment after you make them.
- **No Reload from JSON.** Stop Preview with unsaved edits asks *Guardar / Descartar / Cancelar*.
- **No Scan Collisions** on the timeline bar: the scan runs by itself.
- **Fewer terrain buttons** (see "A simpler dock"); the levelling's slope and margin are on the
  Terrain node.

### A simpler dock

What always happens in sequence is one step, what the tool can do itself is not a button, and
what only applies while previewing is hidden until then: with the preview off the dock shows four
buttons, down from 26. Driven in the real editor on the test project (import, terrain, preview,
edit, import/export, stop with unsaved edits).

#### Dock (`editor/timeline_dock.gd`, `editor/timeline_dock.tscn`)
- **Start Preview / Stop Preview are one toggle.** Stopping with edits not yet saved asks
  *Guardar / Descartar / Cancelar* — the button, **Maquinaria**, **Load IFC (4D)** and **Generate 4D
  Schedule** all go through the question (`_stop_then()`). Switching scene tabs stops at once and
  then offers to save the edits to that scene's file.
- **Edits rebuild the preview by themselves**, 0.4 s after the last one (a one-shot timer), instead
  of the *Recalculate* button and its "out of date" label. Affordable because a schedule with no
  `install` actions no longer builds collision shapes (below).
- **Save to JSON** is greyed out when there is nothing to save. *Reload from JSON* is gone.
- **Importar… / Exportar…** replace the four CSV / Project XML buttons; the format is the file's
  extension. **Importar…** is in the top row and starts the preview itself, so a Project XML
  import is *Load IFC → Importar… → Save*.
- **Load IFC (4D) writes the schedule** (`_schedule_after_import()`): the full generation when
  there is no JSON, otherwise `IFCScheduleGenerator.add_new_actions()` — a second model of the site
  (e.g. `galicia_medios_auxiliares.ifc`) adds its activities without a regeneration, which would
  have re-read every date and dropped formwork. Runs before the terrain, so levelling sees the
  earthworks. **Generate 4D Schedule** and **Edit IFC mapping** are in a **▾** menu.
- **Hidden until the preview**: the timeline, the inspector and its buttons, *Vertido* and
  *Encofrado en todo el proyecto*. Vertido's six tuning fields fold under *▸ Ajustes*.

#### Terreno (`editor/terrain_panel.gd`)
- **Removed**: *Deducir huso* (a download deduces the zone), *Comprobar posición* (the check is
  printed after every download, Aplicar origen and Asentar), *Añadir sol* (a `GeoSun` is added when
  the terrain is built and the scene has no directional light), *Quitar terreno* (delete the node).
- ***Nivelar desde el modelo* / *Terreno natural* → one checkbox, *Nivelar para edificio***, ticked
  by itself on the first terrain built for a schedule with earthworks. *Talud H:V* and *Margen m*
  became `ConstructionTerrain.level_slope` / `level_margin` in the Inspector.
- **Aplicar origen fetches the terrain** for the new place (or lets the existing one follow when
  it already covers it).
- **Folded**: the manual origin fields when the model is georeferenced (*▸ Cambiar origen*); size,
  *Al importar IFC*, *Texturas cercanas*, *Archivos propios…* and *Asentar en el suelo* under
  *▸ Más opciones*. *Cancelar* only shows during a download, in place of *Descargar terreno*.

#### Runtime and core
- `TimelineUI`: the *Scan Collisions* button is gone; the scan runs once per wiring
  (`set_timeline_controller()` resets `_auto_scanned`), so it also follows every dock rebuild.
- `ConstructionSchedule` calls `CollisionQuery.setup()` only when `has_install_parts()`: without
  an install mover nothing can clash, and the shapes were most of a rebuild's cost.
- `IFCScheduleGenerator.add_new_actions()` (+7 checks in `tests/test_ifc_mapping.gd`).

#### Docs
- Both guides: a "short version" at the top; sections 5–9, 11 and 13 follow the new dock.
  `docs/README.md` ("The editor dock", "Collision detection"), `10_TERRAIN.md` (new "The dock"),
  `05_IFC_INTEGRATION.md`, `04_API_REFERENCE.md`, the root README.

### Site equipment

**A tower crane, a mobile crane, an excavator and a truck, with no setup**
(`equipment/`, `runtime/sequence_manager.gd`, `runtime/timeline_controller.gd`,
`editor/timeline_dock.gd`; design and measurements in `docs/13_SITE_EQUIPMENT.md`).
- `EquipmentModels` builds the four machines from boxes and cylinders (660–3,100 triangles depending on size, flat
  colours, no assets). `SiteEquipment` places them from the model and on the terrain: the tower
  crane off the building's back-right corner, its jib (30–75 m) and height (tallest part in reach
  + 10 m) sized to it; the excavator at the pit's edge with the whole of its tracks on the pad; the
  mobile crane beside each of its lifts, 5 m clear of everything already built that day.
- The schedule brings them on and off site through the `TaskClassifier` categories: the tower
  crane goes up mast section by section before the first structural activity, lowers every
  `drop_in` piece it can reach, and comes down after the roof; the mobile crane sets up on its
  outriggers for lifts out of reach or after the tower crane has gone; the excavator digs and
  loads the truck (reverse in, four buckets, drive off) during excavation and earth fill.
- The tower crane is a real `Crane`: `install` lifts use it and start from its laydown area
  (`PickupZone`) instead of 15 m to the side.
- Created at Play by `SequenceManager.auto_equipment`; the dock's **Maquinaria** button adds it to
  the scene with two movable markers (`TowerCraneSite`, `ExcavatorSite`). Driven from
  `TimelineController.scrub_to()`, so scrubbing, the dock preview and Movie Maker all show it.
- On the test project: crane at the back-right corner, 55 m jib, on site 2027-03-31 → 2027-11-13
  following 120 pieces; mobile crane for the pergola, granary and cross; every machine on the
  graded terrain surface; 33 ms to build, 24 µs per frame.

**The excavator is a Caterpillar 320 to the published sheet** (`equipment/specs/
excavator_cat_320.json`, `equipment/equipment_specs.gd`). The sheet's figures are recorded in
millimetres as printed, with source, configuration and date — dimensions, front, working ranges,
performance, cylinders — and `EquipmentSpecs` reads them, for the model now and for clash checks
later. The model is built to them (4.45 m tracks with idler, sprocket and rollers, 2.98 m wide,
2.83 m tail swing, cab to 2.96 m), has its boom, stick and bucket rams with a solved bucket linkage
and a shaped 1.2 m bucket (wrapper, side plates, cutting edge, five teeth, side cutters), and its
joint limits are fitted so its working range is within 5 % of the sheet's (reach 10.01 m vs 9.86,
depth 6.74 vs 6.72, cutting height 9.07 vs 9.37).

New supporting API: `ConstructionSchedule.source_data`, `get_part_window()`;
`ConstructionTerrain.world_height_at()`, `ground_y()` (which grade the platforms on demand when
asked before the terrain's own `_ready()`).

### Animation types and animations

**Types inferred from the activity name** (`core/task_classifier.gd`,
`ifc/ifc_schedule_generator.gd`, `editor/ifc_mapping_dialog.gd`, `editor/timeline_dock.gd`). A
schedule already says what each task is ("Hormigonado de zapatas", "Mampostería de granito",
"Excavación de zanjas"), so the type no longer has to be typed against every row or carried as an
IFC property. `TaskClassifier` reads the action's code and label (Spanish, Galician, Portuguese,
English; accents, case and `CamelCase_codes` normalised) and picks type and cadence; what is done
(demolish, dig, pour) outranks what it is done to (a footing, a roof). Generate 4D Schedule uses it
between the explicit sources and the fallback type (the mapping's new `infer_types`, on by
default); the dock's new **Auto types** button applies it to a loaded schedule and logs each
change. On the Galician test model it recognises all 47 activities and corrects 17 saved types
that contradicted the name (lean concrete fading out, scaffolding "poured").

**Types from the model and the plan, and no more phantom crane lifts**
(`ifc/ifc_schedule_generator.gd`, `editor/schedule_project_xml_io.gd`). A type property whose
values already are type names (`fill_up`, `rise_up`...) now gives those types with no rules —
before, such a model got the default type everywhere, and with `install` as the default every
action became a clash-checked crane lift. Import Project XML sets each action's type and batching
from the plan's custom text column whose values are type names, found by its values.

**`build_up`**, a new type: grows the element from its own base, like `fill_up` without the
pour. Masonry was getting `rise_up`, which moves the whole element up from 10 m below — through
the slab it stands on.

**`drop_in`, `scale_up` and the fades look like construction** (`core/animation_applier.gd`).
`drop_in` fell a fixed 15 m, fastest at the top, appearing opaque out of nothing; it is now
lowered from 1.5 m + 1.5 × the piece's height (2.5–8 m), slow off the hook and slow on landing,
fading in over the first 20 %. `scale_up` grew about the part's centre with an overshoot to ~110 %;
it now grows from the middle of its base, never larger than finished (formwork panels, which use
it, now rise from the ground). Fades run to and from each material's own alpha and restore its
transparency mode — glass used to finish `fade_in` opaque — and `fade_in` is hidden until it
starts. The live tweens drive the instant functions, so Play and scrubbing cannot differ.

### Clash detection

**Designed contact is no longer a clash; lifts start in the right place**
(`core/collision_query.gd`, `core/construction_schedule.gd`, `core/spatial_grouper.gd`,
`runtime/timeline_controller.gd`). On the 663-part Galician model with its stone pieces turned
into crane lifts: 189 clash windows over 39 activity pairs before, 79 over 16 after; the full scan
went from 159 s to 2.4 s.
- Parts a lifted piece touches or overlaps in the *finished* model (a corbel set into its cornice,
  neighbouring segments) are recorded once and never reported.
- The mover's hull is inset by 2 cm (`CONTACT_TOLERANCE`), so grazing and coincident faces don't
  count.
- Parts at near-zero scale are skipped: Jolt replaced their singular basis with identity and
  checked them at full size.
- `install_ground_start` is the part's local start position. It was a world point applied as a
  local one, so in any offset container every lift started metres away, often underground.
- Staggered parts are placed bottom-up (0.5 m levels), then across the plan.
- `scan_collisions()` samples only the days a lift is in progress, and `intersect_shape()` results
  are no longer capped.

### Editor and documentation

- **Load IFC (4D) creates the SequenceManager** when the scene has none; parts used to land under
  the scene root, where Generate 4D Schedule could not find them.
- **The dock no longer draws over the Scene tree**: its root is a `ScrollContainer`, so a long
  inspector scrolls instead of spilling out.
- **Bilingual instructions**: the README is English + Spanish, and two complete step-by-step
  guides, `GUIDE.md` and `GUIA.md`, cover installation to video, with a troubleshooting table.
- **Documentation cleaned up**: `docs/README.md` rewritten as a concise as-built reference (the
  history it had accumulated lives here and in git); new `11_TYPES_REALISM_CLASHES.md`,
  `12_FUTURE_WORK.md` (the to-do list) and `13_SITE_EQUIPMENT.md`; the original planning documents
  marked as historical; stale statements corrected against the code.

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
