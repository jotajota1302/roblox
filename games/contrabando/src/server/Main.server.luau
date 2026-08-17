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

local WorldBuilder = safeRequire("WorldBuilder")
local PlayerState = safeRequire("PlayerState")
local CargoService = safeRequire("CargoService")
local RouteService = safeRequire("RouteService")
local WarehouseService = safeRequire("WarehouseService")
local InterceptService = safeRequire("InterceptService")
local Persistence = safeRequire("Persistence")
local Telemetry = safeRequire("Telemetry")

-- El mundo primero: sin suelo no puede entrar nadie.
local mundo = nil
if WorldBuilder then
	local ok, resultado = pcall(WorldBuilder.build)
	if ok then
		mundo = resultado
	else
		warn("[Contrabando] el mundo no se pudo construir: " .. tostring(resultado))
	end
end

if not mundo then
	-- Suelo de emergencia: prefiero un jugador sobre una plancha gris a un jugador
	-- cayendo al vacío sin entender nada.
	local suelo = Instance.new("Part")
	suelo.Name = "SueloDeEmergencia"
	suelo.Size = Vector3.new(400, 1, 400)
	suelo.Position = Vector3.new(0, 0, 0)
	suelo.Anchored = true
	suelo.Parent = workspace
end

safeStart("PlayerState", PlayerState)
safeStart("CargoService", CargoService)
safeStart("RouteService", RouteService)
safeStart("WarehouseService", WarehouseService)
safeStart("InterceptService", InterceptService)
safeStart("Telemetry", Telemetry)
safeStart("Persistence", Persistence)

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
end

local function colocar(player: Player)
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(colocar)
Players.CharacterAutoLoads = true

for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(colocar, player)
	end
end

print("[Contrabando] servidor listo")
