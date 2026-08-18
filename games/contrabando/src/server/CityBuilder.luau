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
local Detectors = require(game.ReplicatedStorage.Shared.Detectors)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local Shelter = require(game.ReplicatedStorage.Shared.Shelter)

local CityBuilder = {}

-- Alto de las losas de juego. Se apoyan SOBRE el suelo que encuentren, nunca a una
-- altura fija: la ciudad tiene desniveles de 15 studs entre parcelas, y una losa
-- puesta a una cota constante sale flotando en un sitio y enterrada en el otro.
-- Es el mismo fallo que ya salió jugando con la furgoneta del taller.
local ALTO_LOSA = 2

-- Lado de la losa de la salida. Es una constante y no un número suelto porque la
-- carretera de acceso ARRANCA en su borde: si un día crece la losa y la carretera
-- sigue naciendo donde nacía, entre las dos queda un escalón.
local LADO_SALIDA = 30

-- La vía de acceso: cuánto sobresale por encima del suelo que pisa, y su grosor.
-- El resalte es lo justo para que no se la coma un desnivel y lo bastante poco
-- para subirse de un paso.
local RESALTE_VIA = 1.6
local GROSOR_VIA = 2.4

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

-- Por encima de esta cota ya no es calle: es un tejado.
--
-- La ciudad se sondeó con 225 rayos en rejilla y su suelo transitable va de 3 a 30
-- studs; los edificios llegan a 175. 40 deja margen para desniveles y aceras
-- altas sin llegar a confundir una azotea con una acera.
local COTA_CALLE = 40

-- Suelo TRANSITABLE cerca de (x, z), buscando en espiral si hace falta.
--
-- EXISTE POR UN FALLO QUE HACÍA INÚTIL MEDIO SISTEMA DE VIGILANCIA. Un rayo desde
-- arriba devuelve lo primero que toca, y en una ciudad eso es un tejado la mitad
-- de las veces: 15 de los 30 detectores acabaron plantados sobre edificios, uno a
-- 186 studs de altura. Ninguno de ellos podía dispararse jamás -- por debajo pasa
-- la calle, a ochenta studs de su radio de 35. Esto es lo que explicaba que
-- recorrer la ruta verde entera diera calor máximo 0.
--
-- El síntoma es de los peores que da este proyecto: nada revienta, el poste existe
-- y se ve perfectamente si miras hacia arriba, y el juego simplemente es más fácil
-- de lo que dice ser sin que nada lo señale.
local function sueloTransitable(ciudad: Instance?, x: number, z: number): (number?, number, number)
	local y = sueloDeLaCiudad(ciudad, x, z)
	if y ~= nil and y <= COTA_CALLE then
		return y, x, z
	end
	-- En anillos hacia fuera: el sitio ideal está ocupado por un edificio, así que
	-- se busca la calle más cercana en vez de renunciar. Moverlo veinte studs es
	-- mucho mejor que dejarlo en una azotea donde no sirve para nada.
	for radio = 20, 100, 20 do
		for k = 0, 7 do
			local a = k * math.pi / 4
			local nx = x + math.cos(a) * radio
			local nz = z + math.sin(a) * radio
			local ny = sueloDeLaCiudad(ciudad, nx, nz)
			if ny ~= nil and ny <= COTA_CALLE then
				return ny, nx, nz
			end
		end
	end
	return nil, x, z
end

-- Coloca una losa APOYADA en el suelo que haya debajo. `alturaPorDefecto` es la
-- cota medida al elegir el emplazamiento: se usa cuando no hay ciudad, para que el
-- juego siga cuadrando sin ella.
-- DESPEJAR LA PARCELA antes de construir encima.
--
-- "Hemos puesto el almacén en la pista de baloncesto y hay una canasta dentro"
-- (JJ). Y no fue mala suerte: una pista de baloncesto es exactamente lo que un
-- barrido que premia SUELO LLANO Y DESPEJADO va a elegir siempre. El fallo fue
-- creer que se podía comprobar con rayos -- un rayo cada veinticinco studs pasa de
-- largo junto a un poste de canasta, una farola o un banco. Se comprobó, salió
-- limpio, y la canasta estaba ahí.
--
-- Buscar otra parcela tampoco valía: con el criterio bueno (volumen, no rayos) no
-- queda NI UNA libre en el cuadrante con sitio para el almacén, el taller y la
-- salida. Esta ciudad no tiene solares vacíos. Así que se hace lo que haría
-- cualquiera que comprara el terreno: se despeja.
--
-- Se borra desde metro y medio SOBRE el suelo, para no abrir un agujero en la
-- calle, y se dejan en paz las piezas enormes: si el bounding box de un edificio
-- entero roza una esquina de la parcela, el problema es la parcela, no el
-- edificio.
local LIMITE_PIEZA_GRANDE = 200

-- Cuántas piezas de la ciudad hay dentro de un volumen, SIN tocarlas. Sirve para
-- elegir sitio antes de construir: preferir una parcela que ya está limpia es
-- mejor que arrasar la primera que toque.
local function despejarCuenta(ciudad: Instance?, centro: Vector3, lado: number): number
	if ciudad == nil then
		return 0
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }
	params.MaxParts = 60
	local dentro =
		workspace:GetPartBoundsInBox(CFrame.new(centro.X, centro.Y + 24, centro.Z), Vector3.new(lado, 45, lado), params)
	local cuenta = 0
	for _, pieza in dentro do
		if math.max(pieza.Size.X, pieza.Size.Y, pieza.Size.Z) <= LIMITE_PIEZA_GRANDE then
			cuenta += 1
		end
	end
	return cuenta
end

local function despejar(ciudad: Instance?, centro: Vector3, lado: number, alto: number): number
	if ciudad == nil then
		return 0
	end
	local base = sueloDeLaCiudad(ciudad, centro.X, centro.Z) or centro.Y

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }
	params.MaxParts = 400

	local dentro = workspace:GetPartBoundsInBox(
		CFrame.new(centro.X, base + 1.5 + alto / 2, centro.Z),
		Vector3.new(lado, alto, lado),
		params
	)

	local quitadas = 0
	for _, pieza in dentro do
		local tam = pieza.Size
		if math.max(tam.X, tam.Y, tam.Z) <= LIMITE_PIEZA_GRANDE then
			pieza:Destroy()
			quitadas += 1
		end
	end
	if quitadas > 0 then
		print(string.format("[Contrabando] parcela despejada en (%.0f, %.0f): %d piezas", centro.X, centro.Z, quitadas))
	end
	return quitadas
end

