# Verificación del prototipo

> 2026-08-17. Estado del prototipo de [`DISENO.md`](DISENO.md) al terminar las 14 tareas del
> plan de implementación.
>
> Lo que este documento responde: **qué está comprobado, cómo, y qué sigue sin comprobar.**

---

## Resumen

El prototipo está **completo y jugable en solitario**: produces mercancía mientras no estás,
vuelves, cargas lo que te quepa, eliges por qué ruta ir y cobras según el riesgo que hayas
asumido. La capa social —que otro jugador te alcance y te quite parte de la carga— está
construida y sus reglas están probadas, pero **no se ha jugado entre dos personas**.

| | |
|---|---|
| Pruebas automáticas | **869** reglas + **96** comprobaciones del mundo, todas en verde (19/08) |
| Tareas del plan | 14 de 14, todas revisadas |
| Defectos encontrados en revisión | 1 crítico, 2 importantes — los tres corregidos |
| Sin comprobar | El robo entre dos jugadores reales, y si el bucle entretiene |

---

## 1. Lo que está comprobado

### La retícula del mapa (19/08)

Con el mapa propio, la sonda pasa a comprobar cosas que con la ciudad prestada eran
imposibles, porque exigen saber dónde **debería** estar cada calle:

| Comprobación | Qué caza |
|---|---|
| Están las 9 calles, las de los bordes incluidas | Un mapa sin borde por el que rodear: quien huye hacia fuera se encuentra el césped |
| Todas a la misma cota, y a la del plano | Cantos que cortan el navmesh. Ya dejaron las cuatro rutas sin camino una vez |
| Cada destino, a dos giros o menos de la boca | *"No sé a dónde tengo que ir"*, dicho tres partidas seguidas, convertido en algo que falla solo |
| Los tres hitos se ven desde la boca | Que la señal de orientación quede tapada. El mundo se construye igual y nadie se entera |

Las cuatro nacieron con un rojo cada una, que es la única prueba de que sirven:

- El **hito verde estaba plantado encima de la fila de luces del barrio**. Lo puse en el eje
  de la calle de salida para que los tres se vieran en fila, y esa calle es justamente el
  camino al primer destino: un mojón de orientación que estorbaba a la orientación.
- Movido al bordillo, **la baliza del barrio tapaba a los otros dos**. Todo estaba alineado
  en el mismo eje, que era la gracia y también el problema. Se resolvió sacándolos de la
  calzada: la línea de visión va en diagonal y eso los separa.
- `acceso()` **seguía poniendo un escalón de 4 studs** sobre suelo llano. El código que
  servía para sobrevivir a un terreno ajeno hace daño cuando el terreno es tuyo.
- Y siete rojos que **no eran del mundo sino de la sonda**: medía las vías de junta en
  junta, y una vía propia es una sola losa, así que cantaba "0 de 0 puntos". Una sonda que
  deja de saber qué está midiendo es peor que no tenerla, porque su verde ya no significa
  nada.

Un quinto defecto lo cazó el recuento, no una comprobación: aparecían **22 aceras de 48**.
`esDespejable` de `CityBuilder` permitía retirar cualquier pieza con el segundo lado ≤25 —un
criterio calibrado para la chatarra del mapa del Creator Store— y una acera nuestra mide
120 × 1,5 × 6. Las calles se libraban **por un stud**. Se arregló marcando lo que planta el
mapa (`delMapa`) en vez de afinar el listón.

### Las reglas del juego: 133 pruebas

Toda la lógica de reglas vive en módulos **puros** de `src/shared/` que no tocan Roblox, así
que se prueban en milisegundos. Se ejecutan dentro de Studio, porque Luau no corre fuera:

```lua
local clon = game.ReplicatedStorage.Shared:Clone()
clon.Name = "SharedTestRun"
clon.Parent = game.ReplicatedStorage
local ok, resultado = pcall(function()
	return require(clon.TestRunner).run()
end)
clon:Destroy()
print(if ok then resultado else "LA TANDA REVENTO: " .. tostring(resultado))
```

El clon no es un adorno: `require` cachea por instancia, y sin él la segunda tanda devuelve
el informe de la primera aunque el código haya cambiado. Eso ya produjo un falso resultado
durante el desarrollo.

Cubren: valor de una entrega (rareza × ruta se combinan), peso y penalización de velocidad,
definición y validación de rutas, tirada de rarezas con semilla fija, producción del almacén
con tope, y las reglas completas del robo.

