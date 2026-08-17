--!strict
--[[
	WorldBuilder.luau — construye el mapa por código.

	En Roblox lo normal es construir el mapa a mano en Studio y que quede guardado
	dentro del fichero .rbxl (un binario). Nosotros lo generamos por código a propósito:
	así el mapa vive en git, se puede revisar en un diff y tú puedes cambiar un número
	aquí y ver el resultado al instante. El .rbxl queda vacío y desechable.

	Todo lo que se crea aquí va a Workspace, que es el mundo 3D visible.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local WorldBuilder = {}

local SAND = Color3.fromRGB(214, 197, 152)
local STONE = Color3.fromRGB(120, 124, 130)
local WATER = Color3.fromRGB(58, 112, 132)

--[[ Ayuda para crear una Part con las propiedades más habituales de una sola vez. ]]
local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	-- Anchored = no le afecta la gravedad, se queda quieta. Casi todo el decorado va anclado.
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

function WorldBuilder.build()
	-- Empezamos limpios: borramos lo que hubiera de una ejecución anterior o de la
	-- plantilla de Studio. Así el resultado es siempre el mismo.
	local existing = Workspace:FindFirstChild("Island")
	if existing then
		existing:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local island = Instance.new("Folder")
	island.Name = "Island"
	island.Parent = Workspace

	local size = Config.ARENA_SIZE

	-- Mar: una placa enorme y plana debajo de todo, solo decorativa.
	makePart({
		Name = "Sea",
		Size = Vector3.new(size * 6, 4, size * 6),
		Position = Vector3.new(0, -6, 0),
		Color = WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Parent = island,
	})

	-- Suelo jugable.
	makePart({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		Position = Vector3.new(0, -2, 0),
		Color = SAND,
		Material = Enum.Material.Sand,
		Parent = island,
	})

	-- Cuatro muros bajos para que no te caigas al mar sin querer.
	local half = size / 2
	local walls = {
		{ Vector3.new(size, 8, 2), Vector3.new(0, 2, half) },
		{ Vector3.new(size, 8, 2), Vector3.new(0, 2, -half) },
		{ Vector3.new(2, 8, size), Vector3.new(half, 2, 0) },
		{ Vector3.new(2, 8, size), Vector3.new(-half, 2, 0) },
	}
	for index, wall in walls do
		makePart({
			Name = "Wall" .. index,
			Size = wall[1],
			Position = wall[2],
			Color = STONE,
			Material = Enum.Material.Rock,
			Parent = island,
		})
	end

	-- Plataformas flotantes: dan una razón para comprar la mejora de salto.
	-- Random.new(semilla) da SIEMPRE la misma secuencia, así el mapa es reproducible.
	local rng = Random.new(20260817)
	for index = 1, 14 do
		local angle = (index / 14) * math.pi * 2
		local radius = rng:NextNumber(18, half - 14)
		makePart({
			Name = "Platform" .. index,
			Size = Vector3.new(rng:NextNumber(8, 16), 1.5, rng:NextNumber(8, 16)),
			Position = Vector3.new(math.cos(angle) * radius, rng:NextNumber(6, 26), math.sin(angle) * radius),
			Color = STONE,
			Material = Enum.Material.Slate,
			Parent = island,
		})
	end

	-- Punto de aparición. Sin un SpawnLocation, Roblox te deja caer en (0,0,0).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(90, 140, 90)
	spawn.Material = Enum.Material.Grass
	spawn.Duration = 0 -- 0 = sin escudo de invulnerabilidad al aparecer
	spawn.Parent = island
end

return WorldBuilder
