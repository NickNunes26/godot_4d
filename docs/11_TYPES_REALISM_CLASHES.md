# 4D Construction Tool — Animation types, inference, realism and clash detection

> **Status: built 2026-10-10.** As-built description plus the reasoning, in the same spirit as
> `07_FORMWORK.md`. Covers four connected pieces of work that came out of one review of the
> end-to-end test project (`4d-e-2e-5`, the 663-part Galician *pazo* model):
>
> 1. The animation type is **inferred from the activity name** (`TaskClassifier`).
> 2. A new **`build_up`** type, and **`drop_in`, `scale_up` and the fades reworked** to look like
>    construction rather than special effects.
> 3. **Clash detection** stopped reporting designed contact and started lifting from the right
>    place.
> 4. Staggered pieces are **placed bottom-up**.
>
> Future work that this review surfaced but did not build — robust scaffolding/formwork and
> support equipment (cranes, trucks, excavators) — is in `12_FUTURE_WORK.md`.

---

## Why

The review found three complaints, all valid:

- **It is complicated to use.** Every action needed an animation type, typed by hand into a
  model property, an MS Project column or the inspector. In the test project the saved types
  differed from what the activity names imply on 17 of 47 rows, several plainly wrong — lean
  concrete *fading out*, both excavations *scaling up*, the scaffolding being *poured* — because
  whoever types them gets no feedback until playback.
- **The realism isn't there.** Masonry slid up through the slab from 10 m underground
  (`rise_up`); pieces fell 15 m out of thin air (`drop_in`); planting and formwork inflated from
  their centres and overshot (`scale_up`); glass finished its fade fully opaque.
- **Clash detection flags everything.** With the stone and timber pieces turned into crane lifts,
  39 activity pairs were reported, largely for touching what they were designed to touch.

---

## 1. Type inference — `core/task_classifier.gd`

A schedule already says what each task is. `TaskClassifier.classify(texts)` reads it and returns
`{type, batch, category, keyword}`, or `{}` when the name says nothing it knows.

### What it reads

The action's code and its label: `TaskClassifier.action_text(action)` joins `id`,
`target_prefix`/`commander_prefix` and the label half of `comment` (the generator writes
`"<label> -- N part(s), dates"`). For IFC generation it is the type property's value, the Element
ID and the display name.

### Normalisation

Lower case, accents folded (á→a, ñ→n, ç→c…), CamelCase split, every non-letter a space:
`C10_PilaresPB` → `c pilares pb`, `Formigón de LIMPEZA` → `formigon de limpeza`. Keywords then
match at **word starts**, so a stem covers its inflections (`hormig` = hormigón, hormigonado,
hormigonar). A few are pinned to whole words where a stem would be ambiguous: `forja`/`forxa`
(ironwork) must not match `forjado`/`forxado` (slab); `desmonte` (cut) is not `desmontaje`
(dismantling).

### Choosing between matches

Names often hit several rules: "Zapatas de formigón armado" has an element (*zapata*), a material
(*formigón*) and a rebar word (*armado*). Each rule has a **priority**; the highest wins. Equal
priorities go to the **earliest keyword**, which is the head noun in Spanish, Galician and
Portuguese — "Relleno de zanjas" is a fill, "Excavación y relleno" a dig.

The priorities encode one principle: **what is done outranks what it is done to.** Demolition and
clearing beat everything; digging and filling beat concrete; pouring beats rebar, rebar beats
formwork; framing materials (steel, timber, precast) beat the concrete element nouns (slab,
footing); generic element nouns (pilar, viga, escalera) come last.
So "Pilares metálicos" lifts in (steel) while "Pilares" pours, and "Encofrado y hormigonado"
pours while "Encofrado de losa" is formwork.

### The rules

Generated from `TaskClassifier.RULES`; edit the code, not this table. *Cadence* is the `batch`
the rule writes: *together* = one operation split into several meshes (`batch: true`),
*one by one* = discrete pieces (`batch: false`).

