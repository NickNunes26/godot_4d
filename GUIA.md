# Build4D — Guía de uso

*English version: [GUIDE.md](GUIDE.md).*

Esta guía te lleva desde un proyecto de Godot vacío hasta un modelo 4D de tu obra sobre su
terreno real, y un vídeo de cómo se construye. La primera vez, sigue los apartados en orden. Los
nombres de los botones aparecen tal cual se ven en pantalla: el panel mezcla etiquetas en inglés y
en español.

**La versión corta**, para un IFC georreferenciado cuyos elementos llevan sus fechas: **Load IFC
(4D)** (responde una vez a la ventana de propiedades) → **Start Preview** para revisarlo → guarda
la escena → **F5**. La importación escribe la planificación y trae el terreno, explanado para el
edificio, y el sol; al reproducir se añade la maquinaria. El resto de la guía es para cuando
quieras más.

Contenido: [1. Qué necesitas](#1-qué-necesitas) · [2. Instalación](#2-instalación) ·
[3. Prueba el ejemplo](#3-prueba-el-ejemplo) · [4. Prepara la escena](#4-prepara-la-escena) ·
[5. Importa el modelo](#5-importa-el-modelo-ifc) · [6. Consigue la planificación](#6-consigue-la-planificación) ·
[7. Terreno](#7-el-terreno-y-la-parcela) · [8. Vista previa y edición](#8-vista-previa-y-edición-en-el-editor) ·
[9. Encofrados y andamios](#9-encofrados-y-andamios) · [10. Maquinaria](#10-maquinaria-de-obra) · [11. Reproducir](#11-reprodúcelo) ·
[12. Grabar un vídeo](#12-graba-un-vídeo) · [13. Problemas frecuentes](#13-problemas-frecuentes)

---

## 1. Qué necesitas

- **Godot 4.6 o posterior** (probado con 4.6.2 y 4.7.2), versión estándar (no .NET).
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
deslizador y haz clic en la vista para volar (detalles en el [apartado 11](#11-reprodúcelo)). Si
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
([apartado 12](#12-graba-un-vídeo)).

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
   | **Infer the type from the activity name** | Activada por defecto. La animación de cada actividad se elige por su código y su nombre: *Hormigonado…* / *Formigón…* hormigona, *Mampostería…* se levanta, *Excavación…* excava, *Carpintería…* aparece, etc. (español, gallego, portugués, inglés). No hay que configurar nada más. | — |
   | **Type stated by property** + reglas | Solo si tu modelo ya dice cómo aparece cada elemento (una propiedad cuyos valores son `fill_up`, `build_up`...), o trae valores que una regla puede traducir: *contiene* `hormigón` → `fill_up`. Un tipo indicado así gana al deducido. Si no, deja **(none)**. | No |
   | **Fallback type** | La animación de las actividades que nada de lo anterior decide. | — |

   **OK** sigue en gris hasta que eliges los campos obligatorios. Pulsa **OK**.
3. Los elementos aparecen bajo `SequenceManager` (p. ej. `IFCParts_mimodelo`) y, a la vez, se
   escribe la planificación (`construction_steps.json`, ver el
   [apartado 6](#6-consigue-la-planificación)). Tus respuestas se guardan junto a ella
   (`construction_steps.ifc_profile.json`). Si importas otra vez un modelo del mismo tipo, se
   reutilizan sin preguntar; para cambiarlas, abre el **▾** junto a **Load IFC (4D)** →
   **Edit IFC mapping**.
4. Si el IFC está georreferenciado, el terreno empieza a descargarse solo; mira el
   [apartado 7](#7-el-terreno-y-la-parcela).
5. En una misma escena caben varios IFC del mismo emplazamiento (p. ej. estructura y
   urbanización, o dos calzadas): pulsa **Load IFC (4D)** otra vez para cada uno. Cada uno se
   coloca junto al primero según su georreferencia, y sus actividades se añaden a la
   planificación (lo que ya había no cambia).

Los tipos de animación son: `fill_up` (hormigonado, se llena desde abajo), `build_up` (se levanta
desde su base, p. ej. mampostería, andamios), `drop_in` (baja hasta su sitio desde unos metros
más arriba, pieza a pieza), `sink_down` (se hunde y desaparece, p. ej. tierra excavada),
`fade_in`, `fade_out` (p. ej. desbroce), `scale_up` (crece desde su base, p. ej. plantaciones),
`rise_up` (todo el elemento sube desde 10 m por debajo), `install` (lo coloca una grúa, y se
comprueba si choca).

Qué elige, a grandes rasgos, la deducción por el nombre: la demolición y el desbroce
desaparecen; la excavación y la tierra vegetal se hunden; el hormigón, forjados, zapatas y pilares
se hormigonan; la mampostería, muros, chimeneas y andamios se levantan; las piezas de cantería,
prefabricados, estructuras de acero y madera, la forja y el alumbrado bajan pieza a pieza; la
cubierta, carpinterías, acabados e instalaciones aparecen; las plantaciones crecen. Nunca elige
`install`: un izado con grúa es una decisión de obra, no del nombre.

## 6. Consigue la planificación

Elige el caso que corresponde a lo que tienes.

### A. Solo el IFC (las fechas están en el modelo)

No hay que hacer nada: **Load IFC (4D)** escribe `construction_steps.json`, con una actividad por
cada Element ID. Los elementos sin fechas (el terreno existente, por ejemplo) quedan visibles
desde el primer día.

Si más adelante cambias las propiedades elegidas o las fechas del modelo, **▾** → **Generate 4D
Schedule** reescribe la planificación desde el IFC. Conserva los tipos que corregiste, pero vuelve
a tomar todas las fechas del IFC (se pierden las importadas de Project) y quita los encofrados, así
que úsalo solo en ese caso.

### B. El IFC y una planificación de Microsoft Project (XML)

1. **Load IFC (4D)** como arriba: escribe la planificación. La importación del XML actualiza
   actividades; no las crea.
2. Pulsa **Importar…** y elige el `.xml` (la vista previa se inicia sola). Cada tarea se asocia a
   una actividad por su **nombre**, así que en Project los nombres de las tareas deben ser los
   códigos de los elementos (p. ej. `C04_Limpeza`). Las tareas resumen se ignoran. Si alguna tarea
   no coincide, una ventana te pregunta a qué actividad corresponde.
3. Pulsa **Save to JSON** (o **Stop Preview** y responde **Guardar**).

La importación trae las fechas y los vínculos entre tareas (predecesoras y retrasos). También fija
el tipo de animación de cada acción si el plan tiene una columna de texto personalizada (p. ej.
*Texto2*, llamada *Tipo de animación*) con nombres de tipo (`fill_up`, `rise_up`...): la columna se
reconoce por sus valores, se llame como se llame. Para que los Pilares sean un hormigonado, escribe
`fill_up` en esa columna para sus tareas en Project e impórtalo de nuevo.

### C. Ya tienes un `construction_steps.json`

Copia `construction_steps.json` (y `construction_steps.ifc_profile.json` si lo tienes) en la raíz
del proyecto **antes** de cargar el IFC. **Load IFC (4D)** conserva tu planificación: solo añade
actividades del modelo que ninguna de las tuyas cubre. No uses **▾** → **Generate 4D Schedule**:
la sustituiría. Con el perfil presente, **Load IFC (4D)** ni siquiera pregunta por las propiedades.

## 7. El terreno y la parcela

Todo esto está en la sección **Terreno** del panel.

**Automático.** Cuando el IFC lleva su posición en la Tierra, el terreno se descarga justo después
de importar: elevación y ortofotos (España peninsular y Baleares: 5 m y 25 cm; en el resto del
mundo, solo elevación). Tarda de unos segundos a un minuto y se guarda en `res://terrain/`. Después,
por sí solo: un modelo sin altura conocida se apoya en el suelo; el terreno se **explana para el
edificio** si la planificación tiene movimiento de tierras (más abajo); y se añade un **sol** que
sigue la fecha de la planificación (GeoSun) si la escena no tiene luz propia. La línea de estado
dice si el modelo flota o queda enterrado.

**Si el modelo no está georreferenciado**, el panel muestra los campos del origen: escribe el
centro del modelo en **Lat, lon** (por ejemplo, copiado de un mapa web), deja **Altura** vacía si
no la conoces, gira el modelo con **Giro °** si hace falta y pulsa **Aplicar origen**: el terreno se
descarga. Sin altura, el modelo se apoya en el suelo. En un modelo georreferenciado los mismos
campos están bajo **▸ Cambiar origen**, para corregir una posición equivocada.

| Control | Para qué sirve |
|---|---|
| **Descargar terreno** | Descargar / regenerar ahora (mientras descarga, en su lugar aparece **Cancelar**) |
| **Nivelar para edificio** | Terreno explanado para el edificio (más abajo); desmárcalo para el terreno natural |
| **▸ Más opciones** → lista de tamaño | **Reducido (2 km)**, **Estándar (4,2 km)**, **Amplio (8 km)** de terreno alrededor del modelo |
| **▸ Más opciones** → **Al importar IFC** | Descargar automáticamente tras importar (activado por defecto) |
| **▸ Más opciones** → **Texturas cercanas** | Texturas de suelo detalladas cerca de la cámara (~15 MB, una vez) |
| **▸ Más opciones** → **Archivos propios…** | Usar tu propia elevación `.asc` y fotos JPG/PNG con archivo de georreferencia |
| **▸ Más opciones** → **Asentar en el suelo** | Sube o baja el modelo hasta que toque el suelo |

Para quitar el terreno, borra el nodo **Terrain** en el panel Escena (los archivos descargados se
conservan).

**Explanación para un edificio.** El terreno natural sirve para un puente; un edificio se apoya
en un terreno explanado. **Nivelar para edificio** crea una plataforma bajo el modelo y una
excavación hasta las zapatas, y las asocia a las actividades de movimiento de tierras de tu
planificación (retirada de tierra vegetal, excavación...), de modo que el terreno cambia en esas
fechas. Se marca solo la primera vez que se crea el terreno para una planificación con movimiento
de tierras; desmárcalo para el terreno natural. Para ajustarlo, selecciona el nodo **Terrain**:
**Platforms** en el Inspector tiene cada plataforma (contorno, cota, talud, actividades), y
**Levelling from the model** tiene **Level Slope** (pendiente del talud, 1,5 = 1,5 m en horizontal
por cada metro de altura) y **Level Margin** (espacio alrededor del modelo); desmarca y vuelve a
marcar **Nivelar para edificio** para aplicar esos dos.

**Créditos.** Los datos del terreno deben citarse allí donde se muestren. El crédito aparece en el
panel, y los vídeos grabados con la herramienta lo incluyen automáticamente. Para España:
*© Instituto Geográfico Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)*.

## 8. Vista previa y edición en el editor

1. Pulsa **Start Preview** (el mismo botón pasa a decir **Stop Preview**). Aparece una línea de
   tiempo en el panel: arrastra su deslizador y la vista 3D muestra la obra en esa fecha. Las
   herramientas de planificación de debajo solo aparecen con la vista previa activa. **No guardes
   la escena con la vista previa activa.**
2. El **Schedule Inspector** muestra todas las actividades. En cada fila puedes cambiar **Tipo**
   (la animación), **Fecha Inicio**, **Duración (días)**, **Fecha Fin**, **Unidades/Día**,
   **Encofrado** y **Días vertido** (apartado 9), **Depende De** (la actividad a la que espera) y
   **Retraso (días)**, y borrar la fila (**✕**). **Ancla** decide cuál de inicio / duración / fin se
   mantiene al editar los demás. Cada cambio se ve en la vista 3D un momento después.
3. **Save to JSON** guarda tus cambios (está en gris cuando no hay nada nuevo que guardar).
4. **Exportar…** escribe la planificación para Microsoft Project (`.xml`) o Excel (`.csv`): elige
   el tipo en la ventana de archivo. **Importar…** lee cualquiera de los dos.
5. **Auto types** pone el **Tipo** y la cadencia de cada fila según el nombre de la actividad,
   igual que la importación (útil para una planificación que vino de CSV, de Project XML o de una
   versión anterior); el panel Output lista cada cambio, y las filas cuyo nombre no reconoce no se
   tocan.
6. Al terminar, pulsa **Stop Preview**. Si hay cambios sin guardar, pregunta: **Guardar** los
   guarda, **Descartar** los tira, **Cancelar** sigue con la vista previa. Todos los elementos
   vuelven a como estaba guardada la escena. Después, guarda la escena.

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
  3. De vuelta en el panel, pulsa **Stop Preview** y otra vez **Start Preview**: la vista previa
     vuelve a leer el archivo.

Este procedimiento es provisional: los andamios usan el mecanismo de encofrado del hormigón,
sirven a una sola actividad, requieren la edición del JSON de arriba y se pierden al regenerar.
Está prevista una revisión a fondo: ver [docs/12_FUTURE_WORK.md](docs/12_FUTURE_WORK.md).

Si más adelante usas **▾** → **Generate 4D Schedule**, se conservan los tipos que corregiste, pero
no los encofrados. Cargar otro IFC no los toca.

## 10. Maquinaria de obra

Al reproducir aparece la maquinaria de la obra sin configurar nada: una **excavadora** cargando un
**camión** en la excavación durante el movimiento de tierras, una **grúa torre** que se monta antes
de la estructura, baja las piezas de piedra con el gancho y se desmonta después de la cubierta, y
una **grúa autopropulsada** para los izados que la grúa torre no puede hacer (fuera de su alcance o
cuando ya se ha ido). Entran y salen con las actividades, leídas de sus nombres igual que los tipos
de animación (**Auto types**, apartado 8): "Excavación" trae la excavadora, "Hormigonado",
"Mampostería", "Sillería"... mantienen la grúa en obra y la cubierta la termina.

- **Para verlas y moverlas en el editor**, pulsa **Maquinaria** (junto a **Load IFC (4D)**).
  Aparece un nodo **SiteEquipment** con dos marcadores, **TowerCraneSite** y **ExcavatorSite**, en
  las posiciones propuestas: mueve o gira un marcador y la máquina lo sigue. Selecciona
  **SiteEquipment** para cambiar **Tower Height** (del suelo a la pluma) y **Jib Length** (0 =
  automático), los días de montaje (**Erect Days**) o desactivar una máquina. Guarda la escena para
  conservarlo. Si vuelves a pulsar **Maquinaria**, propone posiciones nuevas (antes detiene la
  vista previa, preguntando por los cambios sin guardar).
- **La grúa autopropulsada** se coloca en cada izado junto a las piezas, así que no tiene marcador.
- **Si la escena ya tiene una grúa tuya**, no se añade la grúa torre.
- **La excavadora está a escala**: una Caterpillar 320 construida con las medidas publicadas por
  el fabricante, que llega tan lejos y tan hondo como la real (`equipment/specs/`).
- **Sin maquinaria**: selecciona el SequenceManager y desmarca **Auto Equipment** (y borra
  SiteEquipment si lo añadiste).
- Las máquinas son solo visuales: no se comprueban colisiones con ellas ni aparecen en la
  planificación.

## 11. Reprodúcelo

Pulsa **F5** (la primera vez, responde **Seleccionar actual** para que tu escena sea la principal)
o **F6** para la escena abierta.

- **Barra superior**: **Play / Pause**, el deslizador (arrástralo a cualquier fecha), la casilla
  de velocidad (días de obra por segundo, de 0,1 a 5), **Reset** (vuelve al primer día).
- **Los choques** (solo con izados de grúa, `install`) se buscan solos al empezar: las fechas con
  alguno se marcan en rojo en el deslizador (pasa el ratón para ver la pareja), el panel Output los
  lista y la reproducción se detiene en cada uno. Una pieza izada choca cuando atraviesa algo ya
  construido en su camino. Tocar o solaparse con aquello sobre lo que
  apoya *en el modelo terminado* no es un choque, ni rozar a menos de 2 cm. Las piezas de una
  actividad se colocan de abajo arriba, así que un choque que queda suele indicar que la actividad
  está planificada después de lo que tiene encima (p. ej. recercados que siguen colocándose cuando
  la cornisa de encima ya está puesta).
- **Cámara**: haz clic en la vista para volar. **W A S D** para moverte, el ratón para mirar,
  **Q / E** para bajar / subir, **Mayús** para ir más rápido, **Esc** para soltar el ratón y volver
  a usar la barra.

## 12. Graba un vídeo

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

## 13. Problemas frecuentes

| Problema | Qué hacer |
|---|---|
| El panel dice **No SequenceManager found in the open scene** | Es normal antes de la primera importación: **Load IFC (4D)** lo crea. Sin IFC, añádelo a mano como en el [apartado 4](#4-prepara-la-escena). |
| **Load IFC (4D)** no hace nada; el panel Salida dice que GDIFC no está instalado | Activa **GDIFC** en Configuración del proyecto → Plugins y reinicia el editor. |
| **OK** está en gris en **Map IFC Properties** | Elige Element ID, Start date, y End date o Duration. |
| Ya no aparece la ventana de propiedades | Se reutilizan las respuestas guardadas. Usa **▾** → **Edit IFC mapping** para cambiarlas. |
| Al reproducir no se ve nada | Los elementos sin actividad en la planificación quedan ocultos. Mira el panel Output tras **Load IFC (4D)**; si no se pudo escribir la planificación, usa **▾** → **Generate 4D Schedule**. |
| No encuentro el Schedule Inspector, **Save to JSON** ni **Encofrado** | Solo aparecen con la vista previa activa: pulsa **Start Preview**. |
| **Importar…** / **Start Preview** están en gris | Aún no hay SequenceManager: primero **Load IFC (4D)**. |
| Las fechas importadas han desaparecido | No se guardaron: responde **Guardar** al detener la vista previa, o pulsa **Save to JSON**. |
| Una ventana pide asociar tareas de Project | Esos nombres de tarea no son códigos de elemento. Elige la actividad de cada una, o renombra las tareas en Project. |
| Falla la descarga del terreno | Los servidores españoles fallan a veces; la herramienta lo intenta cuatro veces. Pulsa de nuevo **Descargar terreno** más tarde. |
| El modelo flota o queda enterrado | La línea de estado tras la descarga lo indica. **▸ Más opciones** → **Asentar en el suelo**, o **▸ Cambiar origen**, escribe la **Altura** correcta y **Aplicar origen**. |
| Los acentos se ven mal (`FormigÃ³n`) en una escena antigua | Vuelve a importar el IFC; la herramienta ya los corrige. |
| El andamio no se desmonta nunca | Mira el [apartado 9](#9-encofrados-y-andamios). |
| Tras grabar aparecen miles de imágenes en el proyecto | El archivo de vídeo estaba dentro del proyecto. Llévalo fuera y borra las imágenes. |
| `ERROR: Condition "p_I->data != this"` al guardar | Un mensaje inofensivo de Godot 4.7.2; ignóralo. |

Para saber cómo funciona todo por dentro, consulta [docs/README.md](docs/README.md) y los
documentos numerados de `docs/` (en inglés).
