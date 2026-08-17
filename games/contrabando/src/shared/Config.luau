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

-- Vehículos: el sumidero de dinero, y la regla de diseño innegociable es que la
-- progresión va por CAPACIDAD Y ACCESO, NUNCA POR POTENCIA. Ningún vehículo te
-- hace inatrapable: en el momento en que alguien es inalcanzable, el PvP muere y
-- las rutas rojas pasan a ser dinero gratis.
--
-- Por qué cada vehículo lleva su PROPIA penalización por peso en vez de compartir
-- PENALIZACION_POR_CAJA: con la penalización de ir a pie (1,4 por unidad), una
-- furgoneta cargada con sus 10 cajas caería a 0,4 studs/s y la salvaría el suelo
-- de velocidad -- es decir, iría al mínimo SIEMPRE, con lo que su capacidad no
-- valdría nada y no habría gradiente que decidir. Con 0,45 el recorrido va de
-- 14,4 (vacía) a 9,9 (a tope): siempre por debajo del equivalente a pie, que es
-- lo que exige "capacidad contra exposición", pero con margen real de decisión.
Config.VEHICULOS = {
	{
		id = "a_pie",
		nombre = "A pie",
		capacidad = Config.CAPACIDAD_A_PIE,
		velocidadBase = Config.VELOCIDAD_BASE,
		penalizacionPorPeso = Config.PENALIZACION_POR_CAJA,
		coste = 0,
	},
	{
		id = "furgoneta",
		nombre = "Furgoneta",
		capacidad = 10,
		velocidadBase = Config.VELOCIDAD_BASE * 0.9, -- -10%, como el diseño
		penalizacionPorPeso = 0.45,
		coste = 1500, -- PROTOTIPO: 5000
	},
}

Config.VEHICULO_INICIAL = "a_pie"

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

-- Zona segura alrededor del origen (el almacén se construye ahí, ver WorldBuilder):
-- dentro de este radio no se roba a nadie, ni siquiera en la roja. Sin esto, un
-- ladrón parado en la salida roba a todo el que elige ruta en el instante mismo de
-- elegirla, antes de dar un paso -- no viola "el almacén no es asaltable" a la
-- letra (su contenido sigue intocable), pero rompe el espíritu: la zona de partida
-- tiene que ser segura.
Config.ZONA_SEGURA_RADIO = 150

-- Sonidos. Los efectos NO son decoración: son información. Que suene una alerta al
-- acercarse un perseguidor es la diferencia entre persecución y emboscada injusta.
-- Los ids se rellenan en la Tarea 11 buscándolos en la biblioteca de Roblox.
-- Un id vacío no reproduce nada y no rompe: el juego funciona igual, sólo más mudo.
-- El tipo explícito no es adorno: sin él, indexar con una clave variable
-- (Config.SONIDOS[clave]) es un error de tipo en --!strict.
Config.SONIDOS = {
	cobro = "rbxassetid://1319346243", -- "Money,Coins,Drop In Cash Register" (codes4breakfast)
	robo = "rbxassetid://98330897555423", -- "punch2" (GRISAlLLE)
	alerta = "rbxassetid://9119159511", -- "Siren Blat 2 (SFX)" (ProSoundEffects)
} :: { [string]: string }

-- Anticheat: nadie corre más que esto ni en el mejor de los casos.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40

return Config
