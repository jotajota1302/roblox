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

function WorldBuilder.build(): { almacen: BasePart, salida: BasePart, destinos: { BasePart } }
	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	part("Carretera", Vector3.new(2600, 1, 60), Vector3.new(1200, 0, 0), Color3.fromRGB(70, 70, 75), mundo)

	local almacen = part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Color3.fromRGB(120, 100, 60), mundo)

	-- La salida es el único sitio donde se elige ruta. Que sea un punto físico
	-- concreto es lo que impide cambiar de ruta a mitad de viaje.
	local salida = part("Salida", Vector3.new(20, 2, 60), Vector3.new(45, 1, 0), Color3.fromRGB(200, 190, 120), mundo)

	local colores = {
		verde = Color3.fromRGB(60, 140, 70),
		ambar = Color3.fromRGB(200, 150, 50),
		roja = Color3.fromRGB(170, 60, 60),
	}

	local destinos: { BasePart } = {}
	for _, ruta in Config.RUTAS do
		local destino = part(
			"Destino_" .. ruta.id,
			Vector3.new(40, 2, 40),
			Vector3.new(ruta.distancia, 1, 0),
			colores[ruta.id] or Color3.fromRGB(200, 200, 200),
			mundo
		)
		destino:SetAttribute("ruta", ruta.id)
		table.insert(destinos, destino)
	end

	return { almacen = almacen, salida = salida, destinos = destinos }
end

return WorldBuilder
