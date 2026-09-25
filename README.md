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
- **Also**: formwork generation, collision scan, multi-crane, camera keyframes, movie mode,
  and an optional IFC pipeline (needs the separate GDIFC addon).

Tested with **Godot 4.6**.

## Install

1. Copy this folder to `res://addons/construction_4d_tool/` in your project
   (or download a release ZIP and extract it into the project root).
2. Project Settings → Plugins → enable **Construction 4D Tool**.

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

## Layout

```
core/      schedule maths, animations, collision, formwork (no scene assumptions)
runtime/   SequenceManager, timeline controller + UI, cranes, cameras
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
```

## Known limitations (0.4.0)

- The dock's labels are in Spanish (tooltips carry the underlying English field names).
- Animation offsets (drop height, rise depth, crane hover/pickup) are absolute metres, tuned for
  building-scale models.
- IFC schedule dates must be ISO (`YYYY-MM-DD`), and importing needs GDIFC.
- Regenerating a schedule from IFC keeps hand-corrected `type`/`batch`, but not `formwork` blocks.
- Parts of an action are spread along one continuous curve over its whole window rather than
  bucketed per day (`docs/README.md`, "Known limitations").
- `docs/` still carries some historical prose from the original build order.

## Licence

MIT, see [LICENSE](LICENSE).
