# El primer bucle: entregar pronto, saber qué hacer, y notarlo

> 2026-08-18. Segunda tanda salida de comparar el juego con *[X2] +1 Speed Keyboard Escape*.
> La primera atacó el viaje vacío (contactos, racha, habilidades); ésta ataca **el primer
> minuto**, que es donde se decide si alguien vuelve.
>
> Criterio del proyecto sin cambios (`TARGETS.md`): **retención D1**.
>
> Lo pidió JJ así: *"las primeras misiones tienen que ser más cortas y sencillas, y eso
> podríamos hacerlo entregando paquetes más cerca"*, con un encargo de fondo — **copiar lo
> que funciona y no complicarse**.

---

## 1. El problema, medido

Nuestro primer minuto, cronometrado:

| Tiempo | Qué pasa |
|---|---|
| 0-15 s | Apareces y coges 3 piezas de la nave |
| 15-30 s | Andas hasta la salida (**176 studs**) y eliges destino |
| 30-90 s | Viaje |
| **~100 s** | **Primera recompensa** |

En el juego de referencia la primera recompensa llega a los **3 segundos**. No es una
diferencia de gráficos: es que el nuestro cobra durante minuto y medio antes de pagar la
primera vez.

Y las distancias reales, medidas sobre el camino del pathfinder (no en línea recta):

| Ruta | Andando | Cargado a 14,6 studs/s |
|---|---|---|
| Verde | **823 studs** | ~56 s |
| Ámbar | 1.101 | ~75 s |
| Roja | 1.884 | ~129 s |

Ida y vuelta por la verde son ~1.650 studs, casi dos minutos sólo de caminar. Para el
jugador que acaba de entrar, eso es todo lo que hay antes del primer premio.

---

## 2. Decisiones tomadas

| | Decisión |
|---|---|
| Primer bucle | **Escalera de destinos**: uno de barrio por DEBAJO de la verde, que se abre al entregar |
| Qué abre el peldaño | **Entregas hechas**, con el objetivo a la vista. Los cortos **no se cierran nunca** |
| Alcance | Escalera + objetivo visible + **feedback al cobrar** |
| Fuera | Recompensa diaria, regalo por grupo, y tocar las rutas que ya funcionan |

---

## 3. El destino de barrio

Una ruta nueva **por debajo** de la verde. El juego actual no se modifica: se le añade una
rampa de entrada.

| | |
|---|---|
| Distancia | ~250 studs desde la salida (**~18 s de ida**, primera entrega en ~45 s) |
| Multiplicador | **×0,5** |
| Licencia | ninguna |
| Peligro | **1** esquina fichada, sin guaridas propias |
| PvP | ninguno |
| Contactos | 3 sueltos, 0 racimos |

**El ×0,5 no es un castigo: es lo que impide que domine.** Tres cajas comunes son 15 monedas
en ~45 s, o sea 20 por minuto; la verde da 30 en ~100 s, o sea 18 por minuto. Casi iguales.
El barrio es la puerta de entrada, no un atajo permanente — y por eso tampoco hace falta
cerrarlo.

**Coste real, dicho por delante:** una ruta nueva no es una línea de `Config`. `CityBuilder`
tiene que plantarle destino, cartel, acceso asfaltado hasta la calle más cercana y su esquina
fichada. Es justo donde este proyecto se ha equivocado siempre — el taller en un descampado,
la carretera enterrada, los detectores en las azoteas — así que va con la maquinaria que ya
existe (`sueloTransitable`, `calleMasCercana`, `acceso`) y **se mide antes de darla por
buena**.

---

## 4. El objetivo siempre visible

Un contador de entregas y una lista corta de hitos. El actual se enseña en la línea de
**misión** del HUD, que ya existe: no ocupa sitio nuevo en una pantalla que ya está llena.

