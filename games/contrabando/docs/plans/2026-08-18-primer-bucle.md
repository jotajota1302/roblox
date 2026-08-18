# El primer bucle — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la primera recompensa llegue en ~45 segundos en vez de ~100, que el jugador sepa siempre qué toca hacer, y que cobrar se note.

**Architecture:** Un módulo puro nuevo (`Goals`) con los hitos; el contador de entregas en el estado; el enganche donde ya se cobra (`CargoService`); una ruta de barrio plantada por `CityBuilder` con la maquinaria que ya existe; y en el cliente unos números flotantes que no tocan ninguna regla.

**Tech Stack:** Luau, Rojo 7.7.0, pruebas propias (`TestKit`/`TestRunner`) ejecutadas dentro de Studio por MCP.

**Spec:** `games/contrabando/docs/specs/2026-08-18-primer-bucle-design.md`

## Global Constraints

- **El servidor decide.** El selector pinta, pero un remote manipulado manda el id que quiera: los hitos se comprueban en el servidor.
- **La lógica de reglas vive en módulos PUROS de `src/shared/`**; los servicios son pegamento.
- **Lo que es información va en `Heartbeat`, nunca en `RenderStepped`** (con la ventana sin foco, `RenderStepped` da cero llamadas por segundo — medido).
- **Cada pantalla del cliente se construye dentro de su `pcall`.**
- **Nada que se plante en el mundo se baja al suelo con un rayo desde arriba**: devuelve tejados y copas de árbol. Se usa `sueloTransitable`, y si no hay calle, no se planta.
- **Código y comentarios en español.**
- **Formato:** `tools/stylua.exe --check src` a 0 antes de cada commit.
- **Verificación de las pruebas puras** (Studio, datamodel `Edit`, por MCP):
  ```lua
  local copia = game.ReplicatedStorage.Shared:Clone()
  copia.Parent = game.ReplicatedStorage
  local r = require(copia.TestRunner).run()
  copia:Destroy()
  return r
  ```
  El clon es obligatorio: `require` cachea por instancia.
- **Para verificar el estado real hay que plantar un `Script` en `ServerScriptService` durante el Play** y publicar el resultado en atributos del `workspace`: `require` dentro de `execute_luau` corre en un sandbox aparte y toca un estado paralelo.
- **Botones táctiles: 48 px mínimo.**

---

## Estructura de ficheros

| Fichero | Responsabilidad | Estado |
|---|---|---|
| `src/client/Popups.luau` | Números flotantes al cobrar y al recoger | Crear |
| `src/client/Hud.luau` | Dinero contando; la misión dice el hito | Modificar |
| `src/shared/Goals.luau` | **Puro.** Hitos, condición, recompensa | Crear |
| `src/shared/tests/Goals.spec.luau` | Pruebas de los hitos | Crear |
| `src/shared/Config.luau` | La ruta `barrio` y la tabla de hitos | Modificar |
| `src/server/PlayerState.luau` | `entregas` y `hitos` en el estado y el sync | Modificar |
| `src/server/Persistence.luau` | Guardarlos | Modificar |
| `src/server/CargoService.luau` | Contar la entrega, cobrar el hito, avisar | Modificar |
| `src/shared/Routes.luau` | `disponible` mira también los hitos | Modificar |
| `src/server/CityBuilder.luau` | Plantar el destino del barrio | Modificar |
| `src/server/SelfCheck.luau` | Que el barrio tenga calle y camino | Modificar |

---

### Task 1: Que cobrar se note

**Files:**
- Create: `src/client/Popups.luau`
- Modify: `src/client/Hud.luau` (el dinero cuenta en vez de saltar)
- Modify: `src/client/Main.client.luau` (arrancarlo y engancharlo al sync)

**Interfaces:**
- Produces: `Popups.build()`, `Popups.mostrar(texto: string, color: Color3, tamano: number?)` — pinta el texto sobre el personaje y lo desvanece.

- [ ] **Step 1: Escribir `Popups.luau`**

Un `BillboardGui` por número, colgado del `HumanoidRootPart`, que sube ~4 studs y se desvanece en 1,2 s con `TweenService`. Se destruye al terminar.

