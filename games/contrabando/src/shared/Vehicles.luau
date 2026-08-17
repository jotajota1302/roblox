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

export type Vehiculo = {
	id: string,
	nombre: string,
	capacidad: number,
	velocidadBase: number,
	penalizacionPorPeso: number,
	coste: number,
}

local Vehicles = {}

Vehicles.A_PIE = Config.VEHICULO_INICIAL

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

-- ¿Puede este jugador comprar este vehículo? Devuelve el motivo junto al
-- veredicto, igual que Intercept.puedeRobar: cuando alguien diga "le he dado a
-- comprar y no pasa nada", el motivo dice qué regla se aplicó.
function Vehicles.puedeComprar(vehiculoActual: string?, id: string, dinero: number): (boolean, string)
	if not Vehicles.existe(id) then
		return false, "vehiculo_desconocido"
	end
	local def = Vehicles.get(id)
	if def.coste <= 0 then
		return false, "no_esta_a_la_venta"
	end
	local actual = Vehicles.deEstado(vehiculoActual)
	if actual.id == def.id then
		return false, "ya_lo_tienes"
	end
	-- Comprar hacia abajo no está prohibido por capricho: sin esta regla, comprar
	-- un vehículo peor por dinero sería un botón que sólo puede perjudicarte, y
	-- alguien lo pulsaría.
	if def.capacidad <= actual.capacidad then
		return false, "ya_tienes_uno_mejor"
	end
	if dinero < def.coste then
		return false, "sin_dinero"
	end
	return true, "ok"
end

-- Lo que se ofrece en el taller a un jugador concreto: sólo lo que sería una
-- mejora. Que la lista dependa del estado evita que el cliente tenga que decidir
-- qué mostrar, y el cliente no decide nada en este juego.
function Vehicles.mejorasPara(vehiculoActual: string?): { Vehiculo }
	local actual = Vehicles.deEstado(vehiculoActual)
	local mejoras: { Vehiculo } = {}
	for _, def in Config.VEHICULOS do
		if def.coste > 0 and def.capacidad > actual.capacidad then
			-- Copia, no la tabla de Config: lo que sale de aquí viaja al cliente y
			-- lo tocan otros módulos. Devolver la referencia viva significa que
			-- cualquiera que la modifique está modificando la configuración del
			-- juego para todo el servidor, y ese fallo no deja rastro.
			table.insert(mejoras, table.clone(def))
		end
	end
	return mejoras
end

return Vehicles
