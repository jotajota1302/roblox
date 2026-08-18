--!strict
--[[
	Skills.luau — las habilidades del repartidor. Módulo PURO.

	POR QUÉ EXISTE. Levels.luau ya decía en su cabecera que se pidieron cuatro
	estadísticas y que entró primero el estatus a secas. Esto es la otra mitad: lo
	que el jugador construye a su gusto, pagado con lo que recoge por el camino.

	LA REGLA QUE MANDA SOBRE TODAS: la progresión va por capacidad y acceso, NUNCA
	por potencia. Por eso aquí no hay habilidad de velocidad ni de inmunidad --
	camuflaje y aguante MITIGAN, el señuelo RETRASA y tiene recarga. Que ninguna
	combinación deje al jugador fuera de alcance está comprobado en la suite, no
	confiado a este comentario.

	Y por eso los efectos son FACTORES sobre un número que ya se calculaba
	(`bulto` del vehículo, fracción robada, alcance del minimapa) en vez de reglas
	nuevas: lo que ya estaba equilibrado se mueve, no se sustituye.
]]

local Skills = {}

export type Habilidades = { [string]: number }

export type Definicion = {
	id: string,
	nombre: string,
	descripcion: string,
	costes: { number },
}

-- Los costes son crecientes y el primero es barato a propósito: el primer peldaño
-- tiene que caer en la primera sesión, que es cuando el jugador decide si vuelve.
-- Con un viaje verde dando ~11 contactos y uno rojo ~31, el primero cae solo.
Skills.CATALOGO = {
	{
		id = "camuflaje",
		nombre = "Camuflaje",
		descripcion = "Las esquinas fichadas te ven desde menos lejos",
		costes = { 20, 60, 150 },
	},
	{
		id = "aguante",
		nombre = "Aguante",
		descripcion = "Pierdes menos carga cuando te alcanzan",
		costes = { 20, 60, 150 },
	},
	{
		id = "vista",
		nombre = "Vista",
		descripcion = "Ves guaridas y ladrones desde más lejos en el mapa",
		costes = { 20, 60, 150 },
	},
	{
		id = "senuelo",
		nombre = "Señuelo",
		descripcion = "Sueltas un cebo: los ladrones van a él y no a ti",
		costes = { 80 },
	},
} :: { Definicion }

local function definicion(id: string): Definicion?
	for _, d in Skills.CATALOGO do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- TODO LO QUE VENGA DE FUERA PASA POR AQUÍ. El DataStore guarda lo que se le dio y
-- un cliente manipulado manda lo que quiere: sin recorte, un `camuflaje = 99`
-- guardado una vez valdría para siempre.
function Skills.normalizar(datos: any): Habilidades
	local salida: Habilidades = {}
	for _, d in Skills.CATALOGO do
		local valor = 0
		if type(datos) == "table" and type(datos[d.id]) == "number" then
			valor = math.clamp(math.floor(datos[d.id]), 0, #d.costes)
		end
		salida[d.id] = valor
	end
	return salida
end

function Skills.coste(habilidades: Habilidades, id: string): number?
	local d = definicion(id)
	if not d then
		return nil
	end
	local actual = habilidades[id] or 0
	if actual >= #d.costes then
		return nil
	end
	return d.costes[actual + 1]
end

-- Devuelve (comprado, motivo, habilidades resultantes, contactos restantes).
-- NUNCA lanza y NUNCA muta lo que recibe: quien llame se queda con lo devuelto, y
-- si no se pudo comprar lo devuelto es lo que ya había.
function Skills.comprar(habilidades: Habilidades, contactos: number, id: string): (boolean, string, Habilidades, number)
	local copia = Skills.normalizar(habilidades)

	local d = definicion(id)
	if not d then
		return false, "Esa habilidad no existe", copia, contactos
	end

	local coste = Skills.coste(copia, id)
	if not coste then
		return false, "Ya está al máximo", copia, contactos
	end
	if contactos < coste then
		return false, "Te faltan contactos", copia, contactos
	end

	copia[id] = (copia[id] or 0) + 1
	return true, "", copia, contactos - coste
end

local function peldano(habilidades: Habilidades, id: string, maximo: number): number
	local valor = habilidades[id]
	if type(valor) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(valor), 0, maximo)
end

-- Cuánto se multiplica el `bulto` del vehículo, o sea desde qué distancia te
-- fichan. Baja, nunca a cero: un repartidor invisible no existe.
function Skills.factorBulto(habilidades: Habilidades): number
	return ({ 1.0, 0.92, 0.84, 0.75 })[peldano(habilidades, "camuflaje", 3) + 1]
end

-- Cuánto se multiplica la fracción de carga que se lleva quien te alcanza. Quien
-- aplique esto DEBE respetar Config.ROBO_FRACCION_MINIMA como suelo.
function Skills.factorRobo(habilidades: Habilidades): number
	return ({ 1.0, 0.9, 0.8, 0.7 })[peldano(habilidades, "aguante", 3) + 1]
end

-- Cuánto se multiplica el alcance del minimapa. Es la única que sube.
function Skills.factorVista(habilidades: Habilidades): number
	return ({ 1.0, 1.25, 1.5, 1.75 })[peldano(habilidades, "vista", 3) + 1]
end

function Skills.tieneSenuelo(habilidades: Habilidades): boolean
	return peldano(habilidades, "senuelo", 1) >= 1
end

return Skills
