# Terrain, Georeference and Sun

Put the real ground under the model: elevation and orthophotos for the site are downloaded,
draped under the parts, textured, and lit by the sun of the schedule's date. Mainland Spain and
the Balearic Islands get 5 m elevation and 25 cm orthophotos from the Spanish national services;
the rest of the world gets elevation only, from an open global dataset. Everything is GDScript: no
Python, no extra GDExtension, no external program.

## Quick start

1. Load an IFC model with the dock's **Load IFC (4D)** (or place any model yourself, see
   "Models that are not georeferenced" below).
2. If the model is georeferenced and **Al importar IFC** is ticked (default), the terrain downloads
   by itself when the import finishes. Otherwise open the dock's **Terreno** section and press
   **Descargar terreno**. When the scene already has a terrain that covers every model (a second
   model of the same site, or a re-import), it is kept and only the position check runs.
3. Optional: **Añadir sol** adds a `GeoSun` that follows the timeline's date.
4. Save the scene.

The first download of a site takes a few seconds to a minute (about 20 MB); later builds of the
same site reuse the files.

## Where the model is on Earth

### What the IFC can say

Three shapes of georeferenced IFC occur in practice, and exporters (Allplan among them) produce
different ones depending on an export option. All are read:

| Shape | What the file carries | `GeoOrigin.source` |
|---|---|---|
| Map conversion | Local coordinates, plus `IfcMapConversion` (E, N, H, rotation, scale) and usually `IfcProjectedCRS` (EPSG code / map zone) | `ifc_map_conversion` |
| Map coordinates | The root placement's point is at map coordinates, e.g. (452300, 4461200, 650); no map conversion | `ifc_coordinates` |
| Neither | Local coordinates only | `""` (not georeferenced) |

`IfcGeoref.read()` extracts all of this from the STEP text without loading geometry.

### Keeping it through import

GDIFC stores vertices at float32, which is useless at map magnitudes (0.5 m steps at a northing of
4.7 million), so `GDIFCRecenter` strips a large root-placement offset from a copy of the file
before GDIFC sees it. An offset in `IfcMapConversion` needs no stripping (GDIFC ignores the map
conversion) and is only read, so such a file loads without a copy — which matters for models of
hundreds of MB. Both work with CRLF line endings, which most exporters write.
It used to discard what it stripped. Now `recenter_with_info()` returns it, and the import records
two more facts:

- the **framing shift**: after loading, the dock moves the model so its bounding-box centre is at
  the origin, and records that vector;
- **GDIFC's axes**, verified: IFC (x = east, y = north, z = up) becomes Godot (x, z, -y), so
  **east = +X, up = +Y, north = -Z**. GDIFC ignores `IfcMapConversion` entirely, and
  `GDIFCLoaderSettings.coordinate_to_origin` has no effect in the build tested (the dock sets it to
  `false` anyway, so no shift can happen unrecorded).

`GeoOrigin.from_ifc_import(info, shift)` combines these into a `GeoOrigin`, which is stored as
`SequenceManager.geo_origin` and saved with the scene. It holds, as 64-bit floats, the map
coordinates of the **parts container's local origin** (the model's bounding-box centre), the
rotation and scale of the map conversion, the UTM zone, and where each value came from.
`local_to_map()` / `map_to_local()` convert points; `map_frame_transform()` gives the
map-aligned frame (+X east, +Y up, -Z north) in the container's space.

The test `tests/test_ifc_georef_gdifc.gd` runs the whole chain through a real GDIFC load on three
invented fixtures (root point, rotated map conversion, not georeferenced) and checks the box in
each lands on its map coordinates to the millimetre.

### The UTM zone

The zone cannot be told from easting and northing: the same pair is a valid point in every zone,
hundreds of kilometres apart. In order:

1. **Declared** in `IfcProjectedCRS` (`EPSG:25830`, map zone `30N`, ...): used as is.
2. **Deduced** (Spain): for each candidate zone the ground height at that point is asked for, and
   compared with the model's median part height. Accepted only with a wide margin: best within
   120 m, runner-up at least max(300 m, 3 × best) off. Sea (the service returns exact zeros) and
   points outside the coverage are skipped. In practice the right zone matches within a few metres
   and the others miss by hundreds.
