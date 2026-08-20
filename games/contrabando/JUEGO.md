# El juego, hoy

> 2026-08-18. **Qué hace el juego realmente**, leído del código y medido en Studio, no de
> lo que se pensaba hacer. Si este documento y otro se contradicen, manda éste.
>
> Los demás documentos siguen valiendo para lo que son:
> [`DISENO.md`](DISENO.md) es **por qué** el juego es así (el diseño y sus descartes),
> [`DISENO-CIUDAD.md`](DISENO-CIUDAD.md) el rediseño del viaje,
> [`mapa/DISENO-MAPA.md`](mapa/DISENO-MAPA.md) el mapa procedural (aún no activo),
> [`VERIFICACION.md`](VERIFICACION.md) qué está comprobado y cómo.

---

## 1. En una frase

**Eres un repartidor.** Cargas mercancía en tu nave, eliges a qué zona la llevas —verde,
ámbar o roja; cuanto más lejos y más vigilada, más paga— y cruzas la ciudad con ella encima. Por el camino te
ven pasar, y lo que te ve venir detrás son **ladrones**: PNJ mientras juegas solo, otros
jugadores cuando hay gente.

Jugable en solitario desde el primer jugador. La presencia de otros lo cambia, no lo
habilita.

## 2. El bucle, tal y como está implementado

```
[NAVE]      recoges lo que ha producido en tu ausencia — piezas concretas, no un número
   ▼
[DECISIÓN]  qué te llevas (cabe poco) y por qué ruta sales (verde ×1 / ámbar ×3 / roja ×10)
   ▼
[VIAJE]     recoges CONTACTOS por el camino (y aceleras con cada uno) mientras
            te ven pasar → sube el peligro → aparecen ladrones → te refugias o corres
   ▼
[ENTREGA]   cobras, subes de nivel, y el destino te ofrece CARGA DE VUELTA
   ▼
[VUELTA]    con la carga de vuelta encima, que también se puede perder
   ▼
[INVERSIÓN] vehículos, nave y HABILIDADES, desde el menú ───────────────┘
```

La vuelta no es tiempo muerto: se paga al 60 % de la ida y también te la pueden robar.

### Los primeros 60 segundos, medidos

| Tiempo | Qué pasa |
|---|---|
| 0-5 s | Apareces en el polígono, tu zona propia fuera de la ciudad. La nave tiene 3 piezas esperando |
| 5-15 s | Las coges por su aviso de "pulsa aquí". El zurrón cabe **3** — hay que elegir cuál dejas |
| 15-25 s | Sales hacia la boca del polígono. **Si llevas carga y no has elegido ruta, una valla ámbar te frena**: "ELIGE DESTINO PARA SALIR" |
| 25-30 s | **Eliges destino.** A nivel 1 sólo la verde está abierta; la ámbar pide nivel 3 y la roja, nivel 8 y motor |
| 30-45 s | Viaje por el **rastro**: una píldora cada 1,4 s, y cada una te acelera. Las esquinas fichadas te ven pasar, el peligro sube de 0 a 3, salen ladrones |
| 45-55 s | Entregas en la verde. Número grande, XP, **vuelta a casa al instante** y el almacén repuesto |

El viaje a la verde son **20 segundos medidos** andando, y el ciclo completo con carga y
entrega ronda los 30. Hasta el 20/08 había por debajo una cuarta ruta de aprendizaje que el
selector llamaba LOCAL; se fundió en la verde, que se mudó a su cruce — el mapa promete tres
bandas y el selector daba cuatro etiquetas, una de las cuales no era un color.

## 3. Los números de hoy

Todos salen de [`src/shared/Config.luau`](src/shared/Config.luau), que es la única fuente.

### Mercancía

| Rareza | Multiplicador | Huecos | Probabilidad |
|---|---|---|---|
| Común | ×1 | 1 | 70 % |
| Marcada | ×10 | 1 | 20 % |
| Sellada | ×50 | 2 | 8 % |
| Legendaria | ×135 | 3 | 2 % |