### El camino real, no el sandbox

`require` dentro de las herramientas de inspección corre en un **entorno aparte** que no
comparte estado con el servidor que está jugando. Verificar ahí prueba una copia, no el
juego. Para probar el camino de verdad se planta un `Script` dentro del servidor —ése sí
comparte sus módulos— y se actúa desde el cliente como lo haría un jugador.

Comprobado así, en el servidor real:

| Comprobación | Resultado |
|---|---|
| Velocidad con 3 cajas | 16 → **11,8** |
| Entregar **lejos** del destino | **0 monedas** |
| Entregar en el destino de la ruta elegida | paga el multiplicador correcto |
| Elegir ruta roja y entregar en el destino verde | **0 monedas** |
| Reclamar carga lejos del almacén | **nada** |
| Reclamar en el almacén | la carga sube y el almacén baja |
| Un jugador solo, con carga, en ruta roja, 40 ciclos del bucle de robo | **no pierde nada** |

La última importa más de lo que parece: si el bucle no distinguiera a la víctima del
atacante, un jugador en solitario vería su carga desaparecer cada 200 ms sin explicación.

### El bucle jugado andando, de principio a fin

**Esta es la verificación que faltaba, y la que destapó que el mapa era injugable.** Todas
las anteriores movían al personaje teletransportándolo, así que el suelo nunca se pisó: el
juego pasaba todas las pruebas mientras la carretera no cubría siquiera el almacén.

Un `Part` tiene un **tamaño máximo de 2.048 studs por eje**. La carretera pedía 2.600 y
Roblox la recortó **en silencio**, dejándola centrada en la misma posición — así que el
tramo del almacén y el de la salida se quedaron sin asfalto. Nada dio error. Sólo se ve
caminando. Por eso el mundo se construye ahora en segmentos.

Recorrido completo de la ruta roja **andando** (`Humanoid:MoveTo`, sin teletransportes):

```
25 58 90 122 154 186 218 251 ... 1891 1924 1955 1987 1999
```

Avance continuo, altura constante en 3, **ni una caída**, y el personaje llega vivo.

Y el bucle entero, jugado como lo jugaría una persona:

| Paso | Resultado |
|---|---|
| Aparece | a **6 studs del almacén** |
| Vuelve al almacén andando desde 2.000 studs | llega |
| El almacén **había producido** mientras caminaba | **10 cajas** |
| Coge lo que le cabe | 2 (una pesaba doble) |
| Velocidad cargado | **11,8** |
| Elige ruta y recorre los 600 studs andando | llega vivo |
| Cobra | **510 monedas** — salió una caja sellada (×50) |
| Zurrón tras cobrar | vacío |

### El sumidero: comprar la furgoneta

Añadido después de la primera ronda, porque sin él el bucle se quedaba en dos pasos de
cinco: se producía y se cobraba, pero el dinero no compraba nada y el número del HUD dejaba
de significar algo al tercer viaje.

Todo el recorrido, **andando** (`Humanoid:MoveTo`), sobre el servidor real:

| Paso | Resultado |
|---|---|
| Sale del almacén y va al taller (zona nueva, x negativo) | llega en 3 s, sin caerse |
| Intenta comprar con 0 monedas | rechazado — `sin_dinero` |
| Compra con 1.500 | **capacidad 3 → 10**, velocidad 16 → **14,4** |
| Intenta comprarla otra vez con 9.999 | rechazado — `ya_lo_tienes`, **no se le cobra** |
| Vuelve al almacén y reclama | **8 cajas**, peso 10 = lleno; velocidad **9,9** |
| Intenta comprar llevando carga, en el taller | rechazado — `con_carga` |
| Elige ruta y recorre los 555 studs | **56 s andando, sin caerse** |
| Cobra | **1.780 monedas**, zurrón vacío, ruta liberada, velocidad de vuelta a 14,4 |

Las cifras de velocidad son la comprobación que importa: la furgoneta va **siempre más
lenta** que ir a pie, vacía (14,4 < 16) y llena (9,9 < 11,8). Es la regla innegociable del
diseño — capacidad y acceso, nunca potencia — y sin ella las rutas rojas pasan a ser dinero
gratis y el PvP muere.

Basura por la firma directa (`42`, `true`, `"camion_de_oro"`, `"a_pie"`, un objeto del
mundo): los cinco rechazados con su motivo, sin cobrar nada y sin reventar.

### Un intento de exploit por cada remote

