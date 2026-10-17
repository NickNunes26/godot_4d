# 4D Construction Tool — Site equipment (maquinaria)

> **Status: built** (2026-10-10). Item 2 of `12_FUTURE_WORK.md`. Code: `equipment/equipment_models.gd`
> (`EquipmentModels`), `equipment/site_equipment.gd` (`SiteEquipment`); hooks in
> `equipment/route_planner.gd` (`RoutePlanner`, the mobile crane's drives),
> `runtime/sequence_manager.gd`, `runtime/timeline_controller.gd`, `editor/timeline_dock.gd`,
> `core/construction_schedule.gd`, `terrain/construction_terrain.gd`. Tests:
> `tests/test_equipment.gd` (92 checks). Measurements: `equipment/specs/` (`EquipmentSpecs`).

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
| **Tower crane**, flat-top | 1.6 m square lattice mast in ~3 m sections; jib length and height from the site (below); counter-jib 0.3 × jib (10–22 m) with walkway, winch and concrete blocks; cab at the slewing ring | `Arm` (slews; jib along +X), `Track` (trolley), `Rope` (Y scale = length), `Hook`, `PickupZone`, `Mast/Section<i>` | 2,916 (50 m jib) |
| **Mobile crane**, all-terrain | 4-axle carrier 11.6 × 2.55 m; carrier cab; superstructure with crane cab and counterweight; 4-section telescopic boom 13.0 → 41.8 m; four outriggers to 3.6 m each side, jacks and pads | `Slew`, `Slew/Boom`, `…/Section1..3`, `…/Tip`, `Outrigger0..3`, `Hook`, `Rope` | 2,028 |
| **Truck**, rigid 3-axle tipper | 9.0 × 2.5 × 3.0 m; cab, chassis, tipping body (50°) with a soil load | `Body`, `Body/Load` | 660 |
| **Excavator**, Caterpillar 320 (~22 t), to the published sheet | Tracks 4.45 m long (3.65 m idler to sprocket), 2.38 m gauge, 0.6 m shoes, 2.98 m wide, 0.47 m ground clearance, 8 track and 2 carrier rollers a side; upper frame 2.78 m wide, counterweight 1.05 m off the ground, 2.83 m tail swing, cab top 2.96 m, handrails 2.95 m; banana boom 5.70 m pin to pin, stick 2.9 m; 1.2 m, 1.19 m³ bucket, 1.57 m tip radius, curved wrapper, side plates, cutting edge, five teeth on adapters, side cutters, wear strips; twin boom rams, stick ram, bucket ram with power and idler links | `Undercarriage`, `Upper` (slews), `Upper/Boom`, `…/Stick`, `…/Bucket`, `…/Bucket/Load`, `Upper/BoomRamL`/`R`, `Upper/Boom/StickRam`, `…/Stick/BucketRam`, `…/PowerLink`, `…/IdlerLink` | 2,948 |

Posing goes through static helpers so callers never walk the hierarchy:
`pose_mobile_crane(root, slew, luff, extend, outriggers, hook_drop)`,
`pose_truck(root, tip, load)`, `pose_excavator(root, slew, boom, stick, bucket, loaded)`.
`excavator_teeth()` and `excavator_bucket_pin()` give the bucket's position for a pose, which is
how the dig cycle was solved and how the test checks it. The excavator's joints are clamped to
limits fitted to Caterpillar's working ranges (next section); the rams and the bucket linkage
follow every pose (the linkage joint is solved as the intersection of the idler and power links).
Small cylinders (pins, rollers) use 8 sides instead of 14, which is what keeps the excavator under
3,000 triangles with all of that.

## Measurements

The excavator is sized from real published figures, kept in
`equipment/specs/excavator_cat_320.json` and read through `EquipmentSpecs`:

- **Source**: Caterpillar's *320 Hydraulic Excavator — Technical Specifications* (the PDF served by
  a Cat dealer, retrieved 2026-10-10; the URL and pages are in the file), configuration reach boom
  5.7 m, R2.9B1 stick, 1.19 m³ HD bucket, 600 mm shoes, 4.2 t counterweight, long undercarriage.
  The only figure not from that sheet is the overall track length (4.45 m), from a dealer listing,
  marked as such.
