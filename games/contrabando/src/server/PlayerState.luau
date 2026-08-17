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
	-- Los remotes se crean al arrancar, nunca perezosamente. SYNC_STATE sólo se envía,
	-- así que sin esta línea no existiría hasta el primer sync -- y el cliente, que hace
	-- WaitForChild sobre él nada más cargar, esperaría para siempre sin llegar nunca a
	-- pedir su estado. Un interbloqueo perfecto.
	Remotes.event(Remotes.SYNC_STATE)

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
