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
]]

local Config = require(script.Parent.Config)

export type Contacto = { pos: Vector3, valor: number, tipo: string }

local Contacts = {}

-- El tramo útil del corredor, en fracción del trayecto. Empieza pasada la zona
-- segura y termina antes del destino, por lo mismo que en Lairs: un contacto a la
-- puerta de casa es gratis, y uno pegado a la entrega llega cuando ya no hay
-- viaje. Se mide EN STUDS, no en fracción -- una fracción dice lo mismo para una
-- ruta de 420 studs que para una de 1.400, y no es lo mismo.
local function tramo(largo: number): (number, number)
	local tMin = (Config.ZONA_SEGURA_RADIO + 40) / largo
	local tMax = 1 - 60 / largo
	return tMin, tMax
end

function Contacts.sueltos(origen: Vector3, destino: Vector3, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 then
		return salida
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	local largo = plano.Magnitude
	if largo < 1 then
		return salida
	end

	local tMin, tMax = tramo(largo)
	if tMax <= tMin then
		-- Ruta tan corta que no hay tramo donde ponerlos sin pisar la casa o el
		-- destino. Ninguno es mejor que uno mal puesto.
		return salida
	end

	for i = 1, cuantos do
		local t = tMin + (tMax - tMin) * ((i - 0.5) / cuantos)
		table.insert(salida, {
			pos = origen:Lerp(destino, t),
			valor = Config.CONTACTO_VALOR_SUELTO,
			tipo = "suelto",
		})
	end

	return salida
end

-- Un racimo por peligro, apartado hacia el lado del corredor. Sin peligros no hay
-- racimos: su razón de ser es estar junto a uno, así que uno suelto en mitad de
-- ninguna parte sería un premio sin apuesta.
function Contacts.racimos(origen: Vector3, destino: Vector3, peligros: { Vector3 }, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 or #peligros == 0 then
		return salida
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	if plano.Magnitude < 1 then
		return salida
	end
	-- Perpendicular en el plano: girar 90° es (z, -x).
	local lado = Vector3.new(plano.Z, 0, -plano.X).Unit

	for i = 1, math.min(cuantos, #peligros) do
		local ancla = peligros[i]
		local signo = if i % 2 == 1 then 1 else -1
		table.insert(salida, {
			pos = ancla + lado * (Config.CONTACTO_RACIMO_DESVIO * signo),
			valor = Config.CONTACTO_VALOR_RACIMO,
			tipo = "racimo",
		})
	end

	return salida
end

function Contacts.deRuta(rutaId: string, origen: Vector3, destino: Vector3, peligros: { Vector3 }): { Contacto }
	local cuantos = Config.CONTACTOS_POR_RUTA[rutaId]
	if not cuantos then
		return {}
	end

	local salida = Contacts.sueltos(origen, destino, cuantos.sueltos)
	for _, c in Contacts.racimos(origen, destino, peligros, cuantos.racimos) do
		table.insert(salida, c)
	end
	return salida
end

-- LA MEDIDA QUE IMPORTA: cuántos recoge de verdad quien va en línea recta.
--
-- Es la misma comprobación que Detectors.disparadosEnLineaRecta, y existe por lo
-- mismo: quince detectores acabaron en las azoteas y nada reventó. Un contacto
-- que el jugador no pisa es decorado, no sistema.
function Contacts.recogidosEnLineaRecta(
	contactos: { Contacto },
	origen: Vector3,
	destino: Vector3,
	radio: number
): number
	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	local largo = plano.Magnitude
	if largo < 1 then
		return 0
	end
	local unidad = plano.Unit

	local cuenta = 0
	for _, c in contactos do
		local rel = Vector3.new(c.pos.X - origen.X, 0, c.pos.Z - origen.Z)
		local avance = rel:Dot(unidad)
		if avance < 0 or avance > largo then
			continue
		end
		-- La desviación se mide EN EL PLANO. Medirla en 3D fue lo que hizo pasar
		-- por "83 studs de desviación" un detector cuya desviación real era 0: los
		-- 83 eran altura.
		local desvio = (rel - unidad * avance).Magnitude
		if desvio <= radio then
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
