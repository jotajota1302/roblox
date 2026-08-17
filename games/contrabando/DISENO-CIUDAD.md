# Diseño v2: la ciudad y el calor

> Spec del rediseño del viaje. **Complementa a `DISENO.md`, no lo sustituye**: la economía,
> el almacén, las rarezas, los vehículos y las reglas del robo siguen siendo las de allí.
> Lo que cambia aquí es el escenario y lo que ocurre entre salir y cobrar.

---

## 1. Por qué existe este documento

`DISENO.md` fijó un criterio de kill: *si no aguantas diez minutos seguidos tú mismo, sin
nadie más conectado, hay que rehacer el viaje antes de añadir nada*.

La primera partida jugada por una persona lo disparó (`PRIMERA-PARTIDA.md`):

> *"Ahora es correr en línea recta sin obstáculos ni nada. Es bastante triste la experiencia."*

El diagnóstico es exacto y no es un fallo de implementación: **el viaje está vacío por
diseño**. La decisión se toma una vez al salir y después no vuelve a pasar nada durante
minuto y medio. Todo el riesgo de la ruta roja es *que aparezca otro jugador*, y jugando
solo eso es cero: el trayecto no se distingue del de la verde salvo en longitud.

Este documento arregla eso con dos cambios: **la ciudad como tablero** y **el calor como
contenido del viaje**.

---

## 2. Lo que NO cambia

Se escribe explícitamente porque el riesgo mayor de este rediseño es que se lo lleve todo
por delante. Sigue vigente sin tocar una coma:

- La economía entera: caja = 10 monedas, multiplicadores por rareza, valor de entrega.
- El almacén: produce con tope, no es asaltable **nunca**, la producción se calcula al
  consultarla.
- Los vehículos: progresión por **capacidad y acceso, jamás por potencia**.
- El robo entre jugadores: fracción, marcado, zona segura, herencia de ruta.
- Todas las reglas de seguridad: el servidor decide, el cliente dibuja.
- El bucle: recoger → elegir → viajar → cobrar → invertir.

**La ciudad es el tablero, no el juego.** Es la referencia estética y de sensación que pidió
JJ ("mini GTA"), no el alcance. Nada de coches conducibles, armas ni misiones — ver §7.

---

## 3. El escenario: la ciudad

### Qué es

El modelo público `2701703521` del Creator Store. Verificado en Studio antes de adoptarlo:

| Medida | Valor | Por qué importa |
|---|---|---|
| Extensión | 1548 × 1569 studs | Caben las tres zonas con holgura (hoy la roja son 1000 en recta) |
| Piezas | 7152 | Manejable; no hay meshes que resolver |
| **Meshes** | **0** | **Se ve SIN publicar el place.** Elimina la trampa que costó una sesión entera |
| **Scripts** | **0** | Sin backdoor. Es el riesgo real de los modelos del Toolbox y aquí no está |
| Suelo andable | 94 % de 225 sondeos | Sólido y transitable; el 6 % restante son los huecos entre parcelas |

### Cómo entra en el repo

`InsertService:LoadAsset` **no sirve**: probado, devuelve *"User is not authorized to access
Asset"*. Roblox sólo carga en runtime los assets de tu propia cuenta, así que un modelo
ajeno no puede vivir como un id en el código.

Entra como fichero: **`src/assets/Ciudad.rbxm`**, montado por Rojo en el árbol del proyecto.

Esto contradice la letra de una convención del proyecto ("el mundo se genera por código").
Se acepta a conciencia: el motivo de esa regla era que el `.rbxl` fuese desechable y todo
reproducible desde git, y un `.rbxm` versionado cumple el motivo aunque no sea diffeable.
**Generar la ciudad por código queda abierto como salida** si el mapa ajeno nos aprieta —
decisión de JJ, aplazada, no descartada.

### Lo que seguimos poniendo por código

Todo lo que es **juego**, sin excepción: almacén, taller, salida, destinos, detectores,
patrullas, zona segura. La ciudad aporta calles y edificios; ni una regla depende de ella.

### Las tres zonas

Las rutas dejan de ser "la misma recta de distinta longitud" y pasan a ser **barrios con
carácter**. Es el cambio que convierte una decisión aritmética (*¿cuánto ando por cuánto
cobro?*) en una cualitativa (*¿qué tipo de peligro sé manejar?*), y las preferencias son lo
que hace que un jugador vuelva.

| Zona | Multiplicador | Carácter | Detectores |
|---|---|---|---|
| 🟢 Verde | ×1 | El barrio de al lado. Calles anchas, poco que temer | 2-3 |
| 🟡 Ámbar | ×3 | El centro. Cruces, patrullas de paso | 8-10 |
| 🔴 Roja | ×10 | El extremo lejano. Denso, estrecho, vigilado | 16-20 |

`Config.RUTAS` cambia `distancia: number` por `destino: Vector3` y gana `detectores: number`.
La distancia deja de ser un parámetro y pasa a ser una consecuencia de dónde cae el destino.

