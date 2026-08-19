--!strict
--[[
	MapBuilder.luau — genera la ciudad proceduralmente.

	Reemplaza al Ciudad.rbxm del Creator Store (2701703521) que se usaba hasta
	ahora. El motivo del cambio está en `mapa/DISENO-MAPA.md`.

	La interfaz es deliberadamente compatible con el contrato que CityBuilder
	espera: devuelve un Model llamado "Ciudad" que CityBuilder usa como suelo
	para sus raycasts. Cambia el contenido (calles, manzanas, edificios), no
	la forma de integrarse.

	Reglas del proyecto que se respetan aquí:
	- Sin assets externos. Todo Part, sin meshes (los meshes no se ven sin
	  publicar el place — trampa ya pagada).
	- Sin lógica de juego. Esto planta geometría; las reglas viven en shared/.
	- Semilla fija en las posiciones aleatorias, para que los jugadores puedan
	  aprender dónde están los edificios y los cruces.

	Lo que NO hace este módulo (queda para fases posteriores):
	- Callejones con geometría específica (fase 2 — ✅ hecho vía plantarEdificioEnFila).
	- Plaza vacía como atajo (fase 2 — ✅ hecho vía PLAZA).
	- Solares en ámbar/roja como vías de escape (fase 2.5 — ✅ hecho vía LOTES_VACANTES).
	- Hitos de zona + verificación de conectividad (fase 3 lite — ✅ hecho).
	- **Fase 4 (estética) NO entra hasta que el bucle enganche**: calles con
	  ancho variable, farolas, letreros, tejados variados, paleta definitiva.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Grid = require(game.ReplicatedStorage.Shared.Grid)
local Palette = require(game.ReplicatedStorage.Shared.Palette)

local MapBuilder = {}

-- El plano no se decide aquí: vive en shared/Grid.luau, que es de donde beben
-- también Config (para los destinos) y SelfCheck (para verificarlos). Esto es
-- sólo la parte que se planta.
local TAMANO_MANZANA = Grid.LADO_MANZANA
local ANCHO_CALLE = Grid.ANCHO_CALLE
local ALTO_CALLE = 0.5
local ALTO_ACERA = 2
-- Lo que la acera sobresale de la calzada. Es la cota sobre la que se apoyan los
-- edificios, así que vive fuera de plantarLosaManzana: tenerla dentro obligaba a que
-- los edificios se apoyaran en un número repetido a mano.
-- LO QUE LA MANZANA SE LEVANTA SOBRE EL ASFALTO. Bajó de 1,5 a 0,8 el 19/08 y el
-- motivo es de navegación, no de estética: las losas del juego (destinos, guaridas,
-- refugios) se apoyan en el PUNTO MÁS ALTO de su huella --una regla heredada del
-- terreno irregular, donde apoyarse en el centro las dejaba enterradas-- y como los
-- destinos están en cruces, su huella de 44 studs pisa las cuatro manzanas de
-- alrededor. Con 1,5 la losa del barrio quedaba 3,5 studs sobre la calzada y el
-- camino a pie SIN SALTAR se cortaba: el pathfinder decía NoPath a un destino al que
-- se llegaba perfectamente dando un brinco, que es justo la clase de fallo que no
-- reventa nada.
--
-- 0,8 se sigue viendo como bordillo y el navmesh lo cruza sin saltar.
local ACERA_ALTURA = 0.8

-- LA COTA POR LA QUE SE ANDA, y todo lo que se planta se cuelga de ella. Antes el
-- mapa vivía en y=0 y el resto del juego en 19,2, porque el mapa se generaba para
-- probarse solo y el recinto estaba puesto sobre un terreno ajeno. Tener dos alturas
-- distintas para el mismo suelo es exactamente cómo aparece un canto de tres studs
-- que corta el navmesh sin que nada dé error.
local Y_CALZADA = Grid.Y

-- Zonas en índices de manzana (col, fila), 0-based, con el origen abajo-izquierda.
-- La "L" verde→ámbar→roja preserva la asimetría del spec original: el almacén
-- queda en el SO, los destinos se alejan hacia el NE, y la roja además obliga
-- a cruzar una zona más densa — cuello de botella natural sin ponerlo a mano.
local ZONAS: { [string]: { colMin: number, colMax: number, filaMin: number, filaMax: number } } = {
	verde = { colMin = 0, colMax = Grid.COLUMNAS - 1, filaMin = 2, filaMax = 2 },
	ambar = { colMin = 0, colMax = Grid.COLUMNAS - 1, filaMin = 1, filaMax = 1 },
	roja = { colMin = 0, colMax = Grid.COLUMNAS - 1, filaMin = 0, filaMax = 0 },
}

-- Plaza en la zona verde: una manzana vacía como atajo. Se eligió la (col=1,
-- fila=4) — diagonal NE desde el almacén, entre éste y el destino verde — para
-- que la salida natural del jugador pase **por o cerca de** la plaza, y el
-- atajo sea un gesto que el jugador descubre andando, no una decisión que
-- tiene que leer en pantalla.
local PLAZA = { col = 1, fila = 2 }

-- **Solares**: manzanas vacías en ámbar y roja. Son la versión "callejón a lo
-- grande" del diseño: el jugador las cruza en diagonal cuando una patrulla le
-- pisa los talones, y la patrulla (atada a las calles) tiene que bordearlas
-- por fuera. La plaza de la verde cumple el mismo papel, pero en ámbar y roja
-- son **vías de escape** concretas, no un atajo de aprendizaje.
--
-- Posiciones elegidas a mano, no aleatorias: el jugador debe poder **aprender**
-- dónde está el solar. (2,2) cae en la diagonal entre el destino ámbar y la
-- roja, así el jugador que huye de la ámbar la ve venir antes de entrar; (4,1)
-- está en la frontera roja-ámbar, pegado a la zona más densa, y es la salida
-- natural si una patrulla te cierra las calles.
--
-- Si en una partida jugada resulta que alguna de estas posiciones no funciona
-- (la patrulla entra al solar, o el jugador la descubre demasiado tarde), se
-- cambia la coordenada y se vuelve a jugar. Es el mismo flujo que con la
-- plaza: un cambio de 2 líneas, sin tocar el resto del mapa.
local LOTES_VACANTES: { { col: number, fila: number } } = {
	{ col = 2, fila = 1 }, -- ámbar: pegado al destino ámbar, la salida si te pisan
	{ col = 1, fila = 0 }, -- roja: escape de la banda densa hacia el oeste
}

-- Características por zona. Ahora con **rango de densidad** (no un número
-- fijo): cada manzana tira los dados y sale con 1-2, 2-3 o 3-5 edificios según
-- la zona. La repetición de la semilla hace que el resultado sea estable entre
-- partidas, así que la variabilidad es por manzana, no por sesión.
--
-- La plantación pasa a ser **en fila** cuando la zona tiene más de un edificio
-- por manzana (ver plantarEdificioEnFila). Eso es lo que crea los callejones
-- visibles: huecos consistentes de `GAP_ENTRE_EDIFICIOS` studs entre
-- contiguos, no paquetes de edificios apilados al azar.
local ZONA_CONFIG: {
	[string]: { densidadMin: number, densidadMax: number, alturaMin: number, alturaMax: number },
} =
	{
		verde = { densidadMin = 1, densidadMax = 2, alturaMin = 12, alturaMax = 24 },
		ambar = { densidadMin = 2, densidadMax = 3, alturaMin = 24, alturaMax = 44 },
		roja = { densidadMin = 3, densidadMax = 5, alturaMin = 44, alturaMax = 80 },
	}

-- Hueco entre edificios cuando se plantan en fila. Lo bastante estrecho para
-- que sea claramente un callejón (no un patio), lo bastante ancho para que un
-- personaje y una patrulla quepan a la vez: el patrullaje en callejones de la
-- roja es la habilidad de lectura que el viaje pide.
local GAP_ENTRE_EDIFICIOS = 8

-- Lo más estrecho que puede salir un edificio de una fila. Bajó de 40 a 24 con la
-- manzana (de 240 a 120): con 40 sobre 120 studs, la roja no podía plantar más de
-- dos edificios por manzana y su densidad --lo único que la distingue-- se perdía.
local ANCHO_MINIMO_EDIFICIO = 24

-- Paleta. Cubos de colores a propósito — la estética se elige cuando el bucle
-- esté medido. Tres tonos por zona para que el ojo distinga edificios sin
-- leer un cartel.
local COLOR_CALLE = Color3.fromRGB(46, 48, 54)
local COLOR_ACERA = Color3.fromRGB(140, 138, 132)
local COLOR_SUELO_BASE = Color3.fromRGB(40, 40, 45)

local COLOR_EDIFICIO: { [string]: { Color3 } } = {
	verde = {
		Color3.fromRGB(120, 132, 96),
		Color3.fromRGB(108, 118, 86),
		Color3.fromRGB(96, 106, 78),
	},
	ambar = {
		Color3.fromRGB(118, 110, 96),
		Color3.fromRGB(106, 98, 86),
		Color3.fromRGB(130, 120, 104),
	},
	roja = {
		Color3.fromRGB(86, 88, 102),
		Color3.fromRGB(76, 78, 92),
		Color3.fromRGB(98, 96, 110),
	},
}

-- Generador con semilla fija. CRÍTICO: si la semilla cambia, los edificios se
-- mueven y los detectores que siembra CityBuilder (que también tienen semilla
-- fija) podrían caer dentro de uno. El día que haya que mover la semilla, hay
-- que revisar la siembra de detectores al mismo tiempo.
local SEMILLA = 7891
local rng = Random.new(SEMILLA)

-- Una pieza anclada con material SmoothPlastic. Helper mínimo: sin él, el
-- código de plantación se vuelve ilegible y la repetición de propiedades
-- esconde cuál cambió entre una llamada y la siguiente.
local function pieza(nombre: string, tamano: Vector3, posicion: Vector3, color: Color3, padre: Instance): Part
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.Position = posicion
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	-- MARCA DE PROPIEDAD, y no es cosmética. CityBuilder despeja el sitio donde va a
	-- plantar una losa o una vía, y su criterio ("pieza pequeña o estrecha") venía
	-- calibrado para la chatarra del mapa del Creator Store -- vallas, matorrales,
	-- farolas. Contra el mapa propio ese criterio se come las aceras enteras: miden
	-- 120 x 1,5 x 6 y encajan en la definición de estorbo. Las calles se salvan por
	-- UN stud (26 de ancho contra un listón de 25).
	--
	-- Con la marca no hay que afinar ningún listón: lo que planta el mapa es el mapa,
	-- y el mapa no se despeja nunca.
	p:SetAttribute("delMapa", true)
	p.Parent = padre
	return p
end

-- Coordenada X del borde OESTE de la columna i, y Z del borde SUR de la fila j.
-- Los dos salen de Grid.manzana para que no haya dos aritméticas del mismo plano.
local function xDeColumna(i: number): number
	local x0 = Grid.manzana(i, 0)
	return x0
end

local function zDeFila(j: number): number
	local _, _, z0 = Grid.manzana(0, j)
	return z0
end

-- Suelo base bajo todo el mapa. Red de seguridad por si un raycast falla: si
-- el suelo de la ciudad desaparece, esto es lo que pisa el jugador. En
-- segmentos por el límite de 2048 studs por eje, ya pagado.
local function plantarSueloBase(padre: Instance)
	local xMin, xMax, zMin, zMax = Grid.limites()
	-- Un margen por fuera del último bordillo: sin él, quien rodea el mapa por la
	-- calle exterior se cae por el borde del mundo.
	local MARGEN = 60
	xMin, xMax, zMin, zMax = xMin - MARGEN, xMax + MARGEN, zMin - MARGEN, zMax + MARGEN

	-- Piezas modestas y no una losa gigante: el raycast del suelo se hace en cada
	-- siembra de CityBuilder, y cuanto menor es la pieza que devuelve, más barato
	-- sale. El límite de 2048 studs por eje ya no es un riesgo con 610 de mapa.
	local PASO = 200
	local indice = 0
	local x = xMin
	while x < xMax do
		local ancho = math.min(PASO, xMax - x)
		local z = zMin
		while z < zMax do
			local largo = math.min(PASO, zMax - z)
			indice += 1
			pieza(
				string.format("Suelo_%d", indice),
				Vector3.new(ancho, 1, largo),
				-- DOS STUDS POR DEBAJO de la calzada y no pegado a ella. Pegado, su cara
				-- de arriba y la de abajo del asfalto quedan en el mismo plano, y dos
				-- superficies en el mismo plano PARPADEAN: la tarjeta gráfica no
				-- puede decidir cuál está delante y va alternando fotograma a
				-- fotograma. Es lo que JJ vio como "parpadea el suelo".
				Vector3.new(x + ancho / 2, Y_CALZADA - 2.5, z + largo / 2),
				COLOR_SUELO_BASE,
				padre
			)
			z += PASO
		end
		x += PASO
	end
end

-- Una calle entre dos hileras de manzanas. Se planta como una pieza larga en
-- X (calles verticales) o en Z (calles horizontales). En fase 1 todas las
-- calles son del mismo ancho — la variación por zona entra en fase 2.
-- LA CALZADA ES UNA ALFOMBRA CONTINUA, y las manzanas van encima.
--
-- La primera versión plantaba una tira por calle, nueve en total, cruzándose entre
-- sí. En cada uno de los veinte cruces dos tiras ocupaban el MISMO volumen con la
-- cara superior a la MISMA altura, y dos superficies coplanares parpadean: la
-- tarjeta gráfica no puede decidir cuál está delante y alterna fotograma a
-- fotograma. Veinte cruces parpadeando es lo que JJ vio nada más entrar.
--
-- Se arregla invirtiendo el planteamiento: en vez de dibujar las calles, se cubre
-- el mapa entero de asfalto y se levantan las manzanas por encima. Lo que queda sin
-- tapar ES la calle. Cero solapes, y de regalo el canto de cada manzana hace de
-- bordillo sin tener que plantarlo.
--
-- Segmentada y no una losa única porque el raycast del suelo se hace en cada siembra
-- de CityBuilder, y cuanto más pequeña es la pieza que devuelve, más barato sale.
local function plantarCalzada(padre: Instance)
	local xMin, xMax, zMin, zMax = Grid.limites()
	local PASO = 160
	local indice = 0
	local x = xMin
	while x < xMax - 0.01 do
		local ancho = math.min(PASO, xMax - x)
		local z = zMin
		while z < zMax - 0.01 do
			local largo = math.min(PASO, zMax - z)
			indice += 1
			pieza(
				string.format("Calzada_%d", indice),
				Vector3.new(ancho, ALTO_CALLE, largo),
				Vector3.new(x + ancho / 2, Y_CALZADA - ALTO_CALLE / 2, z + largo / 2),
				COLOR_CALLE,
				padre
			)
			z += PASO
		end
		x += PASO
	end
end

-- LA MANZANA, una plataforma que se levanta sobre el asfalto.
--
-- Antes eran cuatro aceras sueltas bordeando un interior que se quedaba al nivel del
-- suelo base -- o sea que cada manzana era un hoyo rodeado de bordillo, y por dentro
-- se andaba metro y medio por debajo de la calle. Ahora es una losa: el canto hace de
-- bordillo, el interior queda al nivel correcto, y donde no hay manzana queda a la
-- vista el asfalto de debajo, que es la calle.
--
-- Baja hasta por debajo de la cara del asfalto a propósito. Si las dos caras se
-- tocaran exactamente quedarían coplanares y volvería el parpadeo, esta vez por el
-- canto.
local function plantarLosaManzana(col: number, fila: number, padre: Instance)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local alto = ACERA_ALTURA + 0.3
	pieza(
		string.format("Manzana_%d_%d", col, fila),
		Vector3.new(x1 - x0, alto, z1 - z0),
		Vector3.new((x0 + x1) / 2, Y_CALZADA + ACERA_ALTURA - alto / 2, (z0 + z1) / 2),
		COLOR_ACERA,
		padre
	)
end

-- Un edificio dentro de una manzana, en posición libre. Tamaño en planta,
-- altura y color elegidos por la zona. Se usa para los casos con un solo
-- edificio por manzana (la mayoría de la verde): no necesita fila.
local function plantarEdificio(col: number, fila: number, indice: number, zona: string, padre: Instance): Part
	local cfg = ZONA_CONFIG[zona]
	local paleta = COLOR_EDIFICIO[zona]

	-- Tamaño en planta: 50-80% de la manzana, con un mínimo de 40 studs para
	-- que el jugador no se lo encuentre microscópico.
	local ancho = rng:NextNumber(0.5, 0.8) * TAMANO_MANZANA
	local largo = rng:NextNumber(0.5, 0.8) * TAMANO_MANZANA
	local alto = rng:NextNumber(cfg.alturaMin, cfg.alturaMax)

	local xManzana = xDeColumna(col)
	local zManzana = zDeFila(fila)
	-- MÁS AIRE JUNTO AL BORDILLO. Con 10 studs, un edificio podía asomarse lo
	-- bastante a la calle como para taparle al jugador el siguiente eslabón de la fila
	-- de luces que le marca la ruta -- la sonda lo cazó en la verde. La fila es la
	-- única señal que le dice por dónde seguir; taparla es peor que no plantar nada.
	local margen = 16
	local dx = rng:NextNumber(margen, TAMANO_MANZANA - margen - ancho)
	local dz = rng:NextNumber(margen, TAMANO_MANZANA - margen - largo)

	local color = paleta[rng:NextInteger(1, #paleta)] :: Color3

	return pieza(
		string.format("Edificio_%d_%d_%d", col, fila, indice),
		Vector3.new(ancho, alto, largo),
		Vector3.new(xManzana + dx + ancho / 2, Y_CALZADA + ACERA_ALTURA + alto / 2, zManzana + dz + largo / 2),
		color,
		padre
	)
end

-- Un edificio dentro de una fila de N, todos en la misma manzana. Los
-- edificios se reparten el ancho útil con huecos `GAP_ENTRE_EDIFICIOS` entre
-- ellos — esos huecos son los callejones visibles desde el aire y desde el
-- suelo, y el sitio por donde la patrulla no cabe y el jugador sí.
--
-- La fila se orienta en X o en Z según el `rng`, así la ciudad no parece un
-- tablero cuadriculado perfecto sino una mezcla de orientaciones. La altura
-- sigue la del rango de la zona.
local function plantarEdificioEnFila(
	col: number,
	fila: number,
	indice: number,
	n: number,
	zona: string,
	padre: Instance
): Part
	local cfg = ZONA_CONFIG[zona]
	local paleta = COLOR_EDIFICIO[zona]

	-- Orientación: 0 = fila en X, 1 = fila en Z. La orientación se deriva
	-- de (col, fila) con una fórmula determinista, así **todos los edificios
	-- de la misma manzana se orientan igual** (y los callejones son paralelos
	-- dentro de la manzana, no se entrecruzan). Sin estado entre llamadas:
	-- cada plantación es independiente.
	local orientacion = ((col * 7 + fila) % 2 == 0) and "X" or "Z"

	local margen = 16
	local anchoUtil = TAMANO_MANZANA - 2 * margen
	-- Reparto equitativo: los huecos entre edificios se reparten a partes
	-- iguales. Si por la densidad impuesta no caben todos a 40 studs mínimo,
	-- se reduce n al máximo que sí quepa: la densidad es un rango, no un
	-- fijo, y el suelo gana a la estética.
	local anchoUnitario = (anchoUtil - (n - 1) * GAP_ENTRE_EDIFICIOS) / n
	if anchoUnitario < ANCHO_MINIMO_EDIFICIO then
		n = math.max(1, math.floor((anchoUtil + GAP_ENTRE_EDIFICIOS) / (ANCHO_MINIMO_EDIFICIO + GAP_ENTRE_EDIFICIOS)))
		anchoUnitario = (anchoUtil - (n - 1) * GAP_ENTRE_EDIFICIOS) / n
	end

	-- El "largo" del edificio ocupa la dimensión perpendicular a la fila, con
	-- un margen mayor (15 studs) para que asome algo de suelo entre la fila y
	-- la acera opuesta — visualmente más rico que pegado a la otra acera.
	local largo = TAMANO_MANZANA - 2 * 15
	local alto = rng:NextNumber(cfg.alturaMin, cfg.alturaMax)

	local xManzana = xDeColumna(col)
	local zManzana = zDeFila(fila)

	local xCentro: number
	local zCentro: number
	if orientacion == "X" then
		-- Fila en X: los edificios se reparten a lo largo del eje X, comparten
		-- el mismo centro Z.
		xCentro = xManzana + margen + (indice - 0.5) * anchoUnitario + (indice - 1) * GAP_ENTRE_EDIFICIOS
		zCentro = zManzana + TAMANO_MANZANA / 2
	else
		-- Fila en Z: análogo.
		xCentro = xManzana + TAMANO_MANZANA / 2
		zCentro = zManzana + margen + (indice - 0.5) * anchoUnitario + (indice - 1) * GAP_ENTRE_EDIFICIOS
	end

	local color = paleta[rng:NextInteger(1, #paleta)] :: Color3

	return pieza(
		string.format("Edificio_%d_%d_%d", col, fila, indice),
		Vector3.new(anchoUnitario, alto, largo),
		Vector3.new(xCentro, Y_CALZADA + ACERA_ALTURA + alto / 2, zCentro),
		color,
		padre
	)
end

-- ¿Esta posición (x, z) cae dentro de un edificio? Para no plantar el
-- almacén o un destino encima de un muro. Compara en 2D — la altura del
-- edificio no importa para esto.
local function enManzana(x: number, z: number, col: number, fila: number): boolean
	local x0 = xDeColumna(col)
	local z0 = zDeFila(fila)
	return x >= x0 and x <= x0 + TAMANO_MANZANA and z >= z0 and z <= z0 + TAMANO_MANZANA
end

-- Encuentra la manzana que contiene un punto (x, z), o nil si está en una
-- calle. Útil para validar puntos fijos.
--
-- Devuelve una tabla en vez de una tupla porque la sintaxis `(number, number)?`
-- no es válida en Luau para tuplas nullables — y envolverlo en `{ col, fila }`
-- además deja la API más explícita en el llamador.
local function manzanaEn(x: number, z: number): { col: number, fila: number }?
	for col = 0, Grid.COLUMNAS - 1 do
		for fila = 0, Grid.FILAS - 1 do
			if enManzana(x, z, col, fila) then
				return { col = col, fila = fila }
			end
		end
	end
	return nil
end

-- Una zona: una serie de manzanas. Devuelve la lista de (col, fila).
local function manzanasDe(zona: string): { { col: number, fila: number } }
	local z = ZONAS[zona]
	local lista: { { col: number, fila: number } } = {}
	for col = z.colMin, z.colMax do
		for fila = z.filaMin, z.filaMax do
			table.insert(lista, { col = col, fila = fila })
		end
	end
	return lista
end

-- Puntos fijos del juego: los lee de Config. Si alguno cae dentro de una
-- manzana de su zona, ese edificio se retira y se avisa. La regla: el juego
-- siempre tiene prioridad sobre la estética.
local function validarPuntosFijos(edificios: { Part })
	-- Lista de (x, z) que el juego necesita tener despejados.
	local fijos: { { id: string, x: number, z: number } } = {
		{ id = "almacen", x = Config.ALMACEN_POS.X, z = Config.ALMACEN_POS.Z },
		{ id = "taller", x = Config.TALLER_POS.X, z = Config.TALLER_POS.Z },
	}
	for _, ruta in Config.RUTAS do
		table.insert(fijos, { id = "destino_" .. ruta.id, x = ruta.destino.X, z = ruta.destino.Z })
	end

	for _, punto in fijos do
		local mz = manzanaEn(punto.x, punto.z)
		if mz then
			for _, edificio in edificios do
				-- El nombre lleva el (col, fila) como "Edificio_col_fila_indice".
				local partes = string.split(edificio.Name, "_")
				if #partes >= 3 and tonumber(partes[2]) == mz.col and tonumber(partes[3]) == mz.fila then
					warn(
						string.format(
							"[MapBuilder] edificio %s retirado: el %s cae en (col=%d, fila=%d)",
							edificio.Name,
							punto.id,
							mz.col,
							mz.fila
						)
					)
					edificio:Destroy()
				end
			end
		end
	end
end

-- Verificación de conectividad por PathfindingService. Cara (~0,6-1,3 s por
-- path según DISENO-CIUDAD.md), así se hace UNA vez al construir y dentro
-- de pcall — si PathfindingService falla por cualquier motivo, el juego
-- sigue arrancando. Lo importante no es la métrica, es detectar **callejones
-- sin salida** antes de jugar: si una patrulla se queda atascada, el bug se
-- ve aquí, no en mitad de una ronda.
local function verificarConectividad(almacen: Vector3): { string }
	local issues: { string } = {}
	local ok, pathfinding = pcall(function()
		return game:GetService("PathfindingService")
	end)
	if not ok then
		return { "(PathfindingService no disponible, saltando verificación)" }
	end

	for _, solar in LOTES_VACANTES do
		local x = xDeColumna(solar.col) + TAMANO_MANZANA / 2
		local z = zDeFila(solar.fila) + TAMANO_MANZANA / 2
		local origen = Vector3.new(x, Y_CALZADA + 2, z)
		local okPath, path = pcall(function()
			local p = pathfinding:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				WaypointSpacing = 4,
			})
			p:ComputeAsync(origen, almacen)
			return p
		end)
		if not okPath then
			table.insert(
				issues,
				string.format("solar(%d,%d): PathfindingService error: %s", solar.col, solar.fila, tostring(path))
			)
		elseif (path :: any).Status ~= Enum.PathStatus.Success then
			table.insert(
				issues,
				string.format(
					"solar(%d,%d): NO hay camino al almacén (Status=%s)",
					solar.col,
					solar.fila,
					tostring((path :: any).Status)
				)
			)
		end
	end

	return issues
end

-- Punto de entrada. Crea un Model "Ciudad" con el mapa procedural y lo deja
-- como hijo del padre que se le pasa (en producción, workspace).
function MapBuilder.buildCiudad(padre: Instance): Model
	-- Re-seed aquí, no arriba: si el módulo se requería varias veces en la
	-- misma vida del proceso (no debería, pero por si), cada build empieza
	-- con la misma secuencia. La semilla es lo que hace el mapa aprendible.
	rng = Random.new(SEMILLA)

	local ciudad = Instance.new("Model")
	ciudad.Name = "Ciudad"

	local carpetaSuelo = Instance.new("Folder")
	carpetaSuelo.Name = "Suelo"
	carpetaSuelo.Parent = ciudad

	local carpetaCalles = Instance.new("Folder")
	carpetaCalles.Name = "Calles"
	carpetaCalles.Parent = ciudad

	local carpetaManzanas = Instance.new("Folder")
	carpetaManzanas.Name = "Manzanas"
	carpetaManzanas.Parent = ciudad

	local carpetaEdificios = Instance.new("Folder")
	carpetaEdificios.Name = "Edificios"
	carpetaEdificios.Parent = ciudad

	-- 1. Suelo base (red de seguridad)
	plantarSueloBase(carpetaSuelo)

	-- 2. El asfalto, de borde a borde. Lo que quede sin manzana encima es calle,
	-- incluidas las de los extremos: son las que permiten rodear la ciudad por fuera
	-- en vez de encontrarse el final del mundo.
	plantarCalzada(carpetaCalles)

	-- 3. Para cada zona, plantar sus manzanas con sus edificios
	local edificiosGenerados: { Part } = {}

	-- Helper: ¿es un solar? (plaza de la verde o un solar de ámbar/roja)
	local function esSolar(col: number, fila: number): boolean
		if col == PLAZA.col and fila == PLAZA.fila then
			return true
		end
		for _, solar in LOTES_VACANTES do
			if solar.col == col and solar.fila == fila then
				return true
			end
		end
		return false
	end

	for _, zonaNombre in { "verde", "ambar", "roja" } do
		for _, mz in manzanasDe(zonaNombre) do
			-- Solares y plaza: manzana vacía, sólo suelo y aceras. La
			-- diferencia entre un solar y la plaza es **la razón por la que
			-- está vacía**, no la geometría: la plaza es un atajo de
			-- aprendizaje (verde), los solares son vías de escape (ámbar y
			-- roja). La función mecánica es la misma.
			if esSolar(mz.col, mz.fila) then
				plantarLosaManzana(mz.col, mz.fila, carpetaManzanas)
				continue
			end

			plantarLosaManzana(mz.col, mz.fila, carpetaManzanas)
			local cfg = ZONA_CONFIG[zonaNombre]
			-- Densidad por rango, no fija: la semilla hace que sea estable
			-- entre partidas, pero cada manzana es distinta.
			local n = rng:NextInteger(cfg.densidadMin, cfg.densidadMax)

			if n == 1 then
				table.insert(edificiosGenerados, plantarEdificio(mz.col, mz.fila, 1, zonaNombre, carpetaEdificios))
			else
				-- En fila: crea los callejones visibles.
				for i = 1, n do
					table.insert(
						edificiosGenerados,
						plantarEdificioEnFila(mz.col, mz.fila, i, n, zonaNombre, carpetaEdificios)
					)
				end
			end
		end
	end

	-- 4. Validar que los puntos fijos del juego no quedan encerrados
	validarPuntosFijos(edificiosGenerados)

	-- 5. SIN HITOS DE ZONA. Se plantaron y se quitaron el mismo día. La idea era buena
	-- sobre el papel --tres torres en fila al salir de casa, cada una más lejos y más
	-- alta, para saber de un vistazo cuánto hay hasta cada zona-- y el mundo real la
	-- desmintió dos veces: la sonda las cazó tapando la fila de luces del barrio y
	-- tapándose entre ellas, y JJ pidió quitar TODO lo vertical.
	--
	-- Lo que las sustituye ya existía: las migas de pan marcan la ruta por la calle, y
	-- el mapa pequeño enseña dónde está cada cosa. Una torre no decía nada que esos
	-- dos no dijeran mejor.

	-- 6. Resumen de build — el desarrollador lo ve en la consola de Studio
	-- y verifica de un vistazo que la semilla y las densidades están dando
	-- lo que esperaba. Coste: despreciable (un par de cuentas).
	local totalEdificios = #edificiosGenerados
	local edificiosPorZona: { [string]: number } = { verde = 0, ambar = 0, roja = 0 }
	for _, e in edificiosGenerados do
		local partes = string.split(e.Name, "_")
		if #partes >= 3 then
			local col = tonumber(partes[2])
			local fila = tonumber(partes[3])
			if col and fila then
				for _, nombreZona in { "verde", "ambar", "roja" } do
					local z = ZONAS[nombreZona]
					if col >= z.colMin and col <= z.colMax and fila >= z.filaMin and fila <= z.filaMax then
						edificiosPorZona[nombreZona] = (edificiosPorZona[nombreZona] or 0) + 1
					end
				end
			end
		end
	end

	print(string.format("[MapBuilder] %d edificios plantados:", totalEdificios))
	print(string.format("  · verde: %d", edificiosPorZona.verde or 0))
	print(string.format("  · ámbar: %d", edificiosPorZona.ambar or 0))
	print(string.format("  · roja:  %d", edificiosPorZona.roja or 0))
	print(string.format("  · solares: %d (1 plaza verde + %d ámbar/roja)", 1 + #LOTES_VACANTES, #LOTES_VACANTES))

	-- 7. Verificación de conectividad: solar → almacén. Cara, dentro de pcall.
	local issues = verificarConectividad(Config.ALMACEN_POS)
	if #issues == 0 then
		print("[MapBuilder] verificación de conectividad: OK — todos los solares tienen camino al almacén")
	else
		warn("[MapBuilder] verificación de conectividad: " .. #issues .. " avisos")
		for _, msg in issues do
			warn("  · " .. msg)
		end
	end

	ciudad.Parent = padre
	return ciudad
end

return MapBuilder
