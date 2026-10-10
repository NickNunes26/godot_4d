# 4D Construction Tool — Site equipment (maquinaria)

> **Status: built** (2026-10-10). Item 2 of `12_FUTURE_WORK.md`. Code: `equipment/equipment_models.gd`
> (`EquipmentModels`), `equipment/site_equipment.gd` (`SiteEquipment`); hooks in
> `runtime/sequence_manager.gd`, `runtime/timeline_controller.gd`, `editor/timeline_dock.gd`,
> `core/construction_schedule.gd`, `terrain/construction_terrain.gd`. Tests:
> `tests/test_equipment.gd` (69 checks).

## What you get

A construction site without its plant doesn't read as a construction site. With no setup at all,
Play now shows:

- an **excavator** at the edge of the pit during the excavation and earth-fill activities, digging
  and swinging round to load a **tipper truck** that reverses in, takes four buckets, drives off
  and comes back empty;
- a **tower crane** that goes up section by section a few days before the first structural
  activity, stands over the building, lowers the stone pieces (every `drop_in` it can reach) on
  its hook, drives the existing `install` lifts from its own laydown area, and comes down after the
  roof;
- a **mobile crane** that drives in and sets up on its outriggers beside each lift the tower crane
  can't make — a piece out of its reach, or one placed after it has been taken down — and leaves
  when that lift is done.

Movie Maker records all of it: the machines follow the same `scrub_to()` as the parts.

## The models

One of each, broad strokes: a recognisable outline with roughly the right proportions, built in
code from boxes and cylinders (`EquipmentModels`). No assets — nothing to license or download —
and flat colours: yellow plant, white truck cab, grey truck body, concrete counterweights.

| Machine | Envelope as built | Moving parts (node names) | Triangles |
|---|---|---|---|
| **Tower crane**, flat-top | 1.6 m square lattice mast in ~3 m sections; jib length and height from the site (below); counter-jib 0.3 × jib (10–22 m) with walkway, winch and concrete blocks; cab at the slewing ring | `Arm` (slews; jib along +X), `Track` (trolley), `Rope` (Y scale = length), `Hook`, `PickupZone`, `Mast/Section<i>` | ~3,000 (55 m jib) |
| **Mobile crane**, all-terrain | 4-axle carrier 11.6 × 2.55 m; carrier cab; superstructure with crane cab and counterweight; 4-section telescopic boom 13.0 → 41.8 m; four outriggers to 3.6 m each side, jacks and pads | `Slew`, `Slew/Boom`, `…/Section1..3`, `…/Tip`, `Outrigger0..3`, `Hook`, `Rope` | 2,208 |
| **Truck**, rigid 3-axle tipper | 9.0 × 2.5 × 3.0 m; cab, chassis, tipping body (50°) with a soil load | `Body`, `Body/Load` | 660 |
| **Excavator**, ~20 t crawler | Tracks 4.6 m long, 0.6 m shoes, 3.0 m wide; house 2.7 m wide, 2.8 m tail swing; cab top 3.0 m; banana boom 5.7 m, stick 2.9 m, ~1 m³ bucket | `Upper` (slews), `Upper/Boom`, `…/Stick`, `…/Bucket`, `Upper/BoomRam` | 744 |

Posing goes through static helpers so callers never walk the hierarchy:
`pose_mobile_crane(root, slew, luff, extend, outriggers, hook_drop)`,
`pose_truck(root, tip, load)`, `pose_excavator(root, slew, boom, stick, bucket, loaded)`.
`excavator_teeth()` gives the bucket's position for a pose, which is how the dig cycle was tuned and
how the test checks it.

**The tower crane is a real `Crane`.** Built with `as_crane = true`, its root runs
`runtime/crane.gd` and carries the node names that script looks for, so nothing in the crane code
changed. `SequenceManager._resolve_cranes()` finds it like any modelled crane; install lifts are
assigned to it and start from its `PickupZone` (a laydown of timber dunnage and stone blocks)
instead of the fixed "15 m to the side". In the editor the same model is built without the script,
for display.

## Where the machines stand

