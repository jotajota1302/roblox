--!strict
--[[
	Cargo.luau — peso, capacidad y velocidad. Módulo PURO.

	Que la carga se NOTE es media tensión del juego. Si transportar no cuesta,
	no hay decisión: irías siempre a tope por la ruta que más pague.

	El suelo de velocidad no es un detalle: un jugador clavado en el sitio
	abandona la partida, y eso no es tensión, es un fallo de diseño.
]]

local Economy = require(script.Parent.Economy)
local Goods = require(script.Parent.Goods)
local Vehicles = require(script.Parent.Vehicles)

local VELOCIDAD_MINIMA = 8

local Cargo = {}

-- Lo que ocupa una pieza. Del CATÁLOGO si la pieza es un objeto conocido, y de su
-- rareza si no -- que es el caso de las partidas guardadas antes de que existiera
-- el catálogo. Sin ese respaldo, un jugador que vuelve con carga antigua se
-- encontraría el zurrón calculado a cero y podría meterlo todo.
local function huecosDe(caja: Economy.Caja): number
	if caja.objeto ~= nil then
		return Goods.huecos(caja.objeto)
	end
	return Economy.rareza(caja.rareza).peso
end

function Cargo.pesoTotal(cajas: { Economy.Caja }): number
	local total = 0
	for _, caja in cajas do
		total += huecosDe(caja)
	end
	return total
end

-- Dos condiciones, y la segunda es la regla que puso JJ: **no puedes llevar algo
-- grande sin un vehículo para ello**.
--
-- No es lo mismo que quedarse sin hueco. Un piano NO entra en unos patines por
-- mucho sitio libre que quede, y esa diferencia es justo lo que convierte al
-- vehículo en una llave en vez de en un número: ver mercancía que no puedes tocar
-- es lo que le da destino al dinero.
--
-- Devuelve además el MOTIVO, porque desde dentro "no cabe" y "no puedes con eso"
-- se ven igual --la pieza no se recoge-- y llevan a decisiones opuestas: una dice
-- vacía el zurrón, la otra dice ve a comprarte una moto.
function Cargo.cabe(
	cajas: { Economy.Caja },
	nueva: Economy.Caja,
	capacidad: number,
	vehiculo: string?
): (boolean, string)
	if nueva.objeto ~= nil then
		local def = Vehicles.deEstado(vehiculo)
		if Goods.nivelExigido(nueva.objeto) > (def.tamanoMaximo or 1) then
			return false, "vehiculo_insuficiente"
		end
	end
	if Cargo.pesoTotal(cajas) + huecosDe(nueva) > capacidad then
		return false, "sin_hueco"
	end
	return true, "ok"
end

-- Cuánto puede llevar este jugador. Único sitio del juego que responde a esa
-- pregunta: antes cada servicio leía Config.CAPACIDAD_A_PIE por su cuenta, y el
-- día que apareció un vehículo con otra capacidad eso habría dejado al almacén
-- llenando hasta 3 mientras el zurrón admitía 10.
function Cargo.capacidad(vehiculo: string?): number
	return Vehicles.deEstado(vehiculo).capacidad
end

-- El vehículo cambia las DOS mitades del cálculo: de dónde parte la velocidad y
-- cuánto le quita cada unidad de peso. Ver el porqué en Config.VEHICULOS.
function Cargo.velocidad(cajas: { Economy.Caja }, vehiculo: string?): number
	local def = Vehicles.deEstado(vehiculo)
	local penalizacion = Cargo.pesoTotal(cajas) * def.penalizacionPorPeso
	return math.max(VELOCIDAD_MINIMA, def.velocidadBase - penalizacion)
end

return Cargo
