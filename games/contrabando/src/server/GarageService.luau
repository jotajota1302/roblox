--!strict
--[[
	GarageService.luau — el taller: donde el dinero deja de ser un número.

	Es el sumidero que faltaba. Sin él el bucle era "produces → cobras" y se
	acababa ahí: ninguna razón para preferir la roja a la verde, porque lo que
	ganabas no compraba nada.

	Las mismas cuatro cautelas que RouteService, por el mismo motivo (cada una que
	falte es un exploit):

	  1. que el vehículo exista (un id inventado no da capacidad)
	  2. que sea una mejora de verdad y no lo que ya tienes
	  3. que tenga el dinero — y que se COBRE antes de dárselo
	  4. que esté físicamente en el taller (no se compra desde el otro extremo del
	     mapa a mitad de una persecución)

	Y una que no es de seguridad sino de diseño: no se compra con carga encima. Si
	se pudiera, cambiar de vehículo a mitad de viaje sería una forma de subir la
	capacidad justo antes de robar, y la decisión "salgo con lo que me cabe" -- que
	es media tensión del juego -- desaparecería.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local CargoService = require(script.Parent.CargoService)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local DISTANCIA_TALLER = 35

local VERDE = Palette.AVISO_BUENO
local ROJO = Palette.AVISO_MALO

-- Por qué falló la compra, en palabras que le sirvan a quien ha pulsado el botón.
-- Un botón que no hace nada y no dice nada es indistinguible de un juego roto.
local EXPLICACION: { [string]: string } = {
	sin_dinero = "No te llega el dinero",
	ya_lo_tienes = "Ya tienes ese vehiculo",
	ya_tienes_uno_mejor = "El tuyo es mejor",
	no_esta_a_la_venta = "Eso no se vende",
	vehiculo_desconocido = "Ese vehiculo no existe",
	lejos = "Tienes que estar en el taller",
	con_carga = "Descarga antes de cambiar de vehiculo",
}

local GarageService = {}
local taller: BasePart? = nil

function GarageService.registrarTaller(part: BasePart)
	taller = part
end

function GarageService.enElTaller(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not taller then
		return false
	end
	return (root.Position - (taller :: BasePart).Position).Magnitude <= DISTANCIA_TALLER
end

-- Pública (no local) para poder probarla desde el servidor sin pasar por el
-- remote, igual que CargoService.entregar.
function GarageService.comprar(player: Player, vehiculoId: string): (boolean, string)
	-- typeof antes que nada: por el remote llega lo que le dé la gana al cliente,
	-- y Vehicles.puedeComprar recibe un string en su firma.
	if typeof(vehiculoId) ~= "string" then
		return false, "vehiculo_desconocido"
	end

	local estado = PlayerState.get(player)

	if not GarageService.enElTaller(player) then
		return false, "lejos"
	end
	if #estado.cajas > 0 then
		return false, "con_carga"
	end

	local puede, motivo = Vehicles.puedeComprar(estado.vehiculo, vehiculoId, estado.dinero)
	if not puede then
		return false, motivo
	end

	local def = Vehicles.get(vehiculoId)
	-- Cobrar ANTES de entregar. Al revés, cualquier fallo entre las dos líneas
	-- regala el vehículo, y ese es el orden que se olvida en todas las tiendas.
	estado.dinero -= def.coste
	estado.vehiculo = def.id

	CargoService.aplicarVelocidad(player)
	PlayerState.sync(player)

	Telemetry.evento(player, "compra_vehiculo", { vehiculo = def.id, coste = def.coste })
	Remotes.event(Remotes.AVISO)
		:FireClient(player, string.format("%s comprada. Ahora llevas %d cajas", def.nombre, def.capacidad), VERDE)
	Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")

	return true, "ok"
end

function GarageService.start()
	Remotes.event(Remotes.COMPRAR).OnServerEvent:Connect(function(player, vehiculoId)
		local ok, motivo = GarageService.comprar(player, vehiculoId)
		if not ok then
			-- Sólo se explica al que está en el taller. Fuera de él, el aviso sería
			-- ruido provocable por cualquiera que inunde el remote.
			if GarageService.enElTaller(player) then
				Remotes.event(Remotes.AVISO):FireClient(player, EXPLICACION[motivo] or "No se puede comprar", ROJO)
			end
		end
	end)

	-- El vehículo inicial no se compra: existe para que Config.VEHICULO_INICIAL
	-- sea de verdad la única definición de "con qué empiezas". Si alguien lo
	-- cambiara a "furgoneta", esto lo daría por bueno sin tocar nada más.
	assert(Vehicles.existe(Config.VEHICULO_INICIAL), "VEHICULO_INICIAL no existe en Config.VEHICULOS")
end

return GarageService
