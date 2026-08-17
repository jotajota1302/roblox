# Anatomía de los éxitos y plan de targets iniciales

> Agosto 2026. Tercera parte, después de [`RESEARCH.md`](RESEARCH.md) (¿se gana dinero?) y
> [`MERCADO.md`](MERCADO.md) (¿qué formato?). Aquí: **cómo están hechos por dentro los
> juegos que funcionan**, y 3 conceptos concretos para elegir.
>
> Las secciones 1-3 son datos con fuente. La 5 son propuestas mías, marcadas como tales.

---

## 1. Disección de los tres fenómenos

### Grow a Garden — el idle cozy

| Dato | |
|---|---|
| Visitas | 35.500 M (1.000 M en **33 días**, récord de la plataforma) |
| Concurrencia habitual | 1,0-1,2 M jugadores |
| Origen | Primera versión hecha por un chaval de 16 años **en pocos días** |

**Bucle:** plantar → esperar → recolectar → vender → mejorar semillas.

Un bucle de granja trivial. Lo que lo hace funcionar no es la granja, son **cuatro sistemas
encima**:

1. **Mutaciones por clima.** Eventos globales (lluvia, tormenta, Luna de Sangre) aplican
   mutaciones a lo que tengas plantado, multiplicando su valor **de 10x a 135x**. Y dos
   mutaciones apiladas **se multiplican entre sí**, no se suman.
2. **Tienda que refresca cada 3-5 minutos.** No vuelves por la granja, vuelves a ver si ha
   salido la semilla rara.
3. **Timers escalonados**: cultivos de minutos y cultivos de horas. Te obliga a planificar
   cuándo vuelves.
4. **Misiones diarias y semanales** con semillas exclusivas.

> **La lección:** los eventos globales sincronizan a todos los jugadores a la vez. Cuando
> cae la Luna de Sangre, todo el mundo entra. Esa es la mecánica de retención más potente
> del juego y no tiene nada que ver con plantar.

### Steal a Brainrot — el tycoon con robo

| Dato | |
|---|---|
| Visitas | 69.800 M |
| Récord | **25,8 M jugadores simultáneos** — la cifra más alta de cualquier videojuego de la historia, en cualquier plataforma |
| Autores | SpyderSammy + Do Big Studios |

**Bucle:** conseguir → hacer crecer → defender → robar.

Compras personajes absurdos que generan ingresos pasivos en tu base... y **cualquiera puede
robártelos**. Ahí está todo.

Lo bien diseñado es el **robo con consecuencias**: cuando robas, te quedas lento, pierdes
todos tus objetos, y **se avisa al dueño**. Quedas vulnerable a que cualquiera te ataque, y
si te atacan, la pieza vuelve sola a su base original.

> **La lección:** la capa social no es "ver a otros", es **que otro jugador pueda
> cambiarte la partida**. Y el robo está equilibrado con riesgo real, no es gratis.

### Brookhaven — el sitio donde estar

83.400 M de visitas, la experiencia más visitada de la historia. **Sin misiones, sin
condición de victoria, sin objetivos.** Una ciudad donde estar con gente.

> **La lección:** una ciudad sin nada que hacer gana a la mayoría de juegos con demasiado.
> El contenido no es el producto; la gente lo es.

---

## 2. Los seis mecanismos que comparten

Extraídos de lo anterior. Esto es lo reutilizable, independientemente del tema:

| # | Mecanismo | Por qué funciona |
|---|---|---|
| 1 | **Ingreso pasivo mientras no estás** | Te da un motivo concreto para volver: hay algo esperándote |
| 2 | **Timers escalonados** (minutos / horas) | Estructura cuándo vuelves. Corto para la sesión, largo para mañana |
| 3 | **RNG con techo exponencial** | Mutaciones 10x-135x. La posibilidad de un golpe de suerte sostiene sesiones enteras |
| 4 | **Refresco frecuente de tienda** | Cada 3-5 min hay algo nuevo que mirar. Alarga la sesión sin contenido nuevo |
| 5 | **Eventos globales sincronizados** | Todo el mundo entra a la vez. Convierte jugadores sueltos en multitud |
| 6 | **Fricción social con riesgo** | Otro jugador puede cambiarte la partida, pero le cuesta algo hacerlo |

**Nada de esto requiere arte caro ni contenido narrativo.** Son sistemas — que es
exactamente nuestra ventaja comparativa.

Y un dato de encaje: los formatos idle y cozy escalan en Roblox como los hipercasuales en
las tiendas de móvil, funcionan bien en teléfono y **no exigen habilidad**: cinco minutos al
día bastan.

---

## 3. Criterios que debe cumplir el target

De `MERCADO.md`, más lo aprendido aquí:

