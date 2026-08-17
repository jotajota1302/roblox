--!strict
local Config = require(script.Parent.Parent.Config)
local Heat = require(script.Parent.Parent.Heat)

return function(kit)
	local AHORA = 1000

	-- Empiezas frío. Es lo único que garantiza que salir del almacén sea gratis.
	local limpio = Heat.nuevo(AHORA)
	kit.eq("se empieza sin calor", limpio.nivel, 0)

	-- Un detector sube uno y lo dice, para que el servidor pueda avisar.
	local tras, subio = Heat.detectar(limpio, "poste_1", AHORA)
	kit.eq("un detector sube un nivel", tras.nivel, 1)
	kit.truthy("y avisa de que ha subido", subio)

	-- EL BLOQUEO, que es la diferencia entre una decisión y una trampa: quedarse
	-- quieto encima de un poste no puede subirte a 3 en dos segundos.
	local repetido, subioOtra = Heat.detectar(tras, "poste_1", AHORA + 1)
	kit.eq("el mismo detector no vuelve a subir de inmediato", repetido.nivel, 1)
	kit.falsy("y no avisa dos veces", subioOtra)

	local pasadoElBloqueo = Heat.detectar(tras, "poste_1", AHORA + Config.DETECTOR_BLOQUEO + 1)
	kit.eq("pasado el bloqueo, el mismo detector vuelve a contar", pasadoElBloqueo.nivel, 2)

	-- Pero OTRO detector sí cuenta al momento: el bloqueo es por poste, no global.
	-- Si fuera global, atravesar una zona sembrada de detectores costaría lo mismo
	-- que rozar uno solo, y la densidad por zona -- que es lo que distingue la roja
	-- de la verde -- no significaría nada.
	local otro = Heat.detectar(tras, "poste_2", AHORA + 1)
	kit.eq("otro detector sube aunque sea el mismo instante", otro.nivel, 2)

	-- El tope. Sin él, media hora de mala suerte deja un número sin sentido y el
	-- juego no tendría con qué decidir cuántas patrullas sacar.
	local caliente = limpio
	for i = 1, 8 do
		caliente = Heat.detectar(caliente, "poste_" .. i, AHORA)
	end
	kit.eq("el calor tiene tope", caliente.nivel, Config.CALOR_MAXIMO)

	-- La válvula de escape. Sin ella la única estrategia sensata es no salir.
	local enfriado = Heat.enfriar(caliente, AHORA + Config.CALOR_SEGUNDOS_POR_NIVEL, false)
	kit.eq("sin vigilancia encima, el calor baja", enfriado.nivel, Config.CALOR_MAXIMO - 1)

	-- Y no baja mientras te están mirando.
	local vigilado = Heat.enfriar(caliente, AHORA + Config.CALOR_SEGUNDOS_POR_NIVEL, true)
	kit.eq("con vigilancia encima no baja", vigilado.nivel, Config.CALOR_MAXIMO)

	-- LA MISMA LECCIÓN QUE COSTÓ EL ALMACÉN: si enfriar marcara el reloj a "ahora"
	-- sin más, un bucle de refresco de 1 s con un periodo de 20 tiraría los 19
	-- restantes en cada muestra y el calor NO BAJARÍA NUNCA. Se comprueba llamando
	-- muchas veces seguidas, que es justo como lo va a llamar el servidor.
	local goteo = caliente
	for t = 1, Config.CALOR_SEGUNDOS_POR_NIVEL do
		goteo = Heat.enfriar(goteo, AHORA + t, false)
	end
	kit.eq("enfriar en muestras cortas tambien baja", goteo.nivel, Config.CALOR_MAXIMO - 1)

	-- Varios periodos de golpe (el jugador estuvo escondido un buen rato).
	local frio = Heat.enfriar(caliente, AHORA + Config.CALOR_SEGUNDOS_POR_NIVEL * 5, false)
	kit.eq("mucho tiempo escondido enfria del todo", frio.nivel, 0)

	-- Y no se pasa de rosca por abajo.
	kit.eq("el calor no baja de cero", Heat.enfriar(frio, AHORA + 10000, false).nivel, 0)

	-- Que te pillen reinicia la cuenta: te ha costado media carga, no vas a seguir
	-- arrastrando las tres estrellas que te la costaron.
	kit.eq("que te pillen enfria del todo", Heat.capturado(caliente).nivel, 0)
	kit.eq("y la zona segura tambien", Heat.aSalvo(caliente).nivel, 0)

	-- El estado de entrada NO se toca. Es lo que hace el módulo probable y lo que
	-- evita que dos servicios que comparten un estado se pisen sin enterarse.
	kit.eq("detectar no muta lo que recibe", limpio.nivel, 0)
	kit.eq("enfriar no muta lo que recibe", caliente.nivel, Config.CALOR_MAXIMO)

	-- Cuánta policía sale, que es para lo único que sirve el número.
	kit.eq("sin calor no hay patrullas", Heat.patrullas(0), 0)
	kit.eq("a tope salen tres", Heat.patrullas(Config.CALOR_MAXIMO), 3)
	kit.truthy(
		"y van mas rapido cuanto mas calor",
		Heat.velocidadPatrulla(3) > Heat.velocidadPatrulla(1) and Heat.velocidadPatrulla(1) > 0
	)

	-- Un nivel imposible no puede reventar el servidor: se recorta al rango.
	kit.eq("un nivel fuera de rango se recorta", Heat.patrullas(99), 3)
	kit.eq("y por abajo tambien", Heat.patrullas(-4), 0)

	-- Lo que te cuesta que te alcancen: la MITAD, redondeando hacia arriba. Con 1
	-- caja pierdes esa; que un alcance salga gratis convertiría la patrulla en un
	-- susto sin consecuencia.
	kit.eq("te quitan la mitad de la carga", Heat.cajasIncautadas(4), 2)
	kit.eq("y con impares redondea hacia arriba", Heat.cajasIncautadas(3), 2)
	kit.eq("con una caja, esa caja", Heat.cajasIncautadas(1), 1)
	kit.eq("sin carga no hay nada que incautar", Heat.cajasIncautadas(0), 0)
end