Desde el **cliente**, que es desde donde ataca un exploit real, y con el personaje colocado
lejos del almacén, de la salida y de los tres destinos: **480 llamadas** con basura por los
seis remotes — cobrar sin haber viajado, rutas inventadas, tipos absurdos (`nil`, números,
tablas, un objeto del mundo), reclamar carga a 1.500 studs del almacén, e inundar el canal
de sincronización.

| Después del ataque | |
|---|---|
| Dinero | **0** |
| Cajas | **0** |
| Ruta | **nil** — nunca aceptó `"dorada"` ni `"roja"` lejos de la salida |
| Almacén | **5**, intacto |
| Servidor | **vivo** |

El servidor no cedió nada y ningún tipo inesperado lo tumbó.

El remote de compra, que es el más nuevo, se atacó aparte: **520 llamadas** desde el cliente
a 900 studs del taller, con ids válidos, inventados, vacíos, números, booleanos, tablas y un
objeto del mundo, más llamadas sin argumento y con tres. Después: dinero **intacto**,
vehículo **nil**, servidor **vivo**. Ni una compra a distancia.

### El arranque, sin publicar el juego

`DataStoreService:GetDataStore()` **lanza una excepción** si el place no está publicado. En
el piloto anterior de este repo se llamaba al cargar el módulo, así que el `require`
reventaba y mataba el script entero: juego sin mapa, sin personaje y sin ninguna pista del
motivo. Costó tres rondas de depuración.

Comprobado que ya no ocurre: con el juego **sin publicar**, hay mundo, hay personaje, y ni
guardar ni cargar revientan. El store se resuelve perezosamente y dentro de `pcall`.

### La interfaz, en tres dispositivos

| Dispositivo | Resolución | Problemas |
|---|---|---|
| Samsung Galaxy A06 | 705 × 338 | ninguno tras los tres arreglos de abajo |
| iPad Pro M5 13" | 1375 × 1032 | ninguno — cero solapes con los controles táctiles |
| Portátil promedio | 1365 × 768 | el selector salía a tamaño de cartel; con tope ya no |

Dos detalles que hacen que la medición valga:

- **El selector de ruta se encendió a mano para medirlo.** Sólo aparece cuando llevas carga
  y no has elegido destino, así que en una medición normal ni se mira — y en el piloto, el
  elemento que se salía de pantalla era justo el de una pantalla intermitente.
- **El origen del área de interfaz está en `(0, −58)`**, no en el cero. Midiendo contra cero
  salen elementos "fuera de pantalla" que están perfectamente colocados. Ese falso positivo
  costó una investigación entera durante el desarrollo.

Los únicos avisos son del chat y el joystick de Roblox, que no son parte del juego.

**Al añadir el botón de compra, esa medición encontró dos defectos reales** — los dos en el
Galaxy A06, que es el peor caso:

- **El selector de ruta se superponía a los tres botones**, que asomaban por detrás
  ilegibles y seguían siendo pulsables. Elegir ruta es ahora modal de verdad: velo oscuro a
  pantalla completa y botones ocultos (ocultos, no tapados).
- **Los botones de ruta salían en orden alfabético** —AMBAR, ROJA, VERDE— porque
  `UIListLayout` ordena por nombre cuando todos comparten `LayoutOrder`. El gradiente de
  riesgo es lo único que esa pantalla comunica, y quedaba con el ×10 en el centro.
- **El botón de comprar pisaba el de salto de Roblox por 6 px.** Su borde inferior caía en
  y=196 y el salto empieza en y=190. En la captura no se ve: sólo aparece **comparando
  posiciones**, y comparando en coordenadas **absolutas de pantalla** — el HUD tiene origen
  `(0, −58)` por `DeviceSafeInsets` y los controles táctiles de Roblox lo tienen en `(0,0)`,
  así que medir cada uno en su propio espacio esconde el solape. La regla del proyecto
  —*nada en las esquinas inferiores*— no se cumple sola.

Y al rehacer el aspecto de la interfaz aparecieron **tres solapes más**, ninguno visible en
una captura: el aviso encima del panel de estado, el aviso cruzando las tres tarjetas de
ruta, y el título del selector rozando el panel. Se encontraron comparando **todos contra
todos**, no revisando uno por uno.

Estado final, medido en 705×338 y en coordenadas absolutas, con el aviso encendido:

