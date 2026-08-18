--!strict
--[[
	RouteService.luau — elección de ruta y su validación.

	Cuatro comprobaciones que el servidor NO se salta, porque cada una es un
	exploit si falta:

	  1. que la ruta exista (un id inventado no cobra nada)
	  2. que lleve carga (elegir ruta sin nada encima no tiene sentido)
	  3. que esté DENTRO DEL RECINTO del almacén (no se cambia de ruta a mitad de
	     viaje, que sería elegir la verde para pasar tranquilo y cambiar a roja al
	     llegar)
	  4. que no esté ya en ruta
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local RouteService = {}

-- La losa de salida sigue siendo el sitio donde el juego INVITA a elegir (allí se
-- abre el selector solo), pero ya no es donde se valida: eso lo hace el recinto
-- entero, unos pasos más allá. Se guarda igual porque el mundo la registra al
-- arrancar y perder la referencia obligaría a buscarla por nombre el día que algo
-- vuelva a necesitarla.
local salida: BasePart? = nil

function RouteService.registrarSalida(part: BasePart)
	salida = part
end

function RouteService.getSalida(): BasePart?
	return salida
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
	if not root then
		return false
	end
	-- EL RECINTO ENTERO, no los 40 studs de la losa de salida. El selector se abre
	-- en dos sitios --la salida y la valla-- y la valla está a setenta studs de la
	-- losa: con la comprobación vieja, el jugador que se plantaba delante de la
	-- valla veía tres botones que el servidor rechazaba en silencio, que es
	-- exactamente el fallo que esta ronda venía a quitar.
	--
	-- La regla que importa sigue en pie: fuera del recinto no se elige, así que no
	-- se cambia de ruta a mitad de viaje.
	if not Perimeter.dentro(root.Position, Config.ALMACEN_POS) then
		return false
	end

	estado.ruta = rutaId
	PlayerState.sync(player)
	Telemetry.evento(player, "ruta_elegida", { ruta = rutaId, cajas = #estado.cajas })
	return true
end

-- No sincroniza: quien llame decide cuándo. Antes sí lo hacía, y una sola entrega
-- disparaba TRES envíos del estado completo al cliente (vaciar, limpiar y el sync
-- explícito de entregar), dos de ellos con un estado a medio actualizar que el
-- HUD llegaba a dibujar. Con 30 jugadores entregando eso es tráfico y parpadeo
-- gratis.
function RouteService.limpiar(player: Player)
	local estado = PlayerState.get(player)
	estado.ruta = nil
end

function RouteService.start()
	Remotes.event(Remotes.ELEGIR_RUTA).OnServerEvent:Connect(function(player, rutaId)
		RouteService.elegir(player, rutaId)
	end)
end

return RouteService
