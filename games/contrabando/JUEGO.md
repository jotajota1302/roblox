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

**Eres un repartidor.** Cargas mercancía en tu nave, eliges a qué barrio la llevas —cuanto
más lejos y más vigilado, más paga— y cruzas la ciudad con ella encima. Por el camino te
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
[VIAJE]     te ven pasar → sube el peligro → aparecen ladrones → te refugias o corres
   ▼
[ENTREGA]   cobras, subes de nivel, y el destino te ofrece CARGA DE VUELTA
   ▼
[VUELTA]    con la carga de vuelta encima, que también se puede perder
   ▼
[INVERSIÓN] vehículos en el taller ─────────────────────────────────────┘
```

La vuelta no es tiempo muerto: se paga al 60 % de la ida y también te la pueden robar.

### Los primeros 60 segundos, medidos

| Tiempo | Qué pasa |
|---|---|
| 0-5 s | Apareces en el polígono, tu zona propia fuera de la ciudad. La nave tiene 3 piezas esperando |
| 5-15 s | Las coges por su aviso de "pulsa aquí". El zurrón cabe **3** — hay que elegir cuál dejas |
| 15-25 s | Sales hacia la boca del polígono. **Si llevas carga y no has elegido ruta, una valla ámbar te frena**: "ELIGE DESTINO PARA SALIR" |
| 25-30 s | Eliges destino. Se ven los tres con su multiplicador y su nivel de peligro |
| 30-90 s | Viaje. Las esquinas fichadas te ven pasar, el peligro sube de 0 a 3, salen ladrones |
| 90-110 s | Entregas. Número grande, XP, y el destino te ofrece carga de vuelta |

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

| Ruta | Paga | Licencia | Esquinas fichadas | Robo entre jugadores | Distancia recta |
|---|---|---|---|---|---|
| 🟢 Verde | ×1 | — | 3 | ninguno | ~420 studs |
| 🟡 Ámbar | ×3 | **nivel 3** | 9 | sólo entre los que llevan carga | ~848 |
| 🔴 Roja | ×10 | **nivel 8 + vehículo de motor** | 18 | libre | ~1.399 |

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

**Las comisarías son los refugios.** Un ladrón no entra en una comisaría, y eso no hay que
explicárselo a nadie. **El azul está reservado entero para ellas**: si el que te persigue y
el sitio donde te salvas comparten color, tienes que pararte a distinguirlos justo cuando
no puedes pararte.

### Guaridas

Los ladrones **salen de guaridas**, no de la nada: tres por ruta (dos en la verde, que es
corta), apartadas 70 studs del camino y siempre fuera de la zona segura. Una guarida suelta
ladrones contra ti si estás entre 90 y 380 studs de ella — más cerca sería una emboscada
que no se puede esquivar, más lejos llegarían cuando el viaje ya ha terminado. Medido:
**cubren entre el 62 % y el 66 % de cada trayecto**; en el resto (la salida de casa y la
llegada al destino) se cae al método viejo.

Están en el mapa, con su alcance, igual que las esquinas fichadas con su radio. Es lo que
permite mirar el plano y **decidir por dónde ir** antes de salir.

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
  la misión en curso y una línea de acciones con las teclas.
- **Brújula** hacia lo que toca ahora, y **minimapa con los peligros**: las esquinas
  fichadas con su radio real, las guaridas con su alcance, y los ladrones activos con la
  zona a la que ya te avisan — los que se salen del recuadro se pegan al borde en vez de
  desaparecer.
- **Selector de ruta** al acercarse a la salida, con multiplicador y peligro de cada una.
- **Garaje** dibujado en las plazas del taller: cada vehículo con sus huecos y si puede
  salirse del asfalto.
- **Avisos** cortos en pantalla y sonidos por vehículo (motor, ruedas, pedales).

## 6. Lo que está guardado

En DataStore, por jugador: dinero, XP, vehículos del garaje, vehículo activo, **cuántas
piezas** tiene la nave y la hora de la última visita — de ahí sale la producción offline.
**El peligro no se guarda** a propósito: es del viaje, y volver con 3 heredado sería un
castigo por desconectarse.

## 7. Lo que NO está en el juego

Para que nadie lo dé por hecho leyendo los documentos viejos:

- **No hay monetización.** Ni pases, ni gamepasses, ni Robux. Cero.
- **No hay evento global** ("Redada"): sin masa de jugadores no significa nada.
- **No hay rotación de precios**: los multiplicadores son fijos.
- **No hay tutorial explícito**: todo se aprende con el mundo (la valla que te frena, la
  baliza que se ve desde lejos, el aviso de "te vienen detrás").
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