```
Panel        14, -48 -> 226,  30        JumpButton   610, 190 -> 680, 260
Recoger     557,   6 -> 684,  54        Joystick    -100,  93 -> 282, 380
Entregar    557,  60 -> 684, 108
Comprar     529, 114 -> 684, 162        solapes: NINGUNO
Aviso       148,  43 -> 501,  74        todos los textos: caben
```

En iPad Pro M5 (1375×1032), lo mismo: cero solapes. Nada fuera del área, ningún botón por
debajo de 48 px, ningún texto cortado.

### El aspecto de la interfaz

Se rehízo cuando el mundo pasó a tener modelos 3D: el HUD se había escrito para un juego de
cubos de colores y ahí encajaba, pero con textura y volumen alrededor pasó a parecer un
depurador puesto encima. Esquinas, bordes del mismo tono más oscuro, degradado vertical,
sombras, el multiplicador dominando cada tarjeta de ruta y el dinero con separador de
millares. **Ninguna posición cambió por esto**, para no invalidar las medidas de arriba.

Dos trampas cobradas en el intento:

- **`Color3.new(1.14, 1.14, 1.14)` revienta** — los componentes van en `[0,1]`. Un
  `UIGradient` sólo puede oscurecer (multiplica), nunca aclarar. La excepción mató
  `Hud.build()` entero justo después del primer botón: el juego arrancó con medio HUD, sin
  selector de ruta y **sin ningún error a la vista**. Desde entonces cada pantalla se
  construye dentro de su propio `pcall`, igual que los servicios del servidor.
- **Una sombra dentro de un `UIListLayout` descuadra el reparto**: es un hijo más, así que
  los tres botones de ruta pasaron a ser seis elementos y la tarjeta roja acabó fuera de la
  pantalla. En una pantalla de tres opciones, una dejó de existir. `UiKit.sombra` ahora se
  niega a crearse dentro de un contenedor con layout.

---

## 2. Lo que NO está comprobado

### El robo entre dos jugadores reales

**Es la laguna más importante.** Las herramientas de automatización no permiten lanzar dos
clientes a la vez, así que el robo end-to-end entre dos personas no se ha ejecutado nunca.

Lo que sí está cubierto:

- Las **reglas** del robo, con 89 pruebas: quién puede robar en cada ruta, el marcado de 60
  segundos, el reparto, la distancia, la velocidad imposible.
- El **bucle del servidor**, ejercitado con un jugador simulado para los casos en los que el
  robo se rechaza (ruta verde, cazador sin carga, demasiado lejos, ladrón lleno).
- Que un jugador **no se roba a sí mismo**.

Lo que falta es el caso positivo completo: dos personas, una alcanza a la otra, la carga
cambia de manos, ambas reciben su aviso. **Es lo primero que hay que probar**, y coincide
con lo que el diseño ya exigía: *"con 3 o 4 personas: ¿tensión o frustración?"*.

### Si el bucle entretiene — YA RESPONDIDO, Y LA RESPUESTA ES NO

JJ lo jugó el 17/08 y el veredicto está en [`PRIMERA-PARTIDA.md`](PRIMERA-PARTIDA.md):
*"ahora es correr en línea recta sin obstáculos ni nada, es bastante triste"*.

El bucle está construido y el minuto y medio del medio está **vacío**. Eso dispara el criterio
de kill número 1 del diseño: **rehacer el viaje antes de añadir nada**. Todo lo que sigue en
esta sección se escribió antes de esa partida y se mantiene por lo que enseña del método.

### Si el bucle entretiene

Ninguna prueba puede responderlo. El diseño fija el criterio: **si no aguantas diez minutos
seguidos tú mismo, sin nadie más conectado, hay que rehacer el viaje antes de añadir nada.**

Al jugarlo conviene anotar:

- ¿En qué minuto aparece el primer momento de aburrimiento?
- ¿Cuántos viajes completas y por qué rutas?
- ¿Sale alguna caja rara? ¿Cambia lo que decides después?
- ¿Vuelves al almacén por interés o por obligación?

---

## 3. Defectos encontrados durante el desarrollo

Los tres los encontró la revisión, no las pruebas. Van aquí porque el patrón se repite:
**ninguno lo habría detectado un compilador.**

**El cliente se quedaba colgado para siempre.** Esperaba un RemoteEvent que el servidor sólo
creaba al enviar el primer dato — y ese primer dato sólo llegaba si el cliente lo pedía,
cosa que no hacía porque estaba bloqueado esperando. El HUD nunca se rellenaba. Arreglado
creando los remotes al arrancar el servidor; el mismo patrón se aplicó preventivamente a los
avisos y el sonido.