| Hito | Condición | Qué da |
|---|---|---|
| 1 | 1 entrega | Se abre la **ruta verde** + 50 monedas |
| 2 | 3 entregas | 250 monedas (el monopatín cuesta 150) |
| 3 | nivel 3 | La **ámbar** *(ya existe: sólo se anuncia)* |
| 4 | 8 entregas | 1.000 monedas |
| 5 | nivel 8 + vehículo de motor | La **roja** *(ya existe: sólo se anuncia)* |

Los hitos 3 y 5 no son mecánica nueva: la licencia por nivel está hecha desde el 18/08. Lo
único que cambia es que ahora **se anuncia** en vez de descubrirse chocando contra ella.

**Por qué entregas y no nivel:** el nivel sube con el dinero cobrado, así que su ritmo
depende de qué llevabas encima, no de cuánto has jugado. Un jugador con suerte en el sorteo
de rarezas saltaría dos peldaños en su primer viaje y otro se quedaría atascado haciendo lo
mismo. Contar entregas mide lo que el jugador hace.

**Y los cortos no se cierran.** Quitarle una puerta a alguien que está aprendiendo se lee
como castigo; y como el barrio paga poco, nadie se queda ahí por gusto.

---

## 5. El cobro se nota

La pieza más barata de las tres y la que más cambia la sensación de que el juego responde:

- **Número flotante** sobre el personaje al entregar (`+240`), que sube y se desvanece.
- Un **`+1`** pequeño al recoger cada contacto — literalmente lo que hace el juego de
  referencia, y la razón de que andar por su mapa se sienta como progresar.
- El dinero del HUD **contando hacia arriba** en vez de saltar de golpe.

Nada de esto toca una sola regla: son las mismas cifras, dichas de otra manera.

---

## 6. Arquitectura

Respeta la línea puro/impuro de siempre.

### Puro (`src/shared/`)

- **`Goals.luau`** — los hitos: condición, recompensa, y cuál es el actual dado un estado.
  Sin tocar Roblox. Con `tests/Goals.spec.luau`.
- **`Config.luau`** — la ruta `barrio` y la tabla de hitos.

### Servidor

- **`estado.entregas`** (número, persistido) y **`estado.hitos`** (cuáles se han cobrado).
- El enganche va en **`CargoService`**, donde ya se cobra: al entregar, `+1` entrega,
  comprobar hitos, pagar la recompensa y avisar.
- **`Routes.disponible`** pasa a mirar también los hitos, no sólo el nivel. El servidor sigue
  decidiendo: el selector pinta, pero un remote manipulado manda el id que quiera.
- **`CityBuilder`** planta el destino del barrio con su acceso, cartel y esquina fichada.

### Cliente

- **`Popups.luau`** — los números flotantes. En `Heartbeat` para la lógica; la animación
  puede ir en un `TweenService`, que no depende de `RenderStepped`.
- **`Hud`** — la línea de misión pasa a decir el hito actual y su progreso ("1 de 3
  entregas").

---

## 7. Verificación

1. **Pruebas puras**: los hitos avanzan en orden, no se cobran dos veces, y un estado
   corrupto no desbloquea nada.
2. **`SelfCheck`**: el destino del barrio tiene calle, está a la altura del suelo, y hay
   camino a pie desde la salida. La misma sonda que ya cubre los otros destinos.
3. **Medido andando**: tiempo real desde que apareces hasta que cobras la primera vez.
   **El objetivo es ≤ 50 segundos** (hoy son ~100). Si no baja de ahí, el cambio no ha
   servido, por muy escrito que esté el código.

---

## 8. Fuera de alcance

- Recompensa diaria por volver y regalo por unirse al grupo. Los dos atacan D1, pero no
  significan nada hasta que exista un motivo para volver el primer día.
- Tocar las rutas verde, ámbar y roja, o sus distancias.
- Cualquier sistema de encargos con destino variable: es un subsistema entero y contradice
  el encargo de no complicarse.
