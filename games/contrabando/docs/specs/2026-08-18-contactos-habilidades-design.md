# Contactos y habilidades: que el viaje deje de estar vacío

> 2026-08-18. Diseño aprobado por JJ tras comparar el juego con
> *[X2] +1 Speed Keyboard Escape* (265.424 jugando, 4.884 M de visitas). El diagnóstico no
> fue gráfico: ese juego te da un "+1" cada paso y el nuestro **te cobra por cada paso y te
> paga una sola vez, al final**.
>
> Criterio del proyecto sin cambios (`TARGETS.md`): **retención D1**.

---

## 1. El problema, medido

Toda la experiencia del juego se otorga en **una línea de código**:

```
src/server/CargoService.luau:396 -> estado.xp = (estado.xp or 0) + Levels.xpPorEntrega(cobrado)
```

Durante los **54-100 segundos** de viaje (cronometrados en `VERIFICACION.md`) el jugador no
gana nada. Solo puede perder: sube el peligro, salen ladrones, se va la carga. El viaje es
un impuesto entre dos momentos buenos.

Y en el otro extremo, `Levels.luau` documenta en su propia cabecera que las habilidades se
pidieron y se aparcaron: *"se pidieron cuatro estadísticas (defensa, velocidad, destreza,
camuflaje) y entra primero el estatus a secas"*. El nivel abre rutas (la licencia, hecha el
18/08) pero **no hay nada que el jugador construya a su gusto**.

Los dos agujeros se tapan con un solo sistema: **lo que recoges por el camino es lo que se
gasta en habilidades.**

---

## 2. Decisiones tomadas

| | Decisión |
|---|---|
| Qué recoges | **Contactos**: moneda de habilidad. No ocupa hueco, no se puede robar, no compra nada más |
| Dónde aparece | **Goteo** a lo largo del camino (ritmo) + **racimos** junto a guaridas y esquinas fichadas (decisión) |
| Qué compras | **Tres pasivas + un verbo activo** (el señuelo) |
| Interfaz | **Menú 2D** con botones laterales, salvo sacar vehículo |
| Alcance | **Mínimo jugable**: construir, jugar una partida, decidir después |

---

## 3. Los contactos

### Qué son

Fichas que **no ocupan hueco del zurrón** y **no se pueden robar**. Se gastan solo en
habilidades. Esto es deliberado y es lo que hace el sistema seguro: la economía de monedas y
el eje de riesgo del viaje ya están equilibrados (`V1.md` §1), y una moneda paralela que no
los toca no puede desequilibrarlos.

### Cuándo existen

**Solo con misión activa** — carga encima y ruta elegida. Se siembran al elegir ruta y se
retiran al entregar.

Es la regla que cierra el agujero evidente: si estuvieran siempre, dar vueltas por la ciudad
recolectando sin hacer viajes sería una forma de progresar sin jugar al juego, y el bucle
—nave, decisión, viaje, entrega— dejaría de ser el centro.

### Cómo se reparten

Dos poblaciones distintas, con trabajos distintos:

| | Valor | Dónde | Para qué |
|---|---|---|---|
| **Sueltos** | 1 | sobre la calzada del corredor, cada ~70 studs | Ritmo: algo pasa cada 3-5 segundos |
| **Racimos** | 5 | a 40-90 studs del camino, junto a una guarida o una esquina fichada | Decisión: el premio está donde está el peligro |

Cantidades de partida, escaladas por ruta como todo lo demás:

| Ruta | Sueltos | Racimos | Total si lo coges todo |
|---|---|---|---|
| Verde | 6 | 1 | 11 |
| Ámbar | 10 | 2 | 20 |
| Roja | 16 | 3 | 31 |

**Radio de recogida: 10 studs**, por proximidad automática — no hay que apuntar ni pulsar.
A la velocidad máxima del juego (34 studs/s) eso da ~0,6 s de ventana, suficiente porque los
sueltos van **sobre** el camino, no al lado.

Los números son de partida y están para calibrarse con una partida real, no para defenderse.

---

## 4. Las habilidades

Todas se montan **sobre sistemas que ya existen**, multiplicando o restando a un valor que
ya se calcula. Ninguna crea un sistema nuevo y **ninguna da velocidad**.

| Habilidad | Qué hace | Sobre qué | Peldaños |
|---|---|---|---|
| **Camuflaje** | te fichan desde menos lejos | resta studs al `bulto` del vehículo | −3 / −6 / −10 studs |
| **Aguante** | pierdes menos carga al ser alcanzado | modifica `expone`, **con suelo de 1** | −1 caja por peldaño |
| **Vista** | ves guaridas y ladrones desde más lejos | alcance del minimapa | +25 % / +50 % / +75 % |
| **Señuelo** *(activo)* | los ladrones a menos de 120 studs van a un punto, no a ti | objetivo de `PatrolService` | dura 6 s, recarga 45 s |

Costes de partida: peldaños de pasiva **20 / 60 / 150** contactos; señuelo **80**. Con un
viaje verde dando ~11 y uno rojo ~31, el primer peldaño cae en la primera sesión y el árbol
completo (**770**: 230 por rama × 3, más el señuelo) pide bastantes viajes.

**El señuelo es la mitad del encargo.** Lo que hace que un juego se sienta ágil no es solo
que pasen cosas, es tener **algo que pulsar**. Hoy el jugador solo anda; con el señuelo,
huir pasa de aguantar a decidir cuándo lo gastas.