**Las cajas robadas podían evaporarse.** El reparto calculaba el 30 % del botín sin saber
cuánto le cabía al ladrón: se lo quitaba entero a la víctima, metía lo que cupiera y el
resto desaparecía del juego. Ahora sólo se roba lo que quepa y el resto se queda con la
víctima. De paso mejora el juego: salir de caza con el zurrón vacío pasa a ser una decisión.

**Una función auxiliar declarada después de usarse.** En Lua se habría resuelto como variable
global `nil` y habría reventado al recoger la primera caja. No lo detectan ni el formateador
ni el compilador: sólo aparece jugando. Se corrigió antes de escribir el código.

---

### La geometría, revisada superficie por superficie

Pedido tras ver la furgoneta enterrada. Medido en el servidor, con el mundo ya construido:

| Comprobación | Resultado |
|---|---|
| Puntos de suelo muestreados (5 líneas × todo el eje X) | **1.090**, ninguno sin suelo |
| Alturas de suelo distintas | 3: asfalto `0,5`, losas `2,0`, punto de aparición `3,0` |
| Escalón carretera → cualquier losa | **1,5 studs** (el límite para subir andando son 2) |
| Piezas del decorado enterradas | **ninguna** |

Y caminado de verdad, con `Humanoid:MoveTo`, contando despegues (saltos y caídas):

```
1. bajar del muelle al asfalto   y 5,0 -> 3,5    0 despegues
2. subir a la losa del taller    y 3,5 -> 5,0    0 despegues
3. volver al muelle              y 5,0 -> 6,0    0 despegues
4. hasta la salida               y 6,0 -> 5,0    0 despegues
5. hasta el destino verde        600 studs       0 despegues
```

**El fallo que lo motivó**: la furgoneta del decorado se colocó como si el suelo estuviera
en `y = 0`, pero la losa del taller tiene su superficie en `y = 2`. Aparecía hundida hasta
los ejes. Ahora cada pieza se coloca **apoyada** sobre la cota real de su superficie
(`SUELO_CARRETERA = 0,5`, `SUELO_LOSA = 2`), no centrada en una altura calculada a ojo.

### El personaje era invisible, y por la misma causa que los modelos

Al dar a Play no se veía al jugador. Existía en servidor y cliente, con sus 16 partes,
todas con `Transparency` 0, a trece studs de la cámara y en el centro exacto de la pantalla
según `WorldToViewportPoint`, sin nada por delante. Andaba y chocaba. **Una marca de color
puesta en su posición exacta sí se veía; él no.**

La causa: un avatar R15 son ~15 `MeshPart` que Roblox descarga de `assetdelivery.roblox.com`
— y con el place sin publicar no baja **ningún** mesh. Un fantasma que camina.

La salida es el rig **R6**, hecho de `Part`, que no descarga nada
(`Players:CreateHumanoidModelFromDescription`). Además tiene una ventaja que no es estética:
en un juego de persecuciones, que todos midan lo mismo hace el PvP comparable. Al publicar,
cada uno vuelve a llevar su avatar sin tocar una línea.

### Los modelos 3D no se ven hasta publicar

Encontrado dando a Play en el place del proyecto: **`game.PlaceId == 0`** —sin publicar— y
entonces `AssetService:CreateMeshPartAsync` falla con *"Failed to load mesh asset"* para
**cualquier** id, los nuestros y los públicos de Roblox por igual. Los meshes generados con
Cube 3D sólo existen en la sesión de Studio donde se crearon; al reabrir, se pierden.

Por eso el decorado tiene **respaldo construido con piezas**: 22 `Part` que arman la nave
(paredes, tejado, portón y ventanas), el cobertizo del taller, la furgoneta aparcada y las
cajas del muelle. No es bonito, pero el sitio **se reconoce**, que es lo que hace falta para
saber dónde estás de pie. Al publicar el place entran los meshes solos, sin tocar código.

El mundo jugable nunca dependió de esto: las losas, las distancias y las reglas son las
mismas con meshes y sin ellos.

### El ritmo, medido con un cronómetro

Lo que destapó la primera partida jugada de verdad: **cargado se va a 11,8 studs/s**. Con las
distancias del diseño, un viaje de ida y vuelta costaba:

