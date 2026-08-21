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

	-- Los destinos NOMINALES, tal y como están en Config antes de tocarlos. Hay que
	-- guardarlos porque `sortear` escribe encima: sin esta copia, la segunda prueba
	-- que corriera mediría contra un destino ya sorteado.
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
	-- sin determinismo, "me salió un destino imposible" no se puede volver a mirar.
	local a = Destinations.sortear(12345)
	for _, ruta in Config.RUTAS do
		ruta.destino = nominales[ruta.id]
	end
	local b = Destinations.sortear(12345)
	for id, sitio in a do
		kit.truthy(
			string.format("con la misma semilla, %s sale en el mismo sitio", id),
			(sitio - b[id]).Magnitude < 0.01
		)
	end

	-- Y semillas distintas tienen que poder dar repartos distintos: si siempre
	-- saliera lo mismo, el sorteo sería decorativo y el fallo que arregla seguiría ahí.
	local distintos = false
	for intento = 1, 40 do
		for _, ruta in Config.RUTAS do
			ruta.destino = nominales[ruta.id]
		end
		local otro = Destinations.sortear(intento * 7919)
		for id, sitio in otro do
			if (sitio - a[id]).Magnitude > 0.01 then
				distintos = true
			end
		end
	end
	kit.truthy("con semillas distintas el reparto cambia de verdad", distintos)

	-- Y se deja Config como estaba: este fichero corre dentro de la misma sesión que
	-- el resto de la batería, y dejarlo sorteado haría fallar a las pruebas de mapa
	-- que miden contra los destinos nominales.
	for _, ruta in Config.RUTAS do
		ruta.destino = nominales[ruta.id]
	end
end
