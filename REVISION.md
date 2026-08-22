# ¿Vamos en buena dirección?

> 2026-08-22. Cuarta parte, después de [`RESEARCH.md`](RESEARCH.md) (¿se gana dinero?),
> [`MERCADO.md`](MERCADO.md) (¿qué formato?) y [`TARGETS.md`](TARGETS.md) (¿qué juego?).
>
> Aquí: **qué ha pasado en cinco días de iteración, por qué no encontrábamos jugabilidad,
> y qué hacer ahora.** Escrito porque JJ dijo la frase que más importa de toda la semana:
> *"ya no sé de qué va el juego, la verdad."*
>
> Si el que lo hace no sabe de qué va, un jugador tiene **diez segundos** en Discover
> para saberlo, y no los va a usar.

---

## 1. El diagnóstico, en una frase

**Hemos construido todo lo que el plan decía que NO construyéramos, y no hemos construido
lo único que decía que probáramos.**

No es una interpretación. Está escrito en `TARGETS.md` §7, el 17 de agosto:

> **Lo que NO hay que hacer al principio:** arte bonito, muchos tipos de mercancía, mapa
> grande, historia. **Un almacén, tres destinos, una mercancía y la intercepción.** Si eso
> no engancha, nada de lo demás lo va a arreglar.

Y esto es lo que hay hoy:

| Lo que el plan pedía NO hacer | Lo que hay |
|---|---|
| Arte bonito | Asfalto, hormigón, 4 molduras por edificio, carrocería 3D, avenidas, rotonda |
| Muchos tipos de mercancía | **17 objetos** con 4 tamaños y 4 rarezas |
| Mapa grande | **24 manzanas**, 11 usos distintos, 2.373 piezas |
| Historia | Ladrones, contactos, habilidades, hitos, niveles |

| Lo que el plan pedía SÍ probar | Estado |
|---|---|
| Un almacén | ✅ existe |
| Tres destinos | ✅ existen |
| Una mercancía | ❌ hay diecisiete |
| **La intercepción** | ❌ **nunca la han jugado dos personas** |

Esa última fila es el juego entero. Está implementada, tiene pruebas puras, y **nadie la ha
jugado nunca con dos personas**. Es la mecánica por la que se eligió este target sobre los
otros dos.

---

## 2. Por qué pasó (y esto me toca a mí)

No fue por falta de disciplina: hay 1.402 pruebas, tres sondas y todo medido. Fue por
**elegir bien cada paso y mal la dirección**, cinco días seguidos.

El patrón, que se ve clarísimo mirando los commits:

