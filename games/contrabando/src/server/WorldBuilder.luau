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

local AssetService = game:GetService("AssetService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local MeshCatalog = require(game.ReplicatedStorage.Shared.MeshCatalog)
local Palette = require(game.ReplicatedStorage.Shared.Palette)

local ANCHO_CARRETERA = 160 -- antes 60: un pasillo. Con 160 se puede jugar sin caerse por accidente
local ALTO_BORDILLO = 3
local GROSOR_BORDILLO = 4

-- Cobertura en X: desde bastante antes del almacén (x=0) hasta bastante después
-- del destino más lejano (roja, x=2000). Se trocea en segmentos de SEGMENTO_MAX
-- studs como mucho -- muy por debajo del límite de tamaño de un BasePart -- para
-- que ningún recorte silencioso de Roblox pueda dejar un hueco.
-- Llega hasta -120 (antes -80) para que el taller, que se planta en x=-50 con 30
-- de largo, tenga suelo de sobra por detrás en vez de acabar en el borde exacto.
local MUNDO_X_INICIO = -120
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

-- Planta un modelo de MeshCatalog. Devuelve nil si algo falla, y el mundo sigue
-- en pie: los meshes son DECORACIÓN y ninguna regla depende de ellos. Un id que
-- deja de cargar tiene que costar un edificio feo, nunca un juego sin suelo --
-- exactamente el fallo que este proyecto ya pagó con el DataStore.
--
-- TRAMPA DE ROBLOX, medida aquí: `Instance.new("MeshPart").MeshId = ...` NO
-- funciona en tiempo de ejecución. Falla con "The current thread cannot write
-- 'MeshId' (lacking capability NotAccessible)" -- MeshId sólo se escribe desde
-- Studio o un plugin. En un servidor hay que pedirle la pieza a AssetService, que
-- sí puede. El resultado admite TextureID y Size con normalidad; el que no se
-- puede tocar es el mesh. Descubierto porque la carpeta de decorado salía VACÍA
-- sin un solo error visible: los pcall se lo tragaban todo.
--
-- CreateMeshPartAsync espera al servidor de assets, así que esto NO puede ir en
-- el camino de arranque: el mundo jugable se construye primero y el decorado
-- llega después (ver el final de build()).
local function decorado(
	nombre: string,
	modelo: MeshCatalog.Modelo,
	posicion: Vector3,
	giroY: number,
	padre: Instance
): MeshPart?
	local ok, resultado = pcall(function()
		local m = AssetService:CreateMeshPartAsync(modelo.mesh)
		m.Name = nombre
		m.TextureID = modelo.textura
		m.Size = modelo.tamano
		m.CFrame = CFrame.new(posicion) * CFrame.Angles(0, math.rad(giroY), 0)
		m.Anchored = true
		-- Sin colisión: la geometría jugable son las losas. Un edificio sólido
		-- puede empujar al jugador fuera de la zona en la que el servidor mide
		-- distancias, y entonces el botón de recoger dejaría de funcionar sin que
		-- nada lo explique.
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.Parent = padre
		return m
	end)
	if not ok then
		warn("[Contrabando] no se pudo plantar el decorado " .. nombre .. ": " .. tostring(resultado))
		return nil
	end
	return resultado
end

-- La luz por defecto de un place vacío deja el mundo casi de noche, y con modelos
-- texturizados eso no es un detalle estético: un edificio que no se distingue del
-- suelo no informa de dónde estás, y la única pista de que vas bien en un viaje
-- de 2.000 studs es reconocer a lo lejos el sitio al que vas.
--
-- Media tarde, no mediodía: con el sol en cenit todo se aplana y los volúmenes se
-- pierden. Con sombras largas, el almacén y el taller se leen de un vistazo.
local function iluminar()
	local ok, err = pcall(function()
		local luz = game:GetService("Lighting")
		luz.ClockTime = 15.5
		luz.Brightness = 2.5
		luz.GlobalShadows = true
		luz.EnvironmentDiffuseScale = 0.4
		luz.EnvironmentSpecularScale = 0.3
		luz.OutdoorAmbient = Color3.fromRGB(120, 118, 126)
		luz.Ambient = Color3.fromRGB(70, 68, 74)
		luz.FogEnd = 3000

		-- Bruma ligera: además de ambientar, da profundidad a una carretera recta de
		-- 2.000 studs en la que si no, todo está a la misma distancia aparente.
		if not luz:FindFirstChildOfClass("Atmosphere") then
			local aire = Instance.new("Atmosphere")
			aire.Density = 0.32
			aire.Haze = 1.4
			aire.Color = Color3.fromRGB(200, 198, 190)
			aire.Decay = Color3.fromRGB(106, 112, 125)
			aire.Parent = luz
		end
	end)
	if not ok then
		warn("[Contrabando] no se pudo ajustar la luz: " .. tostring(err))
	end
end

-- Decorado construido con piezas, para cuando los meshes no cargan.
--
-- HACE FALTA DE VERDAD, no es una red de seguridad teórica: con el place SIN
-- PUBLICAR (PlaceId = 0) Studio no resuelve NINGÚN mesh de la nube -- ni los
-- nuestros ni uno público de Roblox -- y todas las llamadas fallan con "Failed to
-- load mesh asset". Los meshes generados con Cube 3D sólo se ven en la misma
-- sesión de Studio en la que se crearon; en cualquier otra, hasta publicar el
-- place, esto es lo único que hay. Es la misma trampa que el DataStore, que
-- también revienta sin publicar.
--
-- No pretende ser bonito: pretende que el sitio se reconozca. Un almacén con
-- paredes, tejado y una puerta se lee como un almacén; una losa plana no se lee
-- como nada, y el jugador no sabe dónde está de pie.
local function respaldo(adorno: Instance)
	local CHAPA = Color3.fromRGB(150, 148, 140)
	local CHAPA_OSCURA = Color3.fromRGB(112, 110, 104)
	local MADERA = Color3.fromRGB(126, 96, 60)
	local PUERTA = Color3.fromRGB(72, 104, 78)

	local function bloque(nombre: string, tamano: Vector3, pos: Vector3, color: Color3, material: Enum.Material)
		local p = part(nombre, tamano, pos, color, adorno)
		p.Material = material
		-- Sin colisión, igual que los meshes: la geometría jugable son las losas, y
		-- un edificio sólido puede empujar al jugador fuera del radio en el que el
		-- servidor mide las distancias.
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		return p
	end

	-- Almacén: nave detrás del muelle. Paredes, tejado y un portón que mira al
	-- muelle, que es por donde se entra a recoger.
	local zNave, anchoNave, largoNave, altoNave = -52, 52, 34, 26
	bloque(
		"NaveIzq",
		Vector3.new(2, altoNave, largoNave),
		Vector3.new(-anchoNave / 2, altoNave / 2, zNave),
		CHAPA,
		Enum.Material.Metal
	)
	bloque(
		"NaveDer",
		Vector3.new(2, altoNave, largoNave),
		Vector3.new(anchoNave / 2, altoNave / 2, zNave),
		CHAPA,
		Enum.Material.Metal
	)
	bloque(
		"NaveFondo",
		Vector3.new(anchoNave, altoNave, 2),
		Vector3.new(0, altoNave / 2, zNave - largoNave / 2),
		CHAPA,
		Enum.Material.Metal
	)
	bloque(
		"NaveFrente",
		Vector3.new(anchoNave, altoNave, 2),
		Vector3.new(0, altoNave / 2, zNave + largoNave / 2),
		CHAPA,
		Enum.Material.Metal
	)
	bloque(
		"NaveTejado",
		Vector3.new(anchoNave + 4, 2, largoNave + 4),
		Vector3.new(0, altoNave, zNave),
		CHAPA_OSCURA,
		Enum.Material.Metal
	)
	bloque(
		"NavePorton",
		Vector3.new(22, 16, 1),
		Vector3.new(0, 8, zNave + largoNave / 2 + 0.6),
		PUERTA,
		Enum.Material.Metal
	)
	for i, x in { -18, 18 } do
		bloque(
			"NaveVentana" .. i,
			Vector3.new(8, 5, 1),
			Vector3.new(x, 18, zNave + largoNave / 2 + 0.6),
			Color3.fromRGB(40, 46, 52),
			Enum.Material.Glass
		)
	end

	-- Cajas apiladas en el muelle: mercancía visible donde el juego dice que hay
	-- mercancía, que es lo que hace que el botón de recoger signifique algo.
	for i, sitio in { Vector3.new(-20, 4, -18), Vector3.new(-14, 4, -20), Vector3.new(-17, 8, -19) } do
		local caja = bloque("CajaMuelle" .. i, Vector3.new(5, 5, 5), sitio, MADERA, Enum.Material.WoodPlanks)
		caja.CFrame = CFrame.new(sitio) * CFrame.Angles(0, math.rad(i * 22), 0)
	end

	-- Taller: cobertizo abierto por delante, para que se vea la furgoneta dentro.
	local zTaller, anchoTaller, largoTaller, altoTaller = -34, 34, 28, 18
	bloque(
		"TallerIzq",
		Vector3.new(2, altoTaller, largoTaller),
		Vector3.new(-50 - anchoTaller / 2, altoTaller / 2, zTaller),
		CHAPA_OSCURA,
		Enum.Material.Metal
	)
	bloque(
		"TallerDer",
		Vector3.new(2, altoTaller, largoTaller),
		Vector3.new(-50 + anchoTaller / 2, altoTaller / 2, zTaller),
		CHAPA_OSCURA,
		Enum.Material.Metal
	)
	bloque(
		"TallerFondo",
		Vector3.new(anchoTaller, altoTaller, 2),
		Vector3.new(-50, altoTaller / 2, zTaller - largoTaller / 2),
		CHAPA_OSCURA,
		Enum.Material.Metal
	)
	bloque(
		"TallerTejado",
		Vector3.new(anchoTaller + 4, 2, largoTaller + 4),
		Vector3.new(-50, altoTaller, zTaller),
		Palette.TALLER,
		Enum.Material.Metal
	)

	-- La furgoneta aparcada ES el escaparate: enseña lo que compras antes de que
	-- puedas pagarlo, y eso es la mitad del motivo para hacer otro viaje.
	local base = Vector3.new(-50, 0, -18)
	bloque(
		"FurgoCaja",
		Vector3.new(8, 7, 11),
		base + Vector3.new(0, 5.5, -2),
		Palette.TALLER,
		Enum.Material.SmoothPlastic
	)
	bloque(
		"FurgoCabina",
		Vector3.new(7.4, 5, 5),
		base + Vector3.new(0, 4.5, 5),
		Color3.fromRGB(96, 116, 156),
		Enum.Material.SmoothPlastic
	)
	bloque(
		"FurgoParabrisas",
		Vector3.new(6.6, 2.6, 0.6),
		base + Vector3.new(0, 5.6, 7.4),
		Color3.fromRGB(40, 46, 52),
		Enum.Material.Glass
	)
	for i, sitio in
		{
			Vector3.new(-4, 1.6, 4.5),
			Vector3.new(4, 1.6, 4.5),
			Vector3.new(-4, 1.6, -5),
			Vector3.new(4, 1.6, -5),
		}
	do
		local rueda = bloque(
			"FurgoRueda" .. i,
			Vector3.new(1.2, 3.2, 3.2),
			base + sitio,
			Color3.fromRGB(32, 32, 36),
			Enum.Material.SmoothPlastic
		)
		rueda.Shape = Enum.PartType.Cylinder
	end
end

function WorldBuilder.build(): { almacen: BasePart, salida: BasePart, taller: BasePart, destinos: { BasePart } }
	iluminar()

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

	local almacen = part("Almacen", Vector3.new(60, 2, 60), Vector3.new(0, 1, 0), Palette.ALMACEN, mundo)

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
	local salida = part("Salida", Vector3.new(20, 2, 60), Vector3.new(45, 1, 0), Palette.SALIDA, mundo)

	-- El taller: donde el dinero deja de ser un número. Se coloca DETRÁS del
	-- almacén (x negativo), no de camino a la salida: pasar por delante de la
	-- tienda cada vez que sales es lo que convierte una mejora en un anuncio.
	-- Está dentro de la zona segura, así que nadie puede emboscar a quien compra.
	local taller = part("Taller", Vector3.new(30, 2, 40), Vector3.new(-50, 1, 0), Palette.TALLER, mundo)

	-- Los colores salen de Palette, no de una tabla local: el botón del selector de
	-- ruta y el destino al que lleva TIENEN que ser del mismo color, y con dos
	-- copias del RGB eso dura hasta que alguien retoque una.
	local destinos: { BasePart } = {}
	for _, ruta in Config.RUTAS do
		local destino = part(
			"Destino_" .. ruta.id,
			Vector3.new(40, 2, 40),
			Vector3.new(ruta.distancia, 1, 0),
			Palette.ruta(ruta.id),
			mundo
		)
		destino:SetAttribute("ruta", ruta.id)

		-- Un pilar alto del color de la ruta, visible desde el otro extremo. No es
		-- adorno: la ruta roja son 2.000 studs en línea recta y, sin una referencia
		-- que se vea de lejos, el jugador camina un minuto sin ninguna señal de que
		-- va bien. Eso no es tensión, es no saber si el juego está roto.
		local baliza = part(
			"Baliza_" .. ruta.id,
			Vector3.new(6, 120, 6),
			Vector3.new(ruta.distancia, 60, 0),
			Palette.ruta(ruta.id),
			mundo
		)
		baliza.CanCollide = false
		baliza.Material = Enum.Material.Neon

		-- Y el multiplicador escrito encima, que es el dato por el que has elegido
		-- venir hasta aquí. AlwaysOnTop para que no lo tape el propio pilar.
		local cartel = Instance.new("BillboardGui")
		cartel.Name = "Cartel"
		cartel.Size = UDim2.fromScale(24, 8)
		cartel.StudsOffsetWorldSpace = Vector3.new(0, 70, 0)
		cartel.AlwaysOnTop = true
		cartel.MaxDistance = 2500
		cartel.Adornee = baliza
		cartel.Parent = baliza

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 255, 255)
		texto.TextStrokeTransparency = 0.2
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = string.format("%s  x%d", string.upper(ruta.id), ruta.multiplicador)
		texto.Parent = cartel

		table.insert(destinos, destino)
	end

	-- Decorado. Va al final, en su propia carpeta y EN OTRO HILO: así se lee de un
	-- vistazo que nada de aquí participa en ninguna regla, y sobre todo, la espera
	-- de AssetService no retrasa ni un milisegundo la aparición del suelo. En este
	-- juego el orden importa más de lo normal: el personaje se carga en cuanto hay
	-- mundo, y todo lo que se meta antes es tiempo cayendo al vacío.
	local adorno = Instance.new("Folder")
	adorno.Name = "Decorado"
	adorno.Parent = mundo

	task.spawn(function()
		-- Se prueba con UNO antes de intentar los cuatro. Si los meshes no cargan
		-- fallan todos por el mismo motivo (place sin publicar), y encadenar cuatro
		-- esperas al servidor de assets para recibir cuatro veces el mismo error es
		-- tiempo de arranque tirado. El edificio DETRÁS de la losa, no encima: la
		-- losa es el muelle de carga por el que se anda y donde aparece el jugador.
		if decorado("EdificioAlmacen", MeshCatalog.ALMACEN, Vector3.new(0, 18, -52), 0, adorno) == nil then
			warn("[Contrabando] sin meshes (place sin publicar?): se monta el decorado de piezas")
			respaldo(adorno)
			return
		end

		-- Cajas apiladas en el muelle. Fijas: el contador real del almacén es de
		-- cada jugador y no cabe en una pila compartida, pero ver mercancía donde
		-- el juego dice que hay mercancía es lo que hace que "Recoger" signifique
		-- algo.
		for i, sitio in { Vector3.new(-20, 4, -18), Vector3.new(-14, 4, -20), Vector3.new(-17, 8, -19) } do
			decorado("CajaMuelle" .. i, MeshCatalog.CAJA, sitio, i * 24, adorno)
		end

		decorado("EdificioTaller", MeshCatalog.TALLER, Vector3.new(-50, 12, -38), 0, adorno)
		-- La furgoneta aparcada en el taller ES el escaparate: enseña lo que
		-- compras antes de que puedas pagarlo, que es la mitad del motivo para
		-- hacer otro viaje.
		decorado("FurgonetaEscaparate", MeshCatalog.FURGONETA, Vector3.new(-50, 5.5, -14), 90, adorno)
	end)

	return { almacen = almacen, salida = salida, taller = taller, destinos = destinos }
end

return WorldBuilder
