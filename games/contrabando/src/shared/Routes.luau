--!strict
--[[
	Routes.luau — las tres rutas y la validación de entrega. Módulo PURO.

	La decisión de ruta es el corazón del juego: cada viaje es una apuesta TUYA,
	no un castigo que te cae encima.

	entregaValida es una pieza de seguridad, no una comodidad: sin ella, elegir la
	roja (x10) y entregar en el destino verde (a 600 studs en vez de a 2.000) sería
	cobrar el premio grande por el viaje corto.
]]

local Config = require(script.Parent.Config)

export type Ruta = {
	id: string,
	multiplicador: number,
	destino: Vector3,
	detectores: number,
	pvp: string,
}

local Routes = {}

-- La distancia deja de ser un dato y pasa a ser una CUENTA. Antes vivía en Config
-- como un número que alguien elegía; con la ciudad de por medio es una
-- consecuencia de dónde cae el destino, y tenerla en dos sitios sería garantizar
-- que un día el selector prometa 400 metros a un sitio que está a 900.
--
-- Es en línea recta, no andando: es una referencia para decidir, no una promesa.
function Routes.distancia(id: string): number
	local ruta = Routes.get(id)
	return (ruta.destino - Config.ALMACEN_POS).Magnitude
end

-- Cuánta policía te vas a encontrar, en palabras. Vive aquí y no en el selector
-- porque es una regla del juego, no una etiqueta: el día que se retoque la
-- densidad de una zona, lo que el jugador lee tiene que cambiar solo. Un selector
-- que promete "vigilancia baja" en la zona más sembrada de detectores es peor que
-- no decir nada.
function Routes.vigilancia(id: string): string
	local n = Routes.get(id).detectores
	if n <= 3 then
		return "vigilancia baja"
	elseif n <= 10 then
		return "vigilancia media"
	end
	return "vigilancia alta"
end

-- Devuelve copias, no la tabla de Config. Con la referencia viva, cualquiera que
-- ordenase, filtrase o retocase el resultado estaría modificando la configuración
-- del juego para todo el servidor -- y un multiplicador cambiado a mitad de
-- partida no deja rastro por ningún lado.
function Routes.todas(): { Ruta }
	local copia: { Ruta } = {}
	for _, ruta in Config.RUTAS do
		table.insert(copia, table.clone(ruta))
	end
	return copia
end

function Routes.existe(id: string?): boolean
	if not id then
		return false
	end
	for _, ruta in Config.RUTAS do
		if ruta.id == id then
			return true
		end
	end
	return false
end

function Routes.get(id: string): Ruta
	for _, ruta in Config.RUTAS do
		if ruta.id == id then
			return ruta
		end
	end
	error("ruta desconocida: " .. tostring(id))
end

function Routes.entregaValida(rutaElegida: string?, rutaDelDestino: string): boolean
	return rutaElegida ~= nil and rutaElegida == rutaDelDestino
end

return Routes
