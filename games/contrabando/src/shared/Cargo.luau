--!strict
--[[
	Cargo.luau — peso, capacidad y velocidad. Módulo PURO.

	Que la carga se NOTE es media tensión del juego. Si transportar no cuesta,
	no hay decisión: irías siempre a tope por la ruta que más pague.

	El suelo de velocidad no es un detalle: un jugador clavado en el sitio
	abandona la partida, y eso no es tensión, es un fallo de diseño.
]]

local Economy = require(script.Parent.Economy)
local Vehicles = require(script.Parent.Vehicles)

local VELOCIDAD_MINIMA = 8

local Cargo = {}

function Cargo.pesoTotal(cajas: { Economy.Caja }): number
	local total = 0
	for _, caja in cajas do
		total += Economy.rareza(caja.rareza).peso
	end
	return total
end

function Cargo.cabe(cajas: { Economy.Caja }, nueva: Economy.Caja, capacidad: number): boolean
	return Cargo.pesoTotal(cajas) + Economy.rareza(nueva.rareza).peso <= capacidad
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
