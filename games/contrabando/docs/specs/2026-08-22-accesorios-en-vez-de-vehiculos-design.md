# Accesorios en vez de vehículos: el garaje se convierte en equipo

**Estado: APROBADA por JJ el 22/08, y la fase 3 ya está hecha y medida.** Sus dos
decisiones: se empieza por las botas y los tejados (la fase que contesta si la idea
vale), y **coche y furgoneta salen del catálogo mientras la moto se queda** — se corta
donde el cuerpo aguanta.

> *"Pues cambiemos los vehículos por accesorios entonces, que sí que pueda usar el
> personaje, tendría más sentido, ¿no? Al final son mejoras para ir a los sitios más
> difíciles."* — JJ, 22/08

La segunda frase es la que manda en todo este documento. Los vehículos de hoy son
**capacidad y velocidad**; JJ dice que lo que deberían ser es **acceso**. Y acceso es
justo lo que la regla de oro del proyecto lleva diciendo desde el principio —
*"la progresión va por capacidad y acceso, NUNCA por potencia"*— sin que ninguna de las
ocho compras del garaje abra un solo sitio nuevo.

---

## 1. La buena noticia: casi no hay que romper nada

Un vehículo, en este código, ya es exactamente un accesorio: **un objeto equipado, que
se compra con dinero, que se desbloquea por nivel, y que modifica capacidad, velocidad,
tamaño admitido, cuánto pierdes al ser alcanzado (`expone`) y a qué distancia te fichan
(`bulto`)**. Eso son 23 ficheros que NO hay que reescribir: `GarageService`,
`Persistence`, `PlayerState`, `Cargo`, `Heat`, la interfaz del garaje y sus pruebas
siguen valiendo tal cual.

Lo que cambia es qué se dibuja, qué hace cada peldaño y cómo se llama. Es un cambio de
**contenido**, no de arquitectura — y por eso es abordable.

Sólo hay dos piezas que se rompen de verdad. Están en la sección 4.

## 2. Lo que la ciudad ya tiene, medido hoy (22/08)

Antes de diseñar sobre el aire, se midió el mapa recién ampliado:

| Altura sobre el suelo | Superficies pisables grandes | Ejemplo |
|---|---|---|
| 8 – 14 studs | **11** | tejado de nave (46 × 34), marquesina de la gasolinera |
| 14 – 24 | **17** | naves de talleres, alas de la escuela (104 × 26) |
| 24 – 45 | **14** | bloque medio de la ámbar (104 × 34) |
| más de 45 | **6** | torres de la roja (104 × 40) |

**Son 48 azoteas grandes y planas. Ya están construidas.** No hay techo invisible: por
encima de la ciudad hay cielo abierto.

Y tres números más que deciden el diseño entero:

- **Ningún salto cruza una calle.** Con salto 10 el alcance horizontal es 13,3 studs;
  con 17, son 17,4; con el impulso de hoy (22), 19,8. La calle mide **26**. Es decir:
  **la retícula de calles sigue siendo la estructura del mapa también por arriba**, y
  cruzar de manzana a manzana exige algo más que saltar.
- **El impulso de salto ya sube a 22 studs**, o sea a 28 de las 48 azoteas. La mecánica
  está en el juego, probada, desde el 20/08 — pero como consumible de ocho segundos.
- **Los 19 alijos están a ras de suelo.** Los diecinueve. **Hoy no existe ni una sola
  razón para subirse a nada**, y ése es exactamente el hueco que este sistema llena.

## 3. El diseño: la ciudad tiene un piso de arriba

**Dos ranuras, y la decisión está en tener que elegir las dos antes de salir:**

- **CARGA** — cuánto te llevas.
- **MOVILIDAD** — por dónde puedes ir.

Y la regla que las ata, que es el corazón de todo esto:

> **Cuanto más llevas, más pegado al suelo vas. Los accesorios te despegan del suelo, y
> arriba no hay patrullas — pero tampoco se entrega desde un tejado.**

Con eso, el viaje cargado sigue siendo por la calle, como hoy; y el piso de arriba es
para ir ligero: explorar, colocarte, huir, y recoger los alijos que se muden allí.

### Carga (se compra con dinero)

| id | coste | nivel | capacidad | tamaño máx | qué te quita |
|---|---|---|---|---|---|
| `bolsa` (inicial) | 0 | 1 | 3 | 1 | nada |
| `mochila` | 150 | 1 | 6 | 2 | nada |
| `arnes` | 1.400 | 3 | 10 | 3 | no puedes usar el gancho |
| `carro` | 4.500 | 6 | 16 | 4 | nada vertical; estorba en callejones |
| `remolque` | 15.000 | 10 | 26 | 4 | **sólo calzada** (hereda `soloCalzada` tal cual) |

El `carro` y el `remolque` **se arrastran**: vas a pie —con la física que ya funciona— y
van detrás con retardo, que es justo el movimiento que un objeto arrastrado puede hacer
de forma rara sin que chirríe. Y traen decisión propia: **se pueden soltar para correr**,
dejando la carga en la calle.

### Movilidad (se compra con dinero)

| id | coste | nivel | qué abre |
|---|---|---|---|
| `monopatin` | 150 | 1 | velocidad en llano, va por todas partes. **Se queda como está** |
| `botas` | 2.500 | 4 | salto permanente ×1,7 (17 studs): gradas, marquesina, tejados de nave |
| `cizalla` | 4.000 | 6 | abre verjas y rejas: convierte muros en atajos (la escuela, los patios) |
| `gancho` | 8.000 | 8 | azoteas altas, y **lo único que cruza una calle por arriba** |

