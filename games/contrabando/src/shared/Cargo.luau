--!strict
--[[
	Cargo.luau — peso, capacidad y velocidad. Módulo PURO.

	Que la carga se NOTE es media tensión del juego. Si transportar no cuesta,
	no hay decisión: irías siempre a tope por la ruta que más pague.

	El suelo de velocidad no es un detalle: un jugador clavado en el sitio
	abandona la partida, y eso no es tensión, es un fallo de diseño.
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

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

function Cargo.velocidad(cajas: { Economy.Caja }): number
	local penalizacion = Cargo.pesoTotal(cajas) * Config.PENALIZACION_POR_CAJA
	return math.max(VELOCIDAD_MINIMA, Config.VELOCIDAD_BASE - penalizacion)
end

return Cargo