- **Contents**, in millimetres as printed: dimensions (cab, FOGS and handrail heights, shipping
  height and length three ways, upper-frame width, tail swing radius, counterweight and ground
  clearance, track length, gauge and width, shoe count and rollers), the front (boom, stick, bucket
  width, capacity, tip radius, weight), the working ranges (maximum digging depth 6.72 m, reach at
  ground line 9.86 m, cutting height 9.37 m, loading height 6.49 m, minimum loading height 2.17 m,
  2.44 m level-bottom depth 6.55 m, vertical wall depth 5.19 m), performance (swing 11.3 rpm,
  travel 5.7 km/h, digging forces, operating weight 21.9 t) and the hydraulic cylinders' bores and
  strokes.
- **How the model uses them**: the dimensions are constants in `EquipmentModels` (`EXC_*`), and the
  test reads the JSON and checks every one against the built model. The boom foot, boom tip and
  joint limits were fitted (a grid search over the model's own kinematics) so that the model's
  working range lands on Caterpillar's: reach at ground line 10.01 m (Cat 9.86), digging depth
  6.74 m (6.72), cutting height 9.07 m (9.37) — all within 5 %, which the test asserts via
  `EquipmentModels.excavator_envelope()`.
- **For clash detection later**: the volumes a check needs are in the file as the manufacturer
  states them, independent of the model — the swept front (working ranges, about the slew centre),
  the tail swing circle (2.83 m) and the transport envelope (9.53 × 2.98 × 3.16 m).
  `EquipmentSpecs.metres(id, section, key)` returns any of them in metres. Other machines can be
  added the same way: one JSON per machine in `equipment/specs/`.

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
- **Excavator at the terrain's pits** (0.7.2): every `TerrainPlatform` dug by an activity
  (`activities`) or filled back by one (`backfill_activities`) -- a footing's pit -- is a job
  for the excavator and its truck, whatever the activity is called: digging over the first,
  filling (the truck tips its load) over the second. The crew stands on natural ground just past
  the top of the banks -- walking out from the middle of the pit until the ground under its tracks
  is neither cut nor filled (`ConstructionTerrain.natural_world_height_at()` against
  `world_height_at()`), two metres further -- facing the pit, on the nearest of eight ways out not
  against anything already built by the first dig. Pits worked at the same time get a crew each
  (`DigRig2`, `DigRig3`... under the SiteEquipment, made as needed), their cycles out of step. Away
  from a job the crew is hidden: it has no place of its own. `_pit_jobs()`, `_pit_site()`.
- **Excavator**: off the front (+Z) edge of the pit, mid-way along it, facing in. The pit is the
  dig parts that go more than 0.5 m below ground; stripping topsoil off the whole plot is excavator
  work too, but the machine belongs at the hole. At least 4 m off, and further, a metre at a time,
  until its whole track length stands on the pad: graded terrain follows a 5 m grid, so the pit
  comes out wider than the parts that draw it (on the test project 4 m was 1.6 m down the bank).
  Its truck loads on its right (7.4 m out, beyond the 2.83 m tail swing) and drives off behind it.
- **Mobile crane**: per job, outside the pieces on the side away from the building — the pieces'
  box radius + 7.5 m from their centre — with the carrier side-on to them. If that spot is not
  5 m clear of everything standing on the day of the lift (a part whose window has ended, or a
  static one), it turns round the pieces and steps out until one is. On the test project the
  granary's first spot was on the boundary wall; the crane now lifts it over the wall from outside.

Explicit values win: `tower_height` and `jib_length` on the `SiteEquipment` node (0 = automatic),
and the two marker nodes below.

## Following the schedule

`SiteEquipment.make_plan()` turns the schedule into windows, once per schedule:

| Machine | On site | Doing |
|---|---|---|
| Tower crane | from the first structural activity (concrete, rebar, steel/timber frame, precast, stone pieces, masonry) − `erect_days`, to the end of the last roofing activity (or the last structural one) + `erect_days` | Erecting: mast sections appear bottom-up over the first 75 % of `erect_days`, then jib, counter-jib and cab. Following: the most recently started `drop_in` piece it is assigned, via `Crane.swing()` (1.2 s slew, then the hook tracks the piece down). `install` units stay `TimelineController`'s; a piece being installed is never interrupted. Idle: `Crane.retract()`. |
| Mobile crane | each job's first piece − 0.75 day to its last piece + 0.75 day, plus the drives to and from it (next section) | Outriggers out over the first half day, boom up; boom tip 6 m over the current piece, hook down to it; stowed again before it leaves |
| Excavator + truck | every excavation and earth-fill activity | Excavation: an 11 s dig cycle (reach, teeth in, drag and curl, lift, slew 90° over the truck, dump); the truck's round is six cycles — reverse in from 40 m, four loads, drive off. With no truck at the spot the bucket is emptied onto a spoil heap on the other side. Earth fill: the truck arrives full and tips at the spot. |

**Which lifts need a crane.** Every `install` part, and `drop_in` parts of any category except
light ones placed by hand or with a telehandler: ironwork and gates, lighting, landscaping,
openings, finishes, services, curtain wall. A lift goes to the tower crane when its piece is within
the jib − 1 m and it starts no later than 7 days after the roof is done; otherwise to the mobile
crane, one job per activity.

## Driving between jobs

*Added in 0.7.3.* The mobile crane used to appear at each job's spot and vanish afterwards. It
now drives, and a drive is planned, not reported: where the straight line would go through
something, the crane takes the shortest way that does not (`_plan_mobile()`, `_drive()`,
`equipment/route_planner.gd`).

**Is the move needed at all?** Two consecutive jobs are one spot (one stand, one outrigger
set-up, one continuous stay) when

1. they are no more than `hold_days` apart (default 30, an export on `SiteEquipment`) --
   a crane that is not needed for longer is hired out, so it leaves by the road it came and
   comes back for the next job; and
2. from where it stands it can still make the next job: the spot is still 5 m clear of everything
   built by then, and the boom (13.0–41.8 m, tip 6 m over the piece) reaches every piece
   (`boom_needed()` against `BOOM_MAX`).

If either fails it moves. A job's `parts` and `finish` then simply grow to cover both.

**When it moves** it drives from the spot it is at to the next (or, arriving and leaving, from and
to a point `ACCESS_RUN` = 40 m out on the side away from the work), taking `length / DRIVE_MPD`
days of schedule (150 m/day, between 0.15 and 0.6 day), arriving just in time for the outriggers: it
waits parked where it was until then (`park` segment) rather than standing early in the way of the
next job. Obstacles are the rest boxes of every part **whose work has started by then** (a wall
half built is a wall), taller than 0.5 m above ground, plus a 3 m square round the tower crane's
mast while that is up. Not obstacles: ground-level layers, anything not yet started, the machines
other than the mast.

**How the route is found** (`RoutePlanner.find()`):

1. **Straight line first.** The carrier's body (11.6 × 2.55 m plus 0.6 m each side) swept along
   the line against every obstacle. Free: that is the route, no search.
2. **Otherwise the shortest way round**: a visibility graph over the corners of the obstacles,
   each grown by half the width plus a margin, searched with A\*. Obstacles that contain the
   start or end are grown only as far as keeps it outside (the crane stands where it stands).
3. **Checked with the real body.** A point fits anywhere; an 11.6 m carrier swings at corners. The
   route is verified leg by leg (the swept rectangle, the ends beyond a corner included) and at
   every corner (the body turned through six headings). If it fails, the search repeats with more
   room -- margins 0.6, 1.5, 3, 5, 8 m, nearest-and-shortest first -- and the first that passes
   wins. Obstacles beyond 40 m of the start-goal box are ignored, then 120 m.
4. **No route** (a closed wall, a goal inside a building): `ok = false`, the plan carries the
   straight line so the crane still moves, and a warning says which drive on which day.

While playing, the crane is placed along the route by the day (`RoutePlanner.sample()`), facing
the way it goes with the heading turning smoothly round corners and easing into the way it stands
at each end (it may back in). Boom stowed and outriggers in. A scrub lands it in the right place at
once, like the rest of the site. The switch **Show Routes** on `SiteEquipment` draws every
planned drive as an orange line on the ground.

The plan holds it: `plan.mobile_segments` (`stand`, `park`, `drive`, tiling the time on site) and
`plan.drives` (`t0`, `t1`, `points`, `length`, `ok`, `direct`, `margin`).

**Measured on the test project** (Galician pazo, hold 30 days): three jobs, five drives -- in and
out for the first two, and *Hórreo* → *Cruceiro* (three weeks apart, the crane waits in between),
taking an 83 m way round (54 m straight, through what stands there). The first two jobs are further apart than the 30-day limit, so the crane leaves and
returns for them; with `hold_days` raised it would drive between them the same way.

## Booms and lifts that clear what is built

*Added in 0.7.3, with the drives above.* The same rule -- plan a way that clears, don't report
the clash -- for the boom and for crane lifts.

**The mobile crane's boom** (`_boom_lift()`, `_boom_clear()`). The boom is a line from its foot to
the tip, which is 6 m over the piece, 0.8 m of clearance either side, and a hook line straight
down from the tip to the piece. For each of a job's pieces it must clear every part that had
started by the time the piece goes in and is still there (a part the schedule removes -- cleared
trees, a stripped scaffold -- stops counting when it goes), except what touches the piece (the
wall it sits on). Looking for a spot, in the order the crane always tried them (away from the
building first, then turning round the pieces, then stepping out up to `radius + 30` m):

1. a spot with a road in (below) where the boom clears **at its usual height** wins, so a crane is
   moved before its boom is raised;
2. failing that, the spot where the tip needs to go **least higher** (`BOOM_RAISE`: +3, 6, 10, 15,
   22 m, kept within the 41.8 m boom and 80° luff) -- the job's `tip_up`, applied to every piece
   and to the idle aim;
3. failing that, the first free spot, `boom_ok = false` in the job, and it will clash.

A stand shared by two jobs (merged, above) needs the boom clear for the new pieces as well.

**A road in.** A spot is no use if the crane cannot get there: `_road_map()` floods the ground
reachable from 60 m out, round what stands then (2 m grid, parts grown by 2.5 m; `RoutePlanner.flood()`),
and a spot off it comes second to one on it. On the test project the *Hórreo* crane moved from
(25.0, 26.9) to (17.5, 25.8): at the first spot the boom could not clear a tree-clearing part
that the plan still counted as standing after its `fade_out` (next paragraph), and once that was
fixed the spot the boom liked was inside the boundary wall with no road in.

**Removed parts.** The standing list now says when a part is *gone*: `fade_out` and `sink_down`
hide a part at the end of its window, and it used to count as present from that moment. Spots,
drives and booms all use it.

**`install` lifts** (`core/lift_planner.gd`, `LiftPlanner`; `ConstructionSchedule._plan_lifts()`).
The default lift is up 5 m, across at that height, down. Per unit (a commander and its parts, or a
lone part), once when the schedule is built:

1. the default path is checked against every part that had started by the time the piece is placed
   and is not removed, other than what touches the piece at its place or at its laydown -- as
   boxes, the piece (the unit's box) swept as a point among the obstacles grown by its size;
2. **free: nothing changes** -- no `install_path` meta, the same animation as ever;
3. otherwise candidates are tried **shortest first**: up to a height that clears something (just
   over the top of each obstacle in the way) then across then straight down (`raised`), or the same
   height then to a point beside the place (8 directions, 2--24 m) and in **sideways at the level of
   its place** (`side`) -- the way in when a floor or roof is over the place. The first free one
   is stored on every part of the unit as `install_path` (local positions), and
   `AnimationApplier._install_instant()` follows it, easing along its whole length;
4. a tower crane's limits apply: the piece stays under the jib (`y_max`), within the hook's reach
   (`r_max` = the farthest of laydown and place + 1.5 m) and not in against the mast (`r_min`
   3 m). The crane tracks the piece as before, so it follows whatever path is stored;
5. **no path** (the place is shut in on every side): the default is kept, the plan says
   `ok = false`, one warning says how many lifts and the first, and the clash scan reports the
   clash as before.

`ConstructionSchedule.lift_plans` (commander name → `{ok, direct, mode, length}`) says what was
decided; `ConstructionSchedule.plan_lifts_enabled = false` turns planning off (the tests use it to
see the default path's clash).

Plain `target_prefix` install actions have no crane and no unit; their parts are planned the same
way from the usual pickup 15 m to the side.

**Cost**: the mobile crane's plan on the test project (663 parts, three jobs, 22 + 15 + 5 pieces)
140 ms. Installing every `drop_in` of the pazo (204 lifts among 663 parts) takes about 4 s, most of
it spent on the 74 lifts with no path (every candidate tried); one install action of a dozen
precast pieces is a few tens of milliseconds.

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
- **On the real terrain** (the downloaded IGN ground, levelled from the model: pad at −9.13 m,
  pit to −10.93 m): every machine stands on the surface to within 1 cm — the tower crane on the
  natural slope beside the pad at −10.04 m, its laydown, the excavator, the truck over its whole
  round, the mobile crane at each of its three jobs — and each mobile-crane spot is clear of what
  is built by then. A full-year scrub with parts, terrain and machines: 4–6 ms per date headless.

## Known gaps

- **Drives, the mobile crane's boom and `install` lifts are planned round what is built; the
  tower crane's jib is not checked** (it is 10 m over the tallest part in reach by construction)
  and neither is the `drop_in` fall, which is straight down over the place.
- **Obstacles are boxes.** A pitched roof or a deck counts as solid over its whole footprint, so
  a lift under or beside one may find no path where the exact clash scan would find none either
  way -- the lift then keeps the default and the scan reports it. The boom is a line 1.6 m wide,
  not the carrier, superstructure and counterweight swinging.
- **Drives are planned in plan view only**: no slopes, no pits (an open excavation is not an
  obstacle), no turning circle -- the body is swept straight along each leg and swung at the
  corners, but the path itself is polylines. The excavator, the truck and the tower crane's
  laydown are not obstacles either, and neither are the crane's own outriggers (the spot is 5 m
  clear already).
- **Tower crane follows `drop_in` pieces from wherever they appear**, just above their place; it
  doesn't fetch them from the laydown first (that is what `install` does).
- **One mobile crane; one excavator crew for the model's own pit.** Overlapping mobile jobs: the
  earliest wins. The excavator doesn't travel along the pit. (The terrain's pits get a crew per
  overlapping job, above.) A pit's crew stands at the top of its banks whatever the depth -- on a
  deep pit, further from the bottom than the machine reaches.
- **The truck doesn't bring concrete** (`concrete_pour` with a mixer body was listed as "later").
- **Markers save positions only**; the excavator faces −Z of its marker, so turn the marker to
  turn it.

## Tests

`tests/test_route_planner.gd` (27 checks: the straight line, the way round, the shorter of two
ways, a gap too narrow for the body, a closed yard, which ground is reachable, sampling),
`tests/test_lift_planner.gd` (23: the default untouched, over a wall, round a post, in from the
side under a floor, a bearing is not in the way, shut in, a crane's limits, sampling),
`tests/test_collisions.gd` (21: the post that clashed on the default path is now cleared) and
`tests/test_equipment.gd`, 125 checks on a box fixture (a 20 × 10 m building with its dig, footings,
walls, a cornice, a roof, a cross 90 m away, a granary placed after the roof, street lights and a
boundary wall 40 m out): node names and triangle budgets; dimensions; the excavator against the
Cat 320 sheet (track length and width, ground and counterweight clearance, tail swing, cab top,
upper-frame width, boom, stick, bucket tip radius and width, and its working range within 5 % of
the published one); the dig cycle inside the joint limits; the tower crane works as a
`Crane` and picks up from its laydown; the dig cycle reaches into the ground and dumps over the
truck body; the mobile boom puts its tip 6 m over a target; placement (clear of the building, not
dragged out by the boundary wall, jib covering every corner, 10 m over the top); the plan (crane
window, which pieces go to which crane, no crane for street lights); presence day by day (dig,
half-erected mast, crane following a cornice stone, mobile crane beside the cross, crane gone,
mobile crane back for the granary, each mobile-crane spot clear of what is built by then); the
truck round; reset; a scene's own crane; opting out.
