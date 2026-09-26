# Construction 4D Tool

**Step-by-step guide:** [GUIDE.md](GUIDE.md) (English) · **Guía paso a paso:** [GUIA.md](GUIA.md) (español)

A Godot 4 addon that turns a construction schedule into a 4D model: drag a slider to any date and
your building, imported from IFC, shows exactly what is built that day, standing on the real
terrain of the site, lit by that day's sun. Press Play to watch it being built, or record a video
to share.

Un addon para Godot 4 que convierte la planificación de una obra en un modelo 4D: arrastra un
deslizador hasta cualquier fecha y tu edificio, importado desde IFC, muestra exactamente lo que
está construido ese día, sobre el terreno real de la parcela y con el sol de ese día. Pulsa Play
para verlo construirse, o graba un vídeo para compartirlo.

- **Editor dock / Panel del editor**: scrub the schedule live in the 3D view / recorre la
  planificación en directo en la vista 3D (**Start Preview**).
- **Schedules / Planificación**: from IFC properties, Microsoft Project XML or CSV, edited in an
  inspector grid / desde propiedades IFC, XML de Microsoft Project o CSV, editable en una tabla.
- **Animations / Animaciones**: `scale_up`, `drop_in`, `rise_up`, `sink_down`, `fill_up` (concrete
  pour / hormigonado), `fade_in`, `fade_out`, `install` (crane / grúa).
- **Terrain / Terreno**: real elevation and aerial photos around the model (Spain 5 m / 25 cm,
  elsewhere elevation only), levelled pads and excavations tied to the earthworks, and the sun of
  the date / elevación y ortofotos reales (España 5 m / 25 cm; resto del mundo, solo elevación),
  explanaciones y excavaciones ligadas al movimiento de tierras, y el sol de cada fecha.
- **Also / Además**: formwork and scaffolding, crane lifts with clash detection, camera keyframes,
  one-command video recording / encofrados y andamios, izados con grúa y detección de colisiones,
  fotogramas clave de cámara, grabación de vídeo con un comando.

Tested with Godot 4.6 and 4.7.2. Every workflow below has been run end to end in a fresh
project. / Probado con Godot 4.6 y 4.7.2. Todos los flujos de trabajo de abajo se han probado de
principio a fin en un proyecto nuevo.

## Install / Instalación

