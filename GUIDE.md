# Build4D — User guide

*Versión en español: [GUIA.md](GUIA.md).*

This guide takes you from an empty Godot project to a 4D model of your building on its real
terrain, and a video of it being built. Follow the sections in order the first time. Every
button name below is written exactly as it appears on screen: the dock mixes English and
Spanish labels.

**The short version**, for a georeferenced IFC whose elements carry their dates: **Load IFC
(4D)** (answer the property window once) → **Start Preview** to check it → save the scene → **F5**.
The import writes the schedule and brings in the terrain, levelled for the building, and the sun;
Play adds the machines. The rest of this guide is for when you want more.

Contents: [1. What you need](#1-what-you-need) · [2. Install](#2-install) ·
[3. Try the demo](#3-try-the-demo) · [4. Prepare your scene](#4-prepare-your-scene) ·
[5. Import your model](#5-import-your-model-ifc) · [6. Get a schedule](#6-get-a-schedule) ·
[7. Terrain](#7-terrain-and-the-site) · [8. Preview and edit](#8-preview-and-edit-the-schedule-in-the-editor) ·
[9. Formwork and scaffolding](#9-formwork-and-scaffolding) · [10. Site equipment](#10-site-equipment) · [11. Play](#11-play-it) ·
[12. Record a video](#12-record-a-video) · [13. Troubleshooting](#13-troubleshooting)

---

## 1. What you need

- **Godot 4.6 or newer** (tested on 4.6.2 and 4.7.2), standard (non-.NET) build.
- **Your model as an IFC file** (`.ifc`). Each element should carry a property with its activity
  code, and ideally its start and end dates or duration. Any property names work: you tell the
  tool which ones to use.
- Optional: **your plan as Microsoft Project XML** (in Project: *File → Save As → XML*). The
  binary `.mpp` format cannot be read.
- **An Internet connection** the first time you build the terrain (about 20 MB per site).
- For videos you want to share: **ffmpeg** (free), to turn Godot's recording into an MP4.

## 2. Install

1. Create a new project in the Godot Project Manager (renderer *Forward+*).
2. Download **Build4D** (this repository: the green **Code → Download ZIP** button,
   or a release) and copy its folder into your project as
   `addons/construction_4d_tool/`. The file `addons/construction_4d_tool/plugin.cfg` must exist.
3. Download **GDIFC**, the IFC reader, from the Godot Asset Library
   ([asset 4212](https://godotengine.org/asset-library/asset/4212)). Either use the editor's
   **AssetLib** tab, or download the ZIP and copy its `addons/GDIFC` folder into your project's
   `addons/`.
4. In Godot: **Project → Project Settings → Plugins**, tick **Enabled** for both
   **Build4D** and **GDIFC**.
5. Restart the editor once (**Project → Reload Current Project**). A tab called
   **Build4D** appears in the upper-right dock, next to Inspector and Node.

## 3. Try the demo

Open `addons/construction_4d_tool/examples/demo.tscn` and press **F6**. A small building of
boxes builds itself over ten days. Press **Play** on the bar at the top, drag the slider, and
click in the view to fly around (details in [section 11](#11-play-it)). If this works, the addon is
installed correctly.

## 4. Prepare your scene

1. **Scene → New Scene**, choose **3D Scene**. Rename the root if you like (e.g. `Site`).
2. Save the scene (**Ctrl+S**), for example as `res://site.tscn`.

The tool is driven by a `SequenceManager` node. You do not add it yourself: the first **Load IFC
(4D)** creates it (it is a `Node3D` with `runtime/sequence_manager.gd`, so you will not find it in
**Add Child Node**), and the dock then says **Target: SequenceManager**. For a schedule without an
IFC model, add it by hand: right-click the root → **Add Child Node** → **Node3D**, name it
`SequenceManager`, and drag `addons/construction_4d_tool/runtime/sequence_manager.gd` from the
FileSystem panel onto its **Script** field in the Inspector.

You do not need to add a camera, sky or light:
if the scene has none when you press Play, the tool adds a camera framed on the building, a
sky and a sun for that run. You can add your own later ([section 12](#12-record-a-video)).

## 5. Import your model (IFC)

1. In the dock, press **Load IFC (4D)** and pick your `.ifc` file.
2. The window **Map IFC Properties** opens. It lists every property found in the model, with
   how many elements carry it and a few sample values. Choose:

   | Field | What to pick | Required |
   |---|---|---|
   | **Element ID** | The activity or element code (e.g. `C04_Limpeza`). Elements sharing a code become one schedule action. | Yes |
   | **Start date** | The start date property (format `YYYY-MM-DD`). | Yes |
   | **End date** | The end date property. | This **or** Duration |
   | **Duration (days)** | The duration property. | This **or** End date |
   | **Display name** | A readable name for the activity. | No |
   | **Infer the type from the activity name** | On by default. Each activity's animation is chosen from its code and display name: *Hormigonado…* / *Formigón…* pours, *Mampostería…* builds up, *Excavación…* digs, *Carpintería…* fades in, and so on (Spanish, Galician, Portuguese, English). Nothing else to set up. | — |
   | **Type stated by property** + rules | Only if your model already says how each element appears (a property whose values are `fill_up`, `build_up`...), or carries values a rule can translate: *contains* `hormigón` → `fill_up`. A type stated this way wins over the inferred one. Leave **(none)** otherwise. | No |
   | **Fallback type** | The animation for activities nothing above decides. | — |

   **OK** stays greyed out until the required fields are chosen. Press **OK**.
3. The elements appear under `SequenceManager` (e.g. `IFCParts_mymodel`), and the schedule is
   written at the same time (`construction_steps.json`, see [section 6](#6-get-a-schedule)).
   Your answers are saved next to it (`construction_steps.ifc_profile.json`). Importing the same
   kind of model again reuses them without asking; to change them, open the **▾** next to
   **Load IFC (4D)** → **Edit IFC mapping**.
4. If the IFC is georeferenced, the terrain starts downloading by itself; see
   [section 7](#7-terrain-and-the-site).
5. Several IFC files of the same site (e.g. structure and landscaping, or two carriageways) can
   go in one scene: press **Load IFC (4D)** again for each. Each is placed next to the first by
   its georeference, and its activities are added to the schedule (nothing already in it
   changes).

The animation types are: `fill_up` (concrete pour, fills from the bottom), `build_up` (built up
from its own base, e.g. masonry, scaffolding), `drop_in` (lowered onto its place from a few
metres above, one piece after another), `sink_down` (sinks and disappears, e.g. excavated soil),
`fade_in`, `fade_out` (e.g. clearing trees), `scale_up` (grows from its base, e.g. planting),
`rise_up` (the whole element rises from 10 m below), `install` (lifted by a crane, and
clash-checked).

Elements built in one position and then turned into their final one (an arch half built
standing up and lowered onto its springing) take a `"rotate"` block in `construction_steps.json`:
`"rotate": {"group": "ARCH_P13", "duration_days": 2}` on each of their actions. They are built
standing upright about a hinge at the base of the lowest piece, and swing down together once the
last one is finished.

What the name inference picks, roughly: demolition and site clearing fade out; excavation and
topsoil sink down; concrete, slabs, footings and columns fill up; masonry, walls, chimneys and
scaffolding build up; stone pieces, precast, steel and timber framing, ironwork and lighting drop
in one by one; roofing, openings, finishes and services fade in; planting scales up. It never
picks `install`: a crane lift is a decision about the site, not about the name.

## 6. Get a schedule

Pick the case that matches what you have.

### A. Only the IFC (dates are in the model)

Nothing to do: **Load IFC (4D)** writes `construction_steps.json`, one action per Element ID.
Elements with no dates (existing ground, for instance) stay visible from day 0.

If you later change the mapping or the dates in the model, **▾** → **Generate 4D Schedule**
rewrites the schedule from the IFC. It keeps the types you corrected, but takes every date from
the IFC again (dates imported from Project are lost) and drops formwork, so use it only then.

### B. The IFC plus a Microsoft Project plan (XML)

1. **Load IFC (4D)** as above: it writes the schedule. The XML import updates actions; it does
   not create them.
2. Press **Importar…** and pick the `.xml` (the preview starts by itself). Each task is matched to
   an action by its **name**, so the task names in Project must be the element codes (e.g.
   `C04_Limpeza`). Summary tasks are ignored. If some tasks don't match, a window asks you which
   action each one is.
3. Press **Save to JSON** (or **Stop Preview** and answer **Guardar**).

The import brings in the dates and the links between tasks (predecessors and lags). It also sets
each action's animation type when the plan has a custom text column (e.g. *Text2*, named *Tipo de
animación*) holding type names (`fill_up`, `rise_up`...): the column is recognised by its values,
whatever it is called. To make the Pilares a concrete pour, write `fill_up` in that column for
their tasks in Project and import again.

### C. You already have a `construction_steps.json`

Copy `construction_steps.json` (and `construction_steps.ifc_profile.json` if you have it) into
the project root **before** loading the IFC. **Load IFC (4D)** keeps your schedule: it only adds
actions for activities of the model that none of yours covers. Don't use **▾** → **Generate 4D
Schedule**: it would replace it. With the profile present, **Load IFC (4D)** doesn't even ask for
the mapping.

## 7. Terrain and the site

Everything here is in the **Terreno** section of the dock.

**Automatic.** When the IFC carries its position on Earth, the terrain downloads right after the
import: elevation and aerial photos (mainland Spain and the Balearics: 5 m and 25 cm; elsewhere
elevation only). It takes a few seconds to a minute and is cached in `res://terrain/`. Then, by
itself: a model with no known height is set on the ground; the ground is **levelled for the
building** when the schedule has earthworks (below); a **sun** that follows the schedule's date
(GeoSun) is added if the scene has no light of its own. The status line says whether the model
floats or is buried.

**If the model is not georeferenced**, the dock shows the origin fields: type the centre of the
model as **Lat, lon** (e.g. copied from a web map), leave **Altura** empty if you don't know the
height, turn the model with **Giro °** if needed, and press **Aplicar origen**: the terrain
downloads. Without a height the model is placed on the ground. For a georeferenced model the same
fields are under **▸ Cambiar origen**, to correct a wrong position.

| Control | Use |
|---|---|
| **Descargar terreno** | Download / rebuild now (**Cancelar** takes its place while downloading) |
| **Nivelar para edificio** | Levelled ground for the building (below); untick for the natural ground |
| **▸ Más opciones** → size list | **Reducido (2 km)**, **Estándar (4,2 km)**, **Amplio (8 km)** of terrain around the model |
| **▸ Más opciones** → **Al importar IFC** | Download automatically after an import (on by default) |
| **▸ Más opciones** → **Texturas cercanas** | Detailed ground textures close to the camera (~15 MB, once) |
| **▸ Más opciones** → **Archivos propios…** | Use your own `.asc` elevation and JPG/PNG photos with world files instead |
| **▸ Más opciones** → **Asentar en el suelo** | Lower or raise the model until it just touches the ground |

To remove the terrain, delete the **Terrain** node in the Scene panel (the downloaded files stay).

**Levelling for a building.** Natural ground is right for a bridge; a building sits on levelled
ground. **Nivelar para edificio** creates a platform under the model and an excavation down to the
footings, and ties them to the earthworks activities in your schedule (topsoil stripping,
excavation...), so the ground changes on those dates. It is ticked by itself the first time the
terrain is built for a schedule that has earthworks; untick it for the natural ground. To adjust,
select the **Terrain** node: **Platforms** in the Inspector holds each one (outline, level,
slope, activities), and **Levelling from the model** holds **Level Slope** (bank slope, 1.5 =
1.5 m across per 1 m of height) and **Level Margin** (room around the model) — untick and tick
**Nivelar para edificio** again to apply those two.

**Credit.** Terrain data must be credited wherever it is shown. The credit appears in the dock,
and videos recorded with the tool include it automatically. For Spain: *© Instituto Geográfico
Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)*.

## 8. Preview and edit the schedule in the editor

1. Press **Start Preview** (the same button then reads **Stop Preview**). A timeline appears in
   the dock: drag its slider and the 3D view shows the building on that date. The schedule tools
   below only appear while the preview is on. **Do not save the scene while the preview is on.**
2. The **Schedule Inspector** lists every action. Per row you can change **Tipo** (animation),
   **Fecha Inicio**, **Duración (días)**, **Fecha Fin**, **Unidades/Día**, **Encofrado** and
   **Días vertido** (section 9), **Depende De** (the action it waits for) and **Retraso (días)**,
   and remove the row (**✕**). **Ancla** decides which of start / duration / end stays fixed when
   you edit the others. Its column headers are in Spanish (hover one for the English name). Each
   edit shows in the 3D view a moment later.
3. **Save to JSON** keeps your edits (it is greyed out when there is nothing new to save).
4. **Exportar…** writes the schedule for Microsoft Project (`.xml`) or Excel (`.csv`): pick the
   type in the file window. **Importar…** reads either back.
5. **Auto types** sets every row's **Tipo** and cadence from the activity's name, as the import
   does (useful for a schedule that came from CSV, Project XML or an older version); the Output
   panel lists every change, and rows whose name it doesn't recognise are left alone.
6. Press **Stop Preview** when done. With edits not yet saved it asks: **Guardar** saves them,
   **Descartar** throws them away, **Cancelar** keeps previewing. Every element returns to how the
   scene was saved. Then save the scene.

## 9. Formwork and scaffolding

Neither the IFC nor Project XML can describe formwork, so elements poured in formwork and
scaffolding that is put up and struck must be set up here.

- **Formwork panels for concrete elements**: in the Schedule Inspector, set the row's
  **Encofrado** to **Genérico** and choose **Días vertido**: the last days of the action, when the
  concrete is poured. The panels are generated around the element and go up during the days
  before the pour, then come off once it is done. **Encofrado en todo el proyecto** switches it
  on for every action at once.
- **Scaffolding or formwork that exists in your model** (e.g. elements coded `Z99_Andamio`):
  1. In the Schedule Inspector, remove the scaffolding's own row (**✕**) and **Save to JSON**.
  2. Open `construction_steps.json` in a text editor and add to the action that needs it (e.g. the
     façade stonework):
     `"formwork": {"prefix": "Z99_Andamio", "pour_days": 84, "strip_days": 3}`.
     The scaffolding goes up during the first part of that action, the action's own elements go
     in during its last `pour_days` days, and the scaffolding comes down `strip_days` days after
     the action ends.
  3. Back in the dock, press **Stop Preview** and **Start Preview** again: the preview reads the
     file afresh.

**▾** → **Generate 4D Schedule** later keeps the types you corrected, but not formwork. Loading
another IFC doesn't touch it.

This set-up is a stopgap: scaffolding borrows the concrete-formwork mechanism, serves one
activity only, needs the JSON edit above and is lost on regeneration. A proper rework is planned
— see [docs/12_FUTURE_WORK.md](docs/12_FUTURE_WORK.md).

## 10. Site equipment

Play shows the site's plant with no setup: an **excavator** loading a **truck** at the pit during
the excavation, a **tower crane** that goes up before the structure, lowers the stone pieces on its
hook and comes down after the roof, and a **mobile crane** for the lifts the tower crane can't make
(out of its reach, or after it has gone). They come and go with the activities, read from their
names like the animation types (**Auto types**, section 8): "Excavación" brings the excavator,
"Hormigonado", "Mampostería", "Sillería"... keep the crane on site, the roofing ends it.

- **To see and move them in the editor**, press **Maquinaria** (next to **Load IFC (4D)**). A
  **SiteEquipment** node appears with two markers, **TowerCraneSite** and **ExcavatorSite**, at the
  proposed positions: move or turn a marker and the machine follows. Select **SiteEquipment** to
  change **Tower Height** (ground to the jib) and **Jib Length** (0 = automatic), **Erect Days**, or
  switch a machine off. Save the scene to keep it. Pressing **Maquinaria** again proposes fresh
  positions (it stops the preview first, asking about unsaved edits).
- **The mobile crane** is set up beside each lift's pieces, so it has no marker.
- **Your own crane**: if the scene already has one, no tower crane is added.
- **The excavator is to scale**: a Caterpillar 320 built to the manufacturer's published
  dimensions, reaching as far and as deep as the real one (`equipment/specs/`).
- **No machines**: select the SequenceManager and untick **Auto Equipment** (and delete
  SiteEquipment if you added one).
- The machines are for show: they are not clash-checked and are not in the schedule.

## 11. Play it

Press **F5** (the first time, answer **Select Current** to make your scene the main scene) or
**F6** for the open scene.

- **Bar at the top**: **Play / Pause**, the slider (drag to any date), the speed box (schedule
  days per second, 0.1 to 5), **Reset** (back to the first day).
- **Clashes** (only for crane lifts, `install`) are looked for by themselves when Play starts: the
  dates with one turn red on the slider (hover for the pair), the Output panel lists them, and Play
  stops at each. A lifted piece clashes when it passes through something already built on its way
  in. Touching or overlapping what it sits on or against *in the finished
  model* is not a clash, and neither is grazing within 2 cm. Pieces of one activity are placed
  bottom-up, so a clash that remains usually means the activity is scheduled after what is above
  it (e.g. window surrounds still going in after the cornice above them).
- **Camera**: click in the view to fly. **W A S D** move, the mouse looks, **Q / E** go down / up,
  **Shift** is faster, **Esc** releases the mouse so you can use the bar again.

## 12. Record a video

**Choose the camera.** The video uses the scene's current camera, which stays still. To pick
the shot, add a **Camera3D** to the scene, place it, and tick **Current** in the Inspector
(attach `runtime/free_look_camera.gd` if you also want to fly it). For moving shots, use camera
keyframes: during **Start Preview**, drag the slider to a date, move the editor's 3D view to the
shot you want and press **Capturar cámara**. Each press adds a keyframe to `camera_track.json`,
and the video moves between them.

**Choose the length.** Select `SequenceManager`, group **Movie Maker Mode**, **Movie Duration
Sec** (default 60 s for the whole schedule).

**Record, from the editor:**
1. **Project → Project Settings → Editor → Movie Writer** (turn on **Advanced Settings** if you
   don't see it): set **Movie File** to a path **outside** the project folder, ending in `.avi`
   (e.g. `C:/Videos/obra.avi`). Inside the project, Godot would write one image per frame and
   import them all. **FPS**: 30 is enough.
2. Press the **Movie Maker** button (film icon, next to the play buttons, top right) so it is
   on, then **F5**. The window plays the whole schedule without controls and closes by itself.

**Or from a terminal** (same result):
```
godot --path "C:/path/to/project" --write-movie "C:/Videos/obra.avi" --fixed-fps 30 res://site.tscn
```

**Make it shareable.** The `.avi` is large (around 250 MB per minute). Convert it to MP4:
```
ffmpeg -i obra.avi -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart -an obra.mp4
```
A one-minute 1080p video ends up around 10–15 MB, fine for WhatsApp, Telegram or email. Raise
`-crf` (e.g. 24) for a smaller file. The window size (**Project Settings → Display → Window →
Size**) is the video size; 1920 × 1080 is standard.

## 13. Troubleshooting

| Problem | What to do |
|---|---|
| The dock says **No SequenceManager found in the open scene** | Normal before the first import: **Load IFC (4D)** creates it. Without an IFC, add it by hand as in [section 4](#4-prepare-your-scene). |
| **Load IFC (4D)** does nothing; the Output panel says GDIFC is not installed | Enable **GDIFC** in Project Settings → Plugins and restart the editor. |
| **OK** is greyed out in **Map IFC Properties** | Choose Element ID, Start date, and End date or Duration. |
| The mapping window no longer appears | The saved answers are reused. Use **▾** → **Edit IFC mapping** to change them. |
| Nothing is visible when playing | Parts with no action in the schedule stay hidden. Check the Output panel after **Load IFC (4D)**; if the schedule could not be written, use **▾** → **Generate 4D Schedule**. |
| I can't find the Schedule Inspector, **Save to JSON** or **Encofrado** | They show only while the preview is on: press **Start Preview**. |
| **Importar…** / **Start Preview** are greyed out | There is no SequenceManager yet: **Load IFC (4D)** first. |
| Imported dates disappeared | They were not saved: answer **Guardar** when stopping the preview, or press **Save to JSON**. |
| A window asks to map Project tasks | Those task names are not element codes. Pick the action for each, or rename the tasks in Project. |
| The terrain download fails | The Spanish servers fail now and then; the tool tries four times. Press **Descargar terreno** again later. |
| The model floats or is buried | The status line after the download says so. **▸ Más opciones** → **Asentar en el suelo**, or **▸ Cambiar origen**, type the right **Altura** and **Aplicar origen**. |
| Accents look wrong (`FormigÃ³n`) in an old scene | Re-import the IFC; the tool now repairs them. |
| Scaffolding never comes down | See [section 9](#9-formwork-and-scaffolding). |
| Thousands of images appear in the project after recording | The movie file was inside the project. Move it outside and delete the images. |
| `ERROR: Condition "p_I->data != this"` when saving | A harmless Godot 4.7.2 message; ignore it. |

For how everything works inside, see [docs/README.md](docs/README.md) and the numbered documents
in `docs/`.