Caja base **10 monedas**. Las probabilidades están **aflojadas para el prototipo** (en
producción: 90 / 8 / 1,8 / 0,2) para poder ver una legendaria sin jugar una hora.

**Y el tamaño paga.** Lo que rinde cada tamaño por hueco ocupado: pequeño 54,7 · mediano
64,8 · grande 78,5 · enorme **87,4**. Antes la curva iba justo al revés —lo enorme pagaba
33,6— y eso hacía del piano lo más vistoso del catálogo y lo peor que podías cargar. Mover
algo grande exige vehículo, y lo que exige inversión tiene que devolverla.

Cada pieza es además **un objeto concreto** de un catálogo de 17 (sobre, frasco, maletín,
cajón, televisión, baúl, nevera, sofá, piano, estatua…) con **tamaño**: pequeño (1 hueco),
mediano (2), grande (4), enorme (8). **El tamaño exige vehículo**: un piano no se lleva a
pie. Ésa es la razón de ser del dinero — el vehículo no es "una caja más", es una llave.

### Rutas

Las distancias son **camino real medido con el pathfinder dentro del juego**, no línea
recta: en una ciudad con manzanas las dos cosas se parecen poco, y la que el jugador anda
es ésta. El ciclo es ida y vuelta, contando el tramo de casa a la boca del polígono.

| Ruta | Paga | Licencia | Esquinas fichadas | Robo entre jugadores | Camino | Ciclo | Con el rastro |
|---|---|---|---|---|---|---|---|
| 🟢 Verde | ×1 | — | 2 | ninguno | 147 | 32 s | **26 s** |
| 🟡 Ámbar | ×3 | **nivel 3** | 9 | sólo entre los que llevan carga | 374 | 53 s | **40 s** |
| 🔴 Roja | ×10 | **nivel 8 + vehículo de motor** | 18 | libre | 572 | 66 s | **48 s** |

> **Caminos medidos el 19/08 con el pathfinder sobre la retícula propia** (`Grid`), desde la
> boca del recinto. Los tres destinos son cruces de calle y están a **un giro o ninguno**
> de la salida: a la verde se va recto, a la ámbar y la roja girando al este. Sobre el plano
> los caminos son 146 / 438 / 730 — **dos pasos de retícula entre ruta y ruta**, así que cada
> escalón vale lo mismo; hasta el 20/08 los saltos eran 146 / 146 / 292 y elegir entre las
> dos primeras significaba la mitad. Los medidos salen más
> cortos porque por dentro de las manzanas se puede cortar entre edificios, y eso es un
> atajo real que se descubre andando.
>
> Los **ciclos** están escalados en proporción al camino, no cronometrados de nuevo: hay que
> volver a medirlos jugando antes de darlos por buenos.

El ciclo ya **no incluye volver a casa**: al entregar puedes seguir desde donde estás.

**EL MUNDO SE ENCOGIÓ A LA MITAD el 19/08**, y no por opinión: JJ lo jugó dos veces y las
dos dijo lo mismo — *"es muy largo, nada atractivo"* y *"tardamos mucho en completar algo"*.

Medido antes: **el ciclo del reparto más corto que existe eran 87 segundos**, y más de la
mitad era andar sin que pasara nada — 15 s cruzando tu propio patio para salir y 37
volviendo por donde ya habías ido. Ahora son **26**.

Tres cambios, y el tercero es el que más quita:

1. **El almacén y el taller, pegados a la boca del recinto** (177 studs → 77).
2. **Los cuatro destinos, mucho más cerca**, todos medidos con el pathfinder dentro del
   juego y sobre terreno llano.
3. **La vuelta a casa deja de ser obligatoria**: la carga de retorno se puede entregar en
   cualquier otro destino, así que entregar te deja EN OTRO SITIO desde el que seguir en vez
   de deshacer el camino. Volver a la nave sigue existiendo —es donde está la mercancía que
   de verdad paga— pero pasa a ser una decisión y no un peaje.

