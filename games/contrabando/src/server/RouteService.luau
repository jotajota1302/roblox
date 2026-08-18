--!strict
--[[
	RouteService.luau — elección de ruta y su validación.

	Cinco comprobaciones que el servidor NO se salta, porque cada una es un
	exploit si falta:

	  1. que la ruta exista (un id inventado no cobra nada)
	  2. que lleve carga (elegir ruta sin nada encima no tiene sentido)
	  3. que esté DENTRO DEL RECINTO del almacén (no se cambia de ruta a mitad de
	     viaje, que sería elegir la verde para pasar tranquilo y cambiar a roja al
	     llegar)
	  4. que no esté ya en ruta
	  5. que TENGA LA LICENCIA: nivel suficiente y, en la roja, vehículo de motor
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local RouteService = {}

-- Lo que se le dice al jugador cuando la licencia le cierra una ruta. El texto
-- del nivel se compone con Routes.requisito para que no haya dos sitios diciendo
-- qué hace falta: el día que cambie el nivel pedido, esto cambia solo.
local EXPLICACION: { [string]: string } = {
	necesitas_motor = "Esa ruta pide un vehiculo de motor",
	ruta_desconocida = "Esa ruta no existe",
}

local function avisar(player: Player, texto: string)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, Palette.AVISO_MALO)
end

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
		avisar(player, "Ya vas de camino: entrega antes de elegir otra")
		return false
	end
	-- SIN NADA QUE LLEVAR NO HAY VIAJE, y hay que decirlo. Jugando salió así: con
	-- la bolsa vacía, pulsar un destino no hacía nada -- ni salía ni avisaba-- y
	-- desde dentro eso no se distingue de un juego roto. Es exactamente la lección
	-- que este proyecto ya pagó con el botón de entregar.
	if #estado.cajas == 0 then
		avisar(player, "Coge algo en la nave antes de salir")
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
	if not Perimeter.dentro(root.Position, 25) then
		avisar(player, "La ruta se elige en tu poligono, no a mitad de viaje")
		return false
	end

	-- LA LICENCIA, y se comprueba aquí porque el cliente no decide nada: el
	-- selector pinta en gris lo que no puedes coger, pero un remote manipulado
	-- manda el id que quiera. Sin esta línea, el ×10 de la roja seguiría siendo
	-- gratis para cualquiera que sepa abrir la consola.
	local nivel = Levels.nivelDe(estado.xp or 0)
	local puede, motivo = Routes.disponible(rutaId, nivel, estado.vehiculo)
	if not puede then
		-- Y SE DICE POR QUÉ. Cuatro motivos distintos por los que no se sale se ven
		-- todos igual desde dentro --no pasa nada al pulsar-- y eso se lee como un
		-- juego roto, no como una regla.
		avisar(
			player,
			if motivo == "nivel_insuficiente"
				then string.format("Te falta nivel: %s", Routes.requisito(rutaId))
				else EXPLICACION[motivo] or "Por ahi no puedes salir"
		)
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
