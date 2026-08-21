--!strict
--[[
	Main.server.luau — arranque.

	Dos trampas de Roblox ya pagadas en el piloto, y las dos están resueltas aquí:

	1. El personaje aparece ANTES de que el código construya el mundo, se cae al
	   vacío y Roblox lo destruye a -500 studs. Por eso CharacterAutoLoads = false
	   hasta que hay suelo.
	2. Un require que falla se propaga y mata el script entero, dejando el juego sin
	   mapa y sin ninguna pista del motivo. Por eso todos van dentro de pcall.
]]

local Players = game:GetService("Players")

local Config = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

Players.CharacterAutoLoads = false

local function safeRequire(nombre: string): any
	local ok, resultado = pcall(function()
		return require(script.Parent:WaitForChild(nombre, 10))
	end)
	if not ok then
		warn("[Contrabando] no se pudo cargar " .. nombre .. ": " .. tostring(resultado))
		return nil
	end
	return resultado
end

local function safeStart(nombre: string, modulo: any): boolean
	if not modulo then
		return false
	end
	local ok, err = pcall(function()
		modulo.start()
	end)
	if not ok then
		warn("[Contrabando] fallo al arrancar " .. nombre .. ": " .. tostring(err))
	end
	return ok
end

local CityBuilder = safeRequire("CityBuilder")
local MapBuilder = safeRequire("MapBuilder")
local PlayerState = safeRequire("PlayerState")
local CargoService = safeRequire("CargoService")
local RouteService = safeRequire("RouteService")
local ContactService = safeRequire("ContactService")
local WarehouseService = safeRequire("WarehouseService")
local GarageService = safeRequire("GarageService")
local InterceptService = safeRequire("InterceptService")
local HeatService = safeRequire("HeatService")
local PatrolService = safeRequire("PatrolService")
local RoadService = safeRequire("RoadService")
local Persistence = safeRequire("Persistence")
local Telemetry = safeRequire("Telemetry")
local Nameplates = safeRequire("Nameplates")
local Avatar = safeRequire("Avatar")

-- LOS REMOTES, TODOS, ANTES QUE NADA.
--
-- Hasta hoy cada uno nacia cuando el primer servicio lo usaba, y funcionaba por
-- casualidad: casi todos se tocan al arrancar. `Impulso` --el golpe de camara al
-- coger un rayo-- no; solo se usa al recoger, asi que no existia hasta la primera
-- recogida de la partida, y el cliente lo pide con `WaitForChild`.
--
-- Eso no da error: da un hilo del cliente esperando para siempre a algo que
-- todavia no existe. Lo cazo la sonda del mundo --*faltan: Impulso*-- y la
-- respuesta correcta no es tocar ese remote, es dejar de depender de la suerte:
-- se crean los que declara `Remotes`, sin excepciones, antes de que haya nadie
-- conectado.
for clave, valor in Remotes :: any do
	if type(clave) == "string" and type(valor) == "string" then
		Remotes.event(valor)
	end
end

-- A DONDE SE ENTREGA EN ESTA PARTIDA, y va ANTES que todo lo demas.
--
-- *"La ruta verde parece que siempre es la misma, deberia ir cambiando de manera
-- aleatoria"* (JJ). Los tres destinos eran constantes en `Config`, asi que la
-- primera ruta del juego llevaba siempre al mismo portal, por la misma calle, con
-- las migas en los mismos cuatro sitios.
--
-- El orden es lo que hace que esto sea barato: del destino cuelgan las migas, los
-- detectores, las guaridas, los refugios, la casa de entrega y el GPS, y sortearlo
-- DESPUES de construir obligaria a mover una docena de sistemas a la vez. Sorteado
-- antes, todo se siembra ya en el sitio nuevo y ningun sistema se entera.
--
-- La semilla sale de la hora de arranque: cada servidor reparte distinto. Ver
-- `Destinations.luau`.
local Destinations = safeRequire("Destinations")
if Destinations then
	local ok, elegidos = pcall(Destinations.sortear, os.time())
	if ok then
		local partes = {}
		for id, sitio in elegidos do
			table.insert(partes, string.format("%s -> (%.0f, %.0f)", id, sitio.X, sitio.Z))
		end
		table.sort(partes)
		print("[Contrabando] destinos de esta partida: " .. table.concat(partes, " | "))
	else
		warn("[Contrabando] no se pudieron sortear los destinos: " .. tostring(elegidos))
	end
end

