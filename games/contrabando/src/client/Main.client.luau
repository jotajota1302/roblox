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

Hud.build()

RoutePicker.build(function(rutaId)
	Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
end)

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	Hud.update(estado)
	-- El selector aparece cuando llevas carga y aún no has elegido por dónde vas.
	if #estado.cajas > 0 and estado.ruta == nil then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
	end
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
