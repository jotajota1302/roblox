--!strict
local Routes = require(script.Parent.Parent.Routes)

return function(kit)
	kit.eq("hay tres rutas", #Routes.todas(), 3)
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

	-- LOS HITOS, que son el peldaño de más abajo. Sin ellos la función se comporta
	-- como antes: quien llame sin el parámetro no ve ningún cambio.
	local sinHitos: { [string]: boolean } = {}
	kit.falsy("la verde esta cerrada hasta la primera entrega", (Routes.disponible("verde", 1, "a_pie", sinHitos)))
	kit.eq("y el motivo es el hito", select(2, Routes.disponible("verde", 1, "a_pie", sinHitos)), "hito_pendiente")
	kit.truthy("con el hito hecho, se sale", (Routes.disponible("verde", 1, "a_pie", { primera = true })))
	kit.truthy("sin pasar hitos, todo sigue como antes", (Routes.disponible("verde", 1, "a_pie")))

	-- EL HITO VA PRIMERO: decirle que le falta nivel para una ruta que ni siquiera
	-- ha desbloqueado es mandarle a perseguir lo que no le sirve.
	kit.eq(
		"lo que falta se dice en el orden correcto",
		select(2, Routes.disponible("verde", 0, "a_pie", sinHitos)),
		"hito_pendiente"
	)

	-- Y el texto de lo que falta cambia con lo que ya tienes.
	kit.eq("sin el hito, se pide el hito", Routes.requisitoPara("verde", sinHitos), "Deliver your first package")
	kit.eq("con el hito, se pide el nivel", Routes.requisitoPara("verde", { primera = true }), "Level 1")
	kit.eq("y la roja pide sus dos cosas", Routes.requisitoPara("roja", sinHitos), "Level 8 and a road vehicle")

	-- Lo que se lee en el selector sale de la regla, no de un texto a mano.
	kit.truthy("el requisito de la roja menciona el vehiculo", string.find(Routes.requisito("roja"), "motor") ~= nil)
	kit.truthy("y el de la ambar solo el nivel", string.find(Routes.requisito("ambar"), "Nivel") ~= nil)
end
