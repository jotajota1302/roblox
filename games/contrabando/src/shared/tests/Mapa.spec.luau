--!strict
--[[
	Mapa.spec — que los emplazamientos del juego tengan sentido entre sí.

	Existe porque estas coordenadas se han movido A MANO tres veces en un solo día
	--el almacén cambió de sitio dos veces y el taller le siguió-- y un dedazo en
	cualquiera de ellas no da ningún error: el mundo se construye igual, el juego
	arranca igual, y lo único que pasa es que el taller queda dentro del almacén, o
	que la ruta roja resulta estar más cerca que la verde y pagar diez veces más
	por menos camino. Eso no se ve leyendo el diff; se ve jugando media hora.

	Son comprobaciones de RELACIONES, no de valores concretos: no dicen dónde tiene
	que estar cada cosa --eso lo decide el mapa-- sino qué no puede pasar entre
	ellas nunca.
]]

local Config = require(script.Parent.Parent.Config)
local Routes = require(script.Parent.Parent.Routes)

return function(kit)
	-- El taller está pegado al almacén (es su tienda) pero no encima: la losa del
	-- almacén mide 90, así que a menos de 45 quedarían solapadas y el jugador
	-- aparecería dentro de la tienda.
	local alTaller = (Config.TALLER_POS - Config.ALMACEN_POS).Magnitude
	kit.truthy("el taller no se solapa con el almacen", alTaller > 50)
	kit.truthy("pero esta al lado, no en la otra punta", alTaller < 220)

	-- El taller vive DENTRO de la zona segura. Es una promesa del diseño: nadie
	-- puede emboscar a quien está comprando, que es el momento en el que el
	-- jugador está parado, con dinero y sin mirar la pantalla.
	kit.truthy("el taller esta dentro de la zona segura", alTaller <= Config.ZONA_SEGURA_RADIO)

	-- Ningún destino puede caer dentro de la zona segura: ahí no se roba ni se
	-- calienta nadie, así que una ruta que terminase dentro sería dinero gratis.
	for _, ruta in Routes.todas() do
		kit.truthy(
			"el destino " .. ruta.id .. " esta fuera de la zona segura",
			Routes.distancia(ruta.id) > Config.ZONA_SEGURA_RADIO
		)
	end

	-- Pagar más tiene que costar más camino. Sin esto, mover un destino al
	-- rediseñar el mapa puede dejar la roja --que paga x10-- más cerca que la
	-- verde, y entonces no hay ninguna razón para elegir otra cosa.
	local verde, ambar, roja = Routes.distancia("verde"), Routes.distancia("ambar"), Routes.distancia("roja")
	kit.truthy("la ambar esta mas lejos que la verde", ambar > verde)
	kit.truthy("y la roja mas que la ambar", roja > ambar)

	-- Y con margen de verdad: si la roja estuviera un 5 % más lejos que la ámbar,
	-- multiplicaría por diez lo que la otra por tres a cambio de nada. El
	-- escalonado tiene que notarse andando.
	kit.truthy("la roja esta MUCHO mas lejos, no un poco", roja > ambar * 1.4)
	kit.truthy("y la ambar mucho mas que la verde", ambar > verde * 1.4)

	-- Los destinos, separados entre sí: dos a cien studs uno de otro se
	-- confundirían al llegar, y entregar en el equivocado es perder el viaje.
	for _, a in Routes.todas() do
		for _, b in Routes.todas() do
			if a.id < b.id then
				kit.truthy(
					string.format("%s y %s no estan pegados", a.id, b.id),
					(a.destino - b.destino).Magnitude > 250
				)
			end
		end
	end

	-- Cada zona necesita al menos un detector para que su vigilancia signifique
	-- algo, y la verde no puede quedarse en cero: es donde se aprende qué es.
	for _, ruta in Routes.todas() do
		kit.truthy("la ruta " .. ruta.id .. " tiene vigilancia", ruta.detectores > 0)
	end

	-- Y lo que el selector le promete al jugador tiene que coincidir con lo que se
	-- va a encontrar. Es la etiqueta sobre la que decide.
	kit.eq("la verde se anuncia como poco vigilada", Routes.vigilancia("verde"), "vigilancia baja")
	kit.eq("y la roja como muy vigilada", Routes.vigilancia("roja"), "vigilancia alta")
end
