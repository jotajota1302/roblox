--!strict
local Cargo = require(script.Parent.Parent.Cargo)
local Vehicles = require(script.Parent.Parent.Vehicles)
local Config = require(script.Parent.Parent.Config)

return function(kit)
	local comun = { rareza = "comun" }
	local sellada = { rareza = "sellada" }
	local legendaria = { rareza = "legendaria" }

	kit.eq("sin carga no pesa", Cargo.pesoTotal({}), 0)
	kit.eq("tres comunes pesan tres", Cargo.pesoTotal({ comun, comun, comun }), 3)
	kit.eq("una sellada pesa dos", Cargo.pesoTotal({ sellada }), 2)
	kit.eq("una legendaria pesa tres", Cargo.pesoTotal({ legendaria }), 3)

	kit.truthy("cabe una comun con el zurron vacio", Cargo.cabe({}, comun, Config.CAPACIDAD_A_PIE))
	kit.truthy("la legendaria cabe justa a pie", Cargo.cabe({}, legendaria, Config.CAPACIDAD_A_PIE))
	kit.falsy("pero no cabe nada mas con ella", Cargo.cabe({ legendaria }, comun, Config.CAPACIDAD_A_PIE))
	kit.falsy("ni una comun cuando ya llevas tres", Cargo.cabe({ comun, comun, comun }, comun, Config.CAPACIDAD_A_PIE))

	kit.eq("vacio vas a velocidad normal", Cargo.velocidad({}), Config.VELOCIDAD_BASE)
	kit.near("una caja ya se nota", Cargo.velocidad({ comun }), 14.6)
	kit.near("a tope vas claramente lento", Cargo.velocidad({ comun, comun, comun }), 11.8)

	-- Innegociable: por muchas vueltas que dé el cálculo, nadie se queda clavado.
	kit.truthy("la velocidad nunca baja de 8", Cargo.velocidad({ legendaria, legendaria, legendaria }) >= 8)

	-- Capacidad segun vehiculo. Sin esto, el almacen llenaba hasta 3 mientras el
	-- zurron admitia 10.
	kit.eq("sin vehiculo la capacidad es la de a pie", Cargo.capacidad(nil), Config.CAPACIDAD_A_PIE)
	-- Contra Config y no contra un 10 escrito a mano: la escalera de vehiculos se
	-- va a seguir retocando, y una prueba que fija el numero obliga a tocarla en
	-- cada ajuste de balance sin comprobar nada nuevo.
	kit.eq("la capacidad sale del vehiculo", Cargo.capacidad("furgoneta"), Vehicles.get("furgoneta").capacidad)
	kit.eq("con basura se cae a la de a pie", Cargo.capacidad("cohete"), Config.CAPACIDAD_A_PIE)

	local diez = {}
	for _ = 1, 10 do
		table.insert(diez, comun)
	end
	kit.truthy("diez comunes caben en la furgoneta", Cargo.cabe({}, comun, Cargo.capacidad("furgoneta")))
	local tope = Cargo.capacidad("furgoneta")
	local aTope = {}
	for _ = 1, tope do
		table.insert(aTope, comun)
	end
	kit.falsy("pasado el tope ya no cabe nada", Cargo.cabe(aTope, comun, tope))

	-- El vehiculo cambia las DOS mitades del calculo: de donde parte la velocidad y
	-- cuanto le quita cada unidad de peso.
	kit.truthy("la furgoneta vacia va mas rapida que a pie", Cargo.velocidad({}, "furgoneta") > Cargo.velocidad({}))
	kit.truthy("y cargada a tope sigue moviendose", Cargo.velocidad(aTope, "furgoneta") > 0)

	-- LO QUE SIGUE SIENDO CIERTO, y es lo que la regla vieja protegia: llevar carga
	-- SIEMPRE cuesta velocidad, en cualquier vehiculo. Si transportar no costara, no
	-- habria decision: irias siempre a tope por la ruta que mas pague.
	kit.truthy(
		"cargar frena, tambien en furgoneta",
		Cargo.velocidad(aTope, "furgoneta") < Cargo.velocidad({}, "furgoneta")
	)
	kit.truthy("y a pie", Cargo.velocidad({ comun, comun, comun }) < Cargo.velocidad({}))

	-- La regla "ningun vehiculo corre mas que ir a pie" se cambio a proposito al
	-- meter la escalera de nueve (JJ pidio comprar cosas "para ir mas rapido"). Lo
	-- que impide que alguien sea inalcanzable ya no es congelar la velocidad, sino
	-- que los perseguidores escalen con el perseguido: ver PatrolService.

	-- SACAR UN VEHÍCULO CON EL ZURRÓN LLENO. La regla vieja decía "descarga antes de
	-- cambiar" con una sola caja encima, y eso bloqueaba justo lo que quiere hacer
	-- quien acaba de comprarse la furgoneta. Lo que no puede es cambiar A MENOS.
	local tresComunes = {
		{ rareza = "comun" } :: any,
		{ rareza = "comun" } :: any,
		{ rareza = "comun" } :: any,
	}
	kit.truthy("con tres cajas se puede sacar la furgoneta", (Cargo.admiteLaCarga(tresComunes, "furgoneta")))
	kit.truthy("y seguir a pie, que caben tres", (Cargo.admiteLaCarga(tresComunes, nil)))

	local zurronDeFurgoneta = {}
	for _ = 1, 10 do
		table.insert(zurronDeFurgoneta, { rareza = "comun" } :: any)
	end
	kit.falsy("pero con diez cajas no se baja uno a pie", (Cargo.admiteLaCarga(zurronDeFurgoneta, nil)))
	local _, motivo = Cargo.admiteLaCarga(zurronDeFurgoneta, nil)
	kit.eq("y el motivo es el hueco", motivo, "no_cabe_la_carga")

	-- Y EL TAMAÑO, que es la otra mitad: un piano no baja a un monopatín por mucho
	-- hueco que sobre.
	local conPiano = { { rareza = "comun", objeto = "piano" } :: any }
	kit.truthy("con el piano se puede sacar la furgoneta", (Cargo.admiteLaCarga(conPiano, "furgoneta")))
	kit.falsy("pero no el monopatin", (Cargo.admiteLaCarga(conPiano, "monopatin")))
	local _, porQue = Cargo.admiteLaCarga(conPiano, "monopatin")
	kit.eq("y ahi el motivo es el tamano", porQue, "carga_demasiado_grande")

	kit.truthy("de vacio se puede sacar cualquiera", (Cargo.admiteLaCarga({}, "monopatin")))
end