`SiteEquipment.site_context()` reads the model: every part's **rest box** (the finished placement,
from the `original_transform` meta while a timeline runs), the actions with their `TaskClassifier`
category, the **building box**, the **pit box**, and a **ground level** (the level most of the model
stands on — `TerrainGrading.platforms_from_model()`'s pad). With a `ConstructionTerrain` in the
scene, each machine stands on the terrain height at its own spot instead
(`ConstructionTerrain.ground_y()`).

- **Building box**: parts of structural and roofing activities; per axis the middle 80 % of their
  centres, grown by half the median part size — the measure `SequenceManager` frames its default
  camera on. A boundary wall, a granary or a cross at the far end of the plot doesn't drag the crane
  away. (The first version used box percentiles 3–97 %; on the test project the boundary wall put
  the crane at the plot corner with a 70 m jib.)
- **Tower crane**: 4 m out from a corner of the building box, back-right first (+X, −Z: behind and
  to the side of the default camera), stepped out 2 m at a time until it is 2.5 m clear of
  anything *standing* there — ground-level layers (topsoil, a terrain slab, the dig itself) don't
  count, or the soil slab under the whole plot pushes the crane 30 m out. Jib towards the
  building's centre. **Jib** = the farthest building-box corner + 6 m, rounded up to 5 m, 30–75 m.
  **Height** (ground to the underside of the jib) = the tallest part within the jib's reach + 10 m,
  at least 18 m. **Laydown**: 10 m beside the mast, the first of four spots clear of the building.
- **Excavator**: 4 m off the front (+Z) edge of the pit, mid-way along it, facing in. The pit is the
  dig parts that go more than 0.5 m below ground; stripping topsoil off the whole plot is excavator
  work too, but the machine belongs at the hole. Its truck loads on its right (7.8 m out, beyond the
  2.8 m tail swing) and drives off behind it.
- **Mobile crane**: per job, outside the pieces on the side away from the building — the pieces'
  box radius + 7.5 m from their centre — with the carrier side-on to them.

Explicit values win: `tower_height` and `jib_length` on the `SiteEquipment` node (0 = automatic),
and the two marker nodes below.

## Following the schedule

`SiteEquipment.make_plan()` turns the schedule into windows, once per schedule:

| Machine | On site | Doing |
|---|---|---|
| Tower crane | from the first structural activity (concrete, rebar, steel/timber frame, precast, stone pieces, masonry) − `erect_days`, to the end of the last roofing activity (or the last structural one) + `erect_days` | Erecting: mast sections appear bottom-up over the first 75 % of `erect_days`, then jib, counter-jib and cab. Following: the most recently started `drop_in` piece it is assigned, via `Crane.swing()` (1.2 s slew, then the hook tracks the piece down). `install` units stay `TimelineController`'s; a piece being installed is never interrupted. Idle: `Crane.retract()`. |
| Mobile crane | each job's first piece − 0.75 day to its last piece + 0.75 day | Outriggers out over the first half day, boom up; boom tip 6 m over the current piece, hook down to it; stowed again before it leaves |
| Excavator + truck | every excavation and earth-fill activity | Excavation: an 11 s dig cycle (reach, teeth in, drag and curl, lift, slew 90° over the truck, dump); the truck's round is six cycles — reverse in from 40 m, four loads, drive off. With no truck at the spot the bucket is emptied onto a spoil heap on the other side. Earth fill: the truck arrives full and tips at the spot. |

**Which lifts need a crane.** Every `install` part, and `drop_in` parts of any category except
light ones placed by hand or with a telehandler: ironwork and gates, lighting, landscaping,
openings, finishes, services, curtain wall. A lift goes to the tower crane when its piece is within
the jib − 1 m and it starts no later than 7 days after the roof is done; otherwise to the mobile
crane, one job per activity.

**Real time, not schedule time.** The dig cycle and truck round run in seconds of playback, and
only while the timeline is moving (the day changed since the last frame): a paused or scrubbed
timeline holds still, a recording is steady. The mobile crane's boom eases towards its target at a
3/s rate, so a scrub snaps the crane into place within a second instead of jumping.

## Scene integration

- **Nothing to configure.** `SequenceManager.auto_equipment` (default on): at Play, after
  `initialize_parts()` and before the cranes are collected, `SiteEquipment.ensure()` uses the
  scene's `SiteEquipment` or creates one as a child of the `SequenceManager`, and builds the
  machines. A scene with a `Crane` of its own gets no tower crane; the other machines still come.
- **Seeing and moving them: the dock's *Maquinaria* button.** It adds a `SiteEquipment` node with
  two saved markers, `TowerCraneSite` and `ExcavatorSite`, at the proposed positions, and writes the
  computed crane height and jib into the node. Move a marker and that is where the machine stands
  (the truck follows the excavator; the mobile crane is placed per job, so it has no marker).
  Pressing it again re-proposes. The models are generated under the markers and never saved, like
  generated formwork.
- **The timeline drives it.** `TimelineController.scrub_to()` calls
  `SiteEquipment.update_all(tree, schedule, day, building_parts)` after its crane retract, so a crane
  following a piece picks it straight back up after a scrub. The dock's preview does the same; Stop
  Preview calls `SiteEquipment.reset_all()` (everything back on its markers, at rest).
- **Not work, not geometry.** No machine is a part, none is collision-checked, none appears in the
  inspector or the schedule.

Small additions it needed: `ConstructionSchedule.source_data` (the JSON the schedule was built
from) and `get_part_window(part)`; `ConstructionTerrain.world_height_at()` / `ground_y()`, which
grade the platforms on demand when asked before the terrain's own `_ready()` (a `SequenceManager`
earlier in the tree).

