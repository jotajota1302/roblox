--[[
	Ui.luau — toda la interfaz, construida por código.

	Esto corre en el CLIENTE (el ordenador del jugador). Aquí NO hay ninguna verdad:
	los números que pinta son una copia de lo que el servidor le ha contado por el
	remote SYNC_STATE. Si un jugador hackea esta pantalla y se pone "9999 monedas",
	solo se engaña a sí mismo: el servidor sigue sabiendo que tiene 12.

	La UI de Roblox es como HTML muy simplificado:
	  ScreenGui -> Frame -> TextLabel / TextButton / ImageLabel
	  UDim2.new(escala_x, pixeles_x, escala_y, pixeles_y)  <- % + píxeles a la vez
	  UIListLayout apila hijos automáticamente (como flexbox column)
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local Ui = {}

-- Paleta
local INK = Color3.fromRGB(24, 26, 33)
local PANEL = Color3.fromRGB(38, 41, 52)
local GOLD = Color3.fromRGB(240, 196, 60)
local TEXT = Color3.fromRGB(238, 238, 240)
local MUTED = Color3.fromRGB(150, 154, 168)
local GREEN = Color3.fromRGB(76, 160, 96)

-- Estado local: la última foto que nos mandó el servidor.
local state = { coins = 0, upgrades = {}, multiplier = 1 }
local rows = {} -- referencias a los widgets de cada mejora, para refrescarlos
local coinLabel: TextLabel
local shopFrame: Frame

--[[ Crea una instancia con propiedades e hijos de un tirón. ]]
local function create(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil

	for key, value in props do
		(instance :: any)[key] = value
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	-- El Parent se asigna al final: así Roblox solo recalcula el layout una vez.
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Refresco: repinta los textos con el estado actual
-- ─────────────────────────────────────────────────────────────────────────────

local function refresh()
	if coinLabel then
		local suffix = if state.multiplier > 1 then "  (x" .. state.multiplier .. ")" else ""
		coinLabel.Text = "🪙 " .. state.coins .. suffix
	end

	for _, row in rows do
		local level = state.upgrades[row.id] or 0
		local upgrade = row.upgrade

		row.levelLabel.Text = "Nivel " .. level .. " / " .. upgrade.maxLevel

		if level >= upgrade.maxLevel then
			row.button.Text = "AL MÁXIMO"
			row.button.BackgroundColor3 = PANEL
			row.button.TextColor3 = MUTED
			row.button.Active = false
		else
			local cost = Config.upgradeCost(upgrade, level)
			row.button.Text = "🪙 " .. cost
			row.button.Active = true
			-- Verde si te lo puedes permitir, apagado si no. El servidor lo comprueba
			-- igualmente; esto es solo cortesía visual.
			if state.coins >= cost then
				row.button.BackgroundColor3 = GREEN
				row.button.TextColor3 = TEXT
			else
				row.button.BackgroundColor3 = PANEL
				row.button.TextColor3 = MUTED
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Construcción
-- ─────────────────────────────────────────────────────────────────────────────

local function buildUpgradeRow(upgrade, parent: Instance, order: number)
	local button = create("TextButton", {
		Name = "Buy",
		Size = UDim2.new(0, 96, 0, 40),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = GREEN,
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = "",
		AutoButtonColor = true,
	}, { corner(8) })

	local levelLabel = create("TextLabel", {
		Size = UDim2.new(1, -120, 0, 16),
		Position = UDim2.new(0, 12, 0, 46),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local row = create("Frame", {
		Name = upgrade.id,
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, {
		corner(10),
		create("TextLabel", {
			Size = UDim2.new(1, -120, 0, 20),
			Position = UDim2.new(0, 12, 0, 8),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = upgrade.displayName,
		}),
		create("TextLabel", {
			Size = UDim2.new(1, -120, 0, 16),
			Position = UDim2.new(0, 12, 0, 28),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = upgrade.description,
		}),
		levelLabel,
		button,
	})

	-- Al pulsar, lo ÚNICO que viaja al servidor es el id de la mejora.
	button.MouseButton1Click:Connect(function()
		Remotes.event(Remotes.BUY_UPGRADE):FireServer(upgrade.id)
	end)

	table.insert(rows, {
		id = upgrade.id,
		upgrade = upgrade,
		button = button,
		levelLabel = levelLabel,
	})

	return row
end

local function buildRobuxButton(text: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.fromRGB(60, 66, 84),
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = text,
		LayoutOrder = order,
		Parent = parent,
	}, { corner(8) })

	button.MouseButton1Click:Connect(onClick)
	return button
end

function Ui.start()
	local screen = create("ScreenGui", {
		Name = "CoinIslandUi",
		-- Sin esto, la interfaz se destruye y se recrea cada vez que el jugador muere.
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- ── HUD de monedas (arriba a la izquierda) ──────────────────────────────
	coinLabel = create("TextLabel", {
		Name = "Coins",
		Size = UDim2.new(0, 200, 0, 44),
		Position = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = GOLD,
		Text = "🪙 0",
		Parent = screen,
	}, { corner(10) })

	-- ── Botón de abrir tienda (abajo a la derecha, grande para dedos) ───────
	local openButton = create("TextButton", {
		Name = "OpenShop",
		Size = UDim2.new(0, 150, 0, 52),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = GOLD,
		TextColor3 = INK,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Text = "🛒 Tienda",
		Parent = screen,
	}, { corner(12) })

	-- ── Panel de tienda ─────────────────────────────────────────────────────
	shopFrame = create("Frame", {
		Name = "Shop",
		Size = UDim2.new(0, 440, 0, 470),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screen,
	}, {
		corner(14),
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			TextColor3 = TEXT,
			Text = "Tienda de la isla",
		}),
		create("TextButton", {
			Name = "Close",
			Size = UDim2.new(0, 36, 0, 36),
			Position = UDim2.new(1, -10, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			TextColor3 = MUTED,
			Text = "✕",
		}),
	})

	shopFrame:FindFirstChild("Close").MouseButton1Click:Connect(function()
		shopFrame.Visible = false
	end)
	openButton.MouseButton1Click:Connect(function()
		shopFrame.Visible = not shopFrame.Visible
	end)

	-- Contenedor con UIListLayout: apila los hijos sin calcular posiciones a mano.
	local list = create("Frame", {
		Size = UDim2.new(1, -24, 1, -60),
		Position = UDim2.new(0, 12, 0, 52),
		BackgroundTransparency = 1,
		Parent = shopFrame,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for index, upgrade in Config.UPGRADES do
		buildUpgradeRow(upgrade, list, index)
	end

	-- ── Compras con Robux (dinero real) ─────────────────────────────────────
	local separator = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = MUTED,
		Text = "— Con Robux —",
		LayoutOrder = 100,
		Parent = list,
	})

	buildRobuxButton("💎 x2 monedas para siempre", 101, list, function()
		if Config.GAME_PASS_ID > 0 then
			MarketplaceService:PromptGamePassPurchase(player, Config.GAME_PASS_ID)
		else
			warn("[Ui] Falta configurar GAME_PASS_ID en Config.luau (ver README, paso 6).")
		end
	end)

	buildRobuxButton("💰 +100 monedas", 102, list, function()
		if Config.PRODUCT_ID > 0 then
			MarketplaceService:PromptProductPurchase(player, Config.PRODUCT_ID)
		else
			warn("[Ui] Falta configurar PRODUCT_ID en Config.luau (ver README, paso 6).")
		end
	end)

	-- ── Escuchar al servidor ────────────────────────────────────────────────
	local syncRemote = Remotes.event(Remotes.SYNC_STATE)

	syncRemote.OnClientEvent:Connect(function(newState)
		state = newState
		refresh()
	end)

	refresh()

	-- Ya estamos escuchando: ahora sí, pedimos el estado inicial. Si lo pidiéramos
	-- antes de conectar OnClientEvent, la respuesta podría llegar antes que el
	-- listener y perderíamos la primera foto.
	syncRemote:FireServer()
end

return Ui
