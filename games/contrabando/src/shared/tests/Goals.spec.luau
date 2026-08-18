--!strict
-- Pruebas de los hitos. Lo que se comprueba es que avancen EN ORDEN, que no se
-- cobren dos veces, y que un estado corrupto no abra nada: el primer hito abre la
-- ruta verde, así que es una llave y se trata como tal.

local Goals = require(script.Parent.Parent.Goals)

return function(kit)
	local ninguno: { [string]: boolean } = {}

	-- El primero, de salida.
	local primero = Goals.actual(0, 1, ninguno)
	kit.truthy("hay un hito al empezar", primero ~= nil)
	kit.eq("y es la primera entrega", (primero :: any).id, "primera")
	kit.eq("con su progreso", Goals.progreso(primero :: any, 0, 1), "0 of 1 deliveries")
	kit.eq("que avanza", Goals.progreso(Goals.actual(1, 1, { primera = true }) :: any, 1, 1), "1 of 3 deliveries")

	-- Al cumplirlo aparece, y sólo una vez.
	kit.eq("con 0 entregas no se cumple nada", #Goals.cumplidos(0, 1, nil, ninguno), 0)
	local cumplidos = Goals.cumplidos(1, 1, nil, ninguno)
	kit.eq("con 1 entrega se cumple el primero", #cumplidos, 1)
	kit.eq("y es ese", cumplidos[1].id, "primera")
	kit.eq("ya cobrado, no se vuelve a cumplir", #Goals.cumplidos(1, 1, nil, { primera = true }), 0)

	-- El siguiente pasa a ser el actual.
	kit.eq("el actual avanza", (Goals.actual(1, 1, { primera = true }) :: any).id, "tres")

	-- LAS RUTAS. La verde está cerrada hasta el primer hito.
	kit.falsy("la verde empieza cerrada", Goals.rutaAbierta("verde", ninguno))
	kit.truthy("y se abre con el primer hito", Goals.rutaAbierta("verde", { primera = true }))
	kit.truthy("el barrio esta abierto desde el principio", Goals.rutaAbierta("barrio", ninguno))
	kit.truthy("y las de arriba no dependen de hitos", Goals.rutaAbierta("roja", ninguno))

	-- El de nivel no se cumple por entregar, por muchas que lleves.
	local sinNivel = Goals.cumplidos(99, 1, nil, { primera = true, tres = true })
	local hayAmbar = false
	for _, h in sinNivel do
		if h.id == "ambar" then
			hayAmbar = true
		end
	end
	kit.falsy("el hito de nivel no se cumple entregando", hayAmbar)
	kit.eq("y se cumple al llegar", Goals.cumplidos(99, 3, nil, { primera = true, tres = true })[1].id, "ambar")

	-- El de la roja pide las dos cosas. Y "de motor" en este juego significa
	-- ATADO AL ASFALTO (Roads.exigeCalzada), que es lo que de verdad condiciona la
	-- ruta: la bicicleta cuenta, el monopatín no.
	local casi = { primera = true, tres = true, ambar = true, ocho = true }
	kit.eq("nivel 8 a pie no basta", #Goals.cumplidos(99, 8, nil, casi), 0)
	kit.eq("ni en monopatin", #Goals.cumplidos(99, 8, "monopatin", casi), 0)
	kit.eq("con moto si", #Goals.cumplidos(99, 8, "moto", casi), 1)
	kit.eq("y con bicicleta tambien, que va por calzada", #Goals.cumplidos(99, 8, "bicicleta", casi), 1)

	-- Varios de golpe: quien entrega ocho seguidas se lleva los tres de entregas.
	local golpe = Goals.cumplidos(8, 1, nil, ninguno)
	kit.eq("tres hitos de entregas de una vez", #golpe, 3)
	kit.eq("y en orden", golpe[1].id .. "," .. golpe[3].id, "primera,ocho")

	-- Cuando no queda ninguno, no revienta.
	local todos = { primera = true, tres = true, ambar = true, ocho = true, roja = true }
	kit.eq("sin hitos pendientes no hay actual", Goals.actual(99, 99, todos), nil)

	-- BASURA. Lo que llega del DataStore y del cliente se trata como sospechoso.
	kit.falsy("un hito inventado no abre la verde", Goals.rutaAbierta("verde", { pirata = true }))
	kit.eq("una tabla de hitos que no es tabla no revienta", #Goals.cumplidos(1, 1, nil, nil :: any), 1)
	kit.eq("y se sanea a lo que existe hoy", Goals.sanear({ primera = true, pirata = true }).pirata, nil)
	kit.eq("conservando lo bueno", Goals.sanear({ primera = true, pirata = true }).primera, true)
end
