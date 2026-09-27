# Build4D — User guide

*Versión en español: [GUIA.md](GUIA.md).*

This guide takes you from an empty Godot project to a 4D model of your building on its real
terrain, and a video of it being built. Follow the sections in order the first time. Every
button name below is written exactly as it appears on screen: the dock mixes English and
Spanish labels.

Contents: [1. What you need](#1-what-you-need) · [2. Install](#2-install) ·
[3. Try the demo](#3-try-the-demo) · [4. Prepare your scene](#4-prepare-your-scene) ·
[5. Import your model](#5-import-your-model-ifc) · [6. Get a schedule](#6-get-a-schedule) ·
[7. Terrain](#7-terrain-and-the-site) · [8. Preview and edit](#8-preview-and-edit-the-schedule-in-the-editor) ·
[9. Formwork and scaffolding](#9-formwork-and-scaffolding) · [10. Play](#10-play-it) ·
[11. Record a video](#11-record-a-video) · [12. Troubleshooting](#12-troubleshooting)

---

## 1. What you need

- **Godot 4.6 or newer** (tested on 4.7.2), standard (non-.NET) build.
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
5. Restart the editor once (**Project → Reload Current Project**). A dock called
   **TimelineDock** appears at the bottom left.

## 3. Try the demo

Open `addons/construction_4d_tool/examples/demo.tscn` and press **F6**. A small building of
boxes builds itself over ten days. Press **Play** on the bar at the top, drag the slider, and
click in the view to fly around (details in [section 10](#10-play-it)). If this works, the addon is
installed correctly.

## 4. Prepare your scene

1. **Scene → New Scene**, choose **3D Scene**. Rename the root if you like (e.g. `Site`).
2. Right-click the root → **Add Child Node** → **Node3D**. Name it `SequenceManager`.
3. With that node selected, drag `addons/construction_4d_tool/runtime/sequence_manager.gd` from
   the FileSystem panel onto the **Script** field in the Inspector.
4. Save the scene (**Ctrl+S**), for example as `res://site.tscn`.

The dock now says **Target: SequenceManager**. You do not need to add a camera, sky or light:
if the scene has none when you press Play, the tool adds a camera framed on the building, a
sky and a sun for that run. You can add your own later ([section 11](#11-record-a-video)).

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
   | **Decide type from** + rules | A property that tells how each element appears (e.g. a column whose values are `fill_up`, `rise_up`...). Add one rule per value: *contains* `fill_up` → `fill_up`. | No |
   | **Default type** | The animation for elements no rule matches. | — |

   **OK** stays greyed out until the required fields are chosen. Press **OK**.
3. The elements appear under `SequenceManager` (e.g. `IFCParts_mymodel`). Your answers are saved
   next to the schedule (`construction_steps.ifc_profile.json`). Importing the same kind of model
   again reuses them without asking; to change them, press **Edit IFC mapping**.
4. If the IFC is georeferenced, the terrain starts downloading by itself; see
   [section 7](#7-terrain-and-the-site).
5. Several IFC files of the same site (e.g. structure and landscaping, or two carriageways) can
   go in one scene: press **Load IFC (4D)** again for each. Each is placed next to the first by
   its georeference.

The animation types are: `scale_up` (grows), `drop_in` (lowered from above), `rise_up` (rises from
below), `sink_down` (sinks and disappears, e.g. excavated soil), `fill_up` (concrete pour, fills
from the bottom), `fade_in`, `fade_out` (e.g. clearing trees), `install` (lifted by a crane).

## 6. Get a schedule

Pick the case that matches what you have.

### A. Only the IFC (dates are in the model)

Press **Generate 4D Schedule**. It writes `construction_steps.json` with one action per Element
ID. Elements with no dates (existing ground, for instance) stay visible from day 0.

### B. The IFC plus a Microsoft Project plan (XML)

1. Press **Generate 4D Schedule** first. The XML import updates actions; it does not create them.
2. Press **Start Preview**. The import buttons only work during a preview.
3. Press **Import Project XML** and pick the `.xml`. Each task is matched to an action by its
   **name**, so the task names in Project must be the element codes (e.g. `C04_Limpeza`). Summary
   tasks are ignored. If some tasks don't match, a window asks you which action each one is.
4. Press **Recalculate**, then **Save to JSON**. Without **Save to JSON**, the imported dates are
   lost when you stop the preview.

The import brings in the dates and the links between tasks (predecessors and lags).

### C. You already have a `construction_steps.json`

Copy `construction_steps.json` (and `construction_steps.ifc_profile.json` if you have it) into
the project root **before** loading the IFC, and **do not** press **Generate 4D Schedule**: it
would replace your schedule. With the profile present, **Load IFC (4D)** doesn't even ask for the
mapping.

## 7. Terrain and the site

Everything here is in the **Terreno** section of the dock.

**Automatic.** When the IFC carries its position on Earth, the terrain downloads right after the
import: elevation and aerial photos (mainland Spain and the Balearics: 5 m and 25 cm; elsewhere
elevation only). It takes a few seconds to a minute and is cached in `res://terrain/`.

**If the model is not georeferenced**, type the centre of the model as **Lat, lon** (e.g. copied
from a web map), leave **Altura** empty if you don't know the height, turn the model with
**Giro °** if needed, press **Aplicar origen**, then **Descargar terreno**. Without a height the
model is placed on the ground automatically.

| Control | Use |
|---|---|
| Size list | **Reducido (2 km)**, **Estándar (4,2 km)**, **Amplio (8 km)** of terrain around the model |
| **Al importar IFC** | Download automatically after an import (on by default) |
| **Texturas cercanas** | Detailed ground textures close to the camera (~15 MB, once) |
| **Descargar terreno** | Download / rebuild now |
| **Archivos propios…** | Use your own `.asc` elevation and JPG/PNG photos with world files instead |
| **Comprobar posición** | Report whether the model floats or is buried |
| **Asentar en el suelo** | Lower or raise the model until it just touches the ground |
| **Añadir sol** | A sun that follows the schedule's date |
| **Quitar terreno** | Remove the terrain (downloaded files stay) |

**Levelling for a building.** Natural ground is right for a bridge; a building sits on levelled
ground. Press **Nivelar desde el modelo**: it creates a platform under the model and an
excavation down to the footings, and ties them to the earthworks activities in your schedule
(topsoil stripping, excavation...), so the ground changes on those dates. **Talud H:V** sets the
bank slope (1.5 = 1.5 m across per 1 m of height); **Margen m** adds room around the model. To
adjust, select the **Terrain** node and open **Platforms** in the Inspector (outline, level,
slope, activities). **Terreno natural** removes all levelling.

**Credit.** Terrain data must be credited wherever it is shown. The credit appears in the dock,
and videos recorded with the tool include it automatically. For Spain: *© Instituto Geográfico
Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)*.

## 8. Preview and edit the schedule in the editor

1. Press **Start Preview**. A timeline appears in the dock: drag its slider and the 3D view
   shows the building on that date. **Do not save the scene while the preview is on.**
2. The **Schedule Inspector** below lists every action. Its column headers are in Spanish (hover
   one for the English name). Per row you can change **Tipo** (animation), **Fecha Inicio**,
   **Duración (días)**, **Fecha Fin**, **Unidades/Día**, **Encofrado** and **Días vertido**
   (section 9), **Depende De** (the action it waits for) and **Retraso (días)**, and remove the row
   (**✕**). **Ancla** decides which of start / duration / end stays fixed when you edit the others.
3. After editing, press **Recalculate** to see the result, and **Save to JSON** to keep it.
   **Reload from JSON** discards unsaved edits.
4. **Export CSV / Import CSV** and **Export Project XML / Import Project XML** exchange the
   schedule with Excel or Microsoft Project.
5. Press **Stop Preview** when done. Every element returns to how the scene was saved. Then save.

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
  3. Back in the dock, press **Reload from JSON**.

Regenerating the schedule from the IFC later keeps the types you corrected, but not formwork.

## 10. Play it

Press **F5** (the first time, answer **Select Current** to make your scene the main scene) or
**F6** for the open scene.

- **Bar at the top**: **Play / Pause**, the slider (drag to any date), the speed box (schedule
  days per second, 0.1 to 5), **Reset** (back to the first day), **Scan Collisions** (only
  relevant for crane lifts, `install`).
- **Camera**: click in the view to fly. **W A S D** move, the mouse looks, **Q / E** go down / up,
  **Shift** is faster, **Esc** releases the mouse so you can use the bar again.

## 11. Record a video

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

## 12. Troubleshooting

| Problem | What to do |
|---|---|
| The dock says **No SequenceManager found in the open scene** | Do [section 4](#4-prepare-your-scene): the scene needs a node with `sequence_manager.gd`. |
| **Load IFC (4D)** does nothing; the Output panel says GDIFC is not installed | Enable **GDIFC** in Project Settings → Plugins and restart the editor. |
| **OK** is greyed out in **Map IFC Properties** | Choose Element ID, Start date, and End date or Duration. |
| The mapping window no longer appears | The saved answers are reused. Use **Edit IFC mapping** to change them. |
| Nothing is visible when playing | Press **Generate 4D Schedule** (or bring a schedule, section 6). Parts with no schedule stay hidden. |
| **Import Project XML** is greyed out | Press **Start Preview** first. |
| Imported dates disappeared | Press **Save to JSON** before **Stop Preview**. |
| A window asks to map Project tasks | Those task names are not element codes. Pick the action for each, or rename the tasks in Project. |
| The terrain download fails | The Spanish servers fail now and then; the tool retries four times. Press **Descargar terreno** again later. |
| The model floats or is buried | **Comprobar posición**, then **Asentar en el suelo**, or type the right **Altura** and **Aplicar origen**. |
| Accents look wrong (`FormigÃ³n`) in an old scene | Re-import the IFC; the tool now repairs them. |
| Scaffolding never comes down | See [section 9](#9-formwork-and-scaffolding). |
| Thousands of images appear in the project after recording | The movie file was inside the project. Move it outside and delete the images. |
| `ERROR: Condition "p_I->data != this"` when saving | A harmless Godot 4.7.2 message; ignore it. |

For how everything works inside, see [docs/README.md](docs/README.md) and the numbered documents
in `docs/`.
