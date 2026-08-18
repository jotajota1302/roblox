--!strict
--[[
	Detectors.luau — dónde se plantan las esquinas fichadas. Módulo PURO.

	POR QUÉ EXISTE, medido: recorrer la ruta roja de punta a punta daba CALOR 0. Sus
	dieciocho detectores estaban repartidos por el barrio con desvíos de hasta 200
	studs respecto al camino, y su radio es 35 -- así que se podía cruzar la zona
	más peligrosa del mapa sin que saltara ni uno. Y sin calor no hay ladrones, así
	que el viaje entero volvía a ser un paseo. Lo dijo JJ nada más jugar: "no veo a
	los ladrones".

	La cuenta que hay detrás es sencilla y es la que faltaba: si el desvío típico
	es mayor que el radio de detección, la vigilancia no vigila NADA. Aquí los
	postes se reparten en dos familias:

	  · los del CORREDOR, pegados al camino (desvío por debajo del radio), que son
	    los que garantizan que ir en línea recta cuesta calor;
	  · los del BARRIO, desviados de verdad, que son los que hacen que exista una
	    ruta alternativa mejor que otra.

	Sin los primeros no hay tensión; sin los segundos no hay nada que decidir. La
	proporción está en UNO DE CADA DOS y se comprueba en la prueba: recorrer la
	línea recta tiene que disparar al menos la mitad de los detectores de la ruta.

	Todo son cuentas sobre posiciones: se prueba entero sin Roblox.
]]

local Config = require(script.Parent.Config)

local Detectors = {}

-- Desde dónde se puede empezar a sembrar. Dentro de la zona segura el calor se
-- apaga en cada muestra, así que un poste ahí es decorado que no dispara nunca.
function Detectors.tMinimo(origen: Vector3, destino: Vector3): number
	local largo = (destino - origen).Magnitude
	return math.min(0.55, (Config.ZONA_SEGURA_RADIO + 40) / math.max(largo, 1))
end

export type Sitio = {
	posicion: Vector3,
	enElCorredor: boolean,
}

function Detectors.sitios(origen: Vector3, destino: Vector3, cuantos: number, radio: number?): { Sitio }
	local r = radio or Config.DETECTOR_RADIO
	local lista: { Sitio } = {}
	if cuantos <= 0 then
		return lista
	end

	local tMin = Detectors.tMinimo(origen, destino)
	-- La perpendicular al trayecto, en el plano: es la dirección en la que tiene
	-- sentido desviarse. Desviar en 3D metería postes dentro de la ladera.
	local linea = Vector3.new(destino.X - origen.X, 0, destino.Z - origen.Z)
	local perpendicular = if linea.Magnitude > 0.001
		then Vector3.new(-linea.Unit.Z, 0, linea.Unit.X)
		else Vector3.new(1, 0, 0)

	for i = 1, cuantos do
		local t = tMin + (0.95 - tMin) * ((i - 0.5) / cuantos)
		local centro = origen:Lerp(destino, t)
		-- Impares en el corredor, pares fuera. Alternar (en vez de "los primeros
		-- dentro y los últimos fuera") reparte las dos familias por todo el
		-- trayecto: con los garantizados agrupados al principio, la segunda mitad
		-- del viaje volvería a ser gratis.
		local enElCorredor = i % 2 == 1
		-- Y a lados opuestos, para que no se puedan esquivar todos andando pegado
		-- al mismo borde.
		local lado = if i % 4 < 2 then 1 else -1
		-- El del corredor se queda DENTRO del radio de detección aunque el jugador
		-- vaya por el borde opuesto del camino: ése es todo el punto.
		local desvio = if enElCorredor then r * 0.45 else r * 2.6
		local sitio = centro + perpendicular * (desvio * lado)
		table.insert(lista, { posicion = sitio, enElCorredor = enElCorredor })
	end

	return lista
end

-- Cuántos de esos postes dispararía alguien que fuera en línea recta del origen al
-- destino. Es la cuenta que convierte "hay dieciocho detectores" en "la ruta roja
-- de verdad quema": lo primero no significa nada por sí solo.
function Detectors.disparadosEnLineaRecta(
	origen: Vector3,
	destino: Vector3,
	sitios: { Sitio },
	radio: number?,
	paso: number?
): number
	local r = radio or Config.DETECTOR_RADIO
	local largo = (destino - origen).Magnitude
	local pasos = math.max(1, math.floor(largo / (paso or 10)))
	local tocados = 0
	for _, sitio in sitios do
		local alcanzado = false
		for k = 0, pasos do
			local punto = origen:Lerp(destino, k / pasos)
			local dx = punto.X - sitio.posicion.X
			local dz = punto.Z - sitio.posicion.Z
			if dx * dx + dz * dz <= r * r then
				alcanzado = true
				break
			end
		end
		if alcanzado then
			tocados += 1
		end
	end
	return tocados
end

return Detectors
