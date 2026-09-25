# 4D Construction Tool — Formwork (encofrado)

> **Status: build order steps 1–5 and 7 built; all three geometry tiers are real, formwork is
> authorable from the dock, and boards follow the mesh's own faces. Only step 6 (the generator
> rule) is open.**
> See the build order at the bottom for exactly what each covers. `README.md`'s "Formwork
> (encofrado)" section is the as-built description; this file keeps the reasoning and the
> decisions, the same way `06_PLANNED_FEATURES.md` does for the five features before it.
>
> Six design decisions were resolved on 2026-08-20 and five more on 2026-08-21; all are
> recorded at the bottom, along with the two still open.

## The want

Today a 5-day `fill_up` element is a **5-day concrete pour** — the mesh grows continuously
from its bottom face over the whole window, with the pour stream running the entire time.
That is not how the work happens. Those five days are four days of **building the forms**
and one day of **pouring into them**.

So: an action's window splits into a formwork phase followed by a pour phase, with the
formwork visible while the concrete is placed and gone afterwards.

**Hybrid geometry, as requested.** Where a project has real formwork geometry, or a real
formwork panel asset, use it. Where it doesn't — which is most models today — generate a generic wood-slab form around the element. See "Geometry resolution"
below.

---

## What this is not: a new animation type

The obvious-looking move is a `formwork_then_fill` entry in `AnimationApplier.TYPES`. It's
wrong, because formwork is **different geometry**, not a different motion. The concrete
part still does exactly `fill_up`; a set of *other* nodes appear before it and disappear
after it. `AnimationApplier` is a stateless library that moves one node given one progress
value — it has nowhere to put "and also these eight panels."

The right seam is one layer up. `ConstructionSchedule._part_schedules` is
`part_name → {start_day, end_day, anim_type}`, and nothing requires every part in an action
to share a window. Formwork panels are simply **more parts, with their own window and their
own anim_type**, derived from the same action. Once they exist as parts, everything
downstream — `get_part_states()`, `apply_instant()`, scrub/play parity, the collision
query, the dock preview, movie mode — works with no changes at all.

That is the whole architectural claim of this feature, and it's the reason it fits: it adds
parts and splits a window. It does not add a concept to the timeline engine.

---

## The phase split

An action's window `[S, S + D]` divides at `S + F`:

```
   S                                   S+F        S+D
   |------------- formwork -------------|-- pour --|
   |  panels appear one after another   |  fill_up |
```

| Part | Window | anim_type |
|---|---|---|
| Formwork panels | `[S, S+F]` | `scale_up` by default (see below) |
| The concrete part | `[S+F, S+D]` | the action's own `type`, unchanged |

**`F` is derived from the pour, not the other way round.** The schema field is
`pour_days` (default `1.0`), and `F = D − pour_days`. Specifying the *tail* rather than the
*head* is the more durable of the two: a pour is a fixed short operation whose length is a
property of the element, while the prep expands to fill whatever the programme allows. When
a revised schedule moves an element from 5 days to 8, `pour_days: 1` still describes the work
correctly and formwork absorbs the change; `formwork_days: 4` would silently leave a 4-day
pour.

`formwork_days` is accepted as an explicit alternative and **wins when both are present** —
the same precedence rule `duration_days` already has over `units_per_day`, and
`start_date` over `depends_on`. Consistency here is worth more than picking one.

**Degenerate windows.** If `D <= pour_days`, `F` is zero or negative: there is no room for
a formwork phase. The action then behaves **exactly as it does today** (no formwork parts,
one continuous pour across the full window) and warns once. A one-day element genuinely has
no visible formwork phase to show, and silently stealing half its window to invent one
would be worse than showing nothing. This affects short elements —
worth knowing before the first preview, because "some elements have no formwork" is going
to look like a bug otherwise.

**The pour particle stream follows the pour, not the action.**
`ConstructionSchedule._fill_up_units` currently records `{start_day: part_start_day,
duration: part_end_day - part_start_day}` — the action window. It must record the *pour*
window instead, or the stream fires four days early and runs five days long.
`TimelineController._detect_fill_up_actions()` needs no change; it reads whatever start day
the unit carries. This is a two-line change and the single easiest thing to get wrong.

**Cadence applies twice, independently.** The concrete keeps the action's own `batch` /
`stagger` / `dur_accel` fields across the pour window — a four-mesh element's meshes still rise
together as one pour, exactly as `06_PLANNED_FEATURES.md` feature 4 established. The
panels get their own cadence across the formwork window, **staggered by default even when
the action batches**, because panels genuinely do go up one after another. That inversion
is deliberate and needs to be explicit in the code, since inheriting `batch: true` from the
action (which is most pours) would make an entire form set pop into
existence in one frame and waste the four days it was given.

---

