--!strict
--[[
	Vehicles.luau — el catálogo de vehículos y las reglas de compra. Módulo PURO.

	Existe porque el dinero necesitaba servir para algo. Sin sumidero, el bucle se
	queda en dos pasos de cinco (produces, cobras) y el número del HUD deja de
	significar nada al tercer viaje: no hay ninguna razón para preferir la ruta
	roja a la verde si lo que ganas no compra nada.

	"A pie" es un vehículo más, no un caso especial. Tratarlo como uno de la lista
	evita el `if vehiculo == nil then ... end` repartido por seis ficheros, que es
	exactamente donde se cuelan las diferencias silenciosas entre servicios.
]]

local Config = require(script.Parent.Config)
local Strings = require(script.Parent.Strings)

export type Vehiculo = {
	id: string,
	capacidad: number,
	velocidadBase: number,
	penalizacionPorPeso: number,
	coste: number,
	nivel: number?,
	expone: number?,
	bulto: number?,
}

local Vehicles = {}

Vehicles.A_PIE = Config.VEHICULO_INICIAL

-- El nombre NO se guarda en el catálogo: se deriva del id. Tenerlo en Config y
-- en Strings serían dos sitios donde escribir texto, y dos sitios es exactamente
-- como se colaron los nueve castellanos que sobrevivieron a la traducción.
function Vehicles.nombre(id: string?): string
	return Strings.get("RIDE_" .. tostring(id))
end

function Vehicles.existe(id: string?): boolean
	if typeof(id) ~= "string" then
		return false
	end
	for _, def in Config.VEHICULOS do
		if def.id == id then
			return true
		end
	end
	return false
end

-- Revienta ante un id desconocido, igual que Economy.rareza: si el servidor
-- recibe un vehículo inventado, dar capacidad de más es mucho peor que cortar.
function Vehicles.get(id: string): Vehiculo
	for _, def in Config.VEHICULOS do
		if def.id == id then
			return def
		end
	end
	error("vehiculo desconocido: " .. tostring(id))
end

-- El estado de un jugador guarda `vehiculo` como string?, donde nil significa "a
-- pie". Esta función es el único sitio donde ese nil se traduce, y así ningún
-- servicio tiene que acordarse de hacerlo.
function Vehicles.deEstado(vehiculo: string?): Vehiculo
	if vehiculo == nil or not Vehicles.existe(vehiculo) then
		return Vehicles.get(Vehicles.A_PIE)
	end
	return Vehicles.get(vehiculo :: string)
end

-- EL GARAJE: lo que ya tienes. Antes el jugador tenía UN vehículo y comprar
-- sustituía al anterior; ahora se acumulan, y elegir cuál sacas es una decisión.
--
-- POR QUÉ CAMBIÓ: tener varios no significaba nada mientras un vehículo sólo
-- fuera "más capacidad" -- el último era siempre el mejor y el anterior, basura.
-- Con la regla de la calzada (ver Roads.luau) dejó de ser así: el patinete entra
-- en cualquier callejón y la furgoneta lleva un piano pero va por donde va todo
-- el mundo. Ya no hay un "mejor": hay un mejor PARA ESTE VIAJE.
function Vehicles.posee(garaje: { string }?, id: string?): boolean
	if id == nil or id == Vehicles.A_PIE then
		-- Ir a pie no se compra ni se pierde: siempre lo tienes.
		return true
	end
	for _, tuyo in garaje or {} do
		if tuyo == id then
			return true
		end
	end
	return false
end

-- El garaje con el que entra un jugador, saneado. Acepta además el `vehiculo`
-- suelto de las partidas ANTERIORES al garaje: quien guardó una furgoneta cuando
-- sólo se guardaba una, la recupera igual. Sin esto, estrenar el garaje habría
-- dejado a pie a todo el que ya jugaba.
function Vehicles.garajeDe(garaje: { string }?, vehiculoSuelto: string?): { string }
	local lista: { string } = {}
	local function meter(id: string?)
		if id == nil or not Vehicles.existe(id) then
			return
		end
		if id == Vehicles.A_PIE or Vehicles.posee(lista, id) then
			return
		end
		table.insert(lista, id :: string)
	end
	for _, id in garaje or {} do
		meter(id)
	end
	meter(vehiculoSuelto)
	return lista
end

