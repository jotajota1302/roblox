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

	-- NINGUNO A LA SALIDA DE CASA, y esto se mide en STUDS. Es el defecto que
	-- destapó JJ jugando: con el reparto por fracción, el refugio de la ruta verde
	-- --622 studs-- caía a 230 del almacén, con su puerta a 35 studs de donde acaba
	-- la zona segura. Pegado a casa, meterse dentro nunca es lo mejor que puedes
	-- hacer, y una opción que nunca gana no es una opción.
	local corta = Shelter.sitiosDeRuta(origen, Vector3.new(622, 20, 0), Config.REFUGIOS_POR_RUTA + 2)
	kit.truthy("la ruta corta sigue teniendo refugios", #corta > 0)
	for i, s in corta do
		local aCasa = (Vector3.new(s.X, 0, s.Z) - Vector3.new(origen.X, 0, origen.Z)).Magnitude
		kit.truthy(
			string.format("el refugio %d de la ruta corta se aparta de casa (%.0f studs)", i, aCasa),
			aCasa - Config.REFUGIO_RADIO >= Config.ZONA_SEGURA_RADIO + Config.REFUGIO_MARGEN_CASA / 2
		)
	end

	-- Y en una ruta tan corta que no cabe ninguno, ninguno: antes que un refugio
	-- dentro de la zona segura, el almacén ya hace ese trabajo y está al lado.
	kit.eq(
		"en una ruta que no da para tramo no se planta nada",
		#Shelter.sitiosDeRuta(origen, Vector3.new(200, 20, 0), 2),
		0
	)

	-- EL REPARTO. Entra AGRUPADO POR RUTA, y tiene dos trabajos que pelean entre sí:
	-- que no se amontonen, y que ninguna ruta se quede sin uno.
	local grupos = {
		{ Vector3.new(0, 20, 0) },
		{ Vector3.new(40, 20, 0) }, -- pegado al de la ruta anterior, y es el único que tiene
	}
	local repartidos = Shelter.repartir(grupos, 300, 1)
	-- LA REGLA QUE NO SE ROMPE. Antes esto devolvía uno solo, y la segunda ruta se
	-- quedaba sin ningún sitio donde bajar el peligro: nada reventaba, esa ruta
	-- simplemente era peor y no había forma de saber por qué. Un refugio algo cerca
	-- de otro es un defecto de reparto; una ruta sin refugio es un agujero de juego.
	kit.eq("ninguna ruta se queda sin refugio", #repartidos, 2)

	-- Y CUANDO HAY ALTERNATIVA, se coge la que respeta la separación: la ruta de
	-- abajo propone dos sitios y el bueno es el lejano.
	local conAlternativa = {
		{ Vector3.new(0, 20, 0) },
		{ Vector3.new(40, 20, 0), Vector3.new(600, 20, 0) },
	}
	local elegidos = Shelter.repartir(conAlternativa, 300, 1)
	kit.eq("con alternativa se planta la lejana", elegidos[2], Vector3.new(600, 20, 0))
	for i = 1, #elegidos do
		for j = i + 1, #elegidos do
			local dx = elegidos[i].X - elegidos[j].X
			local dz = elegidos[i].Z - elegidos[j].Z
			kit.truthy("y entonces ningun par queda cerca", math.sqrt(dx * dx + dz * dz) >= 300)
		end
	end

	-- Dentro de un grupo se respeta el tope de refugios por ruta.
	local sobrados = { { Vector3.new(0, 20, 0), Vector3.new(900, 20, 0), Vector3.new(1800, 20, 0) } }
	kit.eq("no se plantan mas de los pedidos por ruta", #Shelter.repartir(sobrados, 300, 2), 2)

	kit.eq("sin propuestas no hay refugios", #Shelter.repartir({}, 300), 0)
	kit.eq("un grupo vacio no cuela un refugio fantasma", #Shelter.repartir({ {} }, 300), 0)

	-- Casos límite que no pueden reventar el arranque del mundo.
	kit.eq("cero refugios devuelve lista vacia", #Shelter.sitiosDeRuta(origen, destino, 0), 0)
	kit.eq("un origen y destino iguales no revientan", #Shelter.sitiosDeRuta(origen, origen, 2), 0)

	-- CADA RUTA CON SU CUPO. La roja mide el doble que la ambar y pide dos refugios;
	-- hasta el 20/08 el tope era global --`REFUGIOS_POR_RUTA`, o sea 1-- asi que la
	-- ruta que mas los necesitaba era la unica a la que se le quedaba corto. Y no se
	-- podia arreglar sin subirselo a todas.
	local lejos = {
		{ Vector3.new(0, 0, 0), Vector3.new(0, 0, 500), Vector3.new(0, 0, 1000) },
		{ Vector3.new(3000, 0, 0), Vector3.new(3000, 0, 500), Vector3.new(3000, 0, 1000) },
	}
	kit.eq("con un numero, el cupo vale para todos", #Shelter.repartir(lejos, 100, 1), 2)
	kit.eq("y con dos, cada grupo coge el suyo", #Shelter.repartir(lejos, 100, { 2, 1 }), 3)
	kit.eq("sin decir nada se comporta como antes", #Shelter.repartir(lejos, 100), 2)

	-- La red de seguridad sigue: un grupo cuyos sitios chocan todos con lo ya puesto
	-- coloca el primero igualmente. Una ruta sin refugio es un agujero de juego.
	local pegados = {
		{ Vector3.new(0, 0, 0) },
		{ Vector3.new(1, 0, 1) },
	}
	kit.eq("ninguna ruta se queda sin refugio", #Shelter.repartir(pegados, 100, { 1, 1 }), 2)
end
