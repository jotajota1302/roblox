# Los vehículos grandes: qué está midiendo mal y qué se puede hacer

**Estado: ABIERTO. Esto no decide nada.** Es la vuelta que pidió JJ el 22/08 —
*"estudiaría los movimientos del jugador con los vehículos y si no lo vemos funcionar
bien pensamos si en vez de vehículos grandes dejen de ser propulsores o herramientas
como bate etc para defenderte"*— con los números delante, para que la decisión se tome
mirando algo y no de memoria.

---

## 1. Lo que hay hoy, medido

**No existe física de vehículo en este juego.** Un vehículo es `Humanoid.WalkSpeed` más
un decorado soldado al personaje. Medido en partida (22/08, coche montado):

| Medida | A pie | En coche |
|---|---|---|
| Giro de 180° a los 0,1 s | 114° | 106° |
| Giro de 180° a los 0,5 s | 172° | 178° |
| Piezas soldadas | 0 | 20 (la mayor 5,5 × 4,5 × 7) |

Es decir: **el coche gira exactamente igual que un peatón.** Media vuelta en una décima
de segundo, pivotando sobre su propio centro, con radio de giro cero.

Eso no es un defecto de acabado que se arregle modelando mejor. Es que el verbo
"conducir" no está implementado en ningún sitio: `Ride.luau` lo dice sin rodeos —
*"sentarse de verdad entrega el control del personaje a la física, y ahí empiezan las
volcadas, los atascos y el «me he quedado pegado al asiento»"*. La decisión fue
deliberada y **para lo pequeño es la correcta**.

## 2. Por qué escala mal

El error crece con el tamaño, y por eso se nota justo en los peldaños caros:

- **Monopatín y patinete** (de pie, una persona): un patinador pivota de verdad. Con la
  postura del 21/08 —cuerpo abierto 55°, patada, balanceo— se lee bien. Costó tres capas
  de arreglo llegar ahí, pero llegó.
- **Bici y moto** (sentado, una persona, estrecho): aguantan a duras penas. Una moto que
  gira sobre el sitio es raro, no imposible.
- **Coche y furgoneta** (5,5 studs de ancho, 7 de largo): **no hay forma**. Un cuerpo de
  siete studs girando 106° en una décima no se parece a un coche por bien dibujado que
  esté, y cuanto mejor esté dibujado, peor — porque el ojo perdona un dibujo simple y no
  perdona una contradicción. Es la misma frase que ya justificó la postura de la moto.

Y hay un segundo problema, de diseño y no de física: **los cuatro peldaños caros son el
mismo peldaño repetido**. Patinete eléctrico, bici, moto, coche y furgoneta comparten
`soloCalzada = true` y se diferencian sólo en tres números (capacidad, velocidad,
`expone`). Comprar el siguiente no cambia lo que HACES, cambia cuánto cabe. Es
exactamente el defecto que el propio `Config` diagnosticó en los tamaños de mercancía:
*"cuanto más grande, PEOR negocio... el vehículo grande vendía una trampa"*.

## 3. Las dos salidas

### A) Darles conducción de verdad

`AutoRotate = false`, velocidad angular limitada, nada de desplazamiento lateral,
inercia al arrancar y al frenar.

- **A favor:** el catálogo se queda como está; un coche que se conduce se siente caro.
- **En contra:** toca **el control**, que en este juego es el verbo entero — entre
  elegir ruta y entregar no hay otra cosa. Un control pesado en móvil, con joystick, se
  siente como un fallo antes que como peso. Y la calle mide 26 studs: un radio de giro
  creíble a 38 studs/s se come la calzada completa en cada esquina, así que habría que
  ensanchar las calles o aceptar que se rebota contra las aceras.
- **Coste:** alto, y con riesgo de empeorar lo que hoy funciona.

### B) Que lo grande deje de ser un vehículo (lo que propone JJ)

Cortar la escalera donde el cuerpo aguanta —hasta la moto— y convertir el dinero de
arriba en **verbos** en vez de en números.

Dos familias, y no son excluyentes:

1. **El arrastre.** Un carro o remolque del que se TIRA yendo a pie. Resuelve la
   capacidad sin pedir conducción: la física del jugador no cambia (es la que ya
   funciona) y el remolque va detrás con retardo, que es precisamente el movimiento que
   un objeto arrastrado puede hacer de forma rara sin que chirríe. Y trae decisión
   propia: estorba en los callejones, se ve venir de lejos, y **se puede soltar para
   correr** dejando la carga.
2. **Herramientas y propulsores.** Un impulso con enfriamiento, un gancho, un bate para
   defenderte, un señuelo mejor. Cada uno es un verbo nuevo, y **la casilla ya existe**:
   el sistema de "se guarda en una casilla y se usa con un botón" está hecho y probado
   desde el salto y el escudo (commit `da3bb39`). Añadir un objeto usable cuesta poco
   comparado con inventar conducción.

- **A favor:** juega con lo que el motor hace bien; convierte una escalera de números en
  decisiones distintas; el jugador nota cada compra porque cambia lo que puede hacer.
- **En contra:** hay que resolver una promesa que hoy sostiene la furgoneta —
  `Config.TAMANOS` dice *"no puedes llevar algo grande sin un vehículo para ello"*, y el
  piano de x50 es lo que le da destino al dinero. **El carro puede ser esa llave**, pero
  hay que decidirlo a propósito, no dejarlo caer.

## 4. Recomendación

**B, con el carro como sustituto de la furgoneta, y la moto como último vehículo que se
conduce.** Motivo: la regla de la casa es que el bucle va antes que el contenido, y aquí
la opción A gasta el presupuesto en hacer que algo *parezca* mejor mientras la B añade
decisiones. Además A pelea contra el motor y B se apoya en él.

## 5. Cómo decidirlo sin gastar una semana

No hace falta implementar nada para saberlo. **Una ruta roja en furgoneta y la misma
ruta en monopatín**, seguidas. Si la furgoneta se siente peor pese a ser diez veces más
cara, la respuesta ya está y la única duda es cuánto se corta.

Y el criterio final es el de siempre: esto se mide en D1 y en sesión media, no en gusto.
