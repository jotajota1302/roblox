# Contactos y habilidades — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el viaje deje de estar vacío: se recogen **contactos** por el camino y se gastan en **habilidades**, con la tienda en un **menú 2D**.

**Architecture:** Las reglas van en dos módulos PUROS nuevos (`Contacts`, `Skills`) con sus pruebas en la batería existente. Los servicios del servidor son pegamento: `ContactService` siembra y detecta, y tres servicios ya existentes consultan un factor de `Skills` en el punto donde ya calculan su número. El cliente solo pinta y pide.

**Tech Stack:** Luau, Rojo 7.7.0, pruebas propias (`TestKit`/`TestRunner`) ejecutadas dentro de Studio por MCP.

**Spec:** `games/contrabando/docs/specs/2026-08-18-contactos-habilidades-design.md`

## Global Constraints

- **Nadie puede volverse inalcanzable.** Ninguna habilidad da velocidad ni inmunidad. `Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40` sigue siendo el techo.
- **La lógica de reglas vive en módulos PUROS de `src/shared/`** que no tocan Roblox. Los servicios son pegamento.
- **El servidor detecta, el cliente pide.** No puede existir un remote de "he recogido esto", igual que no existe uno de "he tocado a este".
- **Todos los remotes se crean al arrancar.** Un remote que el servidor solo envía no existe hasta el primer envío, y el cliente que hace `WaitForChild` sobre él se cuelga para siempre.
- **Lo que es información va en `Heartbeat`, nunca en `RenderStepped`** (con la ventana sin foco, `RenderStepped` da cero llamadas por segundo — medido).
- **Cada pantalla del cliente se construye dentro de su `pcall`**, y el aviso de fallo sale **una vez** por sesión y por sitio.
- **Código y comentarios en español** en este proyecto (es material de aprendizaje), a diferencia del RPG.
- **Verificación de las pruebas puras** (dentro de Studio, por MCP, datamodel `Edit`):
  ```lua
  local copia = game.ReplicatedStorage.Shared:Clone()
  copia.Parent = game.ReplicatedStorage
  local r = require(copia.TestRunner).run()
  copia:Destroy()
  return r
  ```
  El clon es obligatorio: `require` cachea por instancia y repetir la tanda devolvería el informe de la vez anterior.
- **Formato:** `tools/stylua.exe --check src` debe dar 0 antes de cada commit.

### Reparto con la otra sesión — LEER ANTES DE EMPEZAR

Otra sesión tiene estos ficheros **modificados sin commitear**. **No se tocan en las tareas 1-5**:

```
src/client/Garage.luau      src/server/GarageService.luau   src/shared/Cargo.luau
src/client/Hud.luau         src/server/Ride.luau            src/shared/tests/Cargo.spec.luau
src/client/Main.client.luau src/server/CityBuilder.luau     src/server/SelfCheck.luau
```

Libres y usados por este plan: `Config.luau`, `Remotes.luau`, `Persistence.luau`, `PlayerState.luau`, `CargoService.luau`, `RouteService.luau`, `HeatService.luau`, `InterceptService.luau`, `PatrolService.luau`.

**Las tareas 6 y 7 están BLOQUEADAS** hasta que esa sesión commitee. No empezarlas antes: comprobar con `git status --short` que esos ficheros ya no salen como modificados.

---

## Estructura de ficheros

| Fichero | Responsabilidad | Estado |
|---|---|---|
| `src/shared/Config.luau` | Los números del sistema (radio, valores, costes, señuelo) | Modificar |
| `src/shared/Contacts.luau` | **Puro.** Dónde va cada contacto y cuánto vale | Crear |
| `src/shared/Skills.luau` | **Puro.** Catálogo, costes y el factor de cada habilidad | Crear |
| `src/shared/tests/Contacts.spec.luau` | Pruebas del reparto | Crear |
| `src/shared/tests/Skills.spec.luau` | Pruebas de compra y de la regla de oro | Crear |
| `src/server/ContactService.luau` | Siembra al elegir ruta, detecta en `Heartbeat`, retira al entregar | Crear |
| `src/server/PlayerState.luau` | Dos campos nuevos en `Estado` + sync | Modificar |
| `src/server/Persistence.luau` | Guardar y cargar `contactos` y `habilidades` | Modificar |
| `src/shared/Remotes.luau` | `COMPRAR_HABILIDAD`, `USAR_SENUELO` | Modificar |
| `src/server/HeatService.luau` | Camuflaje: factor sobre el radio de detección | Modificar |
| `src/server/InterceptService.luau` | Aguante: factor sobre la fracción robada | Modificar |
| `src/server/PatrolService.luau` | Señuelo: desvía el objetivo de los ladrones | Modificar |
| `src/client/Menu.luau` | Los paneles 2D | Crear (tarea bloqueada) |

---

### Task 1: Los contactos, como reglas puras

**Files:**
- Modify: `src/shared/Config.luau` (bloque nuevo al final, antes del `return Config`)
- Create: `src/shared/Contacts.luau`
- Test: `src/shared/tests/Contacts.spec.luau`

**Interfaces:**
- Consumes: `Config.ZONA_SEGURA_RADIO` (150), `Config.RUTAS` (`id`, `destino`), `Config.ALMACEN_POS`.
- Produces:
  - `export type Contacto = { pos: Vector3, valor: number, tipo: string }` (`tipo` es `"suelto"` o `"racimo"`)
  - `Contacts.sueltos(origen: Vector3, destino: Vector3, cuantos: number): { Contacto }`
  - `Contacts.racimos(origen: Vector3, destino: Vector3, peligros: { Vector3 }, cuantos: number): { Contacto }`
  - `Contacts.deRuta(rutaId: string, origen: Vector3, destino: Vector3, peligros: { Vector3 }): { Contacto }`
  - `Contacts.recogidosEnLineaRecta(contactos: { Contacto }, origen: Vector3, destino: Vector3, radio: number): number`
  - `Contacts.racha(recogidos: number): number` — studs/s extra, con tope
  - `Contacts.velocidadConRacha(base: number, recogidos: number): number` — la suma, recortada por el antitrampas

- [ ] **Step 1: Añadir los números a `Config.luau`**

Al final del fichero, justo antes del `return Config`:

