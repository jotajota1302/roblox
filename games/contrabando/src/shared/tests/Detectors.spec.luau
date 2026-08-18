--!strict
local Config = require(script.Parent.Parent.Config)
local Detectors = require(script.Parent.Parent.Detectors)
local Routes = require(script.Parent.Parent.Routes)

return function(kit)
	local origen = Config.ALMACEN_POS

	-- LA PRUEBA QUE FALTABA. Se recorrió la ruta roja entera midiendo y el calor
	-- acabó en CERO: dieciocho detectores repartidos por el barrio con desvíos de
	-- hasta 200 studs y un radio de 35, así que ninguno llegaba a dispararse. Sin
	-- calor no hay ladrones y el viaje vuelve a ser un paseo -- exactamente lo que
	-- el sistema entero existe para evitar.
	--
	-- Esto lo mide: ir en línea recta tiene que costar vigilancia en las TRES
	-- rutas, y más cuanto más paga la zona.
	for _, ruta in Routes.todas() do
		local sitios = Detectors.sitios(origen, ruta.destino, ruta.detectores)
		kit.eq("la ruta " .. ruta.id .. " siembra lo que dice", #sitios, ruta.detectores)

		local tocados = Detectors.disparadosEnLineaRecta(origen, ruta.destino, sitios)
		kit.truthy(
			"en la " .. ruta.id .. " ir en linea recta dispara al menos la mitad (" .. tocados .. ")",
			tocados >= math.floor(ruta.detectores / 2)
		)
		kit.truthy("y en la " .. ruta.id .. " salta al menos uno", tocados >= 1)

		-- Pero NO todos: si el camino corto los disparara todos, esquivar dejaría
		-- de existir como idea y la ruta segura no significaría nada.
		kit.truthy(
			"y en la " .. ruta.id .. " esquivar sigue teniendo premio",
			tocados < ruta.detectores or ruta.detectores <= 3
		)

		-- Ninguno dentro de la zona segura: ahí el calor se apaga en cada muestra,
		-- así que sería un poste decorativo.
		for i, sitio in sitios do
			local d = (Vector3.new(sitio.posicion.X, 0, sitio.posicion.Z) - Vector3.new(origen.X, 0, origen.Z)).Magnitude
			kit.truthy(
				string.format("el detector %d de la %s cae fuera de la zona segura", i, ruta.id),
				d > Config.ZONA_SEGURA_RADIO
			)
		end
	end

	-- Las dos familias, en la proporción que hace que el sistema signifique algo.
	local sitios = Detectors.sitios(origen, Routes.get("roja").destino, 18)
	local dentro = 0
	for _, s in sitios do
		if s.enElCorredor then
			dentro += 1
		end
	end
	kit.eq("la mitad van pegados al camino", dentro, 9)

	-- Y los del corredor están, de verdad, dentro del radio de detección desde la
	-- línea: es lo único que garantiza que ir recto cueste algo.
	local destino = Routes.get("roja").destino
	for i, s in sitios do
		if s.enElCorredor then
			local mejor = 1e9
			for k = 0, 400 do
				local p = origen:Lerp(destino, k / 400)
				local dx, dz = p.X - s.posicion.X, p.Z - s.posicion.Z
				mejor = math.min(mejor, math.sqrt(dx * dx + dz * dz))
			end
			kit.truthy(
				string.format("el detector %d roza el camino (%.0f studs)", i, mejor),
				mejor <= Config.DETECTOR_RADIO
			)
		end
	end

	-- Casos límite: cero detectores y origen igual a destino no pueden reventar la
	-- construcción del mundo.
	kit.eq("cero detectores no siembra nada", #Detectors.sitios(origen, destino, 0), 0)
	kit.eq("origen y destino iguales no revientan", #Detectors.sitios(origen, origen, 3), 3)
end
