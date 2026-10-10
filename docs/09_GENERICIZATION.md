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
- **Terrain knows no country or project**: the data provider is picked from the site's
  latitude/longitude (`TerrainService.providers()`), and new countries plug in as `TerrainProvider`
  subclasses (`10_TERRAIN.md`). Test fixtures are invented IFCs.
- **Verified in a fresh empty project**: every script and scene loads, and the example scene builds
  and progresses through its schedule, with GDIFC absent.
- **Dialog default paths** for CSV and Project XML derive from `construction_json_path`
  (`<schedule>.csv`, `<schedule>.xml`, `<schedule>.project_mapping.json`).
- **Docs** use the current module paths throughout.

## Decided: leave as is

- **Dock labels are Spanish** (English tooltips carry the underlying field names). No i18n layer.
- **Animation offsets are absolute metres** (`rise_up`/`sink_down` depth, the `install` hover
  height and pickup offset; `drop_in` follows the piece's height but within 2.5–8 m). They suit
  building-scale models; scale-relative derivation is not planned.

## Open

0. **Formwork on regeneration.** IFC regeneration carries `type`/`batch` forward but not `formwork`
   blocks (`07_FORMWORK.md`, build order step 6).
1. **Continuous cadence.** An action's parts are stretched along one continuous curve across its
   whole `duration_days` window rather than partitioned into per-day buckets
   (`README.md`, "Known limitations"). Either fix it or record it as the intended design and close it.
2. **Asset Library submission** — nothing needed beyond a tagged release.

(Before 0.4.0 the files lived in `4d_plugin/` and `ifc_integration/`.)
