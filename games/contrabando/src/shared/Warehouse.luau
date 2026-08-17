--!strict
--[[
	Warehouse.luau — producción con tope. Módulo PURO.

	No simula NADA. No hay procesos en segundo plano ni temporizadores: al entrar se
	hace una resta y ya está. Da exactamente igual que el jugador estuviera fuera
	diez minutos o dos semanas, y el coste de tener mil jugadores desconectados es cero.

		cajas = min( tope, guardadas + floor( (ahora - ultimaVisita) / ritmo ) )

	El tope es lo que da motivo para volver: al llenarse deja de producir, así que no
	entrar es desperdiciar tiempo. Ampliar la capacidad alarga tu ventana de ausencia,
	de modo que la cadencia de retorno crece con el jugador en vez de agobiarle igual
	desde el primer día.
]]

local Warehouse = {}

function Warehouse.acumulado(
	guardadas: number,
	ultimaVisita: number,
	ahora: number,
	ritmo: number,
	tope: number
): number
	-- Un reloj hacia atrás (cambio de hora, dato corrupto) nunca puede quitar cajas.
	local transcurrido = math.max(0, ahora - ultimaVisita)
	local producidas = math.floor(transcurrido / ritmo)
	return math.min(tope, guardadas + producidas)
end

function Warehouse.lleno(cantidad: number, tope: number): boolean
	return cantidad >= tope
end

-- Igual que acumulado(), pero además devuelve el nuevo reloj (ultimaVisita). Existe
-- porque acumulado() por sí sola no basta para un muestreo periódico: si el llamador
-- avanza el reloj hasta `ahora` en cada muestra, el resto de la división se tira cada
-- vez y, con un refresco más corto que el ritmo, el contador no llega NUNCA al
-- siguiente múltiplo. Sólo se consumen los periodos que de verdad dieron caja.
function Warehouse.avanzar(
	guardadas: number,
	ultimaVisita: number,
	ahora: number,
	ritmo: number,
	tope: number
): (number, number)
	local cajas = Warehouse.acumulado(guardadas, ultimaVisita, ahora, ritmo, tope)
	if cajas >= tope then
		-- Lleno: deja de producir, y el reloj se pone a cero para que al gastar
		-- cajas empiece a contar desde ahora.
		return cajas, ahora
	end
	local transcurrido = math.max(0, ahora - ultimaVisita)
	local producidas = math.floor(transcurrido / ritmo)
	return cajas, ultimaVisita + producidas * ritmo
end

function Warehouse.segundosParaLaSiguiente(ultimaVisita: number, ahora: number, ritmo: number): number
	local transcurrido = math.max(0, ahora - ultimaVisita)
	return ritmo - (transcurrido % ritmo)
end

return Warehouse