3. **By hand** in the dock (the `Huso` field), or implied by entering latitude/longitude.

### Models that are not georeferenced

Type the model centre's latitude and longitude (for example copied from a web map) or its E, N
and zone into the **Terreno** section and press **Aplicar origen**. Leave **Altura** empty if the
height is unknown: after the download the model is *sat on the ground* (raised or lowered until
the part reaching deepest into the ground just touches it). **Giro °** turns a model whose axes
are not aligned with grid north. All of these can also be edited later on `SequenceManager.geo_origin`
in the inspector; the terrain follows immediately.

A model with map-looking coordinates can still be wrong: rotated, or tens of metres too low. After
every build the dock runs a **position check** (below) and says so.

## Downloading

`TerrainService` does the work; the dock only drives it. Providers describe their downloads and
parse their files; the service fetches, retries, resamples, builds the textures and saves.

| Provider | Covers | Elevation | Imagery | Licence |
|---|---|---|---|---|
| `SpainIgnProvider` | Mainland Spain + Balearics (35–44.5° N, 10° W–4.5° E) | MDT05, 5 m, via the IGN INSPIRE WCS (EPSG:4258, ASC in multipart MIME) | PNOA orthophoto via the IGN INSPIRE WMS, in EPSG:258zz | CC BY 4.0, credit required |
| `TerrariumProvider` | Everywhere (\|lat\| < 85°) | Terrain Tiles on AWS, Terrarium PNG encoding, zoom ≤ 14 (≤ 25 tiles) | none | per-source attribution (in the provider) |

The first provider that covers the site's latitude/longitude is used. The Canary Islands (zone 28,
REGCAN95) are not covered by the Spanish provider.

**Size presets** (dock): *Reducido* 2 km of elevation / 1 km + 2 km orthophotos; *Estándar*
(default) 4.2 km at 5 m (840 × 840 points) / 1 km at 0.25 m/px + 4 km at 1 m/px; *Amplio* 8 km at
10 m / 1 km + 8 km. The elevation grid is always resampled bilinearly onto a regular grid in the
model's UTM zone; the orthophotos are requested directly in that zone.

**Reliability.** The Spanish services fail intermittently (502s, timeouts), so every request is
retried four times, waiting 3, 12 and 27 s. The WCS also closes its TLS connection without ending
the chunked response; Godot's `HTTPRequest` reports that as a connection error and, when writing to
a file, drops the last chunk. Downloads therefore go through `HTTPClient` on a worker thread
(`TerrainService.download_blocking()`), and each file is accepted on its *content*: a complete ASC
grid, a JPEG ending in `FF D9`, a PNG ending in `IEND`, parseable JSON. Every file is written as
`.parcial` first and renamed only once accepted.

**Cache.** A site lives in `res://terrain/<key>/`, where the key encodes zone, centre (whole metres),
size and cell, so anything that changes the download changes the folder. Raw downloads go to
`raw/` (with a `.gdignore`, so the editor does not import them; they come with world files
`.jgw` and can be opened in any GIS); the finished `terrain.res` sits next to it. Rebuilding an
existing site does not download again. Commit `terrain.res` if the project should open on
another machine without a network; the `raw/` folders can be git-ignored.

**Your own files.** **Archivos propios…** builds the same terrain from an `.asc` elevation grid
(UTM metres in the model's zone, or geographic degrees — told apart by the corner's magnitude)
plus optional JPG/PNG orthophotos with world files (`.jgw`, `.pgw`, `.wld`). Godot cannot read
GeoTIFF: convert those to JPG + world file first.

## What ends up in the scene

```
SequenceManager
├── IFCParts_<file>     (primary parts container, geo_origin refers to its origin)
├── IFCParts_<file2>    (further models, if any: extra_part_containers, placed relative to it)
└── Terrain             ConstructionTerrain: data = res://terrain/<key>/terrain.res
    ├── Ground          (generated on load, never saved)
    └── GroundBody      (generated on load, never saved)
GeoSun                  (optional, anywhere in the scene)
```

