--!strict
--[[
	Economy.luau — cuánto paga una entrega. Módulo PURO: no toca Roblox.

	Regla central del diseño: los multiplicadores de rareza y de ruta se COMBINAN.
	De ahí sale la decisión más tensa del juego (una legendaria por la roja vale
	13.500, pero tu haz de luz se ve desde el otro extremo del mapa).
]]

local Config = require(script.Parent.Config)
-- Goods sólo depende de Config, así que esto no cierra ningún ciclo.
local Goods = require(script.Parent.Goods)

-- `objeto` es el id del catálogo (Goods): qué cosa concreta es -- un sobre, un
-- piano, una nevera. Es OPCIONAL a propósito y no obligatorio: hay partidas
-- guardadas de antes de que existiera el catálogo, y una carga sin objeto tiene
-- que seguir valiendo (cae a lo que diga su rareza). La rareza sigue mandando en
-- el VALOR; el objeto manda en el tamaño y en qué vehículo hace falta.
export type Caja = { rareza: string, objeto: string? }

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

-- Tres multiplicadores sobre la base, y cada uno responde a una decisión distinta
-- del jugador: la RAREZA a qué cogió del almacén, la RUTA a por dónde salió, y el
-- TAMAÑO a en qué se ha gastado el dinero -- porque lo grande exige vehículo.
--
-- El del tamaño se añadió midiendo: sin él, lo enorme pagaba 33,6 por hueco y lo
-- pequeño 54,7, o sea que llevar el piano era perder dinero (ver Config.TAMANOS).
function Economy.valorCaja(caja: Caja, multiplicadorRuta: number): number
	local def = Economy.rareza(caja.rareza)
	return math.floor(Config.CAJA_VALOR_BASE * def.multiplicador * multiplicadorRuta * Goods.bono(caja.objeto))
end

function Economy.valorEntrega(cajas: { Caja }, multiplicadorRuta: number): number
	local total = 0
	for _, caja in cajas do
		total += Economy.valorCaja(caja, multiplicadorRuta)
	end
	return total
end

return Economy