---

## 4. El calor: lo que llena el viaje

Una barra de **0 a 3**, visible siempre. Es el reloj de tensión del trayecto: sube por lo
que haces, baja por lo que consigues, y decide cuánta policía tienes encima.

### Detectores

Postes fijos en la ciudad, colocados por código, más densos cuanto más caliente la zona.

- Radio **35 studs**. Entrar en él sube **+1** de calor y da un aviso inequívoco.
- **Un detector no puede volver a dispararse contra el mismo jugador en 30 s.** Sin ese
  bloqueo, quedarse quieto sobre un poste sube a 3 en dos segundos y el sistema deja de
  ser una decisión para ser una trampa.
- Se ven y se oyen. Un peligro invisible no es tensión, es injusticia.

### Patrullas

PNJ que aparecen al subir el calor y te buscan.

| Calor | Patrullas | Velocidad |
|---|---|---|
| 0 | ninguna | — |
| 1 | 1 | 18 studs/s |
| 2 | 2 | 20 studs/s |
| 3 | 3 | 22 studs/s |

**La regla de diseño que lo hace un juego y no un impuesto:** la patrulla es **más rápida
que tú pero está atada a las calles**; tú eres más lento pero puedes cortar por parques,
callejones y solares. Escapar es una habilidad de lectura del mapa, no una tirada de dados.
Esto es lo que convierte a la ciudad en mecánica en vez de decorado — y es el argumento de
peso para usarla.

Si una patrulla te alcanza (radio **6 studs**):

- Pierdes **la mitad de la carga**, redondeando hacia arriba. **No mueres.** Morir es que te
  echen de la sesión; perder mercancía es que te salga mal un viaje y quieras otro.
- El calor baja a **0**: te ha pillado, la cuenta empieza de nuevo.

### Cómo baja el calor

- **−1 cada 20 s** sin ningún detector ni patrulla a la vista.
- **A 0 al entrar en la zona segura** del almacén.

Sin esta válvula la única estrategia sensata es no salir, y el juego se acaba.

### El ladrón hereda el calor

Cuando alguien te roba, se lleva la carga **y las estrellas**. Es la mejor pieza del guion
nuevo: hoy robar es gratis y por eso es un impuesto; con esto, robar te compra el problema
del otro y el PvP pasa a tener consecuencia. Encaja además con la herencia de ruta que ya
existe (`Intercept.rutaTrasRobo`).

---

## 5. Arquitectura

Módulos nuevos, con la misma línea puro/impuro del resto del proyecto:

| Módulo | Dónde | Puro | Responsabilidad |
|---|---|---|---|
| `Heat.luau` | `shared/` | **Sí** | Subir, bajar, topes, bloqueo de re-disparo. Todo probado sin Roblox |
| `HeatService.luau` | `server/` | No | Calor por jugador, detección de proximidad, avisos, sync |
| `PatrolService.luau` | `server/` | No | Crear, mover y retirar patrullas; el alcance |
| `CityBuilder.luau` | `server/` | No | Montar la ciudad y plantar encima almacén, taller, destinos y detectores |

**No hay `Zones.luau`.** Se planeó y no se escribió: `Routes.luau` ya era exactamente ese
módulo —lee las rutas de `Config`, valida entregas— y añadir un segundo dueño de las zonas
habría garantizado que algún día el selector prometa un sitio y el servidor cobre por otro.
`Config.RUTAS` gana `destino` y `detectores`, pierde `distancia`, y `Routes` gana
`distancia()` (calculada, no almacenada) y `vigilancia()`.

`WorldBuilder.luau` se retira: su carretera recta es exactamente lo que este documento
elimina. Su red de seguridad y su lección sobre el límite de 2048 studs por eje se conservan
en `CityBuilder`.

**Movimiento de las patrullas:** `PathfindingService` de Roblox, que es nativo y evita
mantener a mano una red de calles. Medido sobre esta ciudad: **0,6-1,3 s por ruta calculada**
y un rodeo del +6 % sobre la línea recta. Aguanta.

### La patrulla va a pie, y no fue una elección estética

Medido, y es el hallazgo que más cambia el plan: con `AgentCanJump = false` **sólo la ruta
ámbar tiene camino**. Verde y roja devuelven `NoPath`. Con el salto activado, las tres
funcionan. Es decir: llegar a dos de los tres destinos **exige saltar** un bordillo o una
acera en algún punto.

Para el jugador da igual — salta sin pensarlo. Para la policía lo decide todo: un coche que
salta bordillos es ridículo, y un coche que no salta **no puede llegar a dos de las tres
zonas**. De ahí el reparto:

- **Agentes a pie**: son los que persiguen. Saltan, corren y alcanzan. Es el sistema.
- **Coches de patrulla** (más adelante): circulan por las calles principales como presencia
  y como detectores móviles. Llegan, y de ellos bajan los agentes.

Se construye lo primero. Los coches son lo segundo, y son decorado con función, no el
mecanismo — porque el mecanismo no puede depender de algo que no alcanza medio mapa.

