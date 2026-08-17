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
local RoutePicker = require(script.Parent:WaitForChild("RoutePicker"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

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

construir("Hud", Hud.build)

construir("RoutePicker", function()
	RoutePicker.build(function(rutaId)
		Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
	end)
end)

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	-- El selector aparece cuando llevas carga y aún no has elegido por dónde vas.
	-- Es modal: mientras esté, los botones de acción se apagan. El orden importa
	-- -- setModal ANTES de update -- porque update es quien decide si el botón de
	-- comprar vuelve a encenderse, y necesita saber ya si hay algo delante.
	local eligiendo = #estado.cajas > 0 and estado.ruta == nil
	Hud.setModal(eligiendo)
	Hud.update(estado)
	if eligiendo then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
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
