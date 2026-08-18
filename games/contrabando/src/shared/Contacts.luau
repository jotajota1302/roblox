--!strict
--[[
	Contacts.luau — los contactos que se recogen por el camino. Módulo PURO.

	POR QUÉ EXISTE. Medido: toda la experiencia del juego se otorgaba en una sola
	línea de CargoService, al entregar. Los 54-100 segundos de viaje no daban nada
	y sólo podían quitar. Esto pone algo bueno dentro del viaje sin tocar la
	economía de monedas, que ya está equilibrada.

	DOS POBLACIONES, CON TRABAJOS DISTINTOS:

	  · los SUELTOS van sobre la calzada del corredor y dan el RITMO. Si se
	    apartaran, el jugador tendría que ir a por ellos y el viaje se convertiría
	    en recolectar en vez de repartir;
	  · los RACIMOS se apartan hacia un peligro y dan la DECISIÓN. Su desvío es
	    menor que el de una guarida (55 frente a 70) para que el rodeo sea un
	    rodeo y no una expedición.

	FIJOS Y APRENDIBLES, como los detectores y las guaridas: el reparto sale del
	trazado, no de un dado. El jugador que repite la ruta sabe dónde están.

	Y SE REPARTEN SOBRE EL CAMINO REAL, no sobre la recta entre casa y destino.
	Esto no es un detalle: la primera versión los repartía sobre la recta y, medido
	contra el camino que calcula el pathfinder, **caían en el camino el 0 % de la
	ruta verde, el 8 % de la ámbar y el 5 % de la roja**. Treinta y ocho piezas
	plantadas, alumbradas y con sus atributos, y ninguna al alcance de nadie. Es la
	misma firma que los quince detectores en las azoteas: nada revienta y el
	sistema simplemente no existe.

	Por eso la entrada de este módulo es una POLILÍNEA y no un par origen-destino.
	Un par de puntos sigue valiendo (es una polilínea de dos), pero quien tenga el
	camino de verdad debe pasarlo.
]]

local Config = require(script.Parent.Config)

export type Contacto = { pos: Vector3, valor: number, tipo: string }

local Contacts = {}

-- Longitud de cada tramo de la polilínea, MEDIDA EN EL PLANO. Las cuestas de la
-- ciudad no cuentan como distancia recorrida para esto: lo que importa es dónde
-- pisa el jugador, no cuánto sube.
local function tramos(camino: { Vector3 }): ({ number }, number)
	local largos: { number } = {}
	local total = 0
	for i = 1, #camino - 1 do
		local a, b = camino[i], camino[i + 1]
		local d = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		largos[i] = d
		total += d
	end
	return largos, total
end

