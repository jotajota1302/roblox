--!strict
local Warehouse = require(script.Parent.Parent.Warehouse)

return function(kit)
	local RITMO, TOPE = 30, 10

	kit.eq("recien visitado no hay nada", Warehouse.acumulado(0, 1000, 1000, RITMO, TOPE), 0)
	kit.eq("a medio ritmo aun no hay caja", Warehouse.acumulado(0, 1000, 1015, RITMO, TOPE), 0)
	kit.eq("un ritmo entero da una caja", Warehouse.acumulado(0, 1000, 1030, RITMO, TOPE), 1)
	kit.eq("cinco ritmos dan cinco", Warehouse.acumulado(0, 1000, 1150, RITMO, TOPE), 5)

	-- El tope es la razón de volver: al llenarse DEJA de producir, así que no
	-- entrar es desperdiciar tiempo.
	kit.eq("el tope corta la produccion", Warehouse.acumulado(0, 1000, 100000, RITMO, TOPE), TOPE)
	kit.eq("lo ya guardado cuenta para el tope", Warehouse.acumulado(8, 1000, 100000, RITMO, TOPE), TOPE)
	kit.eq("suma sobre lo guardado", Warehouse.acumulado(3, 1000, 1090, RITMO, TOPE), 6)

	-- Dos semanas fuera y dos minutos fuera acaban igual: el tope no simula nada.
	kit.eq(
		"dos semanas equivalen al tope",
		Warehouse.acumulado(0, 0, 14 * 24 * 3600, RITMO, TOPE),
		Warehouse.acumulado(0, 0, 3600, RITMO, TOPE)
	)

	-- Un reloj que va hacia atrás (cambio de hora, dato corrupto) no puede dar negativo.
	kit.eq("el tiempo hacia atras no resta", Warehouse.acumulado(4, 2000, 1000, RITMO, TOPE), 4)

	kit.truthy("lleno cuando llega al tope", Warehouse.lleno(10, TOPE))
	kit.falsy("no lleno por debajo", Warehouse.lleno(9, TOPE))

	kit.eq("faltan 30 s justo despues de visitar", Warehouse.segundosParaLaSiguiente(1000, 1000, RITMO), 30)
	kit.eq("faltan 10 s a los veinte", Warehouse.segundosParaLaSiguiente(1000, 1020, RITMO), 10)
end