`ConstructionTerrain` is a sibling of the parts container, never inside it (everything in there
is treated as a part). It places itself from `geo_origin` and `anchor_path`, and follows any edit
of the origin. Its children are rebuilt from `TerrainData` every time the scene loads, so the
`.tscn` only stores the node and a reference.

`TerrainData` (a binary resource, ~23 MB for the standard preset) holds the heights (`PackedFloat32Array`,
row 0 = north), the orthophotos as VRAM-compressed (S3TC) mipmapped textures with their map
rectangles, a collision grid, and the attribution text.

**Mesh.** A `PlaneMesh` whose vertices sit exactly on the height grid; the shader lifts each vertex
to its height (`texelFetch` on a float texture) and computes the normal from its neighbours. Nothing
mesh-sized is stored anywhere; the GPU draws 1.4 million triangles for the standard preset without
trouble. `custom_aabb` carries the real height range for culling.

**Collision.** A `HeightMapShape3D` on a `StaticBody3D`, from a separate grid resampled to
2^k + 1 samples per side (1025 for the standard preset) — the size Jolt builds as a real height
field rather than falling back to a triangle mesh. It does **not** take part in the tool's clash
checks: those only query their own areas (`CollisionQuery`, layer 20, bodies excluded).

**Material** (`terrain/ground.gdshader`, a port of the reference render kit's ground material):

- far: the orthophoto (detail square inside, context square elsewhere, a 3 % fade between them),
  graded with saturation × 1.25, value × 0.72 and a highlight-compressing curve through (0, 0),
  (0.10, 0.09), (0.25, 0.16), (1, 0.45) — burnt summer fields otherwise read as white;
- near (35 → 160 m from the camera): tiled leaf litter on flat ground and rock on slopes
  (normal.y 0.93 → 0.70), mixed 45 % with the orthophoto tint and darkened, with roughness and a
  normal map that fades out with distance.

The near textures (`GroundTextures`: Poly Haven `forest_leaves_02` and `dry_riverbed_rock`, CC0,
2k) are downloaded once per project into `res://terrain/_ground_textures/` (~15 MB). Untick
**Texturas cercanas** to skip them; the ground is then orthophoto only.

## Levelled platforms

The downloaded ground is the land as it is, which suits a bridge or a road on its natural line.
A building sits on levelled ground instead. `ConstructionTerrain.platforms` holds that levelling:
a list of `TerrainPlatform`s, each a level area cut and filled into the terrain. When the list is
empty, the ground stays natural. Nothing is written into `terrain.res`, so removing the platforms
gives back the downloaded ground.

**A platform** (all in the parts container's space, so it moves with the model when its
georeference changes):

| Property | Meaning |
|---|---|
| `footprint` | Outline in the container's X/Z plane, ≥ 3 points |
| `level` | Height of the levelled surface, container Y |
| `bank_slope` | Banks, horizontal per 1 vertical (1.5 earth, 0.5 a steep excavation face; 0 = no bank) |
| `activities` | Schedule action ids that do this earthwork (see below); empty = present from day 0 |
| `bare_earth` | Draw the levelled area and its banks as bare earth |
| `enabled`, `name` | Switch off without deleting; label for reports |

Platforms apply in order: a pit listed after a pad is dug into the pad. Inside the footprint the
ground is set to `level`. Outside it, the ground is clamped between `level ± distance / bank_slope`,
which cuts where it was higher and fills where it was lower. The bank ends where it meets the
natural ground.

**The grid edge.** The ground is a triangle grid of `cell` metres (5 m), so its edge cannot follow a
footprint drawn at arbitrary angles. A triangle with one corner on the platform and another up
the bank would tilt across the footprint's edge and poke through whatever the model has there.
Every grid point within one cell diagonal (7.07 m at 5 m) of the footprint is therefore levelled
too, and the banks start from there. The levelled area can come out up to that much wider than
drawn, never narrower.

**On the timeline.** A platform with `activities` changes from natural to levelled between the
earliest start and the latest finish of those actions (`TerrainPlatform.progress_on()`).
`TimelineController.scrub_to()` pushes the day to every terrain (`ConstructionTerrain.update_all()`,
alongside `GeoSun`), so it works for Play, scrubbing, the dock preview and movie recording. Stop
Preview puts the finished ground back. An id missing from the schedule counts as "no activity".

**How it is drawn.** `TerrainGrading.compute()` works out each grid point's height change and keeps
only the rectangle of points that change: 22 × 19 texels for the sample site, out of 841². Each
point has two slots (platform + change), so a point that is first levelled and then dug keeps both
steps with their own timing. The shader adds `change × progress` per slot in `h_at()`, so normals
and everything else follow. Bare earth is a warm soil colour carrying the rock texture's detail
near the camera, shown where a point is inside a footprint or moved by at least 0.3 m. Collision
is the finished ground: rebuilding a 1025² height field every frame would cost far more than it
is worth. `ConstructionTerrain.height_at()` and **Comprobar posición** use the levelled ground.

**From the model** (dock: **Nivelar desde el modelo**, with **Talud H:V** and **Margen m**).
`TerrainGrading.platforms_from_model()` proposes:

- a **pad** over the model's plan extent plus the margin (default 0: the levelled ring above
  already leaves an apron). Its level is the bottom elevation carrying the largest plan area of
  parts, leaving out foundations (`IfcFooting`, `IfcPile`, ...) and the parts of excavation
  actions. Parts resting there keep their bottom faces exactly on the ground, so no faces are
  drawn on top of each other;