-- El punto del camino que está a `distancia` studs del principio.
local function puntoA(camino: { Vector3 }, largos: { number }, distancia: number): Vector3
	local recorrido = 0
	for i = 1, #largos do
		if recorrido + largos[i] >= distancia then
			local t = if largos[i] > 0 then (distancia - recorrido) / largos[i] else 0
			return camino[i]:Lerp(camino[i + 1], t)
		end
		recorrido += largos[i]
	end
	return camino[#camino]
end

-- La dirección del camino en ese punto, en el plano. La usan los racimos para
-- saber hacia qué lado apartarse; con la dirección global (casa -> destino) un
-- racimo de una curva se apartaba hacia dentro de la manzana.
local function direccionEn(camino: { Vector3 }, largos: { number }, distancia: number): Vector3
	local recorrido = 0
	for i = 1, #largos do
		if recorrido + largos[i] >= distancia or i == #largos then
			local a, b = camino[i], camino[i + 1]
			local plano = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if plano.Magnitude > 0.01 then
				return plano.Unit
			end
		end
		recorrido += largos[i]
	end
	return Vector3.new(0, 0, 1)
end

-- El tramo útil del camino, EN STUDS. Empieza pasada la zona segura y termina
-- antes del destino, por lo mismo que en Lairs: un contacto a la puerta de casa
-- es gratis, y uno pegado a la entrega llega cuando ya no hay viaje.
local MARGEN_FINAL = 60

function Contacts.sueltos(camino: { Vector3 }, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 or #camino < 2 then
		return salida
	end

	local largos, total = tramos(camino)
	local desde = Config.ZONA_SEGURA_RADIO + 40
	local hasta = total - MARGEN_FINAL
	if hasta <= desde then
		-- Camino tan corto que no hay tramo donde ponerlos sin pisar la casa o el
		-- destino. Ninguno es mejor que uno mal puesto.
		return salida
	end

	for i = 1, cuantos do
		local d = desde + (hasta - desde) * ((i - 0.5) / cuantos)
		table.insert(salida, {
			pos = puntoA(camino, largos, d),
			valor = Config.CONTACTO_VALOR_SUELTO,
			tipo = "suelto",
		})
	end

	return salida
end

-- Un racimo por peligro, apartado del camino a la altura de ese peligro. Sin
-- peligros no hay racimos: su razón de ser es estar junto a uno, así que uno
-- suelto en mitad de ninguna parte sería un premio sin apuesta.
function Contacts.racimos(camino: { Vector3 }, peligros: { Vector3 }, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 or #peligros == 0 or #camino < 2 then
		return salida
	end

	local largos, total = tramos(camino)

	for i = 1, math.min(cuantos, #peligros) do
		local ancla = peligros[i]
		-- ¿A qué altura del camino queda este peligro? De ahí sale hacia dónde
		-- apartarse, para que el racimo caiga ENTRE el camino y la guarida.
		local mejor, mejorD = 0, math.huge
		local recorrido = 0
		for j = 1, #largos do
			local a, b = camino[j], camino[j + 1]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if ab.Magnitude > 0.01 then
				local ap = Vector3.new(ancla.X - a.X, 0, ancla.Z - a.Z)
				local t = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
				local d = (ap - ab.Unit * t).Magnitude
				if d < mejorD then
					mejorD = d
					mejor = recorrido + t
				end
			end
			recorrido += largos[j]
		end

		local enElCamino = puntoA(camino, largos, math.clamp(mejor, 0, total))
		local hacia = ancla - enElCamino
		local plano = Vector3.new(hacia.X, 0, hacia.Z)
		-- Si la guarida está justo encima del camino, se aparta perpendicular: un
		-- racimo en mitad de la calzada no sería un rodeo.
		local desvio = if plano.Magnitude > 1
			then plano.Unit
			else Vector3.new(direccionEn(camino, largos, mejor).Z, 0, -direccionEn(camino, largos, mejor).X)

		table.insert(salida, {
			pos = enElCamino + desvio * Config.CONTACTO_RACIMO_DESVIO,
			valor = Config.CONTACTO_VALOR_RACIMO,
			tipo = "racimo",
		})
	end

	return salida
end

function Contacts.deRuta(rutaId: string, camino: { Vector3 }, peligros: { Vector3 }): { Contacto }
	local cuantos = Config.CONTACTOS_POR_RUTA[rutaId]
	if not cuantos then
		return {}
	end

	local salida = Contacts.sueltos(camino, cuantos.sueltos)
	for _, c in Contacts.racimos(camino, peligros, cuantos.racimos) do
		table.insert(salida, c)
	end
	return salida
end

-- LA MEDIDA QUE IMPORTA: cuántos recoge de verdad quien recorre el camino.
--
-- Es la misma comprobación que Detectors.disparadosEnLineaRecta y existe por lo
-- mismo, sólo que aquí ya cazó su fallo: con el reparto sobre la recta, esto daba
-- 0 de 7 en la ruta verde. Un contacto que el jugador no pisa es decorado.
function Contacts.cercaDelCamino(contactos: { Contacto }, camino: { Vector3 }, radio: number): number
	if #camino < 2 then
		return 0
	end

	local cuenta = 0
	for _, c in contactos do
		local mejor = math.huge
		for i = 1, #camino - 1 do
			local a, b = camino[i], camino[i + 1]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if ab.Magnitude < 0.01 then
				continue
			end
			-- EN EL PLANO. Medir en 3D convirtió una vez 83 studs de altura en "83
			-- studs de desviación".
			local ap = Vector3.new(c.pos.X - a.X, 0, c.pos.Z - a.Z)
			local t = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
			local d = (ap - ab.Unit * t).Magnitude
			if d < mejor then
				mejor = d
			end
		end
		if mejor <= radio then
			cuenta += 1
		end
	end
	return cuenta
end

-- LA RACHA: lo que has acelerado por lo que llevas recogido EN ESTE VIAJE.
--
-- La velocidad permanente está descartada (Levels.luau lo dice en su cabecera):
-- chocaría con la regla de que nadie puede volverse inalcanzable, y sin alcance no
-- hay PvP. Ésta es la salida que usa el juego que lo inspiró: la velocidad es del
-- intento, no tuya -- corres, aceleras, y un paso en falso te devuelve al
-- principio. Quien la aplique la borra al entregar y al ser alcanzado.
function Contacts.racha(recogidos: number): number
	if recogidos <= 0 then
		return 0
	end
	return math.min(recogidos * Config.RACHA_POR_CONTACTO, Config.RACHA_MAXIMA)
end

-- EL RECORTE NO ES DECORATIVO: es la regla de oro escrita en un número. El
-- antitrampas expulsa a quien pase de Config.VELOCIDAD_MAXIMA_PLAUSIBLE, así que
-- la suma se queda por debajo con margen -- y de paso, una velocidad base absurda
-- (un fallo en otro sitio) no puede colarse por aquí.
function Contacts.velocidadConRacha(base: number, recogidos: number): number
	return math.min(base + Contacts.racha(recogidos), Config.VELOCIDAD_MAXIMA_PLAUSIBLE - 2)
end

return Contacts
