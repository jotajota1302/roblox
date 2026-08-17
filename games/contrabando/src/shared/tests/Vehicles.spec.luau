--!strict
local Config = require(script.Parent.Parent.Config)
local Vehicles = require(script.Parent.Parent.Vehicles)

return function(kit)
	local aPie = Vehicles.get("a_pie")
	local furgo = Vehicles.get("furgoneta")

	kit.eq("a pie llevas tres", aPie.capacidad, Config.CAPACIDAD_A_PIE)
	kit.eq("la furgoneta lleva diez", furgo.capacidad, 10)
	kit.truthy("la furgoneta cuesta dinero", furgo.coste > 0)
	kit.eq("ir a pie no cuesta nada", aPie.coste, 0)

	-- La regla innegociable del diseño: capacidad y acceso, nunca potencia.
	kit.truthy("ningun vehiculo corre mas que ir a pie", furgo.velocidadBase <= aPie.velocidadBase)
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

	kit.eq("a pie hay una mejora que comprar", #Vehicles.mejorasPara(nil), 1)
	kit.eq("con la furgoneta ya no queda nada", #Vehicles.mejorasPara("furgoneta"), 0)
end