| Priority | Category | Type | Cadence | Keywords (word starts) |
|---|---|---|---|---|
| 100 | `demolition` | `fade_out` | one by one | demol, derrib, derrub, dismantl, desmontaj, desmontax, desmontag, levantado de, picado de |
| 95 | `site_clearing` | `fade_out` | one by one | desbro, tala, talas, talado, destocon, desmata, desarboriz, rocada, clearing, grubbing, tree felling, tree removal, felling |
| 90 | `excavation` | `sink_down` | together | excav, escav, vaciado, baleirad, desmonte, zanja, zanxa, vala, valas, terra vexetal, tierra vegetal, terra vegetal, capa vegetal, decapad, decapax, topsoil, trench, dig, digging, dredg, dragad, movimiento de tierras, movemento de terras, earthwork, earth work |
| 90 | `earth_fill` | `fill_up` | together | relleno, recheo, aterro, terraplen, backfill, embankment, compactac, subbase, sub base, zahorra, base granular, explanada |
| 80 | `concrete_pour` | `fill_up` | together | hormig, formig, concret, betao, betonag, beton, pour, vertido de, vertedura, lean mix, screed, recrecido, mortero autonivel |
| 75 | `rebar` | `fade_in` | one by one | armadura, armado de, armado da, armado do, ferralla, ferrallado, rebar, reinforcement, reinforcing, steel fixing, malla electrosoldada |
| 70 | `scaffolding` | `build_up` | together | andami, andaim, scaffold, encofrad, cofrage, cofragem, formwork, cimbra, apuntalam, shoring, falsework |
| 62 | `precast` | `drop_in` | one by one | prefabric, precast, pre cast, pre fabricad, modular |
| 60 | `steel_timber_frame` | `drop_in` | one by one | estructura metalica, estrutura metalica, metalic, acero, aceiro, aco, steel, perfil, cercha, celosia, truss, pares, cabrio, correa, purlin, rafter, madera, madeira, timber, castineir, carballo, estrutura de cuberta, estructura de cubierta, estrutura de cobertura, roof structure, solaina |
| 58 | `concrete_element` | `fill_up` | together | forjado, forxado, losa, losas, solera, soleira, zapata, encepado, riostra, pantalla, pilote, pilotaje, laje, lajes, sapata, slab, footing, pile cap, piles, raft |
| 55 | `stone_pieces` | `drop_in` | one by one | mensula, cornisa, cornixa, cornija, esquinal, esquinais, silleria, cantaria, canteria, recercad, dintel, lintel, umbral, imposta, balaustr, gargol, escudo, cruceiro, horreo, emparrado, pergola, bufarda, buhardilla, dormer, corbel, cornice, quoin, ashlar |
| 52 | `curtain_wall` | `fade_in` | one by one | muro cortina, fachada ventilada, curtain wall, cladding panel |
| 50 | `masonry` | `build_up` | together | mamposter, manposter, alvenaria, fabrica de, fabrica, ladrillo, ladrillos, tijolo, bloque, bloco, tabique, tabiqueria, muro, muros, parede, cerramento, cerramiento, cierre, cerre, peto, zocalo, chimenea, chemine, chamine, patin, escalinata, brick, block, masonry, stonework, wall, walls, chimney |
| 45 | `roofing` | `fade_in` | together | cubricion, cubrimiento, tejado, teja, tejas, tella, pizarra, lousa, cubierta, cuberta, cobertura, telhado, roofing, roof, slate, tiling roof, roof tiles |
| 42 | `ironwork_gates` | `drop_in` | one by one | forja, forxa, cerrajer, serralhar, barandill, barandal, varand, rejeria, reja, rejas, balcon, balcons, valla, vallado, cancela, porton, gate, gates, fence, fencing, railing, balustrade, guardrail, mobiliario, bancos, furniture |
| 40 | `openings` | `fade_in` | one by one | carpinter, ventan, fiestra, xanela, janela, puerta, porta, portas, acristal, vidrio, vidro, cristal, glazing, window, door, joinery |
| 38 | `lighting` | `drop_in` | one by one | alumbrado, alumeado, iluminac, luminaria, farola, lighting, street light, lamp post |
| 35 | `finishes` | `fade_in` | together | pavimento, pavimentac, solado, lousado, enlosado, alicatad, revest, revoco, enfoscad, enlucid, pintura, aislam, illam, isolam, impermeab, falso techo, teito, plaster, render, paint, flooring, floor finish, tiling, cladding, insulation, waterproof, terraza, acabad |
| 35 | `services` | `fade_in` | together | instalac, fontaner, electric, saneam, tuberia, tubaxe, conduct, climatiz, ventilac, calefacc, plumbing, hvac, pipe, duct, cabling, drainage, drenaje, drenaxe |
| 32 | `paving` | `fill_up` | together | firme, aglomerado, asfalt, bitumin, rodadura, asphalt, paving |
| 30 | `landscaping` | `scale_up` | one by one | jardin, xardin, ajardin, plantac, planta de arbo, arbolado nuevo, cesped, herba, landscap, planting, trees, hedge, seto |
| 28 | `concrete_columns` | `fill_up` | together | pilar, piar, piares, columna, soporte, cimentac, cimiento, foundation, viga, vigas, beam, column, escalera, stair, rampa, ramp |

