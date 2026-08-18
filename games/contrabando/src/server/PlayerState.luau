--!strict
--[[
	PlayerState.luau — el estado real de cada jugador, en el servidor.

	Esta tabla es la ÚNICA verdad. El cliente recibe copias para dibujarlas; nunca
	al revés. Cualquier cosa que el cliente crea saber puede estar manipulada.
]]

local Players = game:GetService("Players")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)

export type Estado = {
	dinero: number,
	cajas: { Economy.Caja },
	ruta: string?,
	marcadoHasta: number,
	almacenCajas: number,
	-- Lo que hay guardado, PIEZA A PIEZA y con su rareza ya sorteada.
	--
	-- Antes el almacén era sólo un número y la rareza se tiraba en el instante de
	-- recoger, así que no había nada que decidir: pulsabas y te llevabas lo que
	-- cupiera. Con las piezas ya definidas, entrar al almacén es una decisión real
	-- --¿la urna que ocupa el zurrón entero y multiplica x135, o tres cajones?--
	-- y esa decisión se encadena con la de ruta y con el haz que te delata.
	-- `almacenCajas` se mantiene como su cuenta para no obligar a todo lo demás
	-- (HUD, guardado) a saber de esta lista.
	almacen: { Economy.Caja },
	almacenUltimaVisita: number,
	-- nil significa "a pie". Vehicles.deEstado es el único sitio que traduce ese
	-- nil, para que ningún servicio tenga que acordarse de hacerlo.
	vehiculo: string?,
	-- Nivel de calor (0..3). Lo escribe HeatService y viaja al HUD con el sync
	-- normal. Vive aquí y no en una tabla aparte de HeatService porque es lo único
	-- del calor que el cliente necesita, y así no hay un segundo canal que pueda
	-- contradecir al primero en pantalla. NO SE PERSISTE: ver la cabecera de
	-- HeatService.
	calor: number,
	-- Experiencia acumulada. El NIVEL no se guarda: se calcula de aquí con
	-- Levels.nivelDe. Guardar los dos es garantizar que algún día no cuadren, y el
	-- que no cuadrase sería el que ve el jugador.
	xp: number,
	-- La carga de VUELTA que te espera en el destino donde acabas de entregar, y
	-- de qué zona viene (de ahí sale lo que te pagan por ella). Se vacía al
	-- recogerla o al salir otra vez del almacén: es una oferta del momento, no un
	-- segundo almacén que se acumule.
	retorno: { Economy.Caja },
	retornoZona: string?,
	-- ¿Va montado en su vehículo, o lo dejó aparcado al salirse del asfalto?
	-- (ver RoadService). Es del estado y no del dibujo: de esto depende a qué
	-- velocidad anda, y eso no puede decidirlo el cliente.
	montado: boolean?,
	-- EL GARAJE: todo lo que ha comprado, no sólo lo que lleva puesto. Comprar ya
	-- no sustituye -- ver Vehicles.posee y el porqué que hay allí.
	garaje: { string }?,
	-- LO QUE VA EN EL VEHÍCULO cuando lo dejas aparcado. Un repartidor no se echa
	-- veinte bultos a la espalda al bajarse de la furgoneta: se quedan dentro (ver
	-- RoadService, y la medición que lo destapó).
	cajasEnVehiculo: { Economy.Caja }?,
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
			almacenCajas = 3, -- las tres cajas de los primeros cinco segundos
			almacen = {},
			almacenUltimaVisita = os.time(),
			vehiculo = nil,
			calor = 0,
			xp = 0,
			retorno = {},
			retornoZona = nil,
			montado = true,
			garaje = {},
			cajasEnVehiculo = {},
		}
		estados[player] = estado
	end
	return estado
end

-- Igual que get(), pero NUNCA crea estado: devuelve nil si el jugador no tiene uno.
-- Existe para Persistence.guardar (C2): Main.server.luau arranca PlayerState antes
-- que Persistence, así que sus dos manejadores de PlayerRemoving compiten sin orden
-- garantizado por Roblox. Si PlayerState borra primero y Persistence llama a get()
-- después, get() RECREA el estado con los valores por defecto (dinero 0) y eso es
-- justo lo que se guarda en la nube: todo jugador que se desconecta pierde su
-- dinero. peek() no puede envenenar el guardado porque no crea nada que guardar.
function PlayerState.peek(player: Player): Estado?
	return estados[player]
end

function PlayerState.sync(player: Player)
	local estado = PlayerState.get(player)
	local vehiculo = Vehicles.deEstado(estado.vehiculo)
	Remotes.event(Remotes.SYNC_STATE):FireClient(player, {
		dinero = estado.dinero,
		cajas = estado.cajas,
		ruta = estado.ruta,
		marcadoHasta = estado.marcadoHasta,
		almacenCajas = estado.almacenCajas,
		-- Las piezas guardadas, para que el muelle dibuje CADA UNA como lo que es.
		-- Sin esto el cliente sólo sabría cuántas hay y volvería a pintar diez
		-- cajones iguales, que es justo lo que quita la decisión.
		almacen = estado.almacen,
		calor = estado.calor or 0,
		xp = estado.xp or 0,
		retorno = estado.retorno or {},
		retornoZona = estado.retornoZona,
		montado = estado.montado ~= false,
		garaje = estado.garaje or {},
		cajasEnVehiculo = estado.cajasEnVehiculo or {},
		-- El nivel viaja ya calculado: el cliente sólo dibuja, y así no hay dos
		-- sitios haciendo la misma cuenta con riesgo de discrepar en pantalla.
		nivel = Levels.nivelDe(estado.xp or 0),
		progresoNivel = Levels.progreso(estado.xp or 0),
		-- El cliente recibe el vehículo YA resuelto (nunca el nil crudo) y su
		-- capacidad calculada: dibujar "2/10" no debe requerir que el cliente
		-- sepa ninguna regla, porque el cliente no decide nada en este juego.
		vehiculo = vehiculo.id,
		vehiculoNombre = vehiculo.nombre,
		capacidad = vehiculo.capacidad,
		-- Lo que le queda por comprar, ya filtrado por su estado: el taller no
		-- ofrece nada que no sea una mejora.
		mejoras = Vehicles.mejorasPara(estado.garaje),
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
