--!strict
--[[
	Grid.luau — la retícula de la ciudad. Módulo PURO.

	Aquí y en ningún otro sitio se decide dónde pasa cada calle. Antes esto vivía
	repartido: la geometría dentro de MapBuilder (servidor, imposible de probar sin
	abrir Studio) y las coordenadas de los destinos sueltas en Config, escritas a
	mano. Dos sitios que pueden discrepar, y discreparon: un destino acabó debajo de
	un árbol y otro sobre un zócalo de 13 studs, porque se eligieron mirando dónde
	había suelo llano en un mapa ajeno en vez de mirando el plano.

	Con una sola fuente, MapBuilder planta desde aquí, Config deriva los destinos de
	aquí y SelfCheck verifica contra aquí. Y como no toca ninguna API de Roblox, se
	comprueba con pruebas puras.

	EL PLANO (spec en docs/specs/2026-08-19-mapa-propio-design.md):

	                 X=-766   -620    -474    -328   -182
	        Z=754  ────┼───────┼───────┼───────┼───────┼──   ← boca del recinto
	                   │ (0,2) │ (1,2) │ (2,2) │ (3,2) │        VERDE
	           608  ────┼───────┼───────┼───────┼───────┼──
	                   │ (0,1) │ (1,1) │ (2,1) │ (3,1) │        ÁMBAR
	           462  ────┼───────┼───────┼───────┼───────┼──
	                   │ (0,0) │ (1,0) │ (2,0) │ (3,0) │        ROJA
	           316  ────┼───────┼───────┼───────┼───────┼──

	Las bandas van por FILAS y no en diagonal a propósito: así la zona de una ruta es
	la que hay que atravesar para llegar a su destino. Con las zonas en diagonal --que
	es lo que proponía el diseño anterior-- se llegaba al destino de la roja sin pisar
	la zona roja, que es justo lo contrario de lo que la ruta promete.

	Por qué esta retícula y no otra: la calle X=-620 pasa por la boca del recinto
	(Config.POLIGONO_SALIDA), así que al salir de casa ya estás EN una calle y todo
	destino queda a un giro o a ninguno. Esa es la razón de que el mapa empiece ahí y
	no en un origen redondo.
]]

local Grid = {}

-- Las tres medidas de las que sale todo lo demás. Derivadas unas de otras para que
-- no puedan discrepar: escribir 146 a mano en dos sitios es cómo se rompen estas
-- cosas.
Grid.LADO_MANZANA = 120
Grid.ANCHO_CALLE = 26
Grid.PASO = Grid.LADO_MANZANA + Grid.ANCHO_CALLE

Grid.COLUMNAS = 4
Grid.FILAS = 3

-- La cota por la que se anda. Es la del almacén, y no un número redondo, porque el
-- recinto ya estaba plantado ahí cuando se rehízo el mapa y moverlo habría obligado
-- a re-medir la zona segura, el spawn y las cuatro rutas.
Grid.Y = 19.2

-- La primera calle de cada eje. X_PRIMERA sale de que la calle siguiente (-620) es
-- la que pasa por la boca del recinto; Z_PRIMERA, de que la última (754) sea el
-- borde sur de ese mismo recinto.
local X_PRIMERA = -766
local Z_PRIMERA = 316

-- Coordenada de la línea CENTRAL de una calle. `i` va de 0 a COLUMNAS (5 calles
-- para 4 columnas de manzanas): las de los extremos existen, y son lo que permite
-- rodear el mapa por fuera en vez de encontrarse el borde.
function Grid.xDeCalle(i: number): number
	return X_PRIMERA + i * Grid.PASO
end

function Grid.zDeCalle(j: number): number
	return Z_PRIMERA + j * Grid.PASO
end

-- Un cruce, que es donde va cada destino del juego. Devolver Vector3 y no dos
-- números es deliberado: Config guarda destinos, y un destino es un sitio.
function Grid.cruce(i: number, j: number): Vector3
	return Vector3.new(Grid.xDeCalle(i), Grid.Y, Grid.zDeCalle(j))
end

-- El rectángulo que ocupa el mapa, calles de los bordes incluidas. Lo usan el suelo
-- base y las comprobaciones que barren el mundo.
function Grid.limites(): (number, number, number, number)
	local medio = Grid.ANCHO_CALLE / 2
	return Grid.xDeCalle(0) - medio,
		Grid.xDeCalle(Grid.COLUMNAS) + medio,
		Grid.zDeCalle(0) - medio,
		Grid.zDeCalle(Grid.FILAS) + medio
