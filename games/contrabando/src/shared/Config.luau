--!strict
--[[
	Config.luau — todas las constantes del juego en un único sitio. Sin lógica.

	Las marcadas con PROTOTIPO: difieren a propósito de DISENO.md para
	poder medir en una sesión lo que en producción tardaría horas. Revertirlas antes
	de publicar.
]]

local Config = {}

-- Economía
Config.CAJA_VALOR_BASE = 10
Config.DINERO_INICIAL = 0

-- Carga a pie
Config.CAPACIDAD_A_PIE = 3
Config.VELOCIDAD_BASE = 16
Config.PENALIZACION_POR_CAJA = 1.4 -- studs/s menos por unidad de peso transportada

-- Rarezas: multiplicador de valor, peso que ocupa y probabilidad.
-- El peso de la legendaria es exactamente CAPACIDAD_A_PIE: cabe, pero te ocupa todo.
Config.RAREZAS = {
	{ id = "comun", multiplicador = 1, peso = 1, probabilidad = 0.70 }, -- PROTOTIPO: 0.90
	{ id = "marcada", multiplicador = 10, peso = 1, probabilidad = 0.20 }, -- PROTOTIPO: 0.08
	{ id = "sellada", multiplicador = 50, peso = 2, probabilidad = 0.08 }, -- PROTOTIPO: 0.018
	{ id = "legendaria", multiplicador = 135, peso = 3, probabilidad = 0.02 }, -- PROTOTIPO: 0.002
}

-- Rutas. Se definen por DISTANCIA, no por tiempo: el tiempo es consecuencia de la
-- velocidad y de lo que lleves encima.
Config.RUTAS = {
	{ id = "verde", multiplicador = 1, distancia = 600, pvp = "ninguno" },
	{ id = "ambar", multiplicador = 3, distancia = 1200, pvp = "transportistas" },
	{ id = "roja", multiplicador = 10, distancia = 2000, pvp = "libre" },
}

-- Almacén
Config.ALMACEN_RITMO = 30 -- PROTOTIPO: 180 (1 caja cada 3 min)
Config.ALMACEN_TOPE = 10

-- Intercepción
Config.ROBO_DISTANCIA = 5 -- studs
Config.ALERTA_DISTANCIA = 60 -- a esta distancia ya se avisa: "te vienen detrás"
Config.ROBO_FRACCION = 0.30
Config.MARCADO_SEGUNDOS = 60
Config.INTERCEPT_HZ = 5

-- Sonidos. Los efectos NO son decoración: son información. Que suene una alerta al
-- acercarse un perseguidor es la diferencia entre persecución y emboscada injusta.
-- Los ids se rellenan en la Tarea 11 buscándolos en la biblioteca de Roblox.
-- Un id vacío no reproduce nada y no rompe: el juego funciona igual, sólo más mudo.
-- El tipo explícito no es adorno: sin él, indexar con una clave variable
-- (Config.SONIDOS[clave]) es un error de tipo en --!strict.
Config.SONIDOS = {
	cobro = "",
	robo = "",
	alerta = "",
} :: { [string]: string }

-- Anticheat: nadie corre más que esto ni en el mejor de los casos.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40

return Config
