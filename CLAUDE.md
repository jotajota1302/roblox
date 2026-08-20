# Proyecto: juegos en Roblox

Investigación de viabilidad + piloto de aprendizaje + desarrollo del primer juego con
intención comercial. **Tiene repo git propio** (https://github.com/jotajota1302/roblox);
el resto de carpetas de `IDEAS/` no. Nunca hagas `git init` en la raíz de `IDEAS/`: hay
`.env` con credenciales de otros proyectos.

## Estructura del repo

Un repo, varios juegos. En la raíz sólo vive lo que sirve a todos:

```
RESEARCH.md MERCADO.md TARGETS.md    Análisis transversal, no de un juego concreto
setup.ps1                            Descarga rojo + stylua + docs oficiales
tools/ creator-docs/                 Compartidos, no versionados
games/
├── coin-island/                     Piloto de aprendizaje (terminado)
└── contrabando/                     Juego con intención comercial
    ├── DISENO.md                    Spec: la autoridad de ese juego
    ├── docs/plans/                  Planes de implementación
    └── src/                         Código
```

**Un juego nuevo es una carpeta nueva en `games/`**, con su propio spec dentro. Lo de la
raíz no se duplica por juego.

## Documentos clave (léelos antes de proponer nada)

Se leen en este orden, cada uno responde a una pregunta:

1. `RESEARCH.md` — **¿se gana dinero?** Economía real, distribución de ingresos, herramientas.
2. `MERCADO.md` — **¿qué formato?** Géneros, saturación, benchmarks de retención.
3. `TARGETS.md` — **¿qué juego?** Anatomía de los éxitos y los 3 conceptos candidatos.
4. `games/contrabando/DISENO.md` — el spec del juego en desarrollo.
5. `games/coin-island/README.md` — el piloto y cómo funciona Roblox por dentro.

## Decisiones tomadas (no reabrir sin preguntar)

- **El criterio de éxito es la retención, no el dinero.** D1 <15% → pivotar. 20-30% → iterar.
  >35% con sesión >8 min → invertir. Todo lo demás es secundario.
- **Target elegido: rutas de contrabando** (target B de `TARGETS.md`). Bucle de progresión
  jugable en solitario + intercepción entre jugadores como capa social.
- **Nada de IA generativa en tiempo de ejecución.** Pierde entre 10 y 60 veces lo que
  ingresa por jugador y empeora con el éxito (`MERCADO.md`, sección 6). La IA se usa en
  producción, nunca en la partida.
- **Nada de narrativa como motor.** Una historia se juega una vez; hunde D1/D7.
- **No reutilizar material de `crime/` ni de `rpg-narrativo/`.** Decisión explícita de JJ:
  quiere que este proyecto se evalúe por sí mismo.
- Iterar rápido y pivotar con datos, no con corazonadas. Los criterios de kill están en
  `TARGETS.md`, sección 7.

## Generación de assets: qué herramienta para qué

| Necesidad | Herramienta | Por qué |
|---|---|---|
| **Modelos 3D** (objetos, vehículos, decorado) | **Cube 3D de Studio** (`generate_mesh` vía MCP) | Devuelve MeshParts ya usables y texturizados, y pasa la moderación de Roblox automáticamente. Probado: un baúl con correas y herrajes en ~1 min con 3.000 triángulos. **Ojo al requisito de publicación, abajo** |

**⚠️ Los meshes NO se ven hasta publicar el place.** Con `game.PlaceId == 0` (place sin
publicar), `AssetService:CreateMeshPartAsync` falla con *"Failed to load mesh asset"* para
**cualquier** id — los generados con Cube 3D y también los públicos de la biblioteca de
Roblox. Los recién generados sólo se ven en la misma sesión de Studio en la que se crearon;
al reabrir, desaparecen. Es la misma trampa que el DataStore.

Consecuencia práctica: **todo lo que dependa de un mesh necesita un respaldo construido con
`Part`**, y el juego tiene que quedar reconocible sin ellos. El decorado de `contrabando`
lo hace: intenta un mesh, y si falla monta el edificio con piezas.

**Y el AVATAR también es un mesh.** Un personaje R15 moderno son ~15 `MeshPart` que Roblox
baja de `assetdelivery.roblox.com`. Sin publicar, el jugador aparece **invisible**: existe,
anda y colisiona, pero no tiene con qué dibujarse. El síntoma es desconcertante —
`WorldToViewportPoint` lo sitúa en el centro de la pantalla, `Transparency` es 0 en todas
sus partes y no hay nada por delante— y sólo se cierra el diagnóstico poniendo una marca de
color en su posición exacta: la marca se ve, el personaje no. La salida es el rig **R6**
(hecho de `Part`), vía `Players:CreateHumanoidModelFromDescription(desc, R6)`. Ver
`games/contrabando/src/server/Avatar.luau`.

**Para ver la experiencia real hay que publicar el place** (puede ser en privado): es lo
único que activa meshes, avatar y DataStore a la vez. Publicar crea contenido en la cuenta
del usuario, así que **lo hace él**, no nosotros: *File → Publish to Roblox As…*
| **Materiales / texturas de superficie** | `generate_material` (MCP) | Genera MaterialVariant nativos |
| **Modelos paramétricos ajustables** | `generate_procedural_model` (MCP) | Primitivas con atributos editables sin regenerar |
| **Miniatura e icono del juego** | **MiniMax** (`image-01`) | Es 2D y es **marketing**: decide el CTR en el Discover, que es el cuello de botella real del proyecto. Estilo saturado y llamativo, no arte de portada |
| **Iconos de inventario y UI** | **MiniMax** | 2D puro. El pipeline del RPG narrativo es transferible |
| **Vídeo promocional (TikTok / Shorts)** | **Grabar gameplay real**, no generar | La gente quiere ver el juego. El vídeo generado aporta poco aquí |

**Momento de hacer arte: cuando D1 lo justifique, no antes.** Durante el prototipo, cubos
de colores. Ponerse con los assets pronto es la forma más común de sentir que se avanza sin
responder a la única pregunta que importa.

## Convenciones

- **Comentarios en español** en este proyecto (a diferencia del RPG narrativo, que van en
  inglés): el código es también material de aprendizaje. Identificadores en inglés.
- **TODO EL TEXTO DEL JUGADOR VIVE EN `src/shared/Strings.luau`** (desde 2026-08-19). Es la
  regla más importante de esta lista, porque es la única que se rompe sin que nadie se entere:
  el juego se tradujo al inglés a mano el 18/08 y esa misma noche se vio castellano en
  pantalla; al inventariar al día siguiente aparecieron NUEVE textos más que el repaso no
  cazó. **No se escribe una cadena en pantalla en ningún otro fichero.** Si hace falta un
  texto nuevo, se añade su clave allí y se pide con `Strings.get("CLAVE", { … })`.
  El idioma de origen es el **inglés**: la masa de Roblox está ahí y la portada se decide en
  un vistazo de Discover, donde el idioma es la primera barrera.
  **Lo que NO se traduce**: los comentarios, los `warn()` de consola, `SelfCheck` y los
  nombres de las pruebas — los lee el desarrollador. Tampoco los nombres de los parámetros
  (`{huecos}`, `{cuantas}`): son código, y el código de esta casa va en castellano.
  **Y los IDS NUNCA se traducen**: `"verde"`, `"ambar"`, `"roja"`, `"barrio"`, `"camuflaje"`,
  `"furgoneta"` son claves que viven en `Palette`, en atributos de piezas, en
  `CONTACTOS_POR_RUTA` y en el DataStore. El texto se DERIVA del id (`"ROUTE_" .. id`), y por
  eso los catálogos ya no guardan ningún `nombre`: dos sitios donde escribir texto es
  exactamente como se colaron los nueve castellanos.
  **El identificador nunca es la etiqueta.** El menú lateral abría su panel comparando
  `abierto == "Skills"`, la misma cadena que pintaba en el botón: traducirla habría dejado el
  menú muerto para siempre. Id por un lado (`"skills"`), etiqueta por otro.
  **El servidor manda claves, no frases** (`Remotes.AVISO` lleva `(clave, args, color)`): el
  idioma es del jugador, y con dos personas de países distintos en la partida el servidor no
  tiene un idioma correcto que elegir.
  **Multiidioma**: no hay que traducir nada a mano. `node scripts/export-locale.js` saca el
  CSV, se sube al portal de localización de Roblox y allí se encienden los idiomas — la
  traducción la hace la plataforma, gratis. Ver `docs/specs/2026-08-19-textos-multiidioma-design.md`.
- Sin dependencias externas salvo necesidad clara.
- El mundo y la interfaz **se generan por código**, no a mano en Studio. Así todo vive en
  git y es revisable en un diff; el `.rbxl` es un artefacto desechable.
- Diseño **móvil primero**: tamaños en Scale con `UISizeConstraint`, contenido desplazable,
  botones de 48px mínimo, y nada en las esquinas inferiores (son del joystick y del botón
  de salto de Roblox). Verificar con la skill `rbx-device-simulator-lua` antes de dar por
  buena cualquier pantalla.

## Flujo de trabajo

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1   # rojo + stylua + docs (todo en ./tools)
cd games\<juego>
..\..\tools\rojo.exe serve                           # y Connect desde el plugin de Studio
```

**Verificación obligatoria antes de dar algo por hecho:**

```powershell
powershell -ExecutionPolicy Bypass -File scriptserificar.ps1   # formato + analisis + build
```

Los tres pasos de golpe, y el del medio es el que faltaba: **`luau-lsp` caza los simbolos
que no existen**. El 20/08 el sistema de senales del cliente llevaba dias muerto porque un
bucle escribia en una tabla borrada al quitar los faroles; `stylua` no lo veia (es formato)
y `rojo build` tampoco (compilaba de sobra). Lo caza el analizador en un segundo, y bloquea
solo con la familia `Unknown global` / `Unknown symbol`, que en un proyecto sano sale a
cero: cualquiera que aparezca es un bug real. Los ~600 avisos de tipos se cuentan y no
bloquean, porque convertirlos en bloqueantes hoy significaria desactivar el paso manana.

Y **probarlo dentro de Studio** con el MCP. Que compile no significa que funcione: el peor
fallo de este proyecto compilaba perfectamente.

### El place se compila SIEMPRE en la carpeta del juego, nunca en un temporal

`games/<juego>/<juego>.rbxl` es **el sitio, y sólo ese**. Está en `.gitignore` (es un
artefacto), pero es el fichero que JJ abre con doble clic para jugar.

Compilar a una carpeta temporal para verificar y dejar el del proyecto sin tocar produce
exactamente el peor resultado posible: **yo verifico una versión y él juega otra**. Ya pasó
— se dio a Play y no aparecía nada de una función terminada y probada hacía una hora,
porque su archivo era hora y media más antiguo. Se pierde la sesión discutiendo un fallo
que no existe.

Corolario: si hay que reabrir Studio para recargar el código (`Stop-Process` + volver a
abrir), se reabre **ese** fichero.

## MCP de Roblox Studio

Activado en scope user. `list_roblox_studios` para el `studio_id`, luego `execute_luau`
(datamodel `Edit` / `Server` / `Client`), `start_stop_play`, `search_game_tree`,
`screen_capture`.

Avisos verificados:

- **`get_console_output` se cuelga y da timeout.** No usarlo; diagnosticar con
  `execute_luau` inspeccionando el estado.
- **`screen_capture` también se cuelga, pero sólo en Play.** En `Edit` responde; con una
  sesión de Play viva se queda colgado los 120 s y acaba en *Request timeout*. Así que
  durante una partida no hay ojos: todo lo visual hay que deducirlo midiendo cotas,
  tamaños y colores de las piezas. Fue así como se cazó que la diana del destino estaba
  enterrada dentro de su losa — comparando topes, no mirando.
- **El `require` del sandbox de `execute_luau` CACHEA entre llamadas.** No es sólo que no
  comparta estado con el servidor: es que una vez cargado un módulo, volver a pedirlo
  devuelve la copia vieja aunque Rojo ya haya sincronizado el fichero nuevo. El síntoma es
  cruel — el `Source` del módulo en el datamodel demuestra que el cambio ESTÁ, y la prueba
  sigue fallando por la línea que acabas de borrar. La salida es clonar la carpeta entera
  (`ReplicatedStorage.Shared:Clone()`) y requerir los módulos de dentro del clon: un
  `Instance` nuevo es una entrada de caché nueva, y clonar la carpeta **entera** —y no el
  módulo suelto— es lo que conserva las rutas relativas (`script.Parent.Parent`) de las que
  cuelga todo.
- **`start_stop_play` se atasca a partir del segundo arranque de la sesión.** El primero
  va; el siguiente se queda colgado más de 120 s, pasa a segundo plano y ya no completa
  nunca -- y a partir de ahí `execute_luau` sólo responde en `Edit`, aunque Studio siga
  vivo y respondiendo (`$p.Responding` en `True`). Ni `TaskStop` ni volver a llamar lo
  desatascan: **la única cura es reiniciar Studio**, y eso le cierra la sesión al
  usuario, así que conviene AGRUPAR todo lo que haya que verificar en una sola pasada de
  Play en vez de hacer stop/start entre cambio y cambio.
- **`require()` dentro de `execute_luau` NO comparte estado con el servidor real** (corre en
  un sandbox aparte). Para verificar hay que actuar sobre el mundo (mover partes, disparar
  remotes) y leer el resultado, no llamar a los módulos.
- Los setters del simulador de dispositivos **fallan en PlayServer**: fijar el dispositivo
  antes de entrar en Play.
- Para medir la interfaz, comparar contra el área real del `ScreenGui`, **nunca** contra
  `Camera.ViewportSize`: con el simulador activo no coinciden (el inset desplaza el origen)
  y salen falsos positivos.
- Y en la misma medición, restar `gui.AbsolutePosition` a la posición de cada hijo. Con
  `ScreenInsets = DeviceSafeInsets` el origen del `ScreenGui` no es (0,0) sino algo como
  (0,−58), así que todo lo colocado arriba parece salirse de pantalla sin estarlo.

## Trampas de Roblox ya pagadas

- **Un `pcall` alrededor de un sistema entero convierte "esta roto" en "se ve raro".**
  `Main.client` llama a cada modulo de interfaz por un `intentar()` que es un pcall con un
  `warn` una vez por sesion -- sensato de uno en uno, porque un fallo pintando el rastro no
  puede costar el HUD. Pero `Senales` reventaba en su primera linea (una tabla borrada al
  quitar los faroles y un bucle que seguia escribiendo en ella), el juego arrancaba igual, y
  lo que se veia era el mundo con **todo encendido a la vez**: las migas de las tres rutas,
  sus detectores, sus dianas y los ocho railes superpuestos. De ahi salieron cuatro quejas
  seguidas --el rail parpadeando, los paquetes que no desaparecen, el minimapa ilegible, "me
  detectan y no hay nadie"-- y ninguna se parecia a la causa. Con `get_console_output`
  colgandose, ese `warn` no lo lee nadie. **El diagnostico es llamar al modulo a mano desde
  `execute_luau` y mirar el error**, y la prevencion es el paso de analisis estatico.
- **Y una sonda que no puede fallar es peor que no tener sonda.** Las dos primeras versiones
  de ese paso daban verde siempre, por motivos opuestos: `2>&1` mataba el script en el
  `[INFO]` de arranque (PowerShell 5.1 envuelve el stderr de un exe nativo en `ErrorRecord`),
  y `2>$null` anunciaba "0 avisos" mientras tiraba las 833 lineas que habia que leer --
  **luau-lsp escribe sus hallazgos por stderr, no por stdout**. Se arregla haciendo la
  redireccion en `cmd`, fuera de PowerShell. Y la unica forma de saber que una sonda sirve es
  **reintroducir el fallo a proposito y comprobar que lo caza**.
- **`DataStoreService:GetDataStore()` LANZA una excepción** si el place no está publicado.
  Llamarlo al cargar un módulo hace que el `require()` reviente y **mata el script entero**:
  juego sin mapa, sin personaje y sin pista del motivo. Todo lo que pueda lanzar va perezoso
  y dentro de `pcall`.
- **`MeshPart.MeshId` NO se puede escribir en tiempo de ejecución.** `Instance.new("MeshPart")`
  seguido de `m.MeshId = "rbxassetid://…"` falla con *"lacking capability NotAccessible"*:
  MeshId sólo se escribe desde Studio o un plugin. En un servidor hay que pedir la pieza a
  `AssetService:CreateMeshPartAsync(meshId)`; sobre el resultado, `TextureID` y `Size` sí se
  asignan con normalidad. Y como esa llamada espera al servidor de assets, **nunca va en el
  camino de arranque**: primero el mundo jugable, el decorado después en otro hilo.
- **El personaje aparece antes de que tu código construya el mundo.** Si generas el mapa por
  código, usa `Players.CharacterAutoLoads = false` durante el arranque.
- Un `require` que falla se propaga: protege los del punto de entrada.
- Los emojis en `TextLabel` suelen salir como `□`. No usarlos.
- **Un `if` de expresión devuelve UN valor y trunca lo que devuelva la función.**
  `local a, b = if cond then nil else f()` deja `b` en `nil` aunque `f` devuelva dos cosas.
  No es un error de sintaxis y no avisa nadie: en `CityBuilder` hacía que cada losa se
  apoyara en la muestra del centro en vez de en el punto alto de su huella, y sólo se vio
  midiendo el mundo ya construido. Si necesitas varios valores, `if` de sentencia.
- **Studio reabre el mundo de la sesión anterior, no el `.rbxl` que acabas de compilar.**
  Al matar Studio queda un `contrabando.rbxl.lock`, y al volver a abrir el fichero Studio
  restaura el documento en memoria: se ven las 7.161 piezas de la ciudad vieja en un place
  cuyo binario ya no las contiene. El síntoma engaña dos veces, porque **el código sí está
  actualizado** (los módulos nuevos aparecen y las pruebas pasan) y sólo el `Workspace` es
  antiguo -- así que parece un fallo del generador. Se descarta comparando el tamaño de dos
  builds, uno con el `.rbxm` escondido: si pesan igual, el place está limpio y el problema
  es Studio. **La cura es borrar el `.lock` antes de abrir.** Es la hermana de la trampa de
  Rojo/Play: en las dos, lo que se mide no es lo que se acaba de escribir.

- **Un rayo desde el cielo se para en la copa de un árbol.** La ciudad del Creator Store
  tiene 2.048 hojas y 2.720 troncos (`Model` llamado `Tree`), así que "el suelo" en un
  parque sale a 80-100 studs de altura y el sitio se descarta por imposible. Hay que seguir
  bajando saltándose el árbol -- y con margen: cuatro rebotes se agotan donde hay dos
  árboles en la misma vertical.
- **Editar mientras Studio está en Play NO llega al juego.** Rojo sincroniza contra el
  datamodel de **Edit**, y una sesión de Play corre sobre el snapshot que se hizo al
  arrancarla. Guardar un fichero con Studio jugando deja el disco, el `.rbxl` y la sesión
  diciendo tres cosas distintas. El síntoma no se parece a un fallo -- `rojo build` dice
  `BUILD OK`, las pruebas pasan, y lo que se está midiendo es el código de antes; así se da
  por bueno un "lo he probado y no cambia nada" sin haberlo probado. **El ciclo correcto es:
  editar, `rojo build`, PARAR el Play, leer el `Source` del módulo en el datamodel `Edit`
  para confirmar que el cambio está, y sólo entonces arrancar y medir.**
- **Cada cosa que se planta cambia el mundo que la siguiente mide.** Si algo se coloca según
  el terreno, el pathfinding o lo que haya alrededor, va **al final** de la construcción. Ya
  se pagó dos veces el mismo día: un rastro de recogibles sembrado antes que los refugios
  acabó marcando un camino que una comisaría cortaba después (19 de 55 piezas fuera de
  alcance), y una rutina que bajaba al suelo lo que flotaba no servía de nada porque el rayo
  encontraba debajo algo que más tarde desaparecía -- el mismo código, movido al final,
  funcionó a la primera.

## Trabajo en paralelo: quién es dueño de qué

**A veces hay más de una sesión trabajando en `contrabando/` a la vez.** El 17/08 hubo dos
y salió caro: tres ciudades superpuestas en el mismo sitio (21.000 piezas donde caben
7.000), el mapa movido de carpeta a mitad de faena, y dos `LEEME.md` afirmando cosas
contrarias sobre qué mapa estaba activo. Nada de eso dio un error: el juego arrancaba.

El reparto, decidido por JJ:

| Zona | Dueño | Qué incluye |
|---|---|---|
| **El mapa** | la sesión del mapa | `mapa/`, `src/server/MapBuilder.luau` y sus documentos |
| **El juego** | la sesión del juego | `CityBuilder`, calor, policía, robo, mercancía, interfaz, `Config`, `shared/` |

**Nadie edita ficheros de la otra zona.** Si necesitas un cambio al otro lado, se pide; no
se hace.

### El único punto de contacto

Hay **dos formas de tener ciudad y no pueden correr a la vez**: el modelo del Creator Store
que Rojo monta desde `mapa/Ciudad.rbxm`, y `MapBuilder`, que la genera por código. Las dos
dejan el mismo contrato — un `Model` llamado `Ciudad` que `CityBuilder` usa de suelo para
sus raycasts — así que se cambia de una a otra **poniendo o quitando el bloque `"Ciudad"`
del `default.project.json`**, y nada más.

`Main.server.luau` sólo llama a `MapBuilder` **si no hay ya una `Ciudad` montada**, así que
manda lo que monte Rojo. Ese guard es lo que impide que vuelvan a superponerse: no lo
quites.

**Activo a 19/08: la retícula propia** (`MapBuilder`), tras tres partidas seguidas con
veredicto negativo cuyo denominador común era el mapa: *no sé hacia dónde tirar*, *el sitio
es feo y confuso* y *no pasa nada por el camino* -- las tres se contestan controlando las
calles. Spec en `games/contrabando/docs/specs/2026-08-19-mapa-propio-design.md`. El plano
vive en `src/shared/Grid.luau` y de él beben `MapBuilder` (planta), `Config` (deriva los
destinos) y `SelfCheck` (verifica). El `.rbxm` sigue en `mapa/` como respaldo, pero volver
a él ya no es gratis: los destinos son cruces que sólo existen en la retícula.

### Antes de tocar nada, `git pull`

Las dos sesiones comparten repo. Guardar encima sin traerse lo del otro tira su trabajo sin
avisar, y ya pasó con el guard de las ciudades.

## Regla de oro

**El bucle antes que el contenido, y los datos antes que el bucle.** Si algo no se puede
medir en D1 o en sesión media, no es una prioridad.