```lua
-- ─────────────────────────────────────────────────────────────────────────────
-- LOS CONTACTOS: la moneda de las habilidades, que se recoge por el camino.
--
-- POR QUÉ EXISTEN. Toda la experiencia del juego se otorgaba en UNA línea
-- (CargoService, al entregar): durante los 54-100 segundos de viaje el jugador no
-- ganaba nada y sólo podía perder. El viaje era un impuesto entre dos momentos
-- buenos. Los contactos ponen algo bueno DENTRO del viaje.
--
-- No ocupan hueco del zurrón y NO SE PUEDEN ROBAR, a propósito: la economía de
-- monedas y el eje de riesgo ya están equilibrados, y una moneda paralela que no
-- los toca no puede desequilibrarlos.
Config.CONTACTO_RADIO = 10 -- studs de recogida, por proximidad: no hay que pulsar
Config.CONTACTO_VALOR_SUELTO = 1
Config.CONTACTO_VALOR_RACIMO = 5

-- Los sueltos van SOBRE el camino y dan el ritmo (algo pasa cada 3-5 segundos).
-- Los racimos van apartados, pegados a un peligro, y son la decisión: el premio
-- está donde está el riesgo. El desvío es menor que el de una guarida (70) para
-- que ir a por uno sea un rodeo y no una expedición.
Config.CONTACTO_RACIMO_DESVIO = 55

-- Cuántos por ruta. Escalan con el peligro, como todo lo demás.
Config.CONTACTOS_POR_RUTA = {
	verde = { sueltos = 6, racimos = 1 },
	ambar = { sueltos = 10, racimos = 2 },
	roja = { sueltos = 16, racimos = 3 },
}

-- LA RACHA: cada contacto recogido te acelera, y la velocidad es DEL VIAJE, no
-- tuya. La velocidad permanente está descartada desde el principio (ver la
-- cabecera de Levels.luau): chocaría con la regla de que nadie puede volverse
-- inalcanzable, y sin alcance no hay PvP.
--
-- Así se puede acelerar de verdad sin romperla: se pierde entera al entregar y al
-- ser alcanzado, y los ladrones escalan con la velocidad ACTUAL del perseguido,
-- racha incluida.
Config.RACHA_POR_CONTACTO = 0.5
Config.RACHA_MAXIMA = 4 -- el coche (34) queda en 38, con el antitrampas en 40
```

- [ ] **Step 2: Escribir la prueba que falla**

Crear `src/shared/tests/Contacts.spec.luau`:

```lua
--!strict
-- Pruebas del reparto de contactos. Lo que se comprueba aquí no es "que salgan":
-- es que quien recorre la ruta LOS ENCUENTRE. La lección de los detectores (quince
-- acabaron en azoteas y medio sistema de vigilancia era decorado sin que nada
-- reventara) vale igual aquí: si el desvío típico supera el radio de recogida, el
-- sistema no existe aunque el código esté escrito.

local Config = require(script.Parent.Parent.Config)
local Contacts = require(script.Parent.Parent.Contacts)

return function(kit)
	local origen = Vector3.new(0, 0, 0)
	local destino = Vector3.new(0, 0, 600)

	local sueltos = Contacts.sueltos(origen, destino, 6)
	kit.eq("siembra los sueltos que se le piden", #sueltos, 6)
	kit.eq("un suelto vale 1", sueltos[1].valor, Config.CONTACTO_VALOR_SUELTO)
	kit.eq("un suelto es de tipo suelto", sueltos[1].tipo, "suelto")

	-- SOBRE el camino: el que va en línea recta los pisa todos.
	local pisados = Contacts.recogidosEnLineaRecta(sueltos, origen, destino, Config.CONTACTO_RADIO)
	kit.eq("quien va en línea recta pisa todos los sueltos", pisados, 6)

	-- Ninguno dentro de la zona segura: un contacto a la puerta de casa es gratis.
	local dentro = 0
	for _, c in sueltos do
		if (c.pos - origen).Magnitude <= Config.ZONA_SEGURA_RADIO then
			dentro += 1
		end
	end
	kit.eq("ningún suelto cae dentro de la zona segura", dentro, 0)

	-- Los racimos se apartan, y por eso NO se pisan yendo recto: son un rodeo.
	local peligros = { Vector3.new(0, 0, 200), Vector3.new(0, 0, 400) }
	local racimos = Contacts.racimos(origen, destino, peligros, 2)
	kit.eq("siembra los racimos que se le piden", #racimos, 2)
	kit.eq("un racimo vale 5", racimos[1].valor, Config.CONTACTO_VALOR_RACIMO)
	kit.eq(
		"un racimo no se pisa yendo recto",
		Contacts.recogidosEnLineaRecta(racimos, origen, destino, Config.CONTACTO_RADIO),
		0
	)

	-- Pero tampoco tan lejos que ir a por él sea una expedición.
	for i, c in racimos do
		local d = (Vector3.new(c.pos.X, 0, c.pos.Z) - Vector3.new(peligros[i].X, 0, peligros[i].Z)).Magnitude
		kit.truthy("el racimo " .. i .. " está junto a su peligro (<= 60)", d <= 60)
	end

	-- Sin peligros que usar de ancla, no inventa racimos sueltos por ahí.
	kit.eq("sin peligros no hay racimos", #Contacts.racimos(origen, destino, {}, 3), 0)

	-- La ruta entera, por su id.
	local ruta = Contacts.deRuta("verde", origen, destino, peligros)
	kit.eq("la verde reparte 6 sueltos y 1 racimo", #ruta, 7)
	kit.eq("una ruta desconocida no revienta, devuelve vacío", #Contacts.deRuta("gris", origen, destino, peligros), 0)

	-- Una ruta tan corta que no cabe nada fuera de la zona segura: mejor ninguno
	-- que uno mal puesto (misma regla que Lairs).
	kit.eq("ruta demasiado corta, sin contactos", #Contacts.sueltos(origen, Vector3.new(0, 0, 120), 6), 0)

	-- LA RACHA. Acelera, tiene tope, y NUNCA deja al jugador fuera de alcance.
	kit.eq("sin recoger nada, no hay racha", Contacts.racha(0), 0)
	kit.near("cuatro contactos dan 2 studs/s", Contacts.racha(4), 2)
	kit.eq("la racha tiene tope", Contacts.racha(999), Config.RACHA_MAXIMA)
	kit.near("la racha se suma a la velocidad", Contacts.velocidadConRacha(16, 4), 18)
	kit.truthy(
		"ni el vehículo más rápido con la racha al tope pasa el antitrampas",
		Contacts.velocidadConRacha(34, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)
	kit.truthy(
		"una velocidad base absurda se recorta igual",
		Contacts.velocidadConRacha(999, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)
end
```