Y con el mundo se reescalaron **todas las constantes que dicen "cuánto es lejos"**: zona
segura, márgenes y desvíos de refugios y guaridas, separación entre destinos. Una sola sin
reescalar no da un error — da un juego donde media ruta cabe dentro de la zona segura, o
donde una ruta se queda sin guaridas y por tanto sin ladrones. Pasaron las dos.

Y al medirlo apareció algo que llevaba ahí sin que nadie lo supiera: **el barrio no tenía
camino desde ninguna parte**. Su destino caía debajo de un árbol de la ciudad y la zona no
era navegable en cincuenta studs a la redonda. La ruta del tutorial era imposible de
recorrer andando, con su losa plantada y su baliza encendida.

El selector de ruta las anuncia con sus números — "9 esquinas · 3 guaridas" — y no con una
palabra: nadie sabe qué significa "peligrosa" hasta que le cuesta una carga.

**La licencia** es lo que impide que el ×10 sea gratis en el primer minuto. Sin ella, medido,
el garaje entero (31.950 monedas, ×2,15 de ganancia) competía contra un multiplicador que no
costaba nada — y perdía. Sigue siendo **acceso, no potencia**: la licencia no te hace más
rápido.

### Vehículos

| | Capacidad | Velocidad | Tamaño máx. | Sólo calzada | Nivel | Te fichan a | De 10 pierdes | Coste |
|---|---|---|---|---|---|---|---|---|
| A pie | 3 | 16 | pequeño | no | 1 | 35 | 5 | — |
| Monopatín | 5 | 19 | mediano | no | 1 | 35 | 5 | 150 |
| Patinete | 6 | 20 | mediano | no | 2 | 37 | 5 | 400 |
| Patinete eléctrico | 7 | 24 | mediano | **sí** | 3 | 40 | 4 | 1.400 |
| Bicicleta | 9 | 26 | grande | **sí** | 4 | 42 | 4 | 2.500 |
| Moto | 12 | 32 | grande | **sí** | 6 | 46 | 3 | 4.500 |
| Coche | 18 | 34 | enorme | **sí** | 8 | 51 | 2 | 8.000 |
| Furgoneta | 26 | 30 | enorme | **sí** | 10 | 56 | 2 | 15.000 |

**El eje de exposición** son las dos columnas del medio, y es lo que impide que el vehículo
caro sea sólo mejor: **aguanta más golpes pero recibe más**. Una furgoneta te ahorra tres de
cada cinco cajas cuando te alcanzan, y a cambio te fichan desde 56 studs en vez de 35.

Tres reglas sostienen esta tabla:

1. **La progresión va por capacidad y acceso, nunca por potencia.** El tope antitrampas
   son 40 studs/s y ningún vehículo se acerca: nadie es inatrapable.
2. **Lo que ganas por un lado lo pagas por el otro** (el eje de exposición).
3. **Los rápidos van atados al asfalto.** Si te sales con uno de motor te bajas, el
   vehículo se queda aparcado en la última calzada que pisaste, y lo que no cabe en tu
   espalda **se queda dentro del vehículo**. Al volver a él lo recuperas; si vuelves a
   casa sin él, aparece solo en tu taller.

Comprar no sustituye: hay **garaje**. Los tienes todos y eliges cuál sacas, porque ya no
hay un mejor sino un mejor **para este viaje**.

### Peligro (en el código se llama `calor`)

| | |
|---|---|
| Niveles | 0 a 3 |
| Radio de una esquina fichada | 35 studs |
| Bloqueo de re-disparo | 30 s por esquina y jugador |
| Baja solo | 1 nivel cada 20 s… |
| …o en comisaría | 1 nivel cada 5 s |
| Ladrones por nivel | 0 / 1 / 2 / 3 |
| …y uno más | si llevas **sellada o legendaria** encima (máximo 4) |

**Lo caro atrae.** Llevar algo de ×50 o ×135 saca un ladrón más. Sale de una regla que el
diseño tenía clara: los ladrones **no** crecen porque hayas subido de nivel —eso enseñaría
que progresar te empeora la vida— sino porque **has decidido** cargarte una legendaria a la
espalda. Es una consecuencia tuya, no un impuesto.

