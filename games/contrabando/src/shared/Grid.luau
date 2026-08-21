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

-- LA ACERA MAS CERCANA A UN PUNTO, y hacia donde mira quien se planta en ella.
--
-- Existe porque *"las camaras o farolas deberian estar en la acera y apuntar a la
-- calle"* (JJ), y hasta ahora no hacian ni una cosa ni la otra: la posicion salia de
-- interpolar sobre la linea origen-destino --asi que un poste podia acabar en mitad
-- de un patio-- y el rumbo de una lista fija de cuatro valores rotando por indice, o
-- sea mirando a donde tocara. Una camara que vigila una pared no vigila nada, y
-- ademas rompe la unica promesa que el sistema le hace al jugador: que se puede ver
-- venir el peligro.
--
-- Devuelve el punto YA en la acera (justo dentro de la manzana, fuera de la calzada)
-- y el rumbo en grados de la convencion del proyecto: 0 mira a -Z, 90 a -X, 180 a +Z
-- y 270 a +X, que es lo que da `CFrame.Angles(0, rad(rumbo), 0)` sobre el frente de
-- Roblox.
--
-- Se elige el eje por el que el punto esta MAS CERCA de una calle. Un punto en mitad
-- de una manzana tiene dos calles a tiro y las dos valen; el desempate por cercania
-- es el que mantiene al poste donde lo puso quien lo sembro, en vez de mandarlo al
-- otro extremo de la manzana.
function Grid.aceraDe(punto: Vector3): (Vector3, number)
	local medio = Grid.ANCHO_CALLE / 2
	-- A que distancia queda el poste del bordillo, ya dentro de la manzana. Tres
	-- studs: fuera de la calzada --si no, un coche lo atraviesa y encima tapa la
	-- linea de borde-- y lo bastante cerca para que su cono barra la calle entera.
	local RETRANQUEO = 3

	local mejorX, distX = 0, math.huge
	for i = 0, Grid.COLUMNAS do
		local d = math.abs(punto.X - Grid.xDeCalle(i))
		if d < distX then
			distX, mejorX = d, Grid.xDeCalle(i)
		end
	end
	local mejorZ, distZ = 0, math.huge
	for j = 0, Grid.FILAS do
		local d = math.abs(punto.Z - Grid.zDeCalle(j))
		if d < distZ then
			distZ, mejorZ = d, Grid.zDeCalle(j)
		end
	end

	-- APARTARSE DE UNA CALLE NO BASTA: HAY QUE APARTARSE DE LAS DOS.
	--
	-- Medido en el mundo con la primera version: 14 de 43 camaras seguian plantadas
	-- en calzada. Eran las de los CRUCES -- salir de la calle vertical las dejaba
	-- dentro del ancho de la horizontal, que es la esquina de la manzana. Y una
	-- camara en mitad de un cruce es justo la que se lleva por delante el primer
	-- coche que pase, ademas de tapar las dos lineas de borde a la vez.
	--
	-- Asi que se ajusta el eje que mande --el mas cercano, que es el que decide a que
	-- calle mira-- y despues se comprueba el otro y se aparta tambien si hace falta.
	-- El rumbo NO cambia con el segundo ajuste: se sigue vigilando la calle elegida,
	-- solo que desde la esquina en vez de desde el borde.
	local x, z = punto.X, punto.Z
	local rumbo

	if distX <= distZ then
		-- Calle VERTICAL: la acera esta a un lado u otro en X, y se mira hacia el eje.
		local lado = if punto.X >= mejorX then 1 else -1
		x = mejorX + lado * (medio + RETRANQUEO)
		-- Al este de la calle se mira hacia -X (rumbo 90); al oeste, hacia +X (270).
		rumbo = if lado > 0 then 90 else 270
		-- Y fuera del cruce, si lo hubiera.
		if math.abs(z - mejorZ) < medio + RETRANQUEO then
			local haciaZ = if z >= mejorZ then 1 else -1
			z = mejorZ + haciaZ * (medio + RETRANQUEO)
		end
	else
		-- Calle HORIZONTAL: lo mismo por el otro eje.
		local lado = if punto.Z >= mejorZ then 1 else -1
		z = mejorZ + lado * (medio + RETRANQUEO)
		-- Al sur de la calle se mira hacia -Z (rumbo 0); al norte, hacia +Z (180).
		rumbo = if lado > 0 then 0 else 180
		if math.abs(x - mejorX) < medio + RETRANQUEO then
			local haciaX = if x >= mejorX then 1 else -1
			x = mejorX + haciaX * (medio + RETRANQUEO)
		end
	end

	-- Y NUNCA FUERA DEL MAPA. En las calles del borde, apartarse "hacia afuera" te
	-- saca del rectangulo entero: medido, diez camaras acabaron en las afueras, donde
	-- no pasa nadie y por tanto no fichan a nadie. Si el sitio elegido se sale, se
	-- coge la acera de enfrente -- y el rumbo se da la vuelta con ella, porque desde
	-- el otro lado se mira la misma calle en sentido contrario.
	--
	-- EL RUMBO SOLO SE DA LA VUELTA SI SE MUEVE EL EJE QUE VIGILA. Cuando la camara
	-- mira una calle vertical (rumbo 90 o 270) su rumbo depende de X y nada mas: si
	-- lo que hay que corregir es la Z --el ajuste del cruce-- se cambia de esquina
	-- pero se sigue mirando la misma calle en el mismo sentido. Invertirlo tambien
	-- ahi la dejaba mirando a la manzana.
	local vigilaX = rumbo == 90 or rumbo == 270
	local lx0, lx1, lz0, lz1 = Grid.limites()
	if x < lx0 or x > lx1 then
		x = mejorX - (x - mejorX)
		if vigilaX then
			rumbo = (rumbo + 180) % 360
		end
	end
	if z < lz0 or z > lz1 then
		z = mejorZ - (z - mejorZ)
		if not vigilaX then
			rumbo = (rumbo + 180) % 360
		end
	end

	return Vector3.new(x, punto.Y, z), rumbo
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

