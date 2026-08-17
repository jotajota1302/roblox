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

	-- C1: la prueba que habria cazado el bug del almacen que nunca produce con el
	-- jugador conectado. WarehouseService muestreaba cada 5 s con un ritmo de 30, y
	-- si cada muestra avanzaba el reloj hasta `ahora` (en vez de sólo los periodos
	-- que de verdad dieron caja), floor(5/30) = 0 SIEMPRE: el resto se tiraba en
	-- cada muestra y el contador no llegaba nunca al ritmo completo. avanzar() debe
	-- dar el mismo resultado tanto si se consulta una sola vez a los 30 s como si se
	-- muestrea cada 5 s durante esos mismos 30 s.
	do
		-- El reloj real ("ahora") avanza 5 en 5 de forma independiente; ultimaVisita
		-- es lo que avanzar() devuelve y NO tiene por qué crecer en cada muestra (si
		-- no se completó un ritmo, se queda igual). Calcular "ahora" a partir de la
		-- ultimaVisita devuelta (en vez de un reloj real aparte) es precisamente el
		-- error que se quiere cazar: con eso el reloj nunca avanzaría de verdad.
		local cajas, ultimaVisita = 0, 1000
		local ahora = 1000
		for _ = 1, 6 do
			ahora += 5
			cajas, ultimaVisita = Warehouse.avanzar(cajas, ultimaVisita, ahora, RITMO, TOPE)
		end
		kit.eq(
			"muestrear cada 5s durante 30s produce lo mismo que mirar una vez a los 30s",
			cajas,
			Warehouse.acumulado(0, 1000, 1030, RITMO, TOPE)
		)
		kit.eq("y esa cifra es una caja", cajas, 1)
	end

	-- Doce muestras de 5 s (60 s reales) deben dar dos cajas, no cero: confirma que
	-- el resto no se pierde muestra tras muestra a lo largo de varios ritmos.
	do
		local cajas, ultimaVisita = 0, 2000
		local ahora = 2000
		for _ = 1, 12 do
			ahora += 5
			cajas, ultimaVisita = Warehouse.avanzar(cajas, ultimaVisita, ahora, RITMO, TOPE)
		end
		kit.eq("doce muestras de 5s (60s) dan dos cajas", cajas, 2)
	end

	-- Al llenarse, avanzar() pone el reloj a `ahora` (no sigue acumulando resto);
	-- por debajo del tope, sólo avanza los periodos consumidos y el resto se queda
	-- pendiente para la siguiente consulta.
	do
		local cajas, visita = Warehouse.avanzar(TOPE - 1, 1000, 100000, RITMO, TOPE)
		kit.eq("al llenar, el reloj se pone a ahora", visita, 100000)
		kit.eq("y las cajas llegan al tope", cajas, TOPE)

		local cajasParcial, visitaParcial = Warehouse.avanzar(0, 1000, 1037, RITMO, TOPE)
		kit.eq("por debajo del ritmo siguiente, cajas no sube", cajasParcial, 1)
		kit.eq("y el reloj sólo avanza lo consumido, no hasta ahora", visitaParcial, 1030)
	end
end