end

-- Los cuatro bordes de una manzana: x0, x1, z0, z1. La manzana (col, fila) vive
-- ENTRE las calles col y col+1, y entre las filas fila y fila+1.
function Grid.manzana(col: number, fila: number): (number, number, number, number)
	local medio = Grid.ANCHO_CALLE / 2
	return Grid.xDeCalle(col) + medio,
		Grid.xDeCalle(col + 1) - medio,
		Grid.zDeCalle(fila) + medio,
		Grid.zDeCalle(fila + 1) - medio
end

-- Centro de una manzana. Lo piden los edificios y los hitos.
function Grid.centroManzana(col: number, fila: number): Vector3
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	return Vector3.new((x0 + x1) / 2, Grid.Y, (z0 + z1) / 2)
end

-- LAS BANDAS. Fila 0 la más lejana de casa, fila FILAS-1 la más cercana. El orden
-- importa: es lo que hace que alejarse de casa sea entrar en zona peor.
local ZONA_POR_FILA = { [0] = "roja", [1] = "ambar", [2] = "verde" }

function Grid.zonaDeFila(fila: number): string
	return ZONA_POR_FILA[fila] or "ambar"
end

function Grid.filaDeZona(zona: string): number
	for fila, nombre in ZONA_POR_FILA do
		if nombre == zona then
			return fila
		end
	end
	return 1
end

-- ¿Este punto está sobre calzada? Vale con que uno de los dos ejes caiga sobre una
-- línea de calle: las calles son continuas de borde a borde, así que estar alineado
-- con una ya es estar en ella.
function Grid.enCalle(x: number, z: number): boolean
	local medio = Grid.ANCHO_CALLE / 2
	for i = 0, Grid.COLUMNAS do
		if math.abs(x - Grid.xDeCalle(i)) <= medio then
			return true
		end
	end
	for j = 0, Grid.FILAS do
		if math.abs(z - Grid.zDeCalle(j)) <= medio then
			return true
		end
	end
	return false
end

-- CUÁNTAS VECES HAY QUE GIRAR. Es la medida de "sé a dónde voy": un destino al que
-- se llega sin girar se explica solo, y uno al que hay que girar cuatro veces no se
-- explica ni con un mapa. Sobre una retícula, dos puntos que comparten eje están a
-- cero giros y cualesquiera otros dos, a uno.
--
-- La tolerancia de un stud no es pereza: la boca del recinto está en Z=755 y la
-- calle norte en 754, porque el recinto se plantó antes que el mapa y moverlo
-- costaría re-medir la zona segura y el spawn por ganar un stud.
function Grid.giros(desde: Vector3, hasta: Vector3): number
	if math.abs(desde.X - hasta.X) <= 1 or math.abs(desde.Z - hasta.Z) <= 1 then
		return 0
	end
	return 1
end

-- Largo del camino en L, que sobre una retícula sin obstáculos ES el camino real.
-- Sirve para dimensionar rutas sin pagar un ComputeAsync por cada tanteo.
function Grid.camino(desde: Vector3, hasta: Vector3): number
	return math.abs(desde.X - hasta.X) + math.abs(desde.Z - hasta.Z)
end

-- EL CAMINO POR CALLES, en L: se avanza por la calle en la que ya estás hasta la
-- altura del destino, y allí se gira una vez.
--
-- Lo pide la fila de luces que marca la ruta. Hasta ahora se repartía sobre el camino
-- del pathfinder, y el pathfinder es un bot omnisciente: corta por dentro de las
-- manzanas entre edificio y edificio, por donde ningún jugador sabe que puede pasar.
-- El resultado, medido: la fila de la verde se perdía detrás de un edificio en dos de
-- sus nueve tramos -- y una fila de luces que se corta es peor que no tener fila,
-- porque el jugador se fía de ella.
--
-- Por las calles, la fila enseña el camino que se puede seguir mirando. Que además
-- exista un atajo por dentro de las manzanas no es un problema: es lo que se descubre
-- andando, y es justo el aprendizaje que el mapa tenía que pedir.
function Grid.porCalles(desde: Vector3, hasta: Vector3): { Vector3 }
	return {
		Vector3.new(desde.X, Grid.Y, desde.Z),
		Vector3.new(desde.X, Grid.Y, hasta.Z),
		Vector3.new(hasta.X, Grid.Y, hasta.Z),
	}
end

return Grid
