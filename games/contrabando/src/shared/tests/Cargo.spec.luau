--!strict
local Cargo = require(script.Parent.Parent.Cargo)
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
	kit.eq("con furgoneta la capacidad es diez", Cargo.capacidad("furgoneta"), 10)
	kit.eq("con basura se cae a la de a pie", Cargo.capacidad("cohete"), Config.CAPACIDAD_A_PIE)

	local diez = {}
	for _ = 1, 10 do
		table.insert(diez, comun)
	end
	kit.truthy("diez comunes caben en la furgoneta", Cargo.cabe({}, comun, Cargo.capacidad("furgoneta")))
	kit.falsy("la once ya no", Cargo.cabe(diez, comun, Cargo.capacidad("furgoneta")))

	-- La furgoneta cambia las DOS mitades: de donde parte y cuanto le quita el peso.
	kit.near("la furgoneta vacia va un 10% mas lenta", Cargo.velocidad({}, "furgoneta"), 14.4)
	kit.near("y cargada a tope sigue moviendose", Cargo.velocidad(diez, "furgoneta"), 9.9)

	-- La regla que hace que el juego siga teniendo PvP: mas capacidad NUNCA es
	-- mas velocidad. Si la furgoneta fuese mas rapida, las rutas rojas pasarian a
	-- ser dinero gratis y la capa social moriria.
	kit.truthy(
		"cargado en furgoneta siempre vas mas lento que a pie",
		Cargo.velocidad(diez, "furgoneta") < Cargo.velocidad({ comun, comun, comun })
	)
	kit.truthy("y vacio tambien", Cargo.velocidad({}, "furgoneta") < Cargo.velocidad({}))
end
