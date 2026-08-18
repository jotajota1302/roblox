--!strict
--[[
	Shelter.luau — los refugios: dónde no te pueden alcanzar. Módulo PURO.

	La regla es corta y no admite excepciones: DENTRO DE UN REFUGIO NO SE ROBA Y NO
	SE PERSIGUE. Es la misma promesa que hace el almacén, repartida por el mapa.

	Lo que separa un refugio del almacén es el PRECIO. El almacén apaga el calor de
	golpe; un refugio lo baja deprisa pero no al instante, así que meterse cuesta lo
	único que de verdad escasea en una sesión de diez minutos: tiempo parado sin
	cobrar. Sin ese precio, un refugio sería un botón de "anular la persecución" y
	el calor dejaría de significar nada.

	Todo lo de aquí son cuentas sobre posiciones: se prueba entero sin Roblox.
]]

local Config = require(script.Parent.Config)

local Shelter = {}

-- El refugio en el que estás, o nil. Devuelve el refugio en vez de un booleano
-- porque quien pregunta casi siempre quiere además saber CUÁL -- para dibujarlo,
-- para decir su nombre, o para que una patrulla sepa dónde plantarse a esperar.
function Shelter.dentro(posicion: Vector3, refugios: { Vector3 }, radio: number?): Vector3?
	local r = radio or Config.REFUGIO_RADIO
	for _, refugio in refugios do
		-- En el plano: un refugio protege el portal entero, no una esfera. Medido
		-- en 3D, quien estuviera en una azotea justo encima quedaría fuera por unos
		-- studs de altura, y esa es una regla que nadie podría deducir jugando.
		local dx = posicion.X - refugio.X
		local dz = posicion.Z - refugio.Z
		if dx * dx + dz * dz <= r * r then
			return refugio
		end
	end
	return nil
end

-- El más cercano y a qué distancia. Es lo que necesita el jugador perseguido:
-- no "hay refugios por ahí" sino "el tuyo está a 80 metros y en esa dirección".
function Shelter.masCercano(posicion: Vector3, refugios: { Vector3 }): (Vector3?, number)
	local mejor: Vector3? = nil
	local mejorDistancia = math.huge
	for _, refugio in refugios do
		local dx = posicion.X - refugio.X
		local dz = posicion.Z - refugio.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < mejorDistancia then
			mejor, mejorDistancia = refugio, d
		end
	end
	return mejor, mejorDistancia
end

-- Cuánto tarda en bajar un nivel de calor según dónde estés. Vive aquí y no
-- repartido por los servicios para que la diferencia entre estar dentro y estar
-- fuera sea UNA cuenta en un sitio, y no dos números que un día dejen de cuadrar.
function Shelter.periodoDeEnfriado(enRefugio: boolean): number
	if enRefugio then
		return Config.REFUGIO_SEGUNDOS_POR_NIVEL
	end
	return Config.CALOR_SEGUNDOS_POR_NIVEL
end