-- LA ESQUINA DE MANZANA QUE TOCA UN CRUCE, y hacia donde da su fachada.
--
-- Existe para los PORTALES DE ENTREGA. Hasta el 20/08 el destino era una losa de
-- color en mitad del cruce, y JJ dio con lo que le faltaba: *"estaria bien que los
-- puntos de entrega estuvieran en ventanas de edificios, como si fueran viviendas,
-- y no puntos en medio del mapa"*. Un punto pintado en el asfalto no es un sitio --
-- no se entrega EN un cruce, se entrega en el portal de alguien.
--
-- LA FACHADA DA A UNA CALLE, NO A LA DIAGONAL. La primera version devolvia el
-- vector del cruce a la esquina, que en una reticula es exactamente la diagonal: la
-- casa salia girada 45 grados, mirando a la boca del cruce en vez de a ninguna de
-- las dos calles. Se vio midiendo su caja -- una casa de 49x37 ocupaba 66x67 de
-- huella, asi que se comia media manzana y la sonda contaba invasores que no la
-- tocaban. Y visto desde dentro es peor todavia: un bloque de pisos torcido
-- respecto a su calle no se lee como un edificio, se lee como un fallo.
--
-- Se toma el eje DOMINANTE, con desempate en Z. En una reticula los dos valen 13
-- (medio ancho de calle) y hay empate siempre, asi que en la practica todas las
-- casas dan a la calle horizontal -- y eso es una virtud, no un azar: un jugador
-- que aprende que "el portal siempre mira al norte o al sur" tiene una regla menos
-- que descubrir en cada entrega.
--
-- Devuelve el centro de la casa y la direccion que va del cruce hacia dentro de la
-- manzana, que es hacia donde apunta su parte de atras. `fondo` y `ancho` son las
-- medidas de la casa: hacen falta las dos para meterla ENTERA en la manzana -- con
-- solo el fondo, la mitad del ancho quedaba sobre la calle perpendicular.
function Grid.portalDeCruce(cruce: Vector3, fondo: number, ancho: number): (Vector3, Vector3)
	local col = math.clamp(math.floor((cruce.X - Grid.xDeCalle(0)) / Grid.PASO + 0.5), 0, Grid.COLUMNAS - 1)
	local fila = math.clamp(math.floor((cruce.Z - Grid.zDeCalle(0)) / Grid.PASO + 0.5), 0, Grid.FILAS - 1)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)

	-- La esquina de la manzana mas cercana al cruce, en cada eje por separado.
	local ex = if math.abs(x0 - cruce.X) <= math.abs(x1 - cruce.X) then x0 else x1
	local ez = if math.abs(z0 - cruce.Z) <= math.abs(z1 - cruce.Z) then z0 else z1
	local dx, dz = ex - cruce.X, ez - cruce.Z

	-- El eje dominante manda; el otro solo sirve para saber hacia que lado correrse.
	local haciaDentro, aLoLargo
	if math.abs(dx) > math.abs(dz) then
		haciaDentro = Vector3.new(if dx >= 0 then 1 else -1, 0, 0)
		aLoLargo = Vector3.new(0, 0, if dz >= 0 then 1 else -1)
	else
		haciaDentro = Vector3.new(0, 0, if dz >= 0 then 1 else -1)
		aLoLargo = Vector3.new(if dx >= 0 then 1 else -1, 0, 0)
	end

	-- Fondo adentro y ancho a lo largo de la fachada: asi la casa cae ENTERA dentro
	-- de la manzana, con su cara delantera justo en la linea de la acera.
	local centro = Vector3.new(ex, Grid.Y, ez) + haciaDentro * (fondo / 2) + aLoLargo * (ancho / 2)
	return centro, haciaDentro
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

