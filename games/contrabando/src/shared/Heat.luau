--!strict
--[[
	Heat.luau — el calor: el reloj de tensión del viaje. Módulo PURO.

	Es la pieza que responde al único defecto que importaba del prototipo: el viaje
	estaba vacío. La ruta se elegía una vez al salir y después no volvía a pasar
	nada durante minuto y medio. El calor es lo que hace que pase algo.

	La regla que lo mantiene siendo un juego y no un impuesto está repartida entre
	tres decisiones de aquí, y las tres son igual de necesarias:

	  · SUBE POR LO QUE HACES. Rozar un detector, no un dado invisible.
	  · CADA DETECTOR TIENE SU PROPIO BLOQUEO. Sin él, quedarse quieto encima de un
	    poste sube al máximo en dos segundos. Con un bloqueo global en vez de uno
	    por poste, cruzar una zona sembrada costaría lo mismo que rozar uno solo, y
	    la densidad por zona -- que es lo único que distingue la roja de la verde --
	    dejaría de significar nada.
	  · BAJA SOLO. Es la válvula de escape. Sin ella la única estrategia sensata es
	    no salir del almacén, y entonces no hay juego que medir.

	Nada aquí toca la API de Roblox: se prueba entero en milisegundos.
]]

local Config = require(script.Parent.Config)

export type Estado = {
	nivel: number,
	-- Instante del último nivel consumido por enfriamiento. NO es "la última vez
	-- que se llamó a enfriar": ver la nota de enfriar().
	ultimoDescenso: number,
	-- id de detector -> instante en que se disparó contra este jugador.
	disparos: { [string]: number },
}

local Heat = {}

local function copia(estado: Estado): Estado
	return {
		nivel = estado.nivel,
		ultimoDescenso = estado.ultimoDescenso,
		disparos = table.clone(estado.disparos),
	}
end

function Heat.nuevo(ahora: number): Estado
	return { nivel = 0, ultimoDescenso = ahora, disparos = {} }
end

-- Devuelve el estado nuevo y SI HA SUBIDO, para que quien llame decida si avisa.
-- Ese segundo valor no es una comodidad: sin él, el servidor tendría que comparar
-- niveles para saber si merece la pena mandar un aviso, y compararía mal en el
-- caso que más importa -- rozar un detector estando ya al máximo, donde el nivel
-- no cambia pero el jugador sí necesita saber que le han visto.
function Heat.detectar(estado: Estado, detectorId: string, ahora: number): (Estado, boolean)
	local ultimo = estado.disparos[detectorId]
	if ultimo ~= nil and ahora - ultimo < Config.DETECTOR_BLOQUEO then
		return estado, false
	end

	local nuevo = copia(estado)
	-- El disparo se registra SIEMPRE, incluso al máximo. Si sólo se registrara
	-- cuando sube, un jugador ya a tope recibiría el aviso de ese mismo poste en
	-- cada muestra del bucle de proximidad: varias veces por segundo, para siempre.
	nuevo.disparos[detectorId] = ahora

	if estado.nivel >= Config.CALOR_MAXIMO then
		return nuevo, false
	end

	nuevo.nivel = estado.nivel + 1
	return nuevo, true
end

-- `hayVigilancia` es "tienes un detector o una patrulla encima ahora mismo": el
-- reloj sólo corre cuando de verdad te has escondido.
--
-- CONSUME LOS PERIODOS QUE DE VERDAD BAJARON, no marca el reloj a `ahora`. Es la
-- misma lección que ya costó el almacén (ver Warehouse.avanzar): con un periodo de
-- 20 s y un bucle de refresco de 1 s, marcar el reloj a `ahora` en cada muestra
-- tira los 19 segundos restantes una y otra vez, y el calor NO BAJA NUNCA. El
-- fallo no da la cara en ninguna prueba que llame a la función una sola vez.
-- `periodo` permite enfriar más rápido en sitios concretos (los refugios). Es
-- opcional y por defecto vale el de la intemperie, así que quien no sepa de
-- refugios sigue llamando igual que siempre.
function Heat.enfriar(estado: Estado, ahora: number, hayVigilancia: boolean, periodo: number?): Estado
	if estado.nivel <= 0 then
		if estado.ultimoDescenso == ahora then
			return estado
		end
		local nuevo = copia(estado)
		nuevo.nivel = 0
		nuevo.ultimoDescenso = ahora
		return nuevo
	end

	if hayVigilancia then
		-- Te están mirando: el reloj se reinicia entero. Esconderse diez segundos,
		-- asomarse y volver a esconderse no puede acumular progreso.
		local nuevo = copia(estado)
		nuevo.ultimoDescenso = ahora
		return nuevo
	end

	local paso = periodo or Config.CALOR_SEGUNDOS_POR_NIVEL
	local transcurridos = math.floor((ahora - estado.ultimoDescenso) / paso)
	if transcurridos <= 0 then
		return estado
	end

	local bajada = math.min(transcurridos, estado.nivel)
	local nuevo = copia(estado)
	nuevo.nivel = estado.nivel - bajada
	nuevo.ultimoDescenso = estado.ultimoDescenso + bajada * paso
	return nuevo
end

-- Que te pillen reinicia la cuenta. Ya te ha costado media carga; arrastrar además
-- las tres estrellas que te la costaron es castigar dos veces lo mismo, y el
-- segundo castigo cae justo cuando el jugador está decidiendo si sigue jugando.
function Heat.capturado(estado: Estado): Estado
	local nuevo = copia(estado)
	nuevo.nivel = 0
	nuevo.disparos = {}
	return nuevo
end

-- La zona segura del almacén limpia igual. Es la promesa que hace jugable el juego
-- en solitario: siempre hay un sitio donde se acaba lo que te esté pasando.
function Heat.aSalvo(estado: Estado): Estado
	return Heat.capturado(estado)
end

local function recortar(nivel: number): number
	return math.clamp(math.floor(nivel), 0, Config.CALOR_MAXIMO)
end

-- Un nivel imposible no puede tumbar el servidor. No es paranoia: este número va a
-- llegar aquí desde un estado guardado en la nube que puede ser de otra versión
-- del juego, con otro máximo.
function Heat.patrullas(nivel: number): number
	return Config.PATRULLAS[recortar(nivel)].cantidad
end

function Heat.velocidadPatrulla(nivel: number): number
	return Config.PATRULLAS[recortar(nivel)].velocidad
end

-- Lo que te cuesta que te alcancen. Redondea HACIA ARRIBA a propósito: con una
-- sola caja encima, redondear hacia abajo dejaría el alcance en un susto gratis, y
-- una patrulla que no puede quitarte nada deja de ser un motivo para correr.
function Heat.cajasIncautadas(cuantas: number): number
	if cuantas <= 0 then
		return 0
	end
	return math.min(cuantas, math.ceil(cuantas * Config.PATRULLA_FRACCION))
end

return Heat
