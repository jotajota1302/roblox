--!strict
--[[
	MonetizationService.luau — dinero real. Los dos productos básicos de Roblox:

	  · GAME PASS        compra ÚNICA y permanente. Aquí: "x2 monedas para siempre".
	  · DEVELOPER PRODUCT compra REPETIBLE. Aquí: "+100 monedas" (se puede comprar 50 veces).

	Los dos se pagan en Robux. De cada 100 Robux que gasta el jugador, tú cobras 70
	(Roblox se queda el 30%), y esos 70 Robux valen ~0,27 $ al cambiarlos por dinero
	real. Ver ../../RESEARCH.md para la matemática completa.

	Mientras Config.GAME_PASS_ID y Config.PRODUCT_ID valgan 0, este módulo no hace
	nada: no se pueden crear pases hasta publicar el juego. El código queda listo.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local MonetizationService = {}

-- Historial de compras ya procesadas. Ver la explicación en ProcessReceipt.
local purchaseHistory = DataStoreService:GetDataStore("CoinIsland_Purchases_v1")

local function refreshGamePass(player: Player)
	if Config.GAME_PASS_ID <= 0 then
		return
	end

	-- Las llamadas ...Async hablan con los servidores de Roblox: tardan y pueden
	-- fallar. Siempre dentro de pcall y nunca en un bucle apretado.
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.GAME_PASS_ID)
	end)

	if ok and owns then
		PlayerData.setMultiplier(player, Config.GAME_PASS_MULTIPLIER)
	end
end

function MonetizationService.start()
	Players.PlayerAdded:Connect(refreshGamePass)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshGamePass, player)
	end

	-- Se dispara cuando el jugador cierra la ventana de compra del pase. Sin esto,
	-- tendría que reconectar para que el x2 le hiciera efecto.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if wasPurchased and gamePassId == Config.GAME_PASS_ID then
				PlayerData.setMultiplier(player, Config.GAME_PASS_MULTIPLIER)
			end
		end
	)

	--[[
		ProcessReceipt: Roblox llama a esta función cuando alguien compra un
		developer product. Es la única parte del juego donde hay dinero real de por
		medio, y tiene dos reglas duras:

		  1. Devuelve PurchaseGranted SOLO si has entregado la recompensa de verdad.
		     Si devuelves eso y no la das, el jugador ha pagado por nada.
		  2. Si devuelves NotProcessedYet, Roblox VOLVERÁ A LLAMAR más tarde con el
		     mismo PurchaseId. Por eso hay que guardar los PurchaseId ya servidos:
		     si no, un reintento entregaría la recompensa dos veces gratis.
	]]
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Se ha ido antes de que llegara el recibo: que Roblox lo reintente
			-- cuando vuelva a entrar.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if receiptInfo.ProductId ~= Config.PRODUCT_ID or Config.PRODUCT_ID <= 0 then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local key = "receipt_" .. receiptInfo.PurchaseId

		-- UpdateAsync lee y escribe de forma atómica: dos servidores no pueden
		-- colarse a la vez con el mismo recibo.
		local alreadyProcessed = false
		local ok = pcall(function()
			purchaseHistory:UpdateAsync(key, function(seen)
				if seen then
					alreadyProcessed = true
					return nil -- devolver nil cancela la escritura: no tocamos nada
				end
				return true
			end)
		end)

		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if alreadyProcessed then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		PlayerData.addCoins(player, Config.PRODUCT_COIN_REWARD)
		PlayerData.save(player)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return MonetizationService
