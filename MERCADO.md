# Estudio de mercado: ¿qué juego tiene sentido hacer en Roblox?

> Agosto 2026. Continuación de [`RESEARCH.md`](RESEARCH.md), que respondía "¿se puede ganar
> dinero?". Este responde "¿haciendo qué?". Fuentes al final.

---

## 1. Conclusión primero

**El formato a construir es un bucle de progresión jugable en solitario con una capa social
de fricción encima** — la estructura de los dos mayores éxitos actuales de la plataforma.
No porque el género sea original, sino porque es el único que funciona **desde el primer
jugador**: los formatos con mejor diseño (deducción social, PvP) necesitan 6-10 personas a
la vez y nunca arrancan sin audiencia previa. Ese criterio, el del arranque en frío, decide
más que la calidad del concepto.

**Dos avisos antes de seguir:**

1. **La IA generativa en tiempo real no es económicamente viable en Roblox** (sección 6).
   Pierde entre 10 y 60 veces lo que ingresa por jugador, y empeora con el éxito.
2. **La narrativa retiene mal por construcción**: una historia se juega una vez. Es la
   trampa que espera a quien oiga que el público adulto está creciendo (sección 5).

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

## 5. El público adulto está creciendo

- **27% de los usuarios activos diarios tienen más de 18 años.**
- **El tramo 18-34 crece más de un 50% interanual.**
- Roblox declara explícitamente que quiere juegos para ese público y que le faltan RPG,
  estrategia y shooters.

Es el cambio demográfico más relevante de la plataforma: durante años el consejo era
"diseña para niños de 10 años" y hoy hay un segmento adulto grande, creciendo deprisa y
mal servido. Abre temáticas y tonos que antes no tenían sitio.

**Ojo con una trampa de diseño asociada.** El instinto al oír "público adulto" es pensar en
juegos narrativos, y la narrativa tiene un problema estructural en esta plataforma:

> Una historia se juega **una vez**. Llegas al final y te vas. Eso hunde D1/D7, que es
> justo lo que decide si el algoritmo te enseña a alguien.

Un juego de historia bien hecho puede medir D1 ~5%. No por malo: porque no hay motivo para
volver mañana. Si se toca ese terreno, hay que resolver la repetición **antes** que la
historia.

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

## 9. Cómo elegir género, objetivamente

Cinco criterios, sin mirar qué se ha hecho antes ni qué material existe:

1. **¿La retención está en el diseño, o depende de producir contenido sin parar?**
2. **¿Cuánto arte 3D y animación necesita?** Es el cuello de botella real de un dev solo,
   no la programación.
3. **¿Está saturado?**
4. **¿Puede una persona tener algo jugable en 2-4 semanas?**
5. **¿Funciona con un jugador?** — el criterio que más se olvida y el más letal. Un juego
   que necesita 8 personas simultáneas **nunca arranca** si nadie te conoce. Es el problema
   del arranque en frío, y mata más juegos que cualquier bug.

| Género | Retención por diseño | Coste de arte | Saturación | Arranca solo | Veredicto |
|---|---|---|---|---|---|
| Deducción social | ✅ Alta | 🟢 Bajo | 🟢 Libre | ❌ **Necesita 6-10** | Arranque en frío letal |
| Horror cooperativo | 🟠 Media | 🔴 **Alto** (el arte *es* el juego) | 🟢 Libre | 🟠 Necesita 3-4 | Depende de lo que peor hacemos |
| Narrativo / RPG | ❌ Necesita contenido continuo | 🔴 Alto | 🟢 Libre | ✅ Sí | Insostenible en solitario |
| Estrategia / PvP | ✅ Alta | 🟢 Bajo | 🟢 Libre | ❌ Necesita rival | Arranque en frío |
| Puzzle | 🟠 Media | 🟢 Bajo | 🟢 **Hueco declarado** | ✅ Sí | Viable, retención floja |
| **Progresión + capa social** | ✅ **Alta** | 🟢 Bajo | 🟠 Saturado de clones | ✅ **Sí** | **Único que aprueba los cinco** |

### Lo que el propio mercado está diciendo

Los dos fenómenos recientes de la plataforma tienen **exactamente la misma estructura**:

- **Grow a Garden**: plantas, esperas, recolectas. Se juega solo. Visitar y comparar
  jardines es la capa social. 35.500 M de visitas.
- **Steal a Brainrot**: acumulas cosas en tu base. Se juega solo. **Robar a otros** es la
  capa social. Récord histórico de concurrencia con 25,8 M simultáneos.

Ninguno de los dos necesita que haya gente para ser jugable, y los dos se vuelven mucho
mejores cuando la hay. Eso resuelve el arranque en frío **sin renunciar** al motor de
retención social. No es casualidad que sean los dos mayores éxitos del momento.

Y sobre la "saturación" de este formato, un matiz importante: está saturado de **clones
malos**, no de buenas ejecuciones. La diferenciación en Roblox no viene del género, viene
del tema y del giro concreto. Grow a Garden es un idle más; lo que lo separó fue la
ejecución y el momento.

---

## 10. Recomendación

**Un bucle de progresión jugable en solitario, con una capa social de fricción encima.**

Es el único formato que aprueba los cinco criterios: retiene por diseño, no exige arte
caro, se puede prototipar en semanas, y —lo decisivo— **funciona desde el primer jugador**
pero mejora cuando hay más. Es la estructura de los dos mayores éxitos actuales de la
plataforma, y la única que no depende de tener audiencia previa.

La "capa de fricción" es la pieza clave y donde está el diseño de verdad: robar, competir,
sabotear, comparar. Algo que haga que la presencia de otro jugador **te cambie la partida**,
para bien o para mal. Sin eso es un idle solitario y la retención se desploma.

Lo que **no** recomiendo, y por qué:

- **Deducción social y estrategia PvP**: excelentes de diseño, pero necesitan 6-10 personas
  a la vez. Sin audiencia previa no arrancan nunca. Son juegos para hacer *después* de
  tener jugadores, no para conseguirlos.
- **Horror**: las fuentes lo señalan como accesible para equipos pequeños, y es cierto en
  cuanto a sistemas. Pero el arte y el sonido *son* el producto, y es justo la capacidad
  que no tenemos.
- **Narrativo**: insostenible en solitario. El contenido se consume más rápido de lo que
  una persona puede producirlo, y ninguna cantidad de IA arregla eso (sección 6).

El siguiente paso no es elegir temática, es **diseñar el bucle**: qué haces en los primeros
60 segundos, qué te hace volver mañana, y qué cambia cuando entra otro jugador. La temática
se decide después, y se elige por diferenciación, no por gusto.

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
