# 4D Construction Tool — Future work (to-do list)

> **Status: items 1, 3, 4 and 5 open; item 2 built (`13_SITE_EQUIPMENT.md`).** The
> planned work, in priority order. Each item records what is wrong or missing today, what a good
> version needs, and how we would know it is done. When an item is built, its reasoning moves
> into its own numbered doc (as `07_FORMWORK.md`, `11_TYPES_REALISM_CLASHES.md` and
> `13_SITE_EQUIPMENT.md` did) and it is marked here.

**What "realism" means from here on.** Build4D is an interactive 4D planning tool: people place
the crane, change the schedule and see the consequences on the site. Realism therefore matters
less in **looks** than in **shapes**: the geometry that clash detection checks — crane jib, hook
path and laydown area, the excavator's working envelope, scaffolding, props, the building at each
date — has to be close enough to the real thing that a reported clash, or its absence, can be
trusted. Broad-strokes models stay the rule (the envelope matters, not the detail), and among the
open items the crane geometry that is not yet collision-checked (section 3) is a bigger realism
gap than anything visual. Presentation pictures are made outside Godot, in Blender (item 4); the
viewport only needs to read clearly on an ordinary laptop (item 5).

| # | Item | Size |
|---|---|---|
| 1 | [Scaffolding and formwork: robust changes needed](#1-scaffolding-and-formwork-robust-changes-needed) | Large |
| 2 | ~~[Model support equipment: tower crane, mobile crane, truck, excavator](#2-model-support-equipment)~~ **Built** — `13_SITE_EQUIPMENT.md` | Medium |
| 3 | [Smaller open items](#3-smaller-open-items) | Small each |
| 4 | [Export to Blender for presentation stills](#4-export-to-blender-for-presentation-stills) | Medium |
| 5 | [A clearer viewport, with quality levels](#5-a-clearer-viewport-with-quality-levels) | Small |

---

## 1. Scaffolding and formwork: robust changes needed

### Where it stands

Formwork (`07_FORMWORK.md`) was designed for **concrete forms around one element**: an action's
window splits into a formwork phase and the pour; panels assemble before the pour and come off at
the end. It works for that. **Scaffolding was then made to ride on the same mechanism**, and
that is where it breaks down. Seen on the test project (`Z99_Andamio`, a façade scaffold modelled
in the IFC):

- **Setting it up means editing JSON by hand.** The guide's own procedure (section 9): delete the
  scaffold's row in the inspector, save, open `construction_steps.json` in a text editor, add
  `"formwork": {"prefix": "Z99_Andamio", "pour_days": 84, "strip_days": 3}` to the action it
  serves, then stop and start the preview. Nobody gets that right first time.
- **Regenerating the schedule destroys it.** Generate 4D Schedule does not carry `formwork`
  blocks forward (formwork build-order step 6, still open), so regenerating undoes the setup —
  silently. (Since the dock rework in 0.7.0 a later Load IFC no longer regenerates: it only
  adds missing activities, so a re-import keeps formwork; the explicit **▾** → Generate 4D
  Schedule still destroys it.)
- **One scaffold, one activity.** A prefix can belong to one action. A real façade scaffold serves
  the masonry, the quoins, the window surrounds, the cornice and the eaves — several activities
  over months. Today it has to be attached to one of them and the others are scheduled as if it
  weren't there.
- **The phasing is concrete's, not scaffolding's.** The host action's own elements are squeezed
  into its last `pour_days` days ("Días vertido" — meaningless for stonework); the scaffold is
  all assembled before any of the host's work starts (staggered over the formwork phase), and
  every piece is removed at once at the end (`strip_type`, `fade_out`). A scaffold goes up **lift
  by lift, keeping ahead of the work**, and is struck **top-down** after the last trade leaves.
- **Inference stops halfway.** `TaskClassifier` recognises *andamio* / *encofrado* /
  *scaffolding* / *formwork* and gives them `build_up`, but cannot attach them to the work they
  serve, so they still animate as a free-standing activity.
- **Generated formwork covers vertical faces only.** Boards come off the element's vertical faces
  (build-order step 7). Slabs and beams need **soffit formwork and props** (*cimbra*,
  *apuntalamiento*) underneath, which are not generated; a slab currently pours with nothing
  holding it up.
- **Only pours will get forms automatically.** The planned generator rule (decision 4) proposes
  formwork for `fill_up` actions only; temporary works for `build_up` walls or `drop_in` stone
  and precast always have to be attached by hand.
- **Temporary works are half-visible to clash detection.** Generated panels are deliberately not
  collision-registered (decision 3). Scaffolding modelled in the IFC is, but only as an ordinary
  part, with no notion that a crane lift must clear it — one of the commonest real lifting
  constraints.
- **Placeholder look.** Plain brown boards; no tubes, boards, rails, or props.

### What a robust version needs

1. **Scaffolding as its own concept**, separate from concrete forms: a `scaffold` block (or an
   action kind) naming its parts (prefix, model asset, or generated) and the **list** of
   activities it serves. It is erected from a lead time before the first of them and struck after
   the last, independent of any one activity's window.
2. **Realistic phasing.** Erect bottom-up by lift (2 m levels, reusing
   `SpatialGrouper.LEVEL_BAND`-style banding), keeping one lift ahead of the work it serves;
   strike top-down. Same for slab props: up before the forms, down after a curing period
   (`cure_days`), which formwork has no notion of today.
3. **Automatic pairing.** Classifier finds the temporary-works activities; geometry proposes what
   they serve (scaffold parts within a few metres of a façade's elements → that façade's
   activities); the dock shows the proposal and one click accepts it. No JSON.
4. **Generated scaffolding when the model has none**: per façade, standards + ledgers + boards +
   guard rails at 2 m lifts, sized to the façade's height and length. Broad strokes, procedural.
5. **Soffit formwork and props** generated under `fill_up` slabs and beams.
6. **Survives regeneration** — formwork step 6 with carry-forward, extended to scaffold blocks.
7. **Everything authorable from the inspector**: an *Andamio* column next to *Encofrado*, a
   served-activities picker, and labels that make sense for non-concrete work (drop *Días vertido*
   wording for scaffolds).
8. **Opt-in clash checking** of temporary works against crane lifts.
9. **Tests** on box fixtures plus the test model: a façade scaffold serving three activities
   rises ahead of the masonry, holds through all three, strikes top-down after the last, and
   survives Generate 4D Schedule.

### Done when

The test project's `Z99_Andamio` can be set up from the dock alone, serves the stonework,
surrounds and cornice together, goes up with the walls and comes down top-down after the eaves —
and is still there after re-importing the IFC and regenerating.

---

## 2. Model support equipment

> **Built 2026-10-10** — see `13_SITE_EQUIPMENT.md` for the design as built, the measurements
> on the test project and the tests.

All four machines exist as procedural models (`EquipmentModels`) and come with no setup
(`SiteEquipment`, created by `SequenceManager` at Play; the dock's **Maquinaria** button shows and
places them in the editor). The tower crane is a real `Crane`: it goes up before the first
structural activity, follows the `drop_in` pieces it can reach, drives `install` lifts from its
laydown area, and comes down after the roof. A mobile crane sets up beside each lift the tower
crane can't make; an excavator loads a truck at the pit during the earthworks. Every "done when"
point was checked on the test project, including a Movie Maker recording.

Left from the original scope, now in section 3 or `13_SITE_EQUIPMENT.md`, "Known gaps": the truck
as a concrete mixer, the excavator travelling along the pit, `drop_in` pieces fetched from the
laydown area rather than appearing above their place.

---

## 3. Smaller open items

- **Formwork step 6** — the generator rule with carry-forward (`07_FORMWORK.md`). Folded into
  item 1, but worth doing first on its own: until then, Generate 4D Schedule destroys formwork.
- **Crane geometry: mostly built, by planning rather than reporting.** The approach is to **plan a
  path that clears instead of reporting a clash**, and it now covers the mobile crane's drives
  (shortest route round what is built, no move at all when the next piece is in reach), its boom
  (another spot, or the tip held higher, so the boom and hook line clear what stands) and the
  `install` lift (over, round or in from the side; `13_SITE_EQUIPMENT.md`, "Driving between
  jobs" and "Lifts that clear what is built"). **Still open:** the tower crane's jib and
  counter-jib are clear by construction (10 m over the tallest part in reach) but not checked;
  the `drop_in` fall is straight down from above and the tower crane follows it without
  checking what is over the place; obstacles are boxes, so a pitched roof counts as solid over
  its footprint and some lifts under or beside one find no path (a refinement: voxelise large
  parts); the boom is a line, not the superstructure and counterweight; the excavator's
  envelope (`equipment/specs/`, `EquipmentSpecs`) is on file but not used for clashes.
- **`rise_up` and `sink_down` move 10 m.** Inference no longer uses `rise_up`. Excavation still
  uses `sink_down`, which pushes the soil down through the ground; a "dug away" animation (the
  reverse of `build_up`, top first) would read better.
- **Inference could use the IFC class** (`IfcWall`, `IfcSlab`, `IfcWindow`…) as a second signal
  when an activity's name says nothing — the adapter would need to keep it on the part.
- **Look-at camera targets** (`"look_at": "D4"`) — deferred from camera keyframes.
- **The schedule inspector has 15 columns.** The dock rework in 0.7.0 cleared the buttons;
  the grid is next. *Unidades/Día* is another view of *Duración*, *Fecha Fin* is derived, *Ancla*
  and *Escalonado (s)* are for fine control — candidates for a "more columns" toggle.
- **Mixed Spanish/English labels in the dock** — tooltips give the English names; a proper
  language setting would remove the need.

---

## 4. Export to Blender for presentation stills

### Where it stands

The only pictures Build4D produces are what the Godot viewport shows: a screenshot, or a Movie
Maker recording. That viewport is a real-time renderer (Forward+) showing the IFC's own
materials, which are flat colours with no textures and, normally, no UV coordinates. Good
enough to plan with; not what goes into a client presentation.

Making Godot look photoreal is the wrong investment (see "What realism means" above). Blender's
**Cycles** is a path tracer: it computes the light physically, renders each frame from scratch
(so geometry that changes with the schedule is no problem), and is free. The job is a **few
stills of the model** — the finished building, or the site on a chosen date — not a 4D video:
the interactive 4D stays in Godot.

**Budget: a handful of shots in about 20 minutes of rendering** on the reference laptop (GeForce
GTX 1050 Ti 4 GB, Core i7-8750H). Not measured yet; the estimate is 3–8 minutes per 1080p
exterior at 128–256 samples with denoising, so 3–5 shots. 4K and glazed interiors take several
times longer. The binding limit is the card's **4 GB of video memory**: textures at 1–2K,
restrained vegetation, or Cycles fails or falls back to the much slower CPU.

### What a good version needs

1. **Export from Godot, not from the raw IFC.** A dock action (*Exportar a Blender…*) writes the
   scene as glTF (`GLTFDocument`) **at the timeline's current date**: parts in their state on
   that day, the terrain, the equipment where it was placed. Importing the IFC straight into
   Blender (Bonsai) would lose all three and the georeferenced placement.
2. **A sidecar JSON** next to the `.glb`: the site's latitude and longitude (from the
   georeference), the date and time, the sun direction `GeoSun` computed, the cameras to render,
   and for each mesh the IFC material or style name and the part name. Check whether GDIFC's
   material names survive into the glTF; the sidecar covers it if they don't.
3. **Custom shaders do not survive glTF.** The terrain's ground shader in particular: the
   exporter gives the terrain a plain material and the sidecar marks it, so the Blender side can
   apply its own ground material.
4. **A Blender setup script** shipped with the addon (Python, e.g. `tools/blender/`). It imports
   the `.glb` and the sidecar and then:
   - swaps materials by keyword for CC0 PBR sets (ambientCG, Poly Haven — bundling allowed):
     *formigón / hormigón* → concrete, *granito / cantería / sillería* → stone, *pizarra /
     lousa* → slate, *tella / teja* → roof tile, *madeira / madera* → timber, *vidro / vidrio* →
     glass, *revoco / enfoscado* → render. Box projection, because the IFC meshes have no UVs.
     One keyword table, in the spirit of `TaskClassifier`, shared with item 5;
   - sets Blender's physical sky and sun from the sidecar, so the light matches the date and
     place Build4D shows;
   - creates the cameras from the sidecar;
   - sets Cycles for the budget: GPU, denoising, adaptive sampling, 1080p by default, textures
     capped at 2K.
5. **Shots framed in Godot.** A short list of saved views ("photo cameras") in the scene, written
   into the sidecar, so nobody has to frame shots again in Blender. Preview in EEVEE (seconds per
   frame), final render in Cycles.

### Done when

On the test project: one action in Godot, then opening Blender and running the script, gives
four 1080p Cycles stills of the finished *pazo* on its terrain in **under 20 minutes of rendering
on the reference laptop**, with stone, slate, timber, glass and render recognisable and the sun
matching what `GeoSun` shows for that date and time. The same steps at an earlier date give a
still of the site mid-construction, cranes included.

---

## 5. A clearer viewport, with quality levels

### Where it stands

When a scene has no environment of its own, `SequenceManager._default_environment()` adds a
procedural sky, ambient light from the sky, Filmic tonemapping and one shadowed sun. Parts keep
the IFC's flat colours. Glass, stone, slate and render are told apart by colour alone, and depth
is hard to read in a dense model.

### What a good version needs

The aim is **legibility, not photorealism** — photos are item 4. And it has to run on the
machines the people using it actually have; the reference is the same GTX 1050 Ti laptop.

1. **A quality setting** on the `SequenceManager` (*Bajo / Medio / Alto*, default *Medio*):
   - *Bajo*: today's environment.
   - *Medio*: AgX tonemapping, SSAO, a physical sky driven by `GeoSun`, tuned shadow cascades.
   - *Alto*: adds SSIL, SDFGI and light fog.

   Frame rate measured on the test project for each level, during Play with the equipment
   working.
2. **Better flat materials without textures**: roughness, metallic and transparency set from the
   same keyword table as item 4 (glass smooth and see-through, metal metallic, stone and render
   rough). No UVs, no texture memory.
3. **Authored environments still win**, as today: a scene with its own `WorldEnvironment` or sun
   is left alone.
4. **Check SDFGI with changing geometry** before putting it in *Alto*: parts appearing and
   disappearing as the schedule plays may leave stale or leaking light.
5. **Looks never change results.** No level touches part shapes or the collision geometry.

### Done when

On the test project, *Medio* holds 30 fps or more at 1080p on the reference laptop during Play
with the equipment working; glass, stone, slate and render can be told apart by more than
their colour; and the clash results are identical at every level.
