# Roblox — investigación y piloto

Dos cosas viven aquí:

## 📊 [`RESEARCH.md`](RESEARCH.md) — ¿se puede ganar dinero?

Investigación con datos verificados contra la documentación oficial de Roblox (agosto 2026):
cómo entra el dinero y cuánto se queda cada uno, cuánto gana la gente de verdad, las 8 vías
de monetización, por qué el cuello de botella es el descubrimiento y no la calidad, qué
herramientas hacen falta y qué riesgos hay.

**Resumen:** sí se puede, pero de cada euro que gasta un jugador te llegan ~21-27 céntimos,
la mediana de un desarrollador que cobra es 1.440 $/año y el 85% gana menos de 100 $/mes.
Entrar cuesta 0 €, así que el experimento sale barato — pero es una lotería de cola larga.

## 🎯 [`MERCADO.md`](MERCADO.md) — ¿qué juego tiene sentido hacer?

Estudio de mercado: qué géneros dominan, cuáles están saturados, qué busca activamente
Roblox, y los benchmarks de retención que deciden si un juego funciona (D1: 20% bien,
30% muy bien, 40% excelente).

**Conclusión:** el formato a construir es un bucle de progresión jugable en solitario con
una capa social de fricción encima — el único que funciona desde el primer jugador. Los
formatos con mejor diseño (deducción social, PvP) necesitan 6-10 personas simultáneas y no
arrancan sin audiencia previa. Y una trampa: **la IA generativa en tiempo real pierde entre
10 y 60 veces lo que ingresa por jugador** — sirve para producir contenido, no para
ejecutarlo en la partida.

## 🧭 [`TARGETS.md`](TARGETS.md) — anatomía de los éxitos y plan

Disección por dentro de Grow a Garden, Steal a Brainrot y Brookhaven: qué bucle tienen y
qué sistemas los sostienen. De ahí salen **seis mecanismos de retención reutilizables**
(ingreso pasivo, timers escalonados, RNG exponencial, tienda con refresco, eventos globales
sincronizados y fricción social con riesgo) — ninguno necesita arte caro ni narrativa.

Y tres conceptos concretos evaluados con esos criterios: excavación, contrabando y
restauración. **Recomendado: contrabando**, con su plan de las primeras semanas y los
criterios para matarlo rápido si no engancha.

## 🚚 [`games/contrabando/`](games/contrabando/) — el juego en desarrollo

El target elegido: tienes un almacén que produce mercancía mientras no estás, y decides qué
llevar, a dónde y por qué ruta — en las que más pagan, cualquiera puede alcanzarte y
quitarte parte de la carga. Jugable en solitario desde el primer jugador, mejor con gente.

- [`DISENO.md`](games/contrabando/DISENO.md) — el spec: bucle, economía con números,
  arquitectura, alcance del prototipo y criterios para matarlo.
- [`docs/plans/`](games/contrabando/docs/plans/) — el plan de implementación, tarea a tarea.

## 🎮 [`games/coin-island/`](games/coin-island/) — el piloto

Juego pequeño y completo para entender cómo funciona Roblox por dentro: mundo 3D
multijugador, economía, tienda, guardado en la nube y dos productos de pago.
~700 líneas de Luau comentadas en español.

Todo se genera **por código** (el mapa y la interfaz incluidos), así que el juego entero
vive en git en vez de dentro de un binario de Studio.

👉 **Empieza por [`games/coin-island/README.md`](games/coin-island/README.md)**, que lleva la guía paso
a paso desde instalar Studio hasta publicar y activar los pases de pago.

---

## 📚 `creator-docs/` — documentación oficial en local (no versionada)

Clon en modo *sparse* del repo oficial [`Roblox/creator-docs`](https://github.com/Roblox/creator-docs):
1005 ficheros markdown + 1232 YAML de referencia de la API, sin imágenes ni historial (19 MB).

Sirve para lo que la web no permite: **buscar en toda la documentación de golpe**. Un
`grep` de `ProcessReceipt` o `FilterStringAsync` encuentra en un segundo las advertencias
que no sabías que tenías que buscar — así apareció la causa del primer fallo grave del
piloto, que estaba documentada y no se veía navegando página a página.

No sustituye al **MCP de Roblox Studio**, que es otra cosa: el MCP da acceso al estado
real del juego (ejecutar Luau, inspeccionar el árbol, jugar y capturar). Documentación y
MCP son complementarios: uno dice cómo funciona la plataforma, el otro qué está pasando
en tu partida.

Se recupera con `setup.ps1`.

## Puesta en marcha rápida

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1   # descarga rojo + stylua en ./tools
cd games\coin-island
..\..\tools\rojo.exe serve                              # y conecta desde Studio
```

Requisitos: Windows, VS Code y Roblox Studio (<https://create.roblox.com/>).
Las extensiones recomendadas de VS Code se sugieren solas al abrir la carpeta.
