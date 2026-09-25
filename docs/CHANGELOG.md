# Changelog

Notable changes per release. The design reasoning behind each subsystem lives in the numbered
docs in this folder; `README.md` is the as-built reference.

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
