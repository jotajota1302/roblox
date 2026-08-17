--!strict
--[[
	WorldBuilder.luau — el mapa por código.

	Cubos de colores a propósito. El arte bonito CONTAMINA la medición: si el
	prototipo es atractivo, cuando alguien aguante diez minutos no sabremos si fue
	por el bucle o por lo bonito. Y el bucle es lo único que estamos midiendo.

	Geometría: el almacén en el origen y una carretera recta hacia +X. Los destinos
	se colocan a la distancia de cada ruta (Config.RUTAS).

	C3 (ampliado en revisión): no basta con un SpawnLocation. La primera versión
	tenía una carretera de 60 studs de ancho SIN nada debajo ni a los lados: un paso
	lateral era caída libre hasta los -500 studs donde Roblox destruye el personaje,
	y sin SpawnLocation, Roblox elegía dónde aparecer a partir de la extensión de
	TODO el mundo (una tira de 2.600 studs), así que podía dejarte fuera de ella. El
	arreglo tiene tres partes, ninguna decorativa:
	  1. SpawnLocation físico encima del almacén.
	  2. Carretera más ancha (perdona un paso en falso) con bordillos a los dos lados
	     que impiden caerse sin tener que mirar al suelo.
	  3. Una red de seguridad invisible por debajo de todo el recorrido: si alguien
	     se cae igualmente (un salto raro, un empujón), aterriza en vez de morir.

	TRAMPA ENCONTRADA VERIFICANDO EN STUDIO (no basta con mirar el código): un
	BasePart normal tiene un tamaño MÁXIMO por eje (2048 studs en este Studio).
	Un `Part` de 2.600 studs de largo NO da error: Roblox lo recorta en silencio a
	2048 y lo deja centrado en la misma Position -- así que la tira resultante
	quedaba desplazada y ya NO cubría el tramo del almacén (x=0) ni el de la salida
	(x=45). Resultado medido: caminando desde el almacén hacia la ruta verde, el
	personaje caía por el hueco y llegaba a -500 studs sin ni un bordillo ni la red
	de seguridad de por medio (ninguno de los dos alcanzaba tan a la izquierda). Por
	eso la carretera, los bordillos y la red se construyen en VARIOS segmentos, cada
	uno muy por debajo del límite, en vez de una sola pieza gigante.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)

local ANCHO_CARRETERA = 160 -- antes 60: un pasillo. Con 160 se puede jugar sin caerse por accidente
local ALTO_BORDILLO = 3
local GROSOR_BORDILLO = 4

-- Cobertura en X: desde bastante antes del almacén (x=0) hasta bastante después
-- del destino más lejano (roja, x=2000). Se trocea en segmentos de SEGMENTO_MAX
-- studs como mucho -- muy por debajo del límite de tamaño de un BasePart -- para
-- que ningún recorte silencioso de Roblox pueda dejar un hueco.
local MUNDO_X_INICIO = -80
local MUNDO_X_FIN = 2060
local SEGMENTO_MAX = 1000

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

-- Construye una tira larga como varios Part en vez de uno solo: un BasePart tiene
-- un tamaño máximo por eje que Roblox recorta EN SILENCIO (sin error) si te pasas,
-- y un recorte silencioso en una pieza que se supone que cubre todo el recorrido es
-- exactamente el tipo de fallo que sólo se ve jugando, no leyendo el código.
local function tira(
	nombreBase: string,
	y: number,
	altoY: number,
	anchoZ: number,
	color: Color3,
	padre: Instance
): { Part }
	local totalX = MUNDO_X_FIN - MUNDO_X_INICIO
	local n = math.ceil(totalX / SEGMENTO_MAX)
	local anchoSegmento = totalX / n
	local segmentos: { Part } = {}
	for i = 1, n do
		local centro = MUNDO_X_INICIO + (i - 1 + 0.5) * anchoSegmento
		local p = part(
			nombreBase .. "_" .. i,
			Vector3.new(anchoSegmento, altoY, anchoZ),
			Vector3.new(centro, y, 0),
			color,
			padre
		)
		table.insert(segmentos, p)
	end
	return segmentos
end

function WorldBuilder.build(): { almacen: BasePart, salida: BasePart, destinos: { BasePart } }
	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	local yCarretera, altoCarretera = 0, 1
	tira("Carretera", yCarretera, altoCarretera, ANCHO_CARRETERA, Color3.fromRGB(70, 70, 75), mundo)

	-- Bordillos: cubren la MISMA extensión en X que la carretera (el almacén y la
	-- salida incluidos), no sólo el tramo de la ruta.
	local zBordillo = ANCHO_CARRETERA / 2 + GROSOR_BORDILLO / 2
	local yBordillo = yCarretera + altoCarretera / 2 + ALTO_BORDILLO / 2
	local colorBordillo = Color3.fromRGB(90, 90, 95)
	for _, p in tira("BordilloNorte", yBordillo, ALTO_BORDILLO, GROSOR_BORDILLO, colorBordillo, mundo) do
		p.Position = Vector3.new(p.Position.X, p.Position.Y, zBordillo)
	end
	for _, p in tira("BordilloSur", yBordillo, ALTO_BORDILLO, GROSOR_BORDILLO, colorBordillo, mundo) do
		p.Position = Vector3.new(p.Position.X, p.Position.Y, -zBordillo)
	end

	-- Red de seguridad: invisible, por debajo de toda la extensión jugable. No
	-- decora nada — sólo evita que un salto raro o un empujón acabe destruyendo el
	-- personaje a -500 studs. Cubre de sobra el ancho de la carretera + bordillos.
	for _, p in
		tira("RedDeSeguridad", -30, 2, ANCHO_CARRETERA + 2 * GROSOR_BORDILLO + 100, Color3.fromRGB(40, 40, 45), mundo)
	do
		p.Transparency = 1
	end

	local almacen = part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Color3.fromRGB(120, 100, 60), mundo)

	-- Punto de aparición físico, encima del almacén (no dentro): sin él Roblox
	-- decide dónde aparece el jugador a partir de la extensión de todo el mundo, y
	-- con una carretera de 2.600 studs eso puede dejarlo fuera de lo jugable.
	-- Neutral = true (nadie es "de un equipo") y Duration = 0 (sin escudo de
	-- aparición: el almacén ya es zona segura por diseño, un escudo aquí sobra).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "AparicionAlmacen"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(almacen.Position.X, almacen.Position.Y + almacen.Size.Y / 2 + 0.5, almacen.Position.Z)
	spawn.Color = Color3.fromRGB(150, 130, 80)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = mundo

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
