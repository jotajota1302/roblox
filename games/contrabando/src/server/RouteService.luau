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