It never returns `install`. Whether a piece goes in by crane is a decision about the site
(where the crane stands, what it can reach), not something a task name tells you, and `install`
is the one type that is clash-checked — inferring it would recreate the "everything is a clash"
problem by default.

### Where it is used

- **Generate 4D Schedule** (`IFCScheduleGenerator._derive()`), in this order: a user rule
  matching the type property → a type property value that already is a type name → **the
  classifier** (type property value + Element ID + display name) → the fallback type. Batching
  follows the classifier when it decided the type, `batch_for()` otherwise. Controlled by
  `IfcMapping.infer_types` (on; profiles without the key read as on); in the dialog, the checkbox
  *Infer the type from the activity name*. Hand corrections still survive regeneration through
  `last_generated`, unchanged.
- **Auto types** (dock, `TimelineDock._on_infer_types_pressed()`): every row of the loaded
  schedule, whatever it came from (CSV, Project XML, an older JSON). Overwrites the rows it
  recognises, including hand-picked types — it is an explicit button — and leaves unrecognised
  rows alone. Each change is printed (`C04_Limpeza: fade_out/one by one -> fill_up/together
  ("formig")`). Dirty until Recalculate, lost without Save to JSON, like any inspector edit.

### Measured

On the test project, Auto types recognises all 47 activities, changes the type of 17 and only
the cadence of 3 more. Every Galician
activity name is a check in `tests/test_task_classifier.gd`, alongside Spanish, Portuguese and
English cases and the words that must *not* match (87 checks).

### Extending it

Add words to the right rule in `RULES`, or a new rule with a priority placed by the principle
above, and add the name that motivated it to the test. Terrain levelling has its own, older
keyword list (`TerrainGrading.PAD_WORDS` / `PIT_WORDS`) for a different question — which
activities move the ground — and was left alone.

---

## 2. Animations that look like construction

Every type is a pure function of progress (`AnimationApplier.apply_instant()`); the live versions
of `scale_up`, `drop_in`, `fade_in` and `fade_out` now **drive those same functions** through
`tween_method`, so playing and scrubbing cannot disagree. The table is the full current set:

| Type | Inspector | What it shows | Used for (by inference) |
|---|---|---|---|
| `fill_up` | Hormigonar | Grows upward from its base, pinned at the bottom; optional pour stream during Play | concrete, slabs, footings, columns, earth fill, paving |
| `build_up` | Levantar | **New.** Same growth from the base, no pour | masonry, walls, chimneys, scaffolding, formwork |
| `drop_in` | Caer | **Reworked.** Lowered onto its place from just above, fading in first | stone pieces, precast, steel and timber framing, ironwork, lighting |
| `fade_in` | Emerger | **Reworked.** Fades in to the material's *own* opacity | roofing, openings and glazing, finishes, services, rebar |
| `fade_out` | Desvanecer | **Reworked** the same way; hidden when done | demolition, site clearing |
| `scale_up` | Aparecer | **Reworked.** Grows from the middle of its base, no overshoot | planting |
| `sink_down` | Bajar | Sinks 10 m and disappears | excavation, topsoil |
| `rise_up` | Subir | The whole element rises from 10 m below | nothing — kept for existing schedules |
| `install` | Instalar | Crane lift: up, across, down. Clash-checked | never inferred |

### `build_up`

