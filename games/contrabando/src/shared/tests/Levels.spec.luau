--!strict
local Levels = require(script.Parent.Parent.Levels)

return function(kit)
	-- Se empieza en 1, no en 0. Un jugador nuevo tiene un nivel, no la ausencia de
	-- uno: "nivel 0" se lee como que el sistema aún no ha arrancado.
	kit.eq("se empieza en el nivel 1", Levels.nivelDe(0), 1)
	kit.eq("y con xp negativa tambien", Levels.nivelDe(-500), 1)
	kit.eq("el nivel 1 no cuesta nada", Levels.xpParaNivel(1), 0)

	-- LOS PRIMEROS NIVELES CAEN CASI SOLOS, y es lo que decide si el jugador nuevo
	-- llega a saber que el sistema existe. Un viaje verde flojo paga ~30 y da ~15
	-- de experiencia; el nivel 2 tiene que estar a un par de viajes, no a media
	-- hora.
	kit.truthy("el nivel 2 esta cerca", Levels.xpParaNivel(2) <= 120)
	kit.truthy("pero no es gratis", Levels.xpParaNivel(2) > 0)

	-- Y cada nivel cuesta más que el anterior: sin eso, el décimo se alcanza en el
	-- mismo tiempo que el segundo y la progresión deja de significar nada.
	local anterior = 0
	for n = 2, 12 do
		local escalon = Levels.xpParaNivel(n) - Levels.xpParaNivel(n - 1)
		kit.truthy("el nivel " .. n .. " cuesta mas que el anterior", escalon > anterior)
		anterior = escalon
	end

	-- La cuenta tiene que ser coherente en las dos direcciones: si estás justo en
	-- el umbral de un nivel, ése es tu nivel.
	for n = 1, 15 do
		kit.eq("con el xp justo del nivel " .. n .. " estas en el " .. n, Levels.nivelDe(Levels.xpParaNivel(n)), n)
		kit.eq("y con uno menos, en el anterior", Levels.nivelDe(Levels.xpParaNivel(n + 1) - 1), n)
	end

	-- SIN TOPE DE JUEGO: quien juegue mil horas tiene que seguir subiendo, aunque
	-- sea despacio. Un techo convierte al veterano en alguien que ya no gana nada.
	kit.truthy("con mucha experiencia se sube mucho", Levels.nivelDe(50000000) > 20)

	-- Pero un dato corrupto no puede colgar el servidor en un bucle infinito.
	kit.truthy("un xp absurdo no cuelga nada", Levels.nivelDe(1e18) <= 200)

	-- La barra de progreso.
	kit.near("recien subido, la barra esta a cero", Levels.progreso(Levels.xpParaNivel(3)), 0)
	kit.truthy("a mitad de camino, por el medio", Levels.progreso(Levels.xpParaNivel(3) + 40) > 0)
	for _, xp in { 0, 50, 500, 5000, 100000 } do
		local p = Levels.progreso(xp)
		kit.truthy("la barra nunca se sale de rango (" .. xp .. ")", p >= 0 and p <= 1)
	end

	-- LA EXPERIENCIA SALE DEL VALOR, no del número de piezas. Si contaran las
	-- piezas, la jugada óptima sería llenar el zurrón de basura común y hacer
	-- viajes cortos -- justo lo contrario de lo que el juego premia. Así subir de
	-- nivel y ganar dinero apuntan al mismo sitio.
	kit.truthy("entregar mas valor da mas experiencia", Levels.xpPorEntrega(1000) > Levels.xpPorEntrega(100))
	kit.truthy("una entrega minima da algo", Levels.xpPorEntrega(1) >= 1)
	kit.truthy("y una entrega de cero no da negativo", Levels.xpPorEntrega(0) >= 0)
end
