--!strict
--[[
	Lairs.luau — las guaridas: de dónde salen los ladrones. Módulo PURO.

	POR QUÉ EXISTE. Lo dijo JJ jugando: *"no ves en el mapa dónde están los
	ladrones y su zona de influencia, te aparecen de repente; deberías poder mirar
	el mapa y planear por dónde ir"*. Y era literal — hasta ahora un ladrón se
	materializaba a 90-140 studs del jugador, en cualquier dirección, sin venir de
	ningún sitio.

	Eso rompe la promesa del rediseño de la ciudad, que decía que la habilidad del
	juego sería **reconocer el cruce malo y rodearlo**. Un peligro que aparece de la
	nada no se puede rodear: no es tensión, es un impuesto.

	Con guaridas fijas pasan tres cosas a la vez:

	  · se pueden **rodear**, y ésa es la decisión que el viaje tenía que pedir;
	  · **explican** de dónde viene el que te persigue, en vez de castigarte sin
	    contexto;
	  · le dan **carácter** a cada zona, más allá de su color.

	FIJAS Y APRENDIBLES, como los detectores y por el mismo motivo: con posiciones
	aleatorias en cada partida no habría nada que aprender, y esquivarlas sería
	suerte. Fijas, el jugador que repite la ruta reconoce la manzana mala.
]]

local Config = require(script.Parent.Config)

local Lairs = {}

-- Las guaridas de una ruta, repartidas por su corredor.
--
-- SE APARTAN MENOS QUE LOS REFUGIOS (70 studs frente a 100), y es deliberado: un
-- refugio hay que poder alcanzarlo desviándote, pero una guarida tiene que estar
-- lo bastante cerca del camino como para que pasar de largo sea una decisión. Si
-- estuviera lejos, rodearla no costaría nada y dejaría de significar algo.
--
-- Y AL LADO CONTRARIO que el primer refugio (empieza el reparto en -1, no en +1):
-- si las dos cosas cayeran del mismo lado, el jugador tendría que meterse en la
-- boca del lobo para poder esconderse.
function Lairs.sitiosDeRuta(origen: Vector3, destino: Vector3, cuantas: number): { Vector3 }
	local sitios: { Vector3 } = {}
	if cuantas <= 0 then
		return sitios
	end

	local direccion = destino - origen
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	if plano.Magnitude < 1 then
		return sitios
	end
	-- Perpendicular en el plano: girar 90° es (z, -x).
	local lado = Vector3.new(plano.Z, 0, -plano.X).Unit

	for i = 1, cuantas do
		-- Repartidas por el tramo central del viaje. Ni en la puerta de casa --que
		-- es zona segura y no puede tener una guarida al lado-- ni pegadas al
		-- destino, donde el viaje ya está hecho y perder la carga allí sólo se lee
		-- como una tomadura de pelo.
		local t = 0.3 + 0.4 * ((i - 0.5) / cuantas)
		local centro = origen:Lerp(destino, t)
		local signo = if i % 2 == 1 then -1 else 1
		table.insert(sitios, centro + lado * (Config.GUARIDA_DESVIO * signo))
	end

	return sitios
end

-- La guarida más cercana a un punto, y a qué distancia. Devuelve nil si no hay
-- ninguna: quien pregunte tiene que poder seguir sin ella.
function Lairs.masCercana(posicion: Vector3, guaridas: { Vector3 }): (Vector3?, number)
	local mejor: Vector3? = nil
	local mejorDistancia = math.huge
	for _, sitio in guaridas do
		local dx = sitio.X - posicion.X
		local dz = sitio.Z - posicion.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < mejorDistancia then
			mejor, mejorDistancia = sitio, d
		end
	end
	return mejor, mejorDistancia
end

-- ¿Sirve esta guarida para soltar un ladrón contra alguien que está aquí?
--
-- La ventana tiene dos bordes y los dos importan. Demasiado cerca es una
-- emboscada: un ladrón que aparece encima no se puede esquivar, y el jugador sólo
-- ve que le han quitado la carga. Demasiado lejos es un adorno: llega cuando el
-- viaje ya ha terminado. Fuera de la ventana, quien llame se las apaña por su
-- cuenta -- antes un ladrón sin guarida que ningún ladrón.
function Lairs.sirve(distancia: number, minimo: number): boolean
	return distancia >= minimo and distancia <= Config.GUARIDA_ALCANCE
end

return Lairs
