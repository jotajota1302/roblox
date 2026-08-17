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
local Rarity = require(game.ReplicatedStorage.Shared.Rarity)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local PlayerState = require(script.Parent.PlayerState)
local RouteService = require(script.Parent.RouteService)
local Telemetry = require(script.Parent.Telemetry)

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

-- Declarada aquí (antes de recoger/vaciar, que la usan) en vez de junto a
-- marcarLegendaria más abajo: en Lua un nombre usado antes de declararse como
-- local se resuelve como global nil, y reventaría al recoger la primera caja.
local function tieneLegendaria(cajas: { Economy.Caja }): boolean
	for _, caja in cajas do
		if caja.rareza == "legendaria" then
			return true
		end
	end
	return false
end

function CargoService.recoger(player: Player, caja: Economy.Caja): boolean
	local estado = PlayerState.get(player)
	if not Cargo.cabe(estado.cajas, caja, Config.CAPACIDAD_A_PIE) then
		return false
	end
	table.insert(estado.cajas, caja)
	aplicarVelocidad(player)
	PlayerState.sync(player)
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
	return true
end

function CargoService.vaciar(player: Player): { Economy.Caja }
	local estado = PlayerState.get(player)
	local cajas = estado.cajas
	estado.cajas = {}
	aplicarVelocidad(player)
	PlayerState.sync(player)
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
	return cajas
end

function CargoService.aplicarVelocidad(player: Player)
	aplicarVelocidad(player)
end

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

-- Genera una caja con rareza aleatoria. La Tarea 9 la llamará desde el almacén;
-- de momento sirve para probar la mecánica de punta a punta.
local rng = Random.new(os.clock() * 1000)

function CargoService.nuevaCaja(): Economy.Caja
	return { rareza = Rarity.tirada(rng) }
end

-- Punto de entrega. El multiplicador es el de la ruta elegida en la salida, y
-- entregaValida exige que la ruta elegida coincida con la ruta del destino:
-- sin eso, elegir la roja y entregar en el destino verde cobraría el premio
-- grande por el viaje corto.
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
			Telemetry.evento(player, "entrega", {
				ruta = rutaDelDestino,
				cajas = #cajas,
				valor = Economy.valorEntrega(cajas, multiplicador),
			})
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
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