- a **pit**, when parts reach more than 0.25 m below the pad. It covers their plan extent (plus
  0.5 m, unless the model draws the dig itself) and goes down to the lowest of them, with banks
  at no more than 0.5;
- **timing** from action ids and comments: site levelling or topsoil words (`terra vexetal`,
  `desmonte`, `explanación`, `grading`, ...) drive the pad; excavation words (`escavación`,
  `vaciado`, `zanja`, `trench`, ...) drive the pit. Each falls back to the other's actions, so a
  pit never appears before its pad.

Parts are measured at their rest placement (`original_pos` / `original_scale`), so a running
preview does not throw it off. The proposal replaces the current platforms; adjust it in the
Terrain node's inspector. **Terreno natural** removes them all.

For `pazo_xilloi.tscn` this gives a pad at 25.47 m (the bottom of the model's own `Z00_Terreo`
ground, 60 × 46 m), tied to `C02_TerraVexetal`. It also gives a pit at 23.67 m, exactly the
model's 29.2 × 19.2 m dig, tied to `C03_Escavacion`: about 10,100 m³ of cut and 2,400 m³ of fill.

## Position check

`TerrainBuilder.position_check()` samples the ground under every part's footprint centre and
reports the range of part bottoms relative to it and how many parts are buried (top more than
1.5 m under ground). It warns when more than half the parts are buried, or when the lowest part is
more than 40 m above the ground (the model floats). Piles and footings are *meant* to be buried,
so a bridge on piles legitimately reports many buried parts; the warning is advice, never a block.
**Comprobar posición** re-runs it; **Asentar en el suelo** applies its suggested lift.

## The sun

`GeoSun` is a `DirectionalLight3D`. Whenever the timeline moves (`TimelineController.scrub_to()`,
which both Play and scrubbing go through), every `GeoSun` gets the schedule's **calendar date**
and points itself where the sun is over the site on that date at `time_of_day` local time
(default 11:00). Only the date is used: playback runs at days per second, and a sun that moved
with the fraction of the day would strobe.

- Position: NOAA's low-precision formulas (about 0.5°), a port of the reference kit's.
- Time zone: `utc_offset_hours` (winter offset; +1 for mainland Spain) plus the EU summer-time
  rule (`eu_summer_time`), last Sunday of March to last Sunday of October at 01:00 UTC.
- Orientation: from `SequenceManager.geo_origin` (so a rotated map conversion is honoured); with no
  georeference, `fallback_lat_lon` and -Z as north.
- `follow_schedule = false` leaves the light alone. In the editor, Stop Preview puts the light back
  exactly where it was, like every other part of the preview.

## Attribution

Shown in the dock under the terrain and stored in `TerrainData.attribution`; reproduce it wherever
the terrain appears (renders, videos, publications):

- Spain: **© Instituto Geográfico Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)**
- Terrain Tiles: the per-source list in `TerrariumProvider.attribution()` (from the dataset's own
  attribution document).
