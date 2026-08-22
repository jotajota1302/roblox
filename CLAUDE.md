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
powershell -ExecutionPolicy Bypass -File scripts\verificar.ps1   # formato + analisis + build + 1.259 pruebas
```

Cuatro pasos de golpe, y el segundo es el que faltaba primero: **`luau-lsp` caza los
simbolos que no existen**. El 20/08 el sistema de senales del cliente llevaba dias muerto porque un
bucle escribia en una tabla borrada al quitar los faroles; `stylua` no lo veia (es formato)
y `rojo build` tampoco (compilaba de sobra). Lo caza el analizador en un segundo, y bloquea
solo con la familia `Unknown global` / `Unknown symbol`, que en un proyecto sano sale a
cero: cualquiera que aparezca es un bug real. Los ~600 avisos de tipos se cuentan y no
bloquean, porque convertirlos en bloqueantes hoy significaria desactivar el paso manana.

**Y el paso 4 (21/08) corre las pruebas SIN Studio.** Hasta entonces las 1.259 pruebas
puras solo se podian lanzar dentro de Studio por MCP, asi que en la practica
`verificar.ps1` daba «TODO OK» habiendo comprobado formato, simbolos y compilacion --
y ninguna regla del juego. Se puede: `shared/` es puro por diseno y `tools/luau.exe`
ejecuta Luau de verdad; lo unico que hacia falta era darle cuatro tipos de Roblox
(Vector3, Color3, CFrame, Random) y un arbol de modulos que responda a `script.Parent`.
Vive en `scripts/banco.js` (+ `scripts/banco/`), y el CLI de Luau no tiene `io`, asi
que las fuentes se **embeben** en el fichero que se ejecuta.

Y su hermano, **para el mapa**:

```powershell
node scripts\mundo.js     # construye la ciudad en memoria y le pasa las sondas
```

Ejecuta `MapBuilder.buildCiudad` contra un `Instance` de mentira y mide lo que sale:
cuantas piezas, si algo del mapa pisa el carril, si alguna manzana se queda vacia y si
hay **caras coplanares** -- el parpadeo, que es el defecto que este mapa lleva pagando
desde que existe. Dos segundos, y por eso se puede mirar en cada cambio. No entra en
`verificar.ps1` a proposito: depende de un `Instance` simulado y es mas fragil.

**Ninguna de las dos sustituye a `SelfCheck`**, que mide el mundo de verdad --con
raycasts, suelo, pathfinding y todo lo que `CityBuilder` planta encima-- y sigue
necesitando una partida. Aqui se comprueba lo que el codigo DICE; alli, lo que sale.

Y las dos se probaron reintroduciendo un fallo a proposito, que es lo unico que
demuestra que una sonda sirve: se metio un uso repetido en el plano (la bateria lo
canto) y una nave desbordando la manzana (la sonda del mundo saco las tres piezas
sobre el carril, con sus coordenadas).

Despues de todo eso, **probarlo dentro de Studio** con el MCP. Que compile y pase las
pruebas no significa que funcione: el peor fallo de este proyecto compilaba
perfectamente.

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

## Sincronizar codigo sin plugin y sin dialogos

**Cada llamada del MCP a Studio le pide permiso al usuario**, y reabrir Studio cuesta
varias: `list_roblox_studios`, `get_studio_state`, comprobar que el codigo llego... El
20/08 JJ lo corto en seco --*"no puedo estar aprobando cada conexion que haces con el
Studio"*-- y tenia razon: casi todas esas llamadas eran para resolver "?tiene Studio mi
codigo?", que ahora se contesta de una vez.

```powershell
node scripts\sync-server.js          # se queda escuchando en el 34873
```

Y desde el MCP, en el datamodel **Edit**, se ejecuta `scripts/sync.luau`: pide la lista
por HTTP, la compara modulo a modulo y escribe solo los `Source` que han cambiado. La
correspondencia fichero -> instancia sale del `sourcemap` que genera el propio Rojo, asi
que es exactamente la que usaria su plugin.

Ventajas sobre reabrir Studio: **una sola llamada MCP**, sin `Connect` que aprobar, sin
matar el proceso, sin borrar el `.lock` y sin cerrarle la partida al usuario. El informe
dice que modulos se movieron, y un "0 actualizados" cuando esperabas uno es la senal de
que estas mirando el sitio equivocado -- que aqui ya ha costado sesiones enteras.

Sigue valiendo la regla de siempre: **en Play no sirve de nada**. Una sesion de Play corre
sobre el snapshot que se hizo al arrancarla, asi que hay que parar, sincronizar y arrancar.

## MCP de Roblox Studio

Activado en scope user. `list_roblox_studios` para el `studio_id`, luego `execute_luau`
(datamodel `Edit` / `Server` / `Client`), `start_stop_play`, `search_game_tree`,
`screen_capture`.

Avisos verificados:

- **`get_console_output` se cuelga y da timeout.** No usarlo -- pero la consola NO
  está perdida: `game:GetService("LogService"):GetLogHistory()` desde `execute_luau`
  devuelve los mensajes de ese datamodel, y filtrando por `messageType ~=
  MessageOutput` salen los `warn` y los errores. Es lo que le faltaba al `intentar()`
  del cliente: sus avisos se escribían y no los leía nadie. El 21/08 esa llamada
  contestó en un segundo *"no se pudo construir RoutePicker: invalid argument #1 to
  'insert' (table expected, got number)"* -- una variable de módulo con el mismo
  nombre que el índice de un bucle, que llevaba media hora manifestándose como "el
  selector de ruta ya no aparece" sin una sola pista. Cuando eso no baste,
  diagnosticar con `execute_luau` inspeccionando el estado.
- **Un `Sink` que llega a mitad de una pulsacion se come la mitad que apaga.** Las
  flechas se enlazaron con `ContextActionService` y `Sink` para navegar los menus, y JJ
  lo probo en un minuto: *"funciona, pero se queda dando vueltas el personaje"*. En
  Roblox las flechas izquierda y derecha **giran la camara** (`RbxCameraKeypress`), y si
  una ya estaba pulsada cuando se abrio el panel, el `Begin` le habia llegado al control
  de Roblox y el `End` ya no: se quedaba creyendo que la tecla seguia apretada. El
  sintoma no se parece a la causa -- parece un fallo del giro, y es un fallo del enlace.
  **La cura es devolver `Pass` en todo lo que no sea `Begin`**: el `End` llega al control,
  el que estuviera girando para, y el `Begin` sigue sin llegar -- o sea que la flecha
  navega el menu y no toca la camara. Una linea. Tambien hace falta
  `BindActionAtPriority` con 3000 en vez de `BindAction`, porque la prioridad media es
  donde viven la camara y el movimiento y ahi gana el ultimo que se enlazo, o sea la
  suerte.

  **Y LA PRIMERA CURA FUE PEOR QUE LA ENFERMEDAD**, que es la mitad de la leccion. Se
  apago el control entero con `PlayerModule:GetControls():Disable()` mientras hubiera un
  panel abierto: curaba el giro y JJ contesto *"se queda enganchado despues de volver de
  la primera entrega"* -- el bucle del cliente abre y cierra la capa del selector en CADA
  VUELTA, unas treinta veces por segundo, asi que el par Disable/Enable se disparaba sin
  parar y bastaba con que uno fallara para dejar al jugador sin poder andar.
  **Si la cura puede dejar el juego inservible y el fallo solo molesta, la cura esta mal
  elegida.** Quitarle el control al jugador es de las pocas cosas que este cliente puede
  hacer para romper la partida entera: no es sitio para arreglar un enlace de teclas.
  Lo que quedo en su lugar es una red proporcionada -- una capa cuya pantalla ya no esta
  `Enabled` se cae sola de la pila-- y si esa se equivoca, lo peor que pasa es que una
  flecha vuelva a girar la camara.

- **`user_keyboard_input` solo entrega teclas si la VENTANA de Studio tiene el foco del
  sistema.** No da error --contesta `Success`-- y simplemente no llega nada cuando esta
  detras: medido el 22/08 con un espia de `ContextActionService` a prioridad 9000 y un
  `UserInputService.InputBegan` crudo, los dos vacios. Y luego, con el usuario delante de
  la ventana, el MISMO espia recogio `Left Left Left Left Up Right M` -- las suyas y las
  mias. En cuanto volvio a segundo plano, vacio otra vez.
  Consecuencia practica, y es dura: **mientras se trabaja por MCP, el teclado no se puede
  verificar** -- justo cuando estas midiendo, la ventana esta detras. Hay dos salidas y
  las dos hay que usarlas: pedirle al usuario que deje la ventana delante un minuto (pero
  si esta delante, lo prueba el en cinco segundos), y sobre todo **sacar lo que se puede
  probar a un modulo puro**: la eleccion de "a que boton lleva esta flecha" vive en
  `shared/Nav.luau` con catorce pruebas, y lo que queda en `Pad` es enlazar teclas.
  OJO CON EL FALSO POSITIVO que dio esto: `GuiService.SelectedObject` habia cambiado
  despues de mandar una tecla, y parecia que habia llegado. Lo habia movido mi propio
  `Pad.abrir` desde el sandbox. Si la tecla no aparece en un espia crudo, no llego.

- **`screen_capture` también se cuelga, pero sólo en Play.** En `Edit` responde; con una
  sesión de Play viva se queda colgado los 120 s y acaba en *Request timeout*. Así que
  durante una partida no hay ojos: todo lo visual hay que deducirlo midiendo cotas,
  tamaños y colores de las piezas. Fue así como se cazó que la diana del destino estaba
  enterrada dentro de su losa — comparando topes, no mirando.
- **Y ese sandbox no ve los datos que el servidor decide AL ARRANCAR.** Es la otra
  cara de lo mismo y se paga aparte: desde que los destinos de las rutas se sortean
  al empezar la partida (`Destinations.luau`), `ruta.destino` es un dato de
  ejecución que vive en la copia de `Config` **del servidor**. Un `require` desde
  `execute_luau` devuelve un módulo recién ejecutado, así que ahí los destinos son
  los de diseño. Lanzar `SelfCheck` por el MCP medía el mundo contra caminos que no
  existían: *"sólo 4 de 7 migas al alcance"*, *"un alijo cae sobre una ruta"*, y
  rotaban de ruta en cada partida. Media sesión persiguiendo fantasmas.
  La firma que lo delata: **las cosas del mundo están de acuerdo entre sí y el único
  que discrepa es el dato** -- las migas y su casa de entrega, las dos al oeste, y
  `ruta.destino` diciendo el este. Se confirma leyendo el `print` de arranque con
  `LogService:GetLogHistory()` y comparándolo con lo que devuelve el módulo: si el
  log dice una cosa y el `require` otra, estás en el sandbox.
  La cura no es parchear la sonda caso por caso: es que **la sonda lea el mundo**.
  `CityBuilder` planta una losa `Destino_<ruta>` en el sitio de verdad, y `SelfCheck`
  se trae de ahí los tres destinos antes de empezar. Una sonda mide lo que se
  construyó.

- **El `require` del sandbox de `execute_luau` CACHEA entre llamadas.** No es sólo que no
  comparta estado con el servidor: es que una vez cargado un módulo, volver a pedirlo
  devuelve la copia vieja aunque Rojo ya haya sincronizado el fichero nuevo. El síntoma es
  cruel — el `Source` del módulo en el datamodel demuestra que el cambio ESTÁ, y la prueba
  sigue fallando por la línea que acabas de borrar. La salida es clonar la carpeta entera
  (`ReplicatedStorage.Shared:Clone()`) y requerir los módulos de dentro del clon: un
  `Instance` nuevo es una entrada de caché nueva, y clonar la carpeta **entera** —y no el
  módulo suelto— es lo que conserva las rutas relativas (`script.Parent.Parent`) de las que
  cuelga todo.
- **Y clonar `Server` para esquivar esa cache ARRANCA EL JUEGO OTRA VEZ.** El truco
  documentado arriba --clonar la carpeta entera y requerir de dentro-- vale para
  `Shared`, que son modulos puros, y es una trampa en `ServerScriptService.Server`:
  ahi vive `Main`, que es un **`Script`**, no un `ModuleScript`. Parentar el clon lo
  ejecuta, y entonces hay dos servidores construyendo el mismo mundo.
  El sintoma no se parece a la causa: `SelfCheck` empezo a cantar *"nadie tiene medio
  taller dentro de casa -- invadidas: verde(12)"*, y los doce invasores eran **las
  propias piezas de la casa**, duplicadas una a una en la misma coordenada. Media hora
  buscando por que un `OverlapParams` no filtraba lo que se le decia; el filtro estaba
  perfecto, lo que habia eran DOS casas superpuestas. Y una casa de entrega duplicada
  son ocho pares de caras coplanares en el sitio que mas se visita.
  Lo que lo delata: la partida anterior, medida sin clonar, daba verde en la misma
  sonda. **Si un fallo aparece justo despues de cambiar COMO mides, sospecha de la
  medida antes que del mundo.**
  Al clonar `Server`, borrar los `Script` del clon antes de parentarlo -- o mejor,
  reiniciar el Play, que ademas es lo unico que garantiza que el mundo sea el de verdad.

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

- **«No se puede comprobar sin mirar la pantalla» casi siempre es mentira, y sale caro
  creérselo.** El cono de visión del ladrón se dibujó con siete barras radiando desde
  los pies porque un sector en planta «obliga a rotaciones que no se pueden verificar»
  — y duró un día: *«el rayo ese que sale del ladrón es muy cutre»*. Hay **dos** formas
  de mirar, y hacían falta las dos: `screen_capture` **sí responde en `Edit`** (sólo se
  cuelga en Play), y la forma de algo en el suelo se mide **lanzando una rejilla de
  rayos hacia abajo** y anotando hasta dónde llega en cada ángulo. La captura enseñó
  que el primer abanico de cuñas salía en estrella de tres puntas; los rayos midieron
  lo que la captura no ve — que además tenía fugas hasta los 100°, y una rendija de
  grosor cero justo a 0° por redondeo entre dos tajadas (se cierra solapándolas un 1%).
  Y para colocar una `WedgePart` **no se deduce su orientación, se sonda**: ocupa el
  triángulo con el ángulo recto en `(Y=-alto/2, Z=+fondo/2)`.

- **Un remote que sólo nace cuando alguien lo usa es un interbloqueo dormido.** Los
  `RemoteEvent` se creaban al vuelo en el primer `Remotes.event(...)`, y funcionaba por
  casualidad: casi todos se tocan al arrancar. `Impulso` no — sólo se usa al recoger,
  así que no existía hasta la primera recogida de la partida, y el cliente lo pide con
  `WaitForChild`. Eso no da error: da un hilo del cliente esperando para siempre. Lo
  cazó `SelfCheck`; la cura es crearlos **todos** al arrancar `Main.server`, recorriendo
  el propio módulo `Remotes`, en vez de depender de la suerte.

- **Un número absoluto no sobrevive a que cambie aquello que mide.** `RASTRO_PASO` (22
  studs entre migas) se calibró con la ruta verde en 558 studs. El 19/08 la verde se
  acortó a 147 y el paso se quedó donde estaba: con el corredor útil en 89 studs, la
  **primera ruta del juego se quedó con UNA sola miga** — ni enseñaba el sistema ni
  pagaba las cuatro doradas que su tabla reparte, porque las doradas se reparten sobre
  las que existen. Ninguna sonda lo vio: contaban piezas plantadas en total, no piezas
  **por ruta**. Se arregla calculando cuántas caben y repartiéndolas a partes iguales,
  con un mínimo por ruta.

- **Un rayo desde el cielo se para en la copa de un árbol.** La ciudad del Creator Store
  tiene 2.048 hojas y 2.720 troncos (`Model` llamado `Tree`), así que "el suelo" en un
  parque sale a 80-100 studs de altura y el sitio se descarta por imposible. Hay que seguir
  bajando saltándose el árbol -- y con margen: cuatro rebotes se agotan donde hay dos
  árboles en la misma vertical.
- **Una sonda que mide algo PARECIDO a lo que se construyo es peor que una que no
  mide nada.** El rastro de migas se siembra sobre `{ALMACEN} ++ porCalles(salida,
  destino)` y la sonda lo comprobaba contra `porCalles(salida, destino)` a secas: dos
  caminos casi iguales. Mientras la ruta verde fue una recta corta dio verde siempre;
  el dia que un destino sorteado la alargo, empezo a cantar *"solo 4 de 7 al alcance"*
  senalando migas que estaban exactamente donde tenian que estar. Y la reaccion
  natural --cambiar el sembrado para que coincida con la sonda-- **lo empeoro**: sacar
  el almacen del camino descuadro el reparto entero, porque `Contacts.rastro`
  descuenta `ZONA_SEGURA_RADIO` DESDE EL PRIMER PUNTO contando con que ese punto es el
  almacen. Medido: de 4 de 7 a 2 de 5. **Se arregla en la sonda, no en el mundo**: la
  sonda se adapta a lo que hay, y si el camino sembrado cambia, cambia con el.

- **UNA pieza anclada soldada a un personaje ancla el ENSAMBLAJE ENTERO.** El cono de
  visión del ladrón se dibuja con `Cone.piezas`, compartido con la cámara -- y las
  cuñas nacían `Anchored = true`, que es lo correcto para una cámara y letal para
  alguien que anda. Ocho cuñas soldadas a la raíz dejaban al ladrón clavado en el
  sitio: estado `FallingDown`, `FloorMaterial = Air`, y `MoveTo` sin ningún efecto.
  **Salían las patrullas, se veían en el minimapa, y ninguna se movía jamás** -- de
  ahí *"me detectan y no hay nadie"*, que se llevaba meses arrastrando y parecía un
  problema de la detección.
  Se cazó midiendo el `Humanoid` de una patrulla (`GetState`, `FloorMaterial`, cuántas
  de sus piezas están ancladas) y se confirmó **desanclándolas en vivo**: pasaron a
  `Running`, tocaron suelo y anduvieron 14 studs en cuatro segundos. Reintroducir el
  fallo a propósito y ver que se cura es la única prueba que vale.
  Dos defensas, porque el fallo no es del cono sino de vestir a un personaje: el
  parámetro `anclado` de `Cone.piezas` **no tiene valor por defecto** (quien dibuje un
  cono contesta "esto se mueve o no"), y `crearAgente` desancla lo que le hayan puesto
  encima antes de soltarlo a la calle.

- **Un agujero en el suelo no mata: te deja andando POR DEBAJO del mapa.** *"Cuando
  llego al medio desaparezco"* (JJ) se buscó leyendo el código --nada de lo que mueve
  al jugador estaba sin acotar-- y con una rejilla de raycasts que dio verde. El
  hallazgo llegó midiendo la posición del jugador en una prueba de otra cosa: `Y =
  -56`. No se había ido a ninguna parte; estaba tumbado sobre la **red de seguridad
  invisible** que hay bajo la ciudad para que Roblox no destruya a nadie a -500.
  Vivo, andando por una plancha que no se ve, y desde arriba es una desaparición.
  Tres lecciones, y las tres se pagaron enteras:
    · **La rejilla de sondeo tiene que ser más fina que un personaje.** El primer
      barrido fue de 20 studs y dio cero huecos; a 4 salieron **1.444** de 23.103.
      Un personaje mide 2 de ancho: por una rendija de 12 se cuela y una rejilla de
      20 no la ve. Y el reparto era la mitad del diagnóstico -- cero en las calles,
      cero en el recinto, los 1.444 en la tierra de nadie que los rodea.
    · **La causa era un número que no se movió con el mapa.** El suelo base salía de
      `Grid.limites()` (la retícula de calles, hasta z=767) mientras el recinto
      cuelga hasta 905: 78 studs de vacío alrededor de donde empieza cada partida.
      Es el mismo fallo que `RASTRO_PASO`. Ahora los tres --suelo, red y guardián--
      salen de `Bounds.mundo()`, y mover el mapa los mueve a la vez.
    · **Una red de seguridad puede tapar el fallo que venía a atrapar.** El guardián
      que devuelve al jugador se escribió primero con el fondo a -130 "por prudencia",
      y no habría cazado NADA: la red para la caída en -60. Un guardián que llega
      tarde es peor que ninguno, porque parece que hay red. La prueba pura que fija
      la relación (`fondo > RED_Y`) vale más que los dos números.

- **El `PivotTo` del servidor sobre un personaje se revierte, y por eso una prueba
  puede mentir.** El personaje es propiedad de RED DEL CLIENTE: teletransportarlo
  desde `execute_luau` en el datamodel `Server` funciona durante una fracción de
  segundo y el cliente lo devuelve. Media sesión midiendo "las patrullas no
  persiguen" salió de ahí -- la distancia jugador-patrulla salía constante a 78,1
  studs medición tras medición, y la conclusión (correcta) era que ninguno de los
  dos se movía; la incorrecta era culpar a la persecución. **Para mover al jugador
  de verdad hay que hacerlo desde el datamodel `Client`**, que es quien manda sobre
  su personaje. Ahí el teletransporte se queda puesto y se puede medir lo que pasa
  después.

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

- **Ampliar una reticula moviendo sus indices lo mueve TODO, y en silencio.** La ciudad
  crecio de 4x3 a 5x4 el 21/08 (*"estaria bien que se ampliara un poco mas, pero creciendo
  desde el sentido y la logica, no copy paste"*), y la forma obvia --subir `COLUMNAS` a 5 y
  `FILAS` a 4-- habria sido la mala: el numero de cada calle cambia de significado, y con el
  todo lo que se escribio contra el. El destino de la verde estaba puesto como
  `Grid.cruce(1, 2)`, el enganche del recinto como `cruce(1, FILAS)` y las pruebas fijan que
  la calle 1 pasa por la boca del almacen. Nada de eso da error: mueve los tres destinos y
  la salida de casa a otra parte del mapa sin decir nada.
  Se crece por **indices negativos** (`COL_MIN = -1`, `FILA_MIN = -1`), y entonces
  `cruce(1, 2)` sigue siendo el mismo sitio que ayer. La ciudad nueva aparece al norte y al
  oeste -- lejos de casa, sin ruta, o sea sitio que solo se pisa si se decide explorar.
  Corolario: `Grid.COLUMNAS` y `Grid.FILAS` se **borraron** en vez de reinterpretarse. Se
  usaban como "el indice de la ultima calle" en veinte sitios; dejarlas valiendo "cuantas
  manzanas hay" habria compilado igual y recorrido media ciudad. Borrarlas hace que el
  analisis estatico liste uno a uno todos los sitios que hay que mirar.

- **Doce manzanas hechas con la misma funcion son una manzana repetida doce veces.** Todas
  salian de `plantarManzanaCerrada` y lo unico que las distinguia era lo altas que eran las
  cajas, asi que la ciudad no daba referencias: todas las esquinas eran la misma esquina --
  que es literalmente la queja que hundio el mapa del Creator Store (*"no se hacia donde
  tirar"*, *"el sitio es feo y confuso"*). Lo que hacia falta no era mas detalle sino que
  **cada manzana fuera una cosa**: el plano vive ahora en `shared/Districts.luau` con **once**
  usos de silueta propia, escrito **a mano** manzana por manzana. Los tres ultimos
  --escuela, cancha y gasolinera-- son SITIOS y no tejido, que es otra cosa: de un
  barrio residencial no te acuerdas, de la gasolinera si. Sacarlo de una formula
  sobre (col, fila) seria una linea y seria copy paste con otro nombre: reparte por
  aritmetica, no por sentido. Y lo que fija la prueba no es que manzana es cada cosa --eso
  se cambia cuando toque-- sino que **no haya tres iguales en linea** en ninguna fila ni
  columna, que es como el ojo ve un patron.

- **Una caja de color no es un edificio, y la diferencia son cuatro piezas.** Las
  manzanas ya tenian identidad --once usos distintos en `Districts.luau`-- y aun asi
  *"los edificios"* seguian siendo cajas con franjas de cristal: sin arriba ni abajo,
  sin delante ni detras, y sin forma de decir "el de la puerta verde" porque ninguno
  tenia puerta. Lo que lo arregla no es detalle sino ORIENTACION y ESCALA: un **zocalo**
  (donde acaba la calle), un **portal en la cara que da a la calle** (que ademas dice
  hacia donde esta la calle desde dentro de una manzana), una **cornisa** que recorta
  la silueta contra el cielo y una **caseta de azotea** en los altos. Cuatro piezas por
  edificio, ~370 en toda la ciudad.
  Y todo eso **cuelga del propio edificio**, no de la carpeta: un edificio se DERRIBA
  --`validarPuntosFijos` retira el que pisa un destino, `CityBuilder` el que estorba a
  una guarida-- y con las molduras plantadas como hermanas quedaron **79 piezas
  flotando** en una partida normal. Lo mide `SelfCheck` desde entonces.

- **Una moldura que remata "a ras" es 57 pares coplanares.** La cornisa se puso con su
  cara superior en la cota exacta del bloque y la sonda del mundo lo canto antes de
  abrir Studio. Corona medio stud por encima, y **vuela medio stud por lado y no nueve
  decimas**: con 0,9 dos alas contiguas se rozan 1,8 studs, que supera el solape minimo
  que la sonda considera parpadeo, y basta con que sus alturas de generador caigan a
  menos de 0,15 para que peleen. Con 0,5 el roce es de uno exacto -- justo por debajo.

- **"Cabe en una pieza" es una afirmacion con fecha de caducidad.** La red de seguridad
  bajo el mapa era una sola `Part` porque la caja medía 1.810 studs y el limite de
  Roblox son 2.048 por eje. El 22/08 la ciudad crecio a 902 de ancho, la caja paso a
  2.102, y **Roblox recorto la pieza sin decir nada**: 27 studs sin red en cada borde.
  Ahora se planta por baldosas de 2.000. Es la tercera vez que se paga lo mismo
  --`RASTRO_PASO`, `Config.ALIJOS`, esto-- asi que la regla merece nombre propio: **un
  numero que describe el mundo tiene que salir de una cuenta sobre el mundo, no
  escrito.** `Config.ALIJOS` ya es `#Districts.manzanas() * 0.8` por este motivo.

