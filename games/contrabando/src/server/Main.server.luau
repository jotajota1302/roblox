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
local WarehouseService = safeRequire("WarehouseService")
local GarageService = safeRequire("GarageService")
local InterceptService = safeRequire("InterceptService")
local HeatService = safeRequire("HeatService")
local PatrolService = safeRequire("PatrolService")
local Persistence = safeRequire("Persistence")
local Telemetry = safeRequire("Telemetry")
local Nameplates = safeRequire("Nameplates")
local Avatar = safeRequire("Avatar")

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
		GarageService.registrarTaller(mundo.taller)
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
