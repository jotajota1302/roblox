--[[
	Main.server.luau — punto de entrada del SERVIDOR.

	El sufijo ".server" le dice a Rojo que esto es un Script (código de servidor).
	Sin sufijo sería un ModuleScript, y con ".client" un LocalScript.

	Roblox ejecuta todos los Scripts de ServerScriptService a la vez y sin orden
	garantizado. Por eso solo hay UN script de arranque, y todo lo demás son módulos
	que él enciende en el orden correcto. Así el orden es explícito y se lee de un vistazo.
]]

local Players = game:GetService("Players")

--[[
	require() protegido.

	Un error en el nivel superior de CUALQUIER módulo se propaga al require y mata
	este script entero, dejando el juego sin mapa, sin monedas y sin personaje. Nos
	pasó de verdad: PlayerData llamaba a DataStoreService:GetDataStore(), que lanza
	si el place no está publicado. Un fallo así debe degradar el juego, no apagarlo.
]]
local function safeRequire(name: string): any
	local ok, result = pcall(function()
		return require(script.Parent:WaitForChild(name, 10))
	end)
	if not ok then
		warn("[Isla de Monedas] ✖ No se pudo cargar " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

local WorldBuilder = safeRequire("WorldBuilder")
local PlayerData = safeRequire("PlayerData")
local ShopService = safeRequire("ShopService")
local CoinService = safeRequire("CoinService")
local MonetizationService = safeRequire("MonetizationService")

--[[
	IMPORTANTE — carrera de arranque.

	Roblox hace aparecer al personaje en cuanto el jugador entra, SIN esperar a que
	nuestros scripts hayan terminado. Como el mapa lo construimos nosotros por código,
	el jugador aparecía antes de que existiera el suelo: caía al vacío y, al pasar de
	-500 studs, Roblox destruía su personaje. Se veía como "aparece un instante y
	desaparece".

	La solución estándar: desactivar la aparición automática, montar el mundo, y
	volver a activarla cuando ya hay suelo bajo los pies.
]]
Players.CharacterAutoLoads = false

--[[
	Arranque a prueba de fallos.

	Si un servicio revienta, el resto del juego debe seguir en pie y el jugador debe
	aparecer igualmente. Sin esto, un error en cualquier módulo dejaba la partida sin
	personaje (porque nunca se llegaba a reactivar CharacterAutoLoads) y sin ninguna
	pista de qué había fallado.
]]
local function safeStart(name: string, module: any, method: string): boolean
	if not module then
		return false -- no se pudo cargar; safeRequire ya avisó
	end

	local ok, err = pcall(function()
		module[method]()
	end)

	if not ok then
		warn("[Isla de Monedas] ✖ Fallo en " .. name .. ": " .. tostring(err))
	else
		print("[Isla de Monedas] ✔ " .. name)
	end
	return ok
end

-- 1. El mapa primero: las monedas necesitan las plataformas ya creadas.
local worldOk = safeStart("WorldBuilder", WorldBuilder, "build")

-- Red de seguridad: sin suelo, el jugador cae al vacío y muere en bucle.
if not worldOk or not workspace:FindFirstChild("Island") then
	warn("[Isla de Monedas] Sin mapa: creo un suelo de emergencia para no caer al vacío.")
	local ground = Instance.new("Part")
	ground.Name = "EmergencyGround"
	ground.Size = Vector3.new(200, 4, 200)
	ground.Position = Vector3.new(0, -2, 0)
	ground.Anchored = true
	ground.Parent = workspace
end

-- 2. Los datos antes que nada que sume o gaste monedas.
safeStart("PlayerData", PlayerData, "start")

-- 3. Servicios de juego.
safeStart("ShopService", ShopService, "start")
safeStart("CoinService", CoinService, "start")
safeStart("MonetizationService", MonetizationService, "start")

-- 4. Pase lo que pase: que aparezcan los personajes.
Players.CharacterAutoLoads = true

-- Los que ya estaban dentro (en Studio, tú mismo) no se cargan solos: hay que pedirlo.
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

print("[Isla de Monedas] Servidor listo.")