## Geometry resolution — the hybrid, in three tiers

Resolved per action, first match wins:

| Tier | Field | Meaning |
|---|---|---|
| 1 | `formwork.prefix` | Formwork already modelled in the scene. Parts matching this prefix *are* the formwork — nothing is generated |
| 2 | `formwork.model` | A `res://` path to a panel `.glb`/`.tscn`. One instance per computed panel placement (see below) |
| 3 | *(nothing)* | Generic wood slab: a box mesh per computed panel placement |

Tiers 2 and 3 differ **only** in what gets placed at each panel position — the placement
math is identical and shared. That keeps "I have a panel asset" one field away from the
default rather than a separate code path.

A project-level `"formwork_defaults"` block at the **root** of `construction_steps.json`
(sibling of `steps`, `static_prefixes`, `excluded_prefixes`) supplies defaults for every
action, so a `model` or a `pour_days` is written once rather than onto every action. A
per-action `formwork` block overrides it key by key. Root-level placement matches the
precedent set by the two geometry lists: this is a statement about the *project*, not about
one task.

### Computed panel placement (tiers 2 and 3)

Per part, from its `original_aabb` and `original_transform` — the same two metas every
`AnimationApplier` method already reads, so no new geometry bookkeeping:

- **Four vertical faces** (±X, ±Z of the local AABB), offset outward by the panel
  thickness. No bottom panel (the element sits on ground, a footing, or the previous
  lift) and no top panel (that's where the concrete goes in). For a slab this degenerates
  into a perimeter of edge boards, which is correct.
- **Each face subdivides into boards** of a target width (~2.5 m, clamped to a 1–8 board
  count per face) so a very large footing reads as a built-up form rather than one
  enormous panel, and so the four-day stagger has something to stagger. A very small element
  gets one board per face.
- **Thickness and material** are the generic "wood slab": a `BoxMesh` with a plain brown
  `StandardMaterial3D`. Every dimension scales off the element, for the same reason the
  pour stream does (`README.md`, "Concrete pour stream") — elements run from well under a metre
  to over twenty and one fixed size reads wrong at one end or the other.

**Formwork is generated per part, not per element.** A four-mesh element is four parts; each gets its
own form set around its own AABB. A union AABB across the four would be wrong for exactly
the reason `06_PLANNED_FEATURES.md` measured — a three-segment girder can span
~19 m, and a single box around all three would enclose mostly air.

**For a `commander_prefix` action, only commanders get formwork**, not their grouped
children — the commander is the concrete; the children are rebar cages and similar, already
inside it. This matches `unit_count`'s existing definition for `units_per_day`.

### The bounding box was the wrong surface (build order step 7)

Steps 2–4 placed boards on the four vertical faces of each part's **local AABB**. On
real models that is visibly wrong, and the reason is measurable: the elements are not boxes.

Measured on a real model, elements filled as little as **4 %** of their local bounding box
(others 11 % and 22 %) and carried 6–15 distinct vertical face normals.

A box around geometry that fills 4 % of it puts every board metres away from the concrete it
is supposed to be holding, which is exactly what the screenshot showed: a wide flat brown
frame sitting well outside the element. Height was never the problem — panel heights match
element heights exactly, and the parts' basis scale is (1, 1, 1).
It is horizontal placement, and only horizontal placement.

**So the boards come off the mesh's own vertical faces instead.** Per part, in world space:

1. Every triangle whose normal is within ~14° of vertical is a candidate face.
2. Candidates cluster by **normal direction** (within a merge angle) **and** plane offset —
   both conditions, because two parallel faces metres apart (a U-shaped wing wall) must not
   merge into one board bridging the gap between them, while consecutive facets around a
   curve must.
3. A cluster whose average normal points *inward* relative to the part's centre is dropped.
   That is what keeps interior surfaces — a hollow box girder's inner walls — from getting
   forms on the wrong side of the concrete.
4. Each surviving cluster is projected onto its own area-weighted average plane, giving a
   rectangle in (horizontal tangent, up). That rectangle subdivides into boards of
   `board_width` exactly as before, so step 2's subdivision, stagger and cadence are
   unchanged — only *where the rectangle is* changed.

**Merged by angle, then capped by area** *(resolved 2026-08-21, decision 11)*. Clustering
strictly by plane gives 76 patches on a rounded pier and 61 on a curved deck edge — real formwork is built from flat panels, but not 76 of them on one pier. Normals
within `MERGE_ANGLE` collapse into one board spanning them, and the largest clusters by area
survive up to a per-part cap. The two alternatives were one board per patch (most literally
"exactly as they are", but the panel count rises sharply on curved parts) and capping without
merging (a chamfered pier would lose its corner facets outright, leaving visible gaps between
four boards rather than a closed form).

**The AABB path stays as the fallback**, for a part whose mesh yields no usable vertical face
at all. It is the old behaviour, reached only where the new one has nothing to say, so a
degenerate part still gets forms rather than silently getting none.

A cluster's plane also gives each board an **orientation**, which the AABB path never needed:
boards are now placed with a full `Basis(tangent, up, normal)` rather than axis-aligned. That
simplifies tier 2 as a side effect — a model asset's thin axis always maps to the board's
local Z, so the "which way did you model it?" correction becomes one fixed rotation instead
of a comparison against the slot.

### Tier 1 — `formwork.prefix`: the scene's own geometry (build order step 4)

Nothing is generated. `ConstructionSchedule` resolves the prefix against `building_parts`
with the same `begins_with()` it uses everywhere else, and hands the matches to the *same*
`_schedule_formwork()` that generated panels go through — same cadence, same stagger-even-
when-batching inversion, same `formwork` anim_type, same phase meta, same strip. The only
difference between a tier-1 form and a tier-3 board, once scheduled, is where the geometry
came from. `FormworkBuilder` stops warning and simply returns 0 for these actions.

**Tier-1 parts must be excluded from work matching, and the existing guard does not reach
them.** The `formwork_of` meta is the guard generated panels use, and it cannot be reused
here: `FormworkBuilder.sweep()` deletes everything carrying it, so stamping it on
scene-resident geometry would make Start Preview **delete the user's model**. And decision 3
skips collision setup for anything carrying it, whereas tier-1 formwork is an ordinary scene
part that stays clash-checked. So tier 1 gets its own index — a project-wide set of
prefix-resolved formwork part names, built **before** the action loop, so that action B's
`target_prefix` cannot eat action A's scene formwork any more than its own.

**That exclusion has to cover `commander_prefix` too, which today it does not.**
`ConstructionSchedule`'s `formwork_of` guard sits only in the `target_prefix` branch;
`SpatialGrouper._compute()` does its own bare `begins_with()` over the whole of
`building_parts`, so a commander action can already sweep generated panels into its groups
and pour them. It has not been seen in practice, but
tier 1 makes it likely rather than theoretical (`commander_prefix: "A1"` with scene forms
named `A1_FORM…` is the obvious way to author this). Fixed by handing `get_groups()` a
`building_parts` filtered of all formwork, generated and tier-1 alike. Note
`SpatialGrouper`'s cache is keyed on the prefixes only, not on the dictionary, so the
filtered copy must be built once and passed consistently.

**A tier-1 action with no room for a formwork phase still schedules its forms**, with a
zero-length assemble at the action's start, holding through the pour and stripping normally.
This is the one place tiers 1 and 2/3 legitimately diverge, and the asymmetry is forced:
geometry that was never generated is simply absent, but geometry that is *already in the
scene* and excluded from work matching would otherwise be left with no window at all —
which means hidden and zero-scaled for the entire run, invisible forever. `_formwork_instant()`
already handles `assemble_end == 0` (the assemble branch is guarded on `assemble_end > 0.0`
and falls through to hold), so this costs nothing.

**A prefix that matches nothing warns and leaves the phase empty**, but does *not* undo the
window split — the author asked for a four-day formwork phase and a one-day pour, and
silently re-lengthening the pour would hide the typo rather than surface it.

Tier-1 parts are **not** rolled up through `_part_to_commander`. They are real scene parts
that are collision-registered today and stay that way; giving them a commander would change
how a clash involving them is reported, for geometry whose behaviour this step is otherwise
not touching.

### Tier 2 — `formwork.model`: an asset at each computed placement (build order step 4)

Step 2's `_panel_specs()` is untouched. `_build_for_part()` places an instance of the model
instead of a `BoxMesh`, and everything downstream — the `ENC_<part>_<id>` name, the
`formwork_of` meta, the `generated_formwork` group, never setting `owner`, the sweep, the
schedule guard, the collision skip, `stop_preview()` — applies unchanged, because a tier-2
panel is the same kind of node with different contents.

**The model is fitted to the computed board, not placed at its natural size.** Each spec is
a box of `(t_x, h, w)`; the instance is scaled so its own AABB fills that box and translated
so its AABB centre lands on `spec.center`. This is the same argument the generic slab and
the pour stream already make: elements run from well under a metre to over twenty, and one fixed size reads
wrong at one end or the other. Board *width* is already adaptive — set `board_width` to the
asset's real width and the horizontal scale stays near 1; height is the element's and has to
scale regardless.

**The asset is rotated 90° about Y when its thin axis doesn't match the slot's.** The four
faces are thin in X (±X faces) or thin in Z (±Z faces). A panel modelled thin-in-Z dropped
into an X slot and scaled per-axis to fit would be squashed to 5 cm across its face and
stretched to the element's depth in its thickness — unrecognisable. Comparing the asset
AABB's two horizontal extents and rotating when they disagree costs one branch and removes
"which way did you model it?" as a thing the author has to know.

**Loaded and measured once per path, not per placement.** A project-wide cache keyed on the
`res://` path, since `formwork_defaults.model` means every action typically shares one asset.
The AABB is measured once from a probe instance (union of descendant `MeshInstance3D` AABBs
in the root's local space, the same walk `SequenceManager._get_local_aabb()` already does).

**Every failure falls back to the generic slab, warning once per action** — a missing path,
a resource that isn't a `PackedScene`, a root that isn't a `Node3D`, a model with a
degenerate AABB. Falling back to tier 3 rather than to nothing is deliberate: a mistyped
path should cost the *look* of the forms, not their existence, and an empty formwork phase
is much harder to read as a typo than brown boxes where panels were expected.

**Composite model roots fade by recursion — resolved 2026-08-21 (decision 7).** A `.glb`
root is a `Node3D` with `MeshInstance3D` children, not a `MeshInstance3D` itself.
`_fade_out_instant()` (the default `strip_type`) returned early on anything that wasn't a
`MeshInstance3D`, and `SequenceManager.make_materials_unique()` did the same — so a tier-2
panel would have *popped* out of existence instead of fading, and every placement would have
shared one material instance. Both now walk descendant `MeshInstance3D`s when the part
itself isn't one.

This is purely additive: composite parts got *no* fade at all before, so recursion can only
improve them, and the material-sharing fix is a latent bug closed rather than a behaviour
traded. The two alternatives were documenting the limitation and telling authors to pick a
transform-based `strip_type` (leaves the *default* visibly wrong for tier 2), and flattening
single-mesh models into a plain `MeshInstance3D` (the common case then matches tier 3
exactly, but behaviour would depend on how the asset happened to be authored, and it buys
two code paths inside `FormworkBuilder`).

---

## Stripping

**Formwork must disappear, or the finished bridge is wrapped in plywood.** This wasn't in
the request but falls straight out of it: there is no version of this feature where the
forms stay.

Proposal: one lifecycle per panel, `assemble → hold → strip`, with

| Field | Default | Effect |
|---|---|---|
| `formwork.strip_days` | `0.0` | Days after the pour finishes before the forms come off (cure time) |
| `formwork.strip_type` | `fade_out` | How they come off |

**Mapping a three-phase lifecycle onto one part.** `_part_schedules` holds one window per
part, so "appear, hold, disappear" doesn't fit as three entries. Rather than making
`_part_schedules` multi-phase — which would touch `get_part_states()`, the single source of
truth both scrubbing and Play route through, and is the most load-bearing function in the
project — a **new `formwork` anim_type** maps the whole lifecycle into one 0–1 progress
window, with the phase boundaries stored as a part meta at schedule time:

```gdscript
part.set_meta("formwork_phases", {"assemble_end": 0.31, "strip_start": 0.94})
```

This is precedented twice over: `_install_instant()` already maps three phases
(lift/slide/lower) into one progress value, and `install_ground_start` is already a
schedule-time meta that `apply_instant()` reads. It costs one entry in
`AnimationApplier.TYPES`, one `_formwork_instant()`, and zero changes to the core query.

The alternative — an Array of phases per part in `_part_schedules` — is more general and
would serve future needs, but it modifies `get_part_states()` for one feature that doesn't
need the generality. Flagged, not chosen. **Open decision below.**

**Stripping extends `_max_day` past the action's finish** when `strip_days > 0`. It must
*not* extend `_action_finish_days`, which is what `depends_on` resolves against — a
dependent action starting while its predecessor's forms are still standing is realistic,
and quietly moving every downstream date because of a cure period would be a much bigger
change than this feature is asking for. `_update_bounds()` and `_action_finish_days` are
already separate; this just means being careful to feed only the former.

---

## Idempotency — the trap this feature walks straight into

Generated geometry lands in the parts container, so a generator that simply appends on every
call duplicates everything the second time it runs. Formwork cannot accept that, because **the dock preview is the authoring flow**.
Start Preview calls `initialize_parts()` on every press, so generation runs repeatedly by
design. Generated panels must therefore be:

- **tagged** — a `formwork_of` meta naming the part they wrap, and membership of a
  `"generated_formwork"` group;
- **swept before regenerating** — delete everything in that group first, so a second run
  produces the same scene as the first;
- **generated before `initialize_parts()`**, so they're registered as parts normally and
  hidden/zero-scaled with everything else.

`initialize_parts()` was already made idempotent for feature 2 (`README.md`, "Static and
excluded geometry"); this is the same discipline applied to the generator that feeds it.

A shared `FormworkBuilder` (`core/formwork_builder.gd`, `RefCounted`) owns this, called
by both `SequenceManager._ready()` and the dock's `start_preview()` — composition, matching
how `ConstructionSchedule` owns `CollisionQuery` and `TimelineDock` owns `ScheduleInspector`.

### Prefix matching would otherwise eat the panels

Schedule matching is `begins_with()`. A panel named `A1_FORM_X0` **starts with `A1`**, so
the action's own `target_prefix: "A1"` would match it as if it were concrete, schedule it
as a pour, and produce a form set that fills up like a wall.

Naming panels `FORM_A1_X0` avoids the collision by accident, which isn't good enough. The
fix is structural: `ConstructionSchedule`'s `target_prefix` loop **skips any part carrying a
`formwork_of` meta**. One condition, and it can't be defeated by a naming choice later. The
`FORM_`-first naming is still worth having for legibility in the inspector and warnings.

---

## Authoring surface — the inspector columns (build order step 5)

Before this existed, turning formwork on meant hand-editing `construction_steps.json`, which
is also the one edit `Generate 4D Schedule` destroys (step 6). Two columns, as sketched in the
interactions table below: **Encofrado** (dropdown) and **Días vertido** (SpinBox).

**The dropdown reports the *resolved* tier, not the action's own block.** With a root
`formwork_defaults` present, an action carrying no `formwork` key still has formwork, and a
row showing "No" there would be a lie. It reads `resolve_formwork_config()` — the same
function the schedule itself calls — so what a row displays and what the animation does
cannot drift apart. This is the same reason the Depends On row shows its *resolved* dates
rather than doing local arithmetic.

| Item | What selecting it writes |
|---|---|
| **No** | `"formwork": false` when a root `formwork_defaults` exists — an explicit opt-out is the only way to say no to a project default. Otherwise erases the `formwork` key entirely, leaving the action byte-identical to a pre-formwork one |
| **Genérico** | a `formwork` block with no `prefix`/`model` — tier 3 |
| **Modelo** | keeps the action's existing `model` — tier 2 |
| **Prefijo** | keeps the action's existing `prefix` — tier 1 |

**Modelo and Prefijo appear but are only selectable when the action already carries that
field** *(resolved 2026-08-21, decision 8)*. Geometry links stay JSON-only, the rule
`commander_prefix`/`child_prefixes` already follow and the one the interactions table already
recorded for `formwork.model`. A disabled item with a tooltip naming the JSON field is better
than either of the alternatives: hiding the tier entirely would make a JSON-authored `model`
row misreport as *Genérico*, and adding a free-text path column would widen a grid that is
already thirteen columns and put a `res://` path next to a set of numeric spinners.

**Selecting Genérico on a row that has a `model` or `prefix` clears it** — otherwise the
resolved tier would not change and the dropdown would snap straight back, which is the same
"a row must not show something the schedule disagrees with" rule as above. When the geometry
field came from the *root* `formwork_defaults` rather than the action, the action gets an
explicit `""` override instead, since erasing a key it never had cannot shadow a default.

### The project-wide toggle *(resolved 2026-08-21, decision 9)*

A checkbox and a pour-length spinner above the inspector, writing and erasing the root
`formwork_defaults` block. Without it "turn formwork on" is dozens of dropdown clicks on
a real model, which is the thing the whole column exists to avoid; with it, per-row edits
become the exceptions they should be ("everything has forms, except this one"). It is also
the honest place for a project-wide statement, matching where `static_prefixes` and
`excluded_prefixes` already live.

Both surfaces write the same schema, so neither is authoritative over the other — the row
dropdown resolves through `resolve_formwork_config()` exactly as the schedule does, so a row
re-reads whatever the toggle just changed rather than caching an answer.

**Días vertido** is `pour_days`. Zero means unset — it erases the key so `DEFAULT_POUR_DAYS`
applies — matching the "0 = unset" convention `stagger`, `lag_days` and `duration_days`
already use in this same grid. Disabled when Encofrado is *No*.

**A row with no room is flagged in the grid, not just in the console.** When
`duration_days <= pour_days` the action falls back to one continuous pour and generates
nothing, which is exactly the "some elements just don't have formwork" confusion this spec
predicted for one-day actions. Marked with the ⚠ + amber + tooltip
treatment `_add_action_row()` already uses for a prefix that matches no geometry — that
marker exists precisely because a row that silently does nothing looks identical to one that
works.

**Grid width goes 13 → 15**, in `timeline_dock.tscn`'s `columns` and `_HEADER_LABELS`, along
with the four doc references that quote the old number.

**Everything else stays JSON-only** — `strip_days`, `strip_type`, `type`, `batch`,
`board_width`, `thickness`. Decision 5 already established that panels are generated geometry
rather than work; this is the same argument applied to their tuning.

### CSV is completeness here, not a hazard

`formwork_mode` / `pour_days` / `strip_days` columns, per the interactions table. Worth being
precise about the risk, because the obvious fear is wrong: `_apply_csv_row()` only touches
keys whose columns are present in the header (`_COLUMN_ABSENT` vs `""`), so a CSV exported
before these columns existed already leaves an action's `formwork` block untouched on
re-import. Nothing is destroyed by deferring this; it just means the CSV isn't a complete
view of what the inspector edits.

---

## Interactions with what already exists

| Subsystem | Effect |
|---|---|
| **Scrub/Play parity** | None needed. Both route through `get_part_states()` → `apply_instant()`; formwork is just more parts in the same dictionary. Verify anyway — a form set that assembles during Play and pops during scrub would be exactly the class of bug `batch` was checked for |
| **Collision detection** | Movers are only `anim_type == "install"` with `progress < 1` (`collision_query.gd:163`), and formwork is never `install`, so panels never *cause* a query. As targets they would be checked — see the open decision on registering them at all |
| **`static_prefixes` / `excluded_prefixes`** | Unaffected. Generated panels carry a meta, not a prefix membership; a project that deliberately excludes a formwork prefix (tier 1) keeps working |
| **Movie mode** | Nothing special. `CameraDriver` and the date label read `current_day`, which is untouched |
| **Pour stream** | Follows the pour window (above). The stream now runs 1 day instead of 5, which is both correct and cheaper |
| **`ScheduleInspector`** | +2 columns: *Encofrado* (dropdown: No / Genérico / Modelo / Prefijo) and *Días vertido* (SpinBox). Spanish display labels with English keys as metadata, matching `_TYPE_DISPLAY_NAMES` / `_HEADER_LABELS` |
| **CSV I/O** | Add `formwork_mode` / `pour_days` / `strip_days` columns — the CSV is scoped to "what the inspector edits," so it follows automatically. `formwork.model` stays JSON-only, like the other geometry fields |
| **Project XML I/O** | **Unchanged.** A formwork phase is a sub-phase of one action, and the anchor/terminal phase-group mechanism already exists for the genuinely-two-task case. Exporting one action as two tasks would break the id-matched round-trip for no gain |
| **`IFCScheduleGenerator`** | See below |

### Performance, honestly

Generated formwork multiplies the part count. A 65-part model with 24 actions ×
~4–12 panels each lands near **200–350**. That is still inside the "< 500 parts" envelope
`00_4D_TOOL_OVERVIEW.md` set, and `get_part_states()` / `scrub_to()` are both O(parts) and
cheap. The real cost is `CollisionQuery.setup()`, which builds a convex hull **and** a
trimesh per `MeshInstance3D` from scratch with no caching — this is already the reason the
Recalculate button exists. A 3–5× part count means every schedule rebuild in the dock gets
3–5× slower unless generated formwork is skipped there. Hence the open decision below.

### `IFCScheduleGenerator`

The model carries no formwork metadata — nothing in property sets
describes forms. So the generator can only apply a **rule**, the same way `_batch_for()`
applies one: emit `"formwork": {"pour_days": 1}` on every action whose type is `fill_up`,
and nothing on the others.

**In an all-cast-in-situ model that is every action**: every element is a pour and every element gets forms.

Written **explicitly onto every action**, not left to a global default, for exactly the
reason `batch` is: an explicit field is visible in the JSON, one toggle away in the
inspector, and the fix survives. And, like both geometry lists, any hand-edited `formwork`
block must be **carried forward by `read_existing()`** across a regeneration.

That carry-forward is not a nicety: without it, a correction made in the inspector's *Tipo*
dropdown is destroyed by the next re-import with no warning (the generator now carries a
hand-edited `type`/`batch` forward; `formwork` blocks are not yet). A `formwork` block that isn't carried forward inherits the
same failure, and it would be harder to notice: a missing form set reads as "that element
just doesn't have formwork yet," not as data loss.

Note what this does to the video: it converts **every action in the model** from "long
pour" to "form, then pour." That is the intended outcome, and it is also a large, sudden
change to what a recording looks like — worth seeing on two or three elements in the dock
before turning it on across the model.

---

## Schema

```jsonc
// root of construction_steps.json — optional, applies to every action
"formwork_defaults": {
  "model": "res://Modelos/Encofrado_panel.glb",  // optional, tier 2
  "pour_days": 1.0,
  "strip_days": 0.0
},

// per action, inside "steps"
{
  "type": "fill_up",
  "target_prefix": "A1",
  "start_date": "2026-06-01",
  "duration_days": 5,

  "formwork": {
    // -- geometry, first match wins --
    "prefix": "A1_FORM",          // tier 1: already in the scene
    "model": "res://…/panel.glb",  // tier 2: instanced at computed placements
                                   // tier 3 (generic wood slab) if neither

    // -- timing --
    "pour_days": 1.0,              // default 1.0; formwork gets duration_days − this
    "formwork_days": 4.0,          // explicit alternative; wins if both present
    "strip_days": 0.0,             // cure days after the pour before forms come off

    // -- appearance --
    "type": "scale_up",            // how panels appear (any AnimationApplier.TYPES)
    "strip_type": "fade_out",      // how they come off
    "batch": false,                // panels stagger even when the action batches
    "board_width": 2.5,            // target board width before subdividing a face
    "thickness": 0.05
  }
}
```

Every field optional. An action with no `formwork` block and a root with no
`formwork_defaults` behaves **byte-identically to today** — the same backwards-compatibility
bar `start_date`, `depends_on`, `batch` and the two geometry lists all cleared.

---

## Decisions — resolved 2026-08-20

1. **Strip behaviour: forms come off at the end of the pour.** `strip_days: 0` and
   `strip_type: fade_out` are the defaults. A real cure period is available per action via
   `strip_days` but is deliberately not the default, because a cure that outlives the next
   action's start reads as a scheduling bug to anyone watching. Forms persisting to the end
   of the run was rejected outright — it wraps the finished model in plywood.

2. **Lifecycle mapping: new `formwork` anim_type + phase meta.** As specified above. It
   follows `_install_instant()`'s existing three-phase precedent and leaves
   `get_part_states()` — the single source of truth both scrubbing and Play route through —
   completely untouched. Multi-phase `_part_schedules` is the more general answer and is the
   right call the moment anything *else* wants it; nothing does yet, so the generality isn't
   bought.

3. **Generated panels are not collision-registered.** `CollisionQuery.setup()` skips any
   part carrying a `formwork_of` meta. It's a 3–5× cost on every schedule rebuild — the
   exact cost the Recalculate button exists to avoid — in exchange for clash detection
   against temporary scaffolding, and on an all-cast-in-situ model the value is zero, since
   there are no `install` actions and therefore nothing is ever a mover. Tier-1
   scene-resident formwork is an ordinary part and stays collision-checked as it is today.
   Reversing this is one line plus adding panels to their element's `_sibling_groups`, so
   they don't flag against the concrete they're holding.

4. **Generator applies formwork to `fill_up` only** — 

5. **Panels never become inspector rows.** They're generated geometry, not work — exactly
   the argument `06_PLANNED_FEATURES.md` feature 2 made for keeping `static_prefixes` out
   of `"steps"`. The formwork phase is visible as two columns on its parent action's row.

6. **Faces subdivide into boards.** One panel per face on a very large footing is a single
   enormous slab appearing in one motion, and gives a four-day stagger only four things to
   stagger.

### Decision — resolved 2026-08-21

7. **Composite parts fade by recursion.** `_fade_in/out_instant()` and
   `SequenceManager.make_materials_unique()` now walk descendant `MeshInstance3D`s when the
   part itself isn't one. Forced by tier 2: a `.glb` panel root is a `Node3D`, so with the
   old early-return a model panel would have popped out of existence on the *default*
   `strip_type` and every placement would have shared one material. Purely additive —
   composite parts got no fade at all before — and it closes the material-sharing bug in
   passing. The dock's `_snapshot_materials()` walks the same set, or the preview would
   leave its duplicates behind in the edited scene. Rejected: documenting the limitation
   and telling authors to pick a transform-based `strip_type` (leaves the default visibly
   wrong), and flattening single-mesh models into a plain `MeshInstance3D` (behaviour would
   depend on how the asset happened to be authored, and it buys a second code path).

### Decision — resolved 2026-08-21

10. **An explicit but empty `formwork` block turns formwork ON.** `{}` is this file's sentinel
    for "no formwork", which collided with an action that opted in explicitly and supplied no
    fields: `"formwork": {}` and `"formwork": true` both merged to `{}` when there was no root
    `formwork_defaults` to inherit, and so behaved exactly like having no key at all —
    silently, and contrary to what `README.md` documented as *the* way to turn the feature on
    for one action. Found by building the inspector dropdown, whose *Genérico* item writes
    precisely that block. Resolved in `resolve_formwork_config()` by materialising the
    documented default (`pour_days: 1.0`) rather than by introducing a second sentinel: every
    consumer already reads `{}` as off, and a config carrying the pour length it would have
    defaulted to anyway is both correct and what an author would have written by hand.

### Still open

- **Board width and thickness defaults** (~2.5 m / 0.05 m proposed). Best settled by
  looking at a generated form set on a pier and on the abutment footing rather than by
  argument — elements can differ in size by two orders of magnitude.
- **What the generic wood slab looks like** — plain brown `StandardMaterial3D` is the
  placeholder. A plank texture would read better on the close-up shots the camera track
  exists for, but that's a materials question, not a scheduling one, and it can follow.

---

## Acceptance criteria

- A 5-day `fill_up` element shows four days of forms assembling, then a one-day pour inside
  them, then the forms come off — scrubbing and playing identically.
- The pour particle stream starts on the pour day and lasts the pour's length, not the
  action's.
- An action with `formwork.prefix` uses the scene's own geometry and generates nothing.
- An action with `formwork.model` places that asset at every computed panel position.
- An action with neither generates the generic wood slab.
- An action with no `formwork` block is visually identical to today.
- A `duration_days <= pour_days` action falls back to today's behaviour with one warning.
- **Start Preview pressed twice produces the same scene as pressing it once** (the idempotency
  trap).
- Re-running Generate 4D Schedule preserves hand-edited `formwork` blocks.
- `construction_steps.json` with no formwork anywhere loads and animates exactly as before.

## Build order

1. ~~**Schema + phase split, no geometry**~~ — **✅ BUILT 2026-08-20.** `pour_days` /
   `formwork_days` split the window, the action's own animation gets the pour window, and
   `_fill_up_units` follows it automatically (it was already derived from the per-part
   window, so no separate change was needed). `resolve_formwork_config()` merges the root
   `formwork_defaults` with an action's own block; `_resolve_formwork_split()` returns
   `{formwork_days, pour_days}`. Both degenerate cases warn. Verified headless — see
   the headless formwork test.
2. ~~**`FormworkBuilder` + generic wood slab**~~ — **✅ BUILT 2026-08-21.**
   `core/formwork_builder.gd` generates four subdivided faces per element,
   sweep-then-rebuild so it is idempotent, panels tagged `formwork_of` and never `owner`ed
   so they can't reach the `.tscn`. `ConstructionSchedule` schedules them across the
   formwork window (staggered even when the action batches) and its `target_prefix` loop
   skips them; `CollisionQuery.setup()` skips them too. Wired into `SequenceManager._ready()`
   and into the dock's Start Preview *and* Recalculate. **Panels do not come off yet — that
   is step 3**, so the finished model is currently wrapped.
3. ~~**The `formwork` anim_type**~~ — **✅ BUILT 2026-08-21.** `_formwork_instant()` maps
   assemble → hold → strip onto one 0–1 window, reading per-panel boundaries from a
   `formwork_phases` meta and **composing** existing animations (`formwork.type` /
   `formwork.strip_type`) rather than reimplementing them. `get_part_states()` untouched, as
   decision 2 required. `formwork` is deliberately kept **out of `AnimationApplier.TYPES`**
   so it can never be picked for an element from the dock's dropdown. `strip: false`
   supports lost formwork (*encofrado perdido*). Steps 1–3 together are the feature; it is
   now usable end to end.
4. ~~**Tiers 1 and 2**~~ — **✅ BUILT 2026-08-21.** `formwork.prefix` resolves against the
   scene and schedules those parts through the same `_schedule_formwork()` generated panels
   use; `formwork.model` instantiates an asset at every placement `_panel_specs()` already
   computed, fitted to the board and rotated when the asset's thin axis disagrees with the
   slot's. Both share step 2's placement math exactly, as specified. The "prefix matching
   can never eat the forms" guard was extended to a project-wide index resolved before any
   action is scheduled, and to the `commander_prefix` branch, which `SpatialGrouper` had
   been bypassing all along. Decision 7 made composite parts fade.
5. ~~**Inspector columns + CSV**~~ — **✅ BUILT 2026-08-21.** *Encofrado* and *Días vertido*
   columns (grid 13 → 15), a project-wide **Encofrado en todo el proyecto** checkbox writing
   the root `formwork_defaults`, and `formwork_mode`/`pour_days`/`strip_days` CSV columns.
   Both surfaces resolve through `resolve_formwork_config()`, so a row can never display a
   tier the schedule disagrees with. Uncovered and fixed a real bug: `"formwork": {}` and
   `"formwork": true` resolved identically to having no formwork key at all — see decision 10.
6. **Generator rule + carry-forward**, last — it's the step that changes every action at
   once, and everything before it should be provable on two or three by hand.

7. ~~**Face-accurate placement**~~ — **✅ BUILT 2026-08-21.** Boards come off each part's own
   vertical mesh faces instead of its bounding box. Not in the original build order: it was
   found by looking at a screenshot, and measured afterwards — these elements fill as little
   as 4 % of their AABB, so box-face boards sat a mean of 5.0 m from the concrete. Face-derived
   boards sit a mean of 0.10 m from it. See "The bounding box was the wrong surface" above.

Steps 1–3 are the feature; 4–6 are what make it usable across the model; 7 is what makes it
correct on geometry that isn't box-shaped.
