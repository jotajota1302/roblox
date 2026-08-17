--!strict
--[[
	CityBuilder.luau — planta el juego DENTRO de la ciudad.

	Sustituye a WorldBuilder, cuya carretera recta era exactamente el defecto que
	este rediseño elimina (ver DISENO-CIUDAD.md §1 y PRIMERA-PARTIDA.md).

	El reparto de responsabilidades es la regla que no se rompe: la ciudad aporta
	calles y edificios, y NI UNA REGLA DEPENDE DE ELLA. Todo lo que es juego
	--almacén, salida, taller, destinos, detectores-- se planta aquí por código,
	sobre coordenadas medidas. Si mañana cambiamos de mapa, esto se vuelve a medir
	y el juego sigue siendo el mismo.

	FUNCIONA SIN LA CIUDAD. Es deliberado y no es una red de seguridad teórica: el
	mapa entra al repo como un .rbxm que hay que exportar a mano, así que hay un
	intervalo real -- y cualquier clon nuevo del repo -- en el que ese fichero no
	está. Sin respaldo, el juego se queda literalmente sin suelo y no se puede ni
	probar. Con él, se juega igual sobre una explanada fea.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Routes = require(game.ReplicatedStorage.Shared.Routes)

local CityBuilder = {}

-- Alto de las losas de juego. Se apoyan SOBRE el suelo que encuentren, nunca a una
-- altura fija: la ciudad tiene desniveles de 15 studs entre parcelas, y una losa
-- puesta a una cota constante sale flotando en un sitio y enterrada en el otro.
-- Es el mismo fallo que ya salió jugando con la furgoneta del taller.
local ALTO_LOSA = 2

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

-- Altura del suelo de la ciudad en un punto, o nil si ahí no hay nada.
--
-- Filtra SÓLO contra la ciudad a propósito: si sondeara el mundo entero, las
-- propias losas que este módulo va plantando se contarían como suelo y cada una
-- se apoyaría encima de la anterior.
local function sueloDeLaCiudad(ciudad: Instance?, x: number, z: number): number?
	if not ciudad then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }
	local r = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -800, 0), params)
	return r and r.Position.Y or nil
end

-- Coloca una losa APOYADA en el suelo que haya debajo. `alturaPorDefecto` es la
-- cota medida al elegir el emplazamiento: se usa cuando no hay ciudad, para que el
-- juego siga cuadrando sin ella.
local function losa(
	ciudad: Instance?,
	nombre: string,
	tamano: Vector3,
	centro: Vector3,
	color: Color3,
	padre: Instance
): Part
	local y = sueloDeLaCiudad(ciudad, centro.X, centro.Z) or centro.Y
	return part(nombre, tamano, Vector3.new(centro.X, y + ALTO_LOSA / 2, centro.Z), color, padre)
end

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

-- Explanada para cuando el .rbxm de la ciudad no está. Fea a propósito: su trabajo
-- es que se pueda jugar y medir, no disimular que falta el mapa.
--
-- En SEGMENTOS, no en una pieza: un BasePart se recorta EN SILENCIO a 2048 studs
-- por eje, sin error, dejando la pieza centrada -- y una explanada recortada deja
-- sin suelo justo los bordes, que es donde están el almacén y la ruta roja. Esta
-- lección ya costó una sesión entera con la carretera del prototipo.
local function explanada(padre: Instance)
	local MIN, MAX, PASO = -800, 800, 800
	for x = MIN, MAX - 1, PASO do
		for z = MIN, MAX - 1, PASO do
			local p = part(
				string.format("Explanada_%d_%d", x, z),
				Vector3.new(PASO, 2, PASO),
				Vector3.new(x + PASO / 2, 18, z + PASO / 2),
				Color3.fromRGB(78, 92, 70),
				padre
			)
			p.Material = Enum.Material.Grass
		end
	end
end

