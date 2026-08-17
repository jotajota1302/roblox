# Prototipo de rutas de contrabando — plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL OBLIGATORIA: usa
> `superpowers:subagent-driven-development` (recomendado) o
> `superpowers:executing-plans` para implementar este plan tarea a tarea.
> Los pasos usan casillas (`- [ ]`) para el seguimiento.

**Objetivo:** construir el prototipo jugable de "rutas de contrabando" hasta poder medir si
transportar carga entretiene diez minutos seguidos y si la intercepción entre jugadores da
tensión en vez de rabia.

**Arquitectura:** toda la lógica de reglas vive en módulos **puros** de `src/shared/`
(sin `Instance`, sin `game:GetService`), probados con un micro-framework propio que se
ejecuta dentro de Studio por MCP. Los servicios del servidor (`src/server/`) son la única
fuente de verdad y sólo orquestan esos módulos puros sobre el mundo. El cliente no tiene
lógica de juego: dibuja y avisa.

**Stack:** Luau (`--!strict`), Rojo 7.7.0 para sincronizar disco ↔ Studio, StyLua 2.5.2
para formato y sintaxis, MCP de Roblox Studio para ejecutar y verificar.

**Spec:** [`games/contrabando/DISENO.md`](../../DISENO.md) — el plan
argumenta desde ese documento; léelo antes de la primera tarea.

## Restricciones globales

Cada tarea las hereda implícitamente. Salen de `roblox/CLAUDE.md` y de la sección 4 del spec.

- **Proyecto nuevo:** todo el código va en `roblox/games/contrabando/`. No se toca `games/coin-island/`.
- **Comentarios en español, identificadores en inglés.** El código es material de aprendizaje.
- **El mundo y la interfaz se generan por código.** Nada a mano en Studio: el `.rbxl` es un
  artefacto desechable y todo debe ser revisable en un diff.
- **El servidor es la única fuente de verdad.** El cliente nunca envía "he cobrado esto",
  "he tocado a ese" ni "he llegado". Envía intenciones; el servidor decide.
- **Nada que pueda lanzar excepciones se llama al cargar un módulo.** `DataStoreService:GetDataStore()`
  lanza si el place no está publicado y mata el script entero: va perezoso y dentro de `pcall`.
- **`Players.CharacterAutoLoads = false`** durante el arranque, y `LoadCharacter()` manual
  cuando el mundo ya existe.
- **Móvil primero:** tamaños en `Scale` con `UISizeConstraint`, botones de 48 px mínimo,
  nada en las esquinas inferiores (joystick y salto), sin emojis en `TextLabel`.
- **Verificación mecánica mínima** antes de cada commit: `..\..\tools\stylua.exe --check src`
  (salida 0) y `..\..\tools\rojo.exe build --output contrabando.rbxl` (compila).
- **Verificación real dentro de Studio por MCP** en toda tarea que toque el mundo. Que
  compile no significa que funcione.
- **`get_console_output` del MCP se cuelga.** Diagnosticar siempre con `execute_luau`.
- Sin dependencias externas salvo necesidad clara.

### Constantes del prototipo que difieren del spec

Se documentan aquí para que nadie las "arregle" pensando que son un error, y llevan un
comentario `PROTOTIPO:` en el código para revertirlas antes de publicar.

| Constante | Spec | Prototipo | Por qué |
|---|---|---|---|
| Probabilidad de caja rara | 90 / 8 / 1,8 / 0,2 % | **70 / 20 / 8 / 2 %** | Con los números del spec una legendaria tarda ~25 h de producción. La mecánica hay que probarla en la primera sesión, no la semana que viene |
| Duración de ruta | 2 / 4 / 7 min | **600 / 1.200 / 2.000 studs** (≈40 s / 80 s / 2,5 min) | Se define por distancia, no por tiempo: el tiempo es consecuencia de la velocidad y de la carga. Un mapa que dé 7 minutos de viaje no cabe en un prototipo |
| Ritmo del almacén | 1 caja / 3 min | **1 caja / 30 s** | Probar el tope y el cálculo offline exige verlo llenarse dentro de una sesión |

---

## Estructura de ficheros

```
roblox/games/contrabando/
├── default.project.json          Mapeo Rojo → datamodel
├── README.md                     Qué es y cómo arrancarlo
└── src/
    ├── shared/                   → ReplicatedStorage.Shared
    │   ├── Config.luau           Todas las constantes. Sin lógica
    │   ├── Remotes.luau          Creación/espera de RemoteEvents
    │   ├── Economy.luau          PURO: valor de una entrega
    │   ├── Cargo.luau            PURO: peso, capacidad, velocidad
    │   ├── Rarity.luau           PURO: tirada de rareza
    │   ├── Routes.luau           PURO: rutas, precios, validación de destino
    │   ├── Warehouse.luau        PURO: producción offline con tope
    │   ├── Intercept.luau        PURO: ¿puede robar? ¿cuánto se lleva?
    │   ├── TestKit.luau          Micro-framework de pruebas
    │   ├── TestRunner.luau       Ejecuta todas las suites y devuelve informe
    │   └── tests/                Una suite por módulo puro
    ├── server/                   → ServerScriptService.Server
    │   ├── Main.server.luau      Punto de entrada blindado con pcall
    │   ├── WorldBuilder.luau     Mapa por código
    │   ├── PlayerState.luau      Estado en memoria de cada jugador
    │   ├── CargoService.luau     Recoger, soltar, velocidad
    │   ├── RouteService.luau     Elección de ruta y validación de entrega
    │   ├── WarehouseService.luau Producción y reclamo
    │   ├── InterceptService.luau Bucle de detección a 5 Hz
    │   ├── Persistence.luau      DataStore perezoso
    │   └── Telemetry.luau        Eventos de medición
    └── client/                   → StarterPlayer.StarterPlayerScripts.Client
        ├── Main.client.luau      Arranque del cliente
        ├── Hud.luau              Carga, dinero, aviso de persecución
        ├── Sfx.luau              Efectos de sonido
        └── RoutePicker.luau      Elección de ruta al salir del almacén
```

**Por qué esta división:** los módulos de `shared/` no tocan Roblox, así que se prueban en
milisegundos y son donde vive todo lo que puede estar mal en las reglas. Los servicios de
`server/` quedan reducidos a pegamento: leen el mundo, llaman a un módulo puro y aplican el
resultado. Cuando algo falle, sabrás en cuál de las dos mitades mirar.

**Sobre el `AntiCheat` que el spec lista como módulo:** no existe como fichero a propósito.
Sus tres piezas van dentro del sistema que protegen — la entrega se valida contra la posición
del servidor en `CargoService`, la ruta contra la salida del almacén en `RouteService`, y la
velocidad imposible dentro de `Intercept`. Un módulo aparte al que hay que acordarse de
llamar es un módulo al que un día no se llama.

---

## Cómo se prueba esto (léelo antes de la Tarea 0)

Luau no corre fuera de Roblox, así que el ciclo rojo/verde vive **dentro de Studio** y se
dispara por MCP:

1. Que el código esté dentro de Studio. Dos vías:
   - **Con alguien delante:** `..\..\tools\rojo.exe serve` y Connect desde el plugin. Al
     guardar un fichero, el módulo aparece actualizado en `ReplicatedStorage.Shared`.
   - **Sin nadie delante (la vía de este proyecto):** `..\..\tools\rojo.exe build --output
     contrabando.rbxl` genera el place ya montado y se abre en Studio. Tras cambiar código,
     escribir el `.Source` del módulo por `execute_luau` — o reconstruir y reabrir.
2. `mcp__Roblox_Studio__list_roblox_studios` para el `studio_id` (una vez por sesión).
3. `mcp__Roblox_Studio__execute_luau` (datamodel `Edit`) con **el lanzador de abajo**.

**El lanzador — úsalo siempre, no llames a `require` directamente:**

```lua
-- require() cachea por instancia: la segunda tanda devolvería el resultado de la primera
-- aunque el .Source haya cambiado, y verías verde sobre código que ya no existe. Clonar
-- Shared da instancias nuevas, sin caché, y aísla cada tanda de la anterior.
local clon = game.ReplicatedStorage.Shared:Clone()
clon.Name = "SharedTestRun"
clon.Parent = game.ReplicatedStorage

local ok, resultado = pcall(function()
	return require(clon.TestRunner).run()
end)

clon:Destroy()

if not ok then
	return "LA TANDA REVENTO: " .. tostring(resultado)
end
return resultado
```

Verificado en la Tarea 0: sin el clon, la corrección del paso 7 seguía dando el informe
rojo del paso 6.

**Para lo que toca el mundo — la sonda.** `require` dentro de `execute_luau` corre en un
sandbox aparte y **no comparte el caché de módulos con el servidor real**: la instancia que
obtienes ahí es nueva, con su estado vacío, así que puedes probar la lógica pero no el
servidor que está corriendo. Para probar el camino de verdad, planta un `Script` en
`ServerScriptService` — ése sí se ejecuta dentro del servidor real y comparte sus módulos —
y que publique lo que veas en atributos del `workspace`, que sí se leen desde fuera:

```lua
local sonda = Instance.new("Script")
sonda.Name = "SondaVerificacion"
sonda.Source = [==[
	local CargoService = require(game.ServerScriptService.Server.CargoService)
	-- ... actúa sobre el servidor real ...
	workspace:SetAttribute("sonda_dinero", estado.dinero)
]==]
sonda.Parent = game.ServerScriptService
```

Luego, desde `datamodel_type: "Client"`, actúa como actuaría un jugador (mover el personaje,
disparar el remote) y lee los atributos. **Retira la sonda al terminar.**

Verificado en la Tarea 3: por esta vía se comprobó que entregar lejos del destino paga 0 y
en el destino paga 30 — el camino completo cliente → remote → servidor real, que la
verificación en sandbox no puede tocar.

**Por qué aquí sí vale `require` dentro de `execute_luau`:** el aviso de `CLAUDE.md` es que
ese `require` corre en un sandbox aparte y no comparte estado con el servidor real. Para
módulos **puros y sin estado** eso es irrelevante — es justo el caso donde funciona. Para
todo lo que toque el mundo (Tareas 3, 6, 9, 11) hay que **actuar sobre el mundo**: mover
personajes, disparar remotes, leer atributos.

---

### Tarea 0: Andamiaje y ciclo de pruebas

Sin esto no hay TDD, así que va primero y termina con una prueba que falla a propósito y
luego pasa — para demostrar que el ciclo funciona de verdad.

**Ficheros:**
- Crear: `roblox/games/contrabando/default.project.json`
- Crear: `roblox/games/contrabando/src/shared/TestKit.luau`
- Crear: `roblox/games/contrabando/src/shared/TestRunner.luau`
- Crear: `roblox/games/contrabando/src/shared/tests/Sanity.spec.luau`
- Crear: `roblox/games/contrabando/README.md`

**Interfaces:**
- Consume: nada.
- Produce:
  - `TestKit.new(suite: string) -> Kit`
  - `Kit.eq(nombre: string, obtenido: any, esperado: any)`
  - `Kit.near(nombre: string, obtenido: number, esperado: number, tolerancia: number?)`
  - `Kit.truthy(nombre: string, valor: any)`
  - `Kit.falsy(nombre: string, valor: any)`
  - `Kit.errors(nombre: string, fn: () -> ())`
  - `TestRunner.run() -> string` (informe; termina en `OK` o en `FALLOS: n`)
  - Cada suite es un `ModuleScript` en `shared/tests/` que devuelve `(kit: TestKit.Kit) -> ()`

- [ ] **Paso 1: crear el mapeo de Rojo**

`roblox/games/contrabando/default.project.json`:

```json
{
  "name": "Contrabando",
  "tree": {
    "$className": "DataModel",

    "ReplicatedStorage": {
      "Shared": {
        "$path": "src/shared"
      }
    },

    "ServerScriptService": {
      "Server": {
        "$path": "src/server"
      }
    },

    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Client": {
          "$path": "src/client"
        }
      }
    },

    "Workspace": {
      "$properties": {
        "Gravity": 180
      }
    },

    "Lighting": {
      "$properties": {
        "Ambient": [0.3, 0.3, 0.35],
        "Brightness": 2,
        "ClockTime": 18,
        "OutdoorAmbient": [0.45, 0.45, 0.5]
      }
    }
  }
}
```

- [ ] **Paso 2: escribir el micro-framework**

`src/shared/TestKit.luau`:

```lua
--!strict
--[[
	TestKit.luau — micro-framework de pruebas.

	Luau no corre fuera de Roblox, así que las pruebas se ejecutan DENTRO de Studio
	(por MCP) contra los módulos puros de esta carpeta. No hace falta nada más
	sofisticado: sin dependencias, sin instalación y el informe cabe en una pantalla.

	Uso desde una suite:

		return function(kit)
			kit.eq("dos mas dos", 2 + 2, 4)
		end
]]

export type Case = { name: string, ok: boolean, detail: string }

export type Kit = {
	suite: string,
	cases: { Case },
	eq: (name: string, actual: any, expected: any) -> (),
	near: (name: string, actual: number, expected: number, tolerance: number?) -> (),
	truthy: (name: string, value: any) -> (),
	falsy: (name: string, value: any) -> (),
	errors: (name: string, fn: () -> ()) -> (),
}

local TestKit = {}

function TestKit.new(suite: string): Kit
	local cases: { Case } = {}

	local function record(name: string, ok: boolean, detail: string)
		table.insert(cases, { name = name, ok = ok, detail = detail })
	end

	local kit: Kit
	kit = {
		suite = suite,
		cases = cases,

		eq = function(name, actual, expected)
			record(
				name,
				actual == expected,
				string.format("esperado <%s>, obtenido <%s>", tostring(expected), tostring(actual))
			)
		end,

		-- Para números con decimales: comparar con == es pedir un falso negativo.
		near = function(name, actual, expected, tolerance)
			local tol = tolerance or 0.001
			record(
				name,
				math.abs(actual - expected) <= tol,
				string.format("esperado %.4f +-%.4f, obtenido %.4f", expected, tol, actual)
			)
		end,

		truthy = function(name, value)
			record(name, value ~= nil and value ~= false, "esperado verdadero, obtenido " .. tostring(value))
		end,

		falsy = function(name, value)
			record(name, value == nil or value == false, "esperado falso, obtenido " .. tostring(value))
		end,

		-- Comprobar que algo REVIENTA es una prueba de primera: así se verifica
		-- que el servidor rechaza la basura que le manda un exploit.
		errors = function(name, fn)
			local ok = pcall(fn)
			record(name, not ok, "se esperaba un error y no lo hubo")
		end,
	}

	return kit
end

return TestKit
```

- [ ] **Paso 3: escribir el ejecutor**

`src/shared/TestRunner.luau`:

```lua
--!strict
--[[
	TestRunner.luau — recorre shared/tests, ejecuta cada suite y devuelve un informe.

	Se lanza por MCP con:
		return require(game.ReplicatedStorage.Shared.TestRunner).run()

	Una suite que revienta al cargarse cuenta como fallo en vez de tumbar la tanda:
	interesa ver TODOS los rojos de una pasada, no el primero.
]]

local TestKit = require(script.Parent.TestKit)

local TestRunner = {}

function TestRunner.run(): string
	local folder = script.Parent:FindFirstChild("tests")
	if not folder then
		return "FALLOS: 1 (no existe la carpeta shared/tests)"
	end

	local lines: { string } = {}
	local total, failed = 0, 0

	local modules = folder:GetChildren()
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)

	for _, module in modules do
		if not module:IsA("ModuleScript") then
			continue
		end

		local kit = TestKit.new(module.Name)
		local ok, err = pcall(function()
			local suite = require(module) :: (TestKit.Kit) -> ()
			suite(kit)
		end)

		if not ok then
			total += 1
			failed += 1
			table.insert(lines, string.format("[X] %s :: la suite reventó: %s", module.Name, tostring(err)))
			continue
		end

		for _, case in kit.cases do
			total += 1
			if case.ok then
				table.insert(lines, string.format("[ok] %s :: %s", module.Name, case.name))
			else
				failed += 1
				table.insert(lines, string.format("[X] %s :: %s -- %s", module.Name, case.name, case.detail))
			end
		end
	end

	local resumen = if failed == 0
		then string.format("OK (%d pruebas)", total)
		else string.format("FALLOS: %d de %d", failed, total)

	table.insert(lines, "")
	table.insert(lines, resumen)
	return table.concat(lines, "\n")
end

return TestRunner
```