Total ≈ 35.550 monedas contra las 31.950 del garaje actual: **el sumidero de dinero se
conserva casi exacto**, así que la economía no hay que volver a medirla.

### Por qué esto hace el juego mejor y no sólo distinto

- Cada compra **cambia lo que puedes hacer**, no un número. Hoy los cinco peldaños caros
  comparten `soloCalzada` y se diferencian en tres cifras.
- **Usa la ciudad que ya existe.** 48 azoteas, marquesinas, gradas y andamios que hoy no
  sirven para nada.
- **Le da destino a la exploración.** Mover una parte de los alijos arriba convierte el
  accesorio en algo que se paga solo, y ahora mismo los alijos son *"lo único que se gana
  fuera del camino"* con los diecinueve tirados en el suelo.
- **Se apoya en el motor en vez de pelearse con él.** Nada de esto necesita física de
  conducción: saltar, escalar y arrastrar son cosas que un `Humanoid` hace bien.

## 4. Lo que se rompe, y con qué se sustituye

Dos cosas, y las dos hay que decidirlas a propósito:

**a) `soloCalzada`.** El propio `Roads.luau` la llama *"la mejor pieza que se le ha
añadido al juego"*, y con razón: es lo que convierte cada trayecto en dos versiones —por
la calle deprisa y visible, o a pie por los atajos. Si todo el mundo va a pie, esa
decisión se evapora.
**Se sustituye por el peso**: la carga grande te ata al suelo y a la calzada (el
`remolque` la conserva literal), y los accesorios de movilidad no funcionan cargado. Es
la misma tensión —capacidad contra exposición— por otro sitio.

**b) La llave de la mercancía grande.** `Config.TAMANOS` dice *"no puedes llevar algo
grande sin un vehículo para ello"*, y el piano de ×50 es lo que le da destino al dinero.
**El `carro` y el `remolque` son esa llave**, con los mismos `tamanoMaximo` de hoy.

**Y un riesgo que hay que vigilar**: si arriba se está a salvo, todo el mundo irá por
arriba siempre. Las tres contrapartidas —no se sube cargado, no se entrega desde un
tejado, y las calles no se cruzan de un salto— tienen que sostenerse. Si no lo hacen, el
piso de arriba deja de ser una decisión y pasa a ser la respuesta a todo.

## 5. Plan por fases, cada una jugable

> **Lo hecho el 22/08 (fase 3).** El accesorio se llama `impulsor` y es una **mochila
> propulsora**, no unas botas, y el cambio no es cosmético: las piezas del vehículo se
> sueldan al `HumanoidRootPart`, así que un calzado se quedaría quieto mientras el pie
> se mueve — es la razón exacta por la que los patines se retiraron el 19/08. En la
> espalda no hay conflicto, y además es la palabra que usó JJ: propulsores.
>
> Medido en partida: el tejado **se pisa** (estado `Running`, suelo `SmoothPlastic` a
> 17,7 studs de altura), el salto con el impulsor **sube 17,1 studs** contra los 16 del
> tejado más alto sembrado, los seis alijos altos caen entre 12 y 15, y **desde la calle
> justo debajo no se recogen y desde el tejado sí**.
>
> Y por el camino salieron dos fallos que la sola lectura del código no da: la recogida
> de alijos **no miraba la altura** (un radio de 18 studs en planta regalaba desde la
> calle un alijo puesto a 16 de altura, o sea el sistema entero convertido en nada), y
> el octavo expositor del taller volvió a caer en el centro de la losa porque el
> desplazamiento de media plaza sólo valía para un número impar de vehículos.

1. **Renombrar y redibujar.** El catálogo pasa a accesorios sin cambiar ni un número:
   mismos costes, capacidades y niveles, pero cada uno se dibuja en el personaje
   (mochila a la espalda, monopatín debajo) en vez de ser una caja de 20 piezas. Aquí el
   juego ya se ve distinto y no se ha roto nada.
2. **Las dos ranuras.** Separar carga de movilidad, con su interfaz. La decisión de
   "¿ligero o cargado?" aparece aquí.
3. **Las botas y el piso de arriba.** Salto permanente y alijos que suben a los tejados.
   Es la fase que hay que medir de verdad: si nadie sube, el sistema no vale.
4. **El gancho y la cizalla.** Los dos peldaños caros, que son los que cruzan calles y
   abren muros.
5. **El carro arrastrado**, y retirar coche y furgoneta.

## 6. Lo que queda por decidir

Decidido ya: **la moto se queda, coche y furgoneta se van**, y **suben un tercio de los
alijos** (seis de diecinueve) — los suficientes para que el impulsor tenga sentido y los
bastante pocos para que quien no lo ha comprado no se quede sin explorar.

Abierto:

- **Si el `carro` se arrastra de verdad** o es sólo capacidad con penalización.
- **Cómo se retiran coche y furgoneta sin romper las partidas guardadas.** Quien ya los
  tenga comprados los tiene en su garaje y en el DataStore; hace falta una migración, y
  por eso esto no se hizo a la vez que la fase 3.
- **Si el impulsor se queda compitiendo por la ranura del vehículo** o pasa a una ranura
  propia (fase 2). Hoy compite, y eso ya es una decisión: cuatro huecos de carga contra
  los nueve de la bici, que cuesta lo mismo.

Y el criterio final es el de siempre: **esto se mide en D1 y en sesión media.** La fase 3
es la que contesta si la idea vale; las demás son trabajo.
