--!strict
--[[
	Rarity.luau — la tirada de rareza. Módulo PURO salvo por Color3, que es un tipo
	de datos sin estado y no impide probarlo.

	Recibe el Random en vez de crearlo dentro: así con semilla fija la tirada es
	determinista y se puede comprobar el reparto de verdad en lugar de confiar.
]]

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Strings = require(script.Parent.Strings)

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

-- QUÉ es cada cosa que llevas, no sólo de qué color es.
--
-- Antes todo era la misma caja de madera marrón, y con eso una legendaria de x135
-- y una común de x1 se veían igual salvo por el tono -- "la caja de madera queda
-- un poco mal, podríamos ver otras cosas para llevar" (JJ). Llevar un cajón o
-- llevar un estuche blindado tiene que notarse en la mano: es la diferencia entre
-- transportar mercancía y transportar ALGO, y de eso vive la tensión de la ruta
-- roja.
--
-- `forma` la interpreta quien dibuja (CargoService a la espalda, Stock en el
-- muelle); aquí sólo se dice qué es cada rareza, para que las dos mitades no
-- tengan cada una su propia idea.
export type Aspecto = {
	forma: string,
	material: Enum.Material,
	-- Proporciones respecto a la pieza base. Un estuche es plano y ancho; un cajón
	-- es un cubo. Que no midan todos igual es la mitad de lo que los distingue de
	-- lejos, antes incluso de leer la etiqueta.
	escala: Vector3,
}

local ASPECTOS: { [string]: Aspecto } = {
	comun = {
		forma = "caja",
		material = Enum.Material.WoodPlanks,
		escala = Vector3.new(1, 1, 1),
	},
	marcada = {
		forma = "maletin",
		material = Enum.Material.Metal,
		escala = Vector3.new(1.15, 0.42, 0.85),
	},
	sellada = {
		forma = "estuche",
		material = Enum.Material.DiamondPlate,
		escala = Vector3.new(1.05, 0.8, 1.05),
	},
	legendaria = {
		forma = "urna",
		material = Enum.Material.Foil,
		escala = Vector3.new(0.85, 1.25, 0.85),
	},
}

function Rarity.aspecto(id: string): Aspecto
	return ASPECTOS[id] or ASPECTOS.comun
end

-- La etiqueta que se lee encima de la pieza: qué es y cuánto multiplica. El
-- multiplicador sale de Economy, no de una copia aquí, porque es el número con el
-- que el jugador decide si le compensa cargar con ello.
function Rarity.etiqueta(id: string): string
	-- Rarity.def LANZA con un id desconocido (delega en Economy.rareza, que hace
	-- error()). Aquí no puede propagarse: esto lo llama el dibujado de una caja, y
	-- una etiqueta mal formada no puede costar la pieza entera -- ni, peor, tumbar
	-- el bucle que dibuja las demás.
	local ok, def = pcall(Rarity.def, id)
	local multiplicador = if ok and def then def.multiplicador else 1
	return Strings.get("GOODS_LABEL", { nombre = Strings.ref("RARITY_" .. id), multiplicador = multiplicador })
end

return Rarity
