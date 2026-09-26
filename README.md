# Construction 4D Tool

A Godot 4 addon that turns a construction schedule into a scrubbable, date-aware 4D
timeline over your 3D model. Drag a slider to any calendar day and the building snaps to its
state on that day, or press Play to watch it get built.

- **Editor dock**: scrub live in the 3D viewport without running the game (Start Preview).
- **Runtime**: `SequenceManager` builds the timeline UI and plays the schedule in-game.
- **Schedule editing**: an inspector grid for dates, durations, units/day and dependencies;
  import/export as CSV and Microsoft Project XML.
- **Animations**: `scale_up`, `drop_in`, `rise_up`, `sink_down`, `fill_up` (concrete pour),
  `fade_in`, `fade_out`, `install` (crane).
- **Terrain**: downloads the real ground around a georeferenced model (elevation + orthophotos;
  Spain at 5 m / 25 cm, elevation-only worldwide), drapes it under the model, and lights the scene
  with the sun of the schedule's date. Building pads and excavation pits can be levelled into it,
  following the earthwork activities on the timeline; with none the ground stays natural (bridges).
- **Also**: formwork generation, collision scan, multi-crane, camera keyframes, movie mode,
  and an optional IFC pipeline (needs the separate GDIFC addon).

Tested with **Godot 4.6** and **4.7.2**. The whole IFC workflow below has been run end to end
in a fresh 4.7.2 project.

## Install

1. Copy this folder to `res://addons/construction_4d_tool/` in your project
   (or download a release ZIP and extract it into the project root).
