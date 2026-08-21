--!strict
--[[
	Destinations.luau — sortea a qué cruce se entrega en cada partida.

	POR QUÉ EXISTE. *"La ruta verde parece que siempre es la misma, debería ir
	cambiando de manera aleatoria"* (JJ). Y es literal: los tres destinos eran tres
	constantes escritas en `Config` (`Grid.cruce(1, 2)` y sus dos hermanas), así que
	la primera ruta del juego llevaba siempre al mismo portal, por la misma calle,
	con las migas en los mismos cuatro sitios. La segunda partida no enseña nada que
	no enseñara la primera, y eso se paga en D7.

	CÓMO SE HACE SIN ROMPER NADA, que es la parte interesante. El destino no es un
	dato suelto: de él cuelgan las migas, los detectores, las guaridas, los refugios,
	la casa de entrega, el GPS y la brújula. Cambiarlo en caliente sería mover una
	docena de sistemas a la vez.

	Pero no hace falta. El destino se elige UNA VEZ, al arrancar el servidor y ANTES
	de construir el mundo, y se escribe en la copia que el servidor tiene de `Config`.
	A partir de ahí todo lo que se siembra se siembra ya en el sitio nuevo, sin que
	ningún sistema se entere de que hubo un sorteo.

	¿Y EL CLIENTE, QUE TIENE SU PROPIA COPIA DE `Config` Y NO SE ENTERA? No le hace
	falta: el minimapa y la brújula ya no leen `ruta.destino`, leen la posición real
	del mostrador de la casa (`dondeSeEntrega` en `Minimap.luau`), que se replica con
	el mundo. `ruta.destino` sólo les queda de respaldo por si la casa no existe. Eso
	se hizo por otro motivo --que la brújula apuntara a la puerta y no al cruce-- y
	resulta que es justo lo que hace que esto salga gratis.

	LO QUE NO CAMBIA: la distancia. Los candidatos se filtran para que estén a una
	distancia parecida a la del destino nominal, porque la distancia ES la ruta -- lo
	que separa la verde de la ámbar es cuánto se anda y cuánto se cobra, y sortear un
	cruce al otro extremo del mapa convertiría la verde en la roja sin avisar.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Grid = require(game.ReplicatedStorage.Shared.Grid)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)

local Destinations = {}

-- Cuánto puede alejarse o acercarse un candidato respecto al destino de siempre.
-- Entre el 75 % y el 130 %: se nota que el sitio es otro, y la ruta sigue siendo la
-- misma ruta. Con la horquilla más abierta, la verde de una partida podía costar el
-- doble que la de la anterior y el jugador no tendría forma de saber por qué.
local CERCA, LEJOS = 0.75, 1.3

-- Los cruces de la banda de una zona que sirven de destino.
--
-- Se piden a `Grid` y no se escriben: la banda de cada zona ya está definida ahí
-- (`filaDeZona`), y una lista escrita a mano se quedaría vieja en cuanto la retícula
-- cambie de tamaño -- que es exactamente lo que le pasó a media docena de constantes
-- de este proyecto.
function Destinations.candidatos(rutaId: string, nominal: Vector3): { Vector3 }
	local fila = Grid.filaDeZona(rutaId)
	if fila == nil then
		return { nominal }
	end
	local base = (nominal - Config.ALMACEN_POS).Magnitude
	local lista: { Vector3 } = {}
	for i = 0, Grid.COLUMNAS do
		local cruce = Grid.cruce(i, fila)
		-- Fuera de casa: un destino dentro de la zona segura se entregaría solo, sin
		-- viaje y sin riesgo.
		if Perimeter.dentro(cruce, Config.ZONA_SEGURA_RADIO) then
			continue
		end
		local d = (cruce - Config.ALMACEN_POS).Magnitude
		if d >= base * CERCA and d <= base * LEJOS then
			table.insert(lista, cruce)
		end
	end
	-- Si el filtro no deja nada, el de siempre. Quedarse sin destino sería quedarse
	-- sin ruta, y ninguna variedad vale eso.
	if #lista == 0 then
		table.insert(lista, nominal)
	end
	return lista
end

-- Elige y ESCRIBE el destino de cada ruta. Se llama una sola vez, desde
-- `Main.server`, antes de construir el mundo.
--
-- La semilla entra por parámetro en vez de leerse aquí para que se pueda probar: con
-- una semilla fija el resultado es fijo, y así una prueba puede comprobar que los
-- tres destinos salen dentro de su banda y a la distancia correcta sin depender de
-- la hora a la que se ejecute.
function Destinations.sortear(semilla: number): { [string]: Vector3 }
	local rng = Random.new(semilla)
	local elegidos: { [string]: Vector3 } = {}
	for _, ruta in Config.RUTAS do
		local opciones = Destinations.candidatos(ruta.id, ruta.destino)
		local elegido = opciones[rng:NextInteger(1, #opciones)]
		ruta.destino = elegido
		elegidos[ruta.id] = elegido
	end
	return elegidos
end

return Destinations