## Measured on the test project

`4d-e-2e-5`, the Galician pazo (663 parts, 47 actions), headless and with rendering:

- Tower crane at (20.1, −0.3, −14.3), the back-right corner, 55 m jib, 30 m under the jib;
  3,072 triangles. On site day 30–257 (2027-03-31 → 2027-11-13): up before *Formigón de limpeza*
  (day 34), down after *Cubrición de lousa*. It follows 120 pieces: quoins, window surrounds,
  cornices, corbels, the coat of arms, the roof timbers and the *solaina*. Balconies and ironwork
  are light lifts and get no crane.
- Mobile crane: three jobs, all placed after the tower crane has gone — *Emparrado*
  (2027-11-22), *Hórreo* (2028-01-18) and *Cruceiro* (2028-02-25).
- Excavator at the pit's front edge for *Retirada de terra vexetal* and *Escavación* (days 10–33).
- Cost: building the machines 33 ms, the plan 18 ms, `follow_schedule()` 24 µs per frame.
- Movie Maker: a full 380-frame recording ran to completion with all four machines in it.

## Known gaps

- **Crane geometry is still not clash-checked** — a jib sweeping through a finished element is
  invisible to the clash system (`12_FUTURE_WORK.md`, section 3). The `install` path is still up,
  across and down; only its start moved to the laydown area.
- **Tower crane follows `drop_in` pieces from wherever they appear**, just above their place; it
  doesn't fetch them from the laydown first (that is what `install` does).
- **One excavator, one truck, one mobile crane.** Overlapping mobile jobs: the earliest wins. The
  excavator doesn't travel along the pit.
- **The truck doesn't bring concrete** (`concrete_pour` with a mixer body was listed as "later").
- **Markers save positions only**; the excavator faces −Z of its marker, so turn the marker to
  turn it.

## Tests

`tests/test_equipment.gd`, 69 checks on a box fixture (a 20 × 10 m building with its dig, footings,
walls, a cornice, a roof, a cross 90 m away, a granary placed after the roof, street lights and a
boundary wall 40 m out): node names and triangle budgets; dimensions; the tower crane works as a
`Crane` and picks up from its laydown; the dig cycle reaches into the ground and dumps over the
truck body; the mobile boom puts its tip 6 m over a target; placement (clear of the building, not
dragged out by the boundary wall, jib covering every corner, 10 m over the top); the plan (crane
window, which pieces go to which crane, no crane for street lights); presence day by day (dig,
half-erected mast, crane following a cornice stone, mobile crane beside the cross, crane gone,
mobile crane back for the granary); the truck round; reset; a scene's own crane; opting out.
