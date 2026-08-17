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
		-- Sólido, igual que el decorado de piezas: un edificio que se atraviesa se
		-- lee como un juego roto. Los modelos están fuera de las zonas que el
		-- servidor mide, así que no pueden dejar a nadie sin poder recoger.
		--
		-- Fidelidad de caja: la malla de un edificio generado tiene miles de
		-- triángulos y calcular su colisión exacta cuesta, además de dejar huecos
		-- por los que colarse. Una caja es lo que se quiere aquí -- una pared que
		-- para -- y no lo que se quiere nunca: una pared con agujeros.
		m.CollisionFidelity = Enum.CollisionFidelity.Box
		m.CanCollide = true
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
-- Alturas de las superficies sobre las que se apoya el decorado. La carretera es
-- un Part en y=0 de 1 de alto (superficie 0,5) y todas las losas -- almacén,
-- salida, taller, destinos -- están en y=1 con 2 de alto (superficie 2). Tenerlas
-- con nombre evita el fallo que ya salió jugando: la furgoneta colocada como si
-- el suelo fuese y=0 aparecía HUNDIDA dos studs dentro de la losa del taller.
local SUELO_CARRETERA = 0.5
local SUELO_LOSA = 2

local function respaldo(adorno: Instance)
	local CHAPA = Color3.fromRGB(158, 156, 148)
	local CHAPA_OSCURA = Color3.fromRGB(104, 102, 98)
	local ZOCALO = Color3.fromRGB(78, 76, 72)
	local MADERA = Color3.fromRGB(132, 100, 62)
	local MADERA_OSCURA = Color3.fromRGB(94, 70, 42)
	local PUERTA = Color3.fromRGB(72, 104, 78)
	local CRISTAL = Color3.fromRGB(42, 50, 58)

	local function bloque(nombre: string, tamano: Vector3, pos: Vector3, color: Color3, material: Enum.Material)
		local p = part(nombre, tamano, pos, color, adorno)
		p.Material = material
		-- SÓLIDO. Al principio no lo era, por miedo a que un edificio empujase al
		-- jugador fuera del radio en el que el servidor mide las distancias. Con
		-- cubos de colores daba igual; en cuanto hubo paredes de verdad, atravesarlas
		-- se lee como que el juego está roto -- y lo dijo JJ a la primera partida.
		--
		-- El miedo era infundado, además: los edificios están FUERA de las zonas que
		-- se miden. La nave arranca en z = -35 y el muelle acaba en -30; el cobertizo
		-- del taller deja libre toda la mitad de la losa que da a la carretera. Hay
		-- sitio de sobra para estar dentro del radio sin tocar una pared.
		p.CanCollide = true
		return p
	end

	-- El asfalto, que es sobre lo que se levantan la nave y el cobertizo. Vive
	-- AQUÍ y no dentro de una sección: al trocear el respaldo en piezas montables
	-- por separado, una `local suelo` declarada dentro de la sección de la nave
	-- dejaba a taller y furgoneta leyendo un global nil -- el mismo error que ya
	-- costó una ronda con tieneLegendaria en CargoService.
	local suelo = SUELO_CARRETERA

	-- APOYADO sobre el suelo, no centrado en una altura a ojo. `suelo` es la cota de
	-- la superficie y la pieza se sienta encima: es la diferencia entre una
	-- furgoneta aparcada y una furgoneta enterrada hasta los ejes.
	local function apoyado(
		nombre: string,
		tamano: Vector3,
		x: number,
		z: number,
		suelo: number,
		color: Color3,
		material: Enum.Material
	)
		return bloque(nombre, tamano, Vector3.new(x, suelo + tamano.Y / 2, z), color, material)
	end

	return {
		nave = function()
			-- ALMACÉN: nave detrás del muelle, sobre la carretera (el muelle sólo llega a
			-- z = -30, y la nave empieza más allá).
			local zNave, ancho, largo, alto = -52, 54, 34, 26
			local function pared(nombre: string, tamano: Vector3, x: number, z: number)
				apoyado(nombre, tamano, x, z, suelo, CHAPA, Enum.Material.Metal)
				-- Zócalo: una franja oscura abajo. Cuesta una pieza y es lo que hace que una
				-- caja gris parezca un edificio en vez de un cubo.
				apoyado(
					nombre .. "Zocalo",
					Vector3.new(tamano.X + 0.4, 3, tamano.Z + 0.4),
					x,
					z,
					suelo,
					ZOCALO,
					Enum.Material.Concrete
				)
			end

			pared("NaveIzq", Vector3.new(1.5, alto, largo), -ancho / 2, zNave)
			pared("NaveDer", Vector3.new(1.5, alto, largo), ancho / 2, zNave)
			pared("NaveFondo", Vector3.new(ancho, alto, 1.5), 0, zNave - largo / 2)
			pared("NaveFrente", Vector3.new(ancho, alto, 1.5), 0, zNave + largo / 2)
			apoyado(
				"NaveTejado",
				Vector3.new(ancho + 5, 1.5, largo + 5),
				0,
				zNave,
				suelo + alto,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)
			-- Alero: la sombra que proyecta es la mitad de lo que da volumen al edificio.
			apoyado(
				"NaveAlero",
				Vector3.new(ancho + 7, 1, 3),
				0,
				zNave + largo / 2 + 2,
				suelo + alto - 1.5,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)

			local frenteZ = zNave + largo / 2 + 1
			apoyado("NavePorton", Vector3.new(22, 16, 0.6), 0, frenteZ, suelo, PUERTA, Enum.Material.Metal)
			apoyado(
				"NavePortonMarco",
				Vector3.new(24, 17.5, 0.4),
				0,
				frenteZ + 0.3,
				suelo,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)
			for i, x in { -19, 19 } do
				apoyado(
					"NaveVentana" .. i,
					Vector3.new(9, 5, 0.6),
					x,
					frenteZ,
					suelo + 14,
					CRISTAL,
					Enum.Material.Glass
				)
				apoyado(
					"NaveVentanaMarco" .. i,
					Vector3.new(10, 6, 0.4),
					x,
					frenteZ + 0.3,
					suelo + 13.5,
					CHAPA_OSCURA,
					Enum.Material.Metal
				)
			end
		end,
		cajas = function()
			-- Cajas apiladas en el muelle. Sobre la LOSA, que es donde se anda, no sobre la
			-- carretera: media caja enterrada se ve al instante.
			local pila = {
				{ x = -20, z = -18, lado = 5 },
				{ x = -13.5, z = -20, lado = 5 },
				{ x = -22, z = -12, lado = 4 },
			}
			for i, c in pila do
				local caja = apoyado(
					"CajaMuelle" .. i,
					Vector3.new(c.lado, c.lado, c.lado),
					c.x,
					c.z,
					SUELO_LOSA,
					MADERA,
					Enum.Material.WoodPlanks
				)
				caja.CFrame = caja.CFrame * CFrame.Angles(0, math.rad(i * 23), 0)
				-- Flejes cruzados: dos piezas finas y la caja deja de ser un cubo marrón.
				local fleje = bloque(
					"CajaFleje" .. i,
					Vector3.new(c.lado + 0.3, 0.6, c.lado + 0.3),
					caja.Position,
					MADERA_OSCURA,
					Enum.Material.Wood
				)
				fleje.CFrame = caja.CFrame
			end
			-- Una encima, para que la pila tenga altura.
			local cima = apoyado(
				"CajaMuelle4",
				Vector3.new(4.5, 4.5, 4.5),
				-17,
				-16.5,
				SUELO_LOSA + 5,
				MADERA,
				Enum.Material.WoodPlanks
			)
			cima.CFrame = cima.CFrame * CFrame.Angles(0, math.rad(37), 0)
		end,
		taller = function()
			-- TALLER: cobertizo abierto por delante, para que se vea la furgoneta dentro.
			-- Va sobre la carretera; la losa azul del taller sólo llega a z = -20.
			local zTaller, anchoT, largoT, altoT = -36, 36, 30, 18
			local xT = -50
			apoyado(
				"TallerIzq",
				Vector3.new(1.5, altoT, largoT),
				xT - anchoT / 2,
				zTaller,
				suelo,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)
			apoyado(
				"TallerDer",
				Vector3.new(1.5, altoT, largoT),
				xT + anchoT / 2,
				zTaller,
				suelo,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)
			apoyado(
				"TallerFondo",
				Vector3.new(anchoT, altoT, 1.5),
				xT,
				zTaller - largoT / 2,
				suelo,
				CHAPA_OSCURA,
				Enum.Material.Metal
			)
			apoyado(
				"TallerTejado",
				Vector3.new(anchoT + 5, 1.5, largoT + 5),
				xT,
				zTaller,
				suelo + altoT,
				Palette.TALLER,
				Enum.Material.Metal
			)
			-- Dintel sobre la boca abierta: sin él, el cobertizo son dos paredes sueltas.
			apoyado(
				"TallerDintel",
				Vector3.new(anchoT + 5, 3, 2),
				xT,
				zTaller + largoT / 2,
				suelo + altoT - 4.5,
				Palette.TALLER,
				Enum.Material.Metal
			)
		end,
		furgoneta = function()
			-- La furgoneta aparcada ES el escaparate: enseña lo que compras antes de que
			-- puedas pagarlo, y eso es la mitad del motivo para hacer otro viaje. DENTRO
			-- del cobertizo y APOYADA en el suelo: colocada a ojo salía enterrada.
			-- DELANTE del cobertizo, sobre la losa del taller, no dentro. El cobertizo
			-- de piezas está abierto y dejaría verla, pero el taller puede venir como
			-- modelo 3D con colisión de caja -- un bloque macizo -- y entonces la
			-- furgoneta desaparecería dentro. Delante funciona en los dos casos, y de
			-- paso se ve desde el muelle al pasar.
			local fx, fz = xT, -12
			apoyado(
				"FurgoChasis",
				Vector3.new(9, 1.6, 17),
				fx,
				fz,
				SUELO_LOSA + 1.6,
				Color3.fromRGB(52, 56, 66),
				Enum.Material.Metal
			)
			apoyado(
				"FurgoCaja",
				Vector3.new(9.4, 7.5, 11),
				fx,
				fz - 3,
				SUELO_LOSA + 3.2,
				Palette.TALLER,
				Enum.Material.SmoothPlastic
			)
			apoyado(
				"FurgoCabina",
				Vector3.new(9, 5.4, 6),
				fx,
				fz + 5.5,
				SUELO_LOSA + 3.2,
				Color3.fromRGB(96, 116, 156),
				Enum.Material.SmoothPlastic
			)
			apoyado(
				"FurgoParabrisas",
				Vector3.new(8, 3, 0.6),
				fx,
				fz + 8.4,
				SUELO_LOSA + 4.6,
				CRISTAL,
				Enum.Material.Glass
			)
			apoyado(
				"FurgoMorro",
				Vector3.new(9, 2.6, 2.5),
				fx,
				fz + 9.4,
				SUELO_LOSA + 1.6,
				Color3.fromRGB(96, 116, 156),
				Enum.Material.SmoothPlastic
			)
			for i, r in { { x = -4.6, z = 5 }, { x = 4.6, z = 5 }, { x = -4.6, z = -6 }, { x = 4.6, z = -6 } } do
				local rueda = apoyado(
					"FurgoRueda" .. i,
					Vector3.new(1.4, 3.4, 3.4),
					fx + r.x,
					fz + r.z,
					SUELO_LOSA,
					Color3.fromRGB(30, 30, 34),
					Enum.Material.SmoothPlastic
				)
				-- SIN rotarla: el eje de un Part cilíndrico ya va a lo largo de su X local,
				-- que es justo el eje sobre el que gira una rueda en una furgoneta que
				-- mira hacia +Z. Girarla 90° la dejaría tumbada como un plato.
				rueda.Shape = Enum.PartType.Cylinder
			end
		end,
	}