| Ruta | Ida y vuelta (diseño) | Ida y vuelta (prototipo) |
|---|---|---|
| Verde | 1,7 min | 0,8 min |
| Ámbar | 3,4 min | 1,7 min |
| Roja | **5,7 min** | **2,8 min** |

En la sesión de diez minutos que decide si el proyecto sigue, las distancias originales dan
**menos de dos viajes rojos**: se estaría midiendo la caminata, no el bucle. A la mitad caben
unos cuatro, con las mismas proporciones y las mismas decisiones.

Medido después del cambio, por la roja: **3 cajas → 300 monedas en 85 s**. Con eso la
furgoneta (1.500) cae sobre el quinto viaje, unos siete minutos — dentro de la sesión, que es
justo donde tiene que estar el primer sumidero.

### La ciudad, recorrida andando (17/08, tarde)

Con el cambio de la recta a la ciudad **ningún número del balance seguía siendo válido**, así
que se recorrió el bucle entero con una sonda que usa los mismos remotes que un jugador y
camina con su propio personaje: `PathfindingService` para trazar y `Humanoid:MoveTo` para
andar. Nunca teletransporta dentro de un tramo medido — esa lección ya costó una sesión.

Lo primero que midió, y sirvió para dos cosas:

| | Recta | Andando | Rodeo | Tiempo |
|---|---|---|---|---|
| Verde | 502 studs | 582 | **+15 %** | 51 s |

El rodeo de la ciudad es del 15 %: hay manzanas de por medio, pero no laberinto. Y **el cobro
funciona**: 3 cajas comunes → 30 monedas, el zurrón vacío y la ruta liberada. El defecto más
grave de la primera partida ("le doy a entregar y no se actualiza") queda cerrado.

Pero el mismo recorrido dio **calor máximo 0 y cero patrullas**. En una ruta con tres
detectores, eso no era suerte.

#### La mitad de los detectores estaba en los tejados

`sueloDeLaCiudad` lanza un rayo desde arriba y devuelve **lo primero que toca**, y en una
ciudad eso es un tejado la mitad de las veces. Medido: **15 de los 30 detectores plantados
sobre edificios**, uno a 186 studs de altura. Ninguno podía dispararse nunca — por debajo
pasaba la calle, a ochenta studs de su radio de 35.

Es el peor tipo de fallo que da este proyecto: **nada revienta**. El poste existe, se ve
perfectamente si miras hacia arriba, y el juego es simplemente más fácil de lo que dice ser
sin que nada lo señale.

Arreglado con `sueloTransitable`, que rechaza cotas por encima de 40 studs y busca la calle
más cercana en anillos. Después: **0 de 30 en tejados**, alturas de 14 a 50.

Y de paso se corrigió lo que había motivado la búsqueda: el primer detector de cada ruta va
ahora **sobre el trayecto** (a 6, 6 y 19 studs de la línea, dentro del radio de 35), así que
la ruta verde —donde se aprende qué es un detector— por fin enseña algo.

#### El mismo recorrido, después

> **VERDE en 52 s · calor máximo 2 · 2 patrullas persiguiendo · cobro 120 · ruta liberada**

Ése es el viaje que faltaba. Ojo al matiz: la sonda **no esquiva**, va en línea recta a lo
tonto, así que ese calor 2 es el caso peor de la ruta más fácil. Un jugador que vea las
lentes rojas y las rodee debería quedarse en 1.

#### Tres fallos de las patrullas, invisibles los tres

Encontrados revisando el código a raíz de lo anterior. Ninguno da error; los tres dejan el
juego funcionando y más fácil de lo que promete:

1. **Tres patrullas escribiendo el mismo booleano.** "Te están viendo" lo ponía cada
   perseguidor por su cuenta, así que la última en pasar ganaba: bastaba con que una se
   quedara atrás para apagar la señal que las otras dos, encima del jugador, acababan de
   encender — y el calor se ponía a enfriar en plena persecución.
2. **Y ese booleano se quedaba encendido para siempre** al salir del bucle por cualquier vía
   que no fuera alejarse (morir, desconectarse, reaparecer): el calor no volvía a bajar nunca.
3. **Patrullas encalladas.** El mapa tiene **116 vallas** y el pathfinding manda contra ellas:
   la sonda acabó empujando una durante minutos, en estado `Running`, a 11,8 de velocidad y
   avanzando cero. A un jugador no le pasa —ve la valla y la rodea— pero una patrulla clavada
   deja de perseguir para siempre y **el jugador no se entera**: sigue corriendo con tres
   estrellas creyendo que le pisan los talones.

