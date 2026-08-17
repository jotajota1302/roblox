--!strict
local Config = require(script.Parent.Parent.Config)
local Vehicles = require(script.Parent.Parent.Vehicles)

return function(kit)
	local aPie = Vehicles.get("a_pie")
	local furgo = Vehicles.get("furgoneta")

	kit.eq("a pie llevas tres", aPie.capacidad, Config.CAPACIDAD_A_PIE)
	kit.truthy("la furgoneta es la que mas lleva", furgo.capacidad >= 26)
	kit.truthy("la furgoneta cuesta dinero", furgo.coste > 0)
	kit.eq("ir a pie no cuesta nada", aPie.coste, 0)

	-- La regla del diseño era "ningún vehículo corre más que ir a pie", y la
	-- escalera de nueve vehículos la rompe POR LA LETRA a propósito: JJ pidió
	-- comprar cosas "para ir más rápido", y unos patines que no corren más que
	-- andar no son patines.
	--
	-- Lo que se conserva es el ESPÍRITU, que es lo que la regla protegía: nadie
	-- puede volverse inalcanzable, porque en el momento en que alguien lo es, el
	-- PvP muere y las rutas rojas pasan a ser dinero gratis. Se consigue por otro
	-- lado -- PatrolService pone a los perseguidores SIEMPRE por encima de la
	-- velocidad real del perseguido -- y aquí se comprueba lo que sigue siendo
	-- cierto: que la progresión es sobre todo de capacidad, no de potencia.
	local saltoCapacidad = furgo.capacidad / aPie.capacidad
	local saltoVelocidad = furgo.velocidadBase / aPie.velocidadBase
	kit.truthy("se progresa mucho mas en capacidad que en velocidad", saltoCapacidad > saltoVelocidad * 4)
	kit.truthy("y ninguno pasa del tope antitrampas", furgo.velocidadBase < Config.VELOCIDAD_MAXIMA_PLAUSIBLE)

	kit.errors("un vehiculo inventado revienta", function()
		Vehicles.get("nave_espacial")
	end)
	kit.falsy("y no existe", Vehicles.existe("nave_espacial"))
	kit.falsy("nil tampoco existe como id", Vehicles.existe(nil))

	-- nil significa "a pie" en el estado del jugador, y este es el unico sitio
	-- donde esa traduccion ocurre.
	kit.eq("sin vehiculo vas a pie", Vehicles.deEstado(nil).id, "a_pie")
	kit.eq("con basura tambien vas a pie", Vehicles.deEstado("cohete").id, "a_pie")
	kit.eq("con furgoneta vas en furgoneta", Vehicles.deEstado("furgoneta").id, "furgoneta")

	local puede, motivo = Vehicles.puedeComprar(nil, "furgoneta", furgo.coste)
	kit.truthy("con el dinero justo se compra", puede)
	kit.eq("y el motivo lo dice", motivo, "ok")

	local _, sinDinero = Vehicles.puedeComprar(nil, "furgoneta", furgo.coste - 1)
	kit.eq("una moneda de menos no basta", sinDinero, "sin_dinero")

	local _, repetida = Vehicles.puedeComprar("furgoneta", "furgoneta", 999999)
	kit.eq("no se compra dos veces", repetida, "ya_lo_tienes")

	local _, aPieVenta = Vehicles.puedeComprar(nil, "a_pie", 999999)
	kit.eq("ir a pie no esta a la venta", aPieVenta, "no_esta_a_la_venta")

	local _, inventado = Vehicles.puedeComprar(nil, "nave_espacial", 999999)
	kit.eq("un id inventado se rechaza sin reventar", inventado, "vehiculo_desconocido")

	-- A pie está TODA la escalera por delante: es lo que hace que siempre haya algo
	-- cerca que comprar, en vez del único salto de 1.500 que había antes y que
	-- dejaba los cinco primeros viajes sin ninguna meta a la vista.
	kit.truthy("a pie queda toda la escalera por comprar", #Vehicles.mejorasPara(nil) >= 8)
	-- Y la primera oferta es la más barata: la tienda enseña el siguiente peldaño,
	-- no el último.
	local primeras = Vehicles.mejorasPara(nil)
	kit.truthy("y la primera oferta es la mas barata", primeras[1].coste < primeras[#primeras].coste)
	kit.eq("con la furgoneta ya no queda nada", #Vehicles.mejorasPara("furgoneta"), 0)
end