-- Los detectores de una zona, repartidos por el camino hacia su destino.
--
-- EN SITIOS FIJOS, con una semilla constante por ruta. Es la decisión de diseño
-- más importante de esta función: con posiciones aleatorias en cada partida no
-- habría nada que aprender, y esquivarlos sería suerte. Fijos, el jugador que
-- repite la ruta reconoce el cruce malo y lo rodea -- y esa es exactamente la
-- habilidad que el viaje tenía que pedir y no pedía.
local function sembrarDetectores(ciudad: Instance?, ruta: Routes.Ruta, padre: Instance): { BasePart }
	local origen = Config.ALMACEN_POS
	local destino = ruta.destino
	local rng = Random.new(#ruta.id * 7919) -- semilla del nombre: estable entre servidores
	local puestos: { BasePart } = {}

	-- El primer detector va SIEMPRE más allá de la zona segura, y esto no es un
	-- ajuste fino: dentro de ese radio HeatService apaga el calor en cada muestra,
	-- así que un detector plantado ahí es un poste decorativo que no dispara nunca.
	-- Con el 15 % fijo que había antes, los tres de la ruta verde caían a 119 studs
	-- --dentro de los 150 de la zona segura-- y la ruta de aprendizaje se quedaba
	-- literalmente sin vigilancia, que es justo donde hay que aprender qué es.
	local largo = (destino - origen).Magnitude
	local tMin = math.min(0.55, (Config.ZONA_SEGURA_RADIO + 40) / math.max(largo, 1))

	for i = 1, ruta.detectores do
		-- Repartidos por el resto del trayecto, dejando también un respiro antes del
		-- destino: llegar y que te detecten en la misma zancada sería quitarle al
		-- jugador la decisión justo cuando ya la había ganado.
		local t = tMin + (0.95 - tMin) * ((i - 0.5) / ruta.detectores)
		local centro = origen:Lerp(destino, t)
		-- Y desviados de la línea recta, si no serían una hilera de postes que se
		-- esquiva andando en paralelo. La desviación crece con la densidad: en la
		-- roja hay que cubrir el barrio, no una calle.
		local ancho = 60 + ruta.detectores * 8
		local x = centro.X + rng:NextNumber(-ancho, ancho)
		local z = centro.Z + rng:NextNumber(-ancho, ancho)

		local y = sueloDeLaCiudad(ciudad, x, z)
		if y == nil then
			-- Sin suelo ahí (un hueco entre parcelas): se cae a la línea del
			-- trayecto, que sí lo tiene, en vez de plantar un poste flotando.
			y = sueloDeLaCiudad(ciudad, centro.X, centro.Z) or centro.Y
			x, z = centro.X, centro.Z
		end

		local poste = part(
			string.format("Detector_%s_%d", ruta.id, i),
			Vector3.new(2, 22, 2),
			Vector3.new(x, (y :: number) + 11, z),
			Color3.fromRGB(40, 44, 52),
			padre
		)
		poste.Material = Enum.Material.Metal
		poste.CanCollide = false
		-- El id viaja con la pieza: HeatService necesita distinguirlos para que el
		-- bloqueo de re-disparo sea POR POSTE (ver Heat.luau).
		poste:SetAttribute("detectorId", poste.Name)
		poste:SetAttribute("ruta", ruta.id)

		-- La lente, arriba y encendida. UN PELIGRO INVISIBLE NO ES TENSIÓN, ES
		-- INJUSTICIA: si el jugador no puede ver de dónde le vino el calor, no
		-- aprende nada y sólo siente que el juego le castiga por sorpresa.
		local lente = part(
			"Lente",
			Vector3.new(3.4, 3.4, 3.4),
			Vector3.new(x, (y :: number) + 22, z),
			Color3.fromRGB(230, 90, 80),
			poste
		)
		lente.Material = Enum.Material.Neon
		lente.CanCollide = false

		local luz = Instance.new("PointLight")
		luz.Color = Color3.fromRGB(255, 120, 100)
		luz.Range = Config.DETECTOR_RADIO
		luz.Brightness = 1.6
		luz.Parent = lente

		table.insert(puestos, poste)
	end

	return puestos
end

-- Una nave sencilla detrás de la losa, para que el almacén SE LEA como un almacén.
--
-- Lo dijo JJ probándolo: "el almacén no se ve". Una losa de color no es un sitio;
-- es una mancha en el suelo. Y el almacén no es un sitio cualquiera -- es el punto
-- al que se vuelve, la zona segura y el motivo de todo el bucle. Si no se reconoce
-- de lejos, el jugador no sabe hacia dónde está volviendo.
--
-- Piezas simples a propósito: cuatro paredes, un tejado y un portón bastan para
-- que el ojo lo lea. Los modelos bonitos vienen cuando el bucle esté medido.
local function nave(base: Part, padre: Instance)
	local CHAPA = Color3.fromRGB(158, 156, 148)
	local CHAPA_OSCURA = Color3.fromRGB(104, 102, 98)
	local PORTON = Color3.fromRGB(72, 104, 78)

	local suelo = base.Position.Y + base.Size.Y / 2
	local ancho, largo, alto = 52, 34, 20
	-- SOBRE la losa y hacia el fondo, dejando patio delante. Antes iba DETRÁS, y eso
	-- dejaba el muelle a la intemperie: lo dijo JJ jugando -- las cajas "no salen
	-- dentro del almacén, están sueltas por el mapa". Con la nave fuera no había
	-- ningún sitio que fuera "el almacén", sólo una caseta cerrada y unas cajas al
	-- lado. Ahora hay un interior en el que se entra, y la mercancía está dentro.
	local centro = base.Position + Vector3.new(0, 0, -base.Size.Z / 2 + largo / 2 + 4)

	local function pieza(nombre: string, tamano: Vector3, offset: Vector3, color: Color3)
		local p = part(
			nombre,
			tamano,
			centro + Vector3.new(offset.X, suelo - base.Position.Y + offset.Y, offset.Z),
			color,
			padre
		)
		p.Material = Enum.Material.Metal
		return p
	end

	pieza("NaveIzq", Vector3.new(1.5, alto, largo), Vector3.new(-ancho / 2, alto / 2, 0), CHAPA)
	pieza("NaveDer", Vector3.new(1.5, alto, largo), Vector3.new(ancho / 2, alto / 2, 0), CHAPA)
	pieza("NaveFondo", Vector3.new(ancho, alto, 1.5), Vector3.new(0, alto / 2, -largo / 2), CHAPA)
	pieza("NaveTejado", Vector3.new(ancho + 5, 1.5, largo + 5), Vector3.new(0, alto, 0), CHAPA_OSCURA)
	-- SIN pared frontal: sólo el dintel y dos jambas, para que la boca quede abierta
	-- y la mercancía se vea desde fuera. Un almacén cerrado hay que adivinarlo, y
	-- entrar a por la carga es el gesto que el jugador repite en cada vuelta: tiene
	-- que estar invitando desde lejos.
	pieza("NaveDintel", Vector3.new(ancho, 6, 1.5), Vector3.new(0, alto - 3, largo / 2), CHAPA_OSCURA)
	pieza(
		"NaveJambaIzq",
		Vector3.new(10, alto - 6, 1.5),
		Vector3.new(-ancho / 2 + 5, (alto - 6) / 2, largo / 2),
		PORTON
	)
	pieza("NaveJambaDer", Vector3.new(10, alto - 6, 1.5), Vector3.new(ancho / 2 - 5, (alto - 6) / 2, largo / 2), PORTON)

	-- Luz dentro, lo justo para que la mercancía no sea un bulto negro.
	--
	-- La primera versión era una barra de neón de 40 studs y quedaba como un plató:
	-- "se ve demasiado iluminado" (JJ). El problema del neón es que la fuente misma
	-- es lo más brillante de la escena, así que el ojo va a la lámpara en vez de a
	-- las cajas. Ahora la pieza es pequeña y mate, y la luz la pone un PointLight
	-- discreto: se ve el interior sin que parezca un escaparate.
	local plafon = part(
		"NaveLuz",
		Vector3.new(6, 0.5, 2),
		centro + Vector3.new(0, suelo - base.Position.Y + alto - 2, 0),
		Color3.fromRGB(226, 220, 204),
		padre
	)
	plafon.Material = Enum.Material.SmoothPlastic
	plafon.CanCollide = false

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 240, 214)
	luz.Range = 34
	luz.Brightness = 0.9
	luz.Parent = plafon

	-- El nombre escrito en el frontal. En un mapa con cien edificios iguales, es lo
	-- que distingue el tuyo del bloque de oficinas de al lado.
	local rotulo = Instance.new("BillboardGui")
	rotulo.Name = "Rotulo"
	rotulo.Size = UDim2.fromScale(34, 7)
	rotulo.StudsOffsetWorldSpace = Vector3.new(0, alto + 8, 0)
	rotulo.AlwaysOnTop = true
	rotulo.MaxDistance = 1200
	rotulo.Adornee = base
	rotulo.Parent = base

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(255, 240, 200)
	texto.TextStrokeTransparency = 0.2
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = "TU ALMACÉN"
	texto.Parent = rotulo