---

## 6. Cómo sabremos si ha funcionado

La pregunta es la misma que falló, y se responde igual: jugando.

**El criterio de kill nº 1, otra vez: ¿aguantas diez minutos seguidos tú solo?** Si la
respuesta vuelve a ser no, el problema no es que falte contenido — es que el bucle no
engancha, y entonces toca pivotar de verdad.

Señales concretas que se miran en esa partida:

1. ¿Pasa algo cada 15-20 segundos, o hay tramos muertos?
2. ¿Has elegido alguna vez la roja **por gusto**, no por calcular?
3. Al escapar de una patrulla, ¿fue por leer el mapa o por suerte?
4. ¿Te ha pillado alguna vez de forma que te pareciera injusta?

---

## 6-bis. Los refugios

Seis sitios repartidos por el mapa —dos por ruta, desviados del trayecto— donde **no se roba
y no se persigue**. La regla no admite excepciones: si te pillaran en el último paso, entrar
dejaría de ser una decisión para ser una apuesta, y nadie vuelve a fiarse de un refugio que
le ha fallado una vez.

Resuelven dos cosas a la vez:

- **Huir deja de ser esperar.** Hasta ahora la única zona segura era el almacén, un punto en
  una esquina, así que al perseguido sólo le quedaba correr y aguantar. Correr *hacia* algo
  es una decisión.
- **La ruta elegida cambia el camino**, que es lo que pedía el veredicto de la primera
  partida. Aparecen trayectos que encadenan refugios —más largos, más seguros— frente a
  atajos expuestos que pagan igual pero sin red.

**El precio** es lo que lo separa de un botón de anular: el almacén apaga el calor de golpe;
un refugio lo baja a 5 s por nivel en vez de 20. Tres estrellas son quince segundos ahí
metido sin cobrar, y el tiempo es lo único que escasea en una sesión de diez minutos.

Y **las patrullas no se van**: se quedan rondando fuera. Verlas esperando convierte estar a
salvo en otra decisión —salir ahora y correr, o aguantar— en vez de en un final.

## 6-ter. El tema, todavía abierto (idea de JJ, 17/08)

`DISENO.md` dejó la ambientación sin decidir **a propósito**, y sigue sin decidirse. Sobre la
mesa hay una alternativa que conviene no perder:

> **Repartidor en vez de contrabandista.** Lo que te persigue son **ladrones** (PNJ y otros
> jugadores), y la policía pasa a ser justo lo contrario: los refugios.

Tres argumentos a favor, en orden de peso:

1. **Arregla una incoherencia de diseño.** Hoy hay dos amenazas que compiten —policía (PNJ) y
   jugadores (ladrones)— mecánicamente idénticas pero narrativamente opuestas. Unificarlas
   hace que **el PNJ sea el tutorial del jugador humano**: aprendes a esquivar ladrones de
   mentira y eso te prepara para los de verdad.
2. **El público.** Roblox es mayoritariamente 8-16 años y su moderación es estricta con temas
   de crimen. El descubrimiento es el cuello de botella real del proyecto (`MERCADO.md`), y un
   repartidor que esquiva ladrones no arrastra fricción en ninguna parte.
3. Encaja con los refugios, que ya están construidos y funcionan con cualquiera de los dos
   temas.

**Por qué no se ha hecho todavía:** cambiar el tema antes de jugar una sola partida con el
viaje lleno sería pintar la fachada de una casa que quizá no se sostiene. El renombrado es
una hora de trabajo mecánico; hacerlo *después* de saber que el bucle engancha cuesta lo
mismo y se hace con certeza.

## 7. Lo que NO entra

"Mini GTA" arrastra expectativas enormes, y el proyecto tiene una regla de oro escrita —*el
bucle antes que el contenido*— y un criterio de kill medido en D1. Si el objetivo pasa a ser
hacer un GTA, no se mide nunca nada. Fuera del alcance, explícitamente:

- Coches conducibles. La progresión es por capacidad, jamás por potencia.
- Armas y combate de cualquier tipo.
- Misiones, encargos o narrativa. `CLAUDE.md`: *nada de narrativa como motor*.
- Peatones, tráfico o vida urbana simulada.
- Interiores de los edificios.

---

## 8. Trampas conocidas que aplican aquí

Todas verificadas y pagadas ya en este proyecto:

- **`rojo build` borra el `PlaceId`** y con él el vínculo con la experiencia publicada. El
  flujo bueno es `rojo serve` + Connect. Ahora mismo el place está desvinculado por esto.
- Un `BasePart` se recorta **en silencio** a 2048 studs por eje.
- El personaje aparece **antes** de que el código construya el mundo: `CharacterAutoLoads`
  apagado durante el arranque.
- Verificar teletransportando **no verifica el mapa**. Cualquier cosa que dependa de la
  geometría se prueba con `Humanoid:MoveTo` y traza de posiciones.
- El `.rbxl` se compila **siempre** en `games/contrabando/contrabando.rbxl`.