- [ ] **Paso 4: escribir una suite que falla a propósito**

`src/shared/tests/Sanity.spec.luau`:

```lua
--!strict
-- Suite de cordura: comprueba que el propio ciclo de pruebas funciona.
-- El caso "esto debe fallar" se corrige en el paso siguiente; existe para
-- ver un rojo antes de fiarnos de un verde.

return function(kit)
	kit.eq("el runner encuentra la suite", 1, 1)
	kit.eq("esto debe fallar", 1, 2)
end
```

- [ ] **Paso 5: arrancar Rojo y conectar Studio**

```powershell
cd C:\Users\Nitropc\Desktop\IDEAS\roblox\contrabando
..\..\tools\rojo.exe serve
```

En Studio: pestaña Plugins → Rojo → Connect. Comprobar por MCP que los módulos llegaron:

`execute_luau` (datamodel `Edit`):
```lua
return game.ReplicatedStorage.Shared:FindFirstChild("TestRunner") ~= nil
```
Esperado: `true`.

- [ ] **Paso 6: ejecutar las pruebas y ver el rojo**

`execute_luau` (datamodel `Edit`):
```lua
return require(game.ReplicatedStorage.Shared.TestRunner).run()
```
Esperado: informe con `[X] Sanity.spec :: esto debe fallar -- esperado <2>, obtenido <1>`
y última línea `FALLOS: 1 de 2`.

**Si aquí sale verde, el ciclo de pruebas no está midiendo nada.** Parar y arreglarlo antes
de seguir: un framework que no sabe fallar es peor que no tener framework.

- [ ] **Paso 7: corregir la suite de cordura**

```lua
--!strict
-- Suite de cordura: comprueba que el propio ciclo de pruebas funciona.

return function(kit)
	kit.eq("el runner encuentra la suite", 1, 1)
	kit.near("near tolera decimales", 0.1 + 0.2, 0.3)
	kit.truthy("truthy acepta valores", "algo")
	kit.falsy("falsy acepta nil", nil)
	kit.errors("errors detecta un fallo", function()
		error("a propósito")
	end)
end
```

- [ ] **Paso 8: ejecutar las pruebas y ver el verde**

Mismo `execute_luau` del paso 6. Esperado: última línea `OK (5 pruebas)`.

- [ ] **Paso 9: escribir el README**

`roblox/games/contrabando/README.md`:

```markdown
# Contrabando — prototipo

Implementación de [`DISENO.md`](DISENO.md). Mide una sola
cosa: si transportar carga entretiene, y si la intercepción da tensión en vez de rabia.

## Arrancar

```powershell
..\..\tools\rojo.exe serve      # y Connect desde el plugin de Rojo en Studio
```

## Probar

Toda la lógica de reglas vive en `src/shared/` como módulos puros y se prueba dentro de
Studio. Con Rojo conectado, ejecutar en la consola de Studio (o por MCP):

```lua
print(require(game.ReplicatedStorage.Shared.TestRunner).run())
```

## Verificación mecánica

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

Ninguna de las dos garantiza que el juego funcione: el peor fallo del piloto compilaba
perfectamente. Probar siempre dentro de Studio.
```

- [ ] **Paso 10: verificación mecánica y commit**

```powershell
cd C:\Users\Nitropc\Desktop\IDEAS\roblox\contrabando
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```
Esperado: ambas con salida 0.

```bash
git add games/contrabando
git commit -m "test: andamiaje del prototipo de contrabando y ciclo de pruebas"
```

---

### Tarea 1: Constantes y economía

Primer módulo puro. Fija cuánto vale una entrega, que es el número del que cuelga todo lo
demás.

**Ficheros:**
- Crear: `src/shared/Config.luau`
- Crear: `src/shared/Economy.luau`
- Prueba: `src/shared/tests/Economy.spec.luau`

**Interfaces:**
- Consume: `TestKit` (Tarea 0).
- Produce:
  - `Config.CAJA_VALOR_BASE: number`, `Config.CAPACIDAD_A_PIE: number`,
    `Config.VELOCIDAD_BASE: number`, `Config.PENALIZACION_POR_CAJA: number`
  - `Economy.Caja = { rareza: string }`
  - `Economy.valorCaja(caja: Economy.Caja, multiplicadorRuta: number) -> number`
  - `Economy.valorEntrega(cajas: { Economy.Caja }, multiplicadorRuta: number) -> number`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Economy.spec.luau`:

```lua
--!strict
local Economy = require(script.Parent.Parent.Economy)

return function(kit)
	local comun = { rareza = "comun" }
	local marcada = { rareza = "marcada" }
	local legendaria = { rareza = "legendaria" }

	kit.eq("una comun por la verde vale la base", Economy.valorCaja(comun, 1), 10)
	kit.eq("la ruta multiplica", Economy.valorCaja(comun, 10), 100)
	kit.eq("la rareza multiplica", Economy.valorCaja(marcada, 1), 100)

	-- El caso que define el juego: rareza y ruta se COMBINAN.
	-- Una legendaria por la roja = 10 base x 135 rareza x 10 ruta.
	kit.eq("legendaria por la roja", Economy.valorCaja(legendaria, 10), 13500)

	kit.eq("una entrega suma sus cajas", Economy.valorEntrega({ comun, comun, marcada }, 3), 360)
	kit.eq("entregar nada no paga", Economy.valorEntrega({}, 10), 0)

	-- Un exploit que invente una rareza no debe cobrar: mejor reventar que pagar de más.
	kit.errors("una rareza inventada revienta", function()
		Economy.valorCaja({ rareza = "diamante" }, 1)
	end)
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Economy.spec :: la suite reventó: ...Economy is not a valid member...`

- [ ] **Paso 3: escribir Config**

`src/shared/Config.luau`:

```lua
--!strict
--[[
	Config.luau — todas las constantes del juego en un único sitio. Sin lógica.

	Las marcadas con PROTOTIPO: difieren a propósito de DISENO.md para
	poder medir en una sesión lo que en producción tardaría horas. Revertirlas antes
	de publicar.
]]

local Config = {}

-- Economía
Config.CAJA_VALOR_BASE = 10
Config.DINERO_INICIAL = 0

-- Carga a pie
Config.CAPACIDAD_A_PIE = 3
Config.VELOCIDAD_BASE = 16
Config.PENALIZACION_POR_CAJA = 1.4 -- studs/s menos por unidad de peso transportada

-- Rarezas: multiplicador de valor, peso que ocupa y probabilidad.
-- El peso de la legendaria es exactamente CAPACIDAD_A_PIE: cabe, pero te ocupa todo.
Config.RAREZAS = {
	{ id = "comun", multiplicador = 1, peso = 1, probabilidad = 0.70 }, -- PROTOTIPO: 0.90
	{ id = "marcada", multiplicador = 10, peso = 1, probabilidad = 0.20 }, -- PROTOTIPO: 0.08
	{ id = "sellada", multiplicador = 50, peso = 2, probabilidad = 0.08 }, -- PROTOTIPO: 0.018
	{ id = "legendaria", multiplicador = 135, peso = 3, probabilidad = 0.02 }, -- PROTOTIPO: 0.002
}

-- Rutas. Se definen por DISTANCIA, no por tiempo: el tiempo es consecuencia de la
-- velocidad y de lo que lleves encima.
Config.RUTAS = {
	{ id = "verde", multiplicador = 1, distancia = 600, pvp = "ninguno" },
	{ id = "ambar", multiplicador = 3, distancia = 1200, pvp = "transportistas" },
	{ id = "roja", multiplicador = 10, distancia = 2000, pvp = "libre" },
}

-- Almacén
Config.ALMACEN_RITMO = 30 -- PROTOTIPO: 180 (1 caja cada 3 min)
Config.ALMACEN_TOPE = 10

-- Intercepción
Config.ROBO_DISTANCIA = 5 -- studs
Config.ALERTA_DISTANCIA = 60 -- a esta distancia ya se avisa: "te vienen detrás"
Config.ROBO_FRACCION = 0.30
Config.MARCADO_SEGUNDOS = 60
Config.INTERCEPT_HZ = 5

-- Sonidos. Los efectos NO son decoración: son información. Que suene una alerta al
-- acercarse un perseguidor es la diferencia entre persecución y emboscada injusta.
-- Los ids se rellenan en la Tarea 11 buscándolos en la biblioteca de Roblox.
-- Un id vacío no reproduce nada y no rompe: el juego funciona igual, sólo más mudo.
-- El tipo explícito no es adorno: sin él, indexar con una clave variable
-- (Config.SONIDOS[clave]) es un error de tipo en --!strict.
Config.SONIDOS = {
	cobro = "",
	robo = "",
	alerta = "",
} :: { [string]: string }

-- Anticheat: nadie corre más que esto ni en el mejor de los casos.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40

return Config
```

- [ ] **Paso 4: escribir Economy**

`src/shared/Economy.luau`:

```lua
--!strict
--[[
	Economy.luau — cuánto paga una entrega. Módulo PURO: no toca Roblox.

	Regla central del diseño: los multiplicadores de rareza y de ruta se COMBINAN.
	De ahí sale la decisión más tensa del juego (una legendaria por la roja vale
	13.500, pero tu haz de luz se ve desde el otro extremo del mapa).
]]

local Config = require(script.Parent.Config)

export type Caja = { rareza: string }

local Economy = {}

-- Busca la definición de una rareza. Revienta si no existe: si el servidor recibe
-- una rareza inventada, pagar de más es mucho peor que cortar la operación.
function Economy.rareza(id: string)
	for _, def in Config.RAREZAS do
		if def.id == id then
			return def
		end
	end
	error("rareza desconocida: " .. tostring(id))
end

function Economy.valorCaja(caja: Caja, multiplicadorRuta: number): number
	local def = Economy.rareza(caja.rareza)
	return Config.CAJA_VALOR_BASE * def.multiplicador * multiplicadorRuta
end

function Economy.valorEntrega(cajas: { Caja }, multiplicadorRuta: number): number
	local total = 0
	for _, caja in cajas do
		total += Economy.valorCaja(caja, multiplicadorRuta)
	end
	return total
end

return Economy
```

- [ ] **Paso 5: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 6: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: constantes y calculo de valor de entrega"
```

---

### Tarea 2: Carga, peso y velocidad

Lo que hace que llevar mercancía **se note**. Es la mitad de la tensión del juego: sin
penalización visible, transportar no cuesta nada y no hay decisión que tomar.

**Ficheros:**
- Crear: `src/shared/Cargo.luau`
- Prueba: `src/shared/tests/Cargo.spec.luau`

**Interfaces:**
- Consume: `Config`, `Economy.Caja` (Tarea 1).
- Produce:
  - `Cargo.pesoTotal(cajas: { Economy.Caja }) -> number`
  - `Cargo.cabe(cajas: { Economy.Caja }, nueva: Economy.Caja, capacidad: number) -> boolean`
  - `Cargo.velocidad(cajas: { Economy.Caja }) -> number`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Cargo.spec.luau`:

```lua
--!strict
local Cargo = require(script.Parent.Parent.Cargo)
local Config = require(script.Parent.Parent.Config)

