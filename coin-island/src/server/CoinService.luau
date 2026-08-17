--!strict
--[[
	CoinService.luau — el bucle de juego: monedas que aparecen, se recogen y vuelven.

	Aquí se ven tres cosas muy de Roblox:
	  1. El evento .Touched de una Part (cómo se detecta que alguien la toca).
	  2. El "debounce": el mismo toque dispara Touched muchas veces por segundo,
	     así que hay que marcar la moneda como recogida antes de sumar nada.
	  3. RunService.Heartbeat: código que corre en cada fotograma del servidor.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local CoinService = {}

local GOLD = Color3.fromRGB(240, 196, 60)

local coinsFolder: Folder
local coins: { Part } = {}
local rng = Random.new()

--[[ Elige un sitio libre para una moneda: a ras de suelo o sobre una plataforma. ]]
local function randomSpot(): Vector3
	local island = Workspace:FindFirstChild("Island")

	-- 40% de las veces la ponemos encima de una plataforma flotante, para premiar el salto.
	if island and rng:NextNumber() < 0.4 then
		local platforms = {}
		for _, child in island:GetChildren() do
			if child:IsA("BasePart") and child.Name:match("^Platform") then
				table.insert(platforms, child)
			end
		end
		if #platforms > 0 then
			local platform = platforms[rng:NextInteger(1, #platforms)]
			return platform.Position
				+ Vector3.new(rng:NextNumber(-2, 2), platform.Size.Y / 2 + 2.5, rng:NextNumber(-2, 2))
		end
	end

	local limit = Config.ARENA_SIZE / 2 - 8
	return Vector3.new(rng:NextNumber(-limit, limit), 2.5, rng:NextNumber(-limit, limit))
end

local function placeCoin(coin: Part)
	coin.Position = randomSpot()
	coin.Transparency = 0
	-- Los atributos son datos sueltos que se pegan a un objeto. Los usamos como
	-- bandera de "esta moneda se puede recoger".
	coin:SetAttribute("Active", true)
end

local function collect(coin: Part, player: Player)
	-- Debounce: si ya está recogida, salimos. Sin esto, un solo toque sumaría
	-- decenas de monedas, porque .Touched se dispara en cada fotograma de contacto.
	if coin:GetAttribute("Active") ~= true then
		return
	end
	coin:SetAttribute("Active", false)

	coin.Transparency = 1
	PlayerData.addCoins(player, Config.COIN_VALUE)

	-- task.delay ejecuta algo dentro de N segundos sin bloquear el resto del script.
	task.delay(Config.COIN_RESPAWN_SECONDS, function()
		if coin.Parent then
			placeCoin(coin)
		end
	end)
end

local function createCoin(): Part
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 3, 3)
	coin.Color = GOLD
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	-- CanCollide false = el jugador la atraviesa en vez de chocar. Touched sigue funcionando.
	coin.CanCollide = false
	coin.Parent = coinsFolder

	coin.Touched:Connect(function(hit: BasePart)
		-- hit es la parte que ha tocado la moneda (un pie, una mano...). Su Parent es
		-- el modelo del personaje. GetPlayerFromCharacter nos dice de quién es.
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			collect(coin, player)
		end
	end)

	placeCoin(coin)
	return coin
end

--[[
	Mejora "imán": recoge sola las monedas cercanas.
	Corre en un bucle lento (5 veces por segundo) en vez de cada fotograma, porque
	no necesita más precisión y así gasta menos CPU del servidor.
]]
local function runMagnetLoop()
	while true do
		task.wait(0.2)

		for _, player in Players:GetPlayers() do
			local level = PlayerData.getUpgradeLevel(player, "magnet")
			if level <= 0 then
				continue
			end

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end

			local upgrade = Config.findUpgrade("magnet")
			local radius = level * (upgrade and upgrade.perLevel or 6)

			for _, coin in coins do
				if coin:GetAttribute("Active") == true then
					if (coin.Position - root.Position).Magnitude <= radius then
						collect(coin, player)
					end
				end
			end
		end
	end
end

function CoinService.start()
	coinsFolder = Instance.new("Folder")
	coinsFolder.Name = "Coins"
	coinsFolder.Parent = Workspace

	for _ = 1, Config.COIN_COUNT do
		table.insert(coins, createCoin())
	end

	-- Heartbeat se dispara una vez por fotograma del servidor (~60/s) y nos dice
	-- cuánto tiempo ha pasado desde el anterior. Multiplicar por deltaTime hace que
	-- el giro sea igual de rápido aunque el servidor vaya a tirones.
	RunService.Heartbeat:Connect(function(deltaTime: number)
		for _, coin in coins do
			if coin:GetAttribute("Active") == true then
				coin.CFrame = coin.CFrame * CFrame.Angles(deltaTime * 2, 0, 0)
			end
		end
	end)

	task.spawn(runMagnetLoop)
end

return CoinService
