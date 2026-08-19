# Mapa propio: una retícula alineada al juego

> 2026-08-19. Sustituye a `mapa/DISENO-MAPA.md`, que diseñó una cuadrícula de
> 1600×1600 para un mundo que ya no existe. El generador (`src/server/MapBuilder.luau`)
> se conserva como base y se reescribe su geometría.
>
> Lo que responde este documento: por qué el mapa deja de ser la ciudad del Creator
> Store, qué retícula la sustituye, cómo se alinea a lo que ya está medido, y qué
> código desaparece con ella.

---

## 1. Por qué ahora

Tres partidas seguidas con veredicto negativo. Preguntado en qué momento dejaba de
apetecer seguir, la respuesta fue **durante el trayecto**, y de las causas ofrecidas se
señalaron tres:

- no sé hacia dónde tirar,
- no pasa nada por el camino,
- el sitio es feo y confuso.

Dos son del mapa. La tercera **también depende del mapa**, aunque no lo parezca: un
atajo sólo es un atajo si se ve que lo es, y "el cruce malo de la roja" sólo se puede
diseñar si sabemos dónde están los cruces. Sobre una ciudad genérica de 7.152 piezas
que no controlamos, no hay dónde colgar los acontecimientos del trayecto.

Lo confirma el trabajo del 19/08: `acceso()`, `limitarDesdeExtremos()`, `asentar()`, la
joroba del acceso verde, el destino del barrio bajo un árbol, el canto de 3,4 studs que
dejó las cuatro rutas sin camino. Nada de eso era diseño de juego. Era pelearse con un
terreno ajeno.

**Lo que NO afirma este documento**: que el mapa haga que el bucle enganche. Eso sigue
sin estar probado y el criterio de kill de `TARGETS.md` §7 no se relaja. Lo que el mapa
quita son las dos causas que se han repetido tres veces, y desbloquea la tercera.

## 2. La decisión de fondo: la retícula se alinea al juego

El instinto sería recolocar el juego sobre un mapa limpio centrado en (0,0). Sería caro
y no aportaría nada: las distancias del 19/08 están medidas y equilibradas (ciclo de
tutorial de 26 s), y de ellas cuelgan `Config`, `Lairs`, `Shelter`, `Contacts` y las 81
comprobaciones de `SelfCheck`. Mover el mundo tira ese balance y obliga a medirlo de
cero.

Así que **la ciudad se planta en las coordenadas que ya hay**. No se tocan:

- `Config.ALMACEN_POS = (-668, 19.2, 815)`
- `Config.TALLER_POS = (-580, 19.2, 815)`
- `Config.POLIGONO_CENTRO = (-620, 19.2, 880)`, tamaño `360 × 250`
- `Config.POLIGONO_SALIDA = (-620, 19.2, 755)` — la boca del recinto

Sí cambian los cuatro destinos de `Config.RUTAS`, que hoy están donde el raycast
encontró suelo llano y no en un sitio elegido. Ver §4.

`Config.POLIGONO_ENGANCHE` desaparece: existía para saber a qué calle de la ciudad ajena
enganchar la salida del recinto. Con retícula propia, la boca del recinto **está** en una
calle.

## 3. Geometría

| | |
|---|---|
| Manzana | 120 × 120 |
| Calle | 26 de ancho |
| Paso de retícula | **146** (120 + 26) |
| Retícula | **4 columnas × 3 filas** = 12 manzanas |
| Cota del suelo | y = 19.2, plana (la misma del almacén) |

**Calles verticales** (X constante), la central pasando por la boca del recinto:

```
X = -766, -620, -474, -328, -182
```

**Calles horizontales** (Z constante), la primera justo bajo la boca:

```
Z = 754, 608, 462, 316
```

**Extensión total**: X ∈ [−779, −169], Z ∈ [303, 767]. Son **610 × 464 studs** frente a
los 1600 × 1600 del spec anterior: una octava parte del área. Doce manzanas, no treinta y
seis. El mapa se cruza a pie en unos 40 segundos y se lee entero desde cualquier cruce.

### Las zonas

Tres bandas **por filas**, alejándose de casa. Numeración: columna 1 = oeste, fila 1 = la
más cercana al recinto.

| Zona | Manzanas | Edificios/manzana | Altura | Callejones |
|---|---|---|---|---|
| Verde | fila 1 — Z ∈ [608, 754] | 1–2 | 12–24 | 0 — la plaza es la escapatoria |
| Ámbar | fila 2 — Z ∈ [462, 608] | 2–3 | 24–44 | 1 por manzana |
| Roja | fila 3 — Z ∈ [316, 462] | 3–5 | 44–80 | varios por manzana |

