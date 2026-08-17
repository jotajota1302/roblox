--!strict
--[[
	Levels.luau — experiencia y nivel. Módulo PURO.

	POR QUÉ EXISTE, y no es por tener otra barra que suba: el dinero se gasta y
	desaparece, así que dos jugadores con la misma cartera pueden llevar uno diez
	minutos y otro diez horas. **El nivel es lo único que no se puede gastar**, y por
	eso es lo único que sirve para saber quién tienes delante.

	Y eso es exactamente lo que le falta al multijugador de este juego: cuando dos
	repartidores se cruzan en una calle no hay forma de saber nada del otro. Con el
	nivel y el vehículo a la vista, cruzarse deja de ser un encuentro con un muñeco
	y pasa a ser información -- ése lleva diez niveles más que yo, o ése acaba de
	empezar y va en patines.

	DE MOMENTO EL NIVEL NO DA VENTAJA MECÁNICA, y es deliberado. Se pidieron cuatro
	estadísticas (defensa, velocidad, destreza, camuflaje) y entra primero el
	estatus a secas: es la mitad del valor por la décima parte del riesgo, y no
	puede desequilibrar nada porque no cambia ninguna regla. Lo demás se decide
	después de ver a dos personas jugando.

	La velocidad por nivel, en concreto, está descartada: chocaría con la regla de
	que nadie puede volverse inalcanzable, que ya obligó a que los ladrones escalen
	con el vehículo del perseguido.
]]

local Levels = {}

-- Cuánta experiencia hace falta para pasar de nivel. Crece, pero MUY despacio al
-- principio: los primeros niveles tienen que caer casi solos para que el jugador
-- nuevo vea el sistema funcionar en su primera sesión, que es cuando decide si
-- vuelve. Si el nivel 2 costara media hora, nadie sabría que existe.
--
-- Con la economía actual (un viaje verde con tres cosas comunes paga ~30, uno
-- rojo con algo bueno pasa de 1.000), el nivel 2 cae en el primer o segundo
-- viaje y el 10 pide bastante rato.
local BASE = 100
local CRECIMIENTO = 1.35

-- Experiencia acumulada necesaria para ESTAR en un nivel dado.
function Levels.xpParaNivel(nivel: number): number
	if nivel <= 1 then
		return 0
	end
	local total = 0
	local escalon = BASE
	for _ = 2, nivel do
		total += escalon
		escalon = math.floor(escalon * CRECIMIENTO)
	end
	return total
end

-- El nivel que corresponde a una experiencia. Sin tope: un jugador que juegue
-- mil horas tiene que seguir subiendo, aunque cada vez más despacio. Un techo
-- convierte al veterano en alguien que ya no gana nada por jugar.
function Levels.nivelDe(xp: number): number
	if xp <= 0 then
		return 1
	end
	local nivel = 1
	-- El tope de 200 no es un techo de juego: es una red contra un xp corrupto que
	-- colgaría el servidor en un bucle infinito.
	while nivel < 200 and xp >= Levels.xpParaNivel(nivel + 1) do
		nivel += 1
	end
	return nivel
end

-- Cuánto falta para el siguiente, en tanto por uno. Es lo que dibuja la barra:
-- ver que queda poco es la mitad del motivo para hacer un viaje más.
function Levels.progreso(xp: number): number
	local nivel = Levels.nivelDe(xp)
	local base = Levels.xpParaNivel(nivel)
	local siguiente = Levels.xpParaNivel(nivel + 1)
	if siguiente <= base then
		return 0
	end
	return math.clamp((xp - base) / (siguiente - base), 0, 1)
end

-- La experiencia que da una entrega. Es el VALOR de lo entregado, no el número de
-- piezas: si contaran las piezas, la jugada óptima sería llenar el zurrón de
-- basura común y hacer viajes cortos, que es justo lo contrario de lo que el
-- juego quiere premiar. Así subir de nivel y ganar dinero apuntan al mismo sitio.
function Levels.xpPorEntrega(valorCobrado: number): number
	return math.max(1, math.floor(valorCobrado * 0.5))
end

return Levels