**Por qué `TweenService` y no un bucle propio:** la animación la lleva el motor, así que no hay ningún bucle nuestro que dependa de `RenderStepped` — que con la ventana sin foco no corre.

Límite de 6 números vivos a la vez: al recoger contactos seguidos se solaparían y el efecto se convierte en ruido.

- [ ] **Step 2: El dinero cuenta hacia arriba**

En `Hud.update`, en vez de escribir la cifra nueva de golpe, guardar la anterior y avanzar hacia la nueva en el bucle de 0,25 s que ya existe en `Main.client`. **Un salto grande se completa igualmente en ~1 s**: contar de 0 a 15.000 moneda a moneda sería peor que no contar.

- [ ] **Step 3: Engancharlo**

- Al llegar un sync con más dinero que el anterior: `Popups.mostrar("+" .. diferencia, oro)`.
- Al llegar un sync con más contactos que el anterior: `Popups.mostrar("+1", ambar, pequeño)`.

**El cliente NO decide nada aquí**: sólo dibuja la diferencia entre dos estados que le ha mandado el servidor.

- [ ] **Step 4: Verificar en Play**

Desde el datamodel `Client`, comprobar que existe el `ScreenGui`/`BillboardGui` y que tras un cambio de dinero aparece un número y desaparece solo. Y que no quedan instancias huérfanas después (contar hijos antes y después).

- [ ] **Step 5: Formato y commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/client/
git commit -m "feat: cobrar se nota -- numeros flotantes y el dinero contando"
```

---

### Task 2: Los hitos, como reglas puras

**Files:**
- Modify: `src/shared/Config.luau`
- Create: `src/shared/Goals.luau`
- Test: `src/shared/tests/Goals.spec.luau`

**Interfaces:**
- Produces:
  - `export type Hito = { id: string, texto: string, entregas: number?, nivel: number?, exigeMotor: boolean?, monedas: number?, abre: string? }`
  - `Goals.actual(entregas: number, nivel: number, hitos: { [string]: boolean }): Hito?`
  - `Goals.cumplidos(entregas: number, nivel: number, vehiculo: string?, hitos: { [string]: boolean }): { Hito }` — los que se acaban de cumplir y aún no se han cobrado
  - `Goals.rutaAbierta(rutaId: string, hitos: { [string]: boolean }): boolean`
  - `Goals.progreso(hito: Hito, entregas: number, nivel: number): string` — "1 de 3 entregas"

- [ ] **Step 1: La tabla en `Config.luau`**

```lua
-- LOS HITOS: qué toca hacer ahora, y qué se gana al hacerlo.
--
-- POR QUÉ EXISTEN. Medido: la primera recompensa del juego llegaba a los ~100 s,
-- y en el juego que lo inspiró llega a los 3. Un jugador nuevo no tiene forma de
-- saber qué se espera de él ni cuánto falta para lo siguiente.
--
-- SE CUENTAN ENTREGAS, NO NIVEL, para los peldaños de abajo: el nivel sube con el
-- dinero cobrado, así que su ritmo depende de qué llevabas encima y no de cuánto
-- has jugado. Uno con suerte en el sorteo de rarezas saltaría dos peldaños en su
-- primer viaje y otro se quedaría atascado haciendo exactamente lo mismo.
Config.HITOS = {
	{ id = "primera", texto = "Entrega tu primer paquete", entregas = 1, monedas = 50, abre = "verde" },
	{ id = "tres", texto = "Entrega 3 paquetes", entregas = 3, monedas = 250 },
	{ id = "ambar", texto = "Sube a nivel 3 para la ruta ambar", nivel = 3 },
	{ id = "ocho", texto = "Entrega 8 paquetes", entregas = 8, monedas = 1000 },
	{ id = "roja", texto = "Nivel 8 y un vehiculo de motor para la roja", nivel = 8, exigeMotor = true },
}
```

- [ ] **Step 2: Escribir la prueba que falla**

```lua
--!strict
-- Pruebas de los hitos. Lo que se comprueba es que avancen EN ORDEN, que no se
-- cobren dos veces, y que un estado corrupto no abra nada: el hito 1 abre la ruta
-- verde, así que es una llave y se trata como tal.