-- LA RUTA COMO LA DARIA UN GPS: desde DONDE ESTAS, no desde la puerta de casa.
--
-- Lo pidio JJ el 20/08 y describio exactamente lo que faltaba: *"el mapa de abajo
-- deberia ensenar el punto de entrega y la ruta dinamica hasta el, segun por donde
-- decida ir, asi no me pierdo, como si fuera un GPS del coche"*.
--
-- Lo que habia era una L fija de la salida del recinto al destino, calculada una
-- vez. Servia mientras se saliera de casa y no se uno se desviara, y en cuanto te
-- salias no volvia a decir nada: la linea seguia donde estaba y tu no. Un plano que
-- solo acierta si vas por donde el creia no es una guia, es una ilustracion.
--
-- COMO SE TRAZA. Primero se sale a la CALLE MAS CERCANA --por el eje en el que
-- menos hay que andar-- y desde ahi se va por calles hasta la vertical del destino,
-- y por ella hasta el. Es la misma L de siempre pero anclada a la reticula en vez
-- de al aire: la diferencia esta en que ahora el primer punto eres tu.
--
-- Se queda en dos giros como maximo a proposito. Un camino optimo de verdad pediria
-- pathfinding, y eso en un plano de 190 pixeles se ve igual y cuesta cien veces
-- mas; lo que el jugador necesita saber es "tira por esta calle y luego gira", que
-- es justo lo que dibujan tres tramos.
function Grid.rutaGps(desde: Vector3, hasta: Vector3): { Vector3 }
	local y = Grid.Y
	local aqui = Vector3.new(desde.X, y, desde.Z)
	local alli = Vector3.new(hasta.X, y, hasta.Z)

	-- La calle mas cercana de cada eje, y cuanto hay que apartarse para pisarla.
	local mejorX, distX = aqui.X, math.huge
	for i = 0, Grid.COLUMNAS do
		local x = Grid.xDeCalle(i)
		if math.abs(x - aqui.X) < distX then
			mejorX, distX = x, math.abs(x - aqui.X)
		end
	end
	local mejorZ, distZ = aqui.Z, math.huge
	for j = 0, Grid.FILAS do
		local z = Grid.zDeCalle(j)
		if math.abs(z - aqui.Z) < distZ then
			mejorZ, distZ = z, math.abs(z - aqui.Z)
		end
	end

	local puntos: { Vector3 } = { aqui }
	if distX <= distZ then
		-- Estas mas cerca de una calle VERTICAL: se sale a ella y se baja por ella.
		table.insert(puntos, Vector3.new(mejorX, y, aqui.Z))
		table.insert(puntos, Vector3.new(mejorX, y, alli.Z))
	else
		-- O de una HORIZONTAL: se sale a ella y se avanza por ella.
		table.insert(puntos, Vector3.new(aqui.X, y, mejorZ))
		table.insert(puntos, Vector3.new(alli.X, y, mejorZ))
	end
	table.insert(puntos, alli)

	-- Se quitan los puntos repetidos: un tramo de longitud cero no se puede dibujar
	-- y ademas rompe la cuenta del "siguiente giro", que es lo que mira la brujula.
	local limpio: { Vector3 } = { puntos[1] }
	for i = 2, #puntos do
		local ultimo = limpio[#limpio]
		if (puntos[i] - ultimo).Magnitude > 1 then
			table.insert(limpio, puntos[i])
		end
	end
	return limpio
end

-- HACIA DONDE HAY QUE TIRAR AHORA MISMO: el siguiente punto de la ruta que no
-- tengas ya encima. Es lo que convierte la brujula en la voz del GPS -- *"arriba
-- una pequena brujula para saber por donde deberia ir ahora mismo"*.
--
-- Apuntar en linea recta al destino es lo que hacia antes, y es justo lo que no
-- sirve en una ciudad: la flecha senala a traves de una manzana y tu no puedes
-- atravesarla. El siguiente vertice si es alcanzable en linea recta.
function Grid.siguientePaso(ruta: { Vector3 }, desde: Vector3, cerca: number?): Vector3?
	if #ruta == 0 then
		return nil
	end
	local umbral = cerca or 12

	-- DESDE EL VERTICE MAS CERCANO HACIA ADELANTE, y no desde el principio de la
	-- lista. Recorrer desde el primero devolvia el primer vertice a mas de `umbral`
	-- studs, que si te has saltado un tramo --por un atajo, o porque la ruta no se
	-- ha repintado todavia-- es un vertice que YA HAS PASADO: la brujula te mandaba
	-- de vuelta por donde venias. Lo cazo su propia prueba, plantando al jugador al
	-- lado del destino.
	local masCerca, mejor = 1, math.huge
	for i, punto in ruta do
		local d = Vector3.new(punto.X - desde.X, 0, punto.Z - desde.Z).Magnitude
		if d < mejor then
			masCerca, mejor = i, d
		end
	end

	for i = masCerca, #ruta do
		local d = Vector3.new(ruta[i].X - desde.X, 0, ruta[i].Z - desde.Z).Magnitude
		if d > umbral then
			return ruta[i]
		end
	end
	return ruta[#ruta]
end

return Grid
