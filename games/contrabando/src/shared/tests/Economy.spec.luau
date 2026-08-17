--!strict
local Economy = require(script.Parent.Parent.Economy)

return function(kit)
	local comun = { rareza = "comun" }
	local marcada = { rareza = "marcada" }
	local legendaria = { rareza = "legendaria" }

	kit.eq("una comun por la verde vale la base", Economy.valorCaja(comun, 1), 10)
	kit.eq("la ruta multiplica", Economy.valorCaja(comun, 10), 100)
	kit.eq("la rareza multiplica", Economy.valorCaja(marcada, 1), 100)

	-- El caso que define el juego: rareza y ruta se COMBINAN.
	-- Una legendaria por la roja = 10 base x 135 rareza x 10 ruta.
	kit.eq("legendaria por la roja", Economy.valorCaja(legendaria, 10), 13500)

	kit.eq("una entrega suma sus cajas", Economy.valorEntrega({ comun, comun, marcada }, 3), 360)
	kit.eq("entregar nada no paga", Economy.valorEntrega({}, 10), 0)

	-- Un exploit que invente una rareza no debe cobrar: mejor reventar que pagar de más.
	kit.errors("una rareza inventada revienta", function()
		Economy.valorCaja({ rareza = "diamante" }, 1)
	end)
end
