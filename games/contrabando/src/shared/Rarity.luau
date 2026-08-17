--!strict
--[[
	Rarity.luau — la tirada de rareza. Módulo PURO salvo por Color3, que es un tipo
	de datos sin estado y no impide probarlo.

	Recibe el Random en vez de crearlo dentro: así con semilla fija la tirada es
	determinista y se puede comprobar el reparto de verdad en lugar de confiar.
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local COLORES = {
	comun = Color3.fromRGB(150, 130, 100),
	marcada = Color3.fromRGB(90, 160, 220),
	sellada = Color3.fromRGB(170, 110, 220),
	legendaria = Color3.fromRGB(255, 200, 60),
}

local Rarity = {}

-- Delega en Economy en vez de repetir la búsqueda: dos funciones que resuelven la
-- misma tabla acaban divergiendo, y la que divergiera aquí pagaría de más.
function Rarity.def(id: string)
	return Economy.rareza(id)
end

function Rarity.tirada(rng: Random): string
	local tirada = rng:NextNumber()
	local acumulado = 0
	for _, def in Config.RAREZAS do
		acumulado += def.probabilidad
		if tirada <= acumulado then
			return def.id
		end
	end
	-- Red de seguridad por si las probabilidades no suman exactamente 1 por
	-- redondeo: devolver la última es infinitamente mejor que devolver nil.
	return Config.RAREZAS[#Config.RAREZAS].id
end

function Rarity.color(id: string): Color3
	return COLORES[id] or Color3.fromRGB(200, 200, 200)
end

function Rarity.esLlamativa(id: string): boolean
	return id == "sellada" or id == "legendaria"
end

return Rarity
