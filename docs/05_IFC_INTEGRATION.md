# IFC Integration

Drive the 4D timeline from an IFC model instead of hand-authoring `construction_steps.json`.

IFC files have no standard place for a construction schedule, so every company stores it
differently: different property sets, different property names, different languages, different
date conventions. **This plugin therefore knows no property names.** You look at the properties
*your* model carries and choose which one means what.

## Requirements

- The **GDIFC** addon (a third-party GDExtension that reads IFC into Godot nodes), installed and
  enabled. It is *not* bundled here. Everything else in this plugin works without it.
- Property values that carry dates must be **ISO** (`YYYY-MM-DD`, an optional time part is ignored).
  Other formats are rejected because day/month order is ambiguous.

## Workflow (editor dock)

1. Open the scene that will hold the model and make sure it contains a `SequenceManager` node.
2. **Load IFC (4D)** and pick the file.
3. The tool reads the model and **scans every property its parts carry**. The mapping dialog opens.
4. Choose, per role (see below). Each entry shows the property path, how many parts carry it, and
   sample values.
5. Confirm. The parts are imported into an `IFCParts_<file>` node under `SequenceManager`, and
   `parts_container_path` is pointed at it. Save the scene to keep them.
6. **Generate 4D Schedule** writes `construction_steps.json` from your mapping.
7. Start Preview and scrub.

**Edit IFC mapping** reopens the dialog later. Because parts were already named from the Element ID,
that one role is locked; re-import the model to change it.

### Several models in one scene

A project often comes as several files (the two carriageways of a bridge, structure and
earthworks). Load each one with **Load IFC (4D)** into the same scene (`IfcSceneModels`):

- The first model is the **primary**: `parts_container_path` points at it and its origin becomes
  `SequenceManager.geo_origin`.
- Each later model gets its own `IFCParts_<file>` container, appended to `extra_part_containers`,
  and is **placed by its georeference relative to the first**: the container's transform is the
  offset (and any rotation/scale difference) between the two files' map positions. The scene's
  origin is kept, and so is the terrain when it already covers the new model.
- Loading a file again (same file name) **replaces** that model's container in place.
- A model with no georeference, or on another UTM zone, cannot be placed: it goes at the first
  model's origin and the Output says so; move it by hand.
- Part names must be unique across models (the timeline registers parts by name). A name another
  model already uses gets a suffix (`_2`, `_3`…), with a warning.
- **Generate 4D Schedule**, the position check and the preview see every model.

Every model keeps small coordinates of its own (each is still centred on load), so nothing reaches
float32 at map magnitude.

## The mapping roles

| Role | Required | Meaning |
|---|---|---|
| Element ID | yes | Each part is named after this value, and it becomes the action's `id` and `target_prefix`. Parts sharing a value form **one action**. |
| Start date | yes | The action's `start_date`. |
| End date **or** Duration (days) | one of them | Window end, or its length (a duration counts calendar days, inclusive of the start). |
| Display name | no | Written into the action's `comment`. |
| Decide type from | no | The property the type rules below are matched against. |
| Default type | — | Animation type for an action no rule matches (`scale_up` unless you change it). |
| Type rules | no | Ordered "value contains *text* → *type*"; the first match wins, case-insensitive. |
| Ignore dates equal to | no | Placeholder dates a model uses for "not scheduled". Empty unless you add some. |

Properties are addressed by their **exact path** (`property set / property`), never by suffix, so
two property sets that share a property name cannot be confused.

The choice is saved next to your schedule as `<schedule name>.ifc_profile.json` and reused
silently on later imports, as long as every property it refers to still exists in the model.
Otherwise the dialog reopens.

## What the import does to the geometry

GDIFC leaves every part's placement baked into its vertex data with its node at the origin, which
breaks the scaling and positioning the timeline relies on. `GDIFC4DAdapter` therefore:

- moves each part's placement out of the mesh and into the node's own transform, without changing
  where anything renders;
- flattens GDIFC's nested tree into one container of named `MeshInstance3D` parts;
- names parts from the Element ID; a part with no value keeps a name built from its structural
  zone (`<zone>_<original name>`), so it still renders and collides but cannot be scheduled;
- removes GDIFC's own collision helper nodes (the tool builds its own collision shapes).

**Accented text.** GDIFC turns IFC strings into UTF-8 bytes and then reads them back as Latin-1.
So a correctly encoded `Formig\X2\00F3\X0\n` arrives as `FormigÃ³n`, in the mapping dialog, the
schedule comments and every saved scene. The dock runs `GDIFC4DAdapter.repair_text()` on the
freshly read model before anything scans its properties. It decodes a string again only when it
is made entirely of U+0000..U+00FF characters whose bytes form valid UTF-8 containing a
multi-byte sequence: exactly this fault. Correct text and genuine Latin-1 are left alone. It
prints how many parts it repaired. The real fix belongs in GDIFC; the repair becomes a no-op
once GDIFC decodes correctly.

`GDIFCRecenter` first strips a very large offset in the root placement from a copy of the file,
because GDIFC stores coordinates at float32 precision and models placed at survey coordinates
jitter and z-fight otherwise (files with CRLF line endings included). An offset held in
`IfcMapConversion` is only read, not stripped: GDIFC ignores the map conversion, so such a file
loads as-is with no copy. What is found is recorded, together with the framing shift the import applies, as
`SequenceManager.geo_origin` — the model's position on the map, used by the terrain and the sun
(`10_TERRAIN.md`).

GDIFC's axes (verified on Godot 4.6.2): IFC (x = east, y = north, z = up) arrives as Godot
(x, z, -y), i.e. east = +X, up = +Y, north = -Z. GDIFC ignores `IfcMapConversion`, and its
`coordinate_to_origin` setting had no effect in the build tested; the dock sets it off regardless.

## What Generate 4D Schedule produces

- **One action per distinct Element ID**, sorted by start date, `target_prefix` = the id.
- If parts sharing an id have different dates, the action spans the **widest window**.
- `duration_days` is an inclusive calendar-day span.
- **Parts with no Element ID or no usable date** become `static_prefixes` entries: they render
  from the first frame and never animate. Without this they would stay hidden for the whole run.
  The prefix is the part's actual name stem. For a part with an id but no dates (existing ground,
  say) that is the **id**. For a part with no id it is its **structural zone** (`<zone>_`), since
  the adapter names those `<zone>_<original name>`. Previously every such part got its zone,
  which matched nothing for a part that had an id: that part stayed hidden all run.
- `batch` is written explicitly: `true` for every type except `install` and `drop_in` (discrete
  units placed one after another). One id covering several meshes normally means one operation
  split for modelling convenience.
- `excluded_prefixes` and `static_prefixes` you added by hand are **carried forward** across
  regeneration.

### Your corrections survive regeneration

An action's `type` and `batch` are derived from your rules, but you can then correct them in the
inspector. Regeneration must not undo that. The mapping file remembers what it derived last time
(`last_generated`), so:

- if the value in the JSON still equals what was derived last time, you never touched it and the
  freshly derived value is used (so editing your rules takes effect);
- if it differs, you changed it, and your value is kept.

To force an action to be re-derived, delete it from the JSON before regenerating.

## Limitations

- IFC dates must be ISO.
- GDIFC must be present to import. A schedule generated earlier keeps working without it.
- The Element ID cannot be changed after import without re-importing.
- Property values are read as GDIFC exposes them (its `properties` dictionary). Properties GDIFC
  does not surface are not visible to the tool.