Copy this folder into your project as `addons/construction_4d_tool/`. For IFC models also install
**GDIFC** from the Godot Asset Library ([asset 4212](https://godotengine.org/asset-library/asset/4212),
source [Muniz1994/GDIFCpub](https://github.com/Muniz1994/GDIFCpub)) as `addons/GDIFC/`. Then
enable both in **Project → Project Settings → Plugins** and restart the editor once. A dock called
**TimelineDock** appears at the bottom left.

Copia esta carpeta en tu proyecto como `addons/construction_4d_tool/`. Para modelos IFC instala
también **GDIFC** desde la Asset Library de Godot
([asset 4212](https://godotengine.org/asset-library/asset/4212), código fuente
[Muniz1994/GDIFCpub](https://github.com/Muniz1994/GDIFCpub)) como `addons/GDIFC/`. Después activa
los dos en **Proyecto → Configuración del proyecto → Plugins** y reinicia el editor una vez.
Aparece un panel llamado **TimelineDock** abajo a la izquierda.

To check the install, open `examples/demo.tscn` and press **F6**: a small building of boxes
builds itself in ten days. / Para comprobar la instalación, abre `examples/demo.tscn` y pulsa
**F6**: un pequeño edificio de cajas se construye solo en diez días.

## Quick start / Inicio rápido

Create a 3D scene, add a **Node3D** with `runtime/sequence_manager.gd` attached, and save. In the
dock press **Load IFC (4D)**, pick your `.ifc`, and in **Map IFC Properties** choose which property
is the element code, the start date and the end date or duration. If the model is georeferenced,
the terrain downloads by itself. Press **Generate 4D Schedule**, then **Start Preview** and drag
the slider. Press **F5** to play it. No camera, sky or light is needed: if the scene has none, one
is added for the run.

Crea una escena 3D, añade un **Node3D** con `runtime/sequence_manager.gd` y guarda. En el panel
pulsa **Load IFC (4D)**, elige tu `.ifc` y en **Map IFC Properties** indica qué propiedad es el
código del elemento, la fecha de inicio y la fecha de fin o la duración. Si el modelo está
georreferenciado, el terreno se descarga solo. Pulsa **Generate 4D Schedule**, después
**Start Preview** y arrastra el deslizador. Pulsa **F5** para reproducirlo. No hace falta cámara,
cielo ni luz: si la escena no los tiene, se añaden para esa ejecución.

**Dates in Microsoft Project?** After **Generate 4D Schedule**, press **Start Preview**, then
**Import Project XML** (task names must be the element codes), **Recalculate** and
**Save to JSON**. **Already have a `construction_steps.json`?** Put it in the project before
loading the IFC and skip **Generate 4D Schedule**.

**¿Las fechas están en Microsoft Project?** Después de **Generate 4D Schedule**, pulsa
**Start Preview**, luego **Import Project XML** (los nombres de las tareas deben ser los códigos de
los elementos), **Recalculate** y **Save to JSON**. **¿Ya tienes un `construction_steps.json`?**
Ponlo en el proyecto antes de cargar el IFC y no pulses **Generate 4D Schedule**.

## Terrain / Terreno

The dock's **Terreno** section downloads the ground around the model, places it, and can add a
sun that follows the schedule's date (**Añadir sol**). For a building, **Nivelar desde el modelo**
levels a pad and digs the excavation on the dates of the earthworks; for a bridge, leave the
ground natural. A model with no georeference takes a latitude and longitude typed into the dock.
Details in the guide and in [docs/10_TERRAIN.md](docs/10_TERRAIN.md).

La sección **Terreno** del panel descarga el terreno alrededor del modelo, lo coloca y puede
añadir un sol que sigue la fecha de la planificación (**Añadir sol**). Para un edificio,
**Nivelar desde el modelo** explana una plataforma y excava el vaciado en las fechas del
movimiento de tierras; para un puente, deja el terreno natural. Un modelo sin georreferencia
acepta una latitud y longitud escritas en el panel. Detalles en la guía y en
[docs/10_TERRAIN.md](docs/10_TERRAIN.md).

The terrain data must be credited wherever it is shown: *© Instituto Geográfico Nacional de España
— PNOA / MDT05, CC BY 4.0 (scne.es)* for Spain; the source list shown in the dock elsewhere. Videos
recorded with the tool include it. / Los datos del terreno deben citarse allí donde se muestren:
*© Instituto Geográfico Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)* en España; fuera,
la lista de fuentes que muestra el panel. Los vídeos grabados con la herramienta ya la incluyen.

## Video / Vídeo

Movie mode plays the whole schedule in a fixed length (60 s by default) with the date and the
terrain credit on screen, and closes when done. With **Movie File** set outside the project
(Project Settings → Editor → Movie Writer), switch on **Movie Maker** and press **F5**, or run
`godot --path <project> --write-movie <outside>/obra.avi --fixed-fps 30 res://<scene>.tscn`. Then
convert it to a small MP4 with
`ffmpeg -i obra.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart -an obra.mp4`.

El modo película reproduce toda la obra en una duración fija (60 s por defecto) con la fecha y el
crédito del terreno en pantalla, y se cierra al terminar. Con **Movie File** apuntando fuera del
proyecto (Configuración del proyecto → Editor → Movie Writer), activa **Movie Maker** y pulsa
**F5**, o ejecuta
`godot --path <proyecto> --write-movie <fuera>/obra.avi --fixed-fps 30 res://<escena>.tscn`.
Después conviértelo en un MP4 ligero con
`ffmpeg -i obra.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart -an obra.mp4`.

## Known limitations / Limitaciones conocidas

- **Formwork / Encofrados**: neither IFC nor Project XML can carry formwork or scaffolding that is
  put up and struck; set it up in the Schedule Inspector (guide, section 9). / ni el IFC ni el XML
  de Project describen encofrados ni andamios que se montan y desmontan; se configuran en el
  Schedule Inspector (guía, apartado 9).
- **Dates / Fechas**: IFC dates must be ISO (`YYYY-MM-DD`). / las fechas del IFC deben ir en
  formato ISO (`AAAA-MM-DD`).
- **Imagery / Ortofotos**: aerial photos only for mainland Spain and the Balearics; elsewhere
  elevation only. The ground ends at the edge of the downloaded square; no water surfaces. /
  ortofotos solo en España peninsular y Baleares; en el resto, solo elevación. El terreno acaba en
  el borde del cuadrado descargado; no hay superficies de agua.
- **Levelling / Explanación**: follows the 5 m terrain grid, so pads come out up to 7 m wider than
  drawn, and collision uses the finished ground. / sigue la malla de 5 m del terreno, así que las
  plataformas salen hasta 7 m más anchas de lo dibujado, y la colisión usa el terreno final.
- **Scale / Escala**: animation offsets (drop height, rise depth, crane heights) are fixed metres
  tuned for buildings. / los desplazamientos de las animaciones (altura de caída, profundidad,
  alturas de grúa) son metros fijos pensados para edificios.
- **Timing / Ritmo**: the elements of an action appear along one continuous curve over its whole
  window, not grouped per day. / los elementos de una actividad aparecen a lo largo de una curva
  continua en toda su duración, no agrupados por días.
- **Collisions / Colisiones**: only crane lifts (`install`) are checked. / solo se comprueban los
  izados con grúa (`install`).
- **Labels / Etiquetas**: the dock mixes Spanish and English labels; tooltips give the English
  field names. / el panel mezcla etiquetas en español e inglés; las ayudas emergentes dan el nombre
  del campo en inglés.
- **GDIFC 1.1.0-alpha** mis-decodes accented text; the dock repairs it on import, so re-import
  scenes made before 0.6.0. / decodifica mal los acentos; el panel los corrige al importar, así
  que vuelve a importar las escenas creadas antes de la 0.6.0.
- **Godot 4.7.2** prints `ERROR: Condition "p_I->data != this"` when saving a scene; it is harmless
  and comes from the engine. / muestra ese error al guardar una escena; es inofensivo y viene del
  motor.

## For developers

*Para desarrolladores: esta sección está solo en inglés.*

```
core/      schedule maths, animations, collision, formwork (no scene assumptions)
geo/       UTM, IFC georeference, the model's map origin, sun position
terrain/   terrain providers, download + build, terrain node, levelling, ground shader
runtime/   SequenceManager, timeline controller + UI, cranes, cameras, GeoSun
editor/    the dock, inspector, CSV / Project XML import-export
ifc/       IFC import: property scan, mapping, adapter, schedule generator
examples/  demo scene + annotated schedule
tests/     headless tests (run with Godot's --script)
docs/      design docs, the as-built reference (docs/README.md), API, changelog
```

Headless tests (none use the network):

```
godot --headless --path . --editor --quit        # once, so class names register
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_mapping.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_geo.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_terrain.gd
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_georef_gdifc.gd   # needs GDIFC
godot --headless --path . --script res://addons/construction_4d_tool/tests/test_ifc_scene_models.gd   # import part needs GDIFC
```

Start with [docs/README.md](docs/README.md) (how it all works), [docs/04_API_REFERENCE.md](docs/04_API_REFERENCE.md)
(classes and methods), [docs/05_IFC_INTEGRATION.md](docs/05_IFC_INTEGRATION.md) (IFC import) and
[docs/CHANGELOG.md](docs/CHANGELOG.md). Some of `docs/` still carries historical prose from the
original build order.

## Licence / Licencia

MIT, see / ver [LICENSE](LICENSE).