- [ ] **Step 3: Ejecutar y ver que falla**

En Studio, datamodel `Edit`, por MCP `execute_luau`, el bloque de "Global Constraints".
Esperado: `[X] Contacts.spec :: la suite reventó: ... Contacts is not a valid member of Shared`.

- [ ] **Step 4: Escribir `Contacts.luau`**

```lua
--!strict
--[[
	Contacts.luau — los contactos que se recogen por el camino. Módulo PURO.

	POR QUÉ EXISTE. Medido: toda la experiencia del juego se otorgaba en una sola
	línea de CargoService, al entregar. Los 54-100 segundos de viaje no daban nada
	y sólo podían quitar. Esto pone algo bueno dentro del viaje sin tocar la
	economía de monedas, que ya está equilibrada.

	DOS POBLACIONES, CON TRABAJOS DISTINTOS:

	  · los SUELTOS van sobre la calzada del corredor y dan el RITMO. Si se
	    apartaran, el jugador tendría que ir a por ellos y el viaje se convertiría
	    en recolectar en vez de repartir;
	  · los RACIMOS se apartan hacia un peligro y dan la DECISIÓN. Su desvío es
	    menor que el de una guarida (55 frente a 70) para que el rodeo sea un
	    rodeo y no una expedición.

	FIJOS Y APRENDIBLES, como los detectores y las guaridas: el reparto sale del
	trazado, no de un dado. El jugador que repite la ruta sabe dónde están.
]]

local Config = require(script.Parent.Config)

export type Contacto = { pos: Vector3, valor: number, tipo: string }

local Contacts = {}

-- El tramo útil del corredor, en fracción del trayecto. Empieza pasada la zona
-- segura y termina antes del destino, por lo mismo que en Lairs: un contacto a la
-- puerta de casa es gratis, y uno pegado a la entrega llega cuando ya no hay
-- viaje. Se mide EN STUDS, no en fracción -- una fracción dice lo mismo para una
-- ruta de 420 studs que para una de 1.400, y no es lo mismo.
local function tramo(largo: number): (number, number)
	local tMin = (Config.ZONA_SEGURA_RADIO + 40) / largo
	local tMax = 1 - 60 / largo
	return tMin, tMax
end

function Contacts.sueltos(origen: Vector3, destino: Vector3, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 then
		return salida
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	local largo = plano.Magnitude
	if largo < 1 then
		return salida
	end

	local tMin, tMax = tramo(largo)
	if tMax <= tMin then
		-- Ruta tan corta que no hay tramo donde ponerlos sin pisar la casa o el
		-- destino. Ninguno es mejor que uno mal puesto.
		return salida
	end

	for i = 1, cuantos do
		local t = tMin + (tMax - tMin) * ((i - 0.5) / cuantos)
		table.insert(salida, {
			pos = origen:Lerp(destino, t),
			valor = Config.CONTACTO_VALOR_SUELTO,
			tipo = "suelto",
		})
	end

	return salida
end

-- Un racimo por peligro, apartado hacia el lado del corredor. Sin peligros no hay
-- racimos: su razón de ser es estar junto a uno, así que uno suelto en mitad de
-- ninguna parte sería un premio sin apuesta.
function Contacts.racimos(origen: Vector3, destino: Vector3, peligros: { Vector3 }, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 or #peligros == 0 then
		return salida
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	if plano.Magnitude < 1 then
		return salida
	end
	-- Perpendicular en el plano: girar 90° es (z, -x).
	local lado = Vector3.new(plano.Z, 0, -plano.X).Unit

	for i = 1, math.min(cuantos, #peligros) do
		local ancla = peligros[i]
		local signo = if i % 2 == 1 then 1 else -1
		table.insert(salida, {
			pos = ancla + lado * (Config.CONTACTO_RACIMO_DESVIO * signo),
			valor = Config.CONTACTO_VALOR_RACIMO,
			tipo = "racimo",
		})
	end

	return salida
end

function Contacts.deRuta(rutaId: string, origen: Vector3, destino: Vector3, peligros: { Vector3 }): { Contacto }
	local cuantos = Config.CONTACTOS_POR_RUTA[rutaId]
	if not cuantos then
		return {}
	end

	local salida = Contacts.sueltos(origen, destino, cuantos.sueltos)
	for _, c in Contacts.racimos(origen, destino, peligros, cuantos.racimos) do
		table.insert(salida, c)
	end
	return salida
end

-- LA MEDIDA QUE IMPORTA: cuántos recoge de verdad quien va en línea recta.
--
-- Es la misma comprobación que Detectors.disparadosEnLineaRecta, y existe por lo
-- mismo: quince detectores acabaron en las azoteas y nada reventó. Un contacto
-- que el jugador no pisa es decorado, no sistema.
function Contacts.recogidosEnLineaRecta(
	contactos: { Contacto },
	origen: Vector3,
	destino: Vector3,
	radio: number
): number
	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	local largo = plano.Magnitude
	if largo < 1 then
		return 0
	end
	local unidad = plano.Unit

	local cuenta = 0
	for _, c in contactos do
		local rel = Vector3.new(c.pos.X - origen.X, 0, c.pos.Z - origen.Z)
		local avance = rel:Dot(unidad)
		if avance < 0 or avance > largo then
			continue
		end
		-- La desviación se mide EN EL PLANO. Medirla en 3D fue lo que hizo pasar
		-- por "83 studs de desviación" un detector cuya desviación real era 0: los
		-- 83 eran altura.
		local desvio = (rel - unidad * avance).Magnitude
		if desvio <= radio then
			cuenta += 1
		end
	end
	return cuenta
end

-- LA RACHA: lo que has acelerado por lo que llevas recogido EN ESTE VIAJE.
--
-- La velocidad permanente está descartada (Levels.luau lo dice en su cabecera):
-- chocaría con la regla de que nadie puede volverse inalcanzable, y sin alcance no
-- hay PvP. Ésta es la salida que usa el juego que lo inspiró: la velocidad es del
-- intento, no tuya -- corres, aceleras, y un paso en falso te devuelve al
-- principio. Quien la aplique la borra al entregar y al ser alcanzado.
function Contacts.racha(recogidos: number): number
	if recogidos <= 0 then
		return 0
	end
	return math.min(recogidos * Config.RACHA_POR_CONTACTO, Config.RACHA_MAXIMA)
end

-- EL RECORTE NO ES DECORATIVO: es la regla de oro escrita en un número. El
-- antitrampas expulsa a quien pase de Config.VELOCIDAD_MAXIMA_PLAUSIBLE, así que
-- la suma se queda por debajo con margen -- y de paso, una velocidad base absurda
-- (un fallo en otro sitio) no puede colarse por aquí.
function Contacts.velocidadConRacha(base: number, recogidos: number): number
	return math.min(base + Contacts.racha(recogidos), Config.VELOCIDAD_MAXIMA_PLAUSIBLE - 2)
end

return Contacts
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Mismo bloque del Step 3. Esperado: todas las líneas de `Contacts.spec` en `[ok]` y el resumen sin fallos nuevos.

- [ ] **Step 6: Formato y commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/shared/Config.luau games/contrabando/src/shared/Contacts.luau games/contrabando/src/shared/tests/Contacts.spec.luau
git commit -m "feat: los contactos, repartidos donde el jugador los pisa"
```