local Goals = require(script.Parent.Parent.Goals)

return function(kit)
	local ninguno: { [string]: boolean } = {}

	-- El primero, de salida.
	local primero = Goals.actual(0, 1, ninguno)
	kit.truthy("hay un hito al empezar", primero ~= nil)
	kit.eq("y es la primera entrega", (primero :: any).id, "primera")
	kit.eq("con su progreso", Goals.progreso(primero :: any, 0, 1), "0 de 1 entregas")

	-- Al cumplirlo aparece, y sólo una vez.
	kit.eq("con 0 entregas no se cumple nada", #Goals.cumplidos(0, 1, nil, ninguno), 0)
	local cumplidos = Goals.cumplidos(1, 1, nil, ninguno)
	kit.eq("con 1 entrega se cumple el primero", #cumplidos, 1)
	kit.eq("y es ese", cumplidos[1].id, "primera")
	kit.eq("ya cobrado, no se vuelve a cumplir", #Goals.cumplidos(1, 1, nil, { primera = true }), 0)

	-- El siguiente pasa a ser el actual.
	kit.eq("el actual avanza", (Goals.actual(1, 1, { primera = true }) :: any).id, "tres")

	-- LAS RUTAS. La verde está cerrada hasta el primer hito: es la llave de la
	-- escalera, y por eso se comprueba en el servidor y no en el selector.
	kit.falsy("la verde empieza cerrada", Goals.rutaAbierta("verde", ninguno))
	kit.truthy("y se abre con el primer hito", Goals.rutaAbierta("verde", { primera = true }))
	kit.truthy("el barrio esta abierto desde el principio", Goals.rutaAbierta("barrio", ninguno))
	kit.truthy("y las de arriba no dependen de hitos", Goals.rutaAbierta("roja", ninguno))

	-- El de nivel no se cumple por entregar.
	kit.eq("el hito de nivel pide nivel", #Goals.cumplidos(99, 1, nil, { primera = true, tres = true }), 0)
	kit.eq(
		"y se cumple al llegar",
		Goals.cumplidos(99, 3, nil, { primera = true, tres = true })[1].id,
		"ambar"
	)

	-- El de la roja pide las dos cosas.
	local casi = { primera = true, tres = true, ambar = true, ocho = true }
	kit.eq("nivel 8 sin motor no basta", #Goals.cumplidos(99, 8, "bicicleta", casi), 0)
	kit.eq("con motor si", #Goals.cumplidos(99, 8, "moto", casi), 1)

	-- Cuando no queda ninguno, no revienta.
	local todos = { primera = true, tres = true, ambar = true, ocho = true, roja = true }
	kit.eq("sin hitos pendientes no hay actual", Goals.actual(99, 99, todos), nil)

	-- Basura no abre nada.
	kit.falsy("un hito inventado no abre la verde", Goals.rutaAbierta("verde", { pirata = true }))
end
```

- [ ] **Step 3: Ejecutar y ver que falla**

Esperado: `[X] Goals.spec :: la suite reventó: ... Goals is not a valid member of Shared`.

- [ ] **Step 4: Escribir `Goals.luau`**

Recorre `Config.HITOS` en orden. `actual` devuelve el primero no cobrado. `cumplidos` devuelve los no cobrados cuya condición ya se cumple (entregas ≥, nivel ≥, y motor si lo pide). `rutaAbierta` busca si alguna ruta la abre y si ese hito está cobrado; una ruta que nadie abre está abierta.

**Todo lo que venga de fuera se trata como sospechoso**: `hitos` llega del DataStore y de un cliente que puede estar manipulado, así que las claves desconocidas se ignoran.

- [ ] **Step 5: Ejecutar y ver que pasa**

- [ ] **Step 6: Formato y commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/shared/Config.luau games/contrabando/src/shared/Goals.luau games/contrabando/src/shared/tests/Goals.spec.luau
git commit -m "feat: los hitos, con la escalera de rutas comprobada en la suite"
```

---

### Task 3: Contar entregas y cobrar los hitos

**Files:**
- Modify: `src/server/PlayerState.luau` (`entregas`, `hitos`, y los dos al sync)
- Modify: `src/server/Persistence.luau` (guardar y cargar)
- Modify: `src/server/CargoService.luau` (dentro de `cobrar`)

**Interfaces:**
- Consumes: `Goals.cumplidos`, `Goals.actual` (Task 2).
- Produces: `estado.entregas: number`, `estado.hitos: { [string]: boolean }`, ambos en el sync.

- [ ] **Step 1: El estado y el guardado**

Igual que se hizo con `contactos` y `habilidades`: campos nuevos en `Estado`, valores iniciales (`0` y `{}`), al sync, y al DataStore. En la carga, **`hitos` se sanea contra `Config.HITOS`**: una clave guardada que hoy no existe no puede abrir una ruta.

- [ ] **Step 2: Contar y cobrar, donde ya se cobra**

Dentro de `cobrar` en `CargoService`, justo después de `estado.dinero += cobrado`:

```lua
	estado.entregas = (estado.entregas or 0) + 1
	-- LOS HITOS SE COBRAN AQUÍ y no en un servicio aparte: es el único sitio del
	-- juego donde una entrega ocurre de verdad, y separarlo obligaría a que dos
	-- módulos se pusieran de acuerdo sobre cuándo cuenta una entrega.
	for _, hito in Goals.cumplidos(estado.entregas, Levels.nivelDe(estado.xp or 0), estado.vehiculo, estado.hitos) do
		estado.hitos[hito.id] = true
		if hito.monedas then
			estado.dinero += hito.monedas
		end
		avisar(player, string.format("%s  (+%d)", hito.texto, hito.monedas or 0), Palette.AVISO_BUENO)
	end
```

- [ ] **Step 3: Verificar en el servidor real**

Con un `Script` plantado en `ServerScriptService` durante el Play (el `require` de `execute_luau` toca un estado paralelo): entregar una vez y comprobar que `entregas` es 1, que `hitos.primera` es `true`, y que el dinero subió el cobro **más** las 50 monedas del hito. Y entregar otra vez para comprobar que **no** se cobra dos veces.

- [ ] **Step 4: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/server/
git commit -m "feat: las entregas se cuentan y los hitos se cobran al entregar"
```

---

### Task 4: El objetivo, siempre a la vista

**Files:**
- Modify: `src/client/Hud.luau`
- Modify: `src/client/Main.client.luau` (`misionActual`)

- [ ] **Step 1: La misión dice el hito**

`misionActual` ya elige qué poner en la línea de misión según el estado. Pasa a anteponer el hito actual con su progreso: `"Entrega 3 paquetes  ·  1 de 3"`. Si no hay hito pendiente, se queda como está hoy.

**Va en la línea que ya existe** y no en un panel nuevo: la pantalla está llena, y este proyecto ya pagó una ronda por un botón que pisaba el de salto de Roblox.

- [ ] **Step 2: Verificar**

En Play, datamodel `Client`: leer el texto de la línea de misión y comprobar que dice el hito y el progreso. Y comprobar el solape en **coordenadas absolutas y todos contra todos** — el texto es más largo que antes.

- [ ] **Step 3: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/client/
git commit -m "feat: el HUD dice que toca hacer ahora"
```

---

### Task 5: Que la escalera cierre de verdad las rutas

**Files:**
- Modify: `src/shared/Routes.luau` (`disponible` y `requisito`)
- Modify: `src/shared/tests/Routes.spec.luau`
- Modify: `src/server/RouteService.luau` (pasarle los hitos)
- Modify: `src/client/RoutePicker.luau` (pintar el motivo)

- [ ] **Step 1: La prueba primero**

En `Routes.spec`, añadir: con hitos vacíos, `disponible("verde", 1, nil, {})` devuelve `false` y motivo `"hito_pendiente"`; con `{ primera = true }` devuelve `true`; y `disponible("barrio", 1, nil, {})` devuelve `true` siempre.

- [ ] **Step 2: Implementarlo**

`Routes.disponible(rutaId, nivel, vehiculo, hitos)` pregunta a `Goals.rutaAbierta` antes que nada. `Routes.requisito` devuelve el texto del hito que falta.

**El parámetro va al final y con valor por defecto** para no romper a quien ya la llama sin él; pero `RouteService` **sí** lo pasa, que es el que decide.

- [ ] **Step 3: El selector lo dice**

`RoutePicker` pinta la ruta bloqueada con su motivo, igual que ya hace con el nivel: "Entrega tu primer paquete". Una puerta cerrada sin explicación se lee como un juego roto.

- [ ] **Step 4: Verificar y commit**

Batería en verde, y en Play: con estado nuevo, elegir "verde" por el remote debe ser rechazado con su aviso; tras una entrega en el barrio, aceptado.

```bash
git commit -m "feat: la verde se gana entregando, y el selector dice como"
```

---

### Task 6: El destino de barrio

**Files:**
- Modify: `src/shared/Config.luau` (`Config.RUTAS`)
- Modify: `src/server/CityBuilder.luau`

- [ ] **Step 1: La ruta**

En `Config.RUTAS`, **la primera**, con `id = "barrio"`, `multiplicador = 0.5`, `nivel = 1`, `detectores = 1`, `pvp = "ninguno"`, y `destino` a ~250 studs de `Config.POLIGONO_SALIDA` en dirección a la ciudad.

**El destino no se elige a ojo.** Se busca con la maquinaria que ya existe: un sitio llano, con calle cerca (`calleMasCercana`) y a la altura del suelo. Si el punto elegido no cumple, se prueba otro — igual que se hizo con la parcela del almacén, que se eligió puntuando espacio libre y acabó flotando 9 studs sobre una calle.

- [ ] **Step 2: Plantarlo**

`CityBuilder` ya recorre `Routes.todas()` para plantar destinos, carteles, accesos, detectores, guaridas y contactos: la ruta nueva entra por ahí sola. Comprobar que:

- `Config.GUARIDAS_POR_RUTA` no le planta guaridas (el spec dice ninguna): darle su propio número o saltarla.
- `Config.CONTACTOS_POR_RUTA` tiene entrada `barrio = { sueltos = 3, racimos = 0 }`.
- El acceso asfaltado llega hasta la calle más cercana.

- [ ] **Step 3: Medir el mundo, que es donde este proyecto se equivoca**

En Play:

```lua
-- El destino, apoyado y con calle
-- El camino a pie desde la salida, y cuánto mide
local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
path:ComputeAsync(Config.POLIGONO_SALIDA, Routes.get("barrio").destino)
```

Esperado: `Success`, y **entre 200 y 350 studs**. Por debajo de 200 la entrega cae dentro de la zona segura y no enseña nada; por encima de 350 no es un bucle corto.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: el barrio, la rampa de entrada al juego"
```

---

### Task 7: Que no pueda romperse en silencio

**Files:**
- Modify: `src/server/SelfCheck.luau`
- Modify: `games/contrabando/VERIFICACION.md`

- [ ] **Step 1: La sonda**

Añadir a la sonda de accesos/destinos: el destino del barrio existe, está apoyado en el suelo (contra el suelo que tiene **debajo**, no contra una cota fija), tiene calle a menos de 40 studs, y hay camino a pie desde la salida de entre 200 y 350 studs.

- [ ] **Step 2: LA MEDIDA QUE DECIDE**

Cronometrar **andando** desde que aparece el personaje hasta que cobra la primera vez. Sonda con `Humanoid:MoveTo` replanteando cada 2 s (una sonda en línea recta se clava contra un seto y parece un atasco del juego).

**Objetivo: ≤ 50 segundos.** Hoy son ~100. Si no baja de ahí, este trabajo no ha servido por muy escrito que esté el código, y hay que acortar más el barrio o mover la salida.

- [ ] **Step 3: Anotarlo y commit**

Escribir en `VERIFICACION.md` el tiempo medido y `git commit`.

---

## Después de este plan

Actualizar `JUEGO.md` (§2 el bucle y los primeros 60 s, §3 las rutas) y `RUMBO.md` §6. Y jugar: si el primer minuto sigue sin enganchar, lo siguiente no es más contenido — es acortarlo más.
