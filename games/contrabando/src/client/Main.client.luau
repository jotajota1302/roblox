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
