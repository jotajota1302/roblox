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

	kit.truthy("la roja es la mas larga", Routes.get("roja").distancia > Routes.get("ambar").distancia)

	kit.falsy("una ruta inventada no existe", Routes.existe("dorada"))
	kit.errors("y pedirla revienta", function()
		Routes.get("dorada")
	end)

	-- El corazón del anti-exploit: cobrar la roja entregando en el destino verde
	-- (que está a 600 studs en vez de a 2.000) sería dinero gratis.
	kit.truthy("entregar donde elegiste vale", Routes.entregaValida("roja", "roja"))
	kit.falsy("entregar en otro destino no vale", Routes.entregaValida("roja", "verde"))
	kit.falsy("sin haber elegido ruta no vale", Routes.entregaValida(nil, "verde"))
end
