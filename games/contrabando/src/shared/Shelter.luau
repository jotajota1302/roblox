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

	for i = 1, cuantos do
		-- Repartidos por el tramo central. Ni pegados al almacén --donde ya estás a
		-- salvo y sobrarían-- ni pegados al destino, donde el viaje ya está hecho.
		local t = 0.3 + 0.4 * ((i - 0.5) / cuantos)
		local centro = origen:Lerp(destino, t)
		local signo = if i % 2 == 1 then 1 else -1
		table.insert(sitios, centro + lado * (Config.REFUGIO_DESVIO * signo))
	end

	return sitios
end

return Shelter
