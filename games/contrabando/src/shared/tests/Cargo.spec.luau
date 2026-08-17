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
end
