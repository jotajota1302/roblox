--!strict
local Config = require(script.Parent.Parent.Config)
local Shelter = require(script.Parent.Parent.Shelter)

return function(kit)
	local refugios = {
		Vector3.new(0, 20, 0),
		Vector3.new(500, 20, 0),
	}

	-- Lo básico: dentro y fuera.
	kit.truthy("en el centro estas dentro", Shelter.dentro(Vector3.new(0, 20, 0), refugios) ~= nil)
	kit.truthy(
		"justo en el borde tambien",
		Shelter.dentro(Vector3.new(Config.REFUGIO_RADIO - 1, 20, 0), refugios) ~= nil
	)
	kit.falsy("un paso fuera ya no", Shelter.dentro(Vector3.new(Config.REFUGIO_RADIO + 5, 20, 0), refugios) ~= nil)

	-- EN EL PLANO, no en 3D. Quien esté en una azotea justo encima del refugio
	-- sigue dentro: un refugio protege el portal entero, y una regla que dependiera
	-- de la altura no habría forma de deducirla jugando.
	kit.truthy("la altura no te saca del refugio", Shelter.dentro(Vector3.new(0, 120, 0), refugios) ~= nil)

	-- Devuelve CUÁL, no sólo que sí: quien pregunta casi siempre necesita saberlo
	-- para dibujarlo o para que una patrulla sepa dónde esperar.
	local cual = Shelter.dentro(Vector3.new(495, 20, 0), refugios)
	kit.eq("dice en cual estas", cual and cual.X or -1, 500)

	-- Sin refugios no hay refugio: el caso del mapa a medio construir no puede
	-- devolver algo que no existe.
	kit.falsy("sin refugios no estas en ninguno", Shelter.dentro(Vector3.new(0, 20, 0), {}) ~= nil)

	-- El más cercano, que es lo que necesita el perseguido: no "hay refugios por
	-- ahí" sino cuál y a cuánto.
	local cerca, distancia = Shelter.masCercano(Vector3.new(400, 20, 0), refugios)
	kit.eq("elige el mas cercano", cerca and cerca.X or -1, 500)
	kit.near("y dice a que distancia", distancia, 100)

	local ninguno, lejos = Shelter.masCercano(Vector3.new(0, 0, 0), {})
	kit.falsy("sin refugios no hay ninguno cerca", ninguno ~= nil)
	kit.truthy("y la distancia es infinita, no cero", lejos == math.huge)

	-- EL PRECIO, que es lo que separa un refugio de un botón de anular: dentro se
	-- enfría deprisa, pero sigue costando tiempo parado sin cobrar.
	kit.truthy(
		"dentro se enfria mas rapido que fuera",
		Shelter.periodoDeEnfriado(true) < Shelter.periodoDeEnfriado(false)
	)
	kit.truthy("pero no es instantaneo", Shelter.periodoDeEnfriado(true) > 0)
	kit.eq("fuera manda el periodo normal", Shelter.periodoDeEnfriado(false), Config.CALOR_SEGUNDOS_POR_NIVEL)

	-- Dónde se plantan.
	local origen, destino = Vector3.new(0, 20, 0), Vector3.new(1000, 20, 0)
	local sitios = Shelter.sitiosDeRuta(origen, destino, 2)
	kit.eq("planta los que se le piden", #sitios, 2)

	-- DESVIADOS de la línea: un refugio que te pilla de paso no es una decisión.
	for i, s in sitios do
		local desvio = math.abs(s.Z - origen.Z)
		kit.near("el refugio " .. i .. " esta desviado de la ruta", desvio, Config.REFUGIO_DESVIO)
	end

	-- Y a lados alternos, para que no se puedan encadenar por el mismo borde en
	-- línea recta: hay que cruzar de un lado al otro.
	kit.truthy("estan a lados opuestos", sitios[1].Z * sitios[2].Z < 0)

	-- En el tramo central: ni pegados al almacén (donde ya estás a salvo y
	-- sobrarían) ni pegados al destino, donde el viaje ya está hecho.
	for i, s in sitios do
		local avance = (s.X - origen.X) / (destino.X - origen.X)
		kit.truthy("el refugio " .. i .. " esta en el tramo central", avance > 0.2 and avance < 0.8)
	end

	-- Casos límite que no pueden reventar el arranque del mundo.
	kit.eq("cero refugios devuelve lista vacia", #Shelter.sitiosDeRuta(origen, destino, 0), 0)
	kit.eq("un origen y destino iguales no revientan", #Shelter.sitiosDeRuta(origen, origen, 2), 0)
end
