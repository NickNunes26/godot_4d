# Making the Tool Generic — Status

The addon started as tooling for one real project. This records what was generalised, what was
deliberately left, and what is open.

## Done

- **Self-contained addon**: own repository, `core/ runtime/ editor/ ifc/ examples/ tests/ docs/`,
  MIT licence, example scene, plugin-facing README.
- **No default container**: `SequenceManager.parts_container_path` must be set; unset reports a
  clear error instead of guessing a name.
- **`extra_part_containers`**: explicit list of further nodes whose children are parts, replacing a
  hard-coded name scan. `SequenceManager.collect_part_nodes()` is the single source for the runtime
  and the dock preview.
- **Project-specific code removed**: generated prop geometry, prop-specific animation timing.
- **IFC property mapping**: no property names ship with the plugin. The user selects them after
  import; see `05_IFC_INTEGRATION.md`. Covered by `tests/test_ifc_mapping.gd`, which uses an
  invented property layout.
- **Hand-corrected `type` / `batch` survive regeneration.**
- **Verified in a fresh empty project**: every script and scene loads, and the example scene builds
  and progresses through its schedule, with GDIFC absent.

## Decided: leave as is

- **Dock labels are Spanish** (English tooltips carry the underlying field names). No i18n layer.
- **Animation offsets are absolute metres** (drop height, rise depth, crane hover height and
  pickup offset). They suit building-scale models; scale-relative derivation is not planned.

## Open

0. **Formwork on regeneration.** IFC regeneration carries `type`/`batch` forward but not `formwork`
   blocks (`07_FORMWORK.md`, build order step 6).
1. **Continuous cadence.** An action's parts are stretched along one continuous curve across its
   whole `duration_days` window rather than partitioned into per-day buckets
   (`README.md`, "Known limitations"). Either fix it or record it as the intended design and close it.
2. **Default file paths for CSV / Project XML dialogs** are `res://schedule.csv` etc.; better derived
   from `construction_json_path`'s directory.
3. **Docs**: `README.md` and the numbered docs still use the historical `4d_plugin/` paths in prose
   (mapping below) and describe phases from the original build order.
4. **Asset Library submission** — nothing needed beyond a tagged release once the above is settled.

## Path mapping for older prose

`4d_plugin/<x>.gd` is now `core/<x>.gd` for `cadence`, `construction_schedule`, `collision_query`,
`spatial_grouper`, `animation_applier`, `formwork_builder`; and `runtime/<x>.gd` for everything else
(including `timeline_ui.tscn`). `ifc_integration/` is now `ifc/`.
`4d_plugin/construction_steps.json` is `res://construction_steps.json`.
