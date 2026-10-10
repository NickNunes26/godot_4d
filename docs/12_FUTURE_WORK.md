# 4D Construction Tool — Future work (to-do list)

> **Status: not built.** The planned work, in priority order. Each item records what is wrong or
> missing today, what a good version needs, and how we would know it is done. When an item is
> built, move its reasoning into its own numbered doc (as `07_FORMWORK.md` and
> `11_TYPES_REALISM_CLASHES.md` did) and mark it here.

| # | Item | Size |
|---|---|---|
| 1 | [Scaffolding and formwork: robust changes needed](#1-scaffolding-and-formwork-robust-changes-needed) | Large |
| 2 | ~~[Model support equipment: tower crane, mobile crane, truck, excavator](#2-model-support-equipment)~~ **Built** — `13_SITE_EQUIPMENT.md` | Medium |
| 3 | [Smaller open items](#3-smaller-open-items) | Small each |

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
  serves, then Reload from JSON. Nobody gets that right first time.
- **Regenerating the schedule destroys it.** Generate 4D Schedule does not carry `formwork`
  blocks forward (formwork build-order step 6, still open), so every re-import of the model undoes
  the setup — silently.
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
- **Crane geometry isn't collision-checked** — a jib sweeping through a finished element is
  invisible to the clash system. Open since Phase 2; more relevant now that every project has a
  tower crane (item 2).
- **The `install` path is fixed**: up 5 m, across, straight down. Since item 2 it starts at the
  tower crane's laydown area (its `PickupZone`) instead of 15 m to the side, but the path itself
  doesn't come from the crane, and a vertical final approach through whatever is above is reported
  as a clash (correctly, for that path).
- **`rise_up` and `sink_down` move 10 m.** Inference no longer uses `rise_up`. Excavation still
  uses `sink_down`, which pushes the soil down through the ground; a "dug away" animation (the
  reverse of `build_up`, top first) would read better.
- **Inference could use the IFC class** (`IfcWall`, `IfcSlab`, `IfcWindow`…) as a second signal
  when an activity's name says nothing — the adapter would need to keep it on the part.
- **Look-at camera targets** (`"look_at": "D4"`) — deferred from camera keyframes.
- **Mixed Spanish/English labels in the dock** — tooltips give the English names; a proper
  language setting would remove the need.