-- La cota del suelo bajo un punto del trazado, tomando el PUNTO MÁS ALTO de una
-- cruz pequeña alrededor en vez de un solo rayo.
--
-- MEDIDO: con un rayo por tramo, el acceso del polígono a la ciudad se quedaba en
-- veinticuatro pasos rodables de veinticinco -- un jirón de césped asomaba 1,2
-- studs por encima del asfalto justo antes de enganchar con la calle. El rayo
-- caía a nueve studs de la loma y no la veía. Un solo rayo mide un solo punto del
-- terreno; la vereda tiene veintiséis studs de ancho.
local function cotaDelTrazado(ciudad: Instance?, punto: Vector3, direccion: Vector3, ancho: number): number?
	-- DENTRO DEL POLÍGONO manda su cota, como en losa() y por lo mismo: la boca cae
	-- justo sobre el borde del mapa y ahí el rayo todavía encuentra suelo de la
	-- ciudad diez studs más abajo. Sin esto, el primer tramo del acceso nace hundido
	-- en su propia explanada.
	local function suelo(p: Vector3): number?
		if Perimeter.dentro(p, 6) then
			return Config.POLIGONO_CENTRO.Y
		end
		return sueloDeLaCiudad(ciudad, p.X, p.Z)
	end

	-- El rayo del CENTRO manda: es el que va por donde de verdad pasa la vía.
	local centro = suelo(punto)
	if centro == nil then
		return nil
	end

	local lado = Vector3.new(-direccion.Z, 0, direccion.X)
	local alto = centro
	for _, desplazamiento in { lado * (ancho / 3), lado * -(ancho / 3), direccion * 3, direccion * -3 } do
		local y = suelo(punto + desplazamiento)
		-- CON TOPE, y este tope es la mitad de la función. Sin él, un rayo de al lado
		-- que caiga sobre un tejado --y en una ciudad eso pasa, es lo mismo que dejó
		-- quince detectores plantados en las azoteas-- levanta la junta entera: el
		-- último tramo del acceso verde salió TRECE STUDS por encima de la calle,
		-- convertido en una rampa hacia un balcón. Cuatro studs es un bordillo alto o
		-- una loma; más que eso ya es un edificio y no un desnivel del camino.
		if y ~= nil and y > alto and y - centro <= 4 then
			alto = y
		end
	end
	return alto
end

-- El punto del BORDE de una losa en la dirección de otro sitio.
--
-- Existe porque la carretera de un destino nacía en el CENTRO de su losa y se la
-- cruzaba entera por encima: la sonda del mundo lo cazó a la primera --"lo que se
-- pisa encima del destino es Acceso_verde_1"-- y es peor de lo que parece. La losa
-- de un destino es su señal: verde, ámbar o roja, visible desde lejos, y es lo que
-- el jugador busca al llegar. Una franja de asfalto gris por el medio la parte en
-- dos.
local function bordeDeLosa(losa: BasePart, hacia: Vector3): Vector3
	local dir = Vector3.new(hacia.X - losa.Position.X, 0, hacia.Z - losa.Position.Z)
	if dir.Magnitude < 1 then
		return losa.Position
	end
	dir = dir.Unit
	-- Por qué lado se sale del rectángulo: el que se alcance antes.
	local tX = if math.abs(dir.X) > 1e-4 then losa.Size.X / 2 / math.abs(dir.X) else math.huge
	local tZ = if math.abs(dir.Z) > 1e-4 then losa.Size.Z / 2 / math.abs(dir.Z) else math.huge
	return losa.Position + dir * math.min(tX, tZ)
end

-- UN ACCESO RODADO entre dos puntos. Lo usa el polígono para engancharse a la
-- ciudad y, sobre todo, cada DESTINO para engancharse a la calle más cercana.
--
-- POR QUÉ EXISTE EL SEGUNDO USO, que es el que importa: la mercancía grande
-- EXIGE vehículo (un piano no se lleva a pie) y los vehículos grandes sólo ruedan
-- por asfalto. Si el último tramo hasta el destino era césped, el juego te pedía
-- una cosa y su contraria: llevar el piano en furgoneta y llegar a un sitio donde
-- la furgoneta no entra. Lo dijo JJ: "que las cargas grandes vayan a sitios donde
-- pueden llegar los vehículos".
--
-- Se marca RODABLE explícitamente en vez de fiarlo a su color: el asfalto se
-- reconoce por gris (ver Roads.esCalzada), y una vía nuestra que un día se pinte
-- de otro color dejaría de contar sin que nadie tocara esta línea.
local function acceso(
	ciudad: Instance?,
	nombre: string,
	desde: Vector3,
	hasta: Vector3,
	ancho: number,
	padre: Instance,
	cotaInicial: number?,
	cotaFinal: number?
): number
	local plano = Vector3.new(hasta.X - desde.X, 0, hasta.Z - desde.Z)
	local largo = plano.Magnitude
	if largo < 6 then
		-- Ya se tocan: una vía de cero studs sólo sería una pieza más que dibujar.
		return 0
	end

	-- POR TRAMOS INCLINADOS, SIGUIENDO EL SUELO. Hubo dos versiones antes de esta y
	-- las dos se midieron:
	--
	--   1. una sola losa a la cota del destino -- el acceso a la ruta ámbar quedó
	--      ENTERRADO bajo el césped en la mitad de su recorrido, porque el terreno
	--      sube por el camino;
	--   2. tramos horizontales, cada uno a la cota de su centro -- mejor, pero
	--      entre dos tramos con distinta altura queda un escalón, y por ese escalón
	--      asomaba el césped.
	--
	-- Ahora cada tramo va de junta a junta INCLINADO: su cota de salida es la de
	-- llegada del anterior, así que la carretera es continua y sube con el relieve
	-- en vez de atravesarlo a saltos.
	local tramos = math.max(2, math.ceil(largo / 10))
	local direccion = plano.Unit

	-- Las cotas de las juntas se calculan ANTES, y una sola vez: la junta entre dos
	-- tramos es la misma para los dos, y calcularla dos veces es la manera de que
	-- un día no coincidan. Lo que se guarda es la COTA DE RODADURA --por dónde pisa
	-- el jugador-- y no el suelo de debajo: es la que tiene que casar con la losa
	-- de la que sale la vía, y hacer esa cuenta en dos sitios distintos es cómo
	-- aparecen los escalones.
	local cotas: { number } = {}
	for i = 0, tramos do
		local p = desde:Lerp(hasta, i / tramos)
		cotas[i] = (cotaDelTrazado(ciudad, p, direccion, ancho) or p.Y) + RESALTE_VIA
	end

	-- LOS DOS EXTREMOS SE IMPONEN, porque de los dos sabemos la respuesta sin
	-- medirla: la vía sale de una losa nuestra (sé a qué altura la puse) y termina
	-- en una calle que calleMasCercana ya localizó y midió. Medirlos otra vez con un
	-- rayo desde el cielo es darle a la ciudad la ocasión de contestar con un
	-- tejado.
	if cotaInicial ~= nil then
		cotas[0] = cotaInicial
	end
	if cotaFinal ~= nil then
		cotas[tramos] = cotaFinal
	end

	-- Y LAS JUNTAS DE ENMEDIO, SUJETAS A LA CUERDA entre los dos extremos. Esto es
	-- lo que impide que la carretera se suba a un edificio: el último tramo del
	-- acceso verde salió TRECE STUDS por encima de la calle --una rampa a un
	-- balcón-- porque el rayo de su junta cayó sobre una azotea. Ocho studs de
	-- libertad admiten cualquier cuesta real de esta ciudad; un piso entero, no.
	local LIBERTAD = 8
	for i = 1, tramos - 1 do
		local cuerda = cotas[0] + (cotas[tramos] - cotas[0]) * (i / tramos)
		cotas[i] = math.clamp(cotas[i], cuerda - LIBERTAD, cuerda + LIBERTAD)
	end

	local puestos = 0
	for i = 1, tramos do
		local p0 = desde:Lerp(hasta, (i - 1) / tramos)
		local p1 = desde:Lerp(hasta, i / tramos)
		local a = Vector3.new(p0.X, cotas[i - 1] - GROSOR_VIA / 2, p0.Z)
		local b = Vector3.new(p1.X, cotas[i] - GROSOR_VIA / 2, p1.Z)
		local centro = (a + b) / 2
		local tramo = part(
			string.format("%s_%d", nombre, i),
			-- Un poco más largo que el hueco que cubre, para que dos tramos seguidos
			-- se solapen y no quede una junta de césped entre ellos.
			Vector3.new(ancho, GROSOR_VIA, (b - a).Magnitude + 6),
			centro,
			Color3.fromRGB(96, 96, 102),
			padre
		)
		tramo.Material = Enum.Material.Asphalt
		tramo.CFrame = CFrame.lookAt(centro, b)
		-- RODABLE explícito y no por color: el asfalto se reconoce por gris (ver
		-- Roads.esCalzada), y una vía nuestra que un día se pinte de otro color
		-- dejaría de contar sin que nadie tocara esta línea.
		tramo:SetAttribute("rodable", true)
		puestos += 1
	end
	return puestos