- Poly Haven textures are CC0 (no attribution required; credited in the dock anyway).

## Adding a country

Subclass `TerrainProvider` and add it to `TerrainService.providers()` before the global fallback:

- `covers(lat, lon)`, `id()`, `display_name()`, `attribution()`;
- `elevation_downloads(spec)` returning `[{url, file, timeout}]`, `validate_elevation(path)`, and
  `build_heights(spec, dir)` returning the spec's grid (use `AscGrid` and
  `TerrainBuilder.sample_geographic()` / `sample_projected()` where they fit);
- for imagery, `has_imagery()` and `ortho_download(spec, half, name)` returning
  `{url, file, timeout, rect}` in the site's UTM zone;
- for zone deduction, `candidate_zones()`, `probe_download()` and `probe_height()`.

Check the licence first: imagery from commercial map services (Google, Esri World Imagery, ...) is
not freely redistributable.

## Files

| File | Class | Role |
|---|---|---|
| `geo/utm.gd` | `Utm` | UTM ↔ lat/lon (GRS80), zone helpers |
| `geo/ifc_georef.gd` | `IfcGeoref` | Map conversion, projected CRS, root placements from STEP text |
| `geo/geo_origin.gd` | `GeoOrigin` | The model's position on the map (Resource) |
| `geo/solar.gd` | `Solar` | Sun position, EU summer time, local time → UTC |
| `ifc/gdifc_recenter.gd` | `GDIFCRecenter` | Strips large offsets before GDIFC and reports them |
| `ifc/ifc_scene_models.gd` | `IfcSceneModels` | Several models per scene: placement, slots, origin |
| `terrain/terrain_spec.gd` | `TerrainSpec` | What to download: zone, centre, sizes, presets, grid geometry |
| `terrain/terrain_provider.gd` | `TerrainProvider` | Provider interface |
| `terrain/spain_ign_provider.gd` | `SpainIgnProvider` | IGN WCS + WMS |
| `terrain/terrarium_provider.gd` | `TerrariumProvider` | Global elevation tiles |
| `terrain/asc_grid.gd` | `AscGrid` | ESRI ASCII grid parser (multipart-aware) |
| `terrain/terrain_service.gd` | `TerrainService` | Downloads, retries, zone deduction, build, save |
| `terrain/terrain_builder.gd` | `TerrainBuilder` | Resampling, textures, world files, position check |
| `terrain/terrain_data.gd` | `TerrainData` | Saved site (Resource) |
| `terrain/construction_terrain.gd` | `ConstructionTerrain` | The terrain node |
| `terrain/terrain_platform.gd` | `TerrainPlatform` | One levelled area (Resource) |
| `terrain/terrain_grading.gd` | `TerrainGrading` | Cut/fill, grading texture, platforms from a model |
| `terrain/ground.gdshader` | — | Ground material |
| `terrain/ground_textures.gd` | `GroundTextures` | Near textures from Poly Haven |
| `runtime/geo_sun.gd` | `GeoSun` | Date-driven sun |
| `editor/terrain_panel.gd` | `TerrainPanel` | The dock's Terreno section |

Tests: `tests/test_geo.gd`, `tests/test_terrain.gd` (no network), `tests/test_ifc_georef_gdifc.gd`
and `tests/test_ifc_scene_models.gd` (need GDIFC for the import part).

## Not done yet

- **Distant hills** beyond the downloaded square (the reference kit adds Terrarium terrain out to
  16 km); today the ground ends at the edge of the square.
- **Water**: rivers are only what the orthophoto shows; no water surface.
- **Vegetation, haze, sky**: use Godot's own `Environment` (fog, sky) for now.
- **Finer ground near the model**: levelled edges follow the 5 m grid (see "Levelled platforms").
  A locally refined grid would give crisp pad edges and near-vertical excavation faces.
- **Landscaping over the banks**: levelled ground stays bare earth to the end of the schedule; a
  platform option to regrass it with a late activity would suit finished-project renders.
- **Survey topography** (detailed site meshes) and other **terrain edits** around the model (burying
  supports, road cuts).
- **Terrain in clash checks**: parts against the ground is a plausible future check.
- **Other countries' imagery**: providers welcome (see "Adding a country").
