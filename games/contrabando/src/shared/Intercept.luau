--!strict
--[[
	Intercept.luau — las reglas del robo. Módulo PURO.

	Devuelve además un MOTIVO junto al veredicto: cuando alguien reporte que "le
	robaron y no debería", el motivo dice exactamente qué regla se aplicó. Sin eso,
	depurar un sistema que ocurre entre dos jugadores en movimiento es adivinar.

	Reglas por ruta:
	  · verde  -> nadie roba. Es la promesa que hace jugable el juego en solitario
	  · ambar  -> sólo roba quien TAMBIÉN lleva carga: el cazador debe arriesgar
	  · roja   -> cualquiera, incluso alguien que salga del almacén vacío sólo a por ti
]]

local Cargo = require(script.Parent.Cargo)
local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Routes = require(script.Parent.Routes)

export type Perfil = {
	cajas: { Economy.Caja },
	ruta: string?,
	marcadoHasta: number,
	velocidad: number,
	-- Distancia de este jugador al origen (donde se construye el almacén). Opcional
	-- y sólo se usa como perfil de VÍCTIMA: Intercept es un módulo puro y no conoce
	-- posiciones del mundo, así que quien arma el perfil (InterceptService) es
	-- quien mide la distancia real y se la pasa aquí. nil significa "no se sabe /
	-- no aplica" y no activa la zona segura -- así los perfiles de prueba que no la
	-- rellenan (o el del atacante, que no la necesita) siguen funcionando igual.
	distanciaOrigen: number?,
}

local Intercept = {}

function Intercept.puedeRobar(atacante: Perfil, victima: Perfil, distancia: number, ahora: number): (boolean, string)
	if distancia > Config.ROBO_DISTANCIA then
		return false, "lejos"
	end
	-- Zona segura: nadie roba cerca del origen, ni siquiera en la roja. Antes de
	-- cualquier otro motivo porque es una garantía espacial ("la zona de partida es
	-- segura"), no una condición del estado de la víctima.
	if victima.distanciaOrigen ~= nil and victima.distanciaOrigen <= Config.ZONA_SEGURA_RADIO then
		return false, "zona_segura"
	end
	if #victima.cajas == 0 then
		return false, "victima_sin_carga"
	end
	if victima.ruta == nil or not Routes.existe(victima.ruta) then
		return false, "victima_no_en_ruta"
	end
	if atacante.marcadoHasta > ahora then
		return false, "marcado"
	end
	-- Ante una anomalía se invalida el robo en vez de expulsar: más suave con los
	-- falsos positivos (lag, caídas del servidor) y le quita el beneficio igual.
	if atacante.velocidad > Config.VELOCIDAD_MAXIMA_PLAUSIBLE then
		return false, "velocidad_imposible"
	end

	local pvp = Routes.get(victima.ruta).pvp
	if pvp == "ninguno" then
		return false, "ruta_sin_pvp"
	end
	if pvp == "transportistas" and #atacante.cajas == 0 then
		return false, "cazador_sin_carga"
	end

	return true, "ok"
end

-- Redondea hacia ARRIBA para que robar a alguien con una sola caja sirva de algo,
-- pero nunca se lleva todo el botín de un zurrón grande: quedarse a cero es
-- exactamente lo que hace abandonar el juego.
function Intercept.reparto(cajas: { Economy.Caja }, fraccion: number): ({ Economy.Caja }, { Economy.Caja })
	local cuantas = math.ceil(#cajas * fraccion)
	local robadas: { Economy.Caja } = {}
	local restantes: { Economy.Caja } = {}

	for i, caja in cajas do
		if i <= cuantas then
			table.insert(robadas, caja)
		else
			table.insert(restantes, caja)
		end
	end

	return robadas, restantes
end

-- Igual que Intercept.reparto, pero limitado por lo que le cabe al ladrón. Las
-- candidatas de reparto() son siempre un PREFIJO de `cajas`; aquí se prueban en
-- ese mismo orden y se para en la primera que no cabe, así que lo robado sigue
-- siendo un prefijo y "quitarle a la víctima justo lo robado" es una simple resta
-- de longitud. Lo que no cabe se queda con la víctima: robar transfiere carga,
-- nunca la destruye — y un ladrón que sale cargado se lleva menos, lo que hace de
-- ir vacío una decisión real.
function Intercept.repartoConCapacidad(
	cajas: { Economy.Caja },
	fraccion: number,
	cajasAtacante: { Economy.Caja },
	capacidad: number
): ({ Economy.Caja }, { Economy.Caja })
	local candidatas = Intercept.reparto(cajas, fraccion)
	local simuladas = table.clone(cajasAtacante)
	local robadas: { Economy.Caja } = {}

	for _, caja in candidatas do
		if not Cargo.cabe(simuladas, caja, capacidad) then
			break
		end
		table.insert(simuladas, caja)
		table.insert(robadas, caja)
	end

	local restantes: { Economy.Caja } = {}
	for i, caja in cajas do
		if i > #robadas then
			table.insert(restantes, caja)
		end
	end

	return robadas, restantes
end

-- ¿Hay que avisar a la víctima de que este jugador se le acerca? Se resuelve con las
-- MISMAS reglas del robo, pasando distancia 0 para saltarse sólo el filtro de
-- alcance: si alguien no podría robarte, avisar de que viene sería asustar por nada.
function Intercept.esAmenaza(atacante: Perfil, victima: Perfil, distancia: number, ahora: number): boolean
	if distancia > Config.ALERTA_DISTANCIA then
		return false
	end
	local puede = Intercept.puedeRobar(atacante, victima, 0, ahora)
	return puede
end

return Intercept