end

-- Los sitios donde se apilan las cajas del muelle. NO se crean las cajas aquí: las
-- dibuja el cliente, porque el contador del almacén es de cada jugador y una pila
-- compartida mentiría a todos menos a uno. Aquí sólo se publican las posiciones,
-- para que las dos mitades no tengan cada una su copia de las coordenadas.
local function muelle(base: Part)
	local sitios: { Vector3 } = {}
	local suelo = base.Position.Y + base.Size.Y / 2
	-- DENTRO de la nave, contra el fondo. Las mismas coordenadas que usa nave() para
	-- colocarse: el centro de la nave cae a `-base.Size.Z/2 + largo/2 + 4` y mide 34
	-- de fondo, así que estas dos filas quedan holgadamente en su interior.
	local zNave = -base.Size.Z / 2 + 34 / 2 + 4
	for i = 0, Config.ALMACEN_TOPE - 1 do
		local fila = math.floor(i / 5)
		local columna = i % 5
		table.insert(
			sitios,
			base.Position + Vector3.new(-16 + columna * 8, suelo - base.Position.Y + 1.6, zNave - 8 + fila * 8)
		)
	end
	-- Viajan como atributos de la losa: el cliente los lee sin necesitar un remote
	-- propio ni conocer la geometría del mundo.
	for i, p in sitios do
		base:SetAttribute("muelle" .. i, p)
	end
	base:SetAttribute("muelleSitios", #sitios)
end

export type Mundo = {
	almacen: BasePart,
	salida: BasePart,
	taller: BasePart,
	aparicion: BasePart,
	destinos: { BasePart },
	detectores: { BasePart },
}

function CityBuilder.build(): Mundo
	iluminar()

	local ciudad = workspace:FindFirstChild("Ciudad")
	if not ciudad then
		warn("[Contrabando] no hay Workspace.Ciudad: se juega sobre la explanada de respaldo")
	end

	local mundo = Instance.new("Folder")
	mundo.Name = "Mundo"
	mundo.Parent = workspace

	if not ciudad then
		explanada(mundo)
	end

	-- Red de seguridad, muy por debajo de todo. No decora: evita que un salto raro
	-- acabe destruyendo el personaje a -500 studs. Va en piezas por el límite de
	-- 2048 studs por eje.
	for x = -900, 899, 900 do
		for z = -900, 899, 900 do
			local red = part(
				string.format("Red_%d_%d", x, z),
				Vector3.new(900, 2, 900),
				Vector3.new(x + 450, -60, z + 450),
				Color3.fromRGB(40, 40, 45),
				mundo
			)
			red.Transparency = 1
		end
	end

	local almacen = losa(ciudad, "Almacen", Vector3.new(90, ALTO_LOSA, 90), Config.ALMACEN_POS, Palette.ALMACEN, mundo)
	nave(almacen, mundo)
	muelle(almacen)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "AparicionAlmacen"
	spawn.Size = Vector3.new(12, 1, 12)
	-- EN EL PATIO, delante de la nave y mirando hacia ella. Aparecer dentro de un
	-- objeto es de las primeras cosas que ve un jugador nuevo y ya pasó una vez
	-- (encima de la furgoneta); ahora además la nave ocupa el fondo de la losa, así
	-- que el centro tampoco vale. Aquí se aparece fuera, con el almacén de frente:
	-- lo primero que se ve es a dónde hay que entrar.
	spawn.Position = almacen.Position + Vector3.new(0, ALTO_LOSA / 2 + 0.5, almacen.Size.Z / 2 - 12)
	spawn.Color = Color3.fromRGB(150, 130, 80)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = mundo

	-- La salida: el único sitio donde se elige ruta, y lo que impide cambiar de
	-- ruta a mitad de viaje. Se coloca entre el almacén y el centro de la ciudad,
	-- que es hacia donde se sale en las tres rutas.
	local haciaLaCiudad = (Vector3.new(0, 0, 0) - Config.ALMACEN_POS).Unit
	local salidaPos = Config.ALMACEN_POS + haciaLaCiudad * 60
	local salida = losa(
		ciudad,
		"Salida",
		Vector3.new(30, ALTO_LOSA, 30),
		Vector3.new(salidaPos.X, Config.ALMACEN_POS.Y, salidaPos.Z),
		Palette.SALIDA,
		mundo
	)

	-- El taller, al otro lado: pasar por delante de la tienda al salir convertiría
	-- la mejora en un anuncio, pero está DENTRO de la zona segura, así que nadie
	-- puede emboscar a quien compra.
	local taller = losa(ciudad, "Taller", Vector3.new(40, ALTO_LOSA, 40), Config.TALLER_POS, Palette.TALLER, mundo)

	local destinos: { BasePart } = {}
	local detectores: { BasePart } = {}

	for _, ruta in Routes.todas() do
		local destino = losa(
			ciudad,
			"Destino_" .. ruta.id,
			Vector3.new(44, ALTO_LOSA, 44),
			ruta.destino,
			Palette.ruta(ruta.id),
			mundo
		)
		destino:SetAttribute("ruta", ruta.id)

		-- La baliza, visible desde el otro extremo del mapa. En la ciudad importa
		-- MÁS que en la recta, no menos: allí bastaba con mirar al frente, y aquí
		-- hay manzanas de por medio y es fácil perder el norte a mitad de viaje.
		local baliza = part(
			"Baliza_" .. ruta.id,
			Vector3.new(8, 300, 8),
			destino.Position + Vector3.new(0, 150, 0),
			Palette.ruta(ruta.id),
			mundo
		)
		baliza.CanCollide = false
		baliza.Material = Enum.Material.Neon

		local cartel = Instance.new("BillboardGui")
		cartel.Name = "Cartel"
		cartel.Size = UDim2.fromScale(26, 9)
		cartel.StudsOffsetWorldSpace = Vector3.new(0, 170, 0)
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
		for _, poste in sembrarDetectores(ciudad, ruta, mundo) do
			table.insert(detectores, poste)
		end
	end

	return {
		almacen = almacen,
		salida = salida,
		taller = taller,
		aparicion = spawn,
		destinos = destinos,
		detectores = detectores,
	}
end

return CityBuilder