1. Jugable y satisfactorio **con un solo jugador** (sin esto no arranca nunca)
2. Capa social de **fricción**, no decorativa
3. Arte barato: objetos simples repetidos con variaciones, nada de personajes animados
4. Prototipo jugable en **2-4 semanas** de una persona
5. Los seis mecanismos de la sección 2 deben poder implementarse
6. Tema **no saturado** — la diferenciación en Roblox viene del tema y el giro, no del género

---

## 4. Sobre "está saturado"

Antes de los targets, un aviso para no paralizarse: **el formato idle/tycoon está saturado
de clones malos, no de buenas ejecuciones.** Grow a Garden es un juego de granja más;
Steal a Brainrot es un tycoon más. Lo que los separó fue la ejecución, el tema y el momento.

Copiar el *formato* es correcto y es lo que hace todo el mundo. Lo que no funciona es
copiar el *tema*.

---

## 5. Tres targets propuestos

> A partir de aquí son propuestas mías, construidas sobre los datos anteriores. Ninguna
> está validada: para eso está el prototipo.

Los tres comparten el mismo esqueleto (progresión en solitario + fricción social) y se
diferencian en el tema, en el tipo de fricción y en el riesgo.

---

### Target A — Excavación con vitrina expuesta

**Pitch:** excavas un yacimiento, encuentras piezas, las restauras y las expones. Tu museo
genera visitas (ingreso pasivo)... y otros jugadores pueden llevarse lo que no protejas.

| Mecanismo | Cómo se implementa |
|---|---|
| Ingreso pasivo | Cada pieza expuesta genera monedas por minuto según rareza |
| Timers escalonados | Restaurar una pieza tarda de 2 min a 4 h según su estado |
| RNG exponencial | Estado de conservación + antigüedad se **multiplican**: una pieza intacta y milenaria vale 100x |
| Tienda con refresco | Herramientas de excavación rotan cada 5 min |
| Evento global | "Tormenta de arena": el terreno se regenera y aparecen zonas ricas. Todos entran |
| Fricción social | Robar de una vitrina es lento y visible: sale una alarma y quedas marcado durante 60 s |

- **Primeros 60 segundos:** cavas, sale algo brillante, lo desentierras, ves un número.
- **Por qué vuelves mañana:** tienes tres piezas restaurándose y el museo ha estado
  generando.
- **Arte:** piezas = 15-20 modelos simples con variaciones de material y color. Terreno
  voxel. Barato de verdad.
- **Riesgo:** hay juegos de excavación en la plataforma. La diferenciación tendría que
  estar en la restauración y el museo, no en cavar.
- **Esfuerzo:** medio. El terreno destructible es la parte técnica delicada.

---

### Target B — Rutas de contrabando ⭐ mi recomendación

**Pitch:** compras mercancía barata, la transportas por un mapa hasta donde se paga cara.
El viaje es largo y en él **cualquiera puede interceptarte**. Si llegas, cobras el margen.

| Mecanismo | Cómo se implementa |
|---|---|
| Ingreso pasivo | Almacén que acumula stock mientras no estás |
| Timers escalonados | Rutas de 2 min (seguras, poco margen) a 20 min (lucrativas, expuestas) |
| RNG exponencial | La demanda de cada destino fluctúa; ocasionalmente se dispara x50 |
| Tienda con refresco | Precios de compra y venta rotan constantemente: siempre hay una oportunidad que mirar |
| Evento global | "Redada": durante 10 min todas las rutas pagan triple y hay patrullas |
| Fricción social | Interceptar un cargamento te da parte de él, pero te marca en el mapa un rato |

- **Primeros 60 segundos:** compras algo, lo cargas, sales. A los 30 segundos ves a otro
  jugador acercarse y tienes que decidir: huir o arriesgar.
- **Por qué vuelves mañana:** los precios han cambiado y tu almacén tiene stock.
- **Arte:** el más barato de los tres. Cajas, carros o vehículos simples, un mapa con zonas.
  Sin personajes propios (valen los avatares de Roblox).
- **Por qué la recomiendo:**
  - **La tensión es el producto**, y la tensión es gratis de producir. No necesita arte ni
    contenido, solo reglas.
  - Jugable en solitario: sin nadie conectado, las rutas siguen dando dinero. La presencia
    de otros la hace más emocionante, no obligatoria.
  - Es **estrategia/economía**, uno de los géneros que Roblox declara infrarrepresentados.
  - Es lo más alineado con nuestra ventaja real: sistemas, economía y equilibrio, no arte.
- **Riesgo:** equilibrar el PvP. Si interceptar es demasiado fácil, los nuevos se frustran y
  se van. Hace falta protección para los primeros niveles.
- **Esfuerzo:** bajo-medio. Es el más rápido de prototipar de los tres.

---

### Target C — Taller de restauración (cozy, sin PvP)

