--!strict
--[[
	PlayerData.luau — el estado de cada jugador y su guardado en la nube.

	Vive en ServerScriptService, así que SOLO existe en el servidor. El jugador no
	puede leer ni tocar este código. Todo lo que sea "verdad" del juego (cuántas
	monedas tienes) vive aquí, nunca en el cliente.

	Guardado: DataStoreService es la base de datos gratuita de Roblox. Guarda una
	tabla por clave (aquí: "player_<UserId>") y persiste entre sesiones y servidores.

	OJO EN STUDIO: por defecto Studio NO puede tocar DataStores. Hay que activarlo en
	  Home > Game Settings > Security > "Enable Studio Access to API Services"
	Si no lo activas el juego funciona igual, pero no guarda (verás un aviso en la consola).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

export type Session = {
	coins: number,
	totalCollected: number,
	upgrades: { [string]: number },
	multiplier: number, -- 1 normalmente, 2 con el pase. No se guarda: se recalcula al entrar.
	loaded: boolean, -- false hasta que sabemos si había partida guardada
}

local PlayerData = {}

local store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
local sessions: { [Player]: Session } = {}
local listeners: { (Player) -> () } = {}
local dataStoreWorks = true

-- ─────────────────────────────────────────────────────────────────────────────
-- Notificación de cambios
-- Otros módulos (la UI, la tienda) se apuntan aquí para enterarse de que los
-- datos de un jugador han cambiado, en vez de preguntar en bucle.
-- ─────────────────────────────────────────────────────────────────────────────

function PlayerData.onChanged(callback: (Player) -> ())
	table.insert(listeners, callback)
end

local function fireChanged(player: Player)
	for _, callback in listeners do
		-- task.spawn ejecuta cada listener por separado: si uno falla, no rompe los demás.
		task.spawn(callback, player)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Estado
-- ─────────────────────────────────────────────────────────────────────────────

local function newSession(): Session
	local upgrades: { [string]: number } = {}
	for _, upgrade in Config.UPGRADES do
		upgrades[upgrade.id] = 0
	end
	return {
		coins = 0,
		totalCollected = 0,
		upgrades = upgrades,
		multiplier = 1,
		loaded = false,
	}
end

function PlayerData.get(player: Player): Session?
	return sessions[player]
end

--[[ Actualiza la tabla de clasificación nativa de Roblox (esquina superior derecha). ]]
local function syncLeaderstats(player: Player)
	local session = sessions[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not session or not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("Monedas") :: IntValue?
	local collected = leaderstats:FindFirstChild("Recogidas") :: IntValue?
	if coins then
		coins.Value = session.coins
	end
	if collected then
		collected.Value = session.totalCollected
	end
end

function PlayerData.addCoins(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return
	end

	local gained = math.floor(amount * session.multiplier)
	session.coins += gained
	session.totalCollected += gained

	syncLeaderstats(player)
	fireChanged(player)
end

--[[
	Intenta gastar monedas. Devuelve true si se pudo.
	Toda la lógica de "¿tienes suficiente?" vive en el servidor, jamás en el cliente.
]]
function PlayerData.trySpend(player: Player, amount: number): boolean
	local session = sessions[player]
	if not session or session.coins < amount then
		return false
	end

	session.coins -= amount
	syncLeaderstats(player)
	fireChanged(player)
	return true
end

function PlayerData.getUpgradeLevel(player: Player, upgradeId: string): number
	local session = sessions[player]
	if not session then
		return 0
	end
	return session.upgrades[upgradeId] or 0
end

function PlayerData.setUpgradeLevel(player: Player, upgradeId: string, level: number)
	local session = sessions[player]
	if not session then
		return
	end
	session.upgrades[upgradeId] = level
	fireChanged(player)
end

function PlayerData.setMultiplier(player: Player, multiplier: number)
	local session = sessions[player]
	if not session then
		return
	end
	session.multiplier = multiplier
	fireChanged(player)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Carga y guardado
-- ─────────────────────────────────────────────────────────────────────────────

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

--[[
	pcall = "protected call". Ejecuta una función y captura el error en vez de
	reventar el script. TODA llamada a DataStore va dentro de pcall: la red falla,
	y un error aquí no debe tumbar la partida de nadie.
]]
local function load(player: Player)
	local session = newSession()
	sessions[player] = session

	local ok, saved = pcall(function()
		return store:GetAsync(keyFor(player))
	end)

	if not ok then
		if dataStoreWorks then
			dataStoreWorks = false
			warn(
				"[PlayerData] DataStore no disponible. ¿Has activado 'Enable Studio Access to API Services'? Se juega sin guardar."
			)
		end
	elseif type(saved) == "table" then
		session.coins = tonumber(saved.coins) or 0
		session.totalCollected = tonumber(saved.totalCollected) or 0
		if type(saved.upgrades) == "table" then
			for _, upgrade in Config.UPGRADES do
				local level = tonumber(saved.upgrades[upgrade.id]) or 0
				-- Se recorta al máximo actual por si bajamos maxLevel en una actualización.
				session.upgrades[upgrade.id] = math.clamp(level, 0, upgrade.maxLevel)
			end
		end
	end

	session.loaded = true
	syncLeaderstats(player)
	fireChanged(player)
end

function PlayerData.save(player: Player)
	local session = sessions[player]
	-- No guardamos si la carga falló: escribiríamos ceros encima de la partida buena.
	if not session or not session.loaded then
		return
	end

	local payload = {
		coins = session.coins,
		totalCollected = session.totalCollected,
		upgrades = session.upgrades,
	}

	local ok, err = pcall(function()
		-- SetAsync es lo más simple. En un juego real con varios servidores por
		-- jugador se usa UpdateAsync, que lee y escribe de forma atómica.
		store:SetAsync(keyFor(player), payload)
	end)

	if not ok then
		warn("[PlayerData] No se pudo guardar a " .. player.Name .. ": " .. tostring(err))
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Arranque
-- ─────────────────────────────────────────────────────────────────────────────

function PlayerData.start()
	local function onPlayerAdded(player: Player)
		-- Una carpeta llamada exactamente "leaderstats" dentro del jugador hace que
		-- Roblox pinte esos valores en la tabla de la esquina. Es magia por nombre.
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"

		local coins = Instance.new("IntValue")
		coins.Name = "Monedas"
		coins.Parent = leaderstats

		local collected = Instance.new("IntValue")
		collected.Name = "Recogidas"
		collected.Parent = leaderstats

		leaderstats.Parent = player

		load(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Si un jugador entró antes de que este script arrancara, lo recogemos aquí.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerData.save(player)
		sessions[player] = nil
	end)

	-- Autoguardado periódico: si el servidor se cae de golpe, se pierde poco.
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				PlayerData.save(player)
			end
		end
	end)

	-- BindToClose se ejecuta cuando el servidor se apaga. Roblox nos da unos
	-- segundos de cortesía para guardar antes de matar el proceso.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			PlayerData.save(player)
		end
	end)
end

return PlayerData