1. JJ juega y dice algo cierto y concreto (*"el sitio es feo y confuso"*, *"no sé hacia
   dónde tirar"*, *"el modelo 3D es muy feo"*, *"¿por qué no podemos usar coches?"*).
2. Yo lo arreglo bien, con medición y verificación.
3. El juego queda mejor **en esa dimensión** y exactamente igual de lejos de tener un
   jugador que vuelva mañana.

Cada arreglo era correcto por separado. **La suma es un mapa muy trabajado para un juego
que nunca se ha publicado.**

Y hay una razón de fondo que JJ nombró y es exacta: *"en parte porque no sabíamos manejar ni
qué podíamos hacer en Roblox"*. Es verdad, y esa parte **ya está pagada**: hoy sabemos
mallas, física de vehículos, pathfinding, replicación, DataStore, el MCP, el sistema de
textos, las trampas. Eso no se pierde. Pero el aprendizaje se pagó con los días que tenía
que haber usado el bucle.

---

## 3. El mercado hoy, con datos de esta semana

### Lo que manda en el ranking cambió, y nos favorece

> *"Los juegos que están subiendo en discovery ahora mismo no son los de sesión media más
> larga: son los que tienen la tasa más alta de jugadores que vuelven en 24-48 h para una
> segunda sesión, más corta. Roblox ha desplazado el peso principal del ranking hacia la
> tasa de retorno y la re-interacción de sesión corta."*

Tres consecuencias directas:

- **Nuestro ciclo de 30 segundos no es un defecto.** Sesión corta y repetida es lo que la
  plataforma premia. Lo que falta no es alargar el viaje: es **un motivo para volver
  mañana**.
- **D1 es literalmente la métrica del algoritmo**, no sólo nuestra regla interna.
- **"Up and Coming" es la puerta realista** para un juego pequeño con velocidad de
  crecimiento. No hace falta competir de frente con Murder Mystery 2.

### Todavía entran juegos nuevos, y en meses

| Juego | Lanzamiento | Hoy |
|---|---|---|
| +1 Speed Keyboard Escape | enero 2026 | 500K concurrentes, 3.800 M visitas |
| Animal Hospital | mayo 2026 | 350K concurrentes, 1.400 M visitas |
| **ROB IT** | ~marzo 2026 | **191 M visitas en cinco meses** |

La ventana no está cerrada. Pero fíjate en qué son:

- **+1 Speed**: un bucle de una línea (corre, ganas velocidad, corres más).
- **Animal Hospital**: veterinaria **+ survival horror**. Dos géneros que no pintaban nada
  juntos. Ése es "el giro" del que hablaba `TARGETS.md`.
- **ROB IT**: *"entras a una run, coges herramientas, te infiltras en una casa, un banco o
  un museo, revientas la caja fuerte y metes el botín en un saco."* **Enfocado con láser en
  el acto de robar.**

### Y dos avisos que cambian supuestos nuestros

**El nicho de "reparto" NO está libre.** `TARGETS.md` daba el tema por libre y no lo está:
Delivery Simulator, Delivery Simulator X, Delivery Industry, Truck Sim World, Trucking
Legends, Trucking Tycoon. Están todos vivos en 2026.

Y nuestro propio `JUEGO.md` abre así: **"Eres un repartidor."**

Ése es el problema de identidad, y explica el *"no sé de qué va"*. Hemos construido un
juego de contrabando con tensión y lo estamos contando como un juego de reparto — que es un
género lleno, y encima el menos vendible de los dos.

**El robo, en cambio, es de lo que más crece.** Jailbreak lleva años con decenas de miles de
concurrentes, y ROB IT ha hecho 191 M de visitas en cinco meses siendo nuevo.

---

## 4. Lo que sí tenemos, y no es poco

Antes de decidir, el inventario honesto de activos:

- **Una ciudad propia, medible y generada por código**, con jerarquía viaria, once usos de
  manzana y sondas que la verifican sola. Eso es meses de trabajo que no hay que repetir.
- **Un motor de reglas probado**: rutas, peligro, rarezas x1/x10/x50/x135, niveles,
  habilidades, persistencia en la nube, textos multiidioma listos para el portal.
- **Vehículos con física de verdad**, medidos y afinados.
- **Un método de trabajo que funciona**: nada se da por bueno sin medirlo. Esto es lo más
  valioso de todo y ha cazado veinte fallos que habrían costado sesiones.
- **El aprendizaje de Roblox**, que era caro y ya está pagado.

**Nada de esto se tira en ninguna de las opciones de abajo.** La pregunta no es "¿empezamos
de cero?". Es "¿a qué apuntamos lo que ya tenemos?".

---

## 5. Las tres opciones reales

### Opción 1 — Publicar esta semana y medir · **mi recomendación**

Cerrar la portada (icono, miniatura, título), un onboarding de treinta segundos, y
publicar. No para triunfar: **para tener el primer dato real en cinco días de trabajo.**

- **Coste:** 2-3 días.
- **Qué contesta:** el CTR de la miniatura (¿alguien entra?) y el D1 (¿alguien vuelve?).
- **Por qué ahora:** todas las decisiones de esta semana —incluidas las mías— han sido
  opiniones sobre un juego que nadie ha jugado. Con 100 jugadores y dos números, la
  siguiente discusión dura diez minutos en vez de cinco días.
- **Riesgo real y hay que decirlo:** el juego no tiene un gancho de cinco palabras. Es
  probable que el CTR sea bajo. **Eso también es un dato**, y es el más barato de conseguir.
- **Lo que NO cuesta:** publicar no quema nada. Un juego con pocos jugadores no gasta su
  oportunidad; el algoritmo mira velocidad de crecimiento, y esa se puede provocar más
  tarde con una actualización y un vídeo.

### Opción 2 — Reenfocar del reparto al robo, y luego publicar

Girar el punto de vista: dejar de ser *el repartidor al que roban* y pasar a ser *el que
intercepta*. El material está casi todo hecho —rutas, peligro, botín, ciudad— y lo que
cambia es **a quién apunta el juego y qué se cuenta en la portada**.

- **Coste:** 1-2 semanas.
- **A favor:** es el género que más crece; el bucle se dice en cinco palabras; y es lo que
  `TARGETS.md` identificó como el motor de la mayor concurrencia de la historia.
- **En contra:** sigue siendo una apuesta sin datos, y el PvP necesita masa de jugadores
  para no estar vacío. Un juego de robar en el que no hay a quién robar es peor que uno de
  repartir en solitario.

### Opción 3 — Cambiar de target (A: excavación · C: restauración)

Los criterios de kill de `TARGETS.md` decían: **D1 < 15% con 100+ jugadores → pasar al
target A**.

- **Hoy no se puede aplicar**, porque no hay D1. Ejecutar esta opción ahora sería tirar
  cinco días por una corazonada, que es exactamente lo que el proyecto tiene prohibido.
- Se mantiene sobre la mesa **para después de la Opción 1**, no antes.

---

## 6. Recomendación

**Opción 1, y empezar por la identidad.**

Antes de la miniatura hay que contestar una pregunta de una línea, y es la misma que hizo
JJ: **¿de qué va este juego?** Las tres respuestas posibles con lo que hay hoy:

| Pitch | En cinco palabras | Nicho |
|---|---|---|
| A · Repartidor | *"Lleva paquetes por la ciudad"* | 🔴 Lleno y sin gancho |
| B · Contrabandista | *"Cruza la ciudad sin que te pillen"* | 🟡 Libre, tensión clara |
| C · Ladrón | *"Róbale la carga a otro"* | 🟢 En crecimiento, pero necesita gente |

**B es lo que el juego ES hoy** —hay peligro, hay ladrones, hay rutas por las que te ven
pasar— y **A es lo que estamos contando**. Alinear las dos cosas no cuesta código: cuesta
decidir, y luego cambiar el título, la miniatura y la primera frase.

Después de publicar, dos números deciden lo siguiente y ninguno es opinable:

| Número | Si sale bien | Si sale mal |
|---|---|---|
| **CTR de la miniatura** | Hay gancho: seguir | El problema es la portada, no el juego |
| **D1** | >15%: iterar el bucle | <15%: Opción 2, y si tampoco, Opción 3 |

---

## 7. Lo que hay que dejar de hacer

Esto vale para mí más que para nadie:

- **Nada de arte, mapa ni vehículos hasta que haya D1.** Ya está escrito en `CLAUDE.md`
  (*"el momento de hacer arte es cuando D1 lo justifique"*) y llevo dos días saltándomelo.
- **`Config.PROTOTIPO_COCHE` decide o muere.** Un flag de prototipo que sobrevive a su
  decisión es código muerto.
- **Quince documentos son demasiados.** 4.400 líneas, varios contradiciéndose y fechados
  entre el 17 y el 20. Sobreviven cuatro: `RESEARCH` / `MERCADO` / `TARGETS` (el análisis),
  este (el rumbo), `JUEGO.md` (qué hace el juego hoy) y `CLAUDE.md` (cómo se trabaja). El
  resto, a `docs/archivo/`.

---

## 8. Lo que no sabemos y hay que reconocer

- **Si el bucle engancha.** Cero partidas de un desconocido. Las únicas opiniones son de JJ,
  que sabe cómo funciona por dentro, y las mías, que lo escribí.
- **Si la intercepción es divertida o frustrante.** Nunca se ha jugado entre dos personas.
- **Si la portada tiene CTR.** No existe.

Tres preguntas, y las tres se contestan publicando. Ninguna se contesta iterando más.

---

## Fuentes

- [Optimizing Discovery — Roblox Newsroom, junio 2026](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox)
- [How the Roblox Discovery Algorithm Works in 2026 — ROLearn](https://rolearn.dev/insights/roblox-game-discovery-algorithm-2026/)
- [Roblox new algorithm targets long-term retention — GAMES.GG](https://games.gg/news/roblox-algorithm-adult-games-retention/)
- [Most Played Roblox Games, agosto 2026 — BloxQuiz](https://www.bloxquiz.gg/stats/most-played)
- [ROB IT vs Jailbreak (2026) — Earnaldo](https://earnaldo.com/blog/rob-it-vs-jailbreak)
- [The 16 Best Heist Games Right Now, Q3 2026 — CrimeNet Gazette](https://www.crimenetgazette.com/post/16-most-popular-heist-games-right-now-q3-2026-ranked-by-the-crimenet-popularity-index)
- [Best Roblox games right now, agosto 2026 — Sportskeeda](https://www.sportskeeda.com/roblox-news/best-roblox-games-to-play-right-now)
- [Trucking Tycoon: EXPANDED & ENHANCED — Roblox](https://www.roblox.com/games/140423719422750/Trucking-Tycoon-EXPANDED-ENHANCED)
