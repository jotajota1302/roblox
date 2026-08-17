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
| Pruebas automáticas | **133**, todas en verde |
| Tareas del plan | 14 de 14, todas revisadas |
| Defectos encontrados en revisión | 1 crítico, 2 importantes — los tres corregidos |
| Sin comprobar | El robo entre dos jugadores reales, y si el bucle entretiene |

---

## 1. Lo que está comprobado

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

## 4. Antes de publicar

- [ ] **Revertir los valores marcados `PROTOTIPO:` en `Config.luau`** — probabilidades de
      caja rara, ritmo del almacén. Son deliberadamente generosos para poder medir en una
      sesión lo que en producción tardaría horas.
- [ ] Al revertir el tope del almacén, **corregir el HUD**: escribe `/10` a mano en vez de
      leerlo de la configuración, así que mentiría en silencio.
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
