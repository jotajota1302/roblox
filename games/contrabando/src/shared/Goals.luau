--!strict
--[[
	Goals.luau — los hitos: qué toca hacer ahora y qué se gana. Módulo PURO.

	POR QUÉ EXISTE. Dos agujeros, y los tapa el mismo sitio:

	  · **el primer minuto no pagaba**. La primera recompensa llegaba a los ~100 s
	    (medido), y en el juego que inspiró esta tanda llega a los 3;
	  · **nadie sabía qué se esperaba de él**. La licencia por nivel existe desde
	    el 18/08, pero sólo se descubría chocando contra ella: pulsabas la ámbar y
	    te decía que no. Un requisito que sólo se conoce al fallar no es una meta,
	    es un muro.

	LOS DE ABAJO CUENTAN ENTREGAS, NO NIVEL, y es deliberado: el nivel sube con el
	dinero cobrado, así que su ritmo depende de qué llevabas encima. Con nivel, uno
	con suerte en el sorteo de rarezas saltaría dos peldaños en su primer viaje y
	otro se quedaría atascado haciendo exactamente lo mismo. Las entregas miden lo
	que el jugador HACE.

	Y `abre` es una LLAVE de verdad: la ruta verde no existe hasta el primer hito.
	Por eso quien la usa para decidir es el servidor, nunca el selector.
]]

local Config = require(script.Parent.Config)
local Roads = require(script.Parent.Roads)

export type Hito = {
	id: string,
	texto: string,
	entregas: number?,
	nivel: number?,
	exigeMotor: boolean?,
	monedas: number?,
	abre: string?,
}

local Goals = {}

-- QUÉ CUENTA COMO "DE MOTOR" no se decide aquí: se le pregunta a Roads, que es
-- quien ya lo responde para la ruta roja (`Routes.disponible` llama a
-- `Roads.exigeCalzada`). Copiar la regla habría dejado dos definiciones que
-- coinciden hoy y el día que cambie una, el hito y la licencia dirían cosas
-- distintas sobre el mismo vehículo.
--
-- Y sí, incluye la bicicleta y el patinete eléctrico: en este juego "de motor"
-- significa atado al asfalto, que es lo que de verdad condiciona la ruta.
local function esDeMotor(vehiculo: string?): boolean
	return Roads.exigeCalzada(vehiculo)
end

-- TODO LO QUE VENGA DE FUERA PASA POR AQUÍ. `hitos` llega del DataStore y viaja
-- al cliente: una clave guardada que hoy no existe no puede abrir una ruta, y una
-- inventada tampoco.
function Goals.sanear(datos: any): { [string]: boolean }
	local salida: { [string]: boolean } = {}
	if type(datos) ~= "table" then
		return salida
	end
	for _, hito in Config.HITOS do
		if datos[hito.id] == true then
			salida[hito.id] = true
		end
	end
	return salida
end

local function cumple(hito: Hito, entregas: number, nivel: number, vehiculo: string?): boolean
	if hito.entregas and entregas < hito.entregas then
		return false
	end
	if hito.nivel and nivel < hito.nivel then
		return false
	end
	if hito.exigeMotor and not esDeMotor(vehiculo) then
		return false
	end
	return true
end

-- El hito actual: el primero de la lista que aún no se ha cobrado. Devuelve nil
-- cuando no queda ninguno -- quien lo pinte tiene que poder seguir sin él.
function Goals.actual(entregas: number, nivel: number, hitos: any): Hito?
	local hechos = Goals.sanear(hitos)
	for _, hito in Config.HITOS do
		if not hechos[hito.id] then
			return hito
		end
	end
	return nil
end

-- Los que se acaban de cumplir y todavía no se han cobrado, EN ORDEN. Devuelve
-- varios a propósito: quien entrega ocho de una sentada se lleva los tres hitos de
-- entregas, y pagarle sólo el último sería quedarse con su dinero.
function Goals.cumplidos(entregas: number, nivel: number, vehiculo: string?, hitos: any): { Hito }
	local hechos = Goals.sanear(hitos)
	local salida: { Hito } = {}
	for _, hito in Config.HITOS do
		if not hechos[hito.id] and cumple(hito, entregas, nivel, vehiculo) then
			table.insert(salida, hito)
		end
	end
	return salida
end

-- ¿Está abierta esta ruta? Una ruta que ningún hito abre está abierta: la
-- escalera sólo añade peldaños por debajo, no cierra lo que ya existía.
function Goals.rutaAbierta(rutaId: string, hitos: any): boolean
	local hechos = Goals.sanear(hitos)
	for _, hito in Config.HITOS do
		if hito.abre == rutaId then
			return hechos[hito.id] == true
		end
	end
	return true
end

-- El hito que abre una ruta, para poder decir QUÉ falta en vez de un "no puedes".
function Goals.hitoQueAbre(rutaId: string): Hito?
	for _, hito in Config.HITOS do
		if hito.abre == rutaId then
			return hito
		end
	end
	return nil
end

-- "1 de 3 entregas" o "nivel 2 de 3". Lo que se enseña debajo del objetivo: sin
-- progreso, un objetivo es una orden; con progreso, es una cuenta atrás.
function Goals.progreso(hito: Hito, entregas: number, nivel: number): string
	if hito.entregas then
		return string.format("%d of %d deliveries", math.min(entregas, hito.entregas), hito.entregas)
	end
	if hito.nivel then
		return string.format("level %d of %d", math.min(nivel, hito.nivel), hito.nivel)
	end
	return ""
end

return Goals