**Pitch:** llegan objetos rotos y sucios, los reparas con minijuegos táctiles, ganan valor y
los vendes o los expones. Sin robo, sin ataques: la capa social es **el mercado**.

| Mecanismo | Cómo se implementa |
|---|---|
| Ingreso pasivo | La tienda vende sola mientras no estás |
| Timers escalonados | Secado, pulido y barnizado tardan de minutos a horas |
| RNG exponencial | Bajo un objeto sucio puede haber una pieza rara: se descubre al limpiarla |
| Tienda con refresco | El lote de objetos por comprar rota cada pocos minutos |
| Evento global | "Subasta": durante 15 min los precios se disparan y todos venden a la vez |
| Fricción social | Mercado entre jugadores: pones precio y compites con otros vendedores |

- **Primeros 60 segundos:** frotas una pieza sucia y aparece oro debajo. Es satisfactorio de
  forma inmediata y muy "vídeo de TikTok".
- **Arte:** medio. Necesita que limpiar **se vea** bien (texturas, partículas). Es el más
  bonito y el que más depende de acertar la sensación.
- **Riesgo:** la fricción social es **la más floja** de los tres. Competir por precio no
  cambia tu partida como que te roben. Retención probablemente menor.
- **Ventaja:** cero toxicidad, público amplio, y el género cozy escala muy bien en móvil.
- **Esfuerzo:** medio. El minijuego de limpieza tiene que sentirse perfecto o no hay juego.

---

## 6. Comparativa

| | A · Excavación | B · Contrabando | C · Restauración |
|---|---|---|---|
| Arranca con 1 jugador | ✅ | ✅ | ✅ |
| Fuerza de la fricción social | 🟢 Alta | 🟢 **Muy alta** | 🟠 Baja |
| Coste de arte | 🟢 Bajo | 🟢 **El más bajo** | 🟠 Medio |
| Saturación del tema | 🟠 Existe competencia | 🟢 Libre | 🟢 Libre |
| Riesgo técnico | 🟠 Terreno destructible | 🟢 Bajo | 🟠 Sensación del minijuego |
| Semanas hasta prototipo | 3-4 | **2-3** | 3-4 |
| Encaje con nuestra ventaja | Media | 🟢 **Alta** | Baja |

---

## 7. Plan

**Empezar por B (contrabando).** Es el más barato, el más rápido, el que menos depende del
arte y el que mejor encaja con lo que sabemos hacer. Y su mecánica central —la tensión de
transportar algo valioso mientras otros pueden quitártelo— es lo que en Steal a Brainrot
resultó ser el motor de la mayor concurrencia de la historia.

**Cómo matarlo rápido si no funciona.** Esto importa tanto como el plan:

| Momento | Comprobación | Si falla |
|---|---|---|
| Semana 1 | ¿El bucle solo (comprar → viajar → vender) es entretenido **sin** nadie más? | Rehacer el bucle. Sin esto no hay juego |
| Semana 2-3 | Prueba con 3-4 personas: ¿la intercepción genera tensión o frustración? | Ajustar riesgo/recompensa |
| Tras publicar | **D1 < 15%** con 100+ jugadores | Pasar al target A |
| Tras publicar | Sesión media < 6 min (la mediana de la plataforma) | El bucle es demasiado corto |

**Lo que NO hay que hacer al principio:** arte bonito, muchos tipos de mercancía, mapa
grande, historia. Un almacén, tres destinos, una mercancía y la intercepción. Si eso no
engancha, nada de lo demás lo va a arreglar.

---

## Fuentes

- [The Algorithm Behind 'Steal a Brainrot' — Andy Hall](https://freesystems.substack.com/p/the-algorithm-behind-steal-a-brainrot)
- [Steal a Brainrot: cómo funciona el juego viral — Bitget Academy](https://web3.bitget.com/en/academy/steal-a-brainrot-guide-how-the-viral-roblox-meme-game-works-and-tips-to-grow-your-brainrot-base)
- [Steal a Brainrot — Roblox Wiki](https://roblox.fandom.com/wiki/BRAZILIAN_SPYDER/Steal_a_Brainrot)
- [Grow a Garden: guía de mecánicas 2026 — GAG Calculator](https://www.gagdata.com/blog/game-basics)
- [Grow a Garden: guía de juego 2026 — NoPing](https://noping.com/sa/blog/grow-a-garden-gameplay-guide)
- [Roblox Charts 2026 — juegos más jugados](https://ejaw.net/roblox-charts/)
- [Top Roblox Games May 2026 — StudioKrew](https://studiokrew.com/blog/top-roblox-games-may-2026/)
- [Most Popular Roblox Game Genres in 2026 — KitsBlox](https://kitsblox.com/blog/popular-roblox-game-genres-2026)
- [Grow a Garden — Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden)