---

### Task 2: Las habilidades, como reglas puras

**Files:**
- Modify: `src/shared/Config.luau`
- Create: `src/shared/Skills.luau`
- Test: `src/shared/tests/Skills.spec.luau`

**Interfaces:**
- Consumes: `Config.ROBO_FRACCION` (0.30), `Config.DETECTOR_RADIO` (35).
- Produces:
  - `export type Habilidades = { [string]: number }` — clave → peldaño comprado (0 = no comprada)
  - `Skills.CATALOGO: { { id: string, nombre: string, costes: { number } } }`
  - `Skills.normalizar(datos: any): Habilidades`
  - `Skills.coste(habilidades: Habilidades, id: string): number?` — `nil` si está al máximo o no existe
  - `Skills.comprar(habilidades: Habilidades, contactos: number, id: string): (boolean, string, Habilidades, number)`
  - `Skills.factorBulto(h: Habilidades): number` · `Skills.factorRobo(h: Habilidades): number` · `Skills.factorVista(h: Habilidades): number` · `Skills.tieneSenuelo(h: Habilidades): boolean`

- [ ] **Step 1: Añadir los números a `Config.luau`**

Debajo del bloque de contactos:

```lua
-- LAS HABILIDADES. Todas se montan sobre un número que ya se calculaba: ninguna
-- crea un sistema nuevo y NINGUNA DA VELOCIDAD.
--
-- El suelo de robo es la regla de oro escrita en un número: la furgoneta ya pierde
-- poco, y tres peldaños de aguante sin suelo la dejarían en CERO -- inmunidad al
-- robo por la puerta de atrás, que es exactamente lo que el diseño prohíbe.
Config.ROBO_FRACCION_MINIMA = 0.10

Config.SENUELO_DURACION = 6 -- segundos que los ladrones van al señuelo y no a ti
Config.SENUELO_RECARGA = 45
Config.SENUELO_RADIO = 120 -- a quién despista
```

- [ ] **Step 2: Escribir la prueba que falla**

Crear `src/shared/tests/Skills.spec.luau`:

```lua
--!strict
-- Pruebas de las habilidades. La más importante es la última: ninguna combinación
-- puede volver al jugador inalcanzable ni inmune al robo. Es la única regla
-- innegociable del diseño y por eso tiene prueba, no comentario.

local Config = require(script.Parent.Parent.Config)
local Skills = require(script.Parent.Parent.Skills)

return function(kit)
	local vacias = Skills.normalizar(nil)
	kit.eq("sin datos, camuflaje a cero", vacias.camuflaje, 0)
	kit.eq("basura del cliente no sube nada", Skills.normalizar({ camuflaje = 99 }).camuflaje, 3)
	kit.eq("basura no numérica se ignora", Skills.normalizar({ camuflaje = "muchos" }).camuflaje, 0)

	kit.eq("el primer peldaño de camuflaje cuesta 20", Skills.coste(vacias, "camuflaje"), 20)
	kit.eq("una habilidad que no existe no tiene coste", Skills.coste(vacias, "volar"), nil)

	-- Comprar sin contactos suficientes no cambia nada.
	local ok, motivo, tras, saldo = Skills.comprar(vacias, 5, "camuflaje")
	kit.falsy("no se compra sin contactos", ok)
	kit.eq("y lo dice", motivo, "Te faltan contactos")
	kit.eq("el saldo no se toca", saldo, 5)
	kit.eq("la habilidad tampoco", tras.camuflaje, 0)

	-- Comprar con contactos suficientes cobra exactamente el coste.
	local ok2, _, tras2, saldo2 = Skills.comprar(vacias, 50, "camuflaje")
	kit.truthy("se compra con contactos de sobra", ok2)
	kit.eq("sube un peldaño", tras2.camuflaje, 1)
	kit.eq("y cobra 20", saldo2, 30)

	-- El tope. Tres peldaños y no hay cuarto.
	local topeCamuflaje = { camuflaje = 3 }
	kit.eq("al máximo no hay coste", Skills.coste(topeCamuflaje, "camuflaje"), nil)
	local ok3, motivo3 = Skills.comprar(topeCamuflaje, 9999, "camuflaje")
	kit.falsy("al máximo no se compra más", ok3)
	kit.eq("y lo dice", motivo3, "Ya está al máximo")

	-- Los factores: mejoran, y en la dirección correcta.
	kit.eq("sin camuflaje, el bulto no cambia", Skills.factorBulto(vacias), 1)
	kit.truthy("con camuflaje, el bulto baja", Skills.factorBulto({ camuflaje = 3 }) < 1)
	kit.truthy("con aguante, el robo baja", Skills.factorRobo({ aguante = 3 }) < 1)
	kit.truthy("con vista, el alcance sube", Skills.factorVista({ vista = 3 }) > 1)
	kit.falsy("sin comprarlo, no hay señuelo", Skills.tieneSenuelo(vacias))
	kit.truthy("comprado, hay señuelo", Skills.tieneSenuelo({ senuelo = 1 }))

	-- LA REGLA DE ORO, en números.
	local todo = { camuflaje = 3, aguante = 3, vista = 3, senuelo = 1 }
	kit.truthy("con todo comprado, todavía te fichan", Config.DETECTOR_RADIO * Skills.factorBulto(todo) > 0)
	kit.truthy(
		"con todo comprado, todavía te roban",
		math.max(Config.ROBO_FRACCION_MINIMA, Config.ROBO_FRACCION * Skills.factorRobo(todo)) >= Config.ROBO_FRACCION_MINIMA
	)
	kit.truthy("ninguna habilidad toca la velocidad", Skills.factorVelocidad == nil)
end
```

