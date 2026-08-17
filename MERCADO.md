# Estudio de mercado: ¿qué juego tiene sentido hacer en Roblox?

> Agosto 2026. Continuación de [`RESEARCH.md`](RESEARCH.md), que respondía "¿se puede ganar
> dinero?". Este responde "¿haciendo qué?". Fuentes al final.

---

## 1. Conclusión primero

**El hueco está en el público adulto, y ahí tu material previo encaja mejor de lo que yo
mismo dije.** Roblox busca activamente RPG, estrategia, shooters y puzzles porque están
infrarrepresentados, mientras el 18+ ya es el 27% de los usuarios diarios y el tramo 18-34
crece más del 50% interanual. Simuladores y obbies, en cambio, están saturados.

**Pero hay una trampa que debes conocer antes de ilusionarte: la IA generativa en tiempo
real no es económicamente viable en Roblox.** Los números están en la sección 6 y son
demoledores. Es lo primero que pensarías hacer, y te habría costado meses descubrirlo.

---

## 2. Cómo es el mercado hoy

Los juegos más visitados de la historia de la plataforma:

| Juego | Visitas | Género |
|---|---|---|
| Brookhaven RP | 83.400 M | Roleplay / vida social |
| Steal a Brainrot | 69.800 M | Tycoon + robo (híbrido) |
| Blox Fruits | 62.000 M | RPG de combate |
| Adopt Me | 43.800 M | Roleplay / mascotas |
| Grow a Garden | 35.500 M | Idle / colección |

Dos hechos que marcan la escala real de la plataforma:

- **Steal a Brainrot alcanzó 25,8 millones de jugadores simultáneos** en octubre de 2025.
  Es el récord de concurrencia de cualquier videojuego de la historia, en cualquier
  plataforma.
- **Grow a Garden** superó los 21.000 millones de visitas en su primer año, a un ritmo que
  ningún juego nuevo había logrado antes.

Lo que domina hoy son **simulación e idle/RNG** (bucles rápidos, recompensa inmediata,
juego con amigos) y **roleplay** como segundo pilar.

---

## 3. Los números que deciden si un juego funciona

Estos son los benchmarks reales de Roblox. Son el termómetro de cualquier cosa que hagamos:

| Métrica | Bien | Muy bien | Excelente |
|---|---|---|---|
| **Retención D1** | 20% | 30% | 40%+ |
| **Retención D7** | 8% | 15% | 20%+ |
| **Retención D30** | 3% | 7% | 10%+ |
| **Sesión media** | La mitad de los juegos no pasa de **6 minutos**; el top 5% ronda los **30** |

Con 100+ jugadores diarios, Roblox te da comparativas contra juegos similares en su panel
de analítica. Esto confirma el umbral que fijamos en el research: **D1 por debajo del 15%
significa pivotar**.

---

## 4. Saturado vs. oportunidad

| Género | Estado | Por qué |
|---|---|---|
| **Simulador** | 🔴 Saturado | Volumen brutal de juegos casi idénticos |
| **Obby** | 🔴 Saturado | Lo mismo, y con sesiones cortas de una sola visita |
| **Roleplay social** | 🟠 Dominado | Brookhaven y Adopt Me tienen efecto de red imbatible |
| **Tycoon / idle** | 🟠 Competido | Funciona, pero compites contra los mejores del mundo |
| **RPG** | 🟢 **Buscado** | Roblox lo señala como infrarrepresentado y muy demandado |
| **Estrategia** | 🟢 **Buscado** | Ídem |
| **Shooter** | 🟢 **Buscado** | Ídem, orientado a 18+ |
| **Puzzle** | 🟢 **Infraservido** | Hueco explícito de mercado |
| **Horror** | 🟢 **Accesible** | Depende de ritmo, audio y diseño de nivel, **no de sistemas complejos** — por eso es el género más viable para equipos pequeños, y el favorito de los creadores de contenido |

---

## 5. El giro: el público adulto

Aquí debo corregir algo que te dije al principio. Cuando avisé de que tu registro noir y
gótico "no encaja" con Roblox, estaba pensando en el Roblox de hace unos años.

Los datos actuales dicen otra cosa:

