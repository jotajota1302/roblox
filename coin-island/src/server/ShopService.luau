--!strict
--[[
	ShopService.luau — comprar mejoras. El módulo más importante para entender
	la SEGURIDAD en Roblox.

	El cliente solo puede decir: "quiero comprar la mejora 'speed'". Nada más.
	No manda el precio, ni cuántas monedas tiene, ni el nivel resultante. Todo eso
	lo decide el servidor consultando SUS datos. Un jugador con exploit puede llamar
	al remote con basura, mil veces por segundo, o con un id inventado: cada una de
	esas situaciones está contemplada abajo.

	Si esto estuviera en el cliente, el primer chaval con un exploit se pondría
	velocidad 500 y monedas infinitas. Es literalmente el error nº1 de los novatos.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local ShopService = {}

local lastRequest: { [Player]: number } = {}
local lastSync: { [Player]: number } = {}
local REQUEST_COOLDOWN = 0.1 -- máximo 10 peticiones por segundo y jugador

--[[ Traduce los niveles de mejora a propiedades reales del personaje. ]]
local function applyToCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local speedUpgrade = Config.findUpgrade("speed")
	local jumpUpgrade = Config.findUpgrade("jump")

	local speedLevel = PlayerData.getUpgradeLevel(player, "speed")
	local jumpLevel = PlayerData.getUpgradeLevel(player, "jump")

	humanoid.WalkSpeed = Config.BASE_WALK_SPEED + speedLevel * (speedUpgrade and speedUpgrade.perLevel or 0)

	-- Los personajes R15 modernos usan JumpHeight por defecto; forzamos JumpPower
	-- para que el número de la tienda signifique algo concreto.
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.BASE_JUMP_POWER + jumpLevel * (jumpUpgrade and jumpUpgrade.perLevel or 0)
end

ShopService.applyToCharacter = applyToCharacter

--[[ Manda al cliente su estado real, para que la interfaz pinte números correctos. ]]
local function pushState(player: Player)
	local session = PlayerData.get(player)
	if not session then
		return
	end

	Remotes.event(Remotes.SYNC_STATE):FireClient(player, {
		coins = session.coins,
		upgrades = session.upgrades,
		multiplier = session.multiplier,
	})
end

function ShopService.start()
	local buyRemote = Remotes.event(Remotes.BUY_UPGRADE)

	buyRemote.OnServerEvent:Connect(function(player: Player, upgradeId: any)
		-- 1. Limitar el ritmo. Un cliente hostil puede llamar en bucle infinito.
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now

		-- 2. Comprobar el TIPO. El cliente puede mandar una tabla, nil, un número...
		if type(upgradeId) ~= "string" then
			return
		end

		-- 3. Comprobar que la mejora existe de verdad.
		local upgrade = Config.findUpgrade(upgradeId)
		if not upgrade then
			return
		end

		-- 4. Comprobar el tope de nivel.
		local level = PlayerData.getUpgradeLevel(player, upgradeId)
		if level >= upgrade.maxLevel then
			return
		end

		-- 5. El precio lo calcula el SERVIDOR, no el cliente.
		local cost = Config.upgradeCost(upgrade, level)
		if not PlayerData.trySpend(player, cost) then
			return -- no tenía suficientes monedas
		end

		-- 6. Solo ahora se aplica el efecto.
		PlayerData.setUpgradeLevel(player, upgradeId, level + 1)
		applyToCharacter(player)
	end)

	-- Cada vez que cambian los datos de alguien, se los reenviamos a su cliente.
	PlayerData.onChanged(pushState)

	--[[
		El mismo remote, en la otra dirección: el cliente pide "mándame mi estado".

		Hace falta por una carrera de tiempos muy típica en Roblox: el servidor carga
		los datos del jugador y dispara SYNC_STATE, pero el cliente puede no haber
		terminado de montar su interfaz todavía, así que se pierde ese primer mensaje
		y se queda mostrando 0 monedas. Con esto, es el cliente quien avisa de que ya
		está listo.
	]]
	local syncRemote = Remotes.event(Remotes.SYNC_STATE)
	syncRemote.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastSync[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastSync[player] = now
		pushState(player)
	end)

	local function hookCharacter(player: Player)
		-- CharacterAdded se dispara al entrar y CADA VEZ que reapareces tras morir.
		-- Las propiedades del Humanoid se reinician, así que hay que reaplicarlas.
		player.CharacterAdded:Connect(function()
			task.wait(0.1) -- pequeño margen para que el Humanoid termine de montarse
			applyToCharacter(player)
		end)
		if player.Character then
			applyToCharacter(player)
		end
	end

	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastSync[player] = nil
	end)
end

return ShopService
