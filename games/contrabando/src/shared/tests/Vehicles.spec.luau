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

	-- LO QUE UN ACCESORIO SÍ TIENE QUE CUMPLIR (22/08). Saltárselo en la escalera de
	-- carga deja un hueco: sin esto, un accesorio podría traer cualquier número y
	-- nadie se enteraría. Las tres reglas son las de siempre, dichas para ellos:
	--
	--   · NO DA VELOCIDAD. La regla de oro no es negociable -- "nadie inalcanzable"--
	--     y un accesorio que corriera más que el peatón la rompe por la puerta de
	--     atrás, sin pasar por la escalera que la vigila.
	--   · NO DA CAPACIDAD DE MÁS. Si además cargara como el vehículo de su precio,
	--     no habría nada que decidir: sería la compra obvia.
	--   · SALTA MÁS, o no es un accesorio de acceso sino un vehículo peor.
	local Vehiculos = require(script.Parent.Parent.Config).VEHICULOS
	local aPie = Vehicles.get(Vehicles.A_PIE)
	local cuantos = 0
	for _, v in Vehiculos do
		if not (v :: any).accesorio then
			continue
		end
		cuantos += 1
		kit.truthy(
			string.format("el accesorio %s no corre mas que ir a pie", v.id),
			v.velocidadBase <= aPie.velocidadBase
		)
		kit.truthy(string.format("y %s salta mas, que es para lo que esta", v.id), Vehicles.saltoFactor(v.id) > 1)
		for _, otro in Vehiculos do
			if not (otro :: any).accesorio and otro.coste == v.coste then
				kit.truthy(
					string.format("y %s carga menos que %s, que cuesta lo mismo", v.id, otro.id),
					v.capacidad < otro.capacidad
				)
			end
		end
	end
	kit.truthy("hay al menos un accesorio en el catalogo", cuantos >= 1)

	-- EL TECHO DE SALTO NO CRUZA UNA CALLE, y es la comprobación que sostiene el mapa
	-- entero por arriba. Con `Config.SALTO_ALTURA` y `Config.VELOCIDAD_BASE`, el
	-- alcance horizontal de un salto es `v * 2 * sqrt(2h/g)`; si llegara a los 26
	-- studs de calzada, se cruzaría de tejado a tejado y la retícula de calles
	-- dejaría de estructurar la ciudad -- que es lo único que hace que el piso de
	-- arriba sea un atajo con precio y no una autopista.
	--
	-- Se mide contra el MAYOR salto posible, que es por lo que en `RoadService` el
	-- factor del accesorio y el de la flecha no se multiplican: 1,7 x 2,2 daría 37
	-- studs de altura y 24,6 de alcance, a stud y medio de cruzar.
	local techo = 1
	for _, v in Vehiculos do
		techo = math.max(techo, Vehicles.saltoFactor(v.id))
	end
	techo = math.max(techo, Config.SALTO_IMPULSO_FACTOR)
	local alto = Config.SALTO_ALTURA * techo
	local GRAVEDAD = 196.2
	local alcance = Config.VELOCIDAD_BASE * 2 * math.sqrt(2 * alto / GRAVEDAD)
	kit.truthy(
		string.format("ni con el salto maximo (%.0f studs) se cruza una calle: %.1f de %d", alto, alcance, 26),
		alcance < 26
	)

	-- Y LOS ALIJOS DE TEJADO TIENEN QUE ESTAR AL ALCANCE DE LO QUE SE VENDE.
	--
	-- Es la lección de la red de seguridad, dicha al derecho: allí el guardián se
	-- escribió con el fondo a -130 "por prudencia" y no habría atrapado nada, porque
	-- la red para en -60 -- un número puesto a ojo contra otro número que ya existía.
	-- Aquí pasa lo mismo entre `ALIJO_TEJADO_MAX` y lo alto que salta el impulsor: si
	-- el techo de siembra subiera por encima del salto, habría premios visibles e
	-- imposibles, que es exactamente el fallo que se pagó con los racimos
	-- (*"salen paquetes fuera de la ruta y no se pueden coger"*).
	--
	-- Lo que vale es la RELACIÓN, no los dos números por separado: quien mañana suba
	-- el techo a 20 se entera aquí y no jugando.
	local mejorSalto = 1
	for _, v in Vehiculos do
		mejorSalto = math.max(mejorSalto, Vehicles.saltoFactor(v.id))
	end
	kit.truthy(
		string.format(
			"se llega a los alijos de tejado (%d studs) con el mejor accesorio (%.0f)",
			Config.ALIJO_TEJADO_MAX,
			Config.SALTO_ALTURA * mejorSalto
		),
		Config.ALIJO_TEJADO_MAX < Config.SALTO_ALTURA * mejorSalto
	)
	kit.truthy(
		"y los de tejado salen del total de alijos, no se suman",
		Config.ALIJOS_ALTOS < Config.ALIJOS and Config.ALIJOS_ALTOS >= 1
	)

	-- NINGUN EXPOSITOR EN EL CENTRO DEL TALLER, con el catálogo que sea.
	--
	-- Se comprueba de 1 a 24 y no sólo con los que hay hoy, porque el fallo aparece al
	-- CAMBIAR el número: el arreglo original corría los podios media plaza --correcto
	-- para siete-- y el día que entró el octavo volvió a poner uno justo en el centro.
	-- La sonda del mundo lo cazó diciendo "el Taller se pisa por arriba y lo que se
	-- pisa ahí es Podio4", que no se parece en nada a "sobra un vehículo".
	--
	-- Y también que no se solapen: dos expositores montados uno encima de otro son dos
	-- vehículos que no se distinguen en el escaparate.
	local PASO = 10
	for cuantos = 1, 24 do
		local centrado, pegados = 0, 0
		local anterior = nil
		for i = 1, cuantos do
			local x = Vehicles.podioX(i, cuantos, PASO)
			if math.abs(x) < PASO / 2 then
				centrado += 1
			end
			if anterior and math.abs(x - anterior) < PASO - 0.01 then
				pegados += 1
			end
			anterior = x
		end
		kit.eq(string.format("con %d expositores ninguno cae en el centro", cuantos), centrado, 0)
		kit.eq(string.format("y con %d ninguno se solapa con el de al lado", cuantos), pegados, 0)
	end

	-- EL NIVEL COMO LICENCIA, también en el taller. La escalera de vehículos tiene
	-- que subir a la vez que la de niveles: un peldaño caro que se abre antes que
	-- uno barato deja al barato sin sentido.
	local Config = require(script.Parent.Parent.Config)
	-- Los accesorios quedan fuera por lo mismo que en `Goods.spec`: no son peldaños de
	-- la escalera de carga, así que su coste no tiene por qué ordenarse con ella.
	local nivelAnterior, costeAnterior = 0, -1
	for _, v in Config.VEHICULOS do
		if (v :: any).accesorio then
			continue
		end
		if v.coste > 0 then
			local nivel = Vehicles.nivelDe(v.id)
			kit.truthy(
				string.format("%s no se abre antes que el anterior", v.id),
				nivel >= nivelAnterior and v.coste > costeAnterior
			)
			nivelAnterior, costeAnterior = nivel, v.coste
		end
	end
	kit.eq("ir a pie no pide nivel", Vehicles.nivelDe("a_pie"), 1)
	kit.eq("y un vehiculo inventado tampoco revienta", Vehicles.nivelDe("submarino"), 1)

	-- Con dinero de sobra pero sin nivel, no se compra -- y el motivo lo dice.
	local caro = Config.VEHICULOS[#Config.VEHICULOS]
	kit.falsy("sin nivel no se compra lo caro", (Vehicles.puedeComprar({}, caro.id, 999999, 1)))
	kit.eq(
		"y el motivo es el nivel, no el dinero",
		select(2, Vehicles.puedeComprar({}, caro.id, 999999, 1)),
		"nivel_insuficiente"
	)
	kit.truthy("con nivel y dinero, si", (Vehicles.puedeComprar({}, caro.id, 999999, 99)))
	-- Sin pasar nivel se comporta como antes: los servicios lo pasan, pero nada
	-- que se olvide de hacerlo debe dejar de funcionar en silencio.
	kit.truthy("sin nivel se comporta como antes", (Vehicles.puedeComprar({}, caro.id, 999999)))

	-- El escaparate ENSEÑA lo bloqueado, marcado. Esconderlo quitaría la mitad del
	-- motivo para seguir jugando.
	local paraNovato = Vehicles.mejorasPara(nil, 1)
	local bloqueados = 0
	for _, v in paraNovato do
		if (v :: any).bloqueado then
			bloqueados += 1
		end
	end
	kit.eq("al novato se le enseñan todos", #paraNovato, #Vehicles.mejorasPara(nil))
	kit.truthy("y algunos salen marcados como bloqueados", bloqueados > 0)
	local paraVeterano = Vehicles.mejorasPara(nil, 99)
	for _, v in paraVeterano do
		kit.falsy("al veterano no le bloquea ninguno", (v :: any).bloqueado)
	end
end
