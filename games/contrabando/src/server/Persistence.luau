--!strict
--[[
	Persistence.luau — guardado en la nube.

	LA TRAMPA QUE COSTÓ TRES RONDAS DE DEPURACIÓN EN EL PILOTO:
	DataStoreService:GetDataStore() LANZA UNA EXCEPCIÓN si el place no está
	publicado. Llamarlo al cargar el módulo hace que el require reviente y mate el
	script entero: juego sin mapa, sin personaje y sin ninguna pista del motivo.

	Por eso el store se resuelve PEREZOSAMENTE y dentro de pcall. Sin place
	publicado el juego funciona igual, sólo que no guarda.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Goals = require(game.ReplicatedStorage.Shared.Goals)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local Warehouse = require(game.ReplicatedStorage.Shared.Warehouse)
local PlayerState = require(script.Parent.PlayerState)
local WarehouseService = require(script.Parent.WarehouseService)

local NOMBRE_STORE = "ContrabandoV1"

local store: DataStore? = nil
local resuelto = false

local Persistence = {}

local function getStore(): DataStore?
	if resuelto then
		return store
	end
	resuelto = true

	local ok, resultado = pcall(function()
		return DataStoreService:GetDataStore(NOMBRE_STORE)
	end)

	if ok then
		store = resultado
	else
		warn("[Contrabando] se juega sin guardar en la nube: " .. tostring(resultado))
	end
	return store
end

function Persistence.cargar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	local ok, datos = pcall(function()
		return ds:GetAsync("jugador_" .. player.UserId)
	end)
	if not ok or type(datos) ~= "table" then
		return
	end

	local estado = PlayerState.get(player)
	estado.dinero = tonumber(datos.dinero) or estado.dinero
	-- La experiencia es lo ÚNICO que no se puede gastar, así que es lo que más duele
	-- perder: el dinero se recupera con un par de viajes y el nivel no. Se acepta
	-- con math.max(0, ...) para que un dato corrupto no deje a nadie en negativo.
	estado.xp = math.max(0, tonumber(datos.xp) or estado.xp or 0)
	-- Los contactos y las habilidades, por el mismo motivo que la experiencia: se
	-- ganan jugando y no se pueden recomprar. Skills.normalizar es la aduana --
	-- recorta lo que venga guardado mal, porque un peldaño inflado una vez valdría
	-- para siempre.
	estado.contactos = math.max(0, math.floor(tonumber(datos.contactos) or estado.contactos or 0))
	estado.habilidades = Skills.normalizar(datos.habilidades)
	estado.entregas = math.max(0, math.floor(tonumber(datos.entregas) or estado.entregas or 0))
	-- Goals.sanear es la aduana, y aquí importa más que en ningún otro campo: un
	-- hito guardado que hoy no existe (o inventado) abriría una ruta.
	estado.hitos = Goals.sanear(datos.hitos)
	estado.almacenCajas = tonumber(datos.almacenCajas) or estado.almacenCajas
	estado.almacenUltimaVisita = tonumber(datos.almacenUltimaVisita) or estado.almacenUltimaVisita
	-- El vehículo se valida contra el catálogo antes de aceptarlo. Lo guardado
	-- ayer puede ser un id que hoy ya no existe (se retira un vehículo, se
	-- renombra), y Vehicles.get revienta ante un desconocido: sin este filtro,
	-- un cambio de catálogo dejaría a esos jugadores sin poder entrar.
	-- EL GARAJE, saneado por Vehicles: los ids que ya no existan (un vehículo
	-- retirado del catálogo) se caen solos, y el `vehiculo` suelto de las partidas
	-- anteriores al garaje entra como una plaza más. Sin eso, estrenar el garaje
	-- habría dejado a pie a todo el que ya jugaba.
	estado.garaje = Vehicles.garajeDe(datos.garaje, datos.vehiculo)
	if Vehicles.existe(datos.vehiculo) then
		estado.vehiculo = datos.vehiculo
	end
	-- LA NAVE. Se recorta al rango que exista hoy: una partida guardada con más
	-- escalones de los que tiene esta versión (o un dato corrupto) no puede dejar
	-- el almacén sin responder. Warehouse.mejora ya sanea, pero el número que se
	-- guarda tiene que estar sano también, o al volver a guardar se propaga.
	estado.naveNivel = math.clamp(math.floor(tonumber(datos.naveNivel) or 1), 1, Warehouse.maximo())
	PlayerState.sync(player)

	-- Y AHORA, no antes: la bienvenida cuenta lo que ha producido la nave mientras
	-- no estabas, y eso sólo se puede calcular con la hora de la última visita ya
	-- cargada. Va protegida porque es un adorno: que falle no puede impedir entrar.
	local okBienvenida, err = pcall(WarehouseService.bienvenida, player)
	if not okBienvenida then
		warn("[Contrabando] fallo en la bienvenida: " .. tostring(err))
	end
end

function Persistence.guardar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	-- peek(), NUNCA get(): Main.server.luau arranca PlayerState antes que
	-- Persistence, así que sus dos manejadores de PlayerRemoving se disparan en ese
	-- orden pero Roblox no lo garantiza. Si PlayerState.get(player) se llamara aquí
	-- después de que PlayerState ya haya borrado el estado, RECREARÍA uno con los
	-- valores por defecto (dinero 0) y eso es justo lo que se guardaría en la nube.
	-- Sin estado que leer, no hay nada que guardar: se sale.
	local estado = PlayerState.peek(player)
	if not estado then
		return
	end
	-- La carga que lleva encima NO se guarda a propósito: si la partida se corta a
	-- mitad de viaje, el riesgo asumido se resuelve como una pérdida. Guardarla
	-- convertiría desconectarse en un escudo perfecto contra el robo.
	-- El vehículo SÍ se guarda, al contrario que la carga: es una compra, no un
	-- riesgo asumido. Perder por una desconexión lo que has pagado con 1.500
	-- monedas es la clase de agravio que hace desinstalar.
	local datos = {
		dinero = estado.dinero,
		xp = estado.xp or 0,
		contactos = estado.contactos or 0,
		habilidades = estado.habilidades or {},
		entregas = estado.entregas or 0,
		hitos = estado.hitos or {},
		-- `recogidos` NO se guarda: la racha es del viaje, y volver con la de ayer
		-- sería premio por desconectarse. Misma regla que el calor.
		almacenCajas = estado.almacenCajas,
		almacenUltimaVisita = os.time(),
		vehiculo = estado.vehiculo,
		-- La lista entera, no sólo el que lleva puesto: si sólo se guardara el
		-- activo, salir del juego con el patinete fuera borraría la furgoneta.
		garaje = estado.garaje or {},
		-- La nave mejorada es lo más caro que se puede comprar en el juego: si esto
		-- no se guardara, una desconexión costaría hasta 150.000 monedas.
		naveNivel = estado.naveNivel or 1,
	}

	local ok, err = pcall(function()
		ds:SetAsync("jugador_" .. player.UserId, datos)
	end)
	if not ok then
		warn("[Contrabando] no se pudo guardar: " .. tostring(err))
	end
end

function Persistence.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(Persistence.cargar, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Persistence.guardar(player)
	end)

	-- Guardado periódico: si el servidor cae, PlayerRemoving no llega.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				task.spawn(Persistence.guardar, player)
			end
		end
	end)

	game:BindToClose(function()
		local jugadores = Players:GetPlayers()
		local pendientes = #jugadores

		-- En paralelo, no en serie: antes se guardaba jugador por jugador, y con un
		-- servidor lleno eso son decenas de escrituras seguidas contra un
		-- presupuesto de cierre limitado. task.spawn lanza todas a la vez.
		for _, player in jugadores do
			task.spawn(function()
				Persistence.guardar(player)
				pendientes -= 1
			end)
		end

		-- Se espera activamente a que el contador llegue a cero, con un tope para
		-- no comerse todo el presupuesto de cierre si alguna escritura se cuelga.
		local limite = os.clock() + 25
		while pendientes > 0 and os.clock() < limite do
			task.wait(0.1)
		end

		-- El margen final que ya existía antes de paralelizar se conserva igual.
		task.wait(2)
	end)
end

return Persistence