- [ ] **Step 3: Ejecutar y ver que falla**

Esperado: `[X] Skills.spec :: la suite reventó: ... Skills is not a valid member of Shared`.

- [ ] **Step 4: Escribir `Skills.luau`**

```lua
--!strict
--[[
	Skills.luau — las habilidades del repartidor. Módulo PURO.

	POR QUÉ EXISTE. Levels.luau ya decía en su cabecera que se pidieron cuatro
	estadísticas y que entró primero el estatus a secas. Esto es la otra mitad: lo
	que el jugador construye a su gusto, pagado con lo que recoge por el camino.

	LA REGLA QUE MANDA SOBRE TODAS: la progresión va por capacidad y acceso, NUNCA
	por potencia. Por eso aquí no hay habilidad de velocidad ni de inmunidad --
	camuflaje y aguante MITIGAN, el señuelo RETRASA y tiene recarga. Que ninguna
	combinación deje al jugador fuera de alcance está comprobado en la suite, no
	confiado a este comentario.

	Y por eso los efectos son FACTORES sobre un número que ya se calculaba
	(`bulto` del vehículo, fracción robada, alcance del minimapa) en vez de reglas
	nuevas: lo que ya estaba equilibrado se mueve, no se sustituye.
]]

local Skills = {}

-- Los costes son crecientes y el primero es barato a propósito: el primer peldaño
-- tiene que caer en la primera sesión, que es cuando el jugador decide si vuelve.
-- Con un viaje verde dando ~11 contactos y uno rojo ~31, el primero cae solo.
Skills.CATALOGO = {
	{
		id = "camuflaje",
		nombre = "Camuflaje",
		descripcion = "Las esquinas fichadas te ven desde menos lejos",
		costes = { 20, 60, 150 },
	},
	{
		id = "aguante",
		nombre = "Aguante",
		descripcion = "Pierdes menos carga cuando te alcanzan",
		costes = { 20, 60, 150 },
	},
	{
		id = "vista",
		nombre = "Vista",
		descripcion = "Ves guaridas y ladrones desde más lejos en el mapa",
		costes = { 20, 60, 150 },
	},
	{
		id = "senuelo",
		nombre = "Señuelo",
		descripcion = "Sueltas un cebo: los ladrones van a él y no a ti",
		costes = { 80 },
	},
}

export type Habilidades = { [string]: number }

local function definicion(id: string)
	for _, d in Skills.CATALOGO do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- TODO LO QUE VENGA DE FUERA PASA POR AQUÍ. El DataStore guarda lo que se le dio y
-- un cliente manipulado manda lo que quiere: sin recorte, un `camuflaje = 99`
-- guardado una vez valdría para siempre.
function Skills.normalizar(datos: any): Habilidades
	local salida: Habilidades = {}
	for _, d in Skills.CATALOGO do
		local valor = 0
		if type(datos) == "table" and type(datos[d.id]) == "number" then
			valor = math.clamp(math.floor(datos[d.id]), 0, #d.costes)
		end
		salida[d.id] = valor
	end
	return salida
end

function Skills.coste(habilidades: Habilidades, id: string): number?
	local d = definicion(id)
	if not d then
		return nil
	end
	local actual = habilidades[id] or 0
	if actual >= #d.costes then
		return nil
	end
	return d.costes[actual + 1]
end

-- Devuelve (comprado, motivo, habilidades resultantes, contactos restantes).
-- NUNCA lanza y NUNCA muta lo que recibe: quien llame se queda con lo devuelto, y
-- si no se pudo comprar lo devuelto es lo que ya había.
function Skills.comprar(
	habilidades: Habilidades,
	contactos: number,
	id: string
): (boolean, string, Habilidades, number)
	local copia = Skills.normalizar(habilidades)

	local d = definicion(id)
	if not d then
		return false, "Esa habilidad no existe", copia, contactos
	end

	local coste = Skills.coste(copia, id)
	if not coste then
		return false, "Ya está al máximo", copia, contactos
	end
	if contactos < coste then
		return false, "Te faltan contactos", copia, contactos
	end

	copia[id] = (copia[id] or 0) + 1
	return true, "", copia, contactos - coste
end

-- Cuánto se multiplica el `bulto` del vehículo, o sea desde qué distancia te
-- fichan. Baja, nunca a cero: un repartidor invisible no existe.
function Skills.factorBulto(habilidades: Habilidades): number
	local peldano = math.clamp(math.floor((habilidades.camuflaje :: any) or 0), 0, 3)
	return ({ 1.0, 0.92, 0.84, 0.75 })[peldano + 1]
end

-- Cuánto se multiplica la fracción de carga que se lleva quien te alcanza. Quien
-- aplique esto DEBE respetar Config.ROBO_FRACCION_MINIMA como suelo.
function Skills.factorRobo(habilidades: Habilidades): number
	local peldano = math.clamp(math.floor((habilidades.aguante :: any) or 0), 0, 3)
	return ({ 1.0, 0.9, 0.8, 0.7 })[peldano + 1]
end

-- Cuánto se multiplica el alcance del minimapa. Es la única que sube.
function Skills.factorVista(habilidades: Habilidades): number
	local peldano = math.clamp(math.floor((habilidades.vista :: any) or 0), 0, 3)
	return ({ 1.0, 1.25, 1.5, 1.75 })[peldano + 1]
end

function Skills.tieneSenuelo(habilidades: Habilidades): boolean
	return ((habilidades.senuelo :: any) or 0) >= 1
end

return Skills
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Esperado: `Skills.spec` entero en `[ok]`.

- [ ] **Step 6: Formato y commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/shared/Config.luau games/contrabando/src/shared/Skills.luau games/contrabando/src/shared/tests/Skills.spec.luau
git commit -m "feat: las habilidades, con la regla de oro comprobada en la suite"
```

---

### Task 3: Que el estado los conozca y el guardado los recuerde

**Files:**
- Modify: `src/shared/Remotes.luau` (junto a los demás, sobre la línea 27)
- Modify: `src/server/PlayerState.luau` (tipo `Estado`, valores iniciales, `sync`)
- Modify: `src/server/Persistence.luau` (carga sobre la línea 66, guardado sobre la 126)