end

-- La calzada de la ciudad más cercana a un punto. Devuelve nil si no hay ninguna
-- a tiro, que es la señal de que ese sitio no vale para un destino.
local function calleMasCercana(ciudad: Instance?, centro: Vector3, alcance: number): Vector3?
	if ciudad == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }
	-- A LA ALTURA DE UNO, y no sólo gris. El color dice de qué está hecho, no a qué
	-- altura está: en esta ciudad hay azoteas y pasarelas grises, y la de la ruta
	-- verde estaba VEINTE STUDS por encima del destino. Se dio por buena, se le
	-- construyó una carretera de acceso hasta allí, y el último tramo quedó
	-- convertido en una rampa a un balcón. Doce studs admiten una cuesta y una acera
	-- alta; un piso, no.
	local DESNIVEL_MAXIMO = 12
	for radio = 30, alcance, 10 do
		for k = 0, 17 do
			local angulo = k * math.pi / 9
			local x = centro.X + math.cos(angulo) * radio
			local z = centro.Z + math.sin(angulo) * radio
			local golpe = workspace:Raycast(Vector3.new(x, centro.Y + 120, z), Vector3.new(0, -300, 0), params)
			if
				golpe ~= nil
				and Roads.esCalzada(golpe.Instance.Color)
				and math.abs(golpe.Position.Y - centro.Y) <= DESNIVEL_MAXIMO
			then
				return golpe.Position
			end
		end
	end
	return nil
end

-- EL POLÍGONO: el suelo que construimos nosotros, fuera de la ciudad.
--
-- Aquí no se despeja nada porque no hay nada que despejar: es terreno virgen
-- detrás del borde del mapa. Todo lo del juego --almacén, taller, salida-- vive
-- encima, y una carretera lo cose a la ciudad.
--
-- Se marca RODABLE entero: es una explanada de asfalto, y además es la zona
-- segura, así que bajarse del vehículo aquí no tendría ningún sentido.
local function poligono(ciudad: Instance?, padre: Instance)
	local centro = Config.POLIGONO_CENTRO
	local medida = Config.POLIGONO_TAMANO
	local cota = centro.Y

	local suelo = part(
		"Poligono",
		Vector3.new(medida.X, 4, medida.Y),
		Vector3.new(centro.X, cota - 2, centro.Z),
		Color3.fromRGB(104, 104, 110),
		padre
	)
	suelo.Material = Enum.Material.Concrete
	suelo:SetAttribute("rodable", true)

	-- Un zócalo hasta bien abajo: la explanada está al borde del mundo y sin esto
	-- se ve el canto flotando sobre el vacío desde media ciudad.
	local zocalo = part(
		"PoligonoZocalo",
		Vector3.new(medida.X + 6, 90, medida.Y + 6),
		Vector3.new(centro.X, cota - 48, centro.Z),
		Color3.fromRGB(74, 72, 78),
		padre
	)
	zocalo.Material = Enum.Material.Slate
	zocalo.CanCollide = false

	-- LA CARRETERA DE ACCESO, de la salida del polígono a la calle más cercana.
	-- Es la frontera del juego: cruzarla es salir de casa, y por eso la salida se
	-- planta justo aquí.
	-- Se le pasa la ciudad aunque el primer tramo salga de nuestra explanada:
	-- sueloDeLaCiudad devuelve nil donde la ciudad no llega, y ahí el tramo se
	-- queda en la cota que le damos. Medido: sin esto, los últimos metros antes de
	-- enganchar con la calle quedaban por debajo del césped.
	-- ARRANCA EN EL BORDE EXTERIOR DE LA LOSA DE LA SALIDA, no en la boca: la losa
	-- ocupa los quince primeros studs del camino, así que una vía que naciera en la
	-- boca quedaría enterrada debajo de ella y volvería a asomar --dos studs y medio
	-- más abajo-- justo donde la losa se acaba. Ese escalón se midió.
	local bordeSalida = Config.POLIGONO_SALIDA.Z - LADO_SALIDA / 2
	acceso(
		ciudad,
		"PoligonoAcceso",
		Vector3.new(Config.POLIGONO_SALIDA.X, cota, bordeSalida),
		Vector3.new(Config.POLIGONO_ENGANCHE.X, cota, Config.POLIGONO_ENGANCHE.Z),
		26,
		padre,
		-- Al ras de la losa: su cara de arriba, que es por donde se viene pisando.
		cota + ALTO_LOSA
	)

	-- Muro perimetral bajo en tres lados: cierra el recinto sin encerrar (la valla
	-- de verdad, la que frena, es la del recinto y sólo aparece con carga sin
	-- destino). Éste es decorado que dice "esto es tuyo".
	local function muro(nombre: string, tamano: Vector3, offset: Vector3)
		local m = part(
			nombre,
			tamano,
			Vector3.new(centro.X + offset.X, cota + 1.5, centro.Z + offset.Z),
			Color3.fromRGB(128, 126, 120),
			padre
		)
		m.Material = Enum.Material.Brick
	end
	muro("MuroOeste", Vector3.new(3, 7, medida.Y), Vector3.new(-medida.X / 2, 0, 0))
	muro("MuroEste", Vector3.new(3, 7, medida.Y), Vector3.new(medida.X / 2, 0, 0))
	muro("MuroSur", Vector3.new(medida.X, 7, 3), Vector3.new(0, 0, medida.Y / 2))
	-- El norte queda ABIERTO: es por donde se sale a la ciudad.

	-- Farolas, para que de noche el polígono no sea una mancha negra.
	for i = -1, 1, 2 do
		for j = -1, 1, 2 do
			local poste = part(
				string.format("Farola_%d_%d", i, j),
				Vector3.new(1.2, 22, 1.2),
				Vector3.new(centro.X + i * (medida.X / 2 - 20), cota + 11, centro.Z + j * (medida.Y / 2 - 20)),
				Color3.fromRGB(70, 70, 76),
				padre
			)
			poste.Material = Enum.Material.Metal
			poste.CanCollide = false
			local luz = Instance.new("PointLight")
			luz.Range = 60
			luz.Brightness = 1.4
			luz.Color = Color3.fromRGB(255, 238, 205)
			luz.Parent = poste
		end
	end

	return suelo