`rise_up` was the only type for something going up, and it moves the *whole* element up from
10 m below — through the slab and foundations it stands on. `build_up` is `fill_up`'s growth
without the pour (`_grow_from_base()` for Play, `_fill_up_instant()` for scrubbing): a wall rises
course by course from where it stands.

### `drop_in`

Before: a fixed 15 m fall with a cubic ease-out — fastest at the top, slowest at the bottom — and
the piece popped into existence, opaque, in mid-air. It read as things being thrown at the
building.

Now it is the last few metres of a crane lift, the part anybody watches:

- **Height scaled to the piece**: `DROP_CLEARANCE + DROP_PER_METRE × height`, clamped to
  `[DROP_MIN, DROP_MAX]` = 1.5 m + 1.5 × h within [2.5 m, 8 m]. A 0.4 m cornice stone starts
  2.5 m up, a 3 m truss 6 m, a 6 m column 8 m. `AnimationApplier.drop_height(part)`.
- **Controlled descent**: sine ease-in-out — slow off the hook, steady, slow as it is set down.
- **Fades in** over the first `DROP_FADE` (20 %) of its window instead of appearing.

### `scale_up`

Before: scaled about the node origin with `TRANS_BACK`. IFC parts are re-origined to their
bounding-box centre, so everything inflated from its middle, in mid-air, and overshot to about
110 % before settling back — measured on a rotated part in a rotated, offset container, its base
wandered 2.86 m during the growth.

Now: uniform growth with the **middle of its base pinned** (`_base_pin_offset()`, using the
recorded `original_transform` because at scale zero a basis has no rotation left to read), sine
ease-out, never larger than finished. Formwork panels assemble with `scale_up` by default
(`DEFAULT_FORMWORK_TYPE`), so they now rise from the ground instead of inflating around the
concrete.

### Fades

Before: `fade_in` ended at alpha 1.0 and `fade_out` started from it — whatever the material was.
Glass (alpha 0.3) finished `fade_in` as an **opaque pane**, and only surface 0 of each mesh faded.
`fade_in` also left not-yet-started parts *visible at alpha 0* from day 0, paying for a
transparent pass for nothing.

Now every fade goes through `_set_opacity(part, fraction)`: every surface of every mesh, alpha =
fraction × the material's **own original alpha**, and at full opacity the material gets its
**original transparency mode** back (so opaque parts leave the transparent pass, which matters for
the ~160 formwork panels holding through a pour). The originals are recorded on the material on
first touch (`_c4d_original_alpha`, `_c4d_original_transparency`); materials are per-part
(`make_materials_unique()`), and `Resource.duplicate()` carries the metas into the next Start
Preview. `fade_in` is hidden until it starts, like every other type.

### Tests

`tests/test_animations.gd` (27 checks) pins all of the above: drop heights, monotonic descent with
slow ends, landing exactly; no overshoot, monotonic growth, base drift < 1 mm on a rotated part in
a rotated, offset container; glass keeps alpha 0.3 through both fades; opaque parts leave the
transparent pass; the live tweens end where scrubbing does. Run against the previous
`animation_applier.gd`, 10 of them fail — one per problem listed above.

---

## 3. Clash detection

Only `install` parts are ever movers (unchanged). Everything below is about which of their hits
count. Measured on the test model with its 17 `drop_in` activities turned into crane lifts, scan
step 0.5 days:

| | Before | After |
|---|---|---|
| Clash windows | 189 | 79 |
| Activity pairs | 39 | 16 |
| Full scan | 159 s | 2.4 s |
| Jolt "singular basis" warnings per run | tens of thousands | ~300 |
| Same model lowered 8 m | lifts started underground | identical result |

### Designed contact is not a clash — `CollisionQuery._build_designed_contacts()`

On the first query, every area is moved to its part's `original_transform` and each mover's hull
is queried there. Whatever it touches or overlaps **in the finished model** — a beam on its
column, a corbel set into its cornice, cornice ends on the roof timbers, the next segment along —
is recorded and never reported for that mover. A pair that overlaps in the finished model is a
question for a static clash check of the model, not a sequencing problem this tool can surface.
Built lazily because the physics space is not always queryable when the schedule is built.