-- El nivel mínimo para comprarlo. Uno por defecto: un vehículo sin nivel escrito
-- es comprable desde el principio, que es lo que se espera de un catálogo al que
-- alguien añada una línea sin leer esto.
function Vehicles.nivelDe(id: string): number
	if not Vehicles.existe(id) then
		return 1
	end
	return (Vehicles.get(id) :: any).nivel or 1
end

-- EL EJE DE EXPOSICIÓN, en dos funciones. Los valores por defecto son los de ir a
-- pie --lo pierdes todo, te ven a la distancia normal-- porque es lo que tiene que
-- pasar con un vehículo al que se le olvide ponerle los números: nunca una ventaja
-- silenciosa.
function Vehicles.expone(id: string?): number
	local def = Vehicles.deEstado(id)
	return (def :: any).expone or 1
end

function Vehicles.bulto(id: string?): number
	local def = Vehicles.deEstado(id)
	return (def :: any).bulto or 1
end

-- ¿Puede este jugador comprar este vehículo? Devuelve el motivo junto al
-- veredicto, igual que Intercept.puedeRobar: cuando alguien diga "le he dado a
-- comprar y no pasa nada", el motivo dice qué regla se aplicó.
function Vehicles.puedeComprar(garaje: { string }?, id: string, dinero: number, nivel: number?): (boolean, string)
	if not Vehicles.existe(id) then
		return false, "vehiculo_desconocido"
	end
	local def = Vehicles.get(id)
	if def.coste <= 0 then
		return false, "no_esta_a_la_venta"
	end
	if Vehicles.posee(garaje, id) then
		return false, "ya_lo_tienes"
	end
	-- EL NIVEL VA ANTES QUE EL DINERO al comprobar, y el orden importa: el motivo
	-- que se devuelve es el que ve el jugador, y "te falta nivel" explica algo que
	-- puede arreglar jugando. "No te llega el dinero" cuando además le falta nivel
	-- le manda a hacer viajes para nada.
	--
	-- `nivel` es opcional para no romper a quien todavía llame sin él: sin nivel se
	-- comporta como antes. Los servicios SÍ lo pasan.
	if nivel ~= nil and nivel < Vehicles.nivelDe(id) then
		return false, "nivel_insuficiente"
	end
	-- YA NO SE PROHÍBE COMPRAR "HACIA ABAJO". Esa regla existía para que nadie
	-- gastase dinero en algo estrictamente peor; con el garaje no hay peor, y un
	-- patinete comprado teniendo furgoneta es la llave de los atajos.
	if dinero < def.coste then
		return false, "sin_dinero"
	end
	return true, "ok"
end

-- ¿Puede sacar del garaje este vehículo?
function Vehicles.puedeSacar(garaje: { string }?, id: string?): (boolean, string)
	if id == nil or id == Vehicles.A_PIE then
		-- Volver a ir a pie siempre vale: es la forma de dejar el coche y no es una
		-- compra, así que no se comprueba nada.
		return true, "ok"
	end
	if not Vehicles.existe(id) then
		return false, "vehiculo_desconocido"
	end
	if not Vehicles.posee(garaje, id) then
		return false, "no_es_tuyo"
	end
	return true, "ok"
end

-- Lo que se ofrece en el taller: lo que todavía no tienes, de lo barato a lo
-- caro. Que la lista dependa del estado evita que el cliente decida qué mostrar,
-- y el cliente no decide nada en este juego.
--
-- LOS BLOQUEADOS POR NIVEL TAMBIÉN SALEN, marcados. Un escaparate que esconde lo
-- que aún no puedes comprar no enseña a dónde vas: ver la furgoneta con un
-- "Nivel 10" encima es la mitad del motivo para seguir jugando.
function Vehicles.mejorasPara(garaje: { string }?, nivel: number?): { Vehiculo }
	local mejoras: { Vehiculo } = {}
	for _, def in Config.VEHICULOS do
		if def.coste > 0 and not Vehicles.posee(garaje, def.id) then
			-- Copia, no la tabla de Config: lo que sale de aquí viaja al cliente y lo
			-- tocan otros módulos. Devolver la referencia viva significa que
			-- cualquiera que la modifique está cambiando la configuración del juego
			-- para todo el servidor, y ese fallo no deja rastro.
			local copia = table.clone(def) :: any
			copia.bloqueado = nivel ~= nil and nivel < Vehicles.nivelDe(def.id)
			table.insert(mejoras, copia)
		end
	end
	table.sort(mejoras, function(a, b)
		return a.coste < b.coste
	end)
	return mejoras
end

return Vehicles