**Interfaces:**
- Consumes: `Skills.normalizar` (Task 2).
- Produces: `estado.contactos: number` y `estado.habilidades: Skills.Habilidades`, ambos en el sync al cliente y en el DataStore. Remotes `Remotes.COMPRAR_HABILIDAD` y `Remotes.USAR_SENUELO`.

- [ ] **Step 1: Declarar los remotes**

En `src/shared/Remotes.luau`, junto a los demás (van con los otros para que **se creen todos al arrancar**):

```lua
Remotes.COMPRAR_HABILIDAD = "ComprarHabilidad" -- cliente -> servidor: "compro este peldaño"
Remotes.USAR_SENUELO = "UsarSenuelo" -- cliente -> servidor: "suelto el cebo aquí"
```

- [ ] **Step 2: Añadir los campos al `Estado`**

En `src/server/PlayerState.luau`, dentro de `export type Estado`, detrás de `xp: number`:

```lua
	-- La moneda de las habilidades. Se recoge por el camino y SÓLO se gasta en
	-- ellas: no compra vehículos ni mejoras de nave, y por eso no puede
	-- desequilibrar una economía que ya está medida.
	contactos: number,
	-- Peldaño comprado de cada habilidad. Lo normaliza Skills en cada carga: un
	-- valor guardado mal valdría para siempre.
	habilidades: { [string]: number },
	-- Cuántos contactos llevas recogidos EN ESTE VIAJE. De aquí sale la racha de
	-- velocidad. NO SE PERSISTE, por lo mismo que el calor: es del viaje, y volver
	-- con la racha de ayer sería premio por desconectarse.
	recogidos: number,
```

Y en el sitio donde se construye el estado inicial, `contactos = 0` y `habilidades = Skills.normalizar(nil)`. Añadir arriba `local Skills = require(ReplicatedStorage.Shared.Skills)` siguiendo el estilo de los `require` que ya haya en el fichero.

- [ ] **Step 3: Incluirlos en el sync al cliente**

En `PlayerState.sync`, añadir `contactos` y `habilidades` a la tabla que se envía, junto a `dinero` y `xp`. **El cliente los recibe, nunca los propone.**

- [ ] **Step 4: Guardar y cargar**

En `src/server/Persistence.luau`, en la carga (junto a `estado.xp`, línea ~65):

```lua
	estado.contactos = math.max(0, math.floor(tonumber(datos.contactos) or estado.contactos or 0))
	estado.habilidades = Skills.normalizar(datos.habilidades)
```

Y en el guardado (junto a `xp = estado.xp or 0`, línea ~120):

```lua
		contactos = estado.contactos or 0,
		habilidades = estado.habilidades or {},
```

- [ ] **Step 5: Comprobar que no se ha roto nada**

Ejecutar la batería pura completa (bloque de "Global Constraints"). Esperado: el mismo número de pruebas que antes de esta tarea, todas en verde — esta tarea no añade pruebas porque no añade reglas, solo transporte.

Y con Rojo sincronizado, entrar en Play y comprobar en el datamodel `Server`:

```lua
local PlayerState = require(game.ServerScriptService.Server.PlayerState)
local p = game.Players:GetPlayers()[1]
local e = PlayerState.get(p)
return { contactos = e.contactos, habilidades = e.habilidades }
```

Esperado: `contactos = 0` y las cuatro claves a 0. Recordar la trampa: **entrar en Play antes de que Rojo haya sincronizado construye el mundo con el código viejo** — comprobar el `Source` en el datamodel `Edit` antes de medir.

- [ ] **Step 6: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/shared/Remotes.luau games/contrabando/src/server/PlayerState.luau games/contrabando/src/server/Persistence.luau
git commit -m "feat: el estado y el guardado conocen contactos y habilidades"
```

---

### Task 4: `ContactService` — sembrar, detectar, retirar

**Files:**
- Create: `src/server/ContactService.luau`
- Modify: `src/server/RouteService.luau` (dentro de `RouteService.elegir`, tras dar la ruta por buena)
- Modify: `src/server/CargoService.luau` (donde se cobra la entrega, junto a la línea 396)
- Modify: `src/server/Main.server.luau` (arrancarlo con los demás servicios)

**Interfaces:**
- Consumes: `Contacts.deRuta` (Task 1), `estado.contactos` (Task 3), `Lairs.sitiosDeRuta`, `PlayerState.get/sync`, `Config.CONTACTO_RADIO`.
- Produces: `ContactService.sembrar(player: Player, rutaId: string)`, `ContactService.retirar(player: Player)`, `ContactService.start()`.

- [ ] **Step 1: Escribir el servicio**

Crear `src/server/ContactService.luau`. Lo que tiene que hacer, y las trampas que ya están pagadas:

- **Siembra por jugador**: al elegir ruta, `Contacts.deRuta(rutaId, Config.ALMACEN_POS, destinoDeLaRuta, Lairs.sitiosDeRuta(...))` y planta una pieza por contacto en una carpeta propia del workspace, **sin colisión** y `Anchored = true`.
- **La cota se toma de la calzada, no del cielo.** Un rayo desde arriba devuelve lo primero que toca y en una ciudad eso es un tejado la mitad de las veces: quince detectores acabaron en azoteas. Reutilizar el mismo método que ya usa `MapBuilder`/`RoadService` para apoyar cosas en la calle, y **rechazar cotas altas**.
- **La detección es del servidor**, en un bucle `Heartbeat` a `Config.INTERCEPT_HZ` (5 Hz, ya existe): recorre los contactos vivos de cada jugador y recoge los que estén a menos de `Config.CONTACTO_RADIO` **medido en el plano** (medir en 3D convirtió una vez 83 studs de altura en 83 de desviación).
- Al recoger: `estado.contactos += valor`, destruir la pieza, `PlayerState.sync(player)` y un sonido corto. **Ningún remote de "he recogido"**.
- **Retirada** en `ContactService.retirar(player)`: al entregar, al salir el jugador y al elegir otra ruta (antes de volver a sembrar).
- Todo lo que pueda lanzar, dentro de `pcall`, y el aviso **una vez por sesión y por sitio**: un `pcall` pelado alrededor de algo que corre en bucle es un agujero negro.

- [ ] **Step 2: Engancharlo**

- En `RouteService.elegir`, tras aceptar la ruta: `ContactService.retirar(player)`, `estado.recogidos = 0` y `ContactService.sembrar(player, rutaId)`.
- En `CargoService`, donde se cobra la entrega (junto a `estado.xp = ... + Levels.xpPorEntrega(cobrado)`): `ContactService.retirar(player)` y `estado.recogidos = 0`.
- En `Main.server.luau`, `ContactService.start()` con los demás.

- [ ] **Step 2b: La racha, aplicada**

Al recoger, `estado.recogidos += 1` y refrescar la velocidad. La velocidad se escribe hoy en dos sitios y **en los dos** pasa a ser:

```lua
humanoid.WalkSpeed = Contacts.velocidadConRacha(Cargo.velocidad(estado.cajas, cuenta), estado.recogidos)
```

- `src/server/CargoService.luau:65`
- `src/server/RoadService.luau:391`

**No se toca `Cargo.velocidad`** — además de que la otra sesión tiene ese fichero abierto, la carga y la racha son cosas distintas: mezclarlas obligaría a que todo el que pregunta por el peso supiera del viaje.

Y **la racha se borra al ser alcanzado**: en `InterceptService`, donde ya se aplica el robo, `estado.recogidos = 0` y refrescar la velocidad. Perder la carga y perder la velocidad en el mismo golpe es lo que convierte el robo en un momento, y no hace falta explicarlo.

- [ ] **Step 3: Verificar en el mundo, no en el vacío**

En Play, datamodel `Server`, elegir ruta por código y contar lo plantado:

```lua
local ContactService = require(game.ServerScriptService.Server.ContactService)
local RouteService = require(game.ServerScriptService.Server.RouteService)
local p = game.Players:GetPlayers()[1]
RouteService.elegir(p, "verde")
local carpeta = workspace:FindFirstChild("Contactos")
return carpeta and #carpeta:GetChildren() or "no hay carpeta"
```

Esperado: **7** para la verde (6 sueltos + 1 racimo).

Y comprobar que ninguno quedó en una azotea:

```lua
local altura = {}
for _, p in workspace.Contactos:GetChildren() do
	table.insert(altura, math.floor(p.Position.Y))
