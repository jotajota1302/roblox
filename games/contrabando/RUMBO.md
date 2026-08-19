# Rumbo: de dónde venimos, dónde estamos, a dónde vamos

> 2026-08-18. Escrito porque **hemos divergido del plan original** y conviene decidir qué
> divergencias se quedan. Contrasta [`DISENO.md`](DISENO.md) (el plan) con
> [`JUEGO.md`](JUEGO.md) (lo que hay), y propone la espina dorsal que hoy falta.
>
> El criterio no cambia (`TARGETS.md`): **retención D1**. Todo lo de aquí se justifica por
> ahí o no se justifica.

---

## 1. El plan original, en una tabla

| Pilar | Cómo se sostenía |
|---|---|
| La decisión | Qué llevo, a dónde, por qué ruta — riesgo contra recompensa |
| La tensión | En las rutas que pagan, **cualquiera puede alcanzarte** |
| El sumidero | Almacén (mejora), vehículos, consumibles |
| **Volver mañana** | (a) el almacén produce con tope y **deja de producir** al llenarse; (b) los precios **rotan**; (c) evento global **Redada** |
| La regla de oro | La progresión va por capacidad y acceso, **nunca por potencia** |

## 2. En qué hemos divergido

### Divergencias buenas — se quedan

| | Por qué se quedan |
|---|---|
| **El viaje pasó de una recta a una ciudad** con peligro, esquinas fichadas y ladrones | El plan original falló su propio criterio de kill: el trayecto era tiempo muerto. Esto es el rediseño, no un capricho |
| **Policía → ladrones; refugios → comisarías** | Había dos amenazas idénticas y narrativamente opuestas. Ahora el PNJ es el tutorial del jugador humano |
| **Carga de vuelta** | La vuelta era la mitad del ciclo sin juego |
| **Catálogo con tamaños** (un piano no se lleva a pie) | Es lo que le da destino al dinero: el vehículo deja de ser "una caja más" y pasa a ser una llave |
| **Regla de la calzada + garaje** | Convierte "el último vehículo es el mejor" en "cuál me llevo a este viaje" |
| **El polígono como casa** | Salir de casa significa algo cuando hay una casa |

### Divergencias que hay que corregir

| | Qué pasó | Qué hacer |
|---|---|---|
| **Los tres motivos para volver mañana** | Ninguno de los tres está implementado. El almacén produce y tiene tope, sí, pero **no se puede mejorar**; los precios no rotan; la Redada no existe | Es el agujero grande. Ver §3 |
| **El eje "exposición" de los vehículos** | El plan daba a cada vehículo una consecuencia distinta al ser alcanzado (sueltas todo / pierdes 30 % / aguanta dos toques). Hoy **todos pierden lo mismo**: el eje desapareció sin que nadie lo decidiera | Recuperarlo: es gratis y devuelve una decisión |
| **Cuatro vehículos se volvieron ocho** | Más escalones, pero el último cuesta 15.000 y sólo da ×2,15 sobre ir a pie | No añadir más. Ver §3 |
| **Nivel y XP** | Se añadieron sin estar en el plan, y hoy **no hacen nada**: son un número que sube | Darles el trabajo que falta: ser la licencia |

### Y lo que el plan no vio venir

**La ruta multiplica ×10 gratis lo que el garaje cobra a 31.950.** Medido hoy: el garaje
entero se paga con **siete viajes rojos a pie**. El sumidero compite contra una palanca que
no cuesta nada, y pierde. Es el fallo que hace que el juego se termine en una hora
(detalle y cifras en [`V1.md`](V1.md) §1).

---

## 3. El rumbo: cuatro piezas que encajan entre sí

No son cuatro ideas sueltas: cada una tapa el agujero que dejan las otras.

### A. El nivel es la licencia

Hoy subir de nivel no cambia nada. Que el nivel **abra rutas y tiers de vehículo**:

| Nivel | Qué se abre |
|---|---|
| 1 | Verde |
| 3 | Ámbar, y el primer vehículo de calzada |
| 6 | Roja |

Tres cosas a la vez, con un cambio pequeño:

1. **el ×10 deja de ser gratis** y pasa a estar detrás de jugar, que es exactamente donde
   tenía que estar;
2. **la XP empieza a significar algo** sin inventar un sistema nuevo;
3. **la primera sesión tiene un arco**: viajes verdes → nivel 3 → "acabo de desbloquear la
   ámbar", que es el momento que hace que alguien vuelva.

Y no rompe la regla de oro: sigue siendo **acceso**, no potencia.

### B. Los ladrones crecen — pero con lo que llevas, no con lo que eres

Tu idea, afinada. Que salgan más ladrones *porque has subido de nivel* castiga progresar:
el jugador aprende que mejorar le hace la vida peor. Que salgan más **porque llevas una
fortuna encima** hace lo contrario — es una decisión suya, y es justo la tensión que el
diseño buscaba desde el principio ("una legendaria por la roja vale 13.500, pero tu haz de
luz se ve desde el otro extremo del mapa").

Propuesta concreta:

- **Cuántos**: los que ya manda el peligro (0/1/2/3) **+1 si llevas sellada o legendaria**.
  Lo caro atrae, y eso ya se ve —la legendaria tiene su haz— así que no hay que explicarlo.
- **Cómo de buenos**: su velocidad sube **despacio con tu nivel** (digamos +1 stud/s cada
  tres niveles) con un tope por debajo de la velocidad cargada del vehículo de tu tier. Así
  el mundo no se queda de juguete cuando progresas, pero **nunca te pillan por ser bueno**.
- **La recompensa sube más deprisa que el riesgo.** Es la condición que no se puede
  romper: si un tramo de la progresión da más peligro que dinero, ahí se abandona.

### C. El sumidero que no se acaba: la nave

Está en el plan original y nunca se hizo. Es lo que **alarga tu ventana de ausencia**, o
sea, literalmente el motivo de volver mañana. Tres mejoras, todas con coste creciente:

| Mejora | Qué hace | Por qué importa |
|---|---|---|
| **Ritmo** | produce más deprisa | menos espera muerta en sesión |
| **Tope** | almacena más | puedes ausentarte más tiempo sin desperdiciar |
| **Seguro** | pierdes menos al ser robado | mitiga el mal día sin quitar la tensión |

Con esto el dinero deja de agotarse: el garaje es el escalón 1 y la nave es la escalera.

### D. Se tiene que poder PLANEAR el viaje mirando el mapa

Petición de JJ, jugando: *"no ves en el mapa dónde están los ladrones y su zona de
influencia, te aparecen de repente; deberías poder mirar el mapa y planear por dónde ir"*.

Tiene razón y además señala el agujero exacto entre lo que el diseño prometía y lo que hay.
El rediseño de la ciudad decía que la habilidad del juego sería **reconocer el cruce malo y
rodearlo**. Hoy eso es imposible de aprender salvo perdiendo: las esquinas fichadas están
en sitios fijos —bien— pero **no se ven en ningún sitio**, y los ladrones **aparecen de la
nada a 90-140 studs de ti** (`PatrolService`, `APARICION_MIN/MAX`). Un peligro que no se
puede anticipar no es tensión: es un impuesto.

Cuatro cambios, y los dos primeros son los que arreglan el fondo:

1. **Las esquinas fichadas, en el mapa, con su radio.** Están en posiciones fijas y con
   semilla por ruta; el jugador es un repartidor que se conoce su ciudad. Que se vean
   convierte el viaje en **una decisión antes de salir** en vez de una sorpresa a mitad.
2. **Los ladrones vienen de algún sitio: guaridas.** Hoy aparecen de la nada, y por eso
   "aparecen de repente" — literalmente. Que salgan de **guaridas fijas y marcadas en el
   mapa** hace tres cosas a la vez: se pueden rodear, explican de dónde viene el que te
   persigue, y dan a las zonas un carácter más allá del color.
3. **Los ladrones activos, en el mapa, en vivo**, como puntos con su radio de persecución.
   Ver al que te sigue es lo que convierte huir en decidir por dónde.
4. **El selector de ruta enseña lo que compras**: "la ámbar tiene 9 esquinas fichadas y 2
   guaridas". Elegir ruta hoy es elegir un multiplicador a ciegas.

Encaja con §3.B: si los ladrones crecen con lo que llevas, el jugador tiene que poder
**ver** ese coste antes de cargarse la legendaria a la espalda.

---

## 4. Monetización

**Regla de tiempo: no se monetiza antes de tener retención.** Monetizar un juego que no
retiene es gastarse el tráfico. Pero se diseña ahora para no atornillarla después.

**Regla de contenido: nada que dé velocidad ni que proteja del robo.** Rompería la única
regla innegociable del diseño — que nadie sea inatrapable — y convertiría las rutas rojas
en dinero gratis para quien pague.

Lo que sí encaja, por orden de "cuánto convierte" contra "cuánto daña":

| | Tipo | Qué da | Riesgo |
|---|---|---|---|
| **Nave grande** | Gamepass | +tope y +ritmo de producción | Ninguno: es comodidad, y ataca justo la fricción que más se nota |
| **Doble monedas** | Gamepass | ×2 al cobrar | Infla la economía; aceptable porque el dinero no compra poder en el viaje |
| **Cargamento urgente** | Producto (consumible) | llena la nave al instante | Ninguno |
| **Pintura y placas** | Gamepass / producto | cosmético del vehículo | Ninguno, y es lo que mejor envejece |
| ~~Zona VIP que paga ×5~~ | — | — | **No**: es pagar por saltarse la decisión, que es el juego |

Y una fuente que no es monetización pero se cobra igual: **Premium Payouts** — Roblox paga
por el tiempo que los miembros Premium pasan dentro. No requiere vender nada, sólo que la
sesión dure. Es una razón más para que el objetivo sea la sesión media, no la conversión.

De lo que entra, al desarrollador le llega **entre el 21 % y el 27 %** (`RESEARCH.md`). Con
eso en la cabeza, el orden correcto sigue siendo retención → tráfico → monetización.

---

## 5. Los objetivos, y cómo se miden

`Telemetry.luau` ya registra los eventos que hacen falta (`entrega`, `ruta_elegida`,
`compra_vehiculo`, `robo`, `robado`, `ladron_alcanza`, `calor_sube`). No hay que construir
nada nuevo para medir esto:

| Objetivo | Umbral | De dónde sale |
|---|---|---|
| **D1** | ≥ 20 % (por debajo de 15 %, pivotar) | Roblox, a partir de 100 jugadores/día |
| **Sesión media** | ≥ 8 min | Roblox / `Telemetry` |
| Primera compra | ≤ 3 min desde que entra | `compra_vehiculo` menos hora de entrada |
| Elige ámbar o roja en la sesión 1 | ≥ 60 % | `ruta_elegida` |
| Sesiones con al menos un robo | ≥ 1 por sesión | `ladron_alcanza`, `robo` |
| Abandono por fase | ninguna fase se lleva > 40 % | dónde se corta la secuencia de eventos |

**El dato que más vale no es cuánta gente entra, sino dónde abandona.** Si todos se van
durante el primer viaje, el problema es el viaje, y ninguna cantidad de contenido lo
arregla.

---

## 6. Orden de trabajo

1. ~~**El nivel como licencia** (§3.A)~~ — **hecho el 18/08**. Ámbar a nivel 3; roja a nivel
   8 **y** con vehículo de motor; cada peldaño del taller con su nivel, y el escaparate
   enseña los bloqueados en vez de esconderlos. El servidor lo comprueba y dice qué falta
   ("Te falta nivel: Nivel 8 y vehículo de motor"), porque el selector pinta pero no decide.
2. ~~**La nave mejorable** (§3.C)~~ — **hecho el 18/08**. Siete escalones de 1.200 a 150.000
   (267.200 en total): de guardar 10 y producir cada 30 s, a guardar 48 y producir cada 8.
   Se paga en la oficina de la nave. De paso levanta el techo de la capacidad, que dejaba
   media escalera de vehículos sin sentido.
3. ~~**Lo grande tiene que pagar más por hueco**~~ — **hecho el 18/08**. Un bono por tamaño
   invierte la curva: de 54,7/40,5/39,3/33,6 por hueco a 54,7/64,8/78,5/87,4. Y de paso el
   garaje pasa a rendir ×3,8 en vez de ×2,15 sobre ir a pie.
4. ~~**Recuperar el eje de exposición de los vehículos**~~ — **hecho el 18/08**. Cada
   vehículo pierde distinto al ser alcanzado (`expone`) y se ve venir desde distinta
   distancia (`bulto`): la furgoneta salva tres de cada cinco cajas y a cambio la fichan a
   56 studs en vez de a 35. Una prueba comprueba que ningún vehículo gane en las dos cosas.
5. ~~**El mapa que deja planear** (§3.D)~~ — **hecho el 18/08**. Las esquinas fichadas con
   su radio, las guaridas con su alcance y los ladrones con su aura, todo en el minimapa; y
   el selector anuncia lo que compras. Los ladrones salen de guaridas fijas: medido, entre
   el 62 % y el 66 % del trayecto tiene una a distancia útil (antes: 0 %, salían del aire).
6. ~~**El viaje deja de estar vacío**~~ — **hecho el 18/08**. Contactos por el camino que se
   gastan en cuatro habilidades (camuflaje, aguante, vista, señuelo), racha de velocidad que
   se pierde al entregar y al ser alcanzado, y menú 2D para las tres tiendas. Spec y plan en
   `docs/specs/` y `docs/plans/` del 18/08. Nació de comparar el juego con *+1 Speed Keyboard
   Escape*: allí cada paso da algo y aquí los 54-100 s de viaje no daban nada.
7. ~~**El primer bucle**~~ — **hecho y verificado el 19/08**. Numeritos flotantes al cobrar,
   hitos con objetivo visible, y la ruta de **barrio** que se abre por entregas. La
   verificación en Studio que quedaba pendiente encontró lo peor posible: **el destino del
   barrio no tenía camino desde ninguna parte** —caía debajo de un árbol de la ciudad— así
   que la ruta del tutorial era imposible de recorrer. Movido a calzada medida. La primera
   entrega cronometrada: **49 s**, contra el objetivo de ≤50 y los ~100 de entonces.
8. ~~**El viaje era demasiado largo**~~ — **hecho el 19/08**, y salió de jugarlo: *"es muy
   largo, nada atractivo"*. Dos cosas a la vez. **Las rutas se acortan** a puntos del camino
   real viejo (verde 768 → 679 studs, roja 1.813 → 1.224). Y **el rastro**: los contactos
   pasan de seis piezas sueltas a una fila continua cada 22 studs que dibuja el camino y
   acelera al seguirla, con una **cadena** que se cae si dejas de recoger. Ciclo verde de
   160 s a **96 s**; a pie cargado se pasa de 11,8 a 17,8 studs/s. Las doradas siguen siendo
   3/6/10/16, así que la economía de habilidades no se mueve.
9. **Ladrones que crecen con lo que llevas** (§3.B).
10. **Probar el robo con dos jugadores** — la mitad de la promesa sigue sin jugarse nunca.
11. **Portada: icono, miniatura, nombre, descripción** — en paralelo, no depende del código.

Y sólo entonces publicar y mirar los números. Lo de después —Redada, precios rotativos,
monetización, mapa procedural— **no significa nada hasta que haya gente**.