-- Dónde plantar los refugios de una ruta, dado su trayecto.
--
-- DESVIADOS de la línea a propósito: un refugio que te pilla de paso no es una
-- decisión, es un regalo. Hay que querer ir, y ese desvío es justo lo que hace
-- que exista una "ruta segura" distinta de la "ruta corta" -- que es lo que
-- faltaba para que elegir camino significara algo.
--
-- A lados alternos, para que no se pueda ir encadenándolos en línea recta por el
-- mismo borde: uno a la izquierda y el siguiente a la derecha obliga a cruzar.
function Shelter.sitiosDeRuta(origen: Vector3, destino: Vector3, cuantos: number): { Vector3 }
	local sitios: { Vector3 } = {}
	if cuantos <= 0 then
		return sitios
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	if plano.Magnitude < 1 then
		return sitios
	end
	-- Perpendicular en el plano: girar 90° es (z, -x).
	local lado = Vector3.new(plano.Z, 0, -plano.X).Unit

	-- EL TRAMO SE MIDE EN STUDS, NO EN FRACCIÓN. La versión anterior repartía entre
	-- el 25% y el 75% del trayecto, y con eso el refugio de la ruta verde --que mide
	-- 622 studs-- caía a 230 del almacén: su puerta quedaba a 35 studs de donde
	-- acaba la zona segura. *"Hay un refugio justo a la salida del almacén, no tiene
	-- sentido"* (JJ), y no lo tenía: pegado a casa, meterse dentro nunca es lo mejor
	-- que puedes hacer --el almacén apaga el calor entero y encima es donde cobras--
	-- así que el refugio deja de ser una decisión.
	--
	-- Una fracción dice cosas muy distintas en una ruta de 600 y en una de 1.700; en
	-- studs, el refugio arranca donde volver a casa empieza a doler. Es la misma
	-- lección que ya pagaron las guaridas (ver Lairs.sitiosDeRuta).
	local largo = plano.Magnitude
	local tMin = math.max(0.3, (Config.ZONA_SEGURA_RADIO + Config.REFUGIO_MARGEN_CASA) / largo)
	local tMax = math.min(0.8, 1 - Config.REFUGIO_MARGEN_DESTINO / largo)
	if tMax <= tMin then
		-- Ruta tan corta que no hay tramo donde plantarlo sin pisar la casa o el
		-- destino. En una ruta así el almacén ya hace de refugio: está al lado.
		return sitios
	end

	for i = 1, cuantos do
		-- Repartidos por ese tramo. Con uno por ruta lo que importa es que no caigan
		-- todos a la misma altura del viaje, y los de más son sólo suplentes para
		-- cuando el primero choca con el de otra ruta (ver Shelter.repartir).
		local t = tMin + (tMax - tMin) * ((i - 0.5) / cuantos)
		local centro = origen:Lerp(destino, t)
		local signo = if i % 2 == 1 then 1 else -1
		table.insert(sitios, centro + lado * (Config.REFUGIO_DESVIO * signo))
	end

	return sitios
end

-- TODOS los refugios del mapa, con la separación mínima garantizada Y sin dejar
-- ninguna ruta sin uno.
--
-- Cada ruta propone los suyos sin saber nada de las demás, y dos rutas que pasan
-- cerca acaban plantando refugios casi pegados: tres en el mismo barrio dejan de
-- ser una decisión y pasan a ser mobiliario urbano ("deberían ser menos y estar
-- más espaciados", JJ). Aquí se descartan los que caen demasiado cerca de uno ya
-- aceptado.
--
-- PERO NUNCA HASTA DEJAR UNA RUTA A SECAS, y esto lo enseñó la sonda del mundo:
-- la versión anterior recibía una lista plana y confiaba en que "el primero de
-- cada ruta sobrevive". Con un solo refugio por ruta eso es falso -- el de la
-- ámbar cayó a 233 studs del de la verde, se descartó, y **la ruta ámbar se quedó
-- sin ningún sitio donde bajar el peligro**. Nada reventó: simplemente esa ruta
-- era peor y nadie podía saber por qué.
--
-- Por eso ahora entra AGRUPADO por ruta. De cada grupo se cogen los que quepan
-- respetando la separación; si no cabe ninguno, se coge el primero igualmente. Un
-- refugio algo cerca de otro es un defecto de reparto; una ruta sin refugio es un
-- agujero de juego.
function Shelter.repartir(grupos: { { Vector3 } }, separacion: number?, porGrupo: number?): { Vector3 }
	local minimo = separacion or Config.REFUGIO_SEPARACION
	local tope = porGrupo or Config.REFUGIOS_POR_RUTA
	local aceptados: { Vector3 } = {}

	local function lejosDeTodos(sitio: Vector3): boolean
		for _, puesto in aceptados do
			local dx = sitio.X - puesto.X
			local dz = sitio.Z - puesto.Z
			if math.sqrt(dx * dx + dz * dz) < minimo then
				return false
			end
		end
		return true
	end

	for _, grupo in grupos do
		local puestos = 0
		for _, sitio in grupo do
			if puestos >= tope then
				break
			end
			if lejosDeTodos(sitio) then
				table.insert(aceptados, sitio)
				puestos += 1
			end
		end
		-- La red de seguridad: esta ruta no ha colocado ninguno.
		if puestos == 0 and #grupo > 0 then
			table.insert(aceptados, grupo[1])
		end
	end

	return aceptados
end

return Shelter