-- El mundo primero: la ciudad, y el juego encima.
--
-- HAY DOS FORMAS DE TENER CIUDAD Y NO PUEDEN CONVIVIR A LA VEZ:
--
--   · el modelo del Creator Store, que Rojo monta como Workspace.Ciudad desde
--     mapa/Ciudad.rbxm (bloque "Ciudad" de default.project.json);
--   · MapBuilder, que la genera por código.
--
-- Las dos dejan exactamente el mismo contrato -- un Model llamado "Ciudad" que
-- CityBuilder usa de suelo para sus raycasts -- así que se eligen sin tocar nada
-- más. Lo que NO puede pasar es que corran las dos: serían dos ciudades enteras
-- superpiestas en las mismas coordenadas, 14.000 piezas en el sitio de 7.000. No
-- es hipotético: ya ocurrió con tres copias a la vez y hubo que limpiarlo a mano.
--
-- Manda lo que haya montado Rojo. Poner o quitar el bloque "Ciudad" del
-- default.project.json es lo único que cambia entre un modo y otro.
if MapBuilder and workspace:FindFirstChild("Ciudad") == nil then
	local ok, err = pcall(function()
		MapBuilder.buildCiudad(workspace)
	end)
	if not ok then
		-- Si falla, CityBuilder cae a su explanada de respaldo: sin ciudad el juego
		-- es feo, pero se puede jugar y medir.
		warn("[Contrabando] no se pudo construir la ciudad procedural: " .. tostring(err))
	end
end

local mundo = nil
if CityBuilder then
	local ok, resultado = pcall(CityBuilder.build)
	if ok then
		mundo = resultado
	else
		warn("[Contrabando] el mundo no se pudo construir: " .. tostring(resultado))
	end
end

if not mundo then
	-- Suelo de emergencia: prefiero un jugador sobre una plancha gris a un jugador
	-- cayendo al vacío sin entender nada. Va bajo el ALMACÉN, no bajo el (0,0,0):
	-- ahí es donde aparece el jugador desde que el juego vive dentro de la ciudad,
	-- y una plancha en el origen lo dejaría cayendo igualmente.
	local suelo = Instance.new("Part")
	suelo.Name = "SueloDeEmergencia"
	suelo.Size = Vector3.new(400, 1, 400)
	suelo.Position = Vector3.new(Config.ALMACEN_POS.X, Config.ALMACEN_POS.Y, Config.ALMACEN_POS.Z)
	suelo.Anchored = true
	suelo.Parent = workspace
end

safeStart("PlayerState", PlayerState)
safeStart("CargoService", CargoService)
safeStart("RouteService", RouteService)
safeStart("WarehouseService", WarehouseService)
safeStart("GarageService", GarageService)
safeStart("InterceptService", InterceptService)
safeStart("HeatService", HeatService)
safeStart("PatrolService", PatrolService)
safeStart("RoadService", RoadService)
safeStart("ContactService", ContactService)
safeStart("Telemetry", Telemetry)
safeStart("Persistence", Persistence)
safeStart("Nameplates", Nameplates)

if mundo then
	if RouteService then
		RouteService.registrarSalida(mundo.salida)
	end
	if CargoService then
		for _, destino in mundo.destinos do
			CargoService.registrarDestino(destino)
		end
	end
	if WarehouseService then
		WarehouseService.registrarAlmacen(mundo.almacen)
	end
	if GarageService then
		for _, taller in mundo.talleres do
			GarageService.registrarTaller(taller)
		end
	end
	if HeatService then
		for _, poste in mundo.detectores do
			HeatService.registrarDetector(poste)
		end
		-- Los refugios se registran en HeatService y NO en cada servicio que los
		-- necesita: el calor, las patrullas y el robo preguntan todos ahí. Con tres
		-- copias de la lista, el día que una se quede sin actualizar habría un
		-- refugio que protege del robo pero no de la policía, y el jugador no
		-- tendría forma de saber cuál.
		HeatService.registrarRefugios(mundo.refugios)
		-- Y las guaridas a PatrolService, que es quien suelta a los ladrones desde
		-- ellas. Mismo motivo que los refugios: el servicio no las busca por su
		-- cuenta en workspace, porque entonces cada uno tendría su propia idea de
		-- qué cuenta como guarida.
		if PatrolService and (PatrolService :: any).registrarGuaridas then
			(PatrolService :: any).registrarGuaridas(mundo.guaridas or {})
		end
		-- Y los contactos a su servicio, por lo mismo: las piezas las planta
		-- CityBuilder (que es quien sabe bajar algo al suelo de una ciudad ajena sin
		-- dejarlo en un tejado) y las reglas de quién recoge son de ContactService.
		if ContactService then
			ContactService.registrar(mundo.contactos or {})
			ContactService.registrarAlijos(mundo.alijos or {})
		end
	end
end

-- Los personajes, al final del todo y por su propio módulo. Antes se hacía aquí
-- con un LoadCharacter suelto, y con el place sin publicar eso da un avatar R15
-- cuyas mallas no se pueden descargar: un personaje invisible que camina. Ver la
-- cabecera de Avatar.luau, que cuenta la investigación entera.
if Avatar then
	if mundo then
		Avatar.registrarAparicion(mundo.aparicion)
	end
	safeStart("Avatar", Avatar)
else
	-- Sin el módulo, mejor un avatar invisible que ningún personaje: al menos se
	-- puede andar y el resto del juego responde.
	warn("[Contrabando] sin modulo Avatar: se cargan personajes por defecto")
	Players.CharacterAutoLoads = true
	Players.PlayerAdded:Connect(function(player)
		player:LoadCharacter()
	end)
	for _, player in Players:GetPlayers() do
		if not player.Character then
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

print("[Contrabando] servidor listo")
