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
local Cone = require(script.Parent.Cone)
local Vision = require(game.ReplicatedStorage.Shared.Vision)
local Grid = require(game.ReplicatedStorage.Shared.Grid)
local Detectors = require(game.ReplicatedStorage.Shared.Detectors)
local PathfindingService = game:GetService("PathfindingService")

local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
local Lairs = require(game.ReplicatedStorage.Shared.Lairs)
-- Ride, para poner el vehículo de verdad en el escaparate en vez de una caja.
local Ride = require(script.Parent.Ride)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local Shelter = require(game.ReplicatedStorage.Shared.Shelter)
local Warehouse = require(game.ReplicatedStorage.Shared.Warehouse)
local Strings = require(game.ReplicatedStorage.Shared.Strings)

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

-- La cota de la línea que dibuja la ruta en el suelo. Por encima de la calzada (19,2)
-- y de las losas del juego (19,6) con margen de sobra: dos superficies a menos de dos
-- décimas parpadean, y esa lección ya costó una tarde.
local Y_LINEA_RUTA = 19.9

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
-- LOS ÁRBOLES NO SON SUELO, y esta ciudad tiene 2.048 copas y 2.720 troncos. Un
-- rayo desde el cielo se para en la primera hoja que encuentra, así que en un
-- parque el "suelo" salía a 79 o a 101 studs de altura -- y el sitio quedaba
-- descartado por imposible cuando en realidad era césped llano. El Refugio_1 daba
-- 13 de sus 25 muestras "bajo techo": todas eran hojas.
--
local function sueloDeLaCiudad(ciudad: Instance?, x: number, z: number): number?
	if not ciudad then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }
	local r = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -800, 0), params)
	return if r then r.Position.Y else nil
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

-- EL PERFIL DEL TERRENO BAJO UNA HUELLA ENTERA, no bajo un punto.
--
-- Todo lo que este fichero planta medía el suelo con UN rayo en el centro y dejaba
-- encima una losa plana. En terreno llano eso funciona; en una ladera no, y la
-- ciudad tiene laderas: *"cuidado con las guaridas, que las he visto no muy
-- alineadas con el terreno"* (JJ). Medido después de mirarlo: la Guarida_1 volaba
-- 20 studs por una esquina y la tierra se la comía 32 por la contraria, y el
-- Refugio_1 estaba en la misma ladera con 37 de diferencia entre lados.
--
-- Devuelve la cota más baja, la más alta y cuántas muestras se salen -- sin suelo
-- (un hueco entre parcelas) o por encima de la cota de calle (un edificio que pisa
-- la parcela). Las dos cosas descalifican un sitio igual que un desnivel.
local function perfilDelSuelo(
	ciudad: Instance?,
	centro: Vector3,
	ancho: number,
	largo: number
): (number?, number, number)
	-- REJILLA DE 5×5, no una cruz de nueve puntos, y esto también lo enseñó una
	-- medida: con nueve muestras el taller de la ámbar --que mide 96 por 60-- dio
	-- un perfil perfectamente llano mientras una franja de césped de 93 studs de
	-- ancho le cruzaba una esquina por medio. Los rayos pasaron de largo por los
	-- dos lados. Una huella grande necesita muestras cada veinte studs o el hueco
	-- entre rayos es más grande que lo que se busca.
	local dx, dz = ancho / 2 - 1, largo / 2 - 1
	local bajo, alto, fuera = math.huge, -math.huge, 0
	for i = -2, 2 do
		for k = -2, 2 do
			local y = sueloDeLaCiudad(ciudad, centro.X + (i / 2) * dx, centro.Z + (k / 2) * dz)
			if y == nil or y > COTA_CALLE then
				fuera += 1
			else
				bajo = math.min(bajo, y)
				alto = math.max(alto, y)
			end
		end
	end
	if bajo == math.huge then
		return nil, 0, fuera
	end
	return bajo, alto, fuera
end

-- Un sitio LLANO Y ENTERO para una huella, buscando en anillos hacia fuera.
--
-- Es sueloTransitable con la lección aprendida: aquél buscaba un punto de calle y
-- se daba por satisfecho, y por eso las cosas acababan a medio meter en un talud.
-- Éste no acepta un sitio hasta que la huella COMPLETA se apoya.
--
-- Si no encuentra ninguno dentro de la tolerancia se queda con el MENOS malo en
-- vez de rendirse: una guarida algo torcida sigue siendo mejor que ninguna, y
-- quien llame decide qué hacer con el desnivel que se le devuelve.
local function sitioLlano(
	ciudad: Instance?,
	centro: Vector3,
	ancho: number,
	largo: number,
	tolerancia: number,
	ocupados: { Vector3 }?,
	separacion: number?,
	alcance: number?
): (Vector3?, number)
	local mejor: Vector3? = nil
	local mejorNota = math.huge

	-- LO QUE YA ESTÁ PLANTADO NO VALE, y hace falta decirlo porque buscar sitio
	-- llano mueve las cosas hasta cien studs: la primera vez que corrió esto, dos
	-- guaridas encontraron el MISMO solar bueno y acabaron una encima de otra. No
	-- dio ningún error -- simplemente había siete guaridas donde debía haber ocho,
	-- y una ruta con menos peligro del que anuncia.
	local function libre(p: Vector3): boolean
		if ocupados == nil or separacion == nil then
			return true
		end
		for _, otro in ocupados do
			local dx, dz = p.X - otro.X, p.Z - otro.Z
			if math.sqrt(dx * dx + dz * dz) < separacion then
				return false
			end
		end
		return true
	end

	-- SE PUNTÚAN TODOS Y GANA EL MEJOR; no se descarta nadie por no llegar al
	-- listón. La primera versión exigía sitio perfecto y devolvía nil si no lo
	-- encontraba, y el resultado fue peor que el defecto que venía a arreglar: se
	-- quedaron una guarida y un refugio sin plantar, y una ruta sin sitio donde
	-- bajar el peligro es un agujero de juego, mientras que una losa un poco
	-- torcida --con su zócalo-- es sólo una losa un poco torcida.
	--
	-- La nota junta las dos cosas que estropean un emplazamiento: el desnivel en
	-- studs y las muestras que se salen (sin suelo o dentro de un edificio), estas
	-- últimas a tres studs cada una para que pesen más que una cuesta suave.
	-- HASTA DÓNDE SE PUEDE MOVER. No es un detalle: la primera versión buscaba
	-- hasta cien studs en cualquier dirección y el refugio de la verde se fue tan
	-- lejos del camino que dejó de estar "a mano" -- que era su único trabajo.
	-- Cada quien sabe cuánto margen tiene sobre su ruta y lo dice aquí.
	for radio = 0, alcance or 100, 10 do
		local pasos = if radio == 0 then 1 else 12
		for k = 0, pasos - 1 do
			local a = k * math.pi / 6
			local p = Vector3.new(centro.X + math.cos(a) * radio, centro.Y, centro.Z + math.sin(a) * radio)
			if not libre(p) then
				continue
			end
			local bajo, alto, fuera = perfilDelSuelo(ciudad, p, ancho, largo)
			if bajo ~= nil then
				local nota = (alto - bajo) + fuera * 3
				if fuera == 0 and alto - bajo <= tolerancia then
					return Vector3.new(p.X, alto, p.Z), alto - bajo
				end
				if nota < mejorNota then
					mejor, mejorNota = Vector3.new(p.X, alto, p.Z), nota
				end
			end
		end
	end

	return mejor, mejorNota
end

-- Distancia de un punto al segmento a→b, medida en el plano. La usan las
-- comprobaciones de "esto no puede pasar por encima de aquello".
local function aLaRecta(punto: Vector3, a: Vector3, b: Vector3): number
	local ax, az = a.X, a.Z
	local bx, bz = b.X, b.Z
	local dx, dz = bx - ax, bz - az
	local largo = dx * dx + dz * dz
	if largo < 1 then
		return math.sqrt((punto.X - ax) ^ 2 + (punto.Z - az) ^ 2)
	end
	local t = math.clamp(((punto.X - ax) * dx + (punto.Z - az) * dz) / largo, 0, 1)
	return math.sqrt((punto.X - (ax + dx * t)) ^ 2 + (punto.Z - (az + dz * t)) ^ 2)
end

-- EL ZÓCALO: lo que va entre una losa y el suelo cuando el terreno cae bajo ella.
--
-- Es lo que hace cualquier edificio de verdad en una cuesta, y sale mucho más
-- barato que exigir que todos los sitios del mapa sean llanos -- porque no lo son.
-- Toda losa se apoya en el punto MÁS ALTO de su huella (así no hay nada
-- enterrado) y este bloque tapa el hueco que queda por el lado bajo, que si no se
-- ve por debajo y delata que la pieza está puesta encima del mapa y no en él.
local function zocalo(losa: BasePart, bajo: number, padre: Instance)
	local suelo = losa.Position.Y - losa.Size.Y / 2
	local caida = suelo - bajo
	if caida <= 0.6 then
		return
	end
	-- CON MARGEN POR ABAJO. La cota más baja se mide con veinticinco rayos, y basta
	-- que el terreno tenga un escalón entre dos de ellos --o que algo cambie después
	-- de construir-- para que el zócalo se quede corto y vuelva a verse el hueco.
	-- Enterrar ocho studs de más no lo ve nadie; que falten cuatro, sí.
	local MARGEN = 8
	local pieza = part(
		losa.Name .. "Zocalo",
		-- Un pelo más estrecho que la losa, para que el borde de arriba siga
		-- leyéndose como un escalón y no como un bloque macizo.
		-- Y LA CARA, MEDIO STUD POR DEBAJO DE LA LOSA. Antes subía ALTO_LOSA por
		-- encima de la base --o sea que asomaba por el costado-- y con la losa ya
		-- empotrada eso dejaba su borde a un par de décimas de la calzada: dos
		-- superficies a esa distancia parpadean. El zócalo existe para tapar el hueco
		-- de abajo, no para verse.
		Vector3.new(losa.Size.X - 1.5, caida + MARGEN, losa.Size.Z - 1.5),
		Vector3.new(losa.Position.X, suelo - 0.5 - (caida + MARGEN) / 2, losa.Position.Z),
		Color3.new(losa.Color.R * 0.55, losa.Color.G * 0.55, losa.Color.B * 0.55),
		padre
	)
	pieza.Material = Enum.Material.Concrete
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

-- ¿Se puede quitar esta pieza de la ciudad para construir encima?
--
-- La primera regla era sólo "si no es enorme", y dejaba pasar justo lo que peor
-- encaja: los SETOS Y LAS VALLAS. Un seto de 6 × 10 × 233 mide más de doscientos
-- studs de largo, así que se libraba de la escoba, y luego salía atravesando la
-- Guarida_5 y su nave de lado a lado. Lo mismo con las vallas que cruzaban cinco
-- tramos de carretera.
--
-- La diferencia entre un seto y un edificio no es el tamaño, es la FORMA: un
-- edificio es grande en dos direcciones, un seto sólo en una. Así que se mira el
-- segundo lado más largo -- y además que sea bajo, para no llevarse por delante
-- un muro largo y fino que sí es arquitectura.
local function esDespejable(pieza: BasePart): boolean
	-- LO QUE PLANTA EL MAPA NO SE TOCA. Esta función nació para apartar la chatarra
	-- de un mapa ajeno (vallas, matorrales, farolas sueltas) y su criterio es de
	-- tamaño, porque contra un modelo del Creator Store no había otra cosa a la que
	-- agarrarse. Con mapa propio sí la hay, y hace falta: una acera nuestra mide
	-- 120 x 1,5 x 6 y este criterio la considera estorbo, así que las losas de
	-- destino se comían las aceras de media ciudad. Las calles se libraban por un
	-- stud.
	if pieza:GetAttribute("delMapa") then
		return false
	end
	if math.max(pieza.Size.X, pieza.Size.Y, pieza.Size.Z) <= LIMITE_PIEZA_GRANDE then
		return true
	end
	local lados = { pieza.Size.X, pieza.Size.Y, pieza.Size.Z }
	table.sort(lados, function(a, b)
		return a > b
	end)
	return lados[2] <= 25 and pieza.Size.Y <= 14
end

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