Bandas y no diagonales por un motivo mecánico: así **la zona de una ruta es la zona que
hay que atravesar para llegar a su destino**. Con las zonas en diagonal (como proponía el
spec anterior) el destino de la roja se alcanzaba sin pisar la zona roja, que es
exactamente lo contrario de lo que la ruta promete.

La **plaza** de la verde va en (1,1): manzana sin edificios, enmarcada por calle. Los
**solares** (vías de escape: la patrulla no los cruza en diagonal y el jugador sí) van en
(3,2) para la ámbar y (2,3) para la roja. Posiciones fijas a propósito: se aprenden.

La semilla sigue siendo fija (`7891`), así que el mapa es idéntico en todas las partidas.
La variabilidad es entre manzanas, no entre sesiones — es lo que permite reconocer un
sitio.

## 4. Los cuatro destinos van en cruces

Hoy los destinos son `(-650,680)`, `(-620,555)`, `(-481,456)` y `(-222,421)`: coordenadas
donde el raycast encontró terreno llano. Ninguna cae en un cruce, porque no había cruces
que elegir.

Con retícula propia cada destino va **en una esquina de calle**. Eso es lo que convierte
"ve hacia la luz" en "recto y a la izquierda en el segundo cruce", que es la diferencia
entre orientarse y no orientarse.

| Ruta | Destino nuevo | Camino desde la boca | Giros | Zona que atraviesa | Camino hoy |
|---|---|---|---|---|---|
| barrio | (−620, 19.2, 608) | 147 | 0 | verde | 147 |
| verde | (−766, 19.2, 608) | 293 | 1 (oeste) | verde | 322 |
| ámbar | (−474, 19.2, 462) | 439 | 1 (este) | verde + ámbar | 338 |
| roja | (−328, 19.2, 316) | 731 | 1 (este) | verde + ámbar + roja | 631 |

Tres cosas que esta tabla arregla y que no estaban en el plan:

1. **La progresión se vuelve legible**: 147 / 293 / 439, un paso de retícula entre cada
   una, y la roja al doble de la ámbar. Hoy la verde y la ámbar están a 322 y 338 — a
   efectos del jugador, la misma distancia, de modo que elegir entre ellas no significa
   nada.
2. **Todos los destinos están a un giro o ninguno** de la salida. Deja de ser un
   argumento de fe y pasa a ser comprobable (§7).
3. **Las cuatro salen en abanico**: la verde al oeste, la ámbar y la roja al este a
   distinta profundidad, el barrio recto. Cuatro direcciones distintas se recuerdan; hoy
   los cuatro destinos están apiñados en el mismo cuadrante y sólo se distinguen por lo
   lejos que quedan.

La roja da un salto mayor (731 frente a los 439 de la ámbar) y es deliberado: es la ruta
que exige nivel y vehículo (`exigeMotor`), y ya hoy está a casi el doble que la ámbar
(631 frente a 338). El salto se conserva.

Las distancias de la tabla son **Manhattan sobre la retícula**, que en una cuadrícula sin
obstáculos es el camino real. Se verifican con `PathfindingService` al construir; si
alguna se desvía más de un 15 %, se mueve el cruce, nunca el balance de la economía.

## 5. Lo que desaparece

La mitad del valor del cambio está aquí. Con suelo plano y controlado se cae de
`CityBuilder.luau`:

| Qué | Por qué existía |
|---|---|
| `acceso()` y su envolvente de conos | Tender un camino transitable sobre terreno irregular |
| `limitarDesdeExtremos()`, `SALTO_MAXIMO`, `LEVANTE_MAXIMO` | Evitar escalones que cortan el navmesh |
| `asentar()` | Bajar lo que quedaba flotando y subir lo enterrado |
| Los rebotes de `sueloDeLaCiudad()` | Saltarse las 2.048 copas de árbol del mapa ajeno |
| `Config.POLIGONO_ENGANCHE` | Saber a qué calle ajena enganchar la salida |

Son varios cientos de líneas cuya única razón de ser era no controlar el terreno.
`sueloDeLaCiudad()` no se borra —sigue habiendo edificios sobre los que no plantar— pero
se queda en un raycast simple sin cadena de rebotes.

## 6. Lo que NO cambia

Por la regla de oro: **ni una regla del juego depende del mapa**.

