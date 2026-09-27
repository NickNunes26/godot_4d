# Build4D — Guía de uso

*English version: [GUIDE.md](GUIDE.md).*

Esta guía te lleva desde un proyecto de Godot vacío hasta un modelo 4D de tu obra sobre su
terreno real, y un vídeo de cómo se construye. La primera vez, sigue los apartados en orden. Los
nombres de los botones aparecen tal cual se ven en pantalla: el panel mezcla etiquetas en inglés y
en español.

Contenido: [1. Qué necesitas](#1-qué-necesitas) · [2. Instalación](#2-instalación) ·
[3. Prueba el ejemplo](#3-prueba-el-ejemplo) · [4. Prepara la escena](#4-prepara-la-escena) ·
[5. Importa el modelo](#5-importa-el-modelo-ifc) · [6. Consigue la planificación](#6-consigue-la-planificación) ·
[7. Terreno](#7-el-terreno-y-la-parcela) · [8. Vista previa y edición](#8-vista-previa-y-edición-en-el-editor) ·
[9. Encofrados y andamios](#9-encofrados-y-andamios) · [10. Reproducir](#10-reprodúcelo) ·
[11. Grabar un vídeo](#11-graba-un-vídeo) · [12. Problemas frecuentes](#12-problemas-frecuentes)

---

## 1. Qué necesitas

- **Godot 4.6 o posterior** (probado con 4.7.2), versión estándar (no .NET).
- **Tu modelo en IFC** (`.ifc`). Cada elemento debería llevar una propiedad con su código de
  actividad y, a ser posible, sus fechas de inicio y fin o su duración. Los nombres de las
  propiedades dan igual: tú le dices a la herramienta cuáles usar.
- Opcional: **tu planificación como XML de Microsoft Project** (en Project: *Archivo → Guardar
  como → XML*). El formato binario `.mpp` no se puede leer.
- **Conexión a Internet** la primera vez que se genera el terreno (unos 20 MB por emplazamiento).
- Para vídeos que quieras compartir: **ffmpeg** (gratuito), para convertir la grabación de Godot
  en MP4.

## 2. Instalación

1. Crea un proyecto nuevo en el gestor de proyectos de Godot (renderizador *Forward+*).
2. Descarga **Build4D** (este repositorio: botón verde **Code → Download ZIP**, o una
   release) y copia su carpeta en tu proyecto como `addons/construction_4d_tool/`. Debe existir el
   archivo `addons/construction_4d_tool/plugin.cfg`.
3. Descarga **GDIFC**, el lector de IFC, de la Asset Library de Godot
   ([asset 4212](https://godotengine.org/asset-library/asset/4212)). Puedes usar la pestaña
   **AssetLib** del editor, o descargar el ZIP y copiar su carpeta `addons/GDIFC` dentro de la
   carpeta `addons/` de tu proyecto.
4. En Godot: **Proyecto → Configuración del proyecto → Plugins**, marca **Activado** en
   **Build4D** y en **GDIFC**.
5. Reinicia el editor una vez (**Proyecto → Recargar proyecto actual**). Aparece una pestaña llamada
   **Build4D** en el panel superior derecho, junto a Inspector y Nodo.

## 3. Prueba el ejemplo

Abre `addons/construction_4d_tool/examples/demo.tscn` y pulsa **F6**. Un edificio pequeño hecho
de cajas se construye solo en diez días. Pulsa **Play** en la barra de arriba, arrastra el
deslizador y haz clic en la vista para volar (detalles en el [apartado 10](#10-reprodúcelo)). Si
esto funciona, el addon está bien instalado.

## 4. Prepara la escena

1. **Escena → Nueva escena**, elige **Escena 3D**. Si quieres, cambia el nombre de la raíz (por
   ejemplo `Obra`).
2. Guarda la escena (**Ctrl+S**), por ejemplo como `res://obra.tscn`.

La herramienta funciona a través de un nodo `SequenceManager`. No tienes que añadirlo tú: el
primer **Load IFC (4D)** lo crea (es un `Node3D` con `runtime/sequence_manager.gd`, por eso no
aparece en **Añadir nodo hijo**) y el panel indica entonces **Target: SequenceManager**. Para un
cronograma sin modelo IFC, añádelo a mano: clic derecho en la raíz → **Añadir nodo hijo** →
**Node3D**, llámalo `SequenceManager` y arrastra
`addons/construction_4d_tool/runtime/sequence_manager.gd` desde el panel Sistema de archivos a su
campo **Script** del Inspector.

No hace falta añadir cámara, cielo ni luz: si
la escena no los tiene al pulsar Play, la herramienta añade para esa ejecución una cámara
encuadrada en el edificio, un cielo y un sol. Puedes poner los tuyos más adelante
([apartado 11](#11-graba-un-vídeo)).

## 5. Importa el modelo (IFC)

1. En el panel, pulsa **Load IFC (4D)** y elige tu archivo `.ifc`.
2. Se abre la ventana **Map IFC Properties**. Muestra todas las propiedades que hay en el modelo,
   cuántos elementos tienen cada una y algunos valores de ejemplo. Elige:

   | Campo | Qué elegir | Obligatorio |
   |---|---|---|
   | **Element ID** | El código de actividad o de elemento (p. ej. `C04_Limpeza`). Los elementos con el mismo código forman una misma actividad. | Sí |
   | **Start date** | La propiedad con la fecha de inicio (formato `AAAA-MM-DD`). | Sí |
   | **End date** | La propiedad con la fecha de fin. | Esta **o** la duración |
   | **Duration (days)** | La propiedad con la duración. | Esta **o** la fecha de fin |
   | **Display name** | Un nombre legible de la actividad. | No |
   | **Decide type from** + reglas | Una propiedad que diga cómo aparece cada elemento (p. ej. una cuyos valores son `fill_up`, `rise_up`...). Los valores que ya son nombres de tipo se usan tal cual; añade una regla solo para traducir otros valores: *contiene* `hormigón` → `fill_up`. | No |
   | **Default type** | La animación de los elementos a los que no se aplica ninguna regla. | — |

   **OK** sigue en gris hasta que eliges los campos obligatorios. Pulsa **OK**.
3. Los elementos aparecen bajo `SequenceManager` (p. ej. `IFCParts_mimodelo`). Tus respuestas se
   guardan junto a la planificación (`construction_steps.ifc_profile.json`). Si importas otra vez
   un modelo del mismo tipo, se reutilizan sin preguntar; para cambiarlas, pulsa
   **Edit IFC mapping**.
4. Si el IFC está georreferenciado, el terreno empieza a descargarse solo; mira el
   [apartado 7](#7-el-terreno-y-la-parcela).
5. En una misma escena caben varios IFC del mismo emplazamiento (p. ej. estructura y
   urbanización, o dos calzadas): pulsa **Load IFC (4D)** otra vez para cada uno. Cada uno se
   coloca junto al primero según su georreferencia.

Los tipos de animación son: `scale_up` (crece), `drop_in` (baja desde arriba), `rise_up` (sube
desde abajo), `sink_down` (se hunde y desaparece, p. ej. tierra excavada), `fill_up` (hormigonado,
se llena desde abajo), `fade_in`, `fade_out` (p. ej. desbroce de árboles), `install` (lo coloca una
grúa).

## 6. Consigue la planificación

Elige el caso que corresponde a lo que tienes.

### A. Solo el IFC (las fechas están en el modelo)

Pulsa **Generate 4D Schedule**. Escribe `construction_steps.json` con una actividad por cada
Element ID. Los elementos sin fechas (el terreno existente, por ejemplo) quedan visibles desde el
primer día.

### B. El IFC y una planificación de Microsoft Project (XML)

1. Pulsa primero **Generate 4D Schedule**. La importación del XML actualiza actividades; no las crea.
2. Pulsa **Start Preview**. Los botones de importar solo funcionan durante la vista previa.
3. Pulsa **Import Project XML** y elige el `.xml`. Cada tarea se asocia a una actividad por su
   **nombre**, así que en Project los nombres de las tareas deben ser los códigos de los elementos
   (p. ej. `C04_Limpeza`). Las tareas resumen se ignoran. Si alguna tarea no coincide, una ventana
   te pregunta a qué actividad corresponde.
4. Pulsa **Recalculate** y después **Save to JSON**. Sin **Save to JSON**, las fechas importadas se
   pierden al detener la vista previa.

La importación trae las fechas y los vínculos entre tareas (predecesoras y retrasos). También fija
el tipo de animación de cada acción si el plan tiene una columna de texto personalizada (p. ej.
*Texto2*, llamada *Tipo de animación*) con nombres de tipo (`fill_up`, `rise_up`...): la columna se
reconoce por sus valores, se llame como se llame. Para que los Pilares sean un hormigonado, escribe
`fill_up` en esa columna para sus tareas en Project e impórtalo de nuevo.

### C. Ya tienes un `construction_steps.json`

Copia `construction_steps.json` (y `construction_steps.ifc_profile.json` si lo tienes) en la raíz
del proyecto **antes** de cargar el IFC, y **no** pulses **Generate 4D Schedule**: sustituiría tu
planificación. Con el perfil presente, **Load IFC (4D)** ni siquiera pregunta por las propiedades.

## 7. El terreno y la parcela

Todo esto está en la sección **Terreno** del panel.

**Automático.** Cuando el IFC lleva su posición en la Tierra, el terreno se descarga justo después
de importar: elevación y ortofotos (España peninsular y Baleares: 5 m y 25 cm; en el resto del
mundo, solo elevación). Tarda de unos segundos a un minuto y se guarda en `res://terrain/`.

**Si el modelo no está georreferenciado**, escribe el centro del modelo en **Lat, lon** (por
ejemplo, copiado de un mapa web), deja **Altura** vacía si no la conoces, gira el modelo con
**Giro °** si hace falta, pulsa **Aplicar origen** y después **Descargar terreno**. Sin altura, el
modelo se apoya en el suelo automáticamente.

| Control | Para qué sirve |
|---|---|
| Lista de tamaño | **Reducido (2 km)**, **Estándar (4,2 km)**, **Amplio (8 km)** de terreno alrededor del modelo |
| **Al importar IFC** | Descargar automáticamente tras importar (activado por defecto) |
| **Texturas cercanas** | Texturas de suelo detalladas cerca de la cámara (~15 MB, una vez) |
| **Descargar terreno** | Descargar / regenerar ahora |
| **Archivos propios…** | Usar tu propia elevación `.asc` y fotos JPG/PNG con archivo de georreferencia |
| **Comprobar posición** | Indica si el modelo flota o queda enterrado |
| **Asentar en el suelo** | Sube o baja el modelo hasta que toque el suelo |
| **Añadir sol** | Un sol que sigue la fecha de la planificación |
| **Quitar terreno** | Quita el terreno (los archivos descargados se conservan) |

**Explanación para un edificio.** El terreno natural sirve para un puente; un edificio se apoya
en un terreno explanado. Pulsa **Nivelar desde el modelo**: crea una plataforma bajo el modelo y
una excavación hasta las zapatas, y las asocia a las actividades de movimiento de tierras de tu
planificación (retirada de tierra vegetal, excavación...), de modo que el terreno cambia en esas
fechas. **Talud H:V** fija la pendiente de los taludes (1,5 = 1,5 m en horizontal por cada metro de
altura); **Margen m** añade espacio alrededor del modelo. Para ajustarlo, selecciona el nodo
**Terrain** y abre **Platforms** en el Inspector (contorno, cota, talud, actividades).
**Terreno natural** elimina toda la explanación.

**Créditos.** Los datos del terreno deben citarse allí donde se muestren. El crédito aparece en el
panel, y los vídeos grabados con la herramienta lo incluyen automáticamente. Para España:
*© Instituto Geográfico Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)*.

## 8. Vista previa y edición en el editor

1. Pulsa **Start Preview**. Aparece una línea de tiempo en el panel: arrastra su deslizador y la
   vista 3D muestra la obra en esa fecha. **No guardes la escena con la vista previa activa.**
2. Debajo, el **Schedule Inspector** muestra todas las actividades. En cada fila puedes cambiar
   **Tipo** (la animación), **Fecha Inicio**, **Duración (días)**, **Fecha Fin**,
   **Unidades/Día**, **Encofrado** y **Días vertido** (apartado 9), **Depende De** (la actividad a
   la que espera) y **Retraso (días)**, y borrar la fila (**✕**). **Ancla** decide cuál de inicio /
   duración / fin se mantiene al editar los demás.
3. Después de editar, pulsa **Recalculate** para ver el resultado y **Save to JSON** para
   guardarlo. **Reload from JSON** descarta los cambios sin guardar.
4. **Export CSV / Import CSV** y **Export Project XML / Import Project XML** intercambian la
   planificación con Excel o Microsoft Project.
5. Al terminar, pulsa **Stop Preview**. Todos los elementos vuelven a como estaba guardada la
   escena. Después, guarda.

## 9. Encofrados y andamios

Ni el IFC ni el XML de Project pueden describir encofrados, así que los elementos hormigonados con
encofrado y los andamios que se montan y se desmontan se configuran aquí.

- **Paneles de encofrado para elementos de hormigón**: en el Schedule Inspector, pon la columna
  **Encofrado** de la fila en **Genérico** y elige **Días vertido**: los últimos días de la
  actividad, cuando se hormigona. Los paneles se generan alrededor del elemento, se montan durante
  los días anteriores al vertido y se retiran al terminar. **Encofrado en todo el proyecto** lo
  activa en todas las actividades a la vez.
- **Andamios o encofrados que ya están en tu modelo** (p. ej. elementos con código `Z99_Andamio`):
  1. En el Schedule Inspector, borra la fila propia del andamio (**✕**) y pulsa **Save to JSON**.
  2. Abre `construction_steps.json` en un editor de texto y añade a la actividad que lo necesita
     (p. ej. la cantería de fachada):
     `"formwork": {"prefix": "Z99_Andamio", "pour_days": 84, "strip_days": 3}`.
     El andamio se monta en la primera parte de esa actividad, los elementos de la actividad se
     colocan en sus últimos `pour_days` días, y el andamio se desmonta `strip_days` días después
     de que acabe la actividad.
  3. De vuelta en el panel, pulsa **Reload from JSON**.

Si más adelante regeneras la planificación desde el IFC, se conservan los tipos que corregiste,
pero no los encofrados.

## 10. Reprodúcelo

Pulsa **F5** (la primera vez, responde **Seleccionar actual** para que tu escena sea la principal)
o **F6** para la escena abierta.

- **Barra superior**: **Play / Pause**, el deslizador (arrástralo a cualquier fecha), la casilla
  de velocidad (días de obra por segundo, de 0,1 a 5), **Reset** (vuelve al primer día),
  **Scan Collisions** (solo tiene sentido con izados de grúa, `install`).
- **Cámara**: haz clic en la vista para volar. **W A S D** para moverte, el ratón para mirar,
  **Q / E** para bajar / subir, **Mayús** para ir más rápido, **Esc** para soltar el ratón y volver
  a usar la barra.

## 11. Graba un vídeo

**Elige la cámara.** El vídeo usa la cámara activa de la escena, que no se mueve. Para elegir el
plano, añade una **Camera3D** a la escena, colócala y marca **Current** en el Inspector (asígnale
`runtime/free_look_camera.gd` si además quieres volar con ella). Para planos que se muevan, usa
fotogramas clave de cámara: durante **Start Preview**, lleva el deslizador a una fecha, coloca la
vista 3D del editor en el plano que quieres y pulsa **Capturar cámara**. Cada pulsación añade un
fotograma clave a `camera_track.json`, y el vídeo se desplaza entre ellos.

**Elige la duración.** Selecciona `SequenceManager`, grupo **Movie Maker Mode**, **Movie Duration
Sec** (60 s por defecto para toda la obra).

**Graba desde el editor:**
1. **Proyecto → Configuración del proyecto → Editor → Movie Writer** (activa
   **Configuración avanzada** si no aparece): pon en **Movie File** una ruta **fuera** de la
   carpeta del proyecto, terminada en `.avi` (p. ej. `C:/Videos/obra.avi`). Dentro del proyecto,
   Godot escribiría una imagen por fotograma y las importaría todas. **FPS**: con 30 basta.
2. Activa el botón **Movie Maker** (icono de claqueta, junto a los botones de ejecutar, arriba a la
   derecha) y pulsa **F5**. La ventana reproduce toda la obra sin controles y se cierra sola.

**O desde una terminal** (mismo resultado):
```
godot --path "C:/ruta/al/proyecto" --write-movie "C:/Videos/obra.avi" --fixed-fps 30 res://obra.tscn
```

**Prepáralo para compartir.** El `.avi` es grande (unos 250 MB por minuto). Conviértelo a MP4:
```
ffmpeg -i obra.avi -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart -an obra.mp4
```
Un vídeo de un minuto a 1080p queda en unos 10–15 MB, válido para WhatsApp, Telegram o el correo.
Sube `-crf` (p. ej. 24) para un archivo más pequeño. El tamaño de la ventana (**Configuración del
proyecto → Display → Window → Size**) es el tamaño del vídeo; 1920 × 1080 es el estándar.

## 12. Problemas frecuentes

| Problema | Qué hacer |
|---|---|
| El panel dice **No SequenceManager found in the open scene** | Es normal antes de la primera importación: **Load IFC (4D)** lo crea. Sin IFC, añádelo a mano como en el [apartado 4](#4-prepara-la-escena). |
| **Load IFC (4D)** no hace nada; el panel Salida dice que GDIFC no está instalado | Activa **GDIFC** en Configuración del proyecto → Plugins y reinicia el editor. |
| **OK** está en gris en **Map IFC Properties** | Elige Element ID, Start date, y End date o Duration. |
| Ya no aparece la ventana de propiedades | Se reutilizan las respuestas guardadas. Usa **Edit IFC mapping** para cambiarlas. |
| Al reproducir no se ve nada | Pulsa **Generate 4D Schedule** (o aporta una planificación, apartado 6). Los elementos sin planificación quedan ocultos. |
| **Import Project XML** está en gris | Pulsa antes **Start Preview**. |
| Las fechas importadas han desaparecido | Pulsa **Save to JSON** antes de **Stop Preview**. |
| Una ventana pide asociar tareas de Project | Esos nombres de tarea no son códigos de elemento. Elige la actividad de cada una, o renombra las tareas en Project. |
| Falla la descarga del terreno | Los servidores españoles fallan a veces; la herramienta reintenta cuatro veces. Pulsa de nuevo **Descargar terreno** más tarde. |
| El modelo flota o queda enterrado | **Comprobar posición** y después **Asentar en el suelo**, o escribe la **Altura** correcta y **Aplicar origen**. |
| Los acentos se ven mal (`FormigÃ³n`) en una escena antigua | Vuelve a importar el IFC; la herramienta ya los corrige. |
| El andamio no se desmonta nunca | Mira el [apartado 9](#9-encofrados-y-andamios). |
| Tras grabar aparecen miles de imágenes en el proyecto | El archivo de vídeo estaba dentro del proyecto. Llévalo fuera y borra las imágenes. |
| `ERROR: Condition "p_I->data != this"` al guardar | Un mensaje inofensivo de Godot 4.7.2; ignóralo. |

Para saber cómo funciona todo por dentro, consulta [docs/README.md](docs/README.md) y los
documentos numerados de `docs/` (en inglés).