### La regla que no se puede romper

`DISENO.md` y `JUEGO.md` §3 lo fijan: **la progresión va por capacidad y acceso, nunca por
potencia; nadie puede volverse inalcanzable.** Por eso no hay habilidad de velocidad, ni de
inmunidad al robo. Camuflaje y aguante mitigan; el señuelo **retrasa**, no anula, y tiene
recarga. Una prueba pura comprobará que ninguna combinación deja al jugador fuera del
alcance de un ladrón.

El **suelo de 1 caja** en Aguante existe por esto: la furgoneta ya pierde solo 2 de cada 10,
y tres peldaños sin suelo la dejarían en **cero** — inmunidad al robo por la puerta de
atrás, que es exactamente lo que el diseño prohíbe.

---

## 5. El menú 2D

Hoy todo se compra yendo a un edificio. Cambia a **botones laterales** que abren paneles:
**Habilidades**, **Nave**, **Taller**. Es el estándar que la gente ya sabe usar y la mayoría
de Roblox se juega en móvil.

**Una excepción, y es de diseño, no de comodidad: sacar el vehículo activo sigue pidiendo
estar en un taller.** Comprar desde el menú no rompe nada; poder cambiar de vehículo a mitad
de la ciudad sí — evapora la decisión "cuál me llevo a *este* viaje", que es lo que el
garaje y la regla de la calzada existen para crear (`JUEGO.md` §3).

Los edificios del mundo **se quedan**: la oficina de la nave y los talleres siguen ahí y
siguen funcionando. El menú es una segunda puerta, no una demolición. El polígono sigue
siendo la casa.

---

## 6. Arquitectura

Respeta la línea puro/impuro que estructura el proyecto: **las reglas viven en módulos puros
con pruebas; los servicios son pegamento.**

### Puro (`src/shared/`)

- **`Contacts.luau`** — dado el corredor de una ruta y sus peligros, devuelve dónde va cada
  contacto y cuánto vale. Sin tocar Roblox.
- **`Skills.luau`** — catálogo, costes, peldaños y el efecto de cada habilidad sobre el valor
  que modifica.
- Sus `tests/Contacts.spec.luau` y `tests/Skills.spec.luau` entran en `TestRunner`.

### Servidor

- **`ContactService.luau`** — siembra al elegir ruta, **detecta la recogida en su propio
  bucle `Heartbeat`**, retira al entregar.
  **No existe ningún remote de "he recogido esto"**, por la misma razón que no existe uno de
  "he tocado a este": lo detecta el servidor o es una trampa servida.
- Enganches: `CargoService` (retirada al entregar), `PatrolService` (señuelo),
  `Persistence` (dos campos nuevos: `contactos` y `habilidades`), `InterceptService`
  (aguante), la detección de esquinas fichadas (camuflaje).

### Cliente

- Contador de contactos en el HUD, junto a dinero y nivel.
- **`Menu.luau`** — los paneles 2D, cada pantalla dentro de su `pcall` (una excepción a
  mitad de `Hud.build()` ya dejó una vez el juego sin selector de ruta y sin un solo error
  visible).
- Botón/tecla del señuelo con su recarga a la vista.
- Nada de esto en `RenderStepped`: **lo que es información va en `Heartbeat`** — medido, con
  la ventana sin foco `RenderStepped` da cero llamadas por segundo y la brújula entera se
  quedó apagada sin error.

### Remotes nuevos

`COMPRAR_HABILIDAD` y `USAR_SENUELO`, **creados al arrancar** como todos los demás: un
remote que el servidor solo envía no existe hasta el primer envío, y el cliente que hace
`WaitForChild` sobre él se cuelga para siempre.

---

## 7. Verificación

Las tres capas que este proyecto ya ha aprendido a necesitar:

1. **Pruebas puras** (`TestRunner`): reparto, valores, costes, peldaños, y la comprobación de
   que ninguna combinación de habilidades vuelve al jugador inalcanzable.
2. **`SelfCheck` sobre el mundo construido**, con la lección que costó cara con los
   detectores — quince acabaron en azoteas y medio sistema de vigilancia era decorado sin que
   nada reventara. La medida que vale aquí es: **cuántos contactos encuentra realmente quien
   recorre la ruta**. Umbral: ≥70 % de los sueltos, y racimos a 40-90 studs del camino.
   Si el reparto típico cae fuera del radio de recogida, el sistema no existe aunque el
   código esté escrito y probado.
3. **Una partida andando**, con `Humanoid:MoveTo` y traza de posiciones o jugada por JJ.
   Verificar teletransportando no verifica el mapa: es el fallo que dejó pasar una carretera
   que no cubría ni el almacén.

Y la comprobación de interfaz en **coordenadas absolutas y todos contra todos**: los botones
laterales nuevos no pueden pisar el botón de salto de Roblox ni los controles táctiles.

---

## 8. Fuera de alcance

- Equilibrar la economía de contactos a fondo (sale de la primera partida real).
- Más ramas, más peldaños, cosmética, contactos con rareza.
- Los pendientes de `RUMBO.md` §6: ladrones que crecen con lo que llevas, probar el robo con
  dos jugadores, portada.
- Monetización de habilidades. La regla de `RUMBO.md` §4 sigue: **nada que dé velocidad ni
  que proteja del robo**, y no se monetiza antes de tener retención.