- La economía, las rarezas, los valores de entrega.
- El almacén: produce con tope, cálculo perezoso, nunca asaltable.
- Los vehículos: progresión por capacidad y acceso, jamás por potencia.
- El robo, el calor, las patrullas, los refugios y las guaridas.
- El bucle: recoger → elegir → viajar → cobrar → invertir.
- El contrato con `CityBuilder`: un `Model` llamado `Ciudad` en `workspace` que sirve de
  suelo para sus raycasts. `MapBuilder.buildCiudad(padre)` sigue siendo la única función
  pública.

## 7. Cómo sabremos que funciona

`SelfCheck` no se relaja: se aprieta. La retícula permite comprobar automáticamente cosas
que con la ciudad ajena eran imposibles.

Comprobaciones nuevas:

1. **Cada destino está a dos giros o menos** de la boca del recinto. Es "no sé a dónde
   ir" convertido en una prueba.
2. **Desde cada cruce se ve al menos un hito de zona** sin obstrucción (raycast al hito
   más cercano de su zona).
3. **El suelo es plano donde se camina**: ninguna calle tiene un salto de cota mayor de
   0,5 studs entre segmentos contiguos. Con retícula propia esto debe ser trivialmente
   cierto; si falla, hay un bug de generación.
4. **Las cuatro distancias de camino** están dentro del 15 % de la tabla de §4.

Las 81 comprobaciones actuales siguen corriendo. Las que dependen de coordenadas de
destino se actualizan a los cruces nuevos.

Y la prueba que ninguna sonda sustituye: **JJ juega y dice si sabe a dónde va**.

## 8. Riesgos

- **Que la ciudad de 12 manzanas se quede corta.** 610 × 464 studs es poco mapa. Es
  deliberado: el problema medido es que no se entiende dónde se está, no que falte
  espacio. Crecer es añadir columnas a la retícula, que es barato; encoger un mapa
  al que ya se le ha colgado contenido, no.
- **Que los refugios y guaridas no quepan.** `Lairs` y `Shelter` reparten sobre el tramo
  útil de cada ruta con márgenes en studs (`REFUGIO_MARGEN_CASA = 85`,
  `REFUGIO_MARGEN_DESTINO = 55`, `ZONA_SEGURA_RADIO = 90`). Con la ruta del barrio a 147
  studs, el tramo útil es de 7 studs: **el barrio se queda sin refugios**, igual que hoy,
  y `SelfCheck` ya tiene el guard. Para verde (293) y arriba sí caben.
- **Rendimiento**: 12 manzanas × 2-4 edificios ≈ 35 edificios, más calles y aceras.
  Estimado por debajo de 300 piezas, frente a las 7.152 del `.rbxm`.
- **La sesión del mapa**. `CLAUDE.md` reparte `mapa/` y `MapBuilder.luau` a la sesión del
  mapa. Este trabajo los toca. Si esa sesión está viva, hay que parar y repartir de nuevo.

## 9. Reversibilidad

Volver a la ciudad del Creator Store es restaurar el bloque `"Ciudad"` en
`default.project.json` — el `.rbxm` no se borra. Pero **no es gratis a partir de la fase
2**: los destinos nuevos caen en cruces que sólo existen en la retícula propia, así que
revertir el mapa exige revertir también los destinos en `Config`. Los dos cambios van en
el mismo commit por ese motivo.

## 10. Fases

| Fase | Qué entra | Pregunta que responde |
|---|---|---|
| **1. Retícula** | Suelo plano, calles, aceras, 12 manzanas vacías. Destinos movidos a cruces. `default.project.json` deja de montar el `.rbxm` | ¿Compila, carga, y se llega a los cuatro destinos rodando? |
| **2. Carácter** | Edificios por zona con densidad y altura, plaza, callejones, solares, tres hitos de zona | ¿Se distinguen las tres zonas al caminar? ¿Se sabe dónde se está? |
| **3. Limpieza** | Se borra de `CityBuilder` lo de §5. `SelfCheck` con las cuatro comprobaciones nuevas | ¿Sigue todo verde con varios cientos de líneas menos? |
| **4. El camino** | *Fuera de este spec.* Acontecimientos del trayecto, ya con calles que controlamos | ¿Pasa algo por el camino? |

La fase 4 es la tercera queja, y es el motivo por el que las otras tres existen. No entra
aquí: necesita su propio diseño, y necesita que este mapa esté en pie primero.

## 11. Estética

No entra. Cubos de colores, la paleta mínima que ya tiene `MapBuilder`. El arte se
trabaja cuando el bucle esté probado, y el bucle no lo está.
