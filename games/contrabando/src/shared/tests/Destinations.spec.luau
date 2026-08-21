--!strict
-- Vive en `shared/tests` como el resto de la bateria pura, pero prueba un modulo del
-- SERVIDOR: `Destinations` no toca el mundo --sólo hace cuentas sobre la retícula--
-- así que se puede probar aquí, y merece la pena porque lo que decide es a dónde va
-- el jugador. Un sorteo que se salga de la banda o de la distancia convierte la ruta
-- verde en otra cosa sin que nada avise.
local Config = require(script.Parent.Parent.Config)
local Grid = require(script.Parent.Parent.Grid)
local Perimeter = require(script.Parent.Parent.Perimeter)

return function(kit)
	local Destinations = require(game.ServerScriptService.Server.Destinations)

	-- Los destinos tal y como estan en Config AHORA. En una partida de verdad no son
	-- los de diseno sino los que se sortearon al arrancar, y da igual: de lo que se
	-- parta, lo que se comprueba es que el sorteo respeta la banda y la distancia.
	--
	-- Se pasan a `elegir` en vez de escribirlos: asi cuarenta sorteos seguidos parten
	-- todos del mismo sitio sin que nadie tenga que "restaurar" nada -- y restaurar
	-- era justo donde estaba el fallo.
	local nominales: { [string]: Vector3 } = {}
	for _, ruta in Config.RUTAS do
		nominales[ruta.id] = ruta.destino
	end

	for id, nominal in nominales do
		local opciones = Destinations.candidatos(id, nominal)
		kit.truthy(string.format("la ruta %s tiene al menos un destino", id), #opciones >= 1)

		local fila = Grid.filaDeZona(id)
		local base = (nominal - Config.ALMACEN_POS).Magnitude
		for i, sitio in opciones do
			-- EN SU BANDA. Cada zona es una fila de la retícula, y un destino de la
			-- verde plantado en la banda roja rompería la única cosa que diferencia a
			-- las rutas entre sí.
			kit.truthy(
				string.format("el candidato %d de %s cae en su banda", i, id),
				fila == nil or math.abs(sitio.Z - Grid.zDeCalle(fila)) < 1
			)
			-- FUERA DE CASA. Un destino dentro de la zona segura se entregaría solo,
			-- sin viaje y sin riesgo: la ruta dejaría de existir.
			kit.falsy(
				string.format("el candidato %d de %s no cae en la zona segura", i, id),
				Perimeter.dentro(sitio, Config.ZONA_SEGURA_RADIO)
			)
			-- Y A UNA DISTANCIA PARECIDA. La distancia ES la ruta: lo que separa la
			-- verde de la roja es cuánto se anda y cuánto se cobra, así que un
			-- candidato al otro extremo del mapa convertiría una en la otra sin avisar.
			local d = (sitio - Config.ALMACEN_POS).Magnitude
			kit.truthy(
				string.format("el candidato %d de %s esta a distancia de %s (%.0f contra %.0f)", i, id, id, d, base),
				d >= base * 0.7 and d <= base * 1.35
			)
		end
	end

	-- MISMA SEMILLA, MISMO REPARTO. Es lo que permite reproducir una partida rara:
	-- sin determinismo, "me salio un destino imposible" no se puede volver a mirar.
	--
	-- SE PRUEBA `elegir` Y NUNCA `sortear`, y esa linea es la moraleja de un fallo
	-- caro. `sortear` ESCRIBE en el `Config` del servidor, y esta bateria corre
	-- dentro del servidor de una partida en marcha: la version anterior de esta
	-- prueba sorteaba cuarenta veces y luego "restauraba" los destinos... en su copia
	-- clonada de Config, mientras `sortear` escribia en el real. Correr las pruebas
	-- dejaba la partida con destinos que no eran los del mundo ya construido, y la
	-- sonda del mundo cantaba un rastro roto que estaba perfecto.
	--
	-- `elegir` no escribe nada, asi que esto se puede correr mil veces sin tocar la
	-- partida de nadie.
	local a = Destinations.elegir(12345, nominales)
	local b = Destinations.elegir(12345, nominales)
	for id, sitio in a do
		kit.truthy(
			string.format("con la misma semilla, %s sale en el mismo sitio", id),
			(sitio - b[id]).Magnitude < 0.01
		)
	end

	-- Y semillas distintas tienen que poder dar repartos distintos: si siempre
	-- saliera lo mismo, el sorteo seria decorativo y el fallo que arregla seguiria ahi.
	local distintos = false
	for intento = 1, 40 do
		local otro = Destinations.elegir(intento * 7919, nominales)
		for id, sitio in otro do
			if (sitio - a[id]).Magnitude > 0.01 then
				distintos = true
			end
		end
	end
	kit.truthy("con semillas distintas el reparto cambia de verdad", distintos)

	-- Y NADA DE ESTO HA TOCADO LA PARTIDA. La comprobacion que cierra el circulo:
	-- si algun dia alguien vuelve a poner aqui la version que escribe, esto lo caza.
	for _, ruta in Config.RUTAS do
		kit.truthy(
			string.format("elegir no ha movido el destino de %s", ruta.id),
			(ruta.destino - nominales[ruta.id]).Magnitude < 0.01
		)
	end
end
