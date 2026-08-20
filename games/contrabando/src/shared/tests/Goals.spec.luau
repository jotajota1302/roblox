--!strict
-- Pruebas de los hitos. Lo que se comprueba es que avancen EN ORDEN, que no se
-- cobren dos veces, y que un estado corrupto no abra nada: el primer hito abre la
-- ruta verde, así que es una llave y se trata como tal.

local Config = require(script.Parent.Parent.Config)
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

	-- LAS RUTAS. La verde esta abierta desde el primer segundo desde que absorbio la
	-- rampa de entrada el 20/08: es la ruta con la que se empieza, y una ruta de
	-- entrada cerrada deja al jugador nuevo con el zurron lleno y ningun destino que
	-- elegir. Antes la abria el primer hito, que era coherente cuando existia LOCAL
	-- por debajo.
	kit.truthy("la verde esta abierta desde el principio", Goals.rutaAbierta("verde", ninguno))
	kit.truthy("y las de arriba no dependen de hitos", Goals.rutaAbierta("roja", ninguno))

	-- LA RUTA QUE SE PONE SOLA EN EL PRIMER REPARTO tiene que poder recorrerse en el
	-- primer segundo de la partida. Es un regalo al que acaba de entrar, y un regalo
	-- que resulta ser una puerta cerrada --por hito o por licencia-- seria peor que
	-- no regalar nada: el juego le pondria un destino y acto seguido le diria que no
	-- puede ir. Se comprueba aqui y no se fia al comentario de Config.
	local Routes = require(script.Parent.Parent.Routes)
	kit.truthy("la ruta del primer reparto existe", Routes.existe(Config.RUTA_PRIMERA))
	kit.truthy("y esta abierta sin ningun hito", Goals.rutaAbierta(Config.RUTA_PRIMERA, ninguno))
	local puedeNovato = Routes.disponible(Config.RUTA_PRIMERA, 1, nil, ninguno)
	kit.truthy("y un novato a pie y de nivel 1 puede salir por ella", puedeNovato)

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
	-- HOY NINGUN HITO CIERRA NINGUNA RUTA: lo que cierra la ambar y la roja es el
	-- NIVEL, y la verde esta abierta de salida. El mecanismo `abre` sigue en pie para
	-- la siguiente que lo necesite, y por eso se comprueba que la basura no lo active
	-- al reves -- inventarse un hito no puede abrir ni cerrar nada.
	for _, id in { "verde", "ambar", "roja" } do
		kit.truthy("ningun hito cierra la " .. id, Goals.rutaAbierta(id, ninguno))
		kit.truthy("y un hito inventado tampoco la toca: " .. id, Goals.rutaAbierta(id, { pirata = true }))
	end
	kit.eq("una tabla de hitos que no es tabla no revienta", #Goals.cumplidos(1, 1, nil, nil :: any), 1)
	kit.eq("y se sanea a lo que existe hoy", Goals.sanear({ primera = true, pirata = true }).pirata, nil)
	kit.eq("conservando lo bueno", Goals.sanear({ primera = true, pirata = true }).primera, true)
end
