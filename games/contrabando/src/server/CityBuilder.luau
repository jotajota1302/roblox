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
-- Se reconoce el árbol por su modelo (los del Creator Store vienen en un Model
-- llamado Tree) y se sigue bajando. Es específico de esta ciudad y así está dicho;
-- la alternativa --adivinar por tamaño-- confundiría una copa con un balcón.
local function esArbol(pieza: BasePart): boolean
	local padre = pieza.Parent
	return padre ~= nil and padre.Name == "Tree"
end

local function sueloDeLaCiudad(ciudad: Instance?, x: number, z: number): number?
	if not ciudad then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }

	local desde = 500
	-- OCHO intentos, no cuatro. Con cuatro se agotaban en la arboleda densa --una
	-- copa y un tronco por árbol, y hay sitios con dos árboles en la vertical-- y
	-- entonces la función decía "aquí no hay suelo" en mitad de un parque llano.
	-- Costó una guarida entera: la segunda de la ruta verde no se plantaba y no
	-- había forma de saber por qué. Ocho sigue estando muy lejos de recorrer un
	-- edificio planta por planta, que es lo que no queremos hacer -- un edificio SÍ
	-- tiene que tapar el suelo.
	for _ = 1, 8 do
		local r = workspace:Raycast(Vector3.new(x, desde, z), Vector3.new(0, -(desde + 300), 0), params)
		if r == nil then
			return nil
		end
		if not esArbol(r.Instance) then
			return r.Position.Y
		end
		desde = r.Position.Y - 0.5
	end
	return nil
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
		Vector3.new(losa.Size.X - 1.5, caida + ALTO_LOSA + MARGEN, losa.Size.Z - 1.5),
		Vector3.new(losa.Position.X, suelo - (caida + MARGEN) / 2, losa.Position.Z),
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
		if esDespejable(pieza) then
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

	-- Y AHORA SE ALISA EL PERFIL, que es lo que faltaba: *"el vehículo no sale de la
	-- zona inicial y se queda enganchado en el mapa"* (JJ). Medida la rampa de
	-- salida de casa, sus juntas iban 17,8 → 20,5 → 23,0 → 18,6 → 22,2 → 18,8: un
	-- zigzag de cinco studs sobre un desnivel real de dos. Cada tramo tomaba la cota
	-- del suelo bajo su junta, y ahí abajo hay bordillos, el zócalo del polígono y
	-- el borde de la ciudad. Como los tramos se solapan seis studs para no dejar
	-- juntas abiertas, dos seguidos con inclinaciones opuestas (+16° y −15°) se
	-- cruzan y el canto del de atrás asoma por encima del de delante: un escalón de
	-- cuatro studs, o sea un muro contra el que se choca.
	--
	-- LA CUENTA ES UNA ENVOLVENTE DE CONOS, y se llegó a ella después de probar el
	-- promedio de toda la vida --que sí quitaba el zigzag, pero CORTANDO las lomas:
	-- el acceso verde acabó enterrado en seis de sus cincuenta y seis puntos, que es
	-- el mismo defecto con otro nombre--. Aquí cada junta se levanta hasta el mayor
	-- de los conos que salen de todas las demás con la pendiente máxima:
	--
	--     cota[i] = max sobre j de ( suelo[j] − |i−j| · pendiente )
	--
	-- Con eso salen a la vez las dos cosas que hacen falta y que peleaban entre sí:
	-- la vía NUNCA queda por debajo del terreno (su propio cono la sostiene) y NUNCA
	-- hay un escalón (ningún par de juntas puede separarse más de la pendiente). Las
	-- lomas se suben rodando y las vaguadas se cruzan volando, que es lo que hace
	-- una carretera de verdad.
	local pasoLargo = largo / tramos
	-- 10 grados, bajado de 12 el 19/08. Es la pendiente máxima que se le permite a
	-- una vía, y de ella sale lo que puede subir de un tramo al siguiente.
	--
	-- El motivo del ajuste es que la pendiente **también decide el canto**: dos
	-- tramos seguidos se solapan un poco para no dejar juntas abiertas, y en la
	-- zona solapada el de atrás asoma sobre el de delante en proporción a lo que
	-- se diferencien sus inclinaciones. Con 0,21, el acceso a la verde --que sube
	-- una cuesta de verdad-- dejaba justo en el límite un canto de 2,5 studs, que
	-- es donde la sonda dice "ahí se traba el vehículo".
	--
	-- Bajarla cuesta poco: una rampa algo más larga y tendida. Y lo que compra es
	-- que las cuestas reales de esta ciudad dejen de producir cantos, en vez de
	-- ir buscando destinos llanos para esquivar el problema.
	local SALTO_MAXIMO = pasoLargo * 0.17

	-- LO QUE NO SE PUEDE ALCANZAR DESDE NINGÚN EXTREMO NO ES TERRENO: ES UN
	-- ARTEFACTO, y se recorta ANTES de que los conos lo repartan.
	--
	-- Esto es lo que cerró la joroba del acceso a la verde, y costó encontrarlo
	-- porque el sospechoso obvio era otro. Volcadas las cotas fase por fase, el
	-- perfil bruto de esa vía salía así:
	--
	--     21,0  20,6 … 20,6  20,6  **27,5**  19,4
	--
	-- Trece juntas a ras de una explanada llana, la penúltima SIETE STUDS más
	-- arriba, y la calle final a 19,4. Ese 27,5 no es una cuesta: es el rayo
	-- CENTRAL de esa junta cayendo sobre una calle elevada de la ciudad que pasa
	-- justo por encima antes de llegar. Y por eso apretar el tope de los rayos
	-- laterales no cambiaba nada -- el central manda sin límite, que es lo correcto
	-- en general porque es el que va por donde de verdad pasa la vía.
	--
	-- Lo que hacía daño no era el pico en sí sino lo que venía después: la
	-- envolvente de conos hace su trabajo y lo reparte a las juntas vecinas, así
	-- que un solo rayo despistado levantaba cuatro tramos y dejaba la calzada 4,5
	-- studs sobre la hierba. Ese canto es un obstáculo para el navmesh, el
	-- pathfinder rodeaba nuestra propia carretera, y el camino de la ruta verde
	-- pasaba de 512 a 679 studs.
	--
	-- El criterio no es un número a ojo: **una junta no puede estar más alto de lo
	-- que se alcanza desde un extremo subiendo a la pendiente máxima**. Los
	-- extremos son los dos datos que sí conocemos (la losa de la que sale la vía y
	-- la calle a la que llega), y una cuesta de verdad siempre cumple ese límite
	-- porque sube tramo a tramo. Lo que no lo cumple no se puede recorrer, así que
	-- tampoco hay que construirlo.
	--
	-- Se aplica dos veces, antes y después de los conos: antes para que el pico no
	-- contamine, después para garantizar que el resultado no tenga escalones contra
	-- los extremos.
	local function limitarDesdeExtremos()
		for i = 1, tramos - 1 do
			local desdeElPrincipio = cotas[0] + i * SALTO_MAXIMO
			local desdeElFinal = cotas[tramos] + (tramos - i) * SALTO_MAXIMO
			cotas[i] = math.min(cotas[i], math.min(desdeElPrincipio, desdeElFinal))
		end
	end
	limitarDesdeExtremos()

	local suelo = table.clone(cotas)
	for i = 1, tramos - 1 do
		local mejor = suelo[i]
		for j = 0, tramos do
			mejor = math.max(mejor, suelo[j] - math.abs(i - j) * SALTO_MAXIMO)
		end
		cotas[i] = mejor
	end

	-- Y OTRA VEZ DESPUÉS DE LOS CONOS, porque los conos sólo SUBEN juntas (son un
	-- máximo): garantizan la pendiente entre las de enmedio, pero pueden dejar una
	-- levantada junto a un extremo bajo, y ahí queda la caída que todo lo demás
	-- venía a evitar. Medido en el acceso a la verde antes de esto: sus últimas
	-- juntas subían a 26,5 con la calle esperando abajo a 23,5 -- tres studs de
	-- golpe contra la calzada, y en el peor sitio posible, porque es donde el
	-- jugador llega a entregar.
	limitarDesdeExtremos()

	local estorbos = OverlapParams.new()
	estorbos.FilterType = Enum.RaycastFilterType.Include
	estorbos.FilterDescendantsInstances = if ciudad then { ciudad } else {}
	estorbos.MaxParts = 60

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
			--
			-- POCO, y ésta es la medida delicada de toda la vía: el solape es también
			-- lo que crea los escalones. Dos tramos con distinta inclinación se cruzan
			-- en la zona solapada, y el canto del de atrás asoma sobre el de delante
			-- la mitad del solape por la diferencia de pendientes. Con seis studs eso
			-- daba un muro de cuatro donde la vía cambia de cuesta -- justo lo que
			-- dejó a JJ sin poder salir de casa. Con 2,6 (algo más que el grosor del
			-- firme) la junta sigue tapada y el canto baja de medio stud.
			Vector3.new(ancho, GROSOR_VIA, (b - a).Magnitude + 2.6),
			centro,
			Color3.fromRGB(96, 96, 102),
			padre
		)
		tramo.Material = Enum.Material.Asphalt
		tramo.CFrame = CFrame.lookAt(centro, b)

		-- Y SE DESPEJA LO QUE HAYA EN MEDIO. Medido: cinco tramos de acceso pasaban
		-- a través de VALLAS de la ciudad -- las mismas 116 vallas con las que el
		-- pathfinding de los ladrones ya se atasca (ver PatrolService). Una vía que
		-- atraviesa una valla no es una vía: es una valla con asfalto pintado
		-- debajo, y el jugador que llega en furgoneta se queda parado sin entender
		-- por qué. Se limpia el corredor por encima del firme, igual que se despeja
		-- la parcela de un edificio, y con la misma regla: lo grande no se toca,
		-- porque si un edificio entero roza la vía el problema es el trazado.
		local corredor = workspace:GetPartBoundsInBox(
			CFrame.lookAt(centro + Vector3.new(0, 7, 0), b + Vector3.new(0, 7, 0)),
			Vector3.new(ancho, 12, (b - a).Magnitude + 6),
			estorbos
		)
		for _, pieza in corredor do
			if esDespejable(pieza) then
				pieza:Destroy()
			end
		end
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
	local pieza = part(nombre, tamano, Vector3.new(centro.X, y + ALTO_LOSA / 2, centro.Z), color, padre)

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