#### Y una trampa de método, nueva

**Entrar en Play antes de que Rojo haya sincronizado construye el mundo con el código viejo.**
Pasó aquí: se verificó dos veces un arreglo que ya estaba escrito y compilado, sobre un mundo
que se había generado con la versión anterior. Antes de dar por buena cualquier medición del
mundo, comprobar que el datamodel **Edit** tiene el código — es de ahí de donde Roblox copia
al entrar en Play.

Y la gemela, que costó otro rato: **medir distancias en 3D cuando lo que importa es el
plano**. Un detector en una azotea daba "83 studs de la línea" cuando su desviación real era
0; los 83 eran altura.

## 3-bis. Lo que la sonda del mundo dejó cerrado el 19/08 (y lo que no)

Al acortar las rutas y meter el rastro, la sonda pasó de 4 fallos a **80 de 80 en verde**.
Lo que cazó, porque es el catálogo de cómo se rompe este mundo sin que nada reviente:

| Qué | Por qué pasaba |
|---|---|
| **El barrio no tenía camino** | Su destino caía debajo de un árbol; el rayo desde el cielo se para en la copa y "el suelo" salía a 87 studs. La ruta del tutorial no se podía recorrer |
| **19 de 55 píldoras de la roja, fuera de alcance** | El rastro se sembraba antes que los refugios, y una comisaría de 54×54 cortaba después el camino que acababa de dibujar |
| **La ámbar sin refugio** | Los tres corredores salen del mismo almacén; con 320 studs de separación mínima sólo cabían dos para tres rutas |
| **Tres detectores flotando 5-7 studs** | `HeatService` mide en 3D, así que la altura come radio: 34 studs de alcance pasan a 31,6 |
| **Escalón de 3 studs en el acceso verde** | La envolvente que alisa el perfil sólo sube juntas, y no controlaba la caída contra los extremos impuestos |

**Y una lección que ya había aparecido y volvió a aparecer**: *cada cosa que se planta cambia
el mundo que la siguiente mide*. Le pasó al rastro (sembrado antes que los refugios) y le
pasó al asentado de los detectores, cuya primera versión era correcta y no servía de nada
por estar en el sitio equivocado del orden. Lo que dependa del estado final del mundo va al
final de la construcción, y punto.

### Resuelto: la joroba del acceso verde

**Era un solo rayo despistado, y lo encontró una sonda que volcaba las cotas fase por fase**
en vez de más conjeturas. El perfil bruto de esa vía salía así:

```
21,0  20,6 … 20,6  20,6  **27,5**  19,4
```

Trece juntas a ras de una explanada llana, la penúltima **siete studs más arriba**, y la
calle final a 19,4. Ese 27,5 es el rayo **central** de esa junta cayendo sobre una calle
elevada de la ciudad que pasa justo por encima antes de llegar. Y por eso apretar el tope de
los rayos laterales no cambiaba nada: el central manda sin límite, que es lo correcto en
general porque es el que va por donde de verdad pasa la vía.

Lo que hacía daño no era el pico sino lo que venía después: **la envolvente de conos hace su
trabajo y lo reparte a las juntas vecinas**, así que un rayo levantaba cuatro tramos.

**El arreglo** (`limitarDesdeExtremos`, en `acceso`): una junta no puede estar más alto de lo
que se alcanza desde un extremo subiendo a la pendiente máxima. Los extremos son los dos
datos que sí conocemos —la losa de la que sale la vía y la calle a la que llega— y una cuesta
de verdad siempre cumple ese límite porque sube tramo a tramo. Lo que no lo cumple no se
puede recorrer, así que tampoco hay que construirlo. Se aplica antes de los conos (para que
el pico no contamine) y después (para que no queden escalones contra los extremos).

Medido: el acceso verde pasa de sobresalir **4,5 studs a 1,8**.

**Lo que NO era** (descartado con medida, para no repetirlo): el terreno (los cinco rayos dan
19,00 en todo el trazado), los rayos laterales (bajado su tope de 4 a 1,6 con el cambio
verificado en Studio antes de reconstruir: perfil idéntico al decimal) y los extremos
impuestos (21,00 y 20,43, los dos bajos).

### Sin verificar: el encendido de los efectos de movimiento

La mochila y los efectos (polvo, estela) **están montados y comprobados en el mundo**: los
objetos se crean en el personaje con sus attachments y sus texturas correctas. Lo que **no**
está comprobado es que se enciendan al moverse, y no por falta de intentos:

