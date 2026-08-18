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
local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local CargoService = require(script.Parent.CargoService)
local Ride = require(script.Parent.Ride)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

-- 60 y no 35: el taller creció a 96x60 studs (escaparate + garaje) y con el radio
-- viejo, estar de pie en las plazas del fondo YA CONTABA COMO ESTAR FUERA -- se
-- pulsaba comprar y no pasaba nada. "Intento comprar un vehículo y no funciona"
-- (JJ). Cualquier radio menor que la propia losa es un fallo esperando.
local DISTANCIA_TALLER = 60

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
	no_es_tuyo = "Ese vehiculo no es tuyo",
	ya_lo_llevas = "Ya lo llevas puesto",
	nivel_insuficiente = "Te falta nivel para ese vehiculo",
}

local GarageService = {}
-- VARIOS TALLERES, no uno. Hay uno en tu recinto y otro junto a cada destino
-- (decisión de JJ): cambiar de vehículo no puede costar un viaje entero de ida y
-- vuelta al almacén, que es lo que pasaba con un único taller en casa.
--
-- El ALMACÉN sigue siendo único a propósito, y no es lo mismo: el almacén es el
-- sitio al que volvéis todos --lo que hace que os crucéis-- y repartirlo por el
-- mapa dejaría a cada jugador en su esquina. El taller no mueve el bucle: sólo
-- es donde se gasta.
local talleres: { BasePart } = {}

function GarageService.registrarTaller(part: BasePart)
	table.insert(talleres, part)
end

function GarageService.enElTaller(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, taller in talleres do
		if (root.Position - taller.Position).Magnitude <= DISTANCIA_TALLER then
			return true
		end
	end
	return false
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

	-- CON CARGA SÍ SE PUEDE COMPRAR. Antes no, y era una regla heredada de cuando
	-- comprar SUSTITUÍA el vehículo: cambiar de montura con el zurrón lleno abría
	-- la pregunta de dónde va lo que ya no cabe. Con el garaje eso ya no pasa --
	-- lo comprado se guarda-- y la regla sólo servía para que JJ pulsara comprar,
	-- no pasara nada, y sólo se enterase por un aviso de tres segundos.
	--
	-- Lo que sí se respeta es no cambiar de vehículo a mitad de viaje: con carga
	-- encima, la compra va al garaje y sigues con el que llevas puesto.
	-- EL NIVEL ENTRA EN LA COMPRA. Es la mitad de la licencia (RUMBO.md §3.A): la
	-- otra mitad son las rutas. El nivel se calcula de la experiencia, nunca se
	-- guarda aparte -- dos fuentes para lo mismo acaban discrepando, y la que
	-- discrepara aquí abriría o cerraría el taller sin motivo visible.
	local nivel = Levels.nivelDe(estado.xp or 0)
	local puede, motivo = Vehicles.puedeComprar(estado.garaje, vehiculoId, estado.dinero, nivel)
	if not puede then
		return false, motivo
	end

	local def = Vehicles.get(vehiculoId)
	-- Cobrar ANTES de entregar. Al revés, cualquier fallo entre las dos líneas
	-- regala el vehículo, y ese es el orden que se olvida en todas las tiendas.
	estado.dinero -= def.coste
	-- SE AÑADE al garaje, no sustituye. Y se saca al momento, que es lo que
	-- espera quien acaba de pagar.
	estado.garaje = Vehicles.garajeDe(estado.garaje, estado.vehiculo)
	table.insert(estado.garaje, def.id)
	-- Se saca al momento SÓLO si vas de vacío: con carga encima cambiar de
	-- vehículo cambiaría tu capacidad a mitad de viaje.
	local loSaca = #estado.cajas == 0
	if loSaca then
		estado.vehiculo = def.id
		estado.montado = true
	end

	CargoService.aplicarVelocidad(player)
	-- Y se VE al instante. Sin esto, pagar 4.500 por una moto cambia dos numeros en
	-- un panel y el jugador sigue siendo el mismo muneco andando -- que es la forma
	-- mas rapida de que una compra no se sienta como una compra.
	if loSaca then
		Ride.montar(player.Character, def.id)
	end
	PlayerState.sync(player)

	Telemetry.evento(player, "compra_vehiculo", { vehiculo = def.id, coste = def.coste })
	Remotes.event(Remotes.AVISO):FireClient(
		player,
		if loSaca
			then string.format("%s: llevas %d huecos y cosas mas grandes", def.nombre, def.capacidad)
			else string.format("%s guardado en el garaje: sacalo al descargar", def.nombre),
		VERDE
	)
	-- Y CÓMO SE USA, justo después de pagarlo. Es el único instante en que el
	-- jugador está seguro de estar mirando la pantalla por este motivo, y hasta
	-- ahora la tecla para bajarse no se decía en ningún sitio ("no se sabe cómo se
	-- hace", JJ). Va con retraso para no pisar el aviso de la compra.
	if loSaca then
		task.delay(2.2, function()
			Remotes.event(Remotes.AVISO):FireClient(player, "Pulsa V para bajarte o subirte", VERDE)
		end)
	end
	Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")

	return true, "ok"
end

-- SACAR UN VEHÍCULO DEL GARAJE. Es la otra mitad de tenerlos: sin esto, comprar
-- un patinete teniendo furgoneta sería tirar el dinero.
--
-- Las mismas dos condiciones que comprar --estar en el taller y no llevar carga--
-- y por los mismos motivos: cambiar de vehículo a mitad de viaje sería sacarse
-- una furgoneta de la manga al ver llegar a un ladrón, y hacerlo con el zurrón
-- lleno abriría la pregunta de dónde va la carga que ya no cabe.
function GarageService.sacar(player: Player, vehiculoId: string?): (boolean, string)
	if vehiculoId ~= nil and typeof(vehiculoId) ~= "string" then
		return false, "vehiculo_desconocido"
	end
	local estado = PlayerState.get(player)
	if not GarageService.enElTaller(player) then
		return false, "lejos"
	end
	if #estado.cajas > 0 then
		return false, "con_carga"
	end
	local puede, motivo = Vehicles.puedeSacar(estado.garaje, vehiculoId)
	if not puede then
		return false, motivo
	end
	local def = Vehicles.deEstado(vehiculoId)
	if def.id == (estado.vehiculo or Vehicles.A_PIE) and estado.montado ~= false then
		return false, "ya_lo_llevas"
	end

	estado.vehiculo = def.id
	estado.montado = true
	CargoService.aplicarVelocidad(player)
	Ride.montar(player.Character, if def.id == Vehicles.A_PIE then nil else def.id)
	PlayerState.sync(player)

	Telemetry.evento(player, "saca_vehiculo", { vehiculo = def.id })
	Remotes.event(Remotes.AVISO):FireClient(player, "Sacas " .. def.nombre, VERDE)
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

	Remotes.event(Remotes.SACAR).OnServerEvent:Connect(function(player, vehiculoId)
		local ok, motivo = GarageService.sacar(player, vehiculoId)
		if not ok and GarageService.enElTaller(player) then
			Remotes.event(Remotes.AVISO):FireClient(player, EXPLICACION[motivo] or "No se puede sacar", ROJO)
		end
	end)

	-- El vehículo inicial no se compra: existe para que Config.VEHICULO_INICIAL
	-- sea de verdad la única definición de "con qué empiezas". Si alguien lo
	-- cambiara a "furgoneta", esto lo daría por bueno sin tocar nada más.
	assert(Vehicles.existe(Config.VEHICULO_INICIAL), "VEHICULO_INICIAL no existe en Config.VEHICULOS")
end

return GarageService
