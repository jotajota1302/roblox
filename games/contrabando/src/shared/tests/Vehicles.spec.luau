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

	-- LA COMPRA, que ahora mira el GARAJE y no el vehículo puesto.
	local puede, motivo = Vehicles.puedeComprar(nil, "furgoneta", furgo.coste)
	kit.truthy("con el dinero justo se compra", puede)
	kit.eq("y el motivo lo dice", motivo, "ok")

	local _, sinDinero = Vehicles.puedeComprar(nil, "furgoneta", furgo.coste - 1)
	kit.eq("una moneda de menos no basta", sinDinero, "sin_dinero")

	local _, repetida = Vehicles.puedeComprar({ "furgoneta" }, "furgoneta", 999999)
	kit.eq("no se compra dos veces", repetida, "ya_lo_tienes")

	local _, aPieVenta = Vehicles.puedeComprar(nil, "a_pie", 999999)
	kit.eq("ir a pie no esta a la venta", aPieVenta, "no_esta_a_la_venta")

	local _, inventado = Vehicles.puedeComprar(nil, "nave_espacial", 999999)
	kit.eq("un id inventado se rechaza sin reventar", inventado, "vehiculo_desconocido")

	-- COMPRAR HACIA ABAJO YA VALE, y es el cambio que hace que el garaje signifique
	-- algo: teniendo furgoneta, un patinete no es un desperdicio sino la llave de
	-- los atajos, porque la furgoneta no puede salirse del asfalto.
	local baratoConFurgo = Vehicles.puedeComprar({ "furgoneta" }, "monopatin", 999999)
	kit.truthy("con furgoneta se puede comprar un monopatin", baratoConFurgo)

	-- EL GARAJE.
	kit.truthy("ir a pie lo tiene todo el mundo siempre", Vehicles.posee(nil, "a_pie"))
	kit.truthy("lo comprado esta en el garaje", Vehicles.posee({ "moto", "monopatin" }, "moto"))
	kit.falsy("lo no comprado no", Vehicles.posee({ "moto" }, "furgoneta"))
	kit.falsy("y con el garaje vacio, nada", Vehicles.posee({}, "moto"))

	-- Sacar del garaje.
	kit.truthy("se saca lo que es tuyo", Vehicles.puedeSacar({ "moto" }, "moto"))
	local _, ajeno = Vehicles.puedeSacar({ "moto" }, "furgoneta")
	kit.eq("y no lo que no lo es", ajeno, "no_es_tuyo")
	kit.truthy("volver a ir a pie siempre vale", Vehicles.puedeSacar({}, "a_pie"))
	kit.truthy("y sin garaje tambien", Vehicles.puedeSacar(nil, nil))

	-- LA MIGRACIÓN, que es lo que evita dejar a pie a quien ya jugaba: las partidas
	-- guardadas antes del garaje sólo tienen un `vehiculo` suelto.
	local migrado = Vehicles.garajeDe(nil, "furgoneta")
	kit.eq("una partida vieja conserva su vehiculo", #migrado, 1)
	kit.eq("y es el suyo", migrado[1], "furgoneta")
	kit.eq("ir a pie no ocupa plaza", #Vehicles.garajeDe(nil, "a_pie"), 0)
	kit.eq("un id retirado del catalogo se cae solo", #Vehicles.garajeDe({ "trineo" }, nil), 0)
	-- Y esto no es hipotético: los patines EXISTIERON y se retiraron. Quien los
	-- tuviera guardados no puede quedarse sin poder entrar.
	kit.eq("los patines retirados desaparecen del garaje", #Vehicles.garajeDe({ "patines" }, "patines"), 0)
	kit.eq("pero lo demas del garaje sobrevive", #Vehicles.garajeDe({ "patines", "moto" }, "patines"), 1)
	kit.eq("y no se duplica lo que ya estaba", #Vehicles.garajeDe({ "moto" }, "moto"), 1)

	-- A pie está TODA la escalera por delante: es lo que hace que siempre haya algo
	-- cerca que comprar, en vez del único salto de 1.500 que había antes y que
	-- dejaba los cinco primeros viajes sin ninguna meta a la vista.
	-- Contra el catálogo, no contra un número escrito a mano: al retirar los
	-- patines esta prueba se puso roja por decir "8" en vez de "todos".
	local comprables = 0
	for _, v in Config.VEHICULOS do
		if v.coste > 0 then
			comprables += 1
		end
	end
	kit.eq("con el garaje vacio queda toda la escalera", #Vehicles.mejorasPara(nil), comprables)
	-- Y la primera oferta es la más barata: la tienda enseña el siguiente peldaño,
	-- no el último.
	local primeras = Vehicles.mejorasPara(nil)
	kit.truthy("y la primera oferta es la mas barata", primeras[1].coste < primeras[#primeras].coste)
	kit.truthy("comprar uno lo quita del escaparate", #Vehicles.mejorasPara({ "moto" }) == #primeras - 1)
	local todos = {}
	for _, v in require(script.Parent.Parent.Config).VEHICULOS do
		if v.coste > 0 then
			table.insert(todos, v.id)
		end
	end
	kit.eq("con todos comprados no queda nada", #Vehicles.mejorasPara(todos), 0)
end
