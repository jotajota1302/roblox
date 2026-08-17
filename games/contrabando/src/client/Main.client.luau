--!strict
--[[
	Main.client.luau — arranque del cliente.

	El cliente NO tiene lógica de juego: pide su estado, lo dibuja y manda
	intenciones. Es el servidor quien decide si esas intenciones valen.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local RoutePicker = require(script.Parent:WaitForChild("RoutePicker"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

-- La carpeta del mundo la crea el servidor al arrancar, así que puede no existir
-- todavía cuando este script empieza. Se espera con un tope: sin ella el juego
-- sigue funcionando (sólo que el selector no aparecería), y colgarse para siempre
-- esperando algo que quizá no llega es peor que seguir sin ello.
local mundo = workspace:WaitForChild("Mundo", 20) :: Instance?

-- Cada pantalla se construye por su cuenta y protegida, igual que los servicios
-- del servidor. LA RAZÓN, pagada: una excepción a mitad de Hud.build() (un
-- Color3 fuera de rango en un degradado) se llevó por delante el resto del
-- script -- HUD a medias, selector de ruta que nunca llegó a existir, y ni un
-- error visible en la pantalla del jugador. Un fallo en el adorno de un botón no
-- puede costar el selector de ruta, que es donde se juega la partida.
local function construir(nombre: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Contrabando] no se pudo construir " .. nombre .. ": " .. tostring(err))
	end
	return ok
end

-- Estado del selector de ruta. Se recalcula tanto cuando llega estado nuevo del
-- servidor como cuando el jugador se mueve, porque depende de las dos cosas.
--
-- Declaradas ANTES de construir el selector, que es quien captura `cerradoAMano`
-- en su callback: en Lua un nombre usado antes de existir como local se resuelve
-- como global, así que el botón "Ahora no" escribiría en una variable distinta de
-- la que lee refrescarSelector y no cerraría nada. Este proyecto ya pagó ese
-- mismo error una vez, en CargoService.
local ultimoEstado: any = nil
local cerradoAMano = false

construir("Hud", Hud.build)

construir("RoutePicker", function()
	RoutePicker.build(function(rutaId)
		Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
	end, function()
		cerradoAMano = true
	end)
end)

-- CUÁNDO aparece el selector. La versión anterior sólo miraba "llevas carga y no
-- has elegido ruta", y eso lo abría NADA MÁS RECOGER, dentro del almacén. Dos
-- consecuencias, las dos malas:
--
--   · Ahí el servidor RECHAZA la elección (exige estar en la salida), así que
--     era una pantalla cuyos tres botones no hacían nada.
--   · Y al ser modal, tapaba el mundo entero -- incluido tu propio personaje --
--     y escondía los botones, incluido el de comprar la furgoneta. Recogías
--     cajas y te quedabas encerrado en una pantalla oscura sin salida.
--
-- Ahora aparece donde sirve: en la salida, con carga y sin ruta elegida. Y se
-- puede cerrar; al alejarse y volver, vuelve a ofrecerse.
local function debeElegir(): boolean
	if ultimoEstado == nil or #ultimoEstado.cajas == 0 or ultimoEstado.ruta ~= nil then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local salida = mundo and mundo:FindFirstChild("Salida") :: BasePart?
	if not root or not salida then
		return false
	end
	return (root.Position - salida.Position).Magnitude <= Config.DISTANCIA_SALIDA
end

local function refrescarSelector()
	local eligiendo = debeElegir()
	if not eligiendo then
		-- Al salir de la zona se olvida el cierre manual: volver a la salida es
		-- justamente decir "ahora sí quiero elegir".
		cerradoAMano = false
	end
	local mostrar = eligiendo and not cerradoAMano
	-- setModal ANTES de update: update decide si el botón de comprar se enciende,
	-- y necesita saber ya si hay algo delante.
	Hud.setModal(mostrar)
	if ultimoEstado then
		Hud.update(ultimoEstado)
	end
	if mostrar then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
	end
end

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	ultimoEstado = estado
	refrescarSelector()
end)

-- Y también al moverse: el estado no cambia por caminar, pero la respuesta a
-- "¿estoy en la salida?" sí. Cuatro veces por segundo basta y de sobra para algo
-- que el jugador alcanza andando a 10-16 studs/s.
task.spawn(function()
	while true do
		task.wait(0.25)
		pcall(refrescarSelector)
	end
end)

Remotes.event(Remotes.AVISO).OnClientEvent:Connect(function(texto, color)
	Hud.aviso(texto, color)
end)

Remotes.event(Remotes.SONIDO).OnClientEvent:Connect(function(clave)
	Sfx.reproducir(clave)
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