end

local function losa(
	ciudad: Instance?,
	nombre: string,
	tamano: Vector3,
	centro: Vector3,
	color: Color3,
	padre: Instance
): Part
	-- DENTRO DEL POLÍGONO manda su cota, no la de la ciudad. La boca del polígono
	-- cae justo sobre el borde del mapa, así que ahí el rayo todavía encuentra
	-- suelo de la ciudad -- diez studs más abajo-- y la losa de la salida se
	-- hundía en la explanada.
	local y = if Perimeter.dentro(centro, 6)
		then Config.POLIGONO_CENTRO.Y
		else (sueloDeLaCiudad(ciudad, centro.X, centro.Z) or centro.Y)
	local pieza = part(nombre, tamano, Vector3.new(centro.X, y + ALTO_LOSA / 2, centro.Z), color, padre)
	-- RODABLE: las losas del juego (almacén, salida, taller, destinos) son sitio
	-- del juego, y la regla de la calzada no puede echarte del vehículo al entrar
	-- en tu propio muelle. Se marca con un atributo porque su color es el de su
	-- función --verde, ámbar, azul-- y RoadService reconoce el asfalto por gris.
	pieza:SetAttribute("rodable", true)
	return pieza
end

-- Un aviso de "pulsa aquí" pegado a una pieza del mundo.
--
-- SUSTITUYE A LOS BOTONES FIJOS DE LA PANTALLA, y el motivo lo dio JJ jugando:
-- "lo de entregar y recoger que sean botones es un poco extraño". Lo es. Un botón
-- permanente en una esquina no dice DÓNDE se entrega ni CUÁNDO se puede: está ahí
-- siempre, igual de encendido en mitad de la nada que encima del destino, así que
-- el jugador tiene que aprenderse por su cuenta cuándo sirve.
--
-- ProximityPrompt es la pieza nativa de Roblox para esto y es lo que cualquier
-- jugador de la plataforma ya sabe usar: aparece solo al acercarse a la cosa
-- concreta, sale como tecla en el ordenador y como botón táctil en el móvil, y
-- desaparece cuando te alejas. La acción deja de vivir en la interfaz y pasa a
-- vivir en el sitio donde ocurre.
local function prompt(pieza: BasePart, accion: string, objeto: string, distancia: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = accion
	p.ObjectText = objeto
	p.MaxActivationDistance = distancia
	p.HoldDuration = 0
	p.RequiresLineOfSight = false -- si no, una farola delante lo apaga y parece roto
	p.Parent = pieza
	return p
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
	local puestos: { BasePart } = {}

	-- DÓNDE van los postes lo decide Detectors, que es puro y está probado. Aquí
	-- sólo se bajan al suelo y se construyen.
	--
	-- La cuenta que vive allí es la que este fichero se saltó dos veces: si el
	-- desvío respecto al camino es mayor que el radio de detección, la vigilancia
	-- no vigila nada. Medido antes del cambio: la ruta roja entera, andada de punta
	-- a punta, daba CALOR 0 con dieciocho detectores plantados.
	for i, sitio in Detectors.sitios(origen, ruta.destino, ruta.detectores) do
		local x, z = sitio.posicion.X, sitio.posicion.Z

		-- Suelo de CALLE, no lo primero que toque el rayo: la mitad de los postes
		-- acababa en tejados, donde no se disparan nunca (ver sueloTransitable).
		--
		-- Pero al del CORREDOR se le busca calle en corto: si se le deja vagar cien
		-- studs buscando asfalto acaba fuera del alcance del camino, que es
		-- justamente lo que venía a garantizar. Antes que eso, se queda donde está.
		local y, cx, cz = sueloTransitable(ciudad, x, z)
		if y ~= nil and sitio.enElCorredor then
			local desplazado = math.sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
			if desplazado > Config.DETECTOR_RADIO then
				y = sueloDeLaCiudad(ciudad, x, z)
				cx, cz = x, z
			end
		end
		x, z = cx, cz
		if y == nil then
			-- Ni siquiera hay suelo (un hueco entre parcelas): se cae a la línea del
			-- trayecto, que sí lo tiene, en vez de plantar un poste en el vacío.
			local centro = origen:Lerp(ruta.destino, (i - 0.5) / math.max(ruta.detectores, 1))
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

		-- La marca, arriba y encendida. UN PELIGRO INVISIBLE NO ES TENSIÓN, ES
		-- INJUSTICIA: si el jugador no puede ver de dónde le vino el problema, no
		-- aprende nada y sólo siente que el juego le castiga por sorpresa.
		--
		-- Con el tema nuevo esto ya no es una cámara de policía sino una esquina
		-- fichada: el sitio donde te ven pasar con género y corre la voz.
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
-- `frente` dice hacia qué lado del eje Z se abre la boca: -1 hacia el norte, +1
-- hacia el sur. NO es un capricho de parámetro -- la nave estaba abierta hacia el
-- muro del polígono ("está orientado el almacén y el taller hacia fuera en vez de
-- hacia dentro", JJ), y un almacén que da la espalda a la puerta obliga a
-- rodearlo entero cada vez que entras a cargar.
local function nave(base: Part, padre: Instance, frente: number)
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
	local centro = base.Position + Vector3.new(0, 0, frente * (-base.Size.Z / 2 + largo / 2 + 4))

	local function pieza(nombre: string, tamano: Vector3, offset: Vector3, color: Color3)
		local p = part(
			nombre,
			tamano,
			centro + Vector3.new(offset.X, suelo - base.Position.Y + offset.Y, offset.Z * frente),
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
local function muelle(base: Part, frente: number)
	local sitios: { Vector3 } = {}
	local suelo = base.Position.Y + base.Size.Y / 2
	-- DENTRO de la nave, contra el fondo. Las mismas coordenadas que usa nave() para
	-- colocarse: el centro de la nave cae a `-base.Size.Z/2 + largo/2 + 4` y mide 34
	-- de fondo, así que estas dos filas quedan holgadamente en su interior.
	local zNave = frente * (-base.Size.Z / 2 + 34 / 2 + 4)
	for i = 0, Config.ALMACEN_TOPE - 1 do
		local fila = math.floor(i / 5)
		local columna = i % 5
		table.insert(
			sitios,
			base.Position
				+ Vector3.new(-16 + columna * 8, suelo - base.Position.Y + 1.6, zNave + frente * (-8 + fila * 8))
		)
	end
	-- Viajan como atributos de la losa: el cliente los lee sin necesitar un remote
	-- propio ni conocer la geometría del mundo.
	for i, p in sitios do
		base:SetAttribute("muelle" .. i, p)
	end
	base:SetAttribute("muelleSitios", #sitios)
end

-- Una comisaría: el sitio donde no te pueden alcanzar.
--
-- Es la vuelta que le dio JJ al guion y es mejor que la original: la policía deja
-- de perseguirte y pasa a ser justo lo contrario -- el sitio al que corres. Un
-- ladrón no entra en una comisaría, y eso no hay que explicarlo.
--
-- Tiene que reconocerse DESDE LEJOS y mientras corres mirando hacia atrás, porque
-- ése es el único momento en que importa. De ahí el pilar de luz: cuando te
-- persiguen no vas a leer un cartel, vas a buscar una referencia de color en el
-- horizonte. Es la misma razón por la que los destinos llevan baliza.
-- EL CONCESIONARIO. Antes era una losa amarilla con un aviso encima, y la
-- consecuencia la dijo JJ jugando: "no sé dónde se compran los vehículos, debería
-- haber como un concesionario, ¿o es un menú de compras?". Las dos preguntas
-- salen del mismo sitio: el único sumidero de dinero del juego no se parecía a
-- nada, así que no había forma de saber que estaba ahí ni de qué era.
--
-- Un edificio con techo, escaparate iluminado y tres coches expuestos se reconoce
-- desde la otra acera sin leer nada, que es lo que tiene que pasar: el taller es
-- el sitio al que va el dinero, y ver a dónde va tu dinero es la mitad del motivo
-- para hacer otro viaje.
--
-- Todo con Part y a propósito: los meshes del catálogo de vehículos no cargan
-- mientras el place no esté publicado, y un escaparate vacío no vendería nada.
local function concesionario(base: Part, padre: Instance, frente: number)
	local CHAPA = Color3.fromRGB(214, 206, 186)
	local MARCO = Color3.fromRGB(120, 96, 52)
	local suelo = base.Position.Y + base.Size.Y / 2
	-- Grande de verdad: tiene que caber el escaparate Y el garaje entero (ocho
	-- vehículos), y con 40x26 las plazas se salían por detrás del cobertizo.
	local ancho, largo, alto = 72, 44, 17

	local function pieza(nombre: string, tamano: Vector3, offset: Vector3, color: Color3): Part
		local p = part(
			nombre,
			tamano,
			Vector3.new(base.Position.X, suelo, base.Position.Z) + Vector3.new(offset.X, offset.Y, offset.Z * frente),
			color,
			padre
		)
		p.Material = Enum.Material.SmoothPlastic
		return p
	end

	-- Un cobertizo abierto por delante: dos laterales, fondo, techo y marquesina.
	pieza("TallerIzq", Vector3.new(1.2, alto, largo), Vector3.new(-ancho / 2, alto / 2, 0), CHAPA)
	pieza("TallerDer", Vector3.new(1.2, alto, largo), Vector3.new(ancho / 2, alto / 2, 0), CHAPA)
	pieza("TallerFondo", Vector3.new(ancho, alto, 1.2), Vector3.new(0, alto / 2, -largo / 2), CHAPA)
	pieza("TallerTecho", Vector3.new(ancho + 6, 1.2, largo + 8), Vector3.new(0, alto, 2), MARCO)
	local rotulo = pieza("TallerRotulo", Vector3.new(ancho, 3.4, 1), Vector3.new(0, alto + 2, largo / 2 + 5), MARCO)

	-- El rótulo, en las dos caras: se llega por delante y por detrás.
	for _, giro in { 0, 180 } do
		local cartel = Instance.new("SurfaceGui")
		cartel.Name = "Rotulo" .. giro
		cartel.Face = if giro == 0 then Enum.NormalId.Front else Enum.NormalId.Back
		cartel.CanvasSize = Vector2.new(800, 90)
		cartel.Adornee = rotulo
		cartel.Parent = rotulo

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBlack
		texto.Text = "VEHÍCULOS"
		texto.Parent = cartel
	end

	-- Tres expositores con los vehículos de la escalera, del más barato al más
	-- caro, cada uno con su nombre y su precio. Es el escaparate: enseñar lo que
	-- todavía no puedes pagar es lo que le da destino al dinero.
	local escaparate = { Config.VEHICULOS[2], Config.VEHICULOS[5], Config.VEHICULOS[7], Config.VEHICULOS[9] }
	for i, vehiculo in escaparate do
		if vehiculo == nil then
			continue
		end
		local x = (i - 2.5) * 16
		local podio = pieza("Podio" .. i, Vector3.new(9, 1.2, 9), Vector3.new(x, 0.6, -2), Color3.fromRGB(88, 86, 92))
		-- Una silueta tosca basta: lo que vende es el nombre y el precio de debajo,
		-- y una caja de color se lee como "aquí hay algo" desde la calle.
		local bulto = pieza(
			"Expuesto" .. i,
			Vector3.new(5.5, 3 + i, 8),
			Vector3.new(x, 1.2 + (3 + i) / 2, -2),
			Palette.ruta(if i == 1 then "verde" elseif i == 2 then "ambar" else "roja")
		)
		bulto.Material = Enum.Material.Metal

		-- SE COMPRA ESTE, no "el primero de la lista". El aviso de la losa compra lo
		-- más barato que te falte, que estaba bien cuando la escalera era una fila
		-- de mejoras; con el garaje hay que poder elegir CUÁL, porque un patinete
		-- teniendo furgoneta ya no es un capricho sino la llave de los atajos.
		local compra = prompt(bulto, "Comprar " .. vehiculo.nombre, string.format("%d", vehiculo.coste), 22)
		compra.Name = "PromptComprar"
		compra:SetAttribute("vehiculo", vehiculo.id)

		local etiqueta = Instance.new("BillboardGui")
		etiqueta.Name = "Precio"
		etiqueta.Size = UDim2.fromScale(9, 2.6)
		etiqueta.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		etiqueta.AlwaysOnTop = false
		etiqueta.MaxDistance = 160
		etiqueta.Adornee = bulto
		etiqueta.Parent = bulto

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextStrokeTransparency = 0.35
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = string.format("%s  ·  %d", vehiculo.nombre, vehiculo.coste)
		texto.Parent = etiqueta
		podio.Material = Enum.Material.Concrete
	end

	-- Luz de escaparate: sin ella, bajo el techo los tres expositores son bultos
	-- negros y el edificio parece cerrado.
	local plafon =
		pieza("TallerLuz", Vector3.new(10, 0.5, 2), Vector3.new(0, alto - 1.5, 0), Color3.fromRGB(240, 232, 210))
	plafon.CanCollide = false
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 236, 200)
	luz.Range = 42
	luz.Brightness = 1.6
	luz.Parent = plafon

	-- LAS PLAZAS DEL GARAJE, publicadas como atributos igual que el muelle del
	-- almacén. Los vehículos que hay en ellas NO se construyen aquí: son los de
	-- CADA jugador, así que los dibuja el cliente. Un garaje construido en el
	-- servidor enseñaría la moto de otro.
	-- UNA PLAZA POR VEHÍCULO COMPRABLE: si el garaje tuviera menos sitios que
	-- vehículos, comprar el noveno haría desaparecer a otro de la vista sin decir
	-- nada.
	local plazas = #Config.VEHICULOS - 1
	for i = 1, plazas do
		base:SetAttribute(
			"plaza" .. i,
			Vector3.new(base.Position.X + (i - (plazas + 1) / 2) * 11, suelo + 0.5, base.Position.Z + 17 * frente)
		)
	end
	base:SetAttribute("plazas", plazas)

	-- Tres expositores con los vehículos de la escalera, del más barato al más
	-- caro, cada uno con su nombre y su precio. Es el escaparate: enseñar lo que
	-- todavía no puedes pagar es lo que le da destino al dinero.
	local escaparate = { Config.VEHICULOS[2], Config.VEHICULOS[5], Config.VEHICULOS[7], Config.VEHICULOS[9] }
	for i, vehiculo in escaparate do
		if vehiculo == nil then
			continue
		end
		local x = (i - 2.5) * 16
		local podio = pieza("Podio" .. i, Vector3.new(9, 1.2, 9), Vector3.new(x, 0.6, -2), Color3.fromRGB(88, 86, 92))
		-- Una silueta tosca basta: lo que vende es el nombre y el precio de debajo,
		-- y una caja de color se lee como "aquí hay algo" desde la calle.
		local bulto = pieza(
			"Expuesto" .. i,
			Vector3.new(5.5, 3 + i, 8),
			Vector3.new(x, 1.2 + (3 + i) / 2, -2),
			Palette.ruta(if i == 1 then "verde" elseif i == 2 then "ambar" else "roja")
		)
		bulto.Material = Enum.Material.Metal

		-- SE COMPRA ESTE, no "el primero de la lista". El aviso de la losa compra lo
		-- más barato que te falte, que estaba bien cuando la escalera era una fila
		-- de mejoras; con el garaje hay que poder elegir CUÁL, porque un patinete
		-- teniendo furgoneta ya no es un capricho sino la llave de los atajos.
		local compra = prompt(bulto, "Comprar " .. vehiculo.nombre, string.format("%d", vehiculo.coste), 22)
		compra.Name = "PromptComprar"
		compra:SetAttribute("vehiculo", vehiculo.id)

		local etiqueta = Instance.new("BillboardGui")
		etiqueta.Name = "Precio"
		etiqueta.Size = UDim2.fromScale(9, 2.6)
		etiqueta.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		etiqueta.AlwaysOnTop = false
		etiqueta.MaxDistance = 160
		etiqueta.Adornee = bulto
		etiqueta.Parent = bulto

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextStrokeTransparency = 0.35
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = string.format("%s  ·  %d", vehiculo.nombre, vehiculo.coste)
		texto.Parent = etiqueta
		podio.Material = Enum.Material.Concrete
	end

	-- Luz de escaparate: sin ella, bajo el techo los tres expositores son bultos
	-- negros y el edificio parece cerrado.
	local plafon =
		pieza("TallerLuz", Vector3.new(10, 0.5, 2), Vector3.new(0, alto - 1.5, 0), Color3.fromRGB(240, 232, 210))
	plafon.CanCollide = false
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 236, 200)
	luz.Range = 42
	luz.Brightness = 1.6
	luz.Parent = plafon

	-- LAS PLAZAS DEL GARAJE, publicadas como atributos igual que el muelle del
	-- almacén. Los vehículos que hay en ellas NO se construyen aquí: son los de
	-- CADA jugador, así que los dibuja el cliente. Un garaje construido en el
	-- servidor enseñaría la moto de otro.
	-- UNA PLAZA POR VEHÍCULO COMPRABLE: si el garaje tuviera menos sitios que
	-- vehículos, comprar el noveno haría desaparecer a otro de la vista sin decir
	-- nada.
	local plazas = #Config.VEHICULOS - 1
	for i = 1, plazas do
		base:SetAttribute(
			"plaza" .. i,
			Vector3.new(base.Position.X + (i - (plazas + 1) / 2) * 11, suelo + 0.5, base.Position.Z + 17 * frente)
		)
	end
	base:SetAttribute("plazas", plazas)

	-- Y su baliza, como la de la salida: hay que poder encontrarlo desde el otro
	-- lado del recinto sin dar vueltas.
	local baliza = part(
		"Baliza_Taller",
		Vector3.new(5, 46, 5),
		Vector3.new(base.Position.X, suelo + 23, base.Position.Z),
		Palette.TALLER,
		padre
	)
	baliza.CanCollide = false
	baliza.Material = Enum.Material.Neon
	baliza.Transparency = 0.25
end

local function refugio(ciudad: Instance?, indice: number, centro: Vector3, padre: Instance): BasePart?
	local y, x, z = sueloTransitable(ciudad, centro.X, centro.Z)
	if y == nil then
		-- Sin calle donde plantarlo. Se omite en vez de ponerlo en una azotea: un
		-- refugio inalcanzable es peor que uno menos, porque el jugador lo ve en el
		-- mapa, se desvía hacia él y descubre que no se puede entrar justo cuando
		-- lo necesitaba.
		return nil
	end

	local AZUL = Color3.fromRGB(74, 118, 176)
	local AZUL_OSCURO = Color3.fromRGB(44, 70, 108)
	local PIEDRA = Color3.fromRGB(196, 198, 202)

	local losa = part(
		"Refugio_" .. indice,
		Vector3.new(Config.REFUGIO_RADIO * 1.2, ALTO_LOSA, Config.REFUGIO_RADIO * 1.2),
		Vector3.new(x, y + ALTO_LOSA / 2, z),
		AZUL,
		padre
	)
	losa.Material = Enum.Material.Pavement
	losa:SetAttribute("refugio", true)

	-- UNA CASETA DE VERDAD, no una losa pintada de azul.
	--
	-- Lo pidió JJ y tiene razón de sobra: el refugio es el sitio al que corres
	-- cuando te persiguen, y tiene que reconocerse como un EDIFICIO desde lejos y
	-- de reojo. Una mancha de color en el suelo se confunde con cualquier plaza de
	-- la ciudad justo en el momento en que no puedes pararte a mirar.
	--
	-- Abierta por los cuatro lados a propósito: son cuatro pilares y un techo. Un
	-- refugio con paredes tendría puerta, y una puerta es un sitio donde quedarse
	-- atascado con tres perseguidores detrás.
	local suelo = y + ALTO_LOSA
	local alto, vano = 16, 13

	local function pieza(nombre: string, tamano: Vector3, dx: number, dy: number, dz: number, color: Color3)
		local p = part(nombre, tamano, Vector3.new(x + dx, suelo + dy, z + dz), color, padre)
		p.Material = Enum.Material.Concrete
		return p
	end

	for i, esquina in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		pieza(
			string.format("RefugioPilar_%d_%d", indice, i),
			Vector3.new(3, alto, 3),
			esquina[1] * vano,
			alto / 2,
			esquina[2] * vano,
			PIEDRA
		)
	end
	pieza("RefugioTecho_" .. indice, Vector3.new(vano * 2 + 9, 2.5, vano * 2 + 9), 0, alto + 1.25, 0, AZUL_OSCURO)
	-- Una franja encendida bajo el alero: de noche o en sombra, es lo que hace que
	-- el sitio se lea como "abierto" y no como una ruina.
	local franja = pieza(
		"RefugioFranja_" .. indice,
		Vector3.new(vano * 2 + 9, 1.2, vano * 2 + 9),
		0,
		alto - 0.6,
		0,
		Color3.fromRGB(150, 200, 255)
	)
	franja.Material = Enum.Material.Neon
	franja.CanCollide = false

	-- Y el pilar de luz por encima de los edificios (llegan a 175 studs), para
	-- verlo desde la otra punta del barrio.
	local faro = part("RefugioFaro_" .. indice, Vector3.new(5, 190, 5), Vector3.new(x, y + 95, z), AZUL, padre)
	faro.Material = Enum.Material.Neon
	faro.CanCollide = false
	faro.Transparency = 0.25

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(120, 180, 255)
	luz.Range = 60
	luz.Brightness = 2
	luz.Parent = losa

	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Cartel"
	cartel.Size = UDim2.fromScale(22, 6)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 110, 0)
	cartel.AlwaysOnTop = true
	cartel.MaxDistance = 1400
	cartel.Adornee = faro
	cartel.Parent = faro

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(220, 235, 255)
	texto.TextStrokeTransparency = 0.2
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = "COMISARÍA"
	texto.Parent = cartel

	return losa
end

export type Mundo = {
	almacen: BasePart,
	salida: BasePart,
	talleres: { BasePart },
	aparicion: BasePart,
	destinos: { BasePart },
	detectores: { BasePart },
	-- Posiciones, no piezas: quien los consulta (calor, patrullas, robo) sólo
	-- necesita saber dónde están, y pasar las piezas invitaría a que alguien
	-- empezara a leerles propiedades y a depender de cómo están dibujados.
	refugios: { Vector3 },
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

	-- EL POLÍGONO PRIMERO: el almacén, el taller y la salida van encima de él, no
	-- dentro de la ciudad. Ya no hace falta despejar nada aquí -- es terreno
	-- nuestro y está vacío por construcción.
	--
	-- Se llama `poligono` y no `explanada` porque YA HABÍA una `explanada`: la
	-- plancha de respaldo para cuando no hay ciudad. Dos funciones locales con el
	-- mismo nombre no dan ningún error en Luau -- la segunda pisa a la primera-- y
	-- el resultado fue que el polígono no se construía y nadie se enteraba.
	poligono(ciudad, mundo)
	local almacen = losa(ciudad, "Almacen", Vector3.new(90, ALTO_LOSA, 90), Config.ALMACEN_POS, Palette.ALMACEN, mundo)
	-- La boca mira a la SALIDA: es de donde vienes y a donde vas cada viaje.
	-- DEJAR CARGA, en la propia losa del almacén. El muelle sólo daba y nunca
	-- recibía ("no puedo dejar paquetes en el almacén", JJ), así que elegir mal lo
	-- que cargabas no tenía marcha atrás.
	prompt(almacen, "Dejar carga aquí", "Almacén", 30).Name = "PromptDevolver"

	local frenteCasa = if Config.POLIGONO_SALIDA.Z < Config.ALMACEN_POS.Z then -1 else 1
	nave(almacen, mundo, frenteCasa)
	muelle(almacen, frenteCasa)

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
	-- La salida va en LA BOCA DEL POLÍGONO, que es el único sitio por donde se sale
	-- a la ciudad. Antes se calculaba como "60 studs hacia el centro del mapa" y
	-- con el polígono eso caería en mitad del patio, sin ningún borde que cruzar.
	local salidaPos = Config.POLIGONO_SALIDA
	local salida = losa(
		ciudad,
		"Salida",
		Vector3.new(LADO_SALIDA, ALTO_LOSA, LADO_SALIDA),
		Vector3.new(salidaPos.X, Config.ALMACEN_POS.Y, salidaPos.Z),
		Palette.SALIDA,
		mundo
	)

	-- Y su baliza, que es lo que la convierte en un sitio al que se puede VOLVER.
	-- Los tres destinos tenían la suya desde el principio y la salida no, y eso
	-- dejaba el peor hueco posible: la única losa que hay que encontrar con la
	-- carga puesta era también la única invisible. Más baja que las de destino
	-- (60 studs frente a 300) porque se busca desde dentro del recinto, no desde
	-- el otro extremo del mapa.
	local balizaSalida =
		part("Baliza_Salida", Vector3.new(5, 55, 5), salida.Position + Vector3.new(0, 27, 0), Palette.SALIDA, mundo)
	balizaSalida.CanCollide = false
	balizaSalida.Material = Enum.Material.Neon
	-- Más baja y menos encendida que antes (110 studs y opaca). Tenía que gritar
	-- cuando la salida era una losa perdida entre edificios; ahora está en la boca
	-- de un polígono cerrado por muros, y un pilar de cien studs en mitad del patio
	-- tapaba la vista de la propia base.
	balizaSalida.Transparency = 0.35

	local cartelSalida = Instance.new("BillboardGui")
	cartelSalida.Name = "Cartel"
	cartelSalida.Size = UDim2.fromScale(30, 8)
	cartelSalida.StudsOffsetWorldSpace = Vector3.new(0, 34, 0)
	-- POR ENCIMA DE TODO, al contrario que los carteles de los destinos. Los de
	-- fuera se ocultan tras los edificios a propósito (esconderse tiene que servir
	-- de algo), pero éste está dentro de tu propio recinto y su único trabajo es
	-- que no te pierdas al salir de la nave, que es literalmente lo que pasó.
	cartelSalida.AlwaysOnTop = true
	cartelSalida.MaxDistance = 700
	cartelSalida.Adornee = balizaSalida
	cartelSalida.Parent = balizaSalida

	local textoSalida = Instance.new("TextLabel")
	textoSalida.Size = UDim2.fromScale(1, 1)
	textoSalida.BackgroundTransparency = 1
	textoSalida.TextColor3 = Color3.fromRGB(255, 255, 255)
	textoSalida.TextStrokeTransparency = 0.2
	textoSalida.TextScaled = true
	textoSalida.Font = Enum.Font.GothamBold
	textoSalida.Text = "SALIDA  ·  elige destino"
	textoSalida.Parent = cartelSalida

	-- El taller, al otro lado: pasar por delante de la tienda al salir convertiría
	-- la mejora en un anuncio, pero está DENTRO de la zona segura, así que nadie
	-- puede emboscar a quien compra.
	-- EL CAMINO PINTADO del muelle a la salida. Un cartel dice DÓNDE está; una
	-- línea en el suelo dice POR DÓNDE se va, y es lo que de verdad resuelve el
	-- "le doy a 'ahora no' y no sé dónde tengo que ir". Se sigue sin pensar y sin
	-- levantar la vista, que es como se anda cargado.
	do
		local desde = almacen.Position + Vector3.new(0, almacen.Size.Y / 2, 0)
		local hasta = salida.Position + Vector3.new(0, salida.Size.Y / 2, 0)
		local tramos = 14
		for i = 1, tramos do
			local t = (i - 0.5) / tramos
			local punto = desde:Lerp(hasta, t)
			local y = sueloDeLaCiudad(ciudad, punto.X, punto.Z) or punto.Y
			local raya = part(
				"Sendero" .. i,
				Vector3.new(2.6, 0.25, 5),
				Vector3.new(punto.X, y + 0.2, punto.Z),
				Palette.SALIDA,
				mundo
			)
			raya.CanCollide = false
			raya.Material = Enum.Material.Neon
			raya.Transparency = 0.35
			raya.CastShadow = false
			raya:SetAttribute("rodable", true)
			-- Orientada a lo largo del camino: una raya atravesada parecería un paso de
			-- cebra y diría justo lo contrario de lo que quiere decir.
			raya.CFrame = CFrame.lookAt(raya.Position, Vector3.new(hasta.X, y + 0.2, hasta.Z))
		end
	end

	local talleres: { BasePart } = {}

	-- El taller de casa va en el polígono, al lado del almacén: nada que despejar.
	local taller = losa(ciudad, "Taller", Vector3.new(96, ALTO_LOSA, 60), Config.TALLER_POS, Palette.TALLER, mundo)
	prompt(taller, "Comprar vehículo", "Concesionario", 26).Name = "PromptTaller"
	concesionario(taller, mundo, frenteCasa)
	table.insert(talleres, taller)

	local destinos: { BasePart } = {}
	local detectores: { BasePart } = {}

	for _, ruta in Routes.todas() do
		despejar(ciudad, ruta.destino, 50, 45)
		local destino = losa(
			ciudad,
			"Destino_" .. ruta.id,
			Vector3.new(44, ALTO_LOSA, 44),
			ruta.destino,
			Palette.ruta(ruta.id),
			mundo
		)
		destino:SetAttribute("ruta", ruta.id)

		-- Y SU ACCESO RODADO hasta la calle más cercana. Sin esto, la mercancía
		-- grande era una contradicción: exige vehículo, y el vehículo no podía
		-- llegar hasta la losa.
		local calle = calleMasCercana(ciudad, destino.Position, 220)
		if calle ~= nil then
			acceso(
				ciudad,
				"Acceso_" .. ruta.id,
				bordeDeLosa(destino, calle),
				Vector3.new(calle.X, calle.Y, calle.Z),
				20,
				mundo,
				-- Sale al ras de la losa del destino y muere al ras de la calle.
				destino.Position.Y + ALTO_LOSA / 2,
				calle.Y + 0.2
			)
		else
			warn("[Contrabando] el destino " .. ruta.id .. " no tiene calle a menos de 220 studs")
		end

		-- Y SU TALLER AL LADO. Decisión de JJ: cambiar de vehículo no puede costar
		-- un viaje entero de vuelta a casa, sobre todo ahora que tener varios
		-- significa elegir el bueno para el trayecto (ver el garaje en
		-- Vehicles.posee).
		--
		-- El sitio se busca en un anillo alrededor del destino y se queda con el
		-- primero que esté LIMPIO: plantarlo a ciegas a una distancia fija es como
		-- acabó el primero encima de una pista de baloncesto.
		do
			-- CON CALLE, no sólo despejado. Es el segundo requisito y llegó midiendo:
			-- el taller de la ámbar cayó en un descampado a sesenta studs por debajo
			-- de la ciudad, sin una calzada a doscientos studs a la redonda. Estaba
			-- limpio, sí -- limpio como un solar al que no llega ningún coche, y un
			-- concesionario al que no se puede llegar en coche no es un sitio, es un
			-- adorno.
			local sitio, calleTaller = nil, nil
			for vuelta = 0, 11 do
				local angulo = vuelta * math.pi / 6
				local candidato = ruta.destino + Vector3.new(math.cos(angulo) * 58, 0, math.sin(angulo) * 58)
				local y = sueloDeLaCiudad(ciudad, candidato.X, candidato.Z)
				if y ~= nil then
					local centro = Vector3.new(candidato.X, y, candidato.Z)
					local libre = despejarCuenta(ciudad, centro, 110)
					if libre == 0 then
						local calle = calleMasCercana(ciudad, centro, 200)
						if calle ~= nil then
							sitio, calleTaller = centro, calle
							break
						end
					end
				end
			end
			if sitio == nil then
				warn("[Contrabando] la zona " .. ruta.id .. " no tiene sitio despejado con calle: se queda sin taller")
			end
			if sitio ~= nil then
				despejar(ciudad, sitio, 110, 45)
				local tallerZona =
					losa(ciudad, "Taller_" .. ruta.id, Vector3.new(96, ALTO_LOSA, 60), sitio, Palette.TALLER, mundo)
				prompt(tallerZona, "Comprar vehículo", "Concesionario", 26).Name = "PromptTaller"
				-- Y los de las zonas miran a su destino, que es donde está la acción.
				concesionario(tallerZona, mundo, if ruta.destino.Z < sitio.Z then -1 else 1)
				-- La calle es la que se encontró al elegir el sitio: buscarla otra vez
				-- desde la losa ya construida es darle la ocasión de contestar otra
				-- cosa, y entonces el taller y su carretera dejan de casar.
				if calleTaller ~= nil then
					acceso(
						ciudad,
						"AccesoTaller_" .. ruta.id,
						bordeDeLosa(tallerZona, calleTaller),
						Vector3.new(calleTaller.X, calleTaller.Y, calleTaller.Z),
						18,
						mundo,
						tallerZona.Position.Y + ALTO_LOSA / 2,
						calleTaller.Y + 0.2
					)
				end
				table.insert(talleres, tallerZona)
			end
		end
		-- SIN aviso de entrega: llegar al destino con la carga correcta YA cobra
		-- solo (ver CargoService.arrancarEntregaAutomatica). No existe ninguna razón
		-- para llegar y no querer entregar, así que pedir confirmación era un paso
		-- muerto -- y caía justo en el único momento del bucle en que el juego te da
		-- algo. La tecla E se queda como red de seguridad y como la única vía que
		-- EXPLICA por qué no puedes cobrar cuando no puedes.

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

	-- Los refugios, uno por cada sitio que propone Shelter para cada ruta. Se
	-- plantan DESPUÉS de los destinos porque sólo tienen sentido sobre un trayecto
	-- que ya existe.
	-- LOS REFUGIOS. Se juntan las propuestas de las tres rutas y se pasan por
	-- Shelter.repartir, que descarta los que caen demasiado cerca de otro: cada
	-- ruta propone a ciegas y dos que pasen cerca plantarían los suyos casi
	-- pegados.
	--
	-- Se piden CANDIDATOS DE SOBRA (dos más de los que se van a plantar) y se pasan
	-- AGRUPADOS POR RUTA. Las dos cosas por el mismo motivo: si el sitio natural de
	-- una ruta cae cerca del de otra, Shelter puede coger el siguiente de ESA MISMA
	-- ruta en vez de dejarla sin refugio -- que es lo que pasaba, y lo destapó la
	-- sonda del mundo.
	local grupos: { { Vector3 } } = {}
	for _, ruta in Routes.todas() do
		table.insert(grupos, Shelter.sitiosDeRuta(Config.ALMACEN_POS, ruta.destino, Config.REFUGIOS_POR_RUTA + 2))
	end
	local refugios: { Vector3 } = {}
	for _, sitio in Shelter.repartir(grupos) do
		local pieza = refugio(ciudad, #refugios + 1, sitio, mundo)
		if pieza then
			table.insert(refugios, pieza.Position)
		end
	end

	return {
		almacen = almacen,
		salida = salida,
		talleres = talleres,
		aparicion = spawn,
		destinos = destinos,
		detectores = detectores,
		refugios = refugios,
	}
end

return CityBuilder
