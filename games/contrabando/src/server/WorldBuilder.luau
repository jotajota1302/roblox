--!strict
--[[
	WorldBuilder.luau — el mapa por código.

	Cubos de colores a propósito. El arte bonito CONTAMINA la medición: si el
	prototipo es atractivo, cuando alguien aguante diez minutos no sabremos si fue
	por el bucle o por lo bonito. Y el bucle es lo único que estamos midiendo.

	Geometría: el almacén en el origen y una carretera recta hacia +X. Los destinos
	se colocan a la distancia de cada ruta (Config.RUTAS).
]]

local Config = require(game.ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local function part(nombre: string, tamano: Vector3, posicion: Vector3, color: Color3, padre: Instance): Part
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.Position = posicion
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = padre
	return p
end

function WorldBuilder.build(): { almacen: BasePart, destino: BasePart }
	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	-- Carretera larga: 2.400 studs cubren de sobra la ruta roja (2.000).
	part("Carretera", Vector3.new(2600, 1, 60), Vector3.new(1200, 0, 0), Color3.fromRGB(70, 70, 75), mundo)

	local almacen = part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Color3.fromRGB(120, 100, 60), mundo)

	-- En esta tarea sólo hay un destino, el de la ruta verde. La Tarea 6 añade el resto.
	local verde = Config.RUTAS[1]
	local destino = part(
		"Destino_verde",
		Vector3.new(40, 2, 40),
		Vector3.new(verde.distancia, 1, 0),
		Color3.fromRGB(60, 140, 70),
		mundo
	)
	destino:SetAttribute("ruta", verde.id)

	return { almacen = almacen, destino = destino }
end

return WorldBuilder