end
return altura
```

Esperado: todos dentro de ±6 studs de la cota de la calle (la ciudad ronda 19). Cualquiera 20 studs por encima es un tejado y hay que arreglarlo antes de seguir.

- [ ] **Step 4: Verificar ANDANDO, que es lo único que vale**

**Verificar teletransportando no verifica el mapa** — es el fallo que dejó pasar una carretera que ni cubría el almacén. Mover al personaje con `Humanoid:MoveTo` desde la salida hacia el destino, replanteando cada 2 segundos (una sonda en línea recta se clava contra un seto y parece un atasco del juego), y leer `estado.contactos` al llegar.

Esperado: **≥ 4 de los 6 sueltos** (el 70% del umbral del spec).

- [ ] **Step 5: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/server/ContactService.luau games/contrabando/src/server/RouteService.luau games/contrabando/src/server/CargoService.luau games/contrabando/src/server/Main.server.luau
git commit -m "feat: los contactos existen en la calle y los recoge el servidor"
```

---

### Task 5: Que las habilidades hagan algo

**Files:**
- Modify: `src/server/HeatService.luau` (camuflaje)
- Modify: `src/server/InterceptService.luau` (aguante)
- Modify: `src/server/PatrolService.luau` (señuelo)
- Modify: `src/server/Main.server.luau` (escuchar `COMPRAR_HABILIDAD` y `USAR_SENUELO`)

**Interfaces:**
- Consumes: `Skills.factorBulto/factorRobo/tieneSenuelo` (Task 2), `estado.habilidades` (Task 3), `Config.SENUELO_*`, `Config.ROBO_FRACCION_MINIMA`.
- Produces: `PatrolService.senuelo(player: Player, donde: Vector3, hasta: number)` — mientras `os.clock() < hasta`, los ladrones a menos de `Config.SENUELO_RADIO` de `donde` van a ese punto en vez de al jugador.

- [ ] **Step 1: Camuflaje**

En `HeatService`, donde se compara la distancia del jugador con el radio del detector, multiplicar el radio efectivo por `Skills.factorBulto(estado.habilidades)`. **Es el mismo sitio donde ya se multiplica por el `bulto` del vehículo**, no un cálculo nuevo.

- [ ] **Step 2: Aguante, con su suelo**

En `InterceptService`, donde se decide la fracción que se lleva quien alcanza:

```lua
local fraccion = math.max(
	Config.ROBO_FRACCION_MINIMA,
	fraccionBase * Skills.factorRobo(estadoVictima.habilidades)
)
```

`fraccionBase` es la que ya se usaba (`Config.ROBO_FRACCION` para un jugador, la del PNJ para un ladrón). **El suelo no es opcional**: sin él, tres peldaños dejan a la furgoneta en cero robado, que es inmunidad.

- [ ] **Step 3: Señuelo**

En `PatrolService`, añadir `PatrolService.senuelo(player, donde, hasta)` que guarda el punto y el instante final por jugador, y en `perseguir` (línea ~424): si hay señuelo vivo para ese jugador y la patrulla está a menos de `Config.SENUELO_RADIO` del punto, `MoveTo` al punto en vez de al jugador.

**Retrasa, no anula**: al vencer, la persecución sigue. Y todo PNJ que use `MoveTo` **necesita detección de atasco** — el mapa tiene 116 vallas y un ladrón empujando una se queda en `Running` a velocidad nominal avanzando cero, sin que el jugador se entere. Reutilizar la que `PatrolService` ya tiene.

- [ ] **Step 3b: Los ladrones escalan con la racha, no solo con el vehículo**

En `PatrolService`, donde se decide la velocidad del perseguidor (`vehiculoDelPerseguidor`, línea ~110, y el ajuste de la línea ~599), sumar también `Contacts.racha(estado.recogidos)` del perseguido.

**Es lo que sostiene la regla de oro con la racha puesta.** Sin esto, un jugador con la racha al tope se despega de sus ladrones y el sistema entero de robo se apaga solo — que es exactamente lo que la velocidad permanente habría provocado, solo que más despacio y más difícil de ver.

Comprobación: con el jugador a pie y la racha al tope (16 + 4 = 20), el ladrón debe salir a 20 o más.

- [ ] **Step 4: Escuchar los dos remotes**

