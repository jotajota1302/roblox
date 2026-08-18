--!strict
local Config = require(script.Parent.Parent.Config)
local Lairs = require(script.Parent.Parent.Lairs)
local Shelter = require(script.Parent.Parent.Shelter)

return function(kit)
	local origen = Vector3.new(0, 20, 0)
	local destino = Vector3.new(1000, 20, 0)

	local guaridas = Lairs.sitiosDeRuta(origen, destino, Config.GUARIDAS_POR_RUTA)
	kit.eq("salen las guaridas pedidas", #guaridas, Config.GUARIDAS_POR_RUTA)

	-- NI EN LA PUERTA DE CASA NI ENCIMA DEL DESTINO. Una guarida junto al almacén
	-- sería un peligro en la zona segura; otra pegada al destino es que te quiten
	-- la carga cuando el viaje ya estaba hecho, que no se lee como riesgo sino como
	-- tomadura de pelo.
	for i, g in guaridas do
		local avance = (g.X - origen.X) / (destino.X - origen.X)
		kit.truthy(string.format("la guarida %d esta en el tramo central", i), avance > 0.15 and avance < 0.9)
	end

	-- SE APARTAN DEL CAMINO, pero poco: tienen que estorbar. Si estuvieran lejos,
	-- rodearlas no costaría nada y dejarían de significar algo.
	for i, g in guaridas do
		kit.eq(string.format("la guarida %d se aparta lo previsto", i), math.abs(g.Z), Config.GUARIDA_DESVIO)
	end
	kit.truthy(
		"y se apartan menos que los refugios, que hay que poder alcanzarlos",
		Config.GUARIDA_DESVIO < Config.REFUGIO_DESVIO
	)

	-- Y AL LADO CONTRARIO DEL PRIMER REFUGIO: si las dos cosas cayeran del mismo
	-- lado, esconderse obligaría a meterse en la boca del lobo.
	local refugios = Shelter.sitiosDeRuta(origen, destino, 1)
	if #refugios > 0 and #guaridas > 0 then
		kit.truthy("la primera guarida cae al otro lado que el primer refugio", guaridas[1].Z * refugios[1].Z < 0)
	end

	-- La más cercana, que es la que decide de dónde sale el ladrón.
	local cerca, distancia =
		Lairs.masCercana(Vector3.new(0, 20, 0), { Vector3.new(300, 20, 0), Vector3.new(90, 20, 0) })
	kit.eq("elige la mas cercana", cerca, Vector3.new(90, 20, 0))
	kit.near("y dice a que distancia", distancia, 90, 0.01)
	kit.eq("sin guaridas no hay ninguna cerca", (Lairs.masCercana(origen, {})), nil)

	-- LA VENTANA, que tiene dos bordes y los dos importan. Demasiado cerca es una
	-- emboscada que no se puede esquivar; demasiado lejos es un adorno que llega
	-- cuando el viaje ya ha terminado.
	kit.falsy("una guarida encima no vale", Lairs.sirve(10, 90))
	kit.truthy("una a media distancia si", Lairs.sirve(150, 90))
	kit.falsy("una al otro lado del mapa no", Lairs.sirve(Config.GUARIDA_ALCANCE + 1, 90))
	kit.truthy("justo en el borde de alcance vale", Lairs.sirve(Config.GUARIDA_ALCANCE, 90))

	-- Casos límite que no pueden reventar el arranque del mundo.
	kit.eq("cero guaridas devuelve lista vacia", #Lairs.sitiosDeRuta(origen, destino, 0), 0)
	kit.eq("origen y destino iguales no revientan", #Lairs.sitiosDeRuta(origen, origen, 2), 0)
end
