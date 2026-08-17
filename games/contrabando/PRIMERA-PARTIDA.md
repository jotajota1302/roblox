# La primera partida jugada por una persona

> 2026-08-17. JJ jugó el prototipo de principio a fin por primera vez.
> Esto es lo que dijo, ordenado por lo que cuesta arreglarlo — y con el veredicto de fondo
> al final, que es lo único que decide si el proyecto sigue.

---

## 1. El veredicto de fondo

> *"Ahora es correr en línea recta sin obstáculos ni nada. Es bastante triste la experiencia."*

**Esto no es un defecto: es el resultado de la medición.** El diseño dice que *el viaje es el
juego* y fija el criterio de kill número 1: *si no aguantas diez minutos seguidos tú mismo,
sin nadie más conectado, hay que rehacer el viaje antes de añadir nada*.

El viaje, hoy, es una recta de asfalto sin nada. La decisión (verde / ámbar / roja) se toma
**una vez, al salir**, y después no vuelve a pasar nada durante minuto y medio. Todo el
riesgo de la ruta roja es *que aparezca otro jugador*, y jugando solo eso es exactamente
cero: el trayecto no se distingue del de la verde salvo en su longitud.

Dicho de otra forma: **el bucle está construido, pero el minuto y medio del medio está
vacío**, y ese minuto y medio es la mayor parte de la sesión.

Lo que el diseño ya preveía para llenarlo y aún no existe:

- **La Redada** — el evento que convierte el trayecto en algo que ocurre, no que se recorre.
- Que la ruta **elegida** cambie algo del camino: atajos, tramos ciegos, sitios donde
  esconderse. Hoy las tres rutas son la misma recta de distinta longitud.
- Decisiones **durante** el viaje, no sólo al empezar.

No hay que decidirlo aquí. Pero sí hay que decidirlo antes de tocar nada más: cualquier
pulido de interfaz encima de un viaje vacío es pulir la parte que no falla.

---

## 2. Defectos concretos, en orden de gravedad

### Entregar no actualiza nada

> *"He llegado a la verde y le he dado a entregar y no se actualiza el «a pie» etc."*

**Es lo más grave**, porque es el momento de cobrar: el único instante del bucle en que el
juego te da la recompensa. Si el HUD no cambia, el jugador no sabe si ha cobrado, si el botón
funciona o si el juego está roto.

Hay que averiguar **cuál de las dos cosas pasa** antes de tocar código:

- que la entrega **no se está haciendo** (el servidor la rechaza por distancia o por ruta), o
- que se hace pero **el HUD no lo refleja**.

La sonda automática sí cobró en ese mismo punto (`3 cajas → 300 monedas`), así que lo
segundo es más probable — y apunta a que el jugador llega al destino por un sitio donde el
servidor no le da por llegado, o a que el `sync` posterior no llega. **Verificar jugando, no
razonando.**

### No se ven las cajas que hay para coger

> *"Ni veo los paquetes en el almacén para coger."*

El HUD dice `Almacén 6/10`, pero en el suelo no hay nada que corresponda a ese 6. Las cajas
del muelle son **decoración fija**: siempre las mismas tres, produzca lo que produzca el
almacén.

Es el fallo de legibilidad más caro del juego, porque el almacén es **el motivo para volver**:
ver la mercancía acumulada es lo que hace que volver signifique algo. Un número en una esquina
no lo consigue.

Arreglo: que la pila de cajas del muelle **sea** el contador. Tantas cajas visibles como
`almacenCajas`, apareciendo según se produce. El contador ya existe y es por jugador, así que
hay que decidir si la pila es la del jugador que mira (visible sólo para él) o compartida.

### Se aparece encima de la furgoneta

> *"Salgo encima de la furgoneta."*

El punto de aparición y el escaparate del taller se pisan. Aparecer dentro de un objeto es de
las primeras cosas que ve un jugador nuevo, y da la impresión exacta de descuido.

Revisar la geometría del taller: la furgoneta se movió delante del cobertizo (`z = -12`) y
puede haber quedado en el camino, o el respawn tras morir no está usando el `SpawnLocation`.

---

## 3. Lo que sí funciona

Para no perder la perspectiva: el bucle completo está construido y verificado —producir,
recoger, elegir ruta, viajar, cobrar, comprar la furgoneta—, el mundo no tiene huecos, los
escalones se suben andando, el servidor no cede a 520 llamadas maliciosas y hay 133 pruebas
en verde.

**El problema no es que no funcione. Es que funcionar no basta.**