Y no hay que explicarlo: lo caro **ya se ve** desde lejos —la legendaria lleva su haz de
luz y cada rareza tiene su aspecto—, así que lo que atrae a los ladrones es exactamente lo
que ves que atrae. Con calor 0 no sale nadie por muy caro que sea lo que lleves: el calor
sube por lo que haces, y esto multiplica esa consecuencia en vez de sustituirla.

**Las comisarías son los refugios.** Un ladrón no entra en una comisaría, y eso no hay que
explicárselo a nadie. **El azul está reservado entero para ellas**: si el que te persigue y
el sitio donde te salvas comparten color, tienes que pararte a distinguirlos justo cuando
no puedes pararte.

Y **ninguna a la salida de casa**: el sitio de cada comisaría se mide en studs desde el
almacén, no en fracción del trayecto. Con fracción, la de la ruta verde caía a 230 studs de
casa —la puerta a 35 studs de donde acaba la zona segura— y ahí una comisaría no es una
decisión: el almacén apaga el peligro entero y además es donde cobras, así que meterse
dentro nunca podía ser lo mejor que hacer. Ahora la primera abre a 340 studs, más del doble
de la zona segura.

### Guaridas

Los ladrones **salen de guaridas**, no de la nada: tres por ruta (dos en la verde, que es
corta), apartadas 70 studs del camino y siempre fuera de la zona segura. Una guarida suelta
ladrones contra ti si estás entre 90 y 380 studs de ella — más cerca sería una emboscada
que no se puede esquivar, más lejos llegarían cuando el viaje ya ha terminado. Medido:
**cubren entre el 62 % y el 66 % de cada trayecto**; en el resto (la salida de casa y la
llegada al destino) se cae al método viejo.

Están en el mapa, con su alcance, igual que las esquinas fichadas con su radio. Es lo que
permite mirar el plano y **decidir por dónde ir** antes de salir.

**Y también se ven desde la calle**, que es lo que faltaba: una guarida existía en el plano
pero no en la ciudad, porque su farol medía 46 studs y los tejados de alrededor pasan de 80.
Medido con rayos desde el camino, se veía el 39 % de las veces; con el farol a 170 studs
—por debajo del faro de una comisaría, que es 190, porque el sitio al que corres tiene que
verse desde más lejos que el que hay que rodear— se ve el **61 %**.

Lo mismo con el ladrón, que es lo que se ve peor de todo: a 120 studs, su cuerpo sólo tiene
línea de visión limpia el 38 % de las veces. Lleva un **pilar de luz de 70 studs** —69 %— y
ahí se corta a propósito: más alto asomaría por encima de los tejados, se le seguiría por
toda la ciudad y despistarlos dejaría de existir.

### Robo

| | |
|---|---|
| Te alcanza a | 5 studs |
| Te avisa a | 60 studs ("te vienen detrás") |
| Se lleva | 30 % de tu carga |
| Y te deja marcado | 60 s |
| Zona segura | 150 studs alrededor de la nave |

El PNJ es **el tutorial del jugador humano**: aprendes a esquivar ladrones de mentira y eso
te prepara para los de verdad. Un ladrón PNJ se lleva el 50 %.

### La nave

Produce **1 pieza cada 30 s** (en producción: 180) hasta **10**, y al llenarse **deja de
producir**: no volver es desperdiciar tiempo. La producción se calcula **offline**, por la
hora de la última visita. **La nave no es asaltable jamás** — sólo está en juego lo que
llevas encima.

**Y se mejora**, en la oficina que hay junto a la losa. Siete escalones, de 1.200 a 150.000
monedas (267.200 en total), que suben las dos cosas a la vez:

| Nivel | Guarda | Produce cada | Cuesta |
|---|---|---|---|
| 1 | 10 | 30 s | — |
| 2 | 14 | 24 s | 1.200 |
| 3 | 18 | 19 s | 4.000 |
| 4 | 24 | 15 s | 12.000 |
| 5 | 30 | 12 s | 30.000 |
| 6 | 38 | 10 s | 70.000 |
| 7 | 48 | 8 s | 150.000 |