### Contact tolerance — `CONTACT_TOLERANCE` (0.02 m)

The mover's convex hull is inset by 2 cm per axis (`_inset()`; never below 10 % of its size, so
a thin pane keeps a body). Grazing and coincident faces do not count.

### Not-yet-grown parts are absent — `_MIN_BASIS_DET`

A part at progress just above 0 — `scale_up` at 1 % size has a determinant of 1e-6 — has a
near-singular basis. Jolt replaces a singular basis with identity — i.e. checks the part at **full size** — and
logs a warning per part per query. Parts with |det| ≤ 1e-6 are now skipped as not there yet.

### Lifts start beside the piece — `ConstructionSchedule._cache_ground_start()`

`install_ground_start` was the crane pickup point in **world** space, assigned by
`_install_instant()` as a **local** position. Right only for a container at the world origin. In
any offset container — a georeferenced second model, a model set onto the terrain with *Asentar en
el suelo* — every lift started that offset away (metres underground, rising through the
building), and every child of a commander unit started stacked on one point. It is now the
part's rest position plus the pickup displacement brought into the parent's space, recomputed on
every schedule build (older scenes can carry a saved world-space value), first write per build
wins.

### Results are not truncated — `CollisionQuery._intersect()`

`intersect_shape()` was capped at the number of active parts; a dense neighbourhood could fill
the cap with irrelevant hits and drop the real one. It now retries with a larger cap whenever the
result comes back full. (Suspected while writing the test, when a previous test case's leftover
areas hid a genuine hit on the old code.)

### Scan only while something is lifting — `ConstructionSchedule.get_install_windows()`

`scan_collisions()` stepped every part through the whole schedule at 0.01-day resolution. A clash
needs a mover in transit, so it now samples only the merged windows in which some install part is
in progress.

### What remains on the test model is real

11 of the 16 remaining pairs involve `C23_Recercados` (window surrounds): a 97-day activity that
runs on after the quoins, cornices and roof above the openings are in place. A crane can't lower a
surround through a cornice that's already there. That is the kind of finding the check exists for.

### Tests

`tests/test_collisions.gd` (17 checks, plain boxes): a beam resting on its column, a beam modelled
40 cm into the column head and a beam alongside the segment it abuts are not clashes; a post in the
slide path is, only while the beam passes it, and the full scan finds exactly that window inside
the slide phase; a tiny `scale_up` part is ignored and the same part grown is not; the lift starts
15 m to the side at the piece's own height and lands exactly, in three container offsets. Against
the previous code, the embedded-beam case reports `BEAM|COL`.

---

## 4. Bottom-up placement — `SpatialGrouper.sort_by_position()`

Staggered parts (and formwork panels) used to be ordered by plan position only — z, then x —
ignoring height, so a first-floor surround could be placed before the ground-floor one under it,
and a quoin before the quoin it sits on. They are now ordered by **level first** (the world height
of each part's base at its finished placement, in 0.5 m bands, `LEVEL_BAND`), then by plan
position. Besides reading as construction, this halved the remaining clash windows on the test
model (148 → 79) and removed every same-activity self-clash but one.

---

## Files

| File | Change |
|---|---|
| `core/task_classifier.gd` | New: the classifier |
| `core/animation_applier.gd` | `build_up`; `drop_in`, `scale_up`, fades reworked; `_set_opacity()`; live = instant |
| `core/collision_query.gd` | Designed contact, tolerance, singular guard, uncapped results |
| `core/construction_schedule.gd` | Local-space lift start; `get_install_windows()` |
| `core/spatial_grouper.gd` | Bottom-up ordering |
| `runtime/timeline_controller.gd` | Scan only install windows |
| `ifc/ifc_mapping.gd`, `ifc/ifc_schedule_generator.gd` | `infer_types`; `_derive()` |
| `editor/ifc_mapping_dialog.gd` | Inference checkbox, clearer labels |
| `editor/timeline_dock.gd` / `.tscn` | Auto types button |
| `editor/schedule_inspector.gd` | `build_up` → "Levantar" |
| `tests/test_task_classifier.gd`, `test_animations.gd`, `test_collisions.gd` | New |
| `tests/test_ifc_mapping.gd` | Inference cases; two assertions changed by design |