-- EL CAMINO REAL de una ruta: por dónde se va de verdad, no la recta.
--
-- Existe porque los contactos repartidos sobre la recta caían en el camino el
-- 0 % de las veces en la ruta verde (medido contra esto mismo). Una ciudad con
-- manzanas no se parece a una recta, y un contacto que no se pisa es decorado.
--
-- Si el pathfinder no encuentra camino se devuelve la recta: mejor un reparto
-- imperfecto que ninguno, y el aviso queda en la consola para que se vea.
local function caminoDeRuta(ruta: Routes.Ruta): { Vector3 }
	local recta = { Config.ALMACEN_POS, ruta.destino }

	-- Un peatón: radio y altura de persona, y SIN saltar. Un camino que sólo
	-- existe saltando un bordillo no es el camino por el que va la gente.
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(Config.POLIGONO_SALIDA, ruta.destino)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		warn("[Contrabando] sin camino para los contactos de " .. ruta.id .. ", se reparten en recta")
		return recta
	end

	local puntos: { Vector3 } = { Config.ALMACEN_POS }
	for _, w in path:GetWaypoints() do
		table.insert(puntos, w.Position)
	end
	if #puntos < 2 then
		return recta
	end
	return puntos
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
local function sembrarContactos(
	ciudad: Instance?,
	ruta: Routes.Ruta,
	camino: { Vector3 },
	anclas: { Vector3 },
	padre: Instance
): { BasePart }
	local piezas: { BasePart } = {}
	-- Las del rastro, en orden, para dorarlas DESPUÉS de saber cuáles cabían.
	local delRastro: { BasePart } = {}

	for i, contacto in Contacts.deRuta(ruta.id, camino, anclas) do
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

		local esRacimo = contacto.tipo == "racimo"
		local esRastro = contacto.tipo == "rastro"
		local lado = if esRacimo then 3.4 elseif esRastro then 1.9 else 2.2
		local pieza = part(
			string.format("Contacto_%s_%d", ruta.id, i),
			Vector3.new(lado, lado, 0.7),
			Vector3.new(x, (y :: number) + 3.2, z),
			if esRacimo then Color3.fromRGB(255, 196, 84) else Color3.fromRGB(236, 226, 196),
			padre
		)
		pieza.Material = Enum.Material.Neon
		pieza.CanCollide = false
		pieza.Orientation = Vector3.new(0, 0, 0)
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
				pieza:SetAttribute("tipo", "suelto")
				pieza.Size = Vector3.new(2.6, 2.6, 0.7)
				pieza.Color = Color3.fromRGB(255, 214, 130)
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
	local baseBaliza = alto + 3
	local altoBaliza = 46 - baseBaliza
	local baliza = part(
		"Baliza_Taller",
		Vector3.new(5, altoBaliza, 5),
		Vector3.new(base.Position.X, suelo + baseBaliza + altoBaliza / 2, base.Position.Z),
		Palette.TALLER,
		padre
	)
	baliza.CanCollide = false
	baliza.Material = Enum.Material.Neon
	baliza.Transparency = 0.25
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
	despejar(ciudad, Vector3.new(x, y, z), 38, 45)

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

	-- Y una luz roja encima, MÁS ALTA QUE LOS TEJADOS. Empezó midiendo 46 studs y
	-- eso era, en la práctica, no tenerla: la ciudad tiene 2.944 piezas de más de
	-- 20 studs de alto, con la cumbrera mediana a 86 y el 90% por debajo de 101. Un
	-- farol de 46 no asoma por encima de casi nada, así que la guarida sólo existía
	-- en el minimapa -- *"los enemigos no se ven, sólo en el plano del mapa"* (JJ).
	--
	-- La altura se eligió MIDIENDO, no a ojo: 218 rayos desde el camino de las tres
	-- rutas hacia cada guarida que tuvieran a menos de 400 studs, contando desde qué
	-- fracción del trayecto hay línea de visión limpia.
	--
	--     46 studs (lo que había) ... se ve el 39% de las veces
	--     90 .......................... 50%
	--    130 .......................... 54%
	--    170 .......................... 62%
	--    210 .......................... 67%
	--
	-- Sube deprisa hasta 170 y luego se aplana: a partir de ahí lo que tapa la
	-- guarida no es un tejado sino el edificio que tienes delante, y contra eso no
	-- hay altura que valga. Así que 170 -- que además sigue siendo MÁS BAJO que el
	-- faro de la comisaría (190), y esa diferencia es información: el sitio al que
	-- corres tiene que verse desde más lejos que el sitio que hay que rodear.
	local farol = part("GuaridaFarol_" .. indice, Vector3.new(4, 120, 4), Vector3.new(x, y + 60, z), ROJO, padre)
	farol.Material = Enum.Material.Neon
	farol.CanCollide = false
	farol.Transparency = 0.35

	-- Y su nombre arriba del todo, a la altura del tejado: un pilar rojo dice "algo
	-- pasa aquí", pero no dice qué. Sin AlwaysOnTop, igual que el resto de placas:
	-- si se leyera a través de los edificios, rodear la manzana no serviría de nada.
	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Cartel"
	cartel.Size = UDim2.fromScale(20, 5)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 92, 0)
	cartel.MaxDistance = 900
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
	despejar(ciudad, Vector3.new(x, y, z), LADO + 4, 45)

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

	-- Y el pilar de luz por encima de los edificios (llegan a 175 studs), para
	-- verlo desde la otra punta del barrio.
	local faro = part("RefugioFaro_" .. indice, Vector3.new(5, 145, 5), Vector3.new(x, y + 72.5, z), AZUL, padre)
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
	prompt(almacen, Strings.get("PROMPT_DROP_CARGO"), Strings.get("HUD_WAREHOUSE"), 30).Name = "PromptDevolver"

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
		cartel.MaxDistance = 140
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
	prompt(taller, Strings.get("PROMPT_BUY_VEHICLE"), Strings.get("PROMPT_DEALERSHIP"), 26).Name = "PromptTaller"
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
		-- Se guardan para el taller: su parcela no puede caer sobre esta carretera.
		local calleDestino = calle
		local bordeDestino = if calle ~= nil then bordeDeLosa(destino, calle) else destino.Position
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
			local sitio, calleTaller = nil, nil
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
						sitio, calleTaller, mejorNota = centro, calle, nota
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
			if sitio ~= nil then
				despejar(ciudad, sitio, 110, 45)
				local tallerZona =
					losa(ciudad, "Taller_" .. ruta.id, Vector3.new(96, ALTO_LOSA, 60), sitio, Palette.TALLER, mundo)
				prompt(tallerZona, Strings.get("PROMPT_BUY_VEHICLE"), Strings.get("PROMPT_DEALERSHIP"), 26).Name =
					"PromptTaller"
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
			Vector3.new(8, 210, 8),
			-- Centrada a la MITAD de su alto para que nazca en el suelo. Al bajarla
			-- de 300 a 210 hubo que mover esto con ella: una columna de 210 studs
			-- centrada a 150 arranca a 45 del suelo, o sea flotando.
			destino.Position + Vector3.new(0, 105, 0),
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
		texto.Text = Strings.get("ROUTE_SIGN", { ruta = Strings.ref("ROUTE_" .. ruta.id), paga = Routes.paga(ruta.id) })
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
		-- Las rutas sin peligro NO PIDEN SITIO. Medido al entrar el barrio: sus
		-- candidatos competían con los de la verde --Shelter.repartir descarta los
		-- que caen a menos de 320 studs entre sí-- y la verde se quedaba sin
		-- refugio. Un solar pedido por quien no lo necesita se lo quita a quien sí.
		local cuantos = ruta.refugios or Config.REFUGIOS_POR_RUTA
		if cuantos > 0 then
			table.insert(grupos, Shelter.sitiosDeRuta(Config.ALMACEN_POS, ruta.destino, cuantos + 2))
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
		for _, sitio in Lairs.sitiosDeRuta(Config.ALMACEN_POS, ruta.destino, ruta.guaridas or Config.GUARIDAS_POR_RUTA) do
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
	for _, sitio in Shelter.repartir(grupos) do
		local pieza = refugio(ciudad, #refugios + 1, sitio, mundo, tomados)
		if pieza then
			table.insert(refugios, pieza.Position)
			table.insert(tomados, pieza.Position)
		end
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
		for _, pieza in sembrarContactos(ciudad, ruta, camino, guaridasDeRuta[ruta.id] or {}, mundo) do
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
