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
