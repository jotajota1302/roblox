--[[
	Main.server.luau — punto de entrada del SERVIDOR.

	El sufijo ".server" le dice a Rojo que esto es un Script (código de servidor).
	Sin sufijo sería un ModuleScript, y con ".client" un LocalScript.

	Roblox ejecuta todos los Scripts de ServerScriptService a la vez y sin orden
	garantizado. Por eso solo hay UN script de arranque, y todo lo demás son módulos
	que él enciende en el orden correcto. Así el orden es explícito y se lee de un vistazo.
]]

local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local CoinService = require(script.Parent:WaitForChild("CoinService"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))

-- 1. El mapa primero: las monedas necesitan las plataformas ya creadas.
WorldBuilder.build()

-- 2. Los datos antes que nada que sume o gaste monedas.
PlayerData.start()

-- 3. Servicios de juego.
ShopService.start()
CoinService.start()
MonetizationService.start()

print("[Isla de Monedas] Servidor listo.")
