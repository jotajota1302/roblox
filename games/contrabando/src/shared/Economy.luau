--!strict
--[[
	Economy.luau — cuánto paga una entrega. Módulo PURO: no toca Roblox.

	Regla central del diseño: los multiplicadores de rareza y de ruta se COMBINAN.
	De ahí sale la decisión más tensa del juego (una legendaria por la roja vale
	13.500, pero tu haz de luz se ve desde el otro extremo del mapa).
]]

local Config = require(script.Parent.Config)

export type Caja = { rareza: string }

local Economy = {}

-- Busca la definición de una rareza. Revienta si no existe: si el servidor recibe
-- una rareza inventada, pagar de más es mucho peor que cortar la operación.
function Economy.rareza(id: string)
	for _, def in Config.RAREZAS do
		if def.id == id then
			return def
		end
	end
	error("rareza desconocida: " .. tostring(id))
end

function Economy.valorCaja(caja: Caja, multiplicadorRuta: number): number
	local def = Economy.rareza(caja.rareza)
	return Config.CAJA_VALOR_BASE * def.multiplicador * multiplicadorRuta
end

function Economy.valorEntrega(cajas: { Caja }, multiplicadorRuta: number): number
	local total = 0
	for _, caja in cajas do
		total += Economy.valorCaja(caja, multiplicadorRuta)
	end
	return total
end

return Economy