- **27% de los usuarios activos diarios tienen más de 18 años.**
- **El tramo 18-34 crece más de un 50% interanual.**
- Roblox declara explícitamente que quiere juegos para ese público y que le faltan RPG,
  estrategia y shooters.

Eso significa que **CRIME** (whodunit años 30) y el **RPG narrativo** no son material
descartable: son material alineado con el hueco declarado de la plataforma. Tienes ambientación,
casos escritos, sistema de deducción probado e ilustraciones. Eso es meses de trabajo ya hechos.

**Con una objeción seria**, que es de diseño y no de tono:

> Un misterio narrativo es de **una sola sesión**. Resuelves el caso y te vas. Eso es
> catastrófico para D1/D7, que es exactamente lo que decide si el algoritmo te muestra.

CRIME tal cual, portado a Roblox, mediría D1 ~5%. No por malo, sino porque no hay razón
para volver mañana. Cualquier adaptación tiene que resolver eso primero.

---

## 6. La trampa de la IA generativa (léelo antes de nada)

Tu instinto será reutilizar el pipeline de generación con IA. **Los números no salen.**

| Concepto | Cifra |
|---|---|
| Ingreso real por visita (monetización decente) | **~0,0038 $** |
| Coste de generar un capítulo con M3 | ~0,01-0,05 $ |
| Capítulos por sesión | 3-5 |
| **Coste de IA por sesión** | **0,03-0,25 $** |
| **Resultado** | **Pierdes entre 10 y 60 veces lo que ingresas por jugador** |

Y esto empeora con el éxito: cuantos más jugadores, más pierdes. Es el peor modelo de
negocio posible. Súmale que todo output de IA que llegue al jugador es responsabilidad
legal tuya y debe pasar filtrado, y que la latencia de 50-160 s que tenemos medida es
inaceptable en un juego en tiempo real.

**Dónde sí cabe la IA:** en la *producción*, no en el *runtime*. Generar contenido offline
(casos, diálogos, texturas, mapas), validarlo, y meterlo ya hecho en el juego. Ahí el coste
es fijo y se amortiza entre todos los jugadores. Justo lo que ya haces con los capítulos
pre-generados y los assets.

---

## 7. ¿Qué es viable para una persona sola?

El caso de referencia es **Grow a Garden**: la primera versión la hizo **un chaval de 16
años en pocos días**. Con unos 1.000 jugadores simultáneos, Splitting Point Studios le
compró parte del juego y se incorporó al desarrollo; después entró Do Big Studios como
socio. El creador original conserva alrededor de la mitad.

De ahí salen las dos lecciones honestas:

1. **El techo no requiere un estudio.** Un prototipo simple hecho en días puede convertirse
   en el juego más jugado del mundo.
2. **La escala sí lo requiere.** Nadie sostiene un fenómeno así en solitario. El camino real
   es prototipo pequeño → señal de tracción → equipo o socio.

Y la referencia de ingresos: los 1.000 mejores creadores ganaron de media 1,3 M$ en 2025.
Recuerda que la mediana global sigue siendo 1.440 $/año.

---

## 8. Roblox tiene programas para esto (y encajas)

Anunciados en marzo de 2026:

| Programa | Para quién | Qué da |
|---|---|---|
| **Jumpstart** | Creadores nuevos en la plataforma o veteranos con conceptos novedosos. Basta con que **un miembro sea mayor de 18**. Convocatoria **abierta permanentemente** | Mentoría de expertos de Roblox, apoyo operativo en Robux y herramientas de visibilidad. **No es un sueldo ni un contrato editorial** |
| **Incubator** | Equipos con experiencia y un prototipo sólido. Hasta 40 por cohorte, 6 meses por hitos | Recursos y apoyo a medida según hitos |

**Jumpstart encaja con tu situación**: es continuo, admite gente nueva en la plataforma y
está pensado justo para conceptos que se salen de lo saturado. La visibilidad es el cuello
de botella que identificamos en el research, y esto ataca precisamente eso. Se solicita en
`create.roblox.com/build`.

---

## 9. Tres conceptos candidatos

Aplicando todo lo anterior a lo que ya sabes hacer:

### A. Misterio social multijugador ⭐ recomendado

Deducción entre jugadores en un escenario cerrado años 30. Reutiliza la ambientación, el
arte y el sistema de pistas de CRIME, pero **el misterio lo generan los jugadores**, no un
guion.

- **Resuelve el problema de la sesión única**: cada partida es distinta porque las personas
  son distintas. Rejugabilidad infinita sin coste de contenido.
- **Multijugador social** = el motor de retención más potente que existe: tus amigos te traen.
- Género de deducción social, con demanda probada y encaje con el público adulto.
- **Riesgo**: necesita masa crítica de jugadores para llenar partidas. Un juego social vacío
  está muerto.

### B. Horror cooperativo

Escapar de un sitio entre 3-4 jugadores. Es el género que las fuentes señalan como **más
accesible para equipos pequeños** (depende de ritmo, sonido y nivel, no de sistemas) y el
que más tirón tiene entre creadores de contenido en YouTube y TikTok — que es el canal de
adquisición de mayor ROI según el research.

- **Riesgo**: el arte y el sonido *son* el juego. Es justo nuestro punto débil.

### C. RPG narrativo por capítulos

Lo más cercano a lo que ya tienes construido.

- **Riesgo alto**: contenido pre-generado se agota, y el jugador se va cuando lo termina. La
  retención a 30 días es estructuralmente mala salvo que haya producción continua.
- Solo tiene sentido con contenido episódico constante, que es un compromiso serio.

---

## 10. Mi recomendación

**Concepto A**, y por una razón concreta: es el único de los tres donde **la retención está
integrada en el diseño** en lugar de depender de que sigamos produciendo contenido. Todo lo
demás — el research, los benchmarks, el algoritmo — apunta a que ese es el factor decisivo.

Además aprovecha lo que ya tienes (ambientación, arte, mecánica de deducción) y evita lo que
no tenemos (capacidad de producción de arte 3D y de contenido continuo).

Antes de escribir una línea de código, el siguiente paso es **diseñar el bucle**: qué pasa
en los primeros 60 segundos, por qué alguien vuelve mañana, y cómo funciona una partida con
8 desconocidos. Eso es una conversación de diseño, no de programación.

---

## Fuentes

- [Roblox Charts 2026 — juegos más jugados](https://ejaw.net/roblox-charts/)
- [Most Popular Roblox Games by Visits 2026 — Udonis](https://www.blog.udonis.co/mobile-marketing/mobile-games/most-popular-roblox-games)
- [Roblox most popular games 2026 — Statista](https://www.statista.com/statistics/1220905/roblox-most-visited-games)
- [Roblox Retention Rate Benchmarks by Genre 2026 — BLOXG](https://bloxg.com/statistics/roblox-retention-benchmarks)
- [Roblox Player Retention Strategies — BLOXG](https://bloxg.com/guides/roblox-player-retention)
- [Analytics — documentación oficial de Roblox](https://create.roblox.com/docs/production/analytics)
- [The Roblox Content Creator Landscape 2026 — ROLearn](https://rolearn.dev/trend-reports/roblox-content-creator-landscape-2026/)
- [Roblox anuncia Incubator y Jumpstart — sala de prensa oficial](https://about.roblox.com/newsroom/2026/03/roblox-announces-incubator-jumpstart-creator-programs)
- [Roblox Jumpstart — documentación oficial](https://create.roblox.com/docs/creator-programs/jumpstart)
- [A Look at the 2026 Roblox Incubator Cohort — Roblox](https://about.roblox.com/newsroom/2026/06/2026-roblox-incubator-cohort)
- [Grow a Garden: cómo el juego de un adolescente se hizo el más popular del mundo — Calcalist](https://www.calcalistech.com/ctechnews/article/dj4lxef8r)
- [Entrevista a Janzen "Jandel" Madsen sobre Grow a Garden — GamesBeat](https://gamesbeat.com/janzen-madsen-interview/)
- [Grow a Garden — Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden)
- [Roblox Game Genres — Complete Guide 2026](https://www.creation.dev/genres)
- [Turn your creativity into income — documentación oficial](https://create.roblox.com/docs/monetize)