Al entrar, si ha producido mientras no estabas, la nave te lo cuenta — y si está llena, lo
dice con todas las letras: al tope **deja de producir**, así que cada minuto de más es
tiempo tirado. Es literalmente el motivo de volver, y hasta ahora no se decía en ningún
sitio.

Es el sumidero que no se acaba, y hace lo que el garaje no puede: **alarga tu ventana de
ausencia**. De paso arregla el techo de la capacidad — con la nave de partida un almacén
lleno pesa unos 23 huecos, así que comprar algo que cargue más de 24 no servía de nada.

### Los hitos: qué toca hacer ahora

**El primer minuto no pagaba.** Medido: la primera recompensa llegaba a los ~100 s, y en el
juego que inspiró esta tanda llega a los 3. Y la licencia por nivel existía pero sólo se
descubría chocando: pulsabas la ámbar y te decía que no.

| Hito | Condición | Qué da |
|---|---|---|
| 1 | 1 entrega | Abre la **ruta verde** + 50 monedas |
| 2 | 3 entregas | 250 monedas |
| 3 | nivel 3 | La ámbar *(ya existía; ahora se anuncia)* |
| 4 | 8 entregas | 1.000 monedas |
| 5 | nivel 8 + vehículo de motor | La roja *(ya existía)* |

Los de abajo cuentan **entregas y no nivel**: el nivel sube con el dinero cobrado, así que su
ritmo depende de qué llevabas encima. Las entregas miden lo que el jugador hace.

El objetivo actual va en su propia línea del HUD, separada de la misión: la misión dice qué
hacer **ahora** (ve a la salida, entrega aquí) y el objetivo **a qué aspiras**.

Y **cobrar se nota**: número flotante sobre el personaje al entregar y al recoger un
contacto, y el dinero del HUD contando hacia arriba en vez de saltar.

### El rastro, los contactos y las habilidades

**El viaje ya no es solo peligro.** Antes, toda la experiencia del juego se otorgaba en una
sola línea de código —al entregar—, así que durante los 54-100 segundos de camino el jugador
no ganaba nada y solo podía perder. Ahora hay algo bueno **dentro** del viaje.

**EL RASTRO** (19/08) es una **fila continua de píldoras cada 22 studs sobre el camino
real**. Nació de jugarlo: *"para que enganche a seguir la ruta deberíamos poner la ruta
indicada con píldoras que se van recogiendo y aumentan la velocidad, más seguidos"* (JJ).
Antes eran seis piezas sueltas en la verde —una cada 128 studs, una cada ocho segundos—, y
eso ni marcaba camino ni se sentía como premio continuo.

| | |
|---|---|
| Cuántas | Las que caben: el número sale del largo del camino, no de una tabla |
| Plantadas hoy | verde **9** · ámbar **41** · roja **58** — salen del largo de cada camino |
| Ritmo | A pie, una cada **1,4 segundos** |
| Cuándo se ven | **Sólo las de TU ruta, y sólo llevando algo que entregar.** Sin misión, la ciudad está a oscuras |
| Doradas | Unas cuantas del rastro pagan contacto: 4 · 10 · 16 |
| Racimos | Apartados 55 studs hacia una guarida, valor 5. Dan la **decisión** |
| Qué son los contactos | Fichas que **no ocupan hueco** y **no se pueden robar**. Solo se gastan en habilidades |
| Cuándo cuentan | Solo con misión activa (carga + ruta). Pasar sin nada no da nada |

Que las doradas sigan siendo 3/6/10/16 es deliberado: **el rastro cambia lo que se siente,
no lo que se gana**. La economía de habilidades no se movió ni un contacto.

Y hace algo que no era un premio sino orientación: la brújula dice **hacia dónde**, pero no
**por dónde**. La fila de luces sí.

Se reparte sobre el **camino real** del pathfinder, no sobre la recta casa-destino. No es un
detalle: con la recta caían en el camino el 0 % de la ruta verde. Y se siembra **la última de
todo**, después de guaridas y refugios, porque cada cosa que se planta cambia el camino que
la siguiente mide — sembrándolo antes, una comisaría de 54×54 cortaba después el recorrido
que el rastro acababa de dibujar y 19 de las 55 piezas de la roja quedaban fuera de alcance.