2. Project Settings → Plugins → enable **Construction 4D Tool**.
3. For IFC models, also install **GDIFC**, a separate addon. It is on the Godot Asset Library
   ([asset 4212](https://godotengine.org/asset-library/asset/4212), source
   [Muniz1994/GDIFCpub](https://github.com/Muniz1994/GDIFCpub)). Put its `addons/GDIFC` folder
   into your project and enable **GDIFC** in Project Settings → Plugins as well.

## Try the example

Open `addons/construction_4d_tool/examples/demo.tscn` and see
[`examples/README_EXAMPLE.md`](examples/README_EXAMPLE.md).

## Use it on your own model

1. Put your model's parts as named children of one node (parts are matched by **name prefix**).
2. Add a `Node3D` with `runtime/sequence_manager.gd` attached, and set
   **Parts Container Path** to the node holding your parts (required, there is no default).
3. Write a `construction_steps.json` (see `examples/demo_steps.json`) and set
   **Construction Json Path** to it. The default is `res://construction_steps.json`.
4. Press Play, or use the dock's **Start Preview** to scrub in the editor.

A scene with no `Camera3D`, no environment or no `DirectionalLight3D` of its own still shows the
model when you press Play. For that run only, `SequenceManager` adds whatever is missing: a
free-fly camera framed on the whole model, a procedural sky and a sun. It prints a line saying so
and saves nothing into the scene. Add your own nodes to replace them.

### From an IFC file

This is the sequence verified end to end in a new project:

1. New 3D scene; add a `Node3D` with `runtime/sequence_manager.gd` attached; save the scene.
2. Dock: **Load IFC (4D)** → pick the `.ifc` file.
3. **Map IFC Properties**: choose which property is the element id, the start date, and the
   end date or duration. Optionally also the display name and the property plus rules that pick
   the animation type. Nothing is pre-selected: the plugin knows no property names. Your answers
   are saved beside the schedule, and a later import of the same kind of model reuses them
   silently.
4. The parts arrive under the `SequenceManager`. If the model is georeferenced, the terrain
   downloads by itself (**Terreno** section).
5. **Generate 4D Schedule** writes `construction_steps.json` from those properties.
6. Optional, in **Terreno**: **Añadir sol**, and **Nivelar desde el modelo** for a building
   (pad + excavation, tied to the earthwork activities).
7. **Start Preview** and drag the slider; **Stop Preview**; save.
8. F5 (pick the scene as main scene the first time) → **Play**.

### From an IFC file and an MS Project plan

When the dates live in Microsoft Project, and you have only the `.ifc` and the plan exported as
Project XML (`.xml`, not `.mpp`), follow steps 1–6 above, then:

7. **Start Preview**, then **Import Project XML** and pick the plan. Tasks are matched to actions
   by name, so the task names must be the element ids (a mapping dialog asks about any that are
   not). Summary tasks are ignored. The import updates the dates and adds each task's
   predecessors as `depends_on` / `lag_days`.
8. **Recalculate**, then **Save to JSON**. Without the save, the imported dates are lost when
   you stop the preview.
9. **Stop Preview**, save, F5 → **Play**.

**Generate 4D Schedule** has to come first: the import only updates actions that already exist.
Verified end to end on the Galicia sample: all 46 tasks matched, with dates identical to the
hand-made schedule.

### What neither file carries: formwork

An IFC property gives each element one animation, and Project XML has no notion of formwork. So
anything that is put up and later removed (scaffolding, formwork) comes out as a permanent part,
and elements poured in formwork get none. Add a `formwork` block to those actions in the Schedule
Inspector (`docs/README.md`, "Formwork"), then **Save to JSON**. On the Galicia sample that is 10
actions: footings, tie beams, ground slab, columns and floor slabs (panels), and the facade
scaffolding struck after the stonework (`prefix: Z99_Andamio`). Regenerating from the IFC later
keeps hand-corrected types, but not these blocks.

If you bring an existing `construction_steps.json` along with its
`construction_steps.ifc_profile.json`, skip **Generate 4D Schedule**. Load IFC reuses the saved
mapping without asking, and Generate would replace the hand-made schedule.

## Terrain

After **Load IFC (4D)** the model keeps its position on Earth (`SequenceManager.geo_origin`), and
the dock's **Terreno** section downloads the ground around it — automatically after import when the
model is georeferenced. Models without a georeference take a latitude/longitude typed into the dock.
Several IFC files of one site (e.g. two carriageways) can be loaded into the same scene: each is
placed relative to the first by its georeference.
**Añadir sol** adds a light that follows the timeline's date. Needs an Internet connection the
first time (files are cached in `res://terrain/`); your own `.asc` + JPG/world-file data also work.
See [`docs/10_TERRAIN.md`](docs/10_TERRAIN.md).

Data credit, required wherever the terrain is shown: *© Instituto Geográfico Nacional de España —
PNOA / MDT05, CC BY 4.0 (scne.es)* for Spain; the Terrain Tiles source list elsewhere (shown in the
dock). Near-ground textures come from Poly Haven (CC0).

## Layout

```
core/      schedule maths, animations, collision, formwork (no scene assumptions)
geo/       UTM, IFC georeference, the model's map origin, sun position
terrain/   terrain providers, download + build, terrain node and ground shader
runtime/   SequenceManager, timeline controller + UI, cranes, cameras, GeoSun
editor/    the dock, inspector, CSV / Project XML import-export
ifc/       optional IFC import: property scan, mapping, adapter, schedule generator
examples/  demo scene + annotated schedule
tests/     headless tests (run with Godot's --script)
docs/      design docs and the as-built reference (docs/README.md)
```

## IFC input

Load an IFC model from the dock (needs the separate **GDIFC** addon). The tool scans the
properties your model carries and asks *you* which one is the element id, the dates and so on;
no property names are built in. See [`docs/05_IFC_INTEGRATION.md`](docs/05_IFC_INTEGRATION.md).

## Tests

```
godot --headless --path . --editor --quit        # once, so class names register
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_mapping.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_geo.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_terrain.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_georef_gdifc.gd   # needs GDIFC
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_scene_models.gd   # import part needs GDIFC
```

None of them use the network.

## Known limitations

- The dock's labels are in Spanish (tooltips carry the underlying English field names).
- Animation offsets (drop height, rise depth, crane hover/pickup) are absolute metres, tuned for
  building-scale models.
- IFC schedule dates must be ISO (`YYYY-MM-DD`), and importing needs GDIFC.
- GDIFC (1.1.0-alpha) mis-decodes accented IFC text ("Formigón" arrives as "FormigÃ³n"). The
  dock repairs it on import (`GDIFC4DAdapter.repair_text()`); scenes imported earlier keep the
  garbled labels until re-imported.
- Regenerating a schedule from IFC keeps hand-corrected `type`/`batch`, but not `formwork` blocks.
- Parts of an action are spread along one continuous curve over its whole window rather than
  bucketed per day (`docs/README.md`, "Known limitations").
- Terrain: orthophotos only for mainland Spain and the Balearics (elsewhere elevation only); the
  ground ends at the edge of the downloaded square; no water surfaces. Levelled platforms follow
  the 5 m grid, so they come out up to one cell diagonal (7 m) wider than drawn, and their
  collision is the finished ground whatever the date.
- The collision scan only looks for clashes of `install` parts (crane lifts). A schedule without
  any skips it.
- Godot 4.7.2 prints `ERROR: Condition "p_I->data != this" is true` when a scene is saved. It comes
  from the engine: it appears with this addon and GDIFC both disabled, and is harmless.
- `docs/` still carries some historical prose from the original build order.

## Licence

MIT, see [LICENSE](LICENSE).