return function(kit)
	local comun = { rareza = "comun" }
	local sellada = { rareza = "sellada" }
	local legendaria = { rareza = "legendaria" }

	kit.eq("sin carga no pesa", Cargo.pesoTotal({}), 0)
	kit.eq("tres comunes pesan tres", Cargo.pesoTotal({ comun, comun, comun }), 3)
	kit.eq("una sellada pesa dos", Cargo.pesoTotal({ sellada }), 2)
	kit.eq("una legendaria pesa tres", Cargo.pesoTotal({ legendaria }), 3)

	kit.truthy("cabe una comun con el zurron vacio", Cargo.cabe({}, comun, Config.CAPACIDAD_A_PIE))
	kit.truthy("la legendaria cabe justa a pie", Cargo.cabe({}, legendaria, Config.CAPACIDAD_A_PIE))
	kit.falsy(
		"pero no cabe nada mas con ella",
		Cargo.cabe({ legendaria }, comun, Config.CAPACIDAD_A_PIE)
	)
	kit.falsy(
		"ni una comun cuando ya llevas tres",
		Cargo.cabe({ comun, comun, comun }, comun, Config.CAPACIDAD_A_PIE)
	)

	kit.eq("vacio vas a velocidad normal", Cargo.velocidad({}), Config.VELOCIDAD_BASE)
	kit.near("una caja ya se nota", Cargo.velocidad({ comun }), 14.6)
	kit.near("a tope vas claramente lento", Cargo.velocidad({ comun, comun, comun }), 11.8)

	-- Innegociable: por muchas vueltas que dé el cálculo, nadie se queda clavado.
	kit.truthy("la velocidad nunca baja de 8", Cargo.velocidad({ legendaria, legendaria, legendaria }) >= 8)
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Cargo.spec :: la suite reventó: ...Cargo is not a valid member...`

- [ ] **Paso 3: escribir Cargo**

`src/shared/Cargo.luau`:

```lua
--!strict
--[[
	Cargo.luau — peso, capacidad y velocidad. Módulo PURO.

	Que la carga se NOTE es media tensión del juego. Si transportar no cuesta,
	no hay decisión: irías siempre a tope por la ruta que más pague.

	El suelo de velocidad no es un detalle: un jugador clavado en el sitio
	abandona la partida, y eso no es tensión, es un fallo de diseño.
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local VELOCIDAD_MINIMA = 8

local Cargo = {}

function Cargo.pesoTotal(cajas: { Economy.Caja }): number
	local total = 0
	for _, caja in cajas do
		total += Economy.rareza(caja.rareza).peso
	end
	return total
end

function Cargo.cabe(cajas: { Economy.Caja }, nueva: Economy.Caja, capacidad: number): boolean
	return Cargo.pesoTotal(cajas) + Economy.rareza(nueva.rareza).peso <= capacidad
end

function Cargo.velocidad(cajas: { Economy.Caja }): number
	local penalizacion = Cargo.pesoTotal(cajas) * Config.PENALIZACION_POR_CAJA
	return math.max(VELOCIDAD_MINIMA, Config.VELOCIDAD_BASE - penalizacion)
end

return Cargo
```

- [ ] **Paso 4: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 5: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: peso de la carga y penalizacion de velocidad"
```

---

### Tarea 3: El viaje — mundo, recogida y entrega

**La tarea que puede matar el proyecto.** Al terminar tiene que existir un juego que se
puede jugar solo: coger carga, notar que vas lento, llegar, cobrar. Si esto no entretiene
diez minutos, no hay nada más que construir.

**Ficheros:**
- Crear: `src/shared/Remotes.luau`
- Crear: `src/server/WorldBuilder.luau`
- Crear: `src/server/PlayerState.luau`
- Crear: `src/server/CargoService.luau`
- Crear: `src/server/Main.server.luau`
- Crear: `src/client/Main.client.luau`

**Interfaces:**
- Consume: `Config`, `Economy`, `Cargo` (Tareas 1-2).
- Produce:
  - `Remotes.event(name: string) -> RemoteEvent`; nombres `Remotes.SYNC_STATE`,
    `Remotes.PEDIR_ESTADO`, `Remotes.ENTREGAR`
  - `PlayerState.get(player: Player) -> Estado` con
    `Estado = { dinero: number, cajas: { Economy.Caja }, ruta: string?, marcadoHasta: number }`
  - `PlayerState.sync(player: Player)` — envía el estado real al cliente
  - `CargoService.start()`, `CargoService.recoger(player, caja) -> boolean`,
    `CargoService.vaciar(player) -> { Economy.Caja }`
  - `WorldBuilder.build() -> { almacen: BasePart, destino: BasePart }`

- [ ] **Paso 1: escribir Remotes**

`src/shared/Remotes.luau`:

```lua
--!strict
--[[
	Remotes.luau — el puente cliente/servidor.

	El cliente y el servidor son dos máquinas distintas: no comparten variables.
	La única forma de hablar es un RemoteEvent.

	REGLA DE ORO: el cliente miente. Un exploit llama a FireServer con lo que le dé
	la gana. El servidor no se cree NADA de lo que le llega, sólo la intención.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.SYNC_STATE = "SyncState" -- servidor -> cliente: "este es tu estado real"
Remotes.PEDIR_ESTADO = "PedirEstado" -- cliente -> servidor: "acabo de entrar, ponme al día"
Remotes.ENTREGAR = "Entregar" -- cliente -> servidor: "quiero entregar aquí"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	local folder = getFolder()

	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
```

- [ ] **Paso 2: escribir el estado del jugador**

`src/server/PlayerState.luau`:

```lua
--!strict
--[[
	PlayerState.luau — el estado real de cada jugador, en el servidor.

	Esta tabla es la ÚNICA verdad. El cliente recibe copias para dibujarlas; nunca
	al revés. Cualquier cosa que el cliente crea saber puede estar manipulada.
]]

local Players = game:GetService("Players")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

export type Estado = {
	dinero: number,
	cajas: { Economy.Caja },
	ruta: string?,
	marcadoHasta: number,
}

local estados: { [Player]: Estado } = {}

local PlayerState = {}

function PlayerState.get(player: Player): Estado
	local estado = estados[player]
	if not estado then
		estado = {
			dinero = Config.DINERO_INICIAL,
			cajas = {},
			ruta = nil,
			marcadoHasta = 0,
		}
		estados[player] = estado
	end
	return estado
end

function PlayerState.sync(player: Player)
	local estado = PlayerState.get(player)
	Remotes.event(Remotes.SYNC_STATE):FireClient(player, {
		dinero = estado.dinero,
		cajas = estado.cajas,
		ruta = estado.ruta,
		marcadoHasta = estado.marcadoHasta,
	})
end

function PlayerState.forEach(fn: (Player, Estado) -> ())
	for player, estado in estados do
		if player.Parent then
			fn(player, estado)
		end
	end
end

function PlayerState.start()
	Players.PlayerRemoving:Connect(function(player)
		estados[player] = nil
	end)

	-- El cliente pide su estado cuando su interfaz ya existe: si se lo mandáramos
	-- antes, llegaría a un cliente que aún no sabe dibujarlo.
	Remotes.event(Remotes.PEDIR_ESTADO).OnServerEvent:Connect(function(player)
		PlayerState.sync(player)
	end)
end

return PlayerState
```

- [ ] **Paso 3: escribir el mundo**

`src/server/WorldBuilder.luau`:

```lua
--!strict
--[[
	WorldBuilder.luau — el mapa por código.

	Cubos de colores a propósito. El arte bonito CONTAMINA la medición: si el
	prototipo es atractivo, cuando alguien aguante diez minutos no sabremos si fue
	por el bucle o por lo bonito. Y el bucle es lo único que estamos midiendo.

	Geometría: el almacén en el origen y una carretera recta hacia +X. Los destinos
	se colocan a la distancia de cada ruta (Config.RUTAS).
]]

local Config = require(game.ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local function part(nombre: string, tamano: Vector3, posicion: Vector3, color: Color3, padre: Instance): Part
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.Position = posicion
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = padre
	return p
end

function WorldBuilder.build(): { almacen: BasePart, destino: BasePart }
	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	-- Carretera larga: 2.400 studs cubren de sobra la ruta roja (2.000).
	part("Carretera", Vector3.new(2600, 1, 60), Vector3.new(1200, 0, 0), Color3.fromRGB(70, 70, 75), mundo)

	local almacen =
		part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Color3.fromRGB(120, 100, 60), mundo)

	-- En esta tarea sólo hay un destino, el de la ruta verde. La Tarea 6 añade el resto.
	local verde = Config.RUTAS[1]
	local destino = part(
		"Destino_verde",
		Vector3.new(40, 2, 40),
		Vector3.new(verde.distancia, 1, 0),
		Color3.fromRGB(60, 140, 70),
		mundo
	)
	destino:SetAttribute("ruta", verde.id)

	return { almacen = almacen, destino = destino }
end

return WorldBuilder
```

- [ ] **Paso 4: escribir el servicio de carga**

`src/server/CargoService.luau`:

```lua
--!strict
--[[
	CargoService.luau — recoger cajas, notar el peso y entregar.

	Todo lo que decide se calcula aquí, en el servidor. El cliente pide "quiero
	entregar" y el servidor comprueba que de verdad está donde dice estar: esa
	comprobación es lo que impide teletransportarse al destino y cobrar.
]]

local Players = game:GetService("Players")

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)

local DISTANCIA_ENTREGA = 30 -- studs de margen alrededor del destino

local CargoService = {}
local destinos: { BasePart } = {}

local function aplicarVelocidad(player: Player)
	local estado = PlayerState.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Cargo.velocidad(estado.cajas)
	end
end

function CargoService.recoger(player: Player, caja: Economy.Caja): boolean
	local estado = PlayerState.get(player)
	if not Cargo.cabe(estado.cajas, caja, Config.CAPACIDAD_A_PIE) then
		return false
	end
	table.insert(estado.cajas, caja)
	aplicarVelocidad(player)
	PlayerState.sync(player)
	return true
end

function CargoService.vaciar(player: Player): { Economy.Caja }
	local estado = PlayerState.get(player)
	local cajas = estado.cajas
	estado.cajas = {}
	aplicarVelocidad(player)
	PlayerState.sync(player)
	return cajas
end

function CargoService.aplicarVelocidad(player: Player)
	aplicarVelocidad(player)
end

-- Punto de entrega. En esta tarea el multiplicador es siempre el de la verde;
-- la Tarea 6 lo sustituye por el de la ruta elegida.
-- Va como función pública (no local) para poder probarla desde el servidor sin
-- pasar por el remote.
function CargoService.entregar(player: Player)
	local estado = PlayerState.get(player)
	if #estado.cajas == 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, destino in destinos do
		if (root.Position - destino.Position).Magnitude <= DISTANCIA_ENTREGA then
			local cajas = CargoService.vaciar(player)
			estado.dinero += Economy.valorEntrega(cajas, Config.RUTAS[1].multiplicador)
			PlayerState.sync(player)
			return
		end
	end
	-- Si no está cerca de ningún destino, no pasa nada: no se cobra y no se avisa.
end

function CargoService.registrarDestino(destino: BasePart)
	table.insert(destinos, destino)
end

function CargoService.start()
	Remotes.event(Remotes.ENTREGAR).OnServerEvent:Connect(CargoService.entregar)

	-- Al reaparecer, la velocidad vuelve al valor por defecto de Roblox:
	-- hay que reimponer la que corresponde a lo que lleva encima.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			aplicarVelocidad(player)
		end)
	end)
end

return CargoService
```

- [ ] **Paso 5: escribir el punto de entrada del servidor**

`src/server/Main.server.luau`:

```lua
--!strict
--[[
	Main.server.luau — arranque.

	Dos trampas de Roblox ya pagadas en el piloto, y las dos están resueltas aquí:

	1. El personaje aparece ANTES de que el código construya el mundo, se cae al
	   vacío y Roblox lo destruye a -500 studs. Por eso CharacterAutoLoads = false
	   hasta que hay suelo.
	2. Un require que falla se propaga y mata el script entero, dejando el juego sin
	   mapa y sin ninguna pista del motivo. Por eso todos van dentro de pcall.
]]

local Players = game:GetService("Players")

Players.CharacterAutoLoads = false

local function safeRequire(nombre: string): any
	local ok, resultado = pcall(function()
		return require(script.Parent:WaitForChild(nombre, 10))
	end)
	if not ok then
		warn("[Contrabando] no se pudo cargar " .. nombre .. ": " .. tostring(resultado))
		return nil
	end
	return resultado
end

local function safeStart(nombre: string, modulo: any): boolean
	if not modulo then
		return false
	end
	local ok, err = pcall(function()
		modulo.start()
	end)
	if not ok then
		warn("[Contrabando] fallo al arrancar " .. nombre .. ": " .. tostring(err))
	end
	return ok
end

local WorldBuilder = safeRequire("WorldBuilder")
local PlayerState = safeRequire("PlayerState")
local CargoService = safeRequire("CargoService")

-- El mundo primero: sin suelo no puede entrar nadie.
local mundo = nil
if WorldBuilder then
	local ok, resultado = pcall(WorldBuilder.build)
	if ok then
		mundo = resultado
	else
		warn("[Contrabando] el mundo no se pudo construir: " .. tostring(resultado))
	end
end

if not mundo then
	-- Suelo de emergencia: prefiero un jugador sobre una plancha gris a un jugador
	-- cayendo al vacío sin entender nada.
	local suelo = Instance.new("Part")
	suelo.Name = "SueloDeEmergencia"
	suelo.Size = Vector3.new(400, 1, 400)
	suelo.Position = Vector3.new(0, 0, 0)
	suelo.Anchored = true
	suelo.Parent = workspace
end

safeStart("PlayerState", PlayerState)
safeStart("CargoService", CargoService)

if mundo and CargoService then
	CargoService.registrarDestino(mundo.destino)
end

local function colocar(player: Player)
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(colocar)
Players.CharacterAutoLoads = true

for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(colocar, player)
	end
end

print("[Contrabando] servidor listo")
```

- [ ] **Paso 6: escribir el arranque del cliente**

`src/client/Main.client.luau`:

```lua
--!strict
--[[
	Main.client.luau — arranque del cliente.

	El cliente NO tiene lógica de juego: pide su estado, lo guarda para dibujarlo y
	manda intenciones. La tecla E (o el botón táctil de la Tarea 4) dice "quiero
	entregar"; es el servidor quien comprueba si de verdad está en el destino.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local estado = { dinero = 0, cajas = {}, ruta = nil, marcadoHasta = 0 }

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(nuevo)
	estado = nuevo
	print(string.format("[Contrabando] dinero %d, cajas %d", estado.dinero, #estado.cajas))
end)

ContextActionService:BindAction("Entregar", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.event(Remotes.ENTREGAR):FireServer()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.E)

Remotes.event(Remotes.PEDIR_ESTADO):FireServer()
```

- [ ] **Paso 7: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```
Esperado: ambas con salida 0.

- [ ] **Paso 8: verificar en Studio que el mundo existe y no hay errores de arranque**

`start_stop_play` para entrar en modo Play. Luego `execute_luau` (datamodel `Server`):

```lua
local mundo = workspace:FindFirstChild("Mundo")
return {
	mundo = mundo ~= nil,
	almacen = mundo and mundo:FindFirstChild("Almacen") ~= nil,
	destino = mundo and mundo:FindFirstChild("Destino_verde") ~= nil,
	emergencia = workspace:FindFirstChild("SueloDeEmergencia") ~= nil,
	jugadores = #game.Players:GetPlayers(),
}
```
Esperado: `mundo`, `almacen` y `destino` en `true`; `emergencia` en **`false`** (si sale
`true`, el mundo falló y lo tapó el suelo de emergencia: leer el warn antes de seguir);
`jugadores` ≥ 1.

- [ ] **Paso 9: verificar el bucle completo actuando sobre el mundo**

`execute_luau` (datamodel `Server`). Este script hace de jugador: recoge tres cajas,
comprueba que la velocidad baja, se teletransporta al destino y entrega.

```lua
local CargoService = require(game.ServerScriptService.Server.CargoService)
local PlayerState = require(game.ServerScriptService.Server.PlayerState)

local player = game.Players:GetPlayers()[1]
local estado = PlayerState.get(player)
local root = player.Character:FindFirstChild("HumanoidRootPart")
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

local resultado = {}
resultado.velocidadInicial = humanoid.WalkSpeed

CargoService.recoger(player, { rareza = "comun" })
CargoService.recoger(player, { rareza = "comun" })
CargoService.recoger(player, { rareza = "comun" })
resultado.cajas = #estado.cajas
resultado.velocidadCargado = humanoid.WalkSpeed

-- La cuarta no debe caber.
resultado.cuartaCabe = CargoService.recoger(player, { rareza = "comun" })

root.CFrame = CFrame.new(600, 5, 0)
task.wait(0.3)
-- Se llama a la función del servicio, no al remote: FireServer desde un script de
-- servidor no llega al handler. El camino del remote se prueba jugando, en el paso 10.
CargoService.entregar(player)
task.wait(0.3)

resultado.dinero = estado.dinero
resultado.cajasTrasEntregar = #estado.cajas
resultado.velocidadFinal = humanoid.WalkSpeed
return resultado
```

Esperado: `velocidadInicial = 16`, `cajas = 3`, `velocidadCargado ≈ 11.8`,
`cuartaCabe = false`, `dinero = 30`, `cajasTrasEntregar = 0`, `velocidadFinal = 16`.

- [ ] **Paso 10: jugarlo de verdad**

Entrar en Play, recoger carga con el script del paso 9 (sin el teletransporte), **caminar**
hasta el destino y pulsar E. Confirmar tres cosas que ninguna prueba automática puede
decirte:

1. Que la ralentización **se nota** al andar.
2. Que el trayecto de 600 studs no se hace eterno.
3. Que cobrar da alguna satisfacción aunque no haya ni sonido ni interfaz.

Si el trayecto aburre ya con la ilusión de lo nuevo, **es el momento de decirlo**: el spec
dice que si el paso 1 falla no hay proyecto.

- [ ] **Paso 11: commit**

```bash
git add games/contrabando/src
git commit -m "feat: el viaje - mundo, recogida de carga y entrega"
```

---

### Tarea 4: Interfaz de carga (móvil primero)

Sin ver cuánto llevas y cuánto tienes, la decisión de ruta de la tarea siguiente no se
puede tomar con criterio.

**Ficheros:**
- Crear: `src/client/Hud.luau`
- Modificar: `src/client/Main.client.luau`

**Interfaces:**
- Consume: `Remotes.SYNC_STATE`, `Remotes.ENTREGAR` (Tarea 3).
- Produce:
  - `Hud.build() -> ()` — crea el `ScreenGui`
  - `Hud.update(estado: { dinero: number, cajas: { any } }) -> ()`
  - `Hud.aviso(texto: string, color: Color3) -> ()` — mensaje temporal centrado

- [ ] **Paso 1: escribir el HUD**

`src/client/Hud.luau`:

```lua
--!strict
--[[
	Hud.luau — interfaz mínima, móvil primero.

	Reglas que no son opcionales (aprendidas midiendo el piloto en un Galaxy A06 de
	705x338 px, donde 12 elementos quedaban fuera de sitio y el botón de cerrar la
	tienda ni siquiera se veía):

	  · tamaños en Scale con UISizeConstraint, nunca en píxeles sueltos
	  · botones de 48 px mínimo
	  · nada en las esquinas inferiores: son del joystick y del botón de salto
	  · sin emojis en TextLabel (salen como cuadrados)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local TOUCH_MIN = 48

local Hud = {}
local dineroLabel: TextLabel
local cargaLabel: TextLabel
local avisoLabel: TextLabel

function Hud.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContrabandoHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromScale(0.02, 0.03)
	panel.Size = UDim2.fromScale(0.3, 0.14)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(140, 56)
	panelSize.MaxSize = Vector2.new(280, 110)
	panelSize.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	local function linea(nombre: string): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = nombre
		label.Size = UDim2.fromScale(1, 0.5)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(235, 235, 240)
		label.TextScaled = true
		label.Font = Enum.Font.GothamMedium
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = ""
		label.Parent = panel
		return label
	end

	dineroLabel = linea("Dinero")
	cargaLabel = linea("Carga")

	-- Botón de entregar: centro-derecha, lejos del joystick y del salto.
	local entregar = Instance.new("TextButton")
	entregar.Name = "Entregar"
	entregar.AnchorPoint = Vector2.new(1, 0.5)
	entregar.Position = UDim2.fromScale(0.97, 0.5)
	entregar.Size = UDim2.fromScale(0.18, 0.12)
	entregar.BackgroundColor3 = Color3.fromRGB(60, 140, 70)
	entregar.TextColor3 = Color3.fromRGB(255, 255, 255)
	entregar.TextScaled = true
	entregar.Font = Enum.Font.GothamBold
	entregar.Text = "Entregar"
	entregar.Parent = gui

	local botonSize = Instance.new("UISizeConstraint")
	botonSize.MinSize = Vector2.new(TOUCH_MIN * 2, TOUCH_MIN)
	botonSize.MaxSize = Vector2.new(200, 90)
	botonSize.Parent = entregar

	entregar.Activated:Connect(function()
		Remotes.event(Remotes.ENTREGAR):FireServer()
	end)

	avisoLabel = Instance.new("TextLabel")
	avisoLabel.Name = "Aviso"
	avisoLabel.AnchorPoint = Vector2.new(0.5, 0)
	avisoLabel.Position = UDim2.fromScale(0.5, 0.12)
	avisoLabel.Size = UDim2.fromScale(0.6, 0.09)
	avisoLabel.BackgroundTransparency = 1
	avisoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	avisoLabel.TextScaled = true
	avisoLabel.Font = Enum.Font.GothamBold
	avisoLabel.Text = ""
	avisoLabel.Parent = gui
end

function Hud.update(estado: { dinero: number, cajas: { any } })
	if not dineroLabel then
		return
	end
	dineroLabel.Text = string.format("Dinero: %d", estado.dinero)
	cargaLabel.Text = string.format("Carga: %d cajas", #estado.cajas)
end

local avisoId = 0

function Hud.aviso(texto: string, color: Color3)
	if not avisoLabel then
		return
	end
	avisoId += 1
	local id = avisoId
	avisoLabel.Text = texto
	avisoLabel.TextColor3 = color
	task.delay(3, function()
		-- Sólo se borra si nadie ha escrito otro aviso mientras tanto.
		if avisoId == id then
			avisoLabel.Text = ""
		end
	end)
end

return Hud
```

- [ ] **Paso 2: conectar el HUD en el cliente**

Reemplazar `src/client/Main.client.luau` entero:

```lua
--!strict
--[[
	Main.client.luau — arranque del cliente.

	El cliente NO tiene lógica de juego: pide su estado, lo dibuja y manda
	intenciones. Es el servidor quien decide si esas intenciones valen.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Hud = require(script.Parent:WaitForChild("Hud"))

Hud.build()

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	Hud.update(estado)
end)

ContextActionService:BindAction("Entregar", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.event(Remotes.ENTREGAR):FireServer()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.E)

-- Se pide el estado DESPUÉS de construir la interfaz: al revés llegaría a un
-- cliente que todavía no sabe dibujarlo.
Remotes.event(Remotes.PEDIR_ESTADO):FireServer()
```

- [ ] **Paso 3: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
```

- [ ] **Paso 4: comprobar que el HUD cabe en un móvil pequeño**

Fijar el dispositivo **antes** de entrar en Play (los setters del simulador fallan en
PlayServer). Entrar en Play y ejecutar `execute_luau` (datamodel `Client`):

```lua
local gui = game.Players.LocalPlayer.PlayerGui:WaitForChild("ContrabandoHud")
local area = gui.AbsoluteSize
-- El origen del ScreenGui NO es (0,0) cuando hay insets de dispositivo: con
-- DeviceSafeInsets aparece desplazado (p. ej. (0,-58)). Las posiciones absolutas de los
-- hijos hay que medirlas RELATIVAS a él, o todo lo que esté arriba parecerá salirse.
local origen = gui.AbsolutePosition
local fuera = {}

for _, hijo in gui:GetChildren() do
	if hijo:IsA("GuiObject") then
		local pos = hijo.AbsolutePosition - origen
		local size = hijo.AbsoluteSize
		if pos.X < 0 or pos.Y < 0 or pos.X + size.X > area.X or pos.Y + size.Y > area.Y then
			table.insert(fuera, string.format("%s en %d,%d de %dx%d", hijo.Name, pos.X, pos.Y, size.X, size.Y))
		end
		if size.Y < 48 and hijo:IsA("TextButton") then
			table.insert(fuera, hijo.Name .. " mide menos de 48px de alto")
		end
	end
end

return { area = string.format("%dx%d", area.X, area.Y), problemas = fuera }
```

Esperado: `problemas` vacío.

**Dos fuentes de falsos positivos, las dos ya pagadas:** comparar contra `gui.AbsoluteSize`
y **nunca** contra `Camera.ViewportSize` (con el simulador activo no coinciden), y restar
`gui.AbsolutePosition` de la posición de cada hijo. Sin lo segundo, en la Tarea 4 salieron
dos elementos "fuera de pantalla" que estaban perfectamente colocados.

- [ ] **Paso 5: commit**

```bash
git add games/contrabando/src
git commit -m "feat: hud de carga y dinero, movil primero"
```

---

### Tarea 5: Rutas

Módulo puro con la definición de rutas y la validación de entrega. Aquí vive la decisión que
el spec llama "el corazón del juego".

**Ficheros:**
- Crear: `src/shared/Routes.luau`
- Prueba: `src/shared/tests/Routes.spec.luau`

**Interfaces:**
- Consume: `Config` (Tarea 1).
- Produce:
  - `Routes.Ruta = { id: string, multiplicador: number, distancia: number, pvp: string }`
  - `Routes.get(id: string) -> Routes.Ruta` (revienta si no existe)
  - `Routes.existe(id: string) -> boolean`
  - `Routes.todas() -> { Routes.Ruta }`
  - `Routes.entregaValida(rutaElegida: string?, rutaDelDestino: string) -> boolean`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Routes.spec.luau`:

```lua
--!strict
local Routes = require(script.Parent.Parent.Routes)

return function(kit)
	kit.eq("hay tres rutas", #Routes.todas(), 3)
	kit.eq("la verde paga x1", Routes.get("verde").multiplicador, 1)
	kit.eq("la ambar paga x3", Routes.get("ambar").multiplicador, 3)
	kit.eq("la roja paga x10", Routes.get("roja").multiplicador, 10)

	kit.eq("la verde no tiene pvp", Routes.get("verde").pvp, "ninguno")
	kit.eq("en la ambar solo roban transportistas", Routes.get("ambar").pvp, "transportistas")
	kit.eq("la roja es libre", Routes.get("roja").pvp, "libre")

	kit.truthy("la roja es la mas larga", Routes.get("roja").distancia > Routes.get("ambar").distancia)

	kit.falsy("una ruta inventada no existe", Routes.existe("dorada"))
	kit.errors("y pedirla revienta", function()
		Routes.get("dorada")
	end)

	-- El corazón del anti-exploit: cobrar la roja entregando en el destino verde
	-- (que está a 600 studs en vez de a 2.000) sería dinero gratis.
	kit.truthy("entregar donde elegiste vale", Routes.entregaValida("roja", "roja"))
	kit.falsy("entregar en otro destino no vale", Routes.entregaValida("roja", "verde"))
	kit.falsy("sin haber elegido ruta no vale", Routes.entregaValida(nil, "verde"))
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Routes.spec :: la suite reventó: ...Routes is not a valid member...`

- [ ] **Paso 3: escribir Routes**

`src/shared/Routes.luau`:

```lua
--!strict
--[[
	Routes.luau — las tres rutas y la validación de entrega. Módulo PURO.

	La decisión de ruta es el corazón del juego: cada viaje es una apuesta TUYA,
	no un castigo que te cae encima.

	entregaValida es una pieza de seguridad, no una comodidad: sin ella, elegir la
	roja (x10) y entregar en el destino verde (a 600 studs en vez de a 2.000) sería
	cobrar el premio grande por el viaje corto.
]]

local Config = require(script.Parent.Config)

export type Ruta = {
	id: string,
	multiplicador: number,
	distancia: number,
	pvp: string,
}

local Routes = {}

function Routes.todas(): { Ruta }
	return Config.RUTAS
end

function Routes.existe(id: string?): boolean
	if not id then
		return false
	end
	for _, ruta in Config.RUTAS do
		if ruta.id == id then
			return true
		end
	end
	return false
end

function Routes.get(id: string): Ruta
	for _, ruta in Config.RUTAS do
		if ruta.id == id then
			return ruta
		end
	end
	error("ruta desconocida: " .. tostring(id))
end

function Routes.entregaValida(rutaElegida: string?, rutaDelDestino: string): boolean
	return rutaElegida ~= nil and rutaElegida == rutaDelDestino
end

return Routes
```

- [ ] **Paso 4: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 5: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: definicion de rutas y validacion de entrega"
```

---

### Tarea 6: Elección de ruta en el mundo

**Ficheros:**
- Crear: `src/server/RouteService.luau`
- Crear: `src/client/RoutePicker.luau`
- Modificar: `src/server/WorldBuilder.luau` (un destino por ruta y zona de salida)
- Modificar: `src/server/CargoService.luau` (entrega con el multiplicador de la ruta elegida)
- Modificar: `src/server/Main.server.luau` (arrancar `RouteService`)
- Modificar: `src/client/Main.client.luau` (arrancar `RoutePicker`)
- Modificar: `src/shared/Remotes.luau` (remote `ELEGIR_RUTA`)

**Interfaces:**
- Consume: `Routes`, `PlayerState`, `CargoService`, `Hud` (Tareas 3-5).
- Produce:
  - `Remotes.ELEGIR_RUTA = "ElegirRuta"`
  - `RouteService.start()`
  - `RouteService.elegir(player: Player, rutaId: string) -> boolean`
  - `RoutePicker.mostrar(alElegir: (string) -> ())`, `RoutePicker.ocultar()`
  - `WorldBuilder.build() -> { almacen: BasePart, salida: BasePart, destinos: { BasePart } }`

- [ ] **Paso 1: añadir el remote**

En `src/shared/Remotes.luau`, junto a los otros nombres:

```lua
Remotes.ELEGIR_RUTA = "ElegirRuta" -- cliente -> servidor: "salgo por esta ruta"
```

- [ ] **Paso 2: escribir el servicio de rutas**

`src/server/RouteService.luau`:

```lua
--!strict
--[[
	RouteService.luau — elección de ruta y su validación.

	Cuatro comprobaciones que el servidor NO se salta, porque cada una es un
	exploit si falta:

	  1. que la ruta exista (un id inventado no cobra nada)
	  2. que lleve carga (elegir ruta sin nada encima no tiene sentido)
	  3. que esté en la salida del almacén (no se cambia de ruta a mitad de viaje,
	     que sería elegir la verde para pasar tranquilo y cambiar a roja al llegar)
	  4. que no esté ya en ruta
]]

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local PlayerState = require(script.Parent.PlayerState)

local DISTANCIA_SALIDA = 40

local RouteService = {}
local salida: BasePart? = nil

function RouteService.registrarSalida(part: BasePart)
	salida = part
end

function RouteService.elegir(player: Player, rutaId: string): boolean
	if typeof(rutaId) ~= "string" or not Routes.existe(rutaId) then
		return false
	end

	local estado = PlayerState.get(player)
	if estado.ruta ~= nil then
		return false
	end
	if #estado.cajas == 0 then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not salida then
		return false
	end
	if (root.Position - salida.Position).Magnitude > DISTANCIA_SALIDA then
		return false
	end

	estado.ruta = rutaId
	PlayerState.sync(player)
	return true
end

function RouteService.limpiar(player: Player)
	local estado = PlayerState.get(player)
	estado.ruta = nil
	PlayerState.sync(player)
end

function RouteService.start()
	Remotes.event(Remotes.ELEGIR_RUTA).OnServerEvent:Connect(function(player, rutaId)
		RouteService.elegir(player, rutaId)
	end)
end

return RouteService
```

- [ ] **Paso 3: reescribir el mundo con los tres destinos**

Sustituir la función `build` de `src/server/WorldBuilder.luau`:

```lua
function WorldBuilder.build(): { almacen: BasePart, salida: BasePart, destinos: { BasePart } }
	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	part("Carretera", Vector3.new(2600, 1, 60), Vector3.new(1200, 0, 0), Color3.fromRGB(70, 70, 75), mundo)

	local almacen =
		part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Color3.fromRGB(120, 100, 60), mundo)

	-- La salida es el único sitio donde se elige ruta. Que sea un punto físico
	-- concreto es lo que impide cambiar de ruta a mitad de viaje.
	local salida =
		part("Salida", Vector3.new(20, 2, 60), Vector3.new(45, 1, 0), Color3.fromRGB(200, 190, 120), mundo)

	local colores = {
		verde = Color3.fromRGB(60, 140, 70),
		ambar = Color3.fromRGB(200, 150, 50),
		roja = Color3.fromRGB(170, 60, 60),
	}

	local destinos: { BasePart } = {}
	for _, ruta in Config.RUTAS do
		local destino = part(
			"Destino_" .. ruta.id,
			Vector3.new(40, 2, 40),
			Vector3.new(ruta.distancia, 1, 0),
			colores[ruta.id] or Color3.fromRGB(200, 200, 200),
			mundo
		)
		destino:SetAttribute("ruta", ruta.id)
		table.insert(destinos, destino)
	end

	return { almacen = almacen, salida = salida, destinos = destinos }
end
```

- [ ] **Paso 4: entregar con el multiplicador de la ruta elegida**

En `src/server/CargoService.luau`, sustituir el cuerpo de `CargoService.entregar` y añadir
el `require` de `Routes` y de `RouteService` arriba:

```lua
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local RouteService = require(script.Parent.RouteService)
```

```lua
function CargoService.entregar(player: Player)
	local estado = PlayerState.get(player)
	if #estado.cajas == 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, destino in destinos do
		local rutaDelDestino = destino:GetAttribute("ruta")
		if
			(root.Position - destino.Position).Magnitude <= DISTANCIA_ENTREGA
			and Routes.entregaValida(estado.ruta, rutaDelDestino)
		then
			local multiplicador = Routes.get(rutaDelDestino).multiplicador
			local cajas = CargoService.vaciar(player)
			estado.dinero += Economy.valorEntrega(cajas, multiplicador)
			RouteService.limpiar(player)
			PlayerState.sync(player)
			return
		end
	end
end
```

- [ ] **Paso 5: escribir el selector de ruta**

`src/client/RoutePicker.luau`:

```lua
--!strict
--[[
	RoutePicker.luau — los tres destinos con su precio, al salir del almacén.

	Es la pantalla donde se toma la decisión central del juego, así que enseña el
	multiplicador y la distancia SIN adornos: la elección tiene que poder hacerse
	de un vistazo, no leyendo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))

local COLORES = {
	verde = Color3.fromRGB(60, 140, 70),
	ambar = Color3.fromRGB(200, 150, 50),
	roja = Color3.fromRGB(170, 60, 60),
}

local RoutePicker = {}
local gui: ScreenGui? = nil

function RoutePicker.build(alElegir: (string) -> ())
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "SelectorRuta"
	pantalla.ResetOnSpawn = false
	pantalla.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	pantalla.Enabled = false
	pantalla.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local fila = Instance.new("Frame")
	fila.AnchorPoint = Vector2.new(0.5, 0.5)
	fila.Position = UDim2.fromScale(0.5, 0.5)
	fila.Size = UDim2.fromScale(0.9, 0.34)
	fila.BackgroundTransparency = 1
	fila.Parent = pantalla

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = fila

	for _, ruta in Routes.todas() do
		local boton = Instance.new("TextButton")
		boton.Name = ruta.id
		boton.Size = UDim2.fromScale(0.3, 1)
		boton.BackgroundColor3 = COLORES[ruta.id] or Color3.fromRGB(120, 120, 120)
		boton.TextColor3 = Color3.fromRGB(255, 255, 255)
		boton.TextScaled = true
		boton.Font = Enum.Font.GothamBold
		boton.Text = string.format("%s\nx%d\n%d m", string.upper(ruta.id), ruta.multiplicador, ruta.distancia)
		boton.Parent = fila

		local size = Instance.new("UISizeConstraint")
		size.MinSize = Vector2.new(90, 96)
		size.Parent = boton

		boton.Activated:Connect(function()
			alElegir(ruta.id)
			RoutePicker.ocultar()
		end)
	end

	gui = pantalla
end

function RoutePicker.mostrar()
	if gui then
		gui.Enabled = true
	end
end

function RoutePicker.ocultar()
	if gui then
		gui.Enabled = false
	end
end

return RoutePicker
```

- [ ] **Paso 6: conectar el selector en el cliente**

En `src/client/Main.client.luau`, tras `Hud.build()`:

```lua
local RoutePicker = require(script.Parent:WaitForChild("RoutePicker"))

RoutePicker.build(function(rutaId)
	Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
end)
```

Y dentro del handler de `SYNC_STATE`, sustituir el cuerpo por:

```lua
Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	Hud.update(estado)
	-- El selector aparece cuando llevas carga y aún no has elegido por dónde vas.
	if #estado.cajas > 0 and estado.ruta == nil then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
	end
end)
```

- [ ] **Paso 7: arrancar RouteService en el servidor**

En `src/server/Main.server.luau`, junto a los otros `safeRequire` / `safeStart`:

```lua
local RouteService = safeRequire("RouteService")
```

```lua
safeStart("RouteService", RouteService)

if mundo then
	if RouteService then
		RouteService.registrarSalida(mundo.salida)
	end
	if CargoService then
		for _, destino in mundo.destinos do
			CargoService.registrarDestino(destino)
		end
	end
end
```

(Sustituye al `CargoService.registrarDestino(mundo.destino)` de la Tarea 3.)

- [ ] **Paso 8: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

- [ ] **Paso 9: intentar romperlo**

Entrar en Play y ejecutar `execute_luau` (datamodel `Server`). Cada caso es un exploit real:

```lua
local RouteService = require(game.ServerScriptService.Server.RouteService)
local CargoService = require(game.ServerScriptService.Server.CargoService)
local PlayerState = require(game.ServerScriptService.Server.PlayerState)

local player = game.Players:GetPlayers()[1]
local estado = PlayerState.get(player)
local root = player.Character:FindFirstChild("HumanoidRootPart")
local r = {}

-- Sin carga no se elige ruta.
estado.cajas, estado.ruta = {}, nil
root.CFrame = CFrame.new(45, 5, 0)
task.wait(0.2)
r.sinCarga = RouteService.elegir(player, "roja")

-- Con carga y en la salida, sí.
CargoService.recoger(player, { rareza = "comun" })
r.conCarga = RouteService.elegir(player, "roja")

-- Ya en ruta, no se cambia.
r.cambiarEnRuta = RouteService.elegir(player, "verde")

-- Ids inventados y tipos absurdos: ninguno debe pasar ni tumbar el servidor.
estado.ruta = nil
r.rutaInventada = RouteService.elegir(player, "dorada")
r.rutaNumero = RouteService.elegir(player, 42)
r.rutaTabla = RouteService.elegir(player, { id = "roja" })

-- Elegir ruta lejos de la salida.
estado.ruta = nil
root.CFrame = CFrame.new(1000, 5, 0)
task.wait(0.2)
r.lejosDeLaSalida = RouteService.elegir(player, "roja")

-- Cobrar la roja entregando en el destino verde.
root.CFrame = CFrame.new(45, 5, 0)
task.wait(0.2)
RouteService.elegir(player, "roja")
local dineroAntes = estado.dinero
root.CFrame = CFrame.new(600, 5, 0)
task.wait(0.3)
CargoService.entregar(player)
r.cobroCruzado = estado.dinero - dineroAntes

-- Entregar donde toca sí paga: 10 base x 10 ruta.
root.CFrame = CFrame.new(2000, 5, 0)
task.wait(0.3)
CargoService.entregar(player)
r.cobroLegitimo = estado.dinero - dineroAntes
r.rutaTrasEntregar = estado.ruta
return r
```

Esperado: `sinCarga=false`, `conCarga=true`, `cambiarEnRuta=false`, `rutaInventada=false`,
`rutaNumero=false`, `rutaTabla=false`, `lejosDeLaSalida=false`, **`cobroCruzado=0`**,
`cobroLegitimo=100`, `rutaTrasEntregar=nil`.

`cobroCruzado=0` es el resultado que importa: si sale 100, elegir la roja y entregar en el
destino verde estaría pagando el premio grande por el viaje corto.

- [ ] **Paso 10: jugarlo**

Entrar en Play, coger carga, ver aparecer el selector, elegir la roja y hacer los 2.000
studs andando. La pregunta a contestar: **¿la elección se siente como una apuesta tuya o
como un peaje?** Si el trayecto rojo se hace largo sin nada que lo llene, anotarlo: la
Tarea 7 (cajas raras) existe precisamente para llenarlo.

- [ ] **Paso 11: commit**

```bash
git add games/contrabando/src
git commit -m "feat: eleccion de ruta con validacion de destino"
```

---

### Tarea 7: Cajas raras

El golpe de suerte. Es la mecánica que convierte el viaje en una historia que contar y la
que fabrica los momentos PvP memorables sin obligar a nadie a pelear.

**Ficheros:**
- Crear: `src/shared/Rarity.luau`
- Prueba: `src/shared/tests/Rarity.spec.luau`
- Modificar: `src/server/CargoService.luau` (efecto visual de la legendaria)

**Interfaces:**
- Consume: `Config`, `Economy` (Tarea 1).
- Produce:
  - `Rarity.tirada(rng: Random) -> string`
  - `Rarity.def(id: string) -> { id: string, multiplicador: number, peso: number, probabilidad: number }`
  - `Rarity.color(id: string) -> Color3`
  - `Rarity.esLlamativa(id: string) -> boolean` — cierto para `sellada` y `legendaria`
  - `CargoService.marcarLegendaria(player: Player, activa: boolean)`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Rarity.spec.luau`:

```lua
--!strict
local Config = require(script.Parent.Parent.Config)
local Rarity = require(script.Parent.Parent.Rarity)

return function(kit)
	-- Las probabilidades tienen que sumar 1: si suman menos, la cola se pierde y
	-- la rareza más valiosa no sale nunca; si suman más, sale de más.
	local suma = 0
	for _, def in Config.RAREZAS do
		suma += def.probabilidad
	end
	kit.near("las probabilidades suman uno", suma, 1, 0.0001)

	-- Con semilla fija la tirada es determinista, así que se puede probar de verdad.
	local rng = Random.new(1302)
	local conteo = { comun = 0, marcada = 0, sellada = 0, legendaria = 0 }
	for _ = 1, 10000 do
		local id = Rarity.tirada(rng)
		conteo[id] = (conteo[id] or 0) + 1
	end

	kit.eq("todas las tiradas dan una rareza valida", conteo.comun + conteo.marcada + conteo.sellada + conteo.legendaria, 10000)
	kit.truthy("la comun domina", conteo.comun > conteo.marcada)
	kit.truthy("la marcada supera a la sellada", conteo.marcada > conteo.sellada)
	kit.truthy("la legendaria es la mas rara", conteo.legendaria < conteo.sellada)
	-- Con 2% esperado en 10.000 tiradas, salirse de 100-350 sería un fallo del reparto.
	kit.truthy("la legendaria sale, pero poco", conteo.legendaria > 100 and conteo.legendaria < 350)

	kit.eq("una rareza tiene su multiplicador", Rarity.def("legendaria").multiplicador, 135)
	kit.falsy("la comun no llama la atencion", Rarity.esLlamativa("comun"))
	kit.truthy("la legendaria si", Rarity.esLlamativa("legendaria"))

	kit.errors("una rareza inventada revienta", function()
		Rarity.def("diamante")
	end)
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Rarity.spec :: la suite reventó: ...Rarity is not a valid member...`

- [ ] **Paso 3: escribir Rarity**

`src/shared/Rarity.luau`:

```lua
--!strict
--[[
	Rarity.luau — la tirada de rareza. Módulo PURO salvo por Color3, que es un tipo
	de datos sin estado y no impide probarlo.

	Recibe el Random en vez de crearlo dentro: así con semilla fija la tirada es
	determinista y se puede comprobar el reparto de verdad en lugar de confiar.
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local COLORES = {
	comun = Color3.fromRGB(150, 130, 100),
	marcada = Color3.fromRGB(90, 160, 220),
	sellada = Color3.fromRGB(170, 110, 220),
	legendaria = Color3.fromRGB(255, 200, 60),
}

local Rarity = {}

-- Delega en Economy en vez de repetir la búsqueda: dos funciones que resuelven la
-- misma tabla acaban divergiendo, y la que divergiera aquí pagaría de más.
function Rarity.def(id: string)
	return Economy.rareza(id)
end

function Rarity.tirada(rng: Random): string
	local tirada = rng:NextNumber()
	local acumulado = 0
	for _, def in Config.RAREZAS do
		acumulado += def.probabilidad
		if tirada <= acumulado then
			return def.id
		end
	end
	-- Red de seguridad por si las probabilidades no suman exactamente 1 por
	-- redondeo: devolver la última es infinitamente mejor que devolver nil.
	return Config.RAREZAS[#Config.RAREZAS].id
end

function Rarity.color(id: string): Color3
	return COLORES[id] or Color3.fromRGB(200, 200, 200)
end

function Rarity.esLlamativa(id: string): boolean
	return id == "sellada" or id == "legendaria"
end

return Rarity
```

- [ ] **Paso 4: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 5: añadir el haz de luz de la legendaria**

En `src/server/CargoService.luau`, añadir el `require` de `Rarity` y esta función, y
llamarla desde `recoger` y desde `vaciar`:

```lua
local Rarity = require(game.ReplicatedStorage.Shared.Rarity)
```

```lua
-- El haz de luz no es decoración: es la mitad de la mecánica. Llevar una legendaria
-- vale 13.500 por la roja Y hace que todo el servidor sepa dónde estás y qué llevas.
-- Sin el haz, la decisión difícil desaparece y sólo queda dinero gratis.
function CargoService.marcarLegendaria(player: Player, activa: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local haz = root:FindFirstChild("HazLegendaria") :: Beam?
	if not activa then
		if haz then
			haz:Destroy()
		end
		local a0 = root:FindFirstChild("HazA0")
		local a1 = root:FindFirstChild("HazA1")
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
		return
	end

	if haz then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "HazA0"
	a0.Position = Vector3.new(0, 0, 0)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "HazA1"
	a1.Position = Vector3.new(0, 300, 0)
	a1.Parent = root

	local beam = Instance.new("Beam")
	beam.Name = "HazLegendaria"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 4
	beam.Width1 = 10
	beam.Color = ColorSequence.new(Rarity.color("legendaria"))
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = root
end

local function tieneLegendaria(cajas: { Economy.Caja }): boolean
	for _, caja in cajas do
		if caja.rareza == "legendaria" then
			return true
		end
	end
	return false
end
```

Y al final de `recoger` y de `vaciar`, antes del `return`:

```lua
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
```

- [ ] **Paso 6: generar cajas con rareza en el almacén**

Añadir en `src/server/CargoService.luau` (la Tarea 9 lo llamará desde el almacén; de momento
sirve para probar):

```lua
local rng = Random.new(os.clock() * 1000)

function CargoService.nuevaCaja(): Economy.Caja
	return { rareza = Rarity.tirada(rng) }
end
```

- [ ] **Paso 7: verificar el haz en Studio**

Entrar en Play. `execute_luau` (datamodel `Server`):

```lua
local CargoService = require(game.ServerScriptService.Server.CargoService)
local PlayerState = require(game.ServerScriptService.Server.PlayerState)

local player = game.Players:GetPlayers()[1]
local estado = PlayerState.get(player)
local root = player.Character:FindFirstChild("HumanoidRootPart")
local r = {}

estado.cajas = {}
CargoService.marcarLegendaria(player, false)
r.sinLegendaria = root:FindFirstChild("HazLegendaria") ~= nil

CargoService.recoger(player, { rareza = "legendaria" })
task.wait(0.2)
r.conLegendaria = root:FindFirstChild("HazLegendaria") ~= nil
r.pesaTodo = #estado.cajas == 1 and not CargoService.recoger(player, { rareza = "comun" })

CargoService.vaciar(player)
task.wait(0.2)
r.trasEntregar = root:FindFirstChild("HazLegendaria") ~= nil
return r
```

Esperado: `sinLegendaria=false`, `conLegendaria=true`, `pesaTodo=true`, `trasEntregar=false`.

Además, `screen_capture` con el jugador cargando una legendaria: el haz tiene que verse
desde lejos. Si no se ve, no cumple su función.

- [ ] **Paso 8: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: rarezas de caja y haz de luz de la legendaria"
```

---

### Tarea 8: Producción del almacén (lógica pura)

**Ficheros:**
- Crear: `src/shared/Warehouse.luau`
- Prueba: `src/shared/tests/Warehouse.spec.luau`

**Interfaces:**
- Consume: `Config` (Tarea 1).
- Produce:
  - `Warehouse.acumulado(guardadas: number, ultimaVisita: number, ahora: number, ritmo: number, tope: number) -> number`
  - `Warehouse.lleno(cantidad: number, tope: number) -> boolean`
  - `Warehouse.segundosParaLaSiguiente(ultimaVisita: number, ahora: number, ritmo: number) -> number`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Warehouse.spec.luau`:

```lua
--!strict
local Warehouse = require(script.Parent.Parent.Warehouse)

return function(kit)
	local RITMO, TOPE = 30, 10

	kit.eq("recien visitado no hay nada", Warehouse.acumulado(0, 1000, 1000, RITMO, TOPE), 0)
	kit.eq("a medio ritmo aun no hay caja", Warehouse.acumulado(0, 1000, 1015, RITMO, TOPE), 0)
	kit.eq("un ritmo entero da una caja", Warehouse.acumulado(0, 1000, 1030, RITMO, TOPE), 1)
	kit.eq("cinco ritmos dan cinco", Warehouse.acumulado(0, 1000, 1150, RITMO, TOPE), 5)

	-- El tope es la razón de volver: al llenarse DEJA de producir, así que no
	-- entrar es desperdiciar tiempo.
	kit.eq("el tope corta la produccion", Warehouse.acumulado(0, 1000, 100000, RITMO, TOPE), TOPE)
	kit.eq("lo ya guardado cuenta para el tope", Warehouse.acumulado(8, 1000, 100000, RITMO, TOPE), TOPE)
	kit.eq("suma sobre lo guardado", Warehouse.acumulado(3, 1000, 1090, RITMO, TOPE), 6)

	-- Dos semanas fuera y dos minutos fuera acaban igual: el tope no simula nada.
	kit.eq(
		"dos semanas equivalen al tope",
		Warehouse.acumulado(0, 0, 14 * 24 * 3600, RITMO, TOPE),
		Warehouse.acumulado(0, 0, 3600, RITMO, TOPE)
	)

	-- Un reloj que va hacia atrás (cambio de hora, dato corrupto) no puede dar negativo.
	kit.eq("el tiempo hacia atras no resta", Warehouse.acumulado(4, 2000, 1000, RITMO, TOPE), 4)

	kit.truthy("lleno cuando llega al tope", Warehouse.lleno(10, TOPE))
	kit.falsy("no lleno por debajo", Warehouse.lleno(9, TOPE))

	kit.eq("faltan 30 s justo despues de visitar", Warehouse.segundosParaLaSiguiente(1000, 1000, RITMO), 30)
	kit.eq("faltan 10 s a los veinte", Warehouse.segundosParaLaSiguiente(1000, 1020, RITMO), 10)
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Warehouse.spec :: la suite reventó: ...Warehouse is not a valid member...`

- [ ] **Paso 3: escribir Warehouse**

`src/shared/Warehouse.luau`:

```lua
--!strict
--[[
	Warehouse.luau — producción con tope. Módulo PURO.

	No simula NADA. No hay procesos en segundo plano ni temporizadores: al entrar se
	hace una resta y ya está. Da exactamente igual que el jugador estuviera fuera
	diez minutos o dos semanas, y el coste de tener mil jugadores desconectados es cero.

		cajas = min( tope, guardadas + floor( (ahora - ultimaVisita) / ritmo ) )

	El tope es lo que da motivo para volver: al llenarse deja de producir, así que no
	entrar es desperdiciar tiempo. Ampliar la capacidad alarga tu ventana de ausencia,
	de modo que la cadencia de retorno crece con el jugador en vez de agobiarle igual
	desde el primer día.
]]

local Warehouse = {}

function Warehouse.acumulado(
	guardadas: number,
	ultimaVisita: number,
	ahora: number,
	ritmo: number,
	tope: number
): number
	-- Un reloj hacia atrás (cambio de hora, dato corrupto) nunca puede quitar cajas.
	local transcurrido = math.max(0, ahora - ultimaVisita)
	local producidas = math.floor(transcurrido / ritmo)
	return math.min(tope, guardadas + producidas)
end

function Warehouse.lleno(cantidad: number, tope: number): boolean
	return cantidad >= tope
end

function Warehouse.segundosParaLaSiguiente(ultimaVisita: number, ahora: number, ritmo: number): number
	local transcurrido = math.max(0, ahora - ultimaVisita)
	return ritmo - (transcurrido % ritmo)
end

return Warehouse
```

- [ ] **Paso 4: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 5: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: produccion offline del almacen con tope"
```

---

### Tarea 9: El almacén en el mundo

**Ficheros:**
- Crear: `src/server/WarehouseService.luau`
- Modificar: `src/server/Main.server.luau` (arrancar el servicio)
- Modificar: `src/shared/Remotes.luau` (remote `RECLAMAR`)
- Modificar: `src/client/Hud.luau` (mostrar las cajas disponibles)

**Interfaces:**
- Consume: `Warehouse`, `CargoService.nuevaCaja`, `PlayerState` (Tareas 3, 7, 8).
- Produce:
  - `Remotes.RECLAMAR = "Reclamar"`
  - `WarehouseService.start()`
  - `WarehouseService.disponibles(player: Player) -> number`
  - `WarehouseService.reclamar(player: Player) -> number` (cuántas cogió de verdad)
  - `Estado` gana los campos `almacenCajas: number` y `almacenUltimaVisita: number`

- [ ] **Paso 1: añadir los campos al estado**

En `src/server/PlayerState.luau`, ampliar el tipo `Estado` y el estado inicial:

```lua
export type Estado = {
	dinero: number,
	cajas: { Economy.Caja },
	ruta: string?,
	marcadoHasta: number,
	almacenCajas: number,
	almacenUltimaVisita: number,
}
```

```lua
		estado = {
			dinero = Config.DINERO_INICIAL,
			cajas = {},
			ruta = nil,
			marcadoHasta = 0,
			almacenCajas = 3, -- las tres cajas de los primeros cinco segundos
			almacenUltimaVisita = os.time(),
		}
```

Y añadir los dos campos al `FireClient` de `PlayerState.sync`:

```lua
	Remotes.event(Remotes.SYNC_STATE):FireClient(player, {
		dinero = estado.dinero,
		cajas = estado.cajas,
		ruta = estado.ruta,
		marcadoHasta = estado.marcadoHasta,
		almacenCajas = estado.almacenCajas,
	})
```

- [ ] **Paso 2: añadir el remote**

En `src/shared/Remotes.luau`:

```lua
Remotes.RECLAMAR = "Reclamar" -- cliente -> servidor: "cojo lo que ha producido el almacén"
```

- [ ] **Paso 3: escribir el servicio del almacén**

`src/server/WarehouseService.luau`:

```lua
--!strict
--[[
	WarehouseService.luau — el almacén: produce mientras no estás y te da carga al volver.

	EL ALMACÉN NO ES ASALTABLE. NUNCA. Sólo está en juego lo que llevas encima. Sin
	esa garantía la gente abandona tras el primer mal día, y ninguna cifra de
	retención sobrevive a eso. Aquí no hay ni un remote que permita tocar el almacén
	de otro: ni siquiera existe la posibilidad de expresarlo.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Warehouse = require(game.ReplicatedStorage.Shared.Warehouse)
local CargoService = require(script.Parent.CargoService)
local PlayerState = require(script.Parent.PlayerState)

local DISTANCIA_ALMACEN = 45

local WarehouseService = {}
local almacen: BasePart? = nil

function WarehouseService.registrarAlmacen(part: BasePart)
	almacen = part
end

-- La producción se calcula al consultarla, no con un temporizador: una resta al
-- entrar cubre igual de bien diez minutos que dos semanas.
local function actualizar(player: Player): number
	local estado = PlayerState.get(player)
	local ahora = os.time()
	estado.almacenCajas =
		Warehouse.acumulado(estado.almacenCajas, estado.almacenUltimaVisita, ahora, Config.ALMACEN_RITMO, Config.ALMACEN_TOPE)
	estado.almacenUltimaVisita = ahora
	return estado.almacenCajas
end

function WarehouseService.disponibles(player: Player): number
	return actualizar(player)
end

function WarehouseService.reclamar(player: Player): number
	local estado = PlayerState.get(player)
	actualizar(player)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not almacen then
		return 0
	end
	if (root.Position - almacen.Position).Magnitude > DISTANCIA_ALMACEN then
		return 0
	end

	local cogidas = 0
	while estado.almacenCajas > 0 do
		local caja = CargoService.nuevaCaja()
		if not Cargo.cabe(estado.cajas, caja, Config.CAPACIDAD_A_PIE) then
			break
		end
		CargoService.recoger(player, caja)
		estado.almacenCajas -= 1
		cogidas += 1
	end

	PlayerState.sync(player)
	return cogidas
end

function WarehouseService.start()
	Remotes.event(Remotes.RECLAMAR).OnServerEvent:Connect(function(player)
		WarehouseService.reclamar(player)
	end)

	-- Sincroniza cada 5 s para que el contador del HUD suba solo mientras el
	-- jugador mira: ver el almacén llenarse es parte del motivo para volver.
	task.spawn(function()
		while true do
			task.wait(5)
			PlayerState.forEach(function(player)
				actualizar(player)
				PlayerState.sync(player)
			end)
		end
	end)
end

return WarehouseService
```

- [ ] **Paso 4: arrancar el servicio**

En `src/server/Main.server.luau`:

```lua
local WarehouseService = safeRequire("WarehouseService")
```

```lua
safeStart("WarehouseService", WarehouseService)
```

Y dentro del bloque `if mundo then`:

```lua
	if WarehouseService then
		WarehouseService.registrarAlmacen(mundo.almacen)
	end
```

- [ ] **Paso 5: mostrar el almacén y el botón de recoger en el HUD**

En `src/client/Hud.luau`, añadir una tercera línea en `build` (tras `cargaLabel`):

```lua
	almacenLabel = linea("Almacen")
```

Declararla arriba junto a las otras (`local almacenLabel: TextLabel`), ampliar el panel a
`UDim2.fromScale(0.3, 0.19)` con `MinSize = Vector2.new(140, 78)` y que cada línea mida
`UDim2.fromScale(1, 0.33)`.

Añadir el botón de recoger, encima del de entregar:

```lua
	local recoger = Instance.new("TextButton")
	recoger.Name = "Recoger"
	recoger.AnchorPoint = Vector2.new(1, 0.5)
	recoger.Position = UDim2.fromScale(0.97, 0.32)
	recoger.Size = UDim2.fromScale(0.18, 0.12)
	recoger.BackgroundColor3 = Color3.fromRGB(120, 100, 60)
	recoger.TextColor3 = Color3.fromRGB(255, 255, 255)
	recoger.TextScaled = true
	recoger.Font = Enum.Font.GothamBold
	recoger.Text = "Recoger"
	recoger.Parent = gui

	local recogerSize = Instance.new("UISizeConstraint")
	recogerSize.MinSize = Vector2.new(TOUCH_MIN * 2, TOUCH_MIN)
	recogerSize.MaxSize = Vector2.new(200, 90)
	recogerSize.Parent = recoger

	recoger.Activated:Connect(function()
		Remotes.event(Remotes.RECLAMAR):FireServer()
	end)
```

Y en `Hud.update`:

```lua
	almacenLabel.Text = string.format("Almacen: %d/%d", estado.almacenCajas or 0, 10)
```

- [ ] **Paso 6: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

- [ ] **Paso 7: verificar producción, tope y distancia**

Entrar en Play. `execute_luau` (datamodel `Server`):

```lua
local WarehouseService = require(game.ServerScriptService.Server.WarehouseService)
local CargoService = require(game.ServerScriptService.Server.CargoService)
local PlayerState = require(game.ServerScriptService.Server.PlayerState)

local player = game.Players:GetPlayers()[1]
local estado = PlayerState.get(player)
local root = player.Character:FindFirstChild("HumanoidRootPart")
local r = {}

-- Producción: fingir que la última visita fue hace 5 minutos.
estado.almacenCajas = 0
estado.cajas = {}
estado.almacenUltimaVisita = os.time() - 300
r.tras5min = WarehouseService.disponibles(player)

-- Tope: dos semanas no dan más que el tope.
estado.almacenCajas = 0
estado.almacenUltimaVisita = os.time() - 14 * 24 * 3600
r.trasDosSemanas = WarehouseService.disponibles(player)

-- Reclamar lejos del almacén no da nada.
root.CFrame = CFrame.new(1500, 5, 0)
task.wait(0.2)
r.reclamarLejos = WarehouseService.reclamar(player)

-- En el almacén sí, y sólo lo que quepa (capacidad 3).
root.CFrame = CFrame.new(0, 5, 0)
task.wait(0.2)
r.reclamarCerca = WarehouseService.reclamar(player)
r.cajasEncima = #estado.cajas
r.quedanEnAlmacen = estado.almacenCajas

-- Con el zurrón lleno, reclamar otra vez no coge nada.
r.reclamarLleno = WarehouseService.reclamar(player)
return r
```

Esperado: `tras5min=10` (con ritmo 30 s el tope se alcanza en 5 min), `trasDosSemanas=10`,
`reclamarLejos=0`, `reclamarCerca` entre 1 y 3 (depende de las rarezas que salgan:
una legendaria ocupa las tres unidades ella sola), `cajasEncima` ≥ 1,
`quedanEnAlmacen = 10 - reclamarCerca`, `reclamarLleno=0`.

- [ ] **Paso 8: commit**

```bash
git add games/contrabando/src
git commit -m "feat: almacen con produccion offline y reclamo de carga"
```

---

### Tarea 10: Reglas de intercepción (lógica pura)

Toda la lógica del robo, aislada y probada, antes de tocar el mundo. Es el sistema más
fácil de romper y el que más rabia da si se rompe.

**Ficheros:**
- Crear: `src/shared/Intercept.luau`
- Prueba: `src/shared/tests/Intercept.spec.luau`

**Interfaces:**
- Consume: `Config`, `Economy`, `Routes` (Tareas 1, 5).
- Produce:
  - `Intercept.Perfil = { cajas: { Economy.Caja }, ruta: string?, marcadoHasta: number, velocidad: number }`
  - `Intercept.puedeRobar(atacante: Perfil, victima: Perfil, distancia: number, ahora: number) -> (boolean, string)`
  - `Intercept.reparto(cajas: { Economy.Caja }, fraccion: number) -> ({ Economy.Caja }, { Economy.Caja })`
    (devuelve `robadas, restantes`)
  - `Intercept.esAmenaza(atacante: Perfil, victima: Perfil, distancia: number, ahora: number) -> boolean`

- [ ] **Paso 1: escribir la prueba que falla**

`src/shared/tests/Intercept.spec.luau`:

```lua
--!strict
local Config = require(script.Parent.Parent.Config)
local Intercept = require(script.Parent.Parent.Intercept)

return function(kit)
	local AHORA = 1000
	local comun = { rareza = "comun" }

	local function perfil(ruta, cajas, marcadoHasta, velocidad)
		return {
			cajas = cajas or {},
			ruta = ruta,
			marcadoHasta = marcadoHasta or 0,
			velocidad = velocidad or 16,
		}
	end

	-- Ruta verde: aquí no roba nadie. Es la promesa que hace jugable el juego en
	-- solitario, y romperla es romper el diseño entero.
	local ok, motivo = Intercept.puedeRobar(perfil("verde", { comun }), perfil("verde", { comun }), 3, AHORA)
	kit.falsy("en la verde no se roba", ok)
	kit.eq("y se dice por que", motivo, "ruta_sin_pvp")

	-- Ruta ámbar: sólo roba quien también arriesga algo.
	kit.truthy(
		"en la ambar roba quien lleva carga",
		Intercept.puedeRobar(perfil("ambar", { comun }), perfil("ambar", { comun }), 3, AHORA)
	)
	local okVacio, motivoVacio =
		Intercept.puedeRobar(perfil("ambar", {}), perfil("ambar", { comun }), 3, AHORA)
	kit.falsy("en la ambar no se caza de vacio", okVacio)
	kit.eq("y se dice por que", motivoVacio, "cazador_sin_carga")

	-- Ruta roja: cualquiera, incluso saliendo del almacén sin nada, sólo a por ti.
	kit.truthy(
		"en la roja caza cualquiera",
		Intercept.puedeRobar(perfil("roja", {}), perfil("roja", { comun }), 3, AHORA)
	)

	-- La víctima tiene que llevar algo.
	local okSinBotin = Intercept.puedeRobar(perfil("roja", { comun }), perfil("roja", {}), 3, AHORA)
	kit.falsy("no se roba a quien va vacio", okSinBotin)

	-- Distancia.
	kit.falsy(
		"de lejos no se alcanza",
		Intercept.puedeRobar(perfil("roja", {}), perfil("roja", { comun }), 30, AHORA)
	)

	-- Marcado: 60 s sin poder volver a robar. Sin esto, el ladrón encadena robos.
	local okMarcado, motivoMarcado =
		Intercept.puedeRobar(perfil("roja", {}, AHORA + 30), perfil("roja", { comun }), 3, AHORA)
	kit.falsy("un ladron marcado no roba", okMarcado)
	kit.eq("y se dice por que", motivoMarcado, "marcado")
	kit.truthy(
		"pero al expirar la marca vuelve a poder",
		Intercept.puedeRobar(perfil("roja", {}, AHORA - 1), perfil("roja", { comun }), 3, AHORA)
	)

	-- Velocidad imposible: se invalida el robo en vez de expulsar. Más suave con el
	-- lag y con las caídas, y quita el beneficio igual.
	local okVeloz, motivoVeloz = Intercept.puedeRobar(
		perfil("roja", {}, 0, Config.VELOCIDAD_MAXIMA_PLAUSIBLE + 20),
		perfil("roja", { comun }),
		3,
		AHORA
	)
	kit.falsy("velocidad imposible invalida el robo", okVeloz)
	kit.eq("y se dice por que", motivoVeloz, "velocidad_imposible")

	-- La víctima tiene que estar en ruta: nadie roba dentro del almacén.
	kit.falsy(
		"a quien no esta en ruta no se le roba",
		Intercept.puedeRobar(perfil("roja", { comun }), perfil(nil, { comun }), 3, AHORA)
	)

	-- Reparto: 30% redondeando hacia arriba, para que robar una sola caja sirva
	-- de algo. Y nunca se lleva todo: quedarse a cero es lo que hace abandonar.
	local robadas, restantes = Intercept.reparto({ comun, comun, comun, comun }, 0.30)
	kit.eq("de cuatro se lleva dos", #robadas, 2)
	kit.eq("y deja dos", #restantes, 2)

	local unaRobada, unaRestante = Intercept.reparto({ comun }, 0.30)
	kit.eq("de una se lleva una", #unaRobada, 1)
	kit.eq("y no queda nada", #unaRestante, 0)

	local ningunaRobada = Intercept.reparto({}, 0.30)
	kit.eq("de nada no se lleva nada", #ningunaRobada, 0)

	-- Alerta de proximidad. Usa EXACTAMENTE las mismas reglas que el robo: si alguien
	-- no puede robarte, avisar de que se acerca sería asustar por nada.
	kit.truthy(
		"en la roja se avisa de quien se acerca",
		Intercept.esAmenaza(perfil("roja", {}), perfil("roja", { comun }), 40, AHORA)
	)
	kit.falsy(
		"en la verde no se avisa: alli nadie roba",
		Intercept.esAmenaza(perfil("verde", { comun }), perfil("verde", { comun }), 40, AHORA)
	)
	kit.falsy(
		"en la ambar no asusta un cazador vacio",
		Intercept.esAmenaza(perfil("ambar", {}), perfil("ambar", { comun }), 40, AHORA)
	)
	kit.falsy(
		"desde muy lejos no se avisa",
		Intercept.esAmenaza(perfil("roja", {}), perfil("roja", { comun }), 500, AHORA)
	)
end
```

- [ ] **Paso 2: ejecutar y ver el rojo**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `[X] Intercept.spec :: la suite reventó: ...Intercept is not a valid member...`

- [ ] **Paso 3: escribir Intercept**

`src/shared/Intercept.luau`:

```lua
--!strict
--[[
	Intercept.luau — las reglas del robo. Módulo PURO.

	Devuelve además un MOTIVO junto al veredicto: cuando alguien reporte que "le
	robaron y no debería", el motivo dice exactamente qué regla se aplicó. Sin eso,
	depurar un sistema que ocurre entre dos jugadores en movimiento es adivinar.

	Reglas por ruta:
	  · verde  -> nadie roba. Es la promesa que hace jugable el juego en solitario
	  · ambar  -> sólo roba quien TAMBIÉN lleva carga: el cazador debe arriesgar
	  · roja   -> cualquiera, incluso alguien que salga del almacén vacío sólo a por ti
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Routes = require(script.Parent.Routes)

export type Perfil = {
	cajas: { Economy.Caja },
	ruta: string?,
	marcadoHasta: number,
	velocidad: number,
}

local Intercept = {}

function Intercept.puedeRobar(
	atacante: Perfil,
	victima: Perfil,
	distancia: number,
	ahora: number
): (boolean, string)
	if distancia > Config.ROBO_DISTANCIA then
		return false, "lejos"
	end
	if #victima.cajas == 0 then
		return false, "victima_sin_carga"
	end
	if victima.ruta == nil or not Routes.existe(victima.ruta) then
		return false, "victima_no_en_ruta"
	end
	if atacante.marcadoHasta > ahora then
		return false, "marcado"
	end
	-- Ante una anomalía se invalida el robo en vez de expulsar: más suave con los
	-- falsos positivos (lag, caídas del servidor) y le quita el beneficio igual.
	if atacante.velocidad > Config.VELOCIDAD_MAXIMA_PLAUSIBLE then
		return false, "velocidad_imposible"
	end

	local pvp = Routes.get(victima.ruta).pvp
	if pvp == "ninguno" then
		return false, "ruta_sin_pvp"
	end
	if pvp == "transportistas" and #atacante.cajas == 0 then
		return false, "cazador_sin_carga"
	end

	return true, "ok"
end

-- Redondea hacia ARRIBA para que robar a alguien con una sola caja sirva de algo,
-- pero nunca se lleva todo el botín de un zurrón grande: quedarse a cero es
-- exactamente lo que hace abandonar el juego.
function Intercept.reparto(
	cajas: { Economy.Caja },
	fraccion: number
): ({ Economy.Caja }, { Economy.Caja })
	local cuantas = math.ceil(#cajas * fraccion)
	local robadas: { Economy.Caja } = {}
	local restantes: { Economy.Caja } = {}

	for i, caja in cajas do
		if i <= cuantas then
			table.insert(robadas, caja)
		else
			table.insert(restantes, caja)
		end
	end

	return robadas, restantes
end

-- ¿Hay que avisar a la víctima de que este jugador se le acerca? Se resuelve con las
-- MISMAS reglas del robo, pasando distancia 0 para saltarse sólo el filtro de
-- alcance: si alguien no podría robarte, avisar de que viene sería asustar por nada.
function Intercept.esAmenaza(atacante: Perfil, victima: Perfil, distancia: number, ahora: number): boolean
	if distancia > Config.ALERTA_DISTANCIA then
		return false
	end
	local puede = Intercept.puedeRobar(atacante, victima, 0, ahora)
	return puede
end

return Intercept
```

- [ ] **Paso 4: ejecutar y ver el verde**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: última línea `OK`, sin ningún `[X]`.

- [ ] **Paso 5: verificación mecánica y commit**

```powershell
..\..\tools\stylua.exe --check src
```

```bash
git add games/contrabando/src
git commit -m "feat: reglas de interceptacion y reparto del botin"
```

---

### Tarea 11: Intercepción en el mundo

**Ficheros:**
- Crear: `src/server/InterceptService.luau`
- Crear: `src/client/Sfx.luau`
- Modificar: `src/server/Main.server.luau` (arrancarlo)
- Modificar: `src/shared/Remotes.luau` (remotes `AVISO` y `SONIDO`)
- Modificar: `src/shared/Config.luau` (ids de sonido reales)
- Modificar: `src/client/Main.client.luau` (mostrar el aviso y reproducir el sonido)

**Interfaces:**
- Consume: `Intercept`, `PlayerState`, `CargoService` (Tareas 3, 10).
- Produce:
  - `Remotes.AVISO = "Aviso"` — servidor → cliente, `(texto: string, color: Color3)`
  - `Remotes.SONIDO = "Sonido"` — servidor → cliente, `(clave: string)`
  - `Sfx.reproducir(clave: string)`
  - `InterceptService.start()`
  - `InterceptService.tick(ahora: number)` — un ciclo de detección, expuesto para probarlo

- [ ] **Paso 1: añadir los remotes**

En `src/shared/Remotes.luau`:

```lua
Remotes.AVISO = "Aviso" -- servidor -> cliente: mensaje corto en pantalla
Remotes.SONIDO = "Sonido" -- servidor -> cliente: reproducir un efecto por su clave
```

- [ ] **Paso 2: escribir el servicio de intercepción**

`src/server/InterceptService.luau`:

```lua
--!strict
--[[
	InterceptService.luau — detección de robos, EN EL SERVIDOR.

	EL RIESGO TÉCNICO CENTRAL DEL JUEGO. En Roblox el personaje pertenece al cliente
	por diseño: un exploit puede teletransportarse, y el núcleo de este juego es una
	persecución. No se elimina; se le quita el incentivo.

	Por eso el servidor recorre él mismo a los jugadores cinco veces por segundo y
	NO EXISTE ningún remote de "he tocado a este". Esa llamada sería el primer
	exploit del juego: cualquiera podría robar a cualquiera desde el otro extremo
	del mapa sin moverse.

	Robar no es cobrar: te llevas la carga, pero ahora eres TÚ quien tiene que
	llegar cargado, lento y marcado 60 segundos. Interceptar no puede ser mejor que
	transportar, que es como degeneran estos sistemas.
]]

local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Intercept = require(game.ReplicatedStorage.Shared.Intercept)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local CargoService = require(script.Parent.CargoService)
local PlayerState = require(script.Parent.PlayerState)

local ROJO = Color3.fromRGB(220, 80, 80)
local AMBAR = Color3.fromRGB(230, 180, 70)

local InterceptService = {}

local function raiz(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function perfil(player: Player): Intercept.Perfil?
	local estado = PlayerState.get(player)
	local root = raiz(player)
	if not root then
		return nil
	end
	return {
		cajas = estado.cajas,
		ruta = estado.ruta,
		marcadoHasta = estado.marcadoHasta,
		velocidad = root.AssemblyLinearVelocity.Magnitude,
	}
end

local function avisar(player: Player, texto: string, color: Color3)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, color)
end

local function sonar(player: Player, clave: string)
	Remotes.event(Remotes.SONIDO):FireClient(player, clave)
end

-- Última vez que se alertó a cada jugador, para no repetir el aviso cinco veces por
-- segundo mientras dura la persecución: una alerta constante deja de ser información
-- y pasa a ser ruido que se ignora.
local ultimaAlerta: { [Player]: number } = {}
local ALERTA_CADA = 4

function InterceptService.tick(ahora: number)
	local jugadores = {}
	PlayerState.forEach(function(player)
		table.insert(jugadores, player)
	end)

	for _, atacante in jugadores do
		local rootAtacante = raiz(atacante)
		local perfilAtacante = perfil(atacante)
		if not rootAtacante or not perfilAtacante then
			continue
		end

		for _, victima in jugadores do
			if victima == atacante then
				continue
			end
			local rootVictima = raiz(victima)
			local perfilVictima = perfil(victima)
			if not rootVictima or not perfilVictima then
				continue
			end

			local distancia = (rootAtacante.Position - rootVictima.Position).Magnitude

			-- Aviso de persecución antes del alcance. Sin esto la carga desaparece de
			-- golpe y sin explicación, que es la diferencia exacta entre tensión y rabia.
			if Intercept.esAmenaza(perfilAtacante, perfilVictima, distancia, ahora) then
				if ahora - (ultimaAlerta[victima] or 0) >= ALERTA_CADA then
					ultimaAlerta[victima] = ahora
					avisar(victima, "Te vienen detras", ROJO)
					sonar(victima, "alerta")
				end
			end

			local puede = Intercept.puedeRobar(perfilAtacante, perfilVictima, distancia, ahora)
			if not puede then
				continue
			end

			local estadoVictima = PlayerState.get(victima)
			local estadoAtacante = PlayerState.get(atacante)

			local robadas, restantes = Intercept.reparto(estadoVictima.cajas, Config.ROBO_FRACCION)
			estadoVictima.cajas = restantes

			-- Sólo entra lo que le quepa: robar no puede saltarse la capacidad.
			local metidas = 0
			for _, caja in robadas do
				if Cargo.cabe(estadoAtacante.cajas, caja, Config.CAPACIDAD_A_PIE) then
					table.insert(estadoAtacante.cajas, caja)
					metidas += 1
				end
			end

			estadoAtacante.marcadoHasta = ahora + Config.MARCADO_SEGUNDOS

			CargoService.aplicarVelocidad(atacante)
			CargoService.aplicarVelocidad(victima)
			PlayerState.sync(atacante)
			PlayerState.sync(victima)

			-- La víctima sabe quién fue: sin eso el robo es una desaparición
			-- inexplicable, y eso es rabia, no tensión.
			avisar(victima, string.format("%s te ha robado %d cajas", atacante.DisplayName, #robadas), ROJO)
			avisar(atacante, string.format("Has robado %d cajas. Estas marcado 60 s", metidas), AMBAR)
			sonar(victima, "robo")
			sonar(atacante, "robo")

			break -- un robo por atacante y por ciclo
		end
	end
end

function InterceptService.start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		ultimaAlerta[player] = nil
	end)

	local acumulado = 0
	local intervalo = 1 / Config.INTERCEPT_HZ

	RunService.Heartbeat:Connect(function(delta)
		acumulado += delta
		if acumulado < intervalo then
			return
		end
		acumulado = 0

		local ok, err = pcall(function()
			InterceptService.tick(os.time())
		end)
		if not ok then
			warn("[Contrabando] fallo en el ciclo de intercepcion: " .. tostring(err))
		end
	end)
end

return InterceptService
```

- [ ] **Paso 3: arrancar el servicio**

En `src/server/Main.server.luau`:

```lua
local InterceptService = safeRequire("InterceptService")
```

```lua
safeStart("InterceptService", InterceptService)
```

- [ ] **Paso 4: buscar los tres efectos de sonido en la biblioteca de Roblox**

Con `mcp__Roblox_Studio__search_asset` (tipo `Audio`), buscar tres efectos cortos y libres
de uso: uno de **cobro** (moneda o caja registradora), uno de **robo** (golpe o impacto seco)
y uno de **alerta** (aviso tenso y breve, que se entienda como "alguien viene").

Anotar los tres ids y escribirlos en `Config.SONIDOS` de `src/shared/Config.luau`:

```lua
Config.SONIDOS = {
	cobro = "rbxassetid://<id del efecto de cobro>",
	robo = "rbxassetid://<id del efecto de impacto>",
	alerta = "rbxassetid://<id del efecto de aviso>",
}
```

La biblioteca de Roblox es gratis, instantánea y ya moderada — de ahí que salgan de ahí y
no de MiniMax. Límite verificado: 2.000 assets de audio cada 30 días con identidad
verificada, 100 sin verificar; muy por encima de lo que necesita el prototipo.

Si `search_asset` no devuelve nada usable, **dejar las cadenas vacías y seguir**: `Sfx` no
reproduce nada con un id vacío y el juego funciona igual. Lo que no vale es inventarse un
id: un `rbxassetid` que no existe llena la consola de errores en cada robo.

- [ ] **Paso 5: escribir el reproductor de sonido**

`src/client/Sfx.luau`:

```lua
--!strict
--[[
	Sfx.luau — efectos de sonido en el cliente.

	Los efectos NO son decoración, son información: la alerta de persecución es lo
	que convierte la intercepción en una persecución en lugar de una emboscada.

	El servidor manda una CLAVE, no un id: así cambiar un sonido es tocar Config y
	nada más, y un cliente manipulado no puede hacer sonar cosas que no existen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Sfx = {}
local cache: { [string]: Sound } = {}

function Sfx.reproducir(clave: string)
	local id = Config.SONIDOS[clave]
	if not id or id == "" then
		return -- sin id no suena nada, y no pasa nada
	end

	local sonido = cache[clave]
	if not sonido then
		sonido = Instance.new("Sound")
		sonido.Name = "Sfx_" .. clave
		sonido.SoundId = id
		sonido.Volume = 0.5
		sonido.Parent = SoundService
		cache[clave] = sonido
	end

	sonido:Play()
end

return Sfx
```

- [ ] **Paso 6: conectar aviso y sonido en el cliente**

En `src/client/Main.client.luau`, junto al handler de `SYNC_STATE`:

```lua
local Sfx = require(script.Parent:WaitForChild("Sfx"))

Remotes.event(Remotes.AVISO).OnClientEvent:Connect(function(texto, color)
	Hud.aviso(texto, color)
end)

Remotes.event(Remotes.SONIDO).OnClientEvent:Connect(function(clave)
	Sfx.reproducir(clave)
end)
```

- [ ] **Paso 7: sonar también al cobrar**

En `src/server/CargoService.luau`, dentro de `CargoService.entregar`, junto al cobro:

```lua
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
```

- [ ] **Paso 8: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

- [ ] **Paso 9: verificar el robo con dos jugadores simulados**

Entrar en Play con **dos jugadores** (Test → Clients and Servers → 2 players). `execute_luau`
(datamodel `Server`):

```lua
local InterceptService = require(game.ServerScriptService.Server.InterceptService)
local CargoService = require(game.ServerScriptService.Server.CargoService)
local PlayerState = require(game.ServerScriptService.Server.PlayerState)

local jugadores = game.Players:GetPlayers()
local ladron, victima = jugadores[1], jugadores[2]
local eLadron, eVictima = PlayerState.get(ladron), PlayerState.get(victima)
local rLadron = ladron.Character:FindFirstChild("HumanoidRootPart")
local rVictima = victima.Character:FindFirstChild("HumanoidRootPart")
local ahora = os.time()
local r = {}

local function preparar(ruta, cajasVictima, cajasLadron)
	eVictima.cajas, eVictima.ruta, eVictima.marcadoHasta = cajasVictima, ruta, 0
	eLadron.cajas, eLadron.ruta, eLadron.marcadoHasta = cajasLadron, ruta, 0
	rVictima.CFrame = CFrame.new(300, 5, 0)
	rLadron.CFrame = CFrame.new(303, 5, 0)
end

local comun = { rareza = "comun" }

-- En la verde no se roba, por muy pegado que vaya.
preparar("verde", { comun, comun, comun }, {})
InterceptService.tick(ahora)
r.verdeIntacta = #eVictima.cajas

-- En la ambar, un cazador vacío no roba.
preparar("ambar", { comun, comun, comun }, {})
InterceptService.tick(ahora)
r.ambarCazadorVacio = #eVictima.cajas

-- En la ambar, con carga propia sí.
preparar("ambar", { comun, comun, comun }, { comun })
InterceptService.tick(ahora)
r.ambarConCarga = #eVictima.cajas
r.ladronMarcado = eLadron.marcadoHasta > ahora

-- Marcado: el segundo robo seguido no pasa.
eVictima.cajas = { comun, comun, comun }
InterceptService.tick(ahora)
r.segundoRoboSeguido = #eVictima.cajas

-- De lejos no se alcanza.
preparar("roja", { comun, comun, comun }, {})
rLadron.CFrame = CFrame.new(400, 5, 0)
task.wait(0.2)
InterceptService.tick(ahora)
r.deLejos = #eVictima.cajas
return r
```

Esperado: `verdeIntacta=3`, `ambarCazadorVacio=3`, `ambarConCarga=2` (se lleva `ceil(3×0,3)=1`),
`ladronMarcado=true`, `segundoRoboSeguido=3`, `deLejos=3`.

- [ ] **Paso 10: comprobar que no existe ningún remote de robo**

`execute_luau` (datamodel `Server`):

```lua
local nombres = {}
for _, remote in game.ReplicatedStorage.Remotes:GetChildren() do
	table.insert(nombres, remote.Name)
end
return nombres
```

Esperado exactamente: `SyncState`, `PedirEstado`, `Entregar`, `ElegirRuta`, `Reclamar`,
`Aviso`, `Sonido`. **Si aparece cualquier remote que permita expresar "he robado a X", el
diseño está roto** — hay que quitarlo antes de seguir, no después.

- [ ] **Paso 11: jugarlo con dos**

Con dos clientes de prueba, cargar a uno por la ruta roja y perseguirlo con el otro. La
pregunta del spec: **¿tensión o rabia?** Anotar concretamente si perder el 30% se siente
justo, si 60 segundos de marca es mucho o poco, y sobre todo **si la alerta llega con
margen suficiente para reaccionar**: con 60 studs de aviso y una diferencia de velocidad
pequeña, puede que avise demasiado tarde para que la víctima pueda hacer algo — y una
alerta que sólo anuncia lo inevitable es peor que ninguna.

- [ ] **Paso 12: commit**

```bash
git add games/contrabando/src
git commit -m "feat: interceptacion detectada por el servidor a 5 hz"
```

---

### Tarea 12: Persistencia y telemetría

**Ficheros:**
- Crear: `src/server/Persistence.luau`
- Crear: `src/server/Telemetry.luau`
- Modificar: `src/server/Main.server.luau` (arrancar ambos)
- Modificar: `src/server/CargoService.luau` (registrar entregas)
- Modificar: `src/server/InterceptService.luau` (registrar robos)

**Interfaces:**
- Consume: `PlayerState` (Tarea 3).
- Produce:
  - `Persistence.start()`, `Persistence.cargar(player: Player)`, `Persistence.guardar(player: Player)`
  - `Telemetry.start()`, `Telemetry.evento(player: Player, nombre: string, datos: { [string]: any })`

- [ ] **Paso 1: escribir la persistencia**

`src/server/Persistence.luau`:

```lua
--!strict
--[[
	Persistence.luau — guardado en la nube.

	LA TRAMPA QUE COSTÓ TRES RONDAS DE DEPURACIÓN EN EL PILOTO:
	DataStoreService:GetDataStore() LANZA UNA EXCEPCIÓN si el place no está
	publicado. Llamarlo al cargar el módulo hace que el require reviente y mate el
	script entero: juego sin mapa, sin personaje y sin ninguna pista del motivo.

	Por eso el store se resuelve PEREZOSAMENTE y dentro de pcall. Sin place
	publicado el juego funciona igual, sólo que no guarda.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerState = require(script.Parent.PlayerState)

local NOMBRE_STORE = "ContrabandoV1"

local store: DataStore? = nil
local resuelto = false

local Persistence = {}

local function getStore(): DataStore?
	if resuelto then
		return store
	end
	resuelto = true

	local ok, resultado = pcall(function()
		return DataStoreService:GetDataStore(NOMBRE_STORE)
	end)

	if ok then
		store = resultado
	else
		warn("[Contrabando] se juega sin guardar en la nube: " .. tostring(resultado))
	end
	return store
end

function Persistence.cargar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	local ok, datos = pcall(function()
		return ds:GetAsync("jugador_" .. player.UserId)
	end)
	if not ok or type(datos) ~= "table" then
		return
	end

	local estado = PlayerState.get(player)
	estado.dinero = tonumber(datos.dinero) or estado.dinero
	estado.almacenCajas = tonumber(datos.almacenCajas) or estado.almacenCajas
	estado.almacenUltimaVisita = tonumber(datos.almacenUltimaVisita) or estado.almacenUltimaVisita
	PlayerState.sync(player)
end

function Persistence.guardar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	local estado = PlayerState.get(player)
	-- La carga que lleva encima NO se guarda a propósito: si la partida se corta a
	-- mitad de viaje, el riesgo asumido se resuelve como una pérdida. Guardarla
	-- convertiría desconectarse en un escudo perfecto contra el robo.
	local datos = {
		dinero = estado.dinero,
		almacenCajas = estado.almacenCajas,
		almacenUltimaVisita = os.time(),
	}

	local ok, err = pcall(function()
		ds:SetAsync("jugador_" .. player.UserId, datos)
	end)
	if not ok then
		warn("[Contrabando] no se pudo guardar: " .. tostring(err))
	end
end

function Persistence.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(Persistence.cargar, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Persistence.guardar(player)
	end)

	-- Guardado periódico: si el servidor cae, PlayerRemoving no llega.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				task.spawn(Persistence.guardar, player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Persistence.guardar(player)
		end
		task.wait(2)
	end)
end

return Persistence
```

- [ ] **Paso 2: escribir la telemetría**

`src/server/Telemetry.luau`:

```lua
--!strict
--[[
	Telemetry.luau — medición propia desde el primer día.

	Roblox sólo da analítica a partir de 100 jugadores diarios; por debajo vamos a
	ciegas. Y el dato más valioso no es cuánta gente entra, sino DÓNDE ABANDONA:
	si todos se van durante el primer viaje, el problema es el viaje, y ninguna
	cantidad de contenido nuevo lo arregla.
]]

local Players = game:GetService("Players")

local Telemetry = {}
local entradas: { [Player]: number } = {}

function Telemetry.evento(player: Player, nombre: string, datos: { [string]: any }?)
	local partes = { string.format("t=%d jugador=%d evento=%s", os.time(), player.UserId, nombre) }
	if datos then
		for clave, valor in datos do
			table.insert(partes, string.format("%s=%s", clave, tostring(valor)))
		end
	end
	-- De momento a la consola del servidor. Cuando haya tráfico real, este print se
	-- sustituye por un envío a un endpoint; el resto del código no se entera.
	print("[TELEMETRIA] " .. table.concat(partes, " "))
end

function Telemetry.start()
	Players.PlayerAdded:Connect(function(player)
		entradas[player] = os.time()
		Telemetry.evento(player, "entrada")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local inicio = entradas[player]
		entradas[player] = nil
		Telemetry.evento(player, "salida", {
			segundos = if inicio then os.time() - inicio else 0,
		})
	end)
end

return Telemetry
```

- [ ] **Paso 3: registrar los eventos que importan**

En `src/server/CargoService.luau`, dentro de `entregar`, justo antes del `return` del cobro:

```lua
			Telemetry.evento(player, "entrega", {
				ruta = rutaDelDestino,
				cajas = #cajas,
				valor = Economy.valorEntrega(cajas, multiplicador),
			})
```

En `src/server/RouteService.luau`, dentro de `elegir`, tras `estado.ruta = rutaId`:

```lua
	Telemetry.evento(player, "ruta_elegida", { ruta = rutaId, cajas = #estado.cajas })
```

En `src/server/InterceptService.luau`, tras los avisos:

```lua
			Telemetry.evento(atacante, "robo", { robadas = #robadas, ruta = perfilVictima.ruta })
			Telemetry.evento(victima, "robado", { perdidas = #robadas, ruta = perfilVictima.ruta })
```

Los tres ficheros necesitan el `require` arriba, junto a los demás:

```lua
local Telemetry = require(script.Parent.Telemetry)
```

- [ ] **Paso 4: arrancar ambos servicios**

En `src/server/Main.server.luau`:

```lua
local Persistence = safeRequire("Persistence")
local Telemetry = safeRequire("Telemetry")
```

```lua
safeStart("Telemetry", Telemetry)
safeStart("Persistence", Persistence)
```

- [ ] **Paso 5: verificación mecánica**

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

- [ ] **Paso 6: verificar que sin place publicado el juego arranca igual**

Ésta es **la** verificación de la tarea: es exactamente el fallo que tumbó el piloto.
Entrar en Play sin publicar y ejecutar `execute_luau` (datamodel `Server`):

```lua
local Persistence = require(game.ServerScriptService.Server.Persistence)
local player = game.Players:GetPlayers()[1]

-- Ninguna de las dos debe lanzar, publicado o no.
local okCargar = pcall(Persistence.cargar, player)
local okGuardar = pcall(Persistence.guardar, player)

return {
	mundo = workspace:FindFirstChild("Mundo") ~= nil,
	personaje = player.Character ~= nil,
	cargarNoRevienta = okCargar,
	guardarNoRevienta = okGuardar,
}
```

Esperado: los cuatro en `true`. Si `mundo` o `personaje` salen `false`, el `require` de
`Persistence` ha vuelto a matar el arranque: el store no está siendo perezoso.

- [ ] **Paso 7: commit**

```bash
git add games/contrabando/src
git commit -m "feat: persistencia perezosa y telemetria propia"
```

---

### Tarea 13: Pase de móvil y de exploits

Última tarea antes de poder medir. No añade sistemas: comprueba que lo construido aguanta
fuera del laboratorio.

**Ficheros:**
- Modificar: los que hagan falta según lo que aparezca
- Crear: `roblox/games/contrabando/VERIFICACION.md` con los resultados

**Interfaces:**
- Consume: todo lo anterior.
- Produce: `VERIFICACION.md` con la tabla de resultados y lo que quedó pendiente.

- [ ] **Paso 1: pasar toda la batería de pruebas**

`execute_luau`: `return require(game.ReplicatedStorage.Shared.TestRunner).run()`
Esperado: `OK` sin ningún `[X]`. Si hay rojos, arreglarlos antes de seguir.

- [ ] **Paso 2: verificar la interfaz en tres dispositivos**

Para cada uno de los tres (un móvil pequeño tipo Galaxy A06, una tableta y escritorio):
fijar el dispositivo **antes** de entrar en Play y ejecutar `execute_luau` (datamodel
`Client`):

```lua
local pg = game.Players.LocalPlayer.PlayerGui
local problemas = {}

for _, gui in pg:GetChildren() do
	if gui:IsA("ScreenGui") and gui.Enabled then
		local area = gui.AbsoluteSize
		-- Relativas al origen del ScreenGui, que con insets de dispositivo no es (0,0).
		local origen = gui.AbsolutePosition
		for _, hijo in gui:GetDescendants() do
			if hijo:IsA("GuiObject") and hijo.Visible then
				local pos = hijo.AbsolutePosition - origen
				local size = hijo.AbsoluteSize
				if pos.X < 0 or pos.Y < 0 or pos.X + size.X > area.X or pos.Y + size.Y > area.Y then
					table.insert(problemas, gui.Name .. "/" .. hijo.Name .. " se sale")
				end
				if hijo:IsA("TextButton") and (size.Y < 48 or size.X < 48) then
					table.insert(problemas, gui.Name .. "/" .. hijo.Name .. " es menor de 48px")
				end
			end
		end
	end
end

return problemas
```

Esperado: lista vacía en los tres. **Recordar activar el selector de ruta** (`RoutePicker`)
antes de medir, o sus botones no se comprueban: en el piloto el botón que quedaba fuera de
pantalla era justo el de una pantalla que sólo aparecía a veces.

- [ ] **Paso 3: un intento de exploit por cada remote**

`execute_luau` (datamodel `Client`) — desde el cliente, que es desde donde ataca un exploit:

```lua
local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")

-- Basura por todos los remotes. Ninguna debe tumbar el servidor ni dar nada.
for _ = 1, 50 do
	Remotes.Entregar:FireServer("basura", 999, {})
	Remotes.ElegirRuta:FireServer("dorada")
	Remotes.ElegirRuta:FireServer(nil)
	Remotes.ElegirRuta:FireServer({ id = "roja" })
	Remotes.Reclamar:FireServer(9999)
	Remotes.PedirEstado:FireServer("x")
end
task.wait(2)
return "enviado"
```

Después, `execute_luau` (datamodel `Server`):

```lua
local PlayerState = require(game.ServerScriptService.Server.PlayerState)
local player = game.Players:GetPlayers()[1]
local estado = PlayerState.get(player)
return {
	dinero = estado.dinero,
	cajas = #estado.cajas,
	ruta = estado.ruta,
	servidorVivo = workspace:FindFirstChild("Mundo") ~= nil,
}
```

Esperado: `dinero` sin cambios respecto a antes del ataque, `ruta = nil` (nunca "dorada"),
`servidorVivo = true`.

- [ ] **Paso 4: una sesión real de diez minutos**

Jugar diez minutos seguidos, en solitario, sin tocar código. Cronometrar y anotar:

- ¿en qué minuto apareció el primer momento de aburrimiento?
- ¿cuántos viajes completaste y por qué rutas?
- ¿salió alguna caja rara? ¿cambió lo que decidiste después?
- ¿volviste al almacén por interés o por obligación?

Éste es el criterio de kill del paso 1 del spec: **si no aguantas diez minutos tú mismo, hay
que rehacer el viaje antes que añadir nada**.

- [ ] **Paso 5: escribir VERIFICACION.md**

Crear `roblox/games/contrabando/VERIFICACION.md` con: fecha, resultado de la batería de pruebas,
tabla de los tres dispositivos, resultado del intento de exploits, y las notas de la sesión
de diez minutos con la conclusión — seguir, ajustar el viaje o pivotar al target A.

- [ ] **Paso 6: commit**

```bash
git add games/contrabando
git commit -m "test: verificacion en movil, exploits y sesion real"
```

---

## Qué queda fuera a propósito

Del spec, sección 6 ("no entra"): mapa grande o bonito, música, los otros vehículos (moto,
furgoneta, camión), el evento Redada, la monetización, los iconos y la miniatura, y el
nombre y la ambientación definitivos.

**Los precios rotativos** (sección 2 del spec, segundo motivo para volver) tampoco entran.
Con tres rutas y un único destino cada una, rotar precios sólo añadiría ruido a la decisión
que estamos midiendo: primero hay que saber si elegir entre riesgo fijo y conocido ya
engancha. Si la Tarea 13 sale bien, la rotación es un cambio pequeño — un multiplicador
extra por ruta que cambia cada pocos minutos, calculado en el servidor.

**La furgoneta merece una nota**, porque el spec la lista como "entra" en el prototipo: se ha
dejado fuera de este plan porque es el primer sumidero de dinero, y un sumidero sólo tiene
sentido cuando ya sabemos que la gente quiere ganar dinero. Si la Tarea 13 sale bien, la
furgoneta es la primera ampliación — capacidad 10, −10% de velocidad, 5.000 monedas — y no
necesita ningún sistema nuevo: sólo un campo `vehiculo` en el estado y que `Cargo` reciba la
capacidad en vez de leer la constante.

Cuando eso llegue, la regla innegociable sigue en pie: **la progresión va por capacidad y
acceso, nunca por potencia.** Ningún vehículo puede volver a nadie inatrapable, o el PvP
muere y las rutas rojas pasan a ser dinero gratis.
