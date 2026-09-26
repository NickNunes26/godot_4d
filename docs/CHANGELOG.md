# Changelog

Notable changes per release. The design reasoning behind each subsystem lives in the numbered
docs in this folder; `README.md` is the as-built reference.

## Unreleased

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