| Cómo se intentó medir | Por qué no vale |
|---|---|
| `Humanoid:Move()` desde el servidor | `MoveDirection` se queda a cero: el personaje es propiedad de red del **cliente** |
| Escribir `AssemblyLinearVelocity` | Mismo dueño, mismo resultado: se escribe un 18 y se lee un 0 al instante |
| Mover el `CFrame` del root | El cliente lo devuelve a su sitio entre vueltas del bucle |
| `character_navigation` del MCP | Responde `Success` y el personaje no se mueve (0,0 studs/s medidos) |

Por eso la detección final mide **posiciones entre vueltas del bucle** en vez de propiedades
que el cliente controla, que es lo único que funciona desde el servidor con un jugador real.
Pero confirmarlo **requiere a alguien moviéndose con el teclado**. Es lo primero que hay que
mirar al jugar: al andar debe salir polvo, y al encadenar píldoras hasta media racha, estela
dorada.

### Abierto

- [ ] **Un destino verde alternativo daría 19 s menos de ciclo**, y se descartó a propósito.
      `(-170, 669)` cumple todas las distancias y da un camino de 511 studs contra los 679 del
      actual — **77 s de ciclo contra 96**. Pero cae en cuesta, y su carretera de acceso deja
      un canto de **2,6 studs justo donde nace**, que es donde la sonda dice "ahí se traba el
      vehículo". Probado suavizar la pendiente máxima de las vías (0,21 → 0,17): el canto
      sigue, así que no viene de ahí.

      Se eligió el llano porque un sitio donde el jugador se queda enganchado sin entender por
      qué cuesta más que diecinueve segundos. Si algún día se arregla el canto en el nacimiento
      de las vías, este destino vale 19 s de regalo.

      **Y una trampa de método que costó una medición entera**, ver abajo.

### La trampa: editar durante un Play no llega

Costó dar por buena una medición que no valía, y es puro funcionamiento de Rojo:
**sincroniza contra el datamodel de Edit, y un Play en curso corre sobre el snapshot que
se hizo al arrancarlo**. Guardar un fichero con Studio jugando deja el disco, el `.rbxl` y
la sesión de Play diciendo tres cosas distintas.

El síntoma es el peor posible porque no se parece a un fallo: el `rojo build` dice `BUILD
OK`, la sonda pasa, y lo que se está midiendo es el código de antes.

**El ciclo correcto para probar un cambio del mundo:**

1. editar y `rojo build`;
2. **parar el Play**;
3. leer el `Source` del módulo en el datamodel **Edit** y comprobar que el cambio está;
4. arrancar el Play y medir.

Saltarse el paso 3 es cómo se llega a "lo he probado y no cambia nada" sin haberlo
probado.

## 4. Antes de publicar

- [ ] **Poner `Config.PROTOTIPO = false`.** Una línea, y con eso las probabilidades de caja
      rara y el ritmo del almacén vuelven a los de `DISENO.md`. Antes eran cinco constantes
      con un comentario al lado diciendo a cuánto había que devolverlas: cinco ediciones a
      mano el día de publicar, y ninguna avisa si se olvida — el juego sale con las
      legendarias diez veces más frecuentes de lo diseñado y todo funciona. Las dos tablas
      están ahora en el código y **las pruebas comprueban también la de producción**, que
      hasta el 19/08 vivía en comentarios y no la había ejecutado nadie nunca.
- [x] ~~Al revertir el tope del almacén, corregir el HUD~~ — ya lee el tope de **tu** nave,
      no la constante de partida. Comprobado el 19/08.
- [ ] Publicar el place, sin lo cual no hay guardado en la nube.
- [ ] Jugar el robo con dos personas.
- [ ] Aguantar diez minutos seguidos en solitario.

## 5. Criterios para matarlo

Escritos antes de empezar, a propósito, para que pivotar sea leer un número y no discutir
una corazonada:

| Momento | Comprobación | Si falla |
|---|---|---|
| Ahora | ¿Aguantas 10 minutos seguidos, sin PvP? | Rehacer el viaje. Sin esto no hay juego |
| Con 3-4 personas | ¿Tensión o frustración? | Ajustar reparto y marcado |
| Publicado | **D1 < 15 %** con 100+ jugadores | Pasar al target A (excavación) |
| Publicado | Sesión media < 6 min | El bucle es demasiado corto |