-- `arrasar` = también se lleva por delante lo que plantó el mapa.
--
-- Por defecto NO se toca: el mapa es nuestro y sus aceras y edificios no son chatarra
-- que apartar (ver esDespejable). Pero cuando lo que se planta es una PIEZA DEL JUEGO
-- --una guarida, un refugio, un taller-- el juego manda sobre la estética, y sin esto
-- no encuentra hueco en una ciudad con las manzanas cerradas: los refugios se alejaban
-- del camino buscando sitio hasta quedar a 63 studs, y una guarida acabó encima del
-- destino del barrio.
--
-- Son cuatro o cinco piezas en todo el mapa. Que le hagan un hueco al caserío es
-- exactamente lo que pasa en una ciudad cuando se construye una comisaría.
local function despejar(ciudad: Instance?, centro: Vector3, lado: number, alto: number, arrasar: boolean?): number
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
		if esDespejable(pieza) or (arrasar == true and pieza:GetAttribute("derribable") == true) then
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
-- CUÁNTO puede levantar la vía un rayo de al lado, y por qué es tan poco.
--
-- La función de abajo se queda con el suelo MÁS ALTO de cinco rayos --el del centro
-- y cuatro alrededor-- para que la calzada no quede enterrada cuando el terreno
-- sube por un costado. El tope es lo que impide que ese máximo recoja un tejado.
--
-- ⚠ NO ES ESTE TOPE lo que levantaba el acceso a la verde, aunque lo parecía. Se
-- probó bajarlo de 4 a 1,6 y el perfil salió idéntico al decimal: el pico entraba
-- por el rayo CENTRAL, que no lleva tope --ni debe llevarlo, porque es el que va
-- por donde de verdad pasa la vía-- y se arregla más abajo, limitando las cotas
-- desde los extremos. Queda escrito para que nadie repita el intento.
local LEVANTE_MAXIMO = 4

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
		if y ~= nil and y > alto and y - centro <= LEVANTE_MAXIMO then
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
-- LAS VÍAS DE ACCESO SE ELIMINARON EL 19/08. Aquí vivía acceso(), que tendía una
-- carretera desde cada losa del juego hasta la calle más cercana.
--
-- Existía porque en la ciudad prestada una losa caía donde cabía --sobre césped,
-- sobre una loma, en mitad de un parque-- y había que unirla al asfalto a mano. En
-- la retícula propia la calzada cubre el mapa entero y los destinos están EN cruces
-- de calle: no hay nada que unir, la vía se tendía encima del asfalto que ya estaba
-- y las dos superficies, a dos décimas una de otra, PARPADEABAN. Fue lo primero que
-- dijo JJ al entrar: "no para de parpadear la carretera".
--
-- Doscientas veinticinco líneas primero, cincuenta y tres después de simplificarla,
-- y al final ninguna: la solución de un problema que el mapa nuevo ya no tiene.

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

	-- A SU COTA DE SIEMPRE. Se probó a subirlo cuatro décimas para separarlo de la
	-- calzada --se solapan doce studs y estaban coplanares, que es el peor parpadeo que
	-- hay-- y el remedio fue peor: dentro del recinto TODO se apoya en esta cota, así
	-- que subir el suelo lo puso por encima del almacén, de la salida y del taller. La
	-- sonda lo cantó a la primera: "Almacen se pisa por arriba, lo que se pisa ahí es
	-- Poligono".
	--
	-- El solape se arregla donde nace: la calzada de la ciudad ya no entra aquí.
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
	-- Y SE LE DICE DÓNDE TERMINA, que es lo que le faltaba y costó caro.
	--
	-- Ésta era la única vía del juego que se tendía sin `cotaFinal`: las de los
	-- destinos reciben la cota de la calle a la que llegan, y ésta se quedaba con lo
	-- que midiera el trazado en su último punto. Resultado medido al encoger el
	-- mundo: la carretera del recinto **moría volando 3,4 studs sobre el césped**, y
	-- ese canto CORTA EL NAVMESH -- el pathfinder no podía salir del recinto, así
	-- que las CUATRO rutas se quedaron sin camino a la vez. Nada reventó: el mundo
	-- se construyó entero, las losas y las balizas en su sitio, y simplemente no se
	-- podía llegar a ninguna parte andando.
	--
	-- Es la misma lección que las vías de los destinos ya tenían aprendida: los dos
	-- extremos son los únicos puntos de los que se sabe la respuesta sin medirla, y
	-- callarse uno es dejar que lo adivine un rayo.
	-- Sin carretera de enganche: la boca del recinto ESTÁ en la calle 1 de la retícula
	-- (Config.POLIGONO_ENGANCHE se deriva de ahí), así que se sale pisando asfalto.

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

	-- SIN FAROLAS. Eran cuatro postes de 22 studs con su luz, puestos para que el
	-- recinto no fuera una mancha negra de noche. Pero el juego corre a las 18:00 y
	-- nunca anochece, así que alumbraban un sitio ya iluminado -- decoración vertical
	-- pura, de la que JJ pidió quitar ("quita árboles o palos que he visto, dejemos un
	-- mapa básico").
	--
	-- El día que haya ciclo de día y noche, vuelven.
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
	local enCasa = Perimeter.dentro(centro, 6)

	-- FUERA DE CASA MANDA LA HUELLA ENTERA, no el centro. Con una sola muestra, una
	-- losa en cuesta se hunde por un lado y vuela por el otro -- y eso se ve, se
	-- pisa y se lee como un juego mal montado. Se apoya en el punto MÁS ALTO del
	-- terreno que cubre, para que no quede nada enterrado, y el hueco que deja por
	-- el lado bajo lo tapa el zócalo de aquí abajo.
	-- OJO CON LA FORMA DE ESCRIBIR ESTO. La primera versión decía
	--     local bajo, alto = if enCasa then nil else perfilDelSuelo(...)
	-- y un `if` de expresión devuelve UN valor, así que `alto` se quedaba en nil y
	-- la losa acababa apoyada en la muestra del centro -- justo lo que este cambio
	-- venía a quitar. No dio ningún error: el taller de la roja se hundía 2,8 studs
	-- y el zócalo, que sí recibía su dato, tapaba el hueco de abajo como si todo
	-- estuviera bien. Se ve sólo midiendo el mundo construido.
	local bajo: number? = nil
	local alto: number? = nil
	if not enCasa then
		bajo, alto = perfilDelSuelo(ciudad, centro, tamano.X, tamano.Z)
	end
	local y = if enCasa
		then Config.POLIGONO_CENTRO.Y
		else (alto or sueloDeLaCiudad(ciudad, centro.X, centro.Z) or centro.Y)
	-- EMPOTRADA EN EL SUELO, NO APOYADA ENCIMA. Esto ponía la base de la losa en `y`,
	-- así que la pieza sobresalía ALTO_LOSA entera: sobre el terreno irregular de la
	-- ciudad prestada eso era una plataforma --lo que se quería-- y sobre asfalto
	-- plano es un muro de dos studs alrededor de cada sitio del juego.
	--
	-- Medido el 19/08 con un perfil del suelo desde la boca del recinto: la losa de la
	-- salida quedaba a 21,2 con la calzada a 19,2, y ese escalón cortaba el camino a
	-- pie SIN SALTAR de las CUATRO rutas a la vez, nada más salir de casa. El destino
	-- del barrio hacía lo mismo 2,8 studs más arriba. Nada revienta: se llega dando un
	-- brinco, el mundo se construye igual, y sólo el pathfinder --o sea las patrullas
	-- y los ladrones-- se queda fuera.
	--
	-- Los cinco centímetros son para que la cara de la losa no quede EXACTAMENTE en el
	-- plano del asfalto: dos superficies coplanares parpadean, y ese defecto también
	-- se pagó hoy.
	local pieza = part(nombre, tamano, Vector3.new(centro.X, y + 0.05 - ALTO_LOSA / 2, centro.Z), color, padre)

	if bajo ~= nil then
		zocalo(pieza, bajo, padre)
	end
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

-- LA VIGILANCIA DE LA CIUDAD: una esquina fichada en cada cruce de la retícula.
--
-- ANTES SE SEMBRABAN POR RUTA, repartidas sobre la recta de casa a cada destino, y
-- eso dejaba el resto del mapa a oscuras. JJ lo dijo mirando el resultado: *"los
-- ladrones deberían salir siempre, por todo el mapa; no está libre ninguna ruta"*.
-- Tenía razón y era literal -- bastaba salirse del corredor para que la ciudad dejara
-- de vigilarte, y lo más rápido era precisamente ignorar el camino marcado.
--
-- En los CRUCES, y no repartidas a ojo, porque es donde el jugador toma sus decisiones:
-- seguir recto o girar. Vigilar un cruce es vigilar una elección; vigilar mitad de una
-- recta es cobrar un peaje.
--
-- Y DE REGALO, LA DIFICULTAD SALE SOLA. Con el reparto viejo cada ruta llevaba su
-- número a mano --la verde 2, la ámbar 9, la roja 18-- y había que mantenerlo cuadrado
-- con su longitud. Ahora una ruta larga cruza más cruces que una corta, así que la
-- roja se calienta más que la verde sin que nadie lo escriba en ningún sitio. Un número
-- menos que pueda contradecir al mapa.
--
-- Siguen siendo SITIOS FIJOS, que es lo que importa: con posiciones aleatorias no
-- habría nada que aprender y esquivarlas sería suerte. Fijas, el jugador reconoce el
-- cruce malo y lo rodea, que es la habilidad que el viaje tenía que pedir.
local function sembrarVigilancia(ciudad: Instance?, padre: Instance): { BasePart }
	local puestos: { BasePart } = {}
	local n = 0

	-- LOS CRUCES Y LOS MEDIOS DE CADA TRAMO. Con sólo los cruces la RUTA VERDE SE HACÍA
	-- LIMPIA, y lo cazó la sonda nueva a la primera: mide 146 studs --un paso de
	-- retícula-- y va de un cruce que cae en la zona segura a otro que es su propio
	-- destino, así que los dos estaban excluidos y no la fichaba nadie.
	--
	-- No es un caso raro que se pueda ignorar: es la primera ruta que juega alguien.
	-- Con el medio de cada tramo, la vigilancia pasa a estar cada 73 studs y ningún
	-- trayecto de la ciudad se libra, que es exactamente lo que se pedía.
	local sitios: { Vector3 } = {}
	for i = 0, Grid.COLUMNAS do
		for j = 0, Grid.FILAS do
			table.insert(sitios, Grid.cruce(i, j))
			-- El medio del tramo hacia el siguiente cruce, en los dos ejes.
			if j < Grid.FILAS then
				table.insert(sitios, Grid.cruce(i, j):Lerp(Grid.cruce(i, j + 1), 0.5))
			end
			if i < Grid.COLUMNAS then
				table.insert(sitios, Grid.cruce(i, j):Lerp(Grid.cruce(i + 1, j), 0.5))
			end
		end
	end

	do
		for _, cruce in sitios do
			-- NI EN CASA NI ENCIMA DE UN DESTINO. Dentro de la zona segura no se
			-- calienta nadie, así que una esquina fichada ahí no decide nada; y sobre un
			-- destino sería fichar al jugador justo mientras cobra, que es el único
			-- momento del viaje en que ya no puede hacer nada al respecto.
			if (cruce - Config.ALMACEN_POS).Magnitude <= Config.ZONA_SEGURA_RADIO + 30 then
				continue
			end
			local sobreDestino = false
			for _, ruta in Config.RUTAS do
				if (Vector2.new(cruce.X, cruce.Z) - Vector2.new(ruta.destino.X, ruta.destino.Z)).Magnitude < 60 then
					sobreDestino = true
				end
			end
			if sobreDestino then
				continue
			end

			-- Suelo de CALLE, no lo primero que toque el rayo: la mitad de los postes
			-- acababa en tejados, donde no se disparan nunca (ver sueloTransitable).
			local y, cx, cz = sueloTransitable(ciudad, cruce.X, cruce.Z)
			if y == nil then
				continue
			end
			n += 1

			-- UNA CÁMARA, NO UN CÍRCULO.
			--
			-- Aquí había un disco naranja de 22 studs pintado en la calzada, y era lo
			-- único que marcaba la esquina. JJ mandó una captura señalándolo: *"esto es
			-- lo que te digo que no entiendo"*. Y con el cambio de hoy no es que no se
			-- entienda: es que MIENTE. Un círculo dice "te ven desde cualquier lado", y
			-- desde que la esquina mira hacia un rumbo, eso es exactamente lo que ya no
			-- pasa. La señal contradecía a la mecánica.
			--
			-- Lo que se entiende sin leyenda es una cámara: un objeto que apunta a algún
			-- sitio. Y su cono en el suelo dice hasta dónde llega. Entre las dos cosas
			-- no hay nada que aprender -- que es la diferencia entre una señal y un
			-- símbolo.
			--
			-- La pieza con los atributos sigue siendo la de abajo y sigue a ras de
			-- suelo: es la que mide HeatService y la que comprueba la sonda del mundo,
			-- y subirla al cabezal cambiaría las distancias de todo el sistema de calor
			-- por un motivo decorativo.
			local rumbo = Config.DETECTOR_RUMBOS[(n * 3) % #Config.DETECTOR_RUMBOS + 1]
			local mirando = CFrame.new(Vector3.new(cx, (y :: number) + 0.4, cz)) * CFrame.Angles(0, math.rad(rumbo), 0)

			local foco = part(
				string.format("Detector_%d", n),
				Vector3.new(2.4, 0.8, 2.4),
				Vector3.new(cx, (y :: number) + 0.4, cz),
				Color3.fromRGB(70, 72, 80),
				padre
			)
			foco.Material = Enum.Material.SmoothPlastic
			foco.CanCollide = false
			foco.CanQuery = false
			foco.CanTouch = false

			-- El mástil y el cabezal. Cortos: nueve studs es alto de farola, se ve de
			-- lejos y no es una de las columnas al cielo que se quitaron el 19/08 por
			-- taparlo todo.
			local mastil = part(
				"CamaraMastil",
				Vector3.new(0.9, 9, 0.9),
				Vector3.new(cx, (y :: number) + 4.5, cz),
				Color3.fromRGB(70, 72, 80),
				padre
			)
			mastil.Material = Enum.Material.Metal
			mastil.CanCollide = false
			mastil.CanQuery = false
			mastil.CanTouch = false

			local cabeza = Instance.new("Part")
			cabeza.Name = "CamaraCabeza"
			cabeza.Size = Vector3.new(2.2, 2, 3.6)
			cabeza.CFrame = mirando * CFrame.new(0, 8.6, -1)
			cabeza.Anchored = true
			cabeza.CanCollide = false
			cabeza.CanQuery = false
			cabeza.CanTouch = false
			cabeza.Color = Color3.fromRGB(52, 54, 62)
			cabeza.Material = Enum.Material.Metal
			cabeza.Parent = padre

			-- LA LENTE, redonda y pequena. La primera version era una placa cuadrada de
			-- 1,2 studs en neon naranja, y en neon el naranja satura a amarillo: JJ
			-- mando la captura preguntando *"eso que es?"*, y lo que se veia era una
			-- pantalla amarilla colgada de un poste -- un cartel, no un ojo.
			--
			-- Una esfera pequena y oscura con un punto rojo dentro se lee como lente sin
			-- que nadie lo explique, y sobre todo NO COMPITE con el cono: el cono es la
			-- informacion (hasta donde te ve) y la camara solo dice de quien es.
			local lente = Instance.new("Part")
			lente.Name = "CamaraOjo"
			lente.Shape = Enum.PartType.Ball
			lente.Size = Vector3.new(1.5, 1.5, 1.5)
			lente.CFrame = mirando * CFrame.new(0, 8.6, -2.4)
			lente.Anchored = true
			lente.CanCollide = false
			lente.CanQuery = false
			lente.CanTouch = false
			lente.Color = Color3.fromRGB(24, 24, 28)
			lente.Material = Enum.Material.Glass
			lente.Reflectance = 0.3
			lente.Parent = padre

			-- El piloto: minusculo y rojo, que es como se sabe que una camara esta
			-- encendida sin que nadie te lo diga.
			local piloto = Instance.new("Part")
			piloto.Name = "CamaraPiloto"
			piloto.Size = Vector3.new(0.35, 0.35, 0.35)
			piloto.CFrame = mirando * CFrame.new(0.75, 9.5, -0.4)
			piloto.Anchored = true
			piloto.CanCollide = false
			piloto.CanQuery = false
			piloto.CanTouch = false
			piloto.Color = Color3.fromRGB(255, 70, 60)
			piloto.Material = Enum.Material.Neon
			piloto.Parent = padre

			-- Y LA VISERA sobre la lente, que es lo que remata la silueta: sin ella el
			-- cabezal es una caja, y con ella se reconoce de lejos y de espaldas.
			local visera = Instance.new("Part")
			visera.Name = "CamaraVisera"
			visera.Size = Vector3.new(2.6, 0.3, 1.6)
			visera.CFrame = mirando * CFrame.new(0, 9.5, -2.2)
			visera.Anchored = true
			visera.CanCollide = false
			visera.CanQuery = false
			visera.CanTouch = false
			visera.Color = Color3.fromRGB(40, 42, 48)
			visera.Material = Enum.Material.Metal
			visera.Parent = padre

			foco:SetAttribute("rumbo", rumbo)
			-- SIN `zonaFichada` en la base ni en el mastil: ese atributo lo lee el
			-- cliente para APAGAR lo que no te sirve, y una camara que desaparece
			-- cuando vas sin carga deja de ser parte de la ciudad. La camara siempre
			-- esta; lo que se enciende y se apaga es su CONO, que es la advertencia.
			foco:SetAttribute("detectorId", foco.Name)

			-- SU CONO, con la MISMA figura que el del ladron (ver Cone.luau). Sale de la
			-- camara, a ras de suelo, y no se pega a nada: la esquina no se mueve.
			--
			-- El rumbo sale del indice, asi que es fijo: la misma esquina mira siempre
			-- igual y la ruta se aprende, como todo lo demas de este mapa.
			local base = CFrame.new(Vector3.new(cx, (y :: number) + 0.2, cz)) * CFrame.Angles(0, math.rad(rumbo), 0)
			for _, pieza in
				Cone.piezas(
					base,
					Config.DETECTOR_VISION_ANGULO,
					Config.DETECTOR_RADIO,
					Color3.fromRGB(214, 126, 58),
					-- OPACO: ver la cabecera de Cone.
					0
				)
			do
				pieza.Name = "ConoDetector"
				pieza:SetAttribute("zonaFichada", true)
				pieza:SetAttribute("opacidad", 0)
				pieza.Parent = padre
			end

			table.insert(puestos, foco)
		end
	end

	return puestos
end

-- ASENTAR: bajar al suelo lo que haya quedado flotando.
--
-- SE LLAMA AL FINAL DE LA CONSTRUCCIÓN, y ese detalle ES la función. La primera
-- versión de esto vivía dentro de sembrarDetectores, justo después de plantar los
-- postes, y NO SERVÍA DE NADA: los mismos tres postes seguían en el aire. El
-- código era correcto --ejecutado a mano sobre el mundo terminado los bajaba a los
-- cinco-- pero en su sitio original el rayo encontraba debajo algo que más tarde
-- desaparecía. Es exactamente la lección que ya habían enseñado los contactos:
-- **cada cosa que se planta cambia el mundo que la siguiente mide**, así que lo
-- que dependa del estado final va al final, y punto.
--
-- Y no es estético. HeatService mide `(root.Position - poste.Position).Magnitude`
-- en 3D, así que la altura se come radio: un poste con 6,8 studs de vuelo pasa de
-- alcanzar 34 studs a ras de suelo a alcanzar 31,6. La ruta vigila menos de lo que
-- su selector promete, sin que nada reviente -- la firma de siempre.
--
-- El rayo excluye SÓLO la propia pieza, no nuestra carpeta entera: hay postes que
-- se apoyan legítimamente sobre la losa del polígono, y buscarles suelo ignorando
-- lo que construimos nosotros los declararía en el aire estando bien puestos. Lo
-- que sostiene al poste vale, sea de quien sea.
-- Cuánto se puede subir una pieza enterrada. Con tope, porque enterrado y "debajo
-- de un edificio" se miden igual desde aquí: sacar a la calle un poste que quedó
-- dentro de una nave sería cambiar un fallo invisible por uno que se ve.
local RESCATE_MAXIMO = 8

local function asentar(piezas: { BasePart })
	for _, pieza in piezas do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { pieza }
		local base = pieza.Position.Y - pieza.Size.Y / 2

		-- SE MIRA DESDE ARRIBA DE LA PIEZA, no desde su base, y eso es lo que hace
		-- que valga para los dos casos. Un rayo que sale de la base sólo puede
		-- encontrar lo que hay por debajo, así que ve la pieza que flota y es ciego
		-- a la que está enterrada -- que es exactamente lo que pasó: `asentar`
		-- dejaba las guaridas hundidas hasta 3,3 studs en el terreno y la sonda las
		-- cazaba una por una según se movían los destinos.
		local desde = pieza.Position.Y + pieza.Size.Y / 2 + 2
		local golpe =
			workspace:Raycast(Vector3.new(pieza.Position.X, desde, pieza.Position.Z), Vector3.new(0, -80, 0), params)
		if not golpe then
			continue
		end

		-- Positivo = flota y hay que bajarla; negativo = está enterrada y hay que
		-- subirla. Una sola cuenta para las dos cosas.
		local desajuste = base - golpe.Position.Y
		if math.abs(desajuste) <= 1 then
			continue
		end
		if desajuste < -RESCATE_MAXIMO then
			continue
		end

		local movimiento = Vector3.new(0, desajuste, 0)
		pieza.Position -= movimiento
		-- Los hijos con cuerpo se mueven con ella: son partes sueltas emparentadas,
		-- no un Model, así que mover al padre no los arrastra. La lente que se queda
		-- flotando sobre su poste es el mismo fallo con otra cara.
		for _, hijo in pieza:GetChildren() do
			if hijo:IsA("BasePart") then
				hijo.Position -= movimiento
			end
		end
	end
end

-- REPARTIR SITIOS A LO LARGO DEL CAMINO REAL.
--
-- Refugios y guaridas se colocaban con Shelter.sitiosDeRuta / Lairs.sitiosDeRuta, que
-- interpolan sobre la RECTA del almacén al destino. Con el camino en L de la retícula
-- esa recta es la diagonal: el sitio por el que nadie pasa. Y pasarles un tramo de la
-- L en vez del almacén tampoco vale, porque miden la zona segura desde el origen que
-- se les da -- con la esquina como origen, la cuenta sale negativa y no plantan nada.
-- Las dos cosas se probaron y las dos las cazó la sonda.
--
-- Aquí se recorre la polilínea de verdad: se avanza una distancia por el camino, se
-- coge ese punto y se aparta perpendicularmente. Las constantes son las mismas, así
-- que lo que cambia es DÓNDE se mide, no cuánto.
local function sitiosSobreElCamino(
	destino: Vector3,
	cuantos: number,
	margenCasa: number,
	margenDestino: number,
	desvio: number
): { Vector3 }
	local sitios: { Vector3 } = {}
	if cuantos <= 0 then
		return sitios
	end

	local puntos = Grid.porCalles(Config.POLIGONO_SALIDA, destino)
	local largos: { number } = {}
	local total = 0
	for i = 2, #puntos do
		local l = (puntos[i] - puntos[i - 1]).Magnitude
		table.insert(largos, l)
		total += l
	end

	local dMin, dMax = margenCasa, total - margenDestino
	if dMax <= dMin then
		-- Ruta tan corta que no hay tramo donde plantar sin pisar la casa o el
		-- destino. Es el caso del barrio, y ahí el almacén ya hace de refugio.
		return sitios
	end

	-- Y NUNCA ENCIMA DE UN DESTINO. Los destinos están en cruces, y por un cruce pasan
	-- los caminos de varias rutas: sin este filtro, una guarida de la ámbar se plantó
	-- justo sobre la losa del barrio -- el sitio de cobrar siendo el sitio del que
	-- salen los ladrones.
	local function pisaUnDestino(sitio: Vector3): boolean
		for _, ruta in Config.RUTAS do
			-- 80 y no 55: se mide contra el CENTRO de la pieza que se va a plantar, y un
			-- refugio son 54 studs de lado. Con 55 su centro quedaba justo fuera y su
			-- esquina, encima de la losa del destino.
			if (Vector2.new(sitio.X, sitio.Z) - Vector2.new(ruta.destino.X, ruta.destino.Z)).Magnitude < 80 then
				return true
			end
		end
		return false
	end

	-- SE TANTEAN MÁS POSICIONES DE LAS QUE HACEN FALTA, y se paran al llenar el cupo.
	--
	-- Antes se calculaba exactamente una posición por pieza, y si un filtro la
	-- descartaba, esa pieza no existía: la ruta verde se quedó sin guarida porque su
	-- única posición caía a 16 studs del cruce del barrio y la descartaba el filtro de
	-- destinos. Sin repuestos, un filtro no aparta una pieza: la borra.
	-- POR OCHO y no por cuatro. La ruta verde comparte su primera mitad con la del
	-- barrio, así que el destino del barrio le parte el tramo útil en dos trozos con
	-- un agujero de 160 studs en medio -- y con cuatro tanteos repartidos por igual,
	-- los cuatro caían dentro del agujero. No es que no hubiera sitio: es que no se
	-- miraba con bastante detalle.
	-- POR FRANJAS, Y UNA PIEZA POR FRANJA. Esto recorria el camino de principio a fin
	-- aceptando lo primero que pasara los filtros, y paraba al llenar el cupo: los
	-- repuestos servian para no quedarse corto, pero el resultado era que TODAS las
	-- piezas salian del primer trozo bueno del camino.
	--
	-- Medido el 20/08 con la ruta roja, que mide 731 studs: sus cuatro candidatos a
	-- refugio cayeron entre Z=471 y Z=526, o sea en cincuenta y cinco studs de camino.
	-- Luego `Shelter.repartir` los descarta por separacion --estan a menos de 70 unos
	-- de otros-- y sobrevive UNO. De ahi que el mapa pidiera tres refugios y plantara
	-- uno, y que la roja tuviera el 45 % de su recorrido sin sitio donde meterse.
	--
	-- No era que no hubiera sitio: es que no se buscaba repartido. Ahora el tramo util
	-- se parte en tantas franjas como piezas hagan falta y cada franja aporta la suya,
	-- con ocho tanteos dentro para que un filtro no le borre la pieza a esa franja.
	local franjas = math.max(cuantos, 1)
	for f = 0, franjas - 1 do
		local desde = dMin + (dMax - dMin) * (f / franjas)
		local hasta = dMin + (dMax - dMin) * ((f + 1) / franjas)
		local puestaEnLaFranja = false
		for k = 1, 8 do
			if puestaEnLaFranja then
				break
			end
			local d = desde + (hasta - desde) * ((k - 0.5) / 8)
			-- Buscar en qué tramo cae esa distancia.
			local recorrido = 0
			for t = 1, #largos do
				if recorrido + largos[t] >= d or t == #largos then
					local dentro = math.clamp((d - recorrido) / largos[t], 0, 1)
					local a, b = puntos[t], puntos[t + 1]
					local sobre = a:Lerp(b, dentro)
					local dir = (b - a)
					local plano = Vector3.new(dir.X, 0, dir.Z)
					if plano.Magnitude > 0.01 then
						-- Perpendicular en el plano: girar 90 grados es (z, -x).
						local lado = Vector3.new(plano.Z, 0, -plano.X).Unit
						-- El lado alterna por PIEZA colocada y no por intento: con intentos
						-- descartados de por medio, alternar por intento dejaba las dos
						-- guaridas de una ruta en el mismo lado de la calle.
						local signo = if #sitios % 2 == 0 then 1 else -1
						local sitio = sobre + lado * (desvio * signo)
						-- Y fuera de la zona segura, que se mide desde el ALMACÉN y no
						-- desde donde empiece a contar el camino: dentro de ella no se
						-- roba ni se calienta nadie, así que un refugio ahí no decide nada.
						if
							(sitio - Config.ALMACEN_POS).Magnitude > Config.ZONA_SEGURA_RADIO + 10
							and not pisaUnDestino(sitio)
						then
							table.insert(sitios, sitio)
							puestaEnLaFranja = true
						end
					end
					break
				end
				recorrido += largos[t]
			end
		end
	end

	return sitios
end

-- EL CAMINO REAL de una ruta: por dónde se va de verdad, no la recta.
--
-- Existe porque los contactos repartidos sobre la recta caían en el camino el
-- 0 % de las veces en la ruta verde (medido contra esto mismo). Una ciudad con
-- manzanas no se parece a una recta, y un contacto que no se pisa es decorado.
--
-- Si el pathfinder no encuentra camino se devuelve la recta: mejor un reparto
-- imperfecto que ninguno, y el aviso queda en la consola para que se vea.
local function caminoDeRuta(ruta: Routes.Ruta): { Vector3 }
	-- POR LAS CALLES, no por donde iría un bot.
	--
	-- Esto le pedía el camino al pathfinder, y era lo correcto contra la ciudad
	-- prestada: allí no sabíamos por dónde se podía pasar, así que había que
	-- preguntarlo. Con retícula propia lo sabemos, y preguntárselo es ahora PEOR que
	-- saberlo -- el pathfinder es un bot omnisciente y corta en diagonal por dentro de
	-- las manzanas, entre edificio y edificio, por donde ningún jugador sabe que se
	-- puede ir. La fila de luces salía por ahí y se perdía detrás de un edificio en dos
	-- de sus nueve tramos.
	--
	-- De regalo, plantar el rastro deja de costar cuatro ComputeAsync al arrancar.
	local puntos: { Vector3 } = { Config.ALMACEN_POS }
	for _, p in Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino) do
		table.insert(puntos, p)
	end
	return puntos
end

-- LOS BRAZOS DEL RAYO, colgados de la pieza que ya existe.
--
-- POR QUE UN RAYO Y NO UN CUADRADO, dicho por JJ el 20/08: *"que sean unas
-- zapatillas o un rayo y te den un empujoncito de velocidad temporal"*. Y la forma
-- no es adorno: la miga cambio de trabajo. Antes marcaba el camino --de ahi que un
-- punto valiera-- y ahora lo unico que hace es acelerarte. Un simbolo que
-- significa velocidad se lee sin tener que aprenderlo, y en un juego donde eliges
-- si te desvias a por el, entenderlo de un vistazo ES la mecanica.
--
-- HECHO DE PARTS Y NO DE UN MESH, y no por gusto: este proyecto ya pago que los
-- meshes no existen hasta publicar el place. Tres cajas neon inclinadas dan la
-- silueta y se ven siempre.
--
-- Los brazos cuelgan DE la pieza, asi que van con ella a todas partes: al cliente
-- que pinta el rastro (`Senales`) le basta con recorrer descendientes, y a las
-- sondas que buscan `^Contacto_` no les aparecen como piezas sueltas.
local function rayo(pieza: BasePart, color: Color3, escala: number)
	-- Medidas en el marco de la pieza, que ya viene girada de canto al camino y con
	-- el travesano inclinado. Cada brazo deshace esa inclinacion y pone la suya.
	local brazos = {
		{ largo = 2.0, ancho = 0.75, giro = 20, dx = 0.62, dy = 1.15 },
		{ largo = 2.0, ancho = 0.75, giro = 20, dx = -0.62, dy = -1.15 },
	}
	for _, b in brazos do
		local brazo = Instance.new("Part")
		brazo.Name = "Rayo"
		brazo.Size = Vector3.new(b.ancho * escala, b.largo * escala, 0.55)
		brazo.Color = color
		brazo.Material = Enum.Material.Neon
		brazo.Anchored = true
		brazo.CanCollide = false
		brazo.CastShadow = false
		brazo.CFrame = pieza.CFrame
			* CFrame.Angles(0, 0, math.rad(34))
			* CFrame.new(b.dx * escala, b.dy * escala, 0)
			* CFrame.Angles(0, 0, math.rad(b.giro))
		brazo.Parent = pieza
	end
end

-- LOS BRAZOS DE LA FLECHA, para el recogible de SALTO.
--
-- Dos clases de recogible necesitan dos siluetas, y la unica forma de que un
-- simbolo se lea sin leyenda es que signifique lo que hace. El rayo es velocidad;
-- una flecha hacia arriba es salto. No hay nada que aprender.
--
-- Y SE DISTINGUEN TAMBIEN POR EL COLOR, no solo por la forma: a la distancia a la
-- que hace falta decidir --la siguiente pieza, no la que pisas-- la silueta es
-- cuatro pixeles y el color es un color. El cian no aparece en ningun otro sitio
-- del juego, que es exactamente lo que se le pide a un codigo de color.
local function flecha(pieza: BasePart, color: Color3, escala: number)
	-- La pieza es el ASTA; aqui se le ponen las dos alas de la punta.
	for _, signo in { 1, -1 } do
		local ala = Instance.new("Part")
		ala.Name = "Ala"
		ala.Size = Vector3.new(0.75 * escala, 1.9 * escala, 0.55)
		ala.Color = color
		ala.Material = Enum.Material.Neon
		ala.Anchored = true
		ala.CanCollide = false
		ala.CastShadow = false
		ala.CFrame = pieza.CFrame
			* CFrame.new(0.62 * escala * signo, 0.85 * escala, 0)
			* CFrame.Angles(0, 0, math.rad(40) * signo)
		ala.Parent = pieza
	end
end

-- LOS CONTACTOS de una ruta, plantados sobre su corredor.
--
-- Se siembran AQUÍ y no en su servicio por una razón que este fichero ya pagó
-- cara: bajar algo al suelo de una ciudad ajena es donde se equivoca uno. Un rayo
-- desde arriba devuelve tejados y copas de árbol, y quince detectores acabaron en
-- las azoteas sin que nada reventara. `sueloTransitable` es la maquinaria que lo
-- resuelve y vive en este fichero, así que el sitio de plantar es éste; las
-- reglas (quién recoge, cuándo cuenta) son de ContactService.
--
-- Son FIJOS, como los detectores y las guaridas: el reparto sale del trazado y no
-- de un dado, para que el jugador que repite la ruta sepa dónde están.
-- ¿Cae este punto dentro del cono de alguna camara?
--
-- POR QUE IMPORTA, dicho por JJ: *"no los pongamos en zonas con camara de
-- vigilancia, que eso es tener mala leche"*. Y es exactamente eso -- un premio
-- puesto donde te fichan no es una decision, es una trampa: la fila te esta
-- diciendo "ven por aqui" y el sitio al que te lleva te sube el calor. El juego se
-- estaria contradiciendo a si mismo, y el jugador aprenderia a no fiarse de la
-- unica guia que tiene.
--
-- Se comprueba con las MISMAS dos condiciones que usa HeatService --cono y sin
-- pared de por medio-- porque cualquier otra cosa seria una segunda verdad sobre
-- donde te ven, y dos verdades sobre lo mismo acaban discrepando.
local function enConoDeCamara(donde: Vector3, camaras: { BasePart }): boolean
	for _, poste in camaras do
		local rumbo = poste:GetAttribute("rumbo")
		if typeof(rumbo) ~= "number" then
			continue
		end
		-- CON UN MARGEN PEQUENO, y medido: la primera version sumaba el radio de
		-- recogida entero (35 + 14 = 49) para curarse en salud, y con 45 camaras eso
		-- tapaba media ciudad -- los recogibles pasaron de 33 a TRES. Un filtro de
		-- seguridad que se come el sistema que protege no protege nada.
		--
		-- Cuatro studs bastan para que una miga en el filo no acabe recogiendose desde
		-- dentro del cono.
		local alcance = Config.DETECTOR_RADIO + 4
		if (donde - poste.Position).Magnitude > alcance then
			continue
		end
		local mirando = (CFrame.Angles(0, math.rad(rumbo), 0) * CFrame.new(0, 0, -1)).Position
		if not Vision.dentroDelCono(poste.Position, mirando, donde, Config.DETECTOR_VISION_ANGULO, alcance) then
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { poste }
		if workspace:Raycast(poste.Position, donde - poste.Position, params) == nil then
			return true
		end
	end
	return false
end

local function sembrarContactos(
	ciudad: Instance?,
	ruta: Routes.Ruta,
	camino: { Vector3 },
	anclas: { Vector3 },
	padre: Instance,
	camaras: { BasePart }
): { BasePart }
	local piezas: { BasePart } = {}
	-- Las del rastro, en orden, para dorarlas DESPUÉS de saber cuáles cabían.
	local delRastro: { BasePart } = {}

	-- AQUI SE PINTABA LA RUTA EN EL ASFALTO, una franja continua del color de la ruta
	-- de casa al destino. Nacio contra una queja repetida cuatro veces --"no se ve
	-- donde tienes que ir"-- y funcionaba: una linea continua se lee desde el otro
	-- extremo de la calle sin mirarla.
	--
	-- Se quita el 20/08 porque el propio JJ cerro el debate desde el otro lado: *"con
	-- que salga la ruta en el plano del mapa es suficiente, y asi no contaminamos el
	-- mapa real"*. Y es la decision correcta -- la guia no ha desaparecido, se ha
	-- MUDADO: el minimapa dibuja el mismo camino en L, sale del mismo `Grid.porCalles`
	-- y ahora ademas marca la zona de entrega con un halo.
	--
	-- Lo que queda en el suelo son las MIGAS, y no es lo mismo: una miga es algo que
	-- se recoge --paga contacto y da racha-- asi que no es senalizacion pintada, es
	-- juego. La diferencia entre marcar el camino y decorarlo con el.

	-- La lista se saca ENTERA antes del bucle porque cada pieza necesita saber por
	-- donde sigue el camino: el rayo se planta de canto a la ruta para que quien
	-- llega lo vea de frente y no de perfil. Sin mirar a la siguiente, todos
	-- quedarian orientados igual y en las calles este-oeste serian una raya.
	local lista = Contacts.deRuta(ruta.id, camino, anclas)
	for i, contacto in lista do
		local x, z = contacto.pos.X, contacto.pos.Z

		-- Suelo de CALLE, y NUNCA el de `sueloDeLaCiudad` como red: ése devuelve lo
		-- primero que toca el rayo, o sea el tejado. Medido con la primera versión
		-- de esto: 7 de 38 contactos acabaron a 42, 110 y hasta 178 studs de altura
		-- --los detectores, que son la referencia buena, van de 14 a 32-- y ninguno
		-- reventó. Es la misma trampa que dejó quince postes en las azoteas.
		--
		-- Así que aquí sólo hay dos salidas: calle, o nada. Un contacto que no se
		-- pisa es peor que un contacto que no existe, porque encima decora.
		local y, cx, cz = sueloTransitable(ciudad, x, z)
		if y == nil then
			continue
		end

		-- Y la calle tiene que estar CERCA. Al suelto se le da poco margen porque su
		-- trabajo es estar en el camino; al racimo un poco más, porque el suyo es
		-- estar apartado. Pasado eso, no hay sitio: mejor ninguno que uno lejos.
		local desplazado = math.sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
		-- Al racimo se le da margen porque su trabajo es estar apartado. Al rastro
		-- se le da MENOS QUE EL RADIO DE RECOGIDA, y ése es el número correcto por
		-- una razón que la sonda del mundo cazó midiendo: con margen 24 y radio 10,
		-- **19 de las 55 piezas de la roja quedaron a 21-40 studs del camino**, o
		-- sea plantadas, encendidas, contadas... y fuera del alcance de quien va por
		-- la ruta. La misma firma de siempre: nada revienta y el sistema no existe.
		--
		-- Atado al radio y no escrito a mano para que no puedan volver a separarse:
		-- el día que alguien toque uno, el otro le sigue.
		local margen = if contacto.tipo == "racimo" then 60 else Config.CONTACTO_RADIO - 2
		if desplazado > margen then
			continue
		end
		x, z = cx, cz

		-- Y NO DENTRO DEL CONO DE UNA CAMARA. Si el sitio que le tocaba esta vigilado,
		-- se prueba a CORRERLA por el camino antes de tirarla: un hueco en la fila se
		-- lee como "te has salido de la ruta", que es justo lo que no ha pasado.
		--
		-- Se prueba primero hacia delante (avanzar es lo que el jugador iba a hacer) y
		-- en saltos crecientes. Si a 30 studs por ninguno de los dos lados hay sitio
		-- limpio, entonces si se descarta: mejor un hueco que un premio con castigo.
		if enConoDeCamara(Vector3.new(x, (y :: number) + 4, z), camaras) then
			local vecino = lista[i + 1] or lista[i - 1]
			local haciaAlla = if vecino
				then Vector3.new(vecino.pos.X - x, 0, vecino.pos.Z - z)
				else Vector3.new(0, 0, 1)
			if haciaAlla.Magnitude < 0.5 then
				haciaAlla = Vector3.new(0, 0, 1)
			end
			local dir = haciaAlla.Unit
			-- Se prueba A LO LARGO del camino y tambien A LOS LADOS. Sólo a lo largo no
			-- sirve cuando la camara mira en la direccion en que se avanza: entonces
			-- correrse por el camino es quedarse dentro del mismo cono.
			local lado = Vector3.new(dir.Z, 0, -dir.X)
			local intentos = {
				dir * 15,
				dir * -15,
				lado * 10,
				lado * -10,
				dir * 28,
				dir * -28,
				lado * 16,
				lado * -16,
			}
			for _, salto in intentos do
				local nx, nz = x + salto.X, z + salto.Z
				local ny, ncx, ncz = sueloTransitable(ciudad, nx, nz)
				if ny == nil then
					continue
				end
				if math.sqrt((ncx - nx) ^ 2 + (ncz - nz) ^ 2) > Config.CONTACTO_RADIO - 2 then
					continue
				end
				if enConoDeCamara(Vector3.new(ncx, (ny :: number) + 4, ncz), camaras) then
					continue
				end
				x, z, y = ncx, ncz, ny
				break
			end
			-- Y SI NO HAY HUECO, SE PLANTA IGUAL. Descartarla era la primera version y
			-- salio mucho peor que el problema: un hueco en la fila se lee como "te has
			-- salido de la ruta", que es mentira y ademas rompe la cadena de velocidad.
			--
			-- Que quede alguna vigilada no es una trampa mientras el cono SE VEA -- y se
			-- ve, esta pintado en el suelo. Entonces deja de ser mala leche y pasa a ser
			-- lo que el juego quiere: una decision con la informacion delante.
		end

		local esRacimo = contacto.tipo == "racimo"
		local esRastro = Contacts.esDelRastro(contacto.tipo)
		local esSalto = contacto.tipo == Config.RECOGIBLE_SALTO
		-- HACIA DONDE SIGUE EL CAMINO. Se mira a la pieza siguiente; la ultima
		-- hereda la direccion de la anterior, y si no hay ninguna (rutas de una sola
		-- pieza) se deja el eje Z, que es lo que habia antes.
		local siguiente = lista[i + 1] or lista[i - 1]
		local rumbo = if siguiente then Vector3.new(siguiente.pos.X - x, 0, siguiente.pos.Z - z) else Vector3.zero
		if rumbo.Magnitude < 0.5 then
			rumbo = Vector3.new(0, 0, 1)
		end

		local centro = Vector3.new(x, (y :: number) + 4, z)
		-- EL COLOR DICE QUE HACE, y ya no de que ruta es.
		--
		-- Hasta hoy iban del color de su ruta, y tenia sentido cuando la fila
		-- SENALIZABA: el color decia cual era la tuya. Ese trabajo se lo llevo el
		-- minimapa, y desde que hay dos clases de recogible el color tiene algo mucho
		-- mas util que decir -- para que sirve el que estas mirando. Ambar es
		-- velocidad, cian es salto, y de que ruta son ya lo sabe el cliente, que solo
		-- enciende las tuyas.
		local color = if esRacimo
			then Color3.fromRGB(255, 196, 84)
			elseif esSalto then Color3.fromRGB(96, 226, 236)
			else Color3.fromRGB(255, 186, 70)
		local escala = if esRacimo then 1.25 else 1
		local pieza = part(
			string.format("Contacto_%s_%d", ruta.id, i),
			if esSalto
				then Vector3.new(0.8 * escala, 2.6 * escala, 0.55)
				else Vector3.new(2.1 * escala, 0.8 * escala, 0.55),
			centro,
			color,
			padre
		)
		pieza.Material = Enum.Material.Neon
		pieza.CanCollide = false
		if esSalto then
			-- La flecha va DERECHA, no de canto: apunta arriba, y arriba es arriba se
			-- mire desde donde se mire. Solo se gira sobre su eje para dar la cara al
			-- camino.
			pieza.CFrame = CFrame.lookAt(centro, centro + rumbo.Unit)
			flecha(pieza, color, escala)
		else
			-- De canto al camino, y el travesano del rayo inclinado dentro de ese plano.
			pieza.CFrame = CFrame.lookAt(centro, centro + rumbo.Unit) * CFrame.Angles(0, 0, math.rad(-34))
			rayo(pieza, color, escala)
		end
		-- Los datos viajan CON la pieza: ContactService no repite el reparto, lee lo
		-- que hay plantado. Si algún día el reparto cambia, no hay dos versiones.
		pieza:SetAttribute("ruta", ruta.id)
		pieza:SetAttribute("valor", contacto.valor)
		pieza:SetAttribute("tipo", contacto.tipo)

		-- LA LUZ SÓLO EN LAS QUE DECIDEN ALGO, y esto es un límite de la plataforma,
		-- no una preferencia: con el rastro, la ruta roja pasa de 16 piezas a unas
		-- 50, y las cuatro rutas juntas rondan las 130. Ciento treinta PointLight
		-- encendidas a la vez es de las formas más rápidas de tirar el frame rate de
		-- un móvil, que es donde juega la mayoría de Roblox.
		--
		-- El neón se ve sin alumbrar, así que la fila se lee igual. La luz se
		-- reserva para el racimo, cuya gracia es que lo veas desde el camino y
		-- decidas si te desvías.
		if not esRastro then
			local luz = Instance.new("PointLight")
			luz.Color = Color3.fromRGB(255, 214, 130)
			luz.Range = if esRacimo then 34 else 18
			luz.Brightness = if esRacimo then 2.2 else 1.2
			luz.Parent = pieza
		end

		if esRastro then
			table.insert(delRastro, pieza)
		end
		table.insert(piezas, pieza)
	end

	-- Y AHORA SE DORAN, sobre las que de verdad encontraron calle. Hacerlo antes,
	-- sobre el reparto teórico, haría que cada píldora descartada por la ciudad se
	-- llevara una moneda por delante -- y la ruta con peor suerte de trazado pagaría
	-- menos que las otras sin que nadie lo hubiera decidido ni lo pudiera ver.
	local cuantas = Config.CONTACTOS_POR_RUTA[ruta.id]
	if cuantas then
		for indice in Contacts.indicesDorados(#delRastro, cuantas.sueltos) do
			local pieza = delRastro[indice]
			if pieza then
				pieza:SetAttribute("valor", Config.CONTACTO_VALOR_SUELTO)
				-- Y AQUI **NO** SE TOCA EL TIPO, aunque lo hacia hasta hoy.
				--
				-- Esto ponia `tipo = "suelto"`, que tenia sentido cuando el tipo solo
				-- distinguia "pieza de la fila" de "racimo". Desde que el tipo dice QUE
				-- HACE el recogible --velocidad o salto-- pisarlo aqui le borra su clase:
				-- y como las doradas son casi todas (4 de 4, 10 de 11, 16 de 18), el
				-- resultado medido fue que **treinta y una de las treinta y tres perdian
				-- su tipo** y volvian a dar velocidad. Las flechas de salto estaban
				-- plantadas, dibujadas y contadas, y no hacian nada.
				--
				-- Es la firma de siempre: nada revienta y el sistema no existe. Lo cazo
				-- la sonda nueva -- "la verde tiene 0 de velocidad y 0 de salto".
				--
				-- Pagar contacto y ser de una clase son dos cosas distintas, asi que
				-- ahora viven en dos atributos distintos.
				pieza:SetAttribute("paga", true)
				-- SOLO EL COLOR, no el tamano: la pieza ya no es un cuadrado sino el
				-- travesano de un rayo, y cambiarle las medidas por debajo lo dejaria
				-- descoyuntado de sus dos brazos. Las doradas se distinguen por ser
				-- doradas y por llevar luz, que es de lejos lo que mas se ve.
				-- YA NO SE REPINTAN DE ORO. El color pasó a significar QUÉ HACE la
				-- pieza (ámbar velocidad, cian salto), así que teñir de oro las que
				-- además pagan borraría el único dato que el jugador tiene que leer de
				-- lejos, y a cambio le diría uno que no decide nada: cobrar un contacto
				-- es automático, pasas por encima y ya está.
				--
				-- Se distinguen por la LUZ, que es lo que se ve sin mirar.
				local luz = Instance.new("PointLight")
				luz.Color = pieza.Color
				luz.Range = 20
				luz.Brightness = 1.4
				luz.Parent = pieza
				local luz = Instance.new("PointLight")
				luz.Color = Color3.fromRGB(255, 214, 130)
				luz.Range = 18
				luz.Brightness = 1.2
				luz.Parent = pieza
			end
		end
	end

	return piezas
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
	rotulo.AlwaysOnTop = false
	rotulo.MaxDistance = 120
	rotulo.Adornee = base
	rotulo.Parent = base

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(255, 240, 200)
	texto.TextStrokeTransparency = 0.2
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = Strings.get("SIGN_WAREHOUSE")
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
	-- SITIOS PARA LA NAVE MÁS GRANDE QUE SE PUEDE COMPRAR, no para la de partida:
	-- el muelle se construye una vez y la nave se mejora después, así que con
	-- ALMACEN_TOPE las piezas de más no tendrían dónde dibujarse.
	local plazas = Warehouse.mejora(Warehouse.maximo()).tope
	for i = 0, plazas - 1 do
		local fila = math.floor(i / 8)
		local columna = i % 8
		table.insert(
			sitios,
			base.Position
				+ Vector3.new(-28 + columna * 8, suelo - base.Position.Y + 1.6, zNave + frente * (-10 + fila * 7))
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
	-- 88 DE ANCHO, Y SALE DE UNA MEDIDA. Con 72 el último expositor se salía por la
	-- pared: los siete podios van desplazados media plaza (ver abajo, es
	-- deliberado), así que el séptimo cae en x=+35 y con sus 8,4 de lado llega a
	-- +39,2 -- cuando la pared estaba en +36. La furgoneta, de seis de ancho,
	-- asomaba fuera del cobertizo. Lo dijo JJ: "la furgoneta se sale del almacén,
	-- hay que hacerlo más grande para que quepan los vehículos".
	--
	-- Con 88, la pared queda en +44 y sobran 4,8 studs por el lado apretado.
	local ancho, largo, alto = 88, 44, 17

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
		texto.Text = Strings.get("SIGN_VEHICLES")
		texto.Parent = cartel
	end

	-- OJO: ESTE BLOQUE ESTUVO DUPLICADO. La función tenía el escaparate, el plafón
	-- y las plazas del garaje DOS VECES seguidas, así que cada taller montaba dos
	-- escaparates superpuestos --24 podios donde debía haber 12-- con sus avisos de
	-- compra encima. No daba ningún error: sólo dos avisos de "Comprar" en el mismo
	-- sitio y el doble de piezas. Salió contando lo que hay en el mundo, no leyendo
	-- el código.

	-- Tres expositores con los vehículos de la escalera, del más barato al más
	-- caro, cada uno con su nombre y su precio. Es el escaparate: enseñar lo que
	-- todavía no puedes pagar es lo que le da destino al dinero.
	-- TODOS LOS QUE SE VENDEN, no una selección. Enseñaba tres --y uno de los cuatro
	-- huecos apuntaba a un vehículo que no existe-- así que faltaban cuatro de los
	-- siete: *"no sé dónde está la bicicleta, ha desaparecido"* (JJ). Un escaparate
	-- que esconde la mitad del catálogo no le da destino al dinero; sólo confunde.
	local escaparate = {}
	for i = 2, #Config.VEHICULOS do
		table.insert(escaparate, Config.VEHICULOS[i])
	end

	for i, vehiculo in escaparate do
		-- Desplazada media plaza: con siete expositores centrados, el cuarto cae
		-- justo en el centro de la losa del taller, que es por donde la sonda
		-- comprueba que la losa se pisa -- y también por donde entra el jugador.
		local x = (i - (#escaparate + 1) / 2) * 10 + 5
		local podio =
			pieza("Podio" .. i, Vector3.new(8.4, 1.2, 8.4), Vector3.new(x, 0.6, -4), Color3.fromRGB(88, 86, 92))
		-- Una silueta tosca de respaldo: si la malla no carga --sin el place
		-- publicado no carga ninguna-- esto es lo que se ve, y el escaparate sigue
		-- leyéndose como "aquí hay algo" desde la calle.
		local bulto = pieza(
			"Expuesto" .. i,
			Vector3.new(4.2, 2.4 + i * 0.35, 6.5),
			Vector3.new(x, 1.2 + (2.4 + i * 0.35) / 2, -4),
			Palette.ruta(if i <= 2 then "verde" elseif i <= 4 then "ambar" else "roja")
		)
		bulto.Material = Enum.Material.Metal

		-- Y EL VEHÍCULO DE VERDAD ENCIMA, si la sesión puede descargar su malla.
		-- Va en otro hilo porque CreateMeshPartAsync espera al servidor de assets:
		-- son siete peticiones por taller y ninguna puede estar en el camino de
		-- arranque del mundo (ver CLAUDE.md). Cuando llega, el bulto se apaga.
		task.spawn(function()
			local malla, alto = Ride.malla(vehiculo.id)
			if malla == nil or podio.Parent == nil then
				return
			end
			malla.Name = "Escaparate" .. i
			-- Mirando hacia fuera del cobertizo, como en un concesionario de verdad:
			-- de morro a la calle por la que pasas.
			malla.CFrame = CFrame.new(podio.Position + Vector3.new(0, podio.Size.Y / 2 + alto / 2, 0))
				* CFrame.Angles(0, if frente > 0 then 0 else math.pi, 0)
				* malla.CFrame
			malla.CanCollide = false
			malla.Parent = padre
			-- El bulto se queda: es el que lleva el aviso de compra y el cartel del
			-- precio, y moverlos a la malla sería tener el mismo dato en dos sitios.
			-- Invisible y sin colisión, para que no se choque con una caja que ya no
			-- se ve.
			bulto.Transparency = 1
			bulto.CanCollide = false
			-- Y FUERA DE LOS RAYOS. Invisible no basta: la sonda del mundo mide lo que
			-- se pisa con raycasts, y una caja invisible los para igual que una
			-- maciza. La primera vez que se puso esto, el veredicto fue "lo que se
			-- pisa en el Taller es Expuesto4".
			bulto.CanQuery = false
		end)

		-- SE COMPRA ESTE, no "el primero de la lista". El aviso de la losa compra lo
		-- más barato que te falte, que estaba bien cuando la escalera era una fila
		-- de mejoras; con el garaje hay que poder elegir CUÁL, porque un patinete
		-- teniendo furgoneta ya no es un capricho sino la llave de los atajos.
		local compra = prompt(bulto, Strings.get("PROMPT_BUY_VEHICLE"), Strings.get("RIDE_" .. vehiculo.id), 22)
		compra.Name = "PromptComprar"
		compra:SetAttribute("vehiculo", vehiculo.id)

		local etiqueta = Instance.new("BillboardGui")
		etiqueta.Name = "Precio"
		-- 300 y no 230: con "Van · 15000 · level 10" el texto se cortaba por la
		-- derecha. TextScaled encoge la fuente para caber en ALTO, no en ancho.
		etiqueta.Size = UDim2.fromOffset(300, 54)
		etiqueta.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		etiqueta.AlwaysOnTop = false
		etiqueta.MaxDistance = 70
		etiqueta.Adornee = bulto
		etiqueta.Parent = bulto

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextStrokeTransparency = 0.35
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		-- Nombre, precio y NIVEL. El nivel se escribe en el escaparate porque es del
		-- vehículo, no del jugador: la etiqueta es la misma para todo el mundo y no
		-- hay que redibujarla cuando alguien sube. Y enseñarlo es la mitad del
		-- motivo para seguir -- ver la furgoneta con un "nivel 10" encima es
		-- exactamente lo que hace que subir de nivel signifique algo.
		texto.Text = Strings.get("SHOWROOM_LABEL", {
			vehiculo = Strings.ref("RIDE_" .. vehiculo.id),
			precio = vehiculo.coste,
			nivel = if (vehiculo :: any).nivel and (vehiculo :: any).nivel > 1
				then Strings.get("SHOWROOM_LEVEL", { nivel = (vehiculo :: any).nivel })
				else "",
		})
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
	--
	-- ARRANCA POR ENCIMA DEL TEJADO, y no desde el suelo como estaba. Lo dijo JJ:
	-- "cuando entras al almacén hay un rectángulo azul que va hasta muy alto para
	-- ver el almacén, pero que se vea en el interior molesta y no aporta nada". Y es
	-- exacto: medía 46 studs desde el suelo con un cobertizo de 17 de alto, así que
	-- lo atravesaba entero y te la encontrabas en medio del taller.
	--
	-- Su trabajo es verse DESDE FUERA. Empezando sobre el techo lo sigue haciendo
	-- --la cima queda a la misma altura de siempre-- y por dentro desaparece.
	-- Sin baliza: el taller se reconoce por su nave y su cartel, y el 19/08 se quitó
	-- todo lo vertical del mapa.
end

-- UNA GUARIDA: de dónde salen los ladrones (ver Lairs.luau).
--
-- Tiene que verse y reconocerse DESDE LEJOS, porque su trabajo es que la rodees.
-- Una guarida que sólo se descubre cuando ya te ha soltado un ladrón encima no
-- cambia nada respecto a que aparezcan de la nada, que es justo lo que venía a
-- arreglar.
--
-- ROJA Y CERRADA, al revés que la comisaría (azul y abierta por los cuatro
-- lados). Las dos cosas dicen lo mismo sin una palabra: en una entras, de la otra
-- sales corriendo. Y el azul sigue siendo sólo de las comisarías -- si el sitio
-- donde te salvas y el sitio del que huyes compartieran color, habría que pararse
-- a distinguirlos justo cuando no se puede.
local function guarida(
	ciudad: Instance?,
	indice: number,
	ruta: string,
	centro: Vector3,
	padre: Instance,
	ocupados: { Vector3 }
): BasePart?
	-- NI UNA GUARIDA EN CASA. sueloTransitable busca en espiral, así que una
	-- propuesta cerca del polígono puede acabar desplazada DENTRO de él -- y pasó:
	-- la primera de la ruta verde terminó debajo del zócalo de nuestra propia
	-- explanada. Ver salir ladrones del sitio donde el juego promete que estás a
	-- salvo contradice la única garantía que da el almacén.
	if Perimeter.dentro(centro, 80) then
		return nil
	end

	-- UN SITIO LLANO PARA LA HUELLA ENTERA, no un punto de calle. Con una sola
	-- muestra en el centro, la Guarida_1 acabó en una ladera: volaba 20 studs por
	-- una esquina y la tierra se la comía 32 por la contraria. Medido después, hay
	-- sitios con menos de un stud de desnivel a 10-80 studs de cada una, así que no
	-- había que renunciar a nada -- sólo había que mirar.
	local sitio = sitioLlano(ciudad, centro, 34, 34, 2, ocupados, 50, 60)
	if sitio == nil then
		-- Sin suelo transitable: se omite. Una guarida en una azotea soltaría
		-- ladrones que caen del cielo, que es peor que no tenerla.
		return nil
	end
	local y, x, z = sitio.Y, sitio.X, sitio.Z
	-- Y se vuelve a mirar DESPUÉS de la búsqueda, que es la que mueve el sitio.
	if Perimeter.dentro(Vector3.new(x, y, z), 80) then
		return nil
	end

	-- Se despeja su parcela, igual que la del almacén: es un edificio, y un edificio
	-- con un árbol saliéndole por el tejado se lee como un fallo aunque no lo sea.
	despejar(ciudad, Vector3.new(x, y, z), 38, 45, true)

	local ROJO = Color3.fromRGB(150, 58, 52)
	local ROJO_OSCURO = Color3.fromRGB(92, 34, 32)
	local HIERRO = Color3.fromRGB(58, 54, 58)

	local losa = part(
		"Guarida_" .. indice,
		Vector3.new(34, ALTO_LOSA, 34),
		Vector3.new(x, y + ALTO_LOSA / 2, z),
		ROJO_OSCURO,
		padre
	)
	losa.Material = Enum.Material.Slate
	-- Y su zócalo, si el terreno cae por algún lado: la guarida se apoya en el punto
	-- alto de su huella, así que lo que falte por el bajo hay que rellenarlo.
	local bajo = perfilDelSuelo(ciudad, Vector3.new(x, y, z), 34, 34)
	if bajo ~= nil then
		zocalo(losa, bajo, padre)
	end
	-- Los dos atributos que la hacen existir para el resto del juego: el minimapa
	-- la busca por el primero y PatrolService reparte por rutas con el segundo.
	losa:SetAttribute("guarida", true)
	losa:SetAttribute("ruta", ruta)
	losa:SetAttribute("rodable", true)

	local suelo = y + ALTO_LOSA
	local nave =
		part("GuaridaNave_" .. indice, Vector3.new(26, 18, 26), Vector3.new(x, suelo + 9, z), ROJO_OSCURO, padre)
	nave.Material = Enum.Material.Brick

	-- El portón: la única cara distinta, y mira al camino. Es lo que convierte un
	-- cubo en un sitio del que sale gente.
	local porton =
		part("GuaridaPorton_" .. indice, Vector3.new(12, 11, 1.5), Vector3.new(x, suelo + 5.5, z + 13), HIERRO, padre)
	porton.Material = Enum.Material.DiamondPlate

	-- SIN FAROL. Era una columna roja de 120 studs para ver la guarida desde lejos y
	-- poder rodearla. Se va con el resto de lo vertical (petición de JJ, 19/08): la
	-- guarida ya se reconoce por su NAVE, que mide 26x18x26 y es lo bastante distinta
	-- del resto de edificios, y sale marcada en el mapa pequeño.
	local farol = nave

	-- Y su nombre arriba del todo, a la altura del tejado: un pilar rojo dice "algo
	-- pasa aquí", pero no dice qué. Sin AlwaysOnTop, igual que el resto de placas:
	-- si se leyera a través de los edificios, rodear la manzana no serviría de nada.
	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Cartel"
	cartel.Size = UDim2.fromScale(20, 5)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 22, 0)
	cartel.MaxDistance = 90
	cartel.Adornee = farol
	cartel.Parent = farol

	local rotulo = Instance.new("TextLabel")
	rotulo.Size = UDim2.fromScale(1, 1)
	rotulo.BackgroundTransparency = 1
	rotulo.TextColor3 = Color3.fromRGB(255, 130, 120)
	rotulo.TextStrokeTransparency = 0.35
	rotulo.TextScaled = true
	rotulo.Font = Enum.Font.GothamBold
	rotulo.Text = Strings.get("SIGN_DEN")
	rotulo.Parent = cartel

	return losa
end

local function refugio(
	ciudad: Instance?,
	indice: number,
	centro: Vector3,
	padre: Instance,
	ocupados: { Vector3 }
): BasePart?
	-- El lado de su losa, aquí arriba porque la búsqueda de sitio necesita saber
	-- qué huella tiene que caber antes de que la losa exista.
	local LADO = Config.REFUGIO_RADIO * 1.2

	-- LLANO PARA LA HUELLA ENTERA. El Refugio_1 estaba en una ladera con 37 studs
	-- de diferencia entre un lado y otro: la caseta salía torcida sobre el terreno
	-- y por debajo se veía el hueco. Un refugio es el sitio al que corres cuando te
	-- persiguen; si parece un decorado mal puesto, deja de leerse como un sitio.
	local sitio = sitioLlano(ciudad, centro, LADO, LADO, 2, ocupados, 80, 40)
	if sitio == nil then
		-- Sin calle donde plantarlo. Se omite en vez de ponerlo en una azotea: un
		-- refugio inalcanzable es peor que uno menos, porque el jugador lo ve en el
		-- mapa, se desvía hacia él y descubre que no se puede entrar justo cuando
		-- lo necesitaba.
		return nil
	end
	local y, x, z = sitio.Y, sitio.X, sitio.Z
	despejar(ciudad, Vector3.new(x, y, z), LADO + 4, 45, true)

	local AZUL = Color3.fromRGB(74, 118, 176)
	local AZUL_OSCURO = Color3.fromRGB(44, 70, 108)
	local PIEDRA = Color3.fromRGB(196, 198, 202)

	local losa = part(
		"Refugio_" .. indice,
		Vector3.new(LADO, ALTO_LOSA, LADO),
		Vector3.new(x, y + ALTO_LOSA / 2, z),
		AZUL,
		padre
	)
	losa.Material = Enum.Material.Pavement
	losa:SetAttribute("refugio", true)

	-- Y lo que falte hasta el suelo por el lado bajo.
	local bajo = perfilDelSuelo(ciudad, Vector3.new(x, y, z), LADO, LADO)
	if bajo ~= nil then
		zocalo(losa, bajo, padre)
	end

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

	-- SIN FARO. Era una columna azul de 145 studs. El refugio se reconoce por su techo
	-- sobre pilares --una silueta que no tiene ninguna otra cosa del mapa-- y por su
	-- luz, que se queda porque ilumina el sitio en vez de señalarlo desde el cielo.
	local faro = losa

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(120, 180, 255)
	luz.Range = 60
	luz.Brightness = 2
	luz.Parent = losa

	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Cartel"
	cartel.Size = UDim2.fromScale(22, 6)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	cartel.AlwaysOnTop = false
	cartel.MaxDistance = 90
	cartel.Adornee = faro
	cartel.Parent = faro

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(220, 235, 255)
	texto.TextStrokeTransparency = 0.2
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = Strings.get("SIGN_POLICE")
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
	-- Las PIEZAS, no las posiciones: ContactService las apaga y las vuelve a
	-- encender al recogerlas, así que necesita el objeto.
	contactos: { BasePart },
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
	-- SIN "Drop cargo here". La entrega se cobra sola al llegar
	-- (CargoService.arrancarEntregaAutomatica), así que el botón no hacía falta para
	-- nada y sí estorbaba: un prompt flotando dice "tienes que pulsar esto", y no hay
	-- nada que pulsar. JJ: "los botones de Drop cargo here lían mucho".

	-- LA OFICINA: donde se paga la mejora de la nave (ver Config.NAVE_MEJORAS).
	--
	-- Va en una pieza propia y no como un segundo aviso sobre la losa, por dos
	-- motivos: dos ProximityPrompt en la misma pieza salen amontonados y el
	-- jugador no sabe cuál va a pulsar, y sobre todo porque mejorar la nave tiene
	-- que ser UN SITIO al que ir, igual que el taller. Un sumidero sin lugar es un
	-- botón de menú.
	--
	-- El coste no se escribe aquí: depende del nivel de cada jugador y esta pieza
	-- es la misma para todos. Lo pone el cliente en el propio aviso al recibir su
	-- estado.
	do
		local mitad = almacen.Size.X / 2
		local oficina = part(
			"OficinaNave",
			Vector3.new(10, 7, 6),
			almacen.Position + Vector3.new(mitad - 8, 3.5 + ALTO_LOSA / 2, mitad - 6),
			Palette.ALMACEN,
			mundo
		)
		oficina.Material = Enum.Material.WoodPlanks
		oficina:SetAttribute("rodable", true)
		prompt(oficina, Strings.get("PROMPT_UPGRADE"), Strings.get("OFFICE_NAME"), 18).Name = "PromptMejorar"

		local cartel = Instance.new("BillboardGui")
		cartel.Name = "Rotulo"
		cartel.Size = UDim2.fromOffset(210, 48)
		cartel.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		cartel.AlwaysOnTop = false
		cartel.MaxDistance = 70
		cartel.Adornee = oficina
		cartel.Parent = oficina

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextStrokeTransparency = 0.35
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = Strings.get("SIGN_OFFICE")
		texto.Parent = cartel
	end

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

	-- UN ARCO, NO UNA LOSA AMARILLA.
	--
	-- Aquí había una plataforma de color en el suelo que JJ pisó tres veces sin que
	-- pasara nada y resumió igual de veces: "el cuadrado amarillo que no hace nada".
	-- Tenía razón por partida doble -- desde que la ruta se elige al coger la carga,
	-- la losa dejó de abrir el selector, y una losa de color no dice qué es de todos
	-- modos.
	--
	-- Un arco sí lo dice sin una palabra: **al otro lado empieza la ciudad**. Es la
	-- forma más vieja que hay de marcar un umbral y no hace falta explicarla. Y separa
	-- lo que JJ pidió separar -- de aquí para dentro es tuyo, el almacén y el taller;
	-- de aquí para fuera se juega.
	--
	-- No reabre lo vertical que se quitó: aquello eran columnas de luz que señalaban
	-- sitios a los que ir. Esto es una puerta, y una puerta se cruza.
	local ANCHO_ARCO, ALTO_ARCO, GROSOR_PILAR = 46, 20, 5
	local cotaArco = Config.ALMACEN_POS.Y
	for _, lado in { -1, 1 } do
		local pilar = part(
			"ArcoPilar" .. (if lado < 0 then "O" else "E"),
			Vector3.new(GROSOR_PILAR, ALTO_ARCO, GROSOR_PILAR),
			Vector3.new(salidaPos.X + lado * ANCHO_ARCO / 2, cotaArco + ALTO_ARCO / 2, salidaPos.Z),
			Palette.SALIDA,
			mundo
		)
		pilar.Material = Enum.Material.Concrete
	end
	local dintel = part(
		"ArcoDintel",
		Vector3.new(ANCHO_ARCO + GROSOR_PILAR, 4, GROSOR_PILAR),
		Vector3.new(salidaPos.X, cotaArco + ALTO_ARCO + 2, salidaPos.Z),
		Palette.SALIDA,
		mundo
	)
	dintel.Material = Enum.Material.Concrete
	dintel.CanCollide = false

	-- La losa se queda, pero de umbral y no de botón: marca el suelo bajo el arco.
	local salida = losa(
		ciudad,
		"Salida",
		Vector3.new(LADO_SALIDA, ALTO_LOSA, LADO_SALIDA),
		Vector3.new(salidaPos.X, Config.ALMACEN_POS.Y, salidaPos.Z),
		Palette.SALIDA,
		mundo
	)

	local balizaSalida = salida
	balizaSalida.CanCollide = true

	local cartelSalida = Instance.new("BillboardGui")
	cartelSalida.Name = "Cartel"
	cartelSalida.Size = UDim2.fromScale(30, 8)
	cartelSalida.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
	-- SÓLO AL PIE DE LA LOSA. Se leía a 700 studs y por encima de todo, así que el
	-- "EXIT · pick a route" te acompañaba durante medio viaje. Y además ya no dice la
	-- verdad: desde el 19/08 la ruta se elige al coger el paquete, no al salir.
	cartelSalida.AlwaysOnTop = false
	cartelSalida.MaxDistance = 130
	cartelSalida.Adornee = balizaSalida
	cartelSalida.Parent = balizaSalida

	local textoSalida = Instance.new("TextLabel")
	textoSalida.Size = UDim2.fromScale(1, 1)
	textoSalida.BackgroundTransparency = 1
	textoSalida.TextColor3 = Color3.fromRGB(255, 255, 255)
	textoSalida.TextStrokeTransparency = 0.2
	textoSalida.TextScaled = true
	textoSalida.Font = Enum.Font.GothamBold
	textoSalida.Text = Strings.get("SIGN_EXIT")
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
			-- OPACA, como el resto de lo pintado en el suelo. Catorce rayas Neon
			-- translúcidas dentro del recinto eran catorce fuentes más de centelleo, y
			-- justo en el sitio donde el jugador empieza y termina cada viaje.
			raya.CanCollide = false
			raya.Material = Enum.Material.SmoothPlastic
			raya.Transparency = 0
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
	prompt(taller, Strings.get("PROMPT_BUY_VEHICLE"), Strings.get("PROMPT_DEALERSHIP"), 14).Name = "PromptTaller"
	concesionario(taller, mundo, frenteCasa)
	table.insert(talleres, taller)

	-- LA VIVIENDA DE ENTREGA: el destino deja de ser una mancha en el asfalto.
	--
	-- Lo pidio JJ el 20/08: *"estaria bien que los puntos de entrega estuvieran en
	-- ventanas de edificios, como si fueran viviendas, y no puntos en medio del mapa"*.
	-- Y no es decorado -- es lo que le da SENTIDO al viaje. Llevar un paquete a una
	-- cruz pintada en el suelo no significa nada; llevarlo al portal de una casa con
	-- las luces encendidas es un reparto, que es lo que el juego dice que haces.
	--
	-- Se construye con Parts, como todo lo demas de esta ciudad, y por el motivo de
	-- siempre: los meshes no existen hasta publicar el place.
	--
	-- La FACHADA da al cruce (`hacia` viene invertido de Grid.portalDeCruce) y lleva
	-- las ventanas encendidas del color de la ruta, que es lo que se ve desde lejos y
	-- lo que dice "es aqui" sin necesidad de una baliza vertical -- las balizas se
	-- quitaron el 19/08 por tapar el camino, y esto hace su trabajo sin ocupar cielo.
	local function vivienda(
		nombre: string,
		centro: Vector3,
		haciaDentro: Vector3,
		color: Color3,
		padre: Instance
	): BasePart
		local ANCHO, FONDO, ALTO = 46, 34, 40
		local MURO, PUERTA_ANCHO, PUERTA_ALTO = 1.4, 12, 14
		-- El frente mira al cruce, o sea al reves de "hacia dentro de la manzana".
		local frente = -haciaDentro
		local suelo = Vector3.new(centro.X, centro.Y, centro.Z)
		local base = CFrame.lookAt(suelo, suelo + frente)

		local LADRILLO = Color3.fromRGB(96, 92, 88)
		local OSCURO = Color3.fromRGB(74, 71, 68)

		local function muro(
			sufijo: string,
			tamano: Vector3,
			sitio: CFrame,
			tono: Color3,
			material: Enum.Material
		): BasePart
			local m = Instance.new("Part")
			m.Name = nombre .. sufijo
			m.Size = tamano
			m.CFrame = sitio
			m.Anchored = true
			m.CanCollide = true
			m.Color = tono
			m.Material = material
			m.Parent = padre
			return m
		end

		-- LA CASA ES HUECA, y esa es la peticion: *"que para entregar haya que entrar al
		-- edificio estaria bien, no?"*. Y si -- entrar es lo que convierte la entrega en
		-- un ACTO en vez de en un radio invisible alrededor de un punto.
		--
		-- Ademas resuelve solo el *"no se cuando he llegado al punto de entrega"* de las
		-- partidas anteriores: estar DENTRO de una habitacion no se confunde con estar
		-- cerca de algo. Un radio no se ve; una puerta si.
		--
		-- Se monta con paredes sueltas y el frente partido en dos jambas y un dintel,
		-- porque un hueco en una pieza no existe en Roblox: una puerta ES el espacio que
		-- dejan tres piezas.
		local jamba = (ANCHO - PUERTA_ANCHO) / 2
		local casa = muro(
			"",
			Vector3.new(jamba, ALTO, MURO),
			base * CFrame.new(-(PUERTA_ANCHO + jamba) / 2, ALTO / 2, -FONDO / 2),
			LADRILLO,
			Enum.Material.Brick
		)
		muro(
			"JambaDer",
			Vector3.new(jamba, ALTO, MURO),
			base * CFrame.new((PUERTA_ANCHO + jamba) / 2, ALTO / 2, -FONDO / 2),
			LADRILLO,
			Enum.Material.Brick
		)
		muro(
			"Dintel",
			Vector3.new(PUERTA_ANCHO, ALTO - PUERTA_ALTO, MURO),
			base * CFrame.new(0, PUERTA_ALTO + (ALTO - PUERTA_ALTO) / 2, -FONDO / 2),
			LADRILLO,
			Enum.Material.Brick
		)
		muro(
			"Fondo",
			Vector3.new(ANCHO, ALTO, MURO),
			base * CFrame.new(0, ALTO / 2, FONDO / 2),
			OSCURO,
			Enum.Material.Brick
		)
		muro(
			"Izq",
			Vector3.new(MURO, ALTO, FONDO),
			base * CFrame.new(-ANCHO / 2, ALTO / 2, 0),
			OSCURO,
			Enum.Material.Brick
		)
		muro(
			"Der",
			Vector3.new(MURO, ALTO, FONDO),
			base * CFrame.new(ANCHO / 2, ALTO / 2, 0),
			OSCURO,
			Enum.Material.Brick
		)
		muro(
			"Tejado",
			Vector3.new(ANCHO + 3, 1.6, FONDO + 3),
			base * CFrame.new(0, ALTO, 0),
			OSCURO,
			Enum.Material.Slate
		)

		-- El suelo de dentro, una losa fina: sin el se ve la calle por debajo de las
		-- paredes en cuanto el terreno no sea perfectamente plano. `rodable` para que
		-- entrar en moto no te baje de ella (ver RoadService).
		local piso = muro(
			"Piso",
			Vector3.new(ANCHO, 1, FONDO),
			base * CFrame.new(0, 0.5, 0),
			Color3.fromRGB(58, 56, 54),
			Enum.Material.Concrete
		)
		piso:SetAttribute("rodable", true)

		-- LAS VENTANAS. Una de cada tres apagada: una fachada con TODAS encendidas se lee
		-- como un cartel luminoso, y lo que tiene que parecer es un bloque de pisos donde
		-- vive gente. El patron sale del indice y no de un dado, porque en este mapa todo
		-- es aprendible.
		--
		-- Empiezan POR ENCIMA del dintel: las de abajo caerian dentro del hueco de la
		-- puerta, que es el sitio por el que ahora se pasa.
		for fila = 0, 1 do
			for hueco = 0, 3 do
				local encendida = (fila * 4 + hueco) % 3 ~= 2
				local v = Instance.new("Part")
				v.Name = "Ventana"
				v.Size = Vector3.new(6.5, 5, 0.6)
				v.CFrame = base * CFrame.new(-ANCHO / 2 + 8 + hueco * 10, PUERTA_ALTO + 6 + fila * 10, -FONDO / 2 - 0.8)
				v.Anchored = true
				v.CanCollide = false
				v.CastShadow = false
				v.Material = if encendida then Enum.Material.Neon else Enum.Material.Glass
				v.Color = if encendida then color else Color3.fromRGB(40, 44, 52)
				v.Transparency = if encendida then 0 else 0.35
				v.Parent = casa
			end
		end

		-- EL MARCO DE LA PUERTA, del color de la ruta. Es por donde se entra, asi que
		-- tiene que ser lo mas brillante de la fachada -- si compite con las ventanas, el
		-- jugador se planta delante del edificio y no encuentra por donde pasar. Va a los
		-- lados y arriba del hueco, nunca tapandolo.
		for _, lado in { -1, 1 } do
			local marco = Instance.new("Part")
			marco.Name = "Portal"
			marco.Size = Vector3.new(1.1, PUERTA_ALTO, 1.6)
			marco.CFrame = base * CFrame.new(lado * (PUERTA_ANCHO / 2 + 0.5), PUERTA_ALTO / 2, -FONDO / 2 - 0.9)
			marco.Anchored = true
			marco.CanCollide = false
			marco.CastShadow = false
			marco.Material = Enum.Material.Neon
			marco.Color = color
			marco.Parent = casa
		end

		local dintelLuz = Instance.new("Part")
		dintelLuz.Name = "Portal"
		dintelLuz.Size = Vector3.new(PUERTA_ANCHO + 2.2, 1.1, 1.6)
		dintelLuz.CFrame = base * CFrame.new(0, PUERTA_ALTO + 0.5, -FONDO / 2 - 0.9)
		dintelLuz.Anchored = true
		dintelLuz.CanCollide = false
		dintelLuz.CastShadow = false
		dintelLuz.Material = Enum.Material.Neon
		dintelLuz.Color = color
		dintelLuz.Parent = casa

		local luz = Instance.new("PointLight")
		luz.Color = color
		luz.Range = 30
		luz.Brightness = 2.2
		luz.Parent = dintelLuz

		-- Y EL MOSTRADOR, al fondo de la habitacion: es LO QUE DECIDE si has entregado
		-- (se registra como destino en vez de la losa de la acera). Ponerlo aqui y no en
		-- la calle es toda la mecanica -- con el punto de cobro fuera, "entrar al
		-- edificio" seria decorado.
		local mostrador = Instance.new("Part")
		mostrador.Name = "Mostrador"
		mostrador.Size = Vector3.new(ANCHO - 14, 5, 5)
		mostrador.CFrame = base * CFrame.new(0, 3.5, FONDO / 2 - 5)
		mostrador.Anchored = true
		mostrador.CanCollide = true
		mostrador.Color = Color3.fromRGB(112, 84, 58)
		mostrador.Material = Enum.Material.WoodPlanks
		mostrador.Parent = casa

		local farol = Instance.new("PointLight")
		farol.Color = color
		farol.Range = 34
		farol.Brightness = 1.6
		farol.Parent = mostrador

		-- Y EL NUMERO DE LA CASA. Un bloque de pisos sin numero sigue siendo un bloque
		-- anonimo; con el es UNA direccion, que es lo que convierte "ve al cruce" en "ve
		-- a esta casa".
		local placa = Instance.new("BillboardGui")
		placa.Name = "Numero"
		placa.Size = UDim2.fromScale(9, 3)
		placa.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		placa.AlwaysOnTop = false
		placa.MaxDistance = 260
		placa.Adornee = dintelLuz
		placa.Parent = dintelLuz

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 246, 226)
		texto.TextStrokeTransparency = 0.25
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = Strings.get("DELIVERY_DOOR")
		texto.Parent = placa

		return casa
	end

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

		-- LA VIVIENDA A LA QUE SE ENTREGA, en la esquina de manzana pegada al cruce.
		--
		-- Lo pidio JJ: *"que los puntos de entrega estuvieran en ventanas de edificios,
		-- como si fueran viviendas, y no puntos en medio del mapa"*. La losa se queda,
		-- pero cambia de oficio: era el sitio y ahora es la acera del portal.
		--
		-- VA AQUI, ANTES DEL TALLER DE ZONA, y eso no es orden de lectura sino la regla
		-- de esta casa -- *cada cosa que se planta cambia el mundo que la siguiente
		-- mide*. Puesta al final, el taller ya habia elegido su parcela y las casas de
		-- la verde y la ambar salieron plantadas DENTRO de su tejado; medido el 20/08
		-- con un rayo desde arriba: "debajo de Vivienda_verde: TallerTecho". Delante,
		-- el buscador de parcela del taller la ve y la esquiva solo, porque ya
		-- descarta cualquier sitio con algo dentro.
		local portalDeEntrega: BasePart? = nil
		local centroVivienda: Vector3? = nil
		-- DONDE SE COBRA DE VERDAD. Si por lo que sea la casa no se pudiera construir,
		-- se queda la losa: perder la entrega entera por un fallo de decorado seria
		-- convertir un problema estetico en uno que no deja jugar.
		local puntoDeCobro: BasePart? = nil
		do
			-- Las medidas van juntas con la funcion que las usa: 46x34 es la vivienda.
			local centroCasa, haciaDentro = Grid.portalDeCruce(ruta.destino, 34, 46)
			centroVivienda = centroCasa
			-- Y SU HUELLA SE DESPEJA. `despejar(ruta.destino, 50, 45)` limpia alrededor
			-- del cruce, pero la casa cae a 46 studs de el -- justo en el filo-- y la de
			-- la roja salio metida en `Manzana_3_0`. Un bloque de pisos dentro de otro
			-- no es un fallo que reviente: es una fachada que no se puede leer.
			-- LADO 84 Y NO 52. `despejar` recibe el LADO de una caja, no un radio, asi
			-- que 52 barria solo +-26 studs -- menos que la propia casa, que mide 46x34
			-- y con tejado 49x37. Medido: `Edificio_3_0_4` (40x77x40) seguia metido
			-- dentro de la vivienda roja. Y el alto sube a 90 porque los edificios de la
			-- reticula llegan a 77: una caja de 60 no toca la parte de arriba y deja el
			-- edificio en pie por no llegarle.
			despejar(ciudad, centroCasa, 84, 90)
			local yCasa = sueloDeLaCiudad(ciudad, centroCasa.X, centroCasa.Z) or Grid.Y
			local casa = vivienda(
				"Vivienda_" .. ruta.id,
				Vector3.new(centroCasa.X, yCasa, centroCasa.Z),
				haciaDentro,
				Palette.ruta(ruta.id),
				mundo
			)
			casa:SetAttribute("ruta", ruta.id)
			-- EL CARTEL DE LA RUTA SE MUDA AL PORTAL. Flotaba sobre la losa, que ahora
			-- es acera: un rotulo en mitad del asfalto vuelve a ser "un punto en medio
			-- del mapa", que es justo lo que se viene a quitar.
			portalDeEntrega = casa:FindFirstChild("Portal") :: BasePart?
			-- Y EL MOSTRADOR ES EL DESTINO, que es lo que obliga a entrar. Lleva la
			-- ruta encima porque `destinoParaCobrar` la lee de la pieza.
			local mostrador = casa:FindFirstChild("Mostrador") :: BasePart?
			if mostrador then
				mostrador:SetAttribute("ruta", ruta.id)
				puntoDeCobro = mostrador
			end
		end

		-- Y SU ACCESO RODADO hasta la calle más cercana. Sin esto, la mercancía
		-- grande era una contradicción: exige vehículo, y el vehículo no podía
		-- llegar hasta la losa.
		local calle = calleMasCercana(ciudad, destino.Position, 220)
		-- Se guardan para el taller: su parcela no puede caer sobre esta carretera.
		local calleDestino = calle
		local bordeDestino = if calle ~= nil then bordeDeLosa(destino, calle) else destino.Position
		-- Sin carretera de acceso: el destino ES un cruce de la retícula, así que ya
		-- está sobre asfalto. Antes esta rama construía una vía hasta la calle más
		-- cercana, y con el mapa propio sobra.
		if calle == nil then
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
		-- SALVO SI EL DESTINO ESTÁ EN CASA. Al encoger el mundo, el barrio quedó a
		-- 119 studs de la salida, y su taller de zona --que se busca en un anillo de
		-- 58 a 105 studs alrededor del destino-- se plantó ENCIMA de la losa de
		-- salida del recinto. La sonda lo cazó: "lo que se pisa en Salida es
		-- Taller_barrio".
		--
		-- Y sobra por diseño, no sólo por sitio: el taller de zona existe para que
		-- cambiar de vehículo no cueste un viaje de vuelta a casa. A dos pasos de
		-- casa eso no es un viaje, así que sería un segundo concesionario a la vista
		-- del primero.
		local lejosDeCasa = (ruta.destino - Config.TALLER_POS).Magnitude > 200
		if lejosDeCasa then
			-- CON CALLE, no sólo despejado. Es el segundo requisito y llegó midiendo:
			-- el taller de la ámbar cayó en un descampado a sesenta studs por debajo
			-- de la ciudad, sin una calzada a doscientos studs a la redonda. Estaba
			-- limpio, sí -- limpio como un solar al que no llega ningún coche, y un
			-- concesionario al que no se puede llegar en coche no es un sitio, es un
			-- adorno.
			-- Y LLANO, que es el tercer requisito y llegó igual que los otros dos:
			-- midiendo. El taller de la ámbar se quedó a caballo de un talud --la
			-- tierra le comía 6,7 studs por un lado y dos esquinas suyas colgaban
			-- sobre el vacío-- porque el sitio se elegía con un rayo en el centro y
			-- la losa mide 96 por 60. Un concesionario medio enterrado no rompe
			-- nada; simplemente parece que el juego está mal montado, que es la
			-- clase de defecto que decide si alguien se queda.
			-- Dos vueltas: la primera exige el suelo llano, la segunda se conforma con
			-- lo de siempre. Un taller algo torcido --que además ahora se apoya en su
			-- punto alto y lleva zócalo-- sigue siendo mejor que una zona sin taller.
			-- SE MIRAN TODOS Y GANA EL MEJOR. Coger el primero que cumpliera daba un
			-- taller a caballo de un talud teniendo uno llano dos posiciones más
			-- allá: los requisitos duros (parcela despejada, calle a la que salir, y
			-- que su carretera no cruce el destino) no ordenan entre sí, así que
			-- entre los que pasan hay que quedarse con el que mejor se apoya.
			-- Y SI CON TODAS LAS REGLAS NO HAY SITIO, SE AFLOJAN. La primera vez que se
			-- exigió "ni encima de la carretera del destino", la ruta verde se quedó
			-- SIN TALLER: nada falló, simplemente esa zona no tenía dónde cambiar de
			-- vehículo y nadie podía saber por qué. Un concesionario algo cerca de la
			-- vía es un defecto de reparto; una zona sin concesionario es un agujero.
			local sitio = nil
			local mejorNota = math.huge
			local exigente = true
			for _, radio in { 58, 80, 105, 58, 80, 105 } do
				for vuelta = 0, 11 do
					local angulo = vuelta * math.pi / 6
					local candidato = ruta.destino + Vector3.new(math.cos(angulo) * radio, 0, math.sin(angulo) * radio)
					local bajo, alto, fuera = perfilDelSuelo(ciudad, candidato, 96, 60)
					if bajo == nil then
						continue
					end
					local centro = Vector3.new(candidato.X, alto, candidato.Z)
					if despejarCuenta(ciudad, centro, 110) ~= 0 then
						continue
					end
					-- NI ENCIMA DE LA VIVIENDA DE ENTREGA. `despejarCuenta` sólo mira
					-- dentro de `ciudad`, y la vivienda se planta en `mundo`, así que
					-- para este buscador era invisible: medido el 20/08, los talleres de
					-- la verde y la ámbar salieron con seis piezas suyas --tejado,
					-- escaparates y rótulo-- metidas DENTRO del bloque de pisos.
					--
					-- Setenta y ocho studs es la suma de los dos medios cuerpos (el
					-- taller mide 96 de ancho, la casa 46) más un pasillo: lo justo para
					-- que se toquen sin morderse.
					if centroVivienda ~= nil and (centro - centroVivienda).Magnitude < 78 then
						continue
					end
					local calle = calleMasCercana(ciudad, centro, 200)
					-- Y SU CARRETERA NO PUEDE PASAR POR ENCIMA DEL DESTINO. Salió al
					-- mover el taller: la vía del concesionario ámbar cruzaba la losa de
					-- entrega, así que lo que pisabas en el sitio donde se cobra era
					-- asfalto del taller. No rompe la entrega, pero tapa la única losa
					-- que el jugador tiene que reconocer de un vistazo.
					if calle == nil or aLaRecta(ruta.destino, centro, calle) <= 34 then
						continue
					end
					-- NI ENCIMA DE LA CARRETERA DEL DESTINO. El taller de la verde cayó
					-- justo sobre ella y su escaparate quedó plantado en mitad del
					-- asfalto: lo que se pisaba en la vía era un podio y un coche
					-- expuesto. Se mide contra el trazado real --del borde de la losa a
					-- su calle-- y no contra el destino a secas, que es un punto y no
					-- dice por dónde va el camino.
					if exigente and calleDestino ~= nil and aLaRecta(centro, bordeDestino, calleDestino) < 60 then
						continue
					end
					local nota = (alto - bajo) + fuera * 3 + (radio - 58) / 15
					if nota < mejorNota then
						sitio, mejorNota = centro, nota
					end
				end
				-- Con un sitio bueno cerca no hace falta abrir el radio: alejar el
				-- concesionario del destino es empeorarlo por otro lado.
				if mejorNota <= 1 then
					break
				end
				-- Agotados los dos radios con las reglas duras, se repiten sin la de la
				-- carretera. El orden importa: primero se busca bien, y sólo si no hay
				-- nada se acepta lo que haya.
				if radio == 105 then
					exigente = false
				end
			end
			if sitio == nil then
				warn("[Contrabando] la zona " .. ruta.id .. " no tiene sitio despejado con calle: se queda sin taller")
			end
			-- SIN TALLERES DE ZONA con el mapa desnudo. Es una nave de 96x60 con siete
			-- podios, siete escaparates y su rotulo: treinta y siete piezas por ruta
			-- plantadas buscando hueco, que compiten a la vista con lo unico que hay
			-- que mirar. El taller de casa se queda, asi que se sigue pudiendo comprar.
			if Config.MAPA_DESNUDO then
				sitio = nil
			end
			if sitio ~= nil then
				despejar(ciudad, sitio, 110, 45, true)
				local tallerZona =
					losa(ciudad, "Taller_" .. ruta.id, Vector3.new(96, ALTO_LOSA, 60), sitio, Palette.TALLER, mundo)
				prompt(tallerZona, Strings.get("PROMPT_BUY_VEHICLE"), Strings.get("PROMPT_DEALERSHIP"), 26).Name =
					"PromptTaller"
				-- Y los de las zonas miran a su destino, que es donde está la acción.
				concesionario(tallerZona, mundo, if ruta.destino.Z < sitio.Z then -1 else 1)
				-- Sin carretera propia: el taller se planta junto a una calle de la
				-- retícula. Aquí quedaba un `if` con el cuerpo VACÍO --resto de cuando se
				-- le construía una vía de acceso-- y con él la única lectura de la
				-- variable que lo alimentaba. Es la misma clase de resto que hoy mató el
				-- sistema de señales del cliente durante días: al quitar los faroles se
				-- borró su tabla y se dejó el bucle que escribía en ella. Los restos de
				-- un rediseño no son inofensivos por estar callados.
				table.insert(talleres, tallerZona)
			end
		end
		-- SIN BALIZA. Aquí había una columna de 300 studs, luego 210, luego un mojón de
		-- 16. JJ dijo tres veces que le sobraba --"me sobran las luces esas hasta el
		-- cielo", "las torres de colores no aportan nada", "ningún indicador vertical"--
		-- y la tercera vez traía además el argumento que lo cierra: *los puntos
		-- importantes ya se ven en el mapa pequeño de abajo*.
		--
		-- Lo que marca la ruta es la fila de migas de pan por la calle, y lo que dice
		-- qué es esto al llegar es el cartel de aquí abajo. Una torre no añadía
		-- información: tapaba el centro de la pantalla durante todo el viaje.
		-- LA DIANA DE LLEGADA. "No sé cuándo he llegado al punto de delivery" (JJ), y
		-- es cierto: la losa del destino está EMPOTRADA en el asfalto para no hacer
		-- escalón, así que desde lejos no se distingue del suelo. El sitio donde acaba
		-- el viaje era lo menos visible del viaje.
		--
		-- Un círculo pintado, del color de la ruta y más ancho que la losa: se ve a
		-- media calle de distancia y dice "es aquí" sin una palabra ni nada vertical.
		-- Y es donde muere la línea que te ha traído, así que el camino tiene final.
		-- SOBRE EL TOPE REAL DE LA LOSA, no a un palmo de su centro.
		--
		-- Esto sumaba 0,45 a la posicion del destino dando por hecho que la losa
		-- quedaba empotrada en el asfalto. No queda: su huella de 44 studs es mas ancha
		-- que la calle de 26, asi que muerde la acera de las cuatro esquinas --que va
		-- 0,8 mas alta-- y `losa()` se apoya, con razon, en el punto MAS ALTO de lo que
		-- cubre. Medido en el mundo construido el 20/08: la losa acaba con el tope en
		-- 20,05 y la diana quedaba en 19,60. Enterrada DENTRO de la losa, en las cuatro
		-- rutas, sin asomar por ningun lado. Y del mismo color que ella, de propina.
		--
		-- O sea que la unica senal de "has llegado" era invisible por partida doble, y
		-- "no se cuando he llegado al punto de delivery" no era una impresion: era una
		-- descripcion exacta de lo que habia en pantalla.
		--
		-- Se calcula la cota en vez de suponerla, y el disco pasa a tener GROSOR: apoya
		-- en el asfalto y asoma por encima de la losa, asi que se ve desde lejos por el
		-- canto y desde cerca por arriba, y no deja aire debajo del borde.
		local topeLosa = destino.Position.Y + destino.Size.Y / 2
		local baseDiana = Grid.Y + 0.05
		local grosorDiana = math.max((topeLosa + 0.3) - baseDiana, 0.4)
		local diana = part(
			"Diana_" .. ruta.id,
			Vector3.new(grosorDiana, 58, 58),
			Vector3.new(destino.Position.X, baseDiana + grosorDiana / 2, destino.Position.Z),
			-- Aclarada, para que se despegue de la losa a la que rodea. Del color de la
			-- ruta seguia siendo, pero identico al de la losa no distinguia nada.
			Palette.ruta(ruta.id):Lerp(Color3.new(1, 1, 1), 0.45),
			mundo
		)
		diana.Shape = Enum.PartType.Cylinder
		diana.CFrame = CFrame.new(diana.Position) * CFrame.Angles(0, 0, math.rad(90))
		diana.Material = Enum.Material.SmoothPlastic
		diana.CanCollide = false
		diana.CanQuery = false
		diana.CanTouch = false
		diana:SetAttribute("ruta", ruta.id)
		diana:SetAttribute("lineaDeRuta", true)

		local baliza = portalDeEntrega or destino

		local cartel = Instance.new("BillboardGui")
		cartel.Name = "Cartel"
		cartel.Size = UDim2.fromScale(26, 9)
		cartel.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
		-- SÓLO DE CERCA. Se leía a 2.500 studs y a través de los edificios, así que
		-- desde cualquier punto del mapa había cuatro rótulos flotando a la vez. JJ:
		-- "salen muchos títulos que ahora sobran". Lo que dice el cartel --qué es este
		-- sitio-- sólo hace falta saberlo al llegar; por dónde ir lo dicen las migas.
		cartel.AlwaysOnTop = false
		cartel.MaxDistance = 90
		cartel.Adornee = baliza
		cartel.Parent = baliza

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 255, 255)
		texto.TextStrokeTransparency = 0.2
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = Strings.get("ROUTE_SIGN", { ruta = Strings.ref("ROUTE_" .. ruta.id), paga = Routes.paga(ruta.id) })
		texto.Parent = cartel

		table.insert(destinos, puntoDeCobro or destino)
	end

	-- LA VIGILANCIA, UNA VEZ Y PARA TODA LA CIUDAD. Iba dentro del bucle de rutas
	-- --cada una sembraba las suyas sobre su recta-- y eso dejaba el resto del mapa a
	-- oscuras: bastaba salirse del corredor para que nadie te fichara.
	for _, poste in sembrarVigilancia(ciudad, mundo) do
		table.insert(detectores, poste)
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
	-- Y el cupo de cada uno, en paralelo: la roja pide dos y las demas uno, y sin esto
	-- el reparto le daba uno a todas porque el tope era global.
	local cupos: { number } = {}
	for _, ruta in Routes.todas() do
		-- Las rutas sin peligro NO PIDEN SITIO. Medido al entrar el barrio: sus
		-- candidatos competían con los de la verde --Shelter.repartir descarta los
		-- que caen a menos de 320 studs entre sí-- y la verde se quedaba sin
		-- refugio. Un solar pedido por quien no lo necesita se lo quita a quien sí.
		local cuantos = ruta.refugios or Config.REFUGIOS_POR_RUTA
		if cuantos > 0 then
			table.insert(cupos, cuantos)
			table.insert(
				grupos,
				sitiosSobreElCamino(
					ruta.destino,
					cuantos + 2,
					Config.REFUGIO_MARGEN_CASA,
					Config.REFUGIO_MARGEN_DESTINO,
					Config.REFUGIO_DESVIO
				)
			)
		end
	end
	-- LAS GUARIDAS, dos por ruta. Van antes que los refugios en el código y
	-- después en importancia: son el peligro que se puede ver venir, y sin ellas
	-- los refugios no tienen de qué salvarte.
	local guaridas: { Vector3 } = {}
	-- Y agrupadas por ruta, porque los contactos las usan de ancla: el racimo va
	-- junto a un peligro DE SU RUTA, no junto a cualquiera del mapa.
	local guaridasDeRuta: { [string]: { Vector3 } } = {}
	for _, ruta in Routes.todas() do
		guaridasDeRuta[ruta.id] = {}
		-- Cuántas, por ruta: el barrio pide cero. Es el primer viaje de la partida y
		-- perder ahí la primera carga de tu vida es la forma más rápida de que
		-- alguien cierre el juego.
		local sitiosGuarida =
			sitiosSobreElCamino(ruta.destino, ruta.guaridas or Config.GUARIDAS_POR_RUTA, 60, 50, Config.GUARIDA_DESVIO)
		for _, sitio in sitiosGuarida do
			local pieza = guarida(ciudad, #guaridas + 1, ruta.id, sitio, mundo, guaridas)
			if pieza then
				table.insert(guaridas, pieza.Position)
				table.insert(guaridasDeRuta[ruta.id], pieza.Position)
			end
		end
	end

	-- Los refugios esquivan tanto a los otros refugios como a las guaridas: una
	-- comisaría plantada encima de la guarida que venía a rodear no es un descuido
	-- gracioso, es el sitio al que corres siendo el sitio del que huyes.
	local refugios: { Vector3 } = {}
	local tomados: { Vector3 } = table.clone(guaridas)
	-- Y SI SE PIERDE UNO, QUE SE OIGA. `refugio()` devuelve nil cuando no encuentra
	-- sitio llano libre, y hasta hoy eso pasaba callado: el mapa pedia dos refugios,
	-- plantaba uno --el segundo caia encima del primero, porque la ambar y la roja
	-- comparten su primer tramo-- y nadie se enteraba. La sonda cuenta que haya al
	-- menos uno, no que esten todos los que se pidieron.
	-- Y SIN REFUGIOS con el mapa desnudo. El calor se sigue enfriando solo, nada mas
	-- que sin un sitio al que correr -- que es una perdida real y por eso esto es un
	-- interruptor y no un borrado.
	local reparto = if Config.MAPA_DESNUDO then {} else Shelter.repartir(grupos, nil, cupos)
	local pedidos = #reparto
	for _, sitio in reparto do
		local pieza = refugio(ciudad, #refugios + 1, sitio, mundo, tomados)
		if pieza then
			table.insert(refugios, pieza.Position)
			table.insert(tomados, pieza.Position)
		end
	end
	if #refugios < pedidos then
		warn(
			string.format(
				"[Contrabando] se pidieron %d refugios y solo caben %d: alguna ruta se queda sin sitio donde bajar el calor",
				pedidos,
				#refugios
			)
		)
	end

	-- LOS CONTACTOS, EL ÚLTIMO DE TODO, y el orden es la regla entera.
	--
	-- Se anclan a las guaridas, sí, pero el motivo de que vayan al final es otro y
	-- lo destapó la sonda del mundo: se reparten sobre el camino que calcula el
	-- pathfinder, y **cada cosa que se planta cambia ese camino**. Sembrándolos
	-- antes que los refugios, el rastro de la ruta roja marcaba un recorrido que
	-- luego una comisaría de 54×54 con pilares cortaba: 19 de sus 55 piezas
	-- quedaban a 21-40 studs del camino de verdad, encendidas y fuera de alcance.
	--
	-- Una fila de luces que señala por dónde NO se puede ir es peor que no tener
	-- fila, porque el jugador se fía. Así que el rastro se dibuja cuando la ciudad
	-- ya no se mueve: lo que haya que plantar, se planta antes que esto.
	local contactos: { BasePart } = {}
	for _, ruta in Routes.todas() do
		local camino = caminoDeRuta(ruta)
		for _, pieza in sembrarContactos(ciudad, ruta, camino, guaridasDeRuta[ruta.id] or {}, mundo, detectores) do
			table.insert(contactos, pieza)
		end
	end

	-- Y LO ÚLTIMO DE LO ÚLTIMO: bajar al suelo lo que haya quedado flotando.
	--
	-- Va aquí, con la ciudad ya quieta, porque asentar contra un mundo que todavía
	-- se está construyendo es medir contra algo que va a cambiar (ver `asentar`).
	-- Los detectores son los que lo pedían --tres flotaban entre 5 y 7 studs, y la
	-- altura les come radio de detección-- pero se les pasa también a las guaridas
	-- por lo mismo: un farol suspendido no señala de dónde sale el ladrón.
	local postes: { BasePart } = {}
	for _, poste in detectores do
		table.insert(postes, poste)
	end
	for _, pieza in mundo:GetChildren() do
		if pieza:IsA("BasePart") and pieza.Name:match("^Guarida") then
			table.insert(postes, pieza)
		end
	end
	asentar(postes)

	return {
		almacen = almacen,
		salida = salida,
		talleres = talleres,
		aparicion = spawn,
		destinos = destinos,
		detectores = detectores,
		refugios = refugios,
		guaridas = guaridas,
		contactos = contactos,
	}
end

return CityBuilder
