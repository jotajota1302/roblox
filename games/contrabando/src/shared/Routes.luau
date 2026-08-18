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
local Goals = require(script.Parent.Goals)
local Roads = require(script.Parent.Roads)

export type Ruta = {
	id: string,
	multiplicador: number,
	destino: Vector3,
	detectores: number,
	pvp: string,
	nivel: number?,
	exigeMotor: boolean?,
	-- Cuántas guaridas le tocan. nil = las de siempre; 0 = ninguna, que es lo que
	-- pide el barrio: ahí el peligro se enseña, no se aplica.
	guaridas: number?,
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
		return "poco peligrosa"
	elseif n <= 10 then
		return "peligrosa"
	end
	return "muy peligrosa"
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

-- LA LICENCIA: qué hace falta para poder salir por esta ruta.
--
-- Existe porque el ×10 de la roja era gratis. Medido: el garaje entero cuesta
-- 31.950 monedas y da un ×2,15, mientras cambiar de ruta multiplica por diez sin
-- pagar nada -- el sumidero competía contra una palanca gratuita y perdía, y el
-- juego se agotaba en menos de una hora. Con licencia, lo que más paga está
-- DETRÁS de haber jugado y de haber invertido, que es donde tenía que estar.
--
-- Y no rompe la regla de oro (nadie inatrapable): esto es ACCESO, no potencia.
-- Nadie corre más por tener licencia.
function Routes.licencia(id: string): (number, boolean)
	local ruta = Routes.get(id)
	return ruta.nivel or 1, ruta.exigeMotor == true
end

-- ¿Puede este jugador salir por esta ruta? Devuelve el motivo junto al veredicto,
-- igual que Vehicles.puedeComprar: cuando alguien diga "le doy y no pasa nada",
-- el motivo dice qué regla se aplicó. Un botón que no responde cuesta la partida
-- entera; una línea de texto la salva.
function Routes.disponible(id: string, nivel: number, vehiculoId: string?, hitos: any): (boolean, string)
	if not Routes.existe(id) then
		return false, "ruta_desconocida"
	end
	-- EL HITO VA PRIMERO porque es el peldaño de más abajo: no tiene sentido decirle
	-- a alguien que le falta nivel para una ruta que todavía no ha desbloqueado.
	--
	-- El parámetro es opcional para no romper a quien llame sin él, pero
	-- RouteService SÍ lo pasa, y ése es el que decide. Sin hitos, se comporta como
	-- antes: sólo nivel y vehículo.
	if hitos ~= nil and not Goals.rutaAbierta(id, hitos) then
		return false, "hito_pendiente"
	end
	local nivelPedido, exigeMotor = Routes.licencia(id)
	if nivel < nivelPedido then
		return false, "nivel_insuficiente"
	end
	-- "De motor" es exactamente lo mismo que "no puede salirse del asfalto": no se
	-- inventa una segunda taxonomía de vehículos, porque dos listas de lo mismo
	-- acaban discrepando y entonces el juego dice una cosa y hace otra.
	if exigeMotor and not Roads.exigeCalzada(vehiculoId) then
		return false, "necesitas_motor"
	end
	return true, "ok"
end

-- Lo que le falta al jugador para esta ruta, en palabras. Vive aquí y no en el
-- selector por lo mismo que Routes.vigilancia: es una regla del juego, no una
-- etiqueta, y el día que se toque el nivel pedido lo que se lee tiene que cambiar
-- solo.
function Routes.requisito(id: string): string
	-- Si lo que falta es el hito, se dice el HITO y no el nivel: "Nivel 1" a alguien
	-- que ya tiene nivel 1 es una puerta cerrada sin explicación, que es
	-- exactamente el fallo que este texto vino a arreglar.
	local hito = Goals.hitoQueAbre(id)
	if hito then
		return hito.texto
	end
	local nivel, motor = Routes.licencia(id)
	if motor then
		return string.format("Nivel %d y vehículo de motor", nivel)
	end
	return string.format("Nivel %d", nivel)
end

-- Igual que requisito, pero sabiendo lo que el jugador YA tiene: una vez cumplido
-- el hito, lo que falta vuelve a ser el nivel. Sin esto, la verde diría "entrega
-- tu primer paquete" para siempre.
function Routes.requisitoPara(id: string, hitos: any): string
	if hitos ~= nil and not Goals.rutaAbierta(id, hitos) then
		local hito = Goals.hitoQueAbre(id)
		if hito then
			return hito.texto
		end
	end
	local nivel, motor = Routes.licencia(id)
	if motor then
		return string.format("Nivel %d y vehículo de motor", nivel)
	end
	return string.format("Nivel %d", nivel)
end

-- Lo que te vas a encontrar por el camino, en números. Vive aquí y no en el
-- selector por lo mismo que Routes.vigilancia: es una regla del juego, no una
-- etiqueta. El día que una zona cambie de densidad, lo que el jugador lee cambia
-- solo -- y un selector que promete "poco peligrosa" en la zona más sembrada es
-- peor que no decir nada.
function Routes.amenazas(id: string): (number, number)
	local ruta = Routes.get(id)
	return ruta.detectores, ruta.guaridas or Config.GUARIDAS_POR_RUTA
end

function Routes.entregaValida(rutaElegida: string?, rutaDelDestino: string): boolean
	return rutaElegida ~= nil and rutaElegida == rutaDelDestino
end

return Routes