- **Un radio medido en planta deja de valer el dia que el mapa tiene altura.** La
  recogida de alijos comparaba `dx*dx + dz*dz` contra 18 studs y **no miraba la Y en
  absoluto**. Daba igual mientras todo estaba en el suelo; el dia que seis alijos se
  mudaron a los tejados paso a ser el fallo que se lleva por delante la funcion entera
  -- uno a dieciseis studs de altura entra de sobra en un radio de dieciocho medido en
  planta, asi que se recogia **andando por la calle de abajo**, sin subir y sin el
  accesorio que se acababa de inventar para subir. El sistema habria salido "terminado"
  y no habria servido para nada. No lo caza ninguna prueba de las que habia: se ve
  poniendose debajo y mirando. Ahora hay `Config.ALIJO_ALTURA`, y lo que fija la prueba
  pura es la RELACION con `ALIJO_TEJADO_MIN`, no los dos numeros por separado.

- **Y un desplazamiento que corrige la paridad de N se rompe con N+1.** Los expositores
  del taller se corren media plaza para que ninguno caiga en el centro de la losa --por
  ahi entra el jugador y por ahi comprueba `SelfCheck` que se pisa-- y estaba escrito
  como `+ 5` a secas, con su comentario explicando el porque. Correcto para los SIETE
  vehiculos que habia; el dia que entro el octavo volvio a poner uno justo en el centro,
  y la sonda lo dijo asi: *"el Taller se pisa por arriba y lo que se pisa ahi es
  Podio4"* -- que no se parece en nada a "sobra un vehiculo". La cuenta se fue a
  `Vehicles.podioX` para poder probarla **con catalogos de 1 a 24**, que es lo unico que
  caza un fallo que solo aparece al cambiar el numero.

- **Y una sonda escrita para una pieza miente cuando hay dos.** La que comprueba la red
  la buscaba con `FindFirstChild("Red")`: al partirla en baldosas medía media red y daba
  rojo teniendo el mundo tapado. Mide la union de todas. Es la misma familia que *"una
  sonda que mide algo PARECIDO a lo que se construyo es peor que no tener sonda"*.

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