En `Main.server.luau`:

- `COMPRAR_HABILIDAD(id)`: `Skills.comprar(estado.habilidades, estado.contactos, id)`; si sale bien, escribir las dos cosas devueltas en el estado, `PlayerState.sync` y aviso; si no, mandar el motivo tal cual (`"Te faltan contactos"`, `"Ya está al máximo"`). **El servidor decide**: el cliente pinta el precio pero no lo aplica.
- `USAR_SENUELO()`: rechazar si `not Skills.tieneSenuelo(...)` o si la recarga no ha vencido; si vale, `PatrolService.senuelo(player, posición actual del jugador, os.clock() + Config.SENUELO_DURACION)` y guardar el instante para la recarga. **La posición la toma el servidor del personaje**, no del mensaje del cliente: un parámetro de posición sería un teletransporte de ladrones gratis.

- [ ] **Step 5: Verificar los tres efectos**

En Play, datamodel `Server`, con un jugador dentro:

```lua
local PlayerState = require(game.ServerScriptService.Server.PlayerState)
local p = game.Players:GetPlayers()[1]
local e = PlayerState.get(p)
e.contactos = 1000
-- comprar los tres peldaños de aguante y ver que la fracción baja pero no a cero
```

Esperado: con `aguante = 3` la fracción efectiva es `0.30 × 0.7 = 0.21`, y con la del PNJ `0.50 × 0.7 = 0.35`. **Nunca 0.**

Para el señuelo: subir el calor hasta que salga un ladrón, llamar a `PatrolService.senuelo` con un punto a 30 studs y comprobar en la traza que la patrulla se va al punto y **vuelve a perseguir** a los 6 segundos.

- [ ] **Step 6: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/server/HeatService.luau games/contrabando/src/server/InterceptService.luau games/contrabando/src/server/PatrolService.luau games/contrabando/src/server/Main.server.luau
git commit -m "feat: camuflaje, aguante y senuelo cambian el viaje"
```

---

### Task 6 (BLOQUEADA — esperar a la otra sesión): el cliente y el menú 2D

**Comprobar primero:** `git status --short` no debe listar `Hud.luau`, `Main.client.luau` ni `Garage.luau` como modificados.

**Files:**
- Create: `src/client/Menu.luau`
- Modify: `src/client/Hud.luau` (contador de contactos y botón del señuelo)
- Modify: `src/client/Main.client.luau` (arrancar el menú)

**Interfaces:**
- Consumes: `Skills.CATALOGO`, `Skills.coste`, el sync con `contactos` y `habilidades` (Task 3), `Remotes.COMPRAR_HABILIDAD`, `Remotes.USAR_SENUELO`.
- Produces: `Menu.build(gui: ScreenGui)`, `Menu.refrescar(estado)`.

- [ ] **Step 1: Los paneles**

Botones laterales que abren **Habilidades**, **Nave** y **Taller**. Cada panel lista lo suyo con su precio y un botón que manda el remote correspondiente.

**La excepción que es de diseño, no de comodidad:** el panel del taller **compra** vehículos desde cualquier sitio, pero **sacar** el vehículo activo sigue exigiendo estar en un taller. Si no, "cuál me llevo a *este* viaje" deja de ser una decisión, y es lo que el garaje y la regla de la calzada existen para crear. El botón de sacar sale desactivado con el motivo escrito cuando el jugador está lejos.

Los edificios del mundo **se quedan** y siguen funcionando: el menú es una segunda puerta, no una demolición.

- [ ] **Step 2: El contador y el botón del señuelo**

Contador de contactos en el HUD junto a dinero y nivel. Botón del señuelo **solo si está comprado**, con su recarga a la vista.

Todo dentro de su `pcall`: una excepción a mitad de `Hud.build()` ya dejó una vez el juego con medio HUD y sin selector de ruta, sin un solo error visible.

- [ ] **Step 3: Comprobar los solapes, en absolutas y todos contra todos**

**Mirar una captura no verifica la interfaz**: el botón de comprar pisaba el de salto de Roblox por 6 px y en pantalla no se veía. Comparar posiciones **absolutas** (el HUD y los controles táctiles tienen orígenes distintos, y con `DeviceSafeInsets` el origen del `ScreenGui` no es (0,0) sino algo como (0,−58)), y comparar **todos contra todos**: revisando elemento por elemento se pasaron tres solapes.

Comprobar en las tres pantallas que ya se usaron: Galaxy A06, iPad Pro y portátil.

- [ ] **Step 4: Commit**

```bash
tools/stylua.exe --check src
git add games/contrabando/src/client/
git commit -m "feat: el menu 2D y el contador de contactos"
```

---

### Task 7 (BLOQUEADA — esperar a la otra sesión): la medida que dice si el sistema existe

**Files:**
- Modify: `src/server/SelfCheck.luau`

- [ ] **Step 1: La comprobación**

Añadir a `SelfCheck.run()`, en su sección INFORME, por cada ruta:

- cuántos contactos se sembraron y cuántos **recogería quien va en línea recta** (`Contacts.recogidosEnLineaRecta`). **Umbral: ≥70% de los sueltos.**
- la desviación de cada racimo respecto al camino. **Umbral: entre 40 y 90 studs.**
- la cota de cada contacto contra la de la calzada bajo él. **Cualquiera 20 studs por encima es un tejado.**

Es la lección de los detectores, que costó descubrir que medio sistema de vigilancia era decorado: **si el desvío típico respecto al camino supera el radio de acción, el sistema no existe** aunque el código esté escrito y probado.

- [ ] **Step 2: Una partida entera, jugada**

Las tres rutas, andando, con el bucle completo. Anotar en `VERIFICACION.md`: contactos recogidos por ruta, tiempo, y si el ritmo se nota. **Ésta es la verificación que decide si el sistema se queda como está o se recalibra** — los números del spec son de partida, no un compromiso.

- [ ] **Step 3: Commit**

```bash
git add games/contrabando/src/server/SelfCheck.luau games/contrabando/VERIFICACION.md
git commit -m "verificacion: los contactos se encuentran de verdad"
```

---

## Después de este plan

Actualizar `JUEGO.md` (§3 con los contactos y las habilidades, §5 con el menú, §7 quitando lo que deje de ser cierto) y `RUMBO.md` §6, y seguir con lo que ya estaba pendiente: ladrones que crecen con lo que llevas, el robo con dos jugadores, y la portada.