end

function WorldBuilder.build(): {
	almacen: BasePart,
	salida: BasePart,
	taller: BasePart,
	aparicion: BasePart,
	destinos: { BasePart },
}
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
		-- CADA elemento intenta su modelo y, si no carga, monta su propia versión de
		-- piezas. Antes era todo o nada -- se probaba uno y, si fallaba, se montaba
		-- el respaldo entero -- y eso no aguanta el caso real: al publicar el place,
		-- el almacén y el taller cargaron y la caja y la furgoneta no, porque sus
		-- assets se habían quedado sin subir (403 en la cuenta). Con el todo o nada,
		-- dos modelos buenos se habrían tirado a la basura, o peor: se habrían
		-- montado ENCIMA de sus equivalentes de piezas.
		local piezas = respaldo(adorno)

		-- El edificio DETRÁS de la losa, no encima: la losa es el muelle de carga
		-- por el que se anda y donde aparece el jugador.
		if decorado("EdificioAlmacen", MeshCatalog.ALMACEN, Vector3.new(0, 18, -52), 0, adorno) == nil then
			piezas.nave()
		end

		-- Cajas apiladas en el muelle. Fijas: el contador real del almacén es de
		-- cada jugador y no cabe en una pila compartida, pero ver mercancía donde
		-- el juego dice que hay mercancía es lo que hace que "Recoger" signifique
		-- algo. Van todas o ninguna: media pila de modelos y media de cubos se
		-- notaría más que la pila entera de cubos.
		local cajasOk = true
		for i, sitio in { Vector3.new(-20, 4, -18), Vector3.new(-14, 4, -20), Vector3.new(-17, 8, -19) } do
			if decorado("CajaMuelle" .. i, MeshCatalog.CAJA, sitio, i * 24, adorno) == nil then
				cajasOk = false
				break
			end
		end
		if not cajasOk then
			for _, p in adorno:GetChildren() do
				if string.sub(p.Name, 1, 10) == "CajaMuelle" then
					p:Destroy()
				end
			end
			piezas.cajas()
		end

		if decorado("EdificioTaller", MeshCatalog.TALLER, Vector3.new(-50, 12, -38), 0, adorno) == nil then
			piezas.taller()
		end

		-- La furgoneta aparcada en el taller ES el escaparate: enseña lo que
		-- compras antes de que puedas pagarlo, que es la mitad del motivo para
		-- hacer otro viaje.
		if decorado("FurgonetaEscaparate", MeshCatalog.FURGONETA, Vector3.new(-50, 5.5, -12), 90, adorno) == nil then
			piezas.furgoneta()
		end
	end)

	-- `aparicion` se devuelve porque Avatar.luau construye los personajes a mano
	-- (ver su cabecera) y necesita saber donde dejarlos: con CharacterAutoLoads
	-- apagado, Roblox ya no usa el SpawnLocation por su cuenta.
	return { almacen = almacen, salida = salida, taller = taller, aparicion = spawn, destinos = destinos }
end

return WorldBuilder