**La racha.** Cada pieza recogida da **+0,4 studs/s** hasta un tope de **+6**, y se pierde
entera al entregar y al ser alcanzado. A pie cargado eso son **11,8 → 17,8 studs/s, un 51 %
más rápido**: el rastro no solo entretiene, **acorta el viaje**. La velocidad es **del viaje,
no tuya** — la permanente está descartada porque nadie puede volverse inalcanzable. Los
ladrones escalan con tu velocidad actual, racha incluida.

**La cadena.** Si dejas de recoger, la racha **se cae sola**: 4 segundos de gracia y luego
una pieza por segundo, hasta cero. Es lo que convierte el rastro en un juego en vez de en un
pasillo decorado — sin ella, recoger seis al principio rendiría igual que seguir la fila
entera, y entonces el rastro no pediría nada. Los 4 segundos salen del paso: a 22 studs y
16 studs/s se pisa una cada 1,4 s, así que quien va por la fila no la pierde nunca y quien
la abandona lo nota enseguida.

**Las habilidades**, pagadas con contactos:

| | Qué hace | Peldaños | Coste |
|---|---|---|---|
| **Camuflaje** | te fichan desde menos lejos (35 → 26 studs) | −8 / −16 / −25 % | 20 / 60 / 150 |
| **Aguante** | pierdes menos carga al ser alcanzado | −10 / −20 / −30 % | 20 / 60 / 150 |
| **Vista** | ves guaridas y ladrones desde más lejos | +25 / +50 / +75 % | 20 / 60 / 150 |
| **Señuelo** | sueltas un cebo: los ladrones van a él 6 s (recarga 45 s) | — | 80 |

Ninguna da velocidad y ninguna anula: son factores sobre números que ya se calculaban. El
robo tiene **suelo del 10 %** — con todo comprado siguen llevándose el 21 % ante un jugador y
el 35 % ante un PNJ. Que ninguna combinación deje a nadie fuera de alcance está comprobado en
la batería, no confiado a un comentario.

## 4. El mundo

- **El polígono**: 360 × 250 studs de explanada propia **fuera de la ciudad**, con muro en
  tres lados y una sola boca al norte. Dentro: la nave, el taller-concesionario, la losa de
  salida y su baliza. Cruzar su carretera de acceso es literalmente salir de casa.
- **La ciudad**: el modelo del Creator Store (7.161 piezas), que el juego **no toca ni un
  stud**. Todo lo del juego se planta encima por código.
- **Los accesos**: cada destino y cada taller de zona tiene carretera asfaltada hasta la
  calle más cercana. Sin eso, la mercancía grande era una contradicción — exige vehículo, y
  el vehículo no llegaba.
- **Tres talleres de zona**, uno junto a cada destino, para no volver a casa a cambiar de
  vehículo.

## 5. Lo que ve el jugador

- **HUD**: dinero, nivel y barra de XP, carga (con lo que espera en el vehículo), peligro,
  **contactos con la racha al lado** ("12 (+2,0)"), la misión en curso y una línea de
  acciones con las teclas.
- **Menú 2D** en el borde derecho: Señuelo, Habilidades, Nave y Taller. Los edificios se
  quedan y siguen funcionando -- el menú es una segunda puerta, no una demolición. La única
  excepción: **comprar** un vehículo se puede desde cualquier sitio, **sacarlo** del garaje
  sigue pidiendo estar en un taller, o "cuál me llevo a este viaje" deja de ser una
  decisión.
- **Brújula** hacia lo que toca ahora, y **minimapa con los peligros**: las esquinas
  fichadas con su radio real, las guaridas con su alcance, y los ladrones activos con la
  zona a la que ya te avisan — los que se salen del recuadro se pegan al borde en vez de
  desaparecer.
