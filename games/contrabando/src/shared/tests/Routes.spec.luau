--!strict
local Routes = require(script.Parent.Parent.Routes)

return function(kit)
	-- TRES, y son las tres del codigo de colores del mapa. Eran cuatro hasta el
	-- 20/08: habia una rampa de entrada aparte que el selector llamaba LOCAL, y JJ la
	-- miro y dijo lo que se ve --*"a green amber o red me parecia suficiente"*--. El
	-- mapa promete tres bandas; ofrecer cuatro etiquetas, una sin color, era un
	-- concepto de mas en la primera pantalla. La rampa no se perdio: la verde se mudo
	-- a su cruce.
	--
	-- Se comprueba que esten LAS QUE TIENEN QUE ESTAR y no cuantas: contar deja la
	-- prueba fallando cada vez que se anade una ruta, que es justo cuando menos falta
	-- hace que una prueba grite.
	for _, id in { "verde", "ambar", "roja" } do
		kit.truthy("existe la ruta " .. id, Routes.existe(id))
	end
	kit.falsy("y la rampa de entrada ya no es una ruta aparte", Routes.existe("barrio"))
	kit.eq("la verde paga x1", Routes.get("verde").multiplicador, 1)
	kit.eq("la ambar paga x3", Routes.get("ambar").multiplicador, 3)
	kit.eq("la roja paga x10", Routes.get("roja").multiplicador, 10)

	kit.eq("la verde no tiene pvp", Routes.get("verde").pvp, "ninguno")
	kit.eq("en la ambar solo roban transportistas", Routes.get("ambar").pvp, "transportistas")
	kit.eq("la roja es libre", Routes.get("roja").pvp, "libre")

	-- El escalonado, que es lo que hace que la decisión de ruta sea una decisión.
	-- Se comprueba sobre la distancia CALCULADA desde el almacén: los destinos son
	-- coordenadas de la ciudad, y un dedazo en una de ellas puede dejar la roja más
	-- cerca que la verde sin que nada más se queje.
	kit.truthy("la roja es la mas lejos", Routes.distancia("roja") > Routes.distancia("ambar"))
	kit.truthy("y la ambar mas que la verde", Routes.distancia("ambar") > Routes.distancia("verde"))

	-- Y el mismo escalonado en la vigilancia: pagar diez veces más tiene que costar
	-- algo más que andar un rato, o la roja es dinero gratis para el que tenga
	-- paciencia.
	kit.truthy(
		"cuanto mas paga una zona, mas vigilada esta",
		Routes.get("roja").detectores > Routes.get("ambar").detectores
			and Routes.get("ambar").detectores > Routes.get("verde").detectores
	)
	kit.truthy("y hasta la verde tiene alguno, para aprender", Routes.get("verde").detectores > 0)

	kit.falsy("una ruta inventada no existe", Routes.existe("dorada"))
	kit.errors("y pedirla revienta", function()
		Routes.get("dorada")
	end)

	-- El corazón del anti-exploit: cobrar la roja entregando en el destino verde
	-- (que está a 600 studs en vez de a 2.000) sería dinero gratis.
	kit.truthy("entregar donde elegiste vale", Routes.entregaValida("roja", "roja"))
	kit.falsy("entregar en otro destino no vale", Routes.entregaValida("roja", "verde"))
	kit.falsy("sin haber elegido ruta no vale", Routes.entregaValida(nil, "verde"))

	-- LA LICENCIA. Es lo que arregla el fallo de economía medido el 18/08: el ×10
	-- de la roja era gratis desde el primer minuto mientras el garaje entero
	-- costaba 31.950 monedas para dar un ×2,15.
	kit.eq("la verde se abre desde el principio", select(1, Routes.licencia("verde")), 1)
	kit.truthy("la ambar pide nivel", select(1, Routes.licencia("ambar")) > 1)
	kit.truthy(
		"y la roja pide mas que la ambar",
		select(1, Routes.licencia("roja")) > select(1, Routes.licencia("ambar"))
	)
	kit.falsy("la verde no pide vehiculo", select(2, Routes.licencia("verde")))
	kit.truthy("la roja si", select(2, Routes.licencia("roja")))

	-- EL ORDEN DE LOS REQUISITOS NO PUEDE INVERTIRSE: si una ruta que paga menos
	-- pidiera más nivel, el jugador la saltaría entera y el escalón sobraría.
	local anterior = 0
	for _, ruta in Routes.todas() do
		local nivel = select(1, Routes.licencia(ruta.id))
		kit.truthy(string.format("la %s no pide menos que la anterior", ruta.id), nivel >= anterior)
		anterior = nivel
	end

	-- Y quien no llega, se entera de por qué. Un botón que no responde cuesta la
	-- partida; un motivo la salva.
	kit.truthy("con nivel de sobra se sale por la verde", (Routes.disponible("verde", 1, "a_pie")))
	kit.falsy("un novato no sale por la roja", (Routes.disponible("roja", 1, "moto")))
	kit.eq("y el motivo es el nivel", select(2, Routes.disponible("roja", 1, "moto")), "nivel_insuficiente")
	kit.falsy("ni con nivel pero a pie", (Routes.disponible("roja", 99, "a_pie")))
	kit.eq("y ahi el motivo es el vehiculo", select(2, Routes.disponible("roja", 99, "a_pie")), "necesitas_motor")
	kit.truthy("con nivel y moto, adelante", (Routes.disponible("roja", 99, "moto")))
	kit.falsy("una ruta inventada nunca esta disponible", (Routes.disponible("dorada", 99, "moto")))
	-- El monopatín no es de motor: va por todas partes, y ésa es su gracia.
	kit.falsy("el monopatin no abre la roja", (Routes.disponible("roja", 99, "monopatin")))

	-- LA VERDE, ABIERTA DE SALIDA. Es la ruta con la que se empieza desde que absorbio
	-- la rampa de entrada el 20/08, y esta es la prueba que lo sujeta: una ruta de
	-- entrada cerrada deja al jugador nuevo con el zurron lleno, la valla bajada y
	-- ningun destino que pueda elegir. Antes la abria el primer hito, que era
	-- coherente cuando existia LOCAL por debajo.
	local sinHitos: { [string]: boolean } = {}
	kit.truthy("la verde esta abierta desde el primer segundo", (Routes.disponible("verde", 1, "a_pie", sinHitos)))
	kit.truthy("con hitos hechos, igual", (Routes.disponible("verde", 1, "a_pie", { primera = true })))
	kit.truthy("y sin pasar hitos tampoco cambia", (Routes.disponible("verde", 1, "a_pie")))

	-- LO QUE CIERRA UNA RUTA HOY ES EL NIVEL, no un hito: ningun hito lleva ya `abre`.
	-- El orden --hito antes que nivel-- sigue implementado para la siguiente puerta
	-- que se ponga, pero no se puede ejercitar con los datos de hoy, y una prueba que
	-- afirme lo contrario mentiria.
	kit.eq(
		"a nivel 0 lo que falta es el nivel",
		select(2, Routes.disponible("verde", 0, "a_pie", sinHitos)),
		"nivel_insuficiente"
	)
	kit.eq(
		"la ambar la cierra su nivel",
		select(2, Routes.disponible("ambar", 1, "a_pie", sinHitos)),
		"nivel_insuficiente"
	)

	-- Y el texto de lo que falta sale de la regla, no de un texto a mano.
	kit.eq("de la verde se pide el nivel", Routes.requisitoPara("verde", sinHitos), "Level 1")
	kit.eq("y no cambia por tener hitos", Routes.requisitoPara("verde", { primera = true }), "Level 1")
	kit.eq("y la roja pide sus dos cosas", Routes.requisitoPara("roja", sinHitos), "Level 8 and a road vehicle")

	-- Lo que se lee en el selector sale de la regla, no de un texto a mano.
	kit.truthy("el requisito de la roja menciona el vehiculo", string.find(Routes.requisito("roja"), "vehicle") ~= nil)
	kit.truthy("y el de la ambar solo el nivel", string.find(Routes.requisito("ambar"), "Level") ~= nil)
end