- **Selector de ruta** al acercarse a la salida, con multiplicador y peligro de cada una.
- **Garaje** dibujado en las plazas del taller: cada vehículo con sus huecos y si puede
  salirse del asfalto.
- **Avisos** cortos en pantalla y sonidos por vehículo (motor, ruedas, pedales).
- **La carga va en una MOCHILA**, no flotando. Las piezas asoman por su boca, y la mochila
  **abulta con los huecos ocupados**: un piano se lee de lejos y ocho sobres también. No es
  decorado — el diseño se apoya en que ver a alguien por la calle diga si merece la pena
  perseguirle, y una mochila reventada se lee mucho antes que contar cajitas.
- **Efectos de movimiento**: polvo bajo los pies que sube con la velocidad real (más si
  llevas motor) y **estela dorada cuando la racha pasa de la mitad del tope**, del color de
  los contactos, porque es literalmente lo que has recogido convertido en velocidad. Existía
  un problema de lectura concreto: ir a 12 studs/s y a 22 se veía **exactamente igual**, y
  desde que entró el rastro la velocidad es la moneda del viaje.
- **El peligro tiñe la pantalla**: a partir del nivel 2, los bordes se ponen rojos y laten
  —despacio a 2, deprisa a 3—. A partir de 2 y no de 1 porque con uno sólo te han visto
  pasar, y un aviso encendido medio viaje deja de ser un aviso. El centro queda limpio: es
  ambiente, no algo que haya que leer.
- **El primer reparto no tiene competencia.** A nivel 1 sólo la verde está abierta, así que
  la primera decisión del jugador nuevo no es entre tres cosas que no conoce: es coger carga
  y salir. La ámbar aparece con el nivel 3 y la roja con el 8, cuando ya sabe qué significan.
- **Entregar repone el almacén.** Lo que dejas en el destino vuelve a tu nave como género
  nuevo, así que el viaje siguiente sale sin esperar. El goteo por tiempo sigue detrás como
  suelo, para quien vuelve mañana o se queda a cero porque le han robado. Antes sólo existía
  el goteo, y salían **veinte segundos jugando y setenta esperando** encerrado en tu propio
  almacén: el bucle se quedaba sin combustible en el minuto uno.

## 6. Lo que está guardado

En DataStore, por jugador: dinero, XP, **contactos y habilidades**, vehículos del garaje,
vehículo activo, **cuántas piezas** tiene la nave y la hora de la última visita — de ahí sale la producción offline.
**El peligro no se guarda** a propósito: es del viaje, y volver con 3 heredado sería un
castigo por desconectarse. **La racha tampoco**, por lo mismo al revés: volver con la de ayer
sería premio por desconectarse.

## 7. Lo que NO está en el juego

Para que nadie lo dé por hecho leyendo los documentos viejos:

- **No hay monetización.** Ni pases, ni gamepasses, ni Robux. Cero.
- **No hay evento global** ("Redada"): sin masa de jugadores no significa nada.
- **No hay rotación de precios**: los multiplicadores son fijos.
- **No hay tutorial explícito**: todo se aprende con el mundo (la valla que te frena, la
  baliza que se ve desde lejos, el aviso de "te vienen detrás") y con los hitos, que dicen
  qué toca sin explicar cómo.
- **El robo entre dos jugadores reales no se ha probado nunca.** Está implementado y sus
  reglas tienen pruebas puras, pero nadie lo ha jugado con dos personas.

## 8. Cómo se verifica

Dos baterías, y hacen cosas distintas:

```lua
-- LAS REGLAS (puras, ~500 comprobaciones, no necesitan mundo):
return require(game.ReplicatedStorage.Shared.TestRunner).run()

-- EL MUNDO CONSTRUIDO (en Play, datamodel Server):
return require(game.ServerScriptService.Server.SelfCheck).run()
```

La segunda existe porque **ningún fallo caro de este proyecto lo habría cazado la primera**:
los detectores en las azoteas, la nave encima de una pista de baloncesto, la carretera
enterrada, el taller en un descampado sin calles. Todos tenían la misma firma — nada
revienta, el juego arranca, y simplemente es más fácil o más raro de lo que dice ser.
