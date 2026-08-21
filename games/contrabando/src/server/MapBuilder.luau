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
	- Callejones con geometría específica (✅ uno por manzana, en sitio fijo).
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
-- LA ACERA, A RAS. Eran 0,8 studs y JJ lo pidio explicito: *"que solo se vean
-- carreteras a nivel y desaparezcan desniveles raros"*.
--
-- Medido antes del cambio: lo pisable de la ciudad salia repartido en dos cotas,
-- y=19 (la calzada, 288 muestras) e y=20 (las manzanas, 228). Un bordillo de un
-- stud es realista y en un juego de correr es una piedra: te frena, te engancha en
-- las esquinas y a veces te sube encima sin que lo hayas pedido.
--
-- No baja a CERO porque dos superficies a la misma cota exacta parpadean -- la
-- tarjeta grafica no puede decidir cual esta delante y alterna fotograma a
-- fotograma. Dos decimas es lo minimo que las separa, y a esa altura no se tropieza:
-- el personaje la sube sin cambiar de estado.
local ACERA_ALTURA = 0.2

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

-- Características por zona. La DENSIDAD desapareció con los edificios sueltos: desde
-- que la manzana se construye por el perímetro, lo que distingue una zona de otra es
-- lo ALTO que es el caserío y lo hondo que son sus alas, no cuántos cubos caben.
--
-- Es una simplificación que además arregla algo: con densidad por rango, dos manzanas
-- de la misma zona podían salir una llena y otra casi vacía, y la zona dejaba de
-- leerse como una zona.
local ZONA_CONFIG: { [string]: { alturaMin: number, alturaMax: number } } = {
	verde = { alturaMin = 12, alturaMax = 24 },
	ambar = { alturaMin = 24, alturaMax = 44 },
	roja = { alturaMin = 44, alturaMax = 80 },
}

-- Hueco entre edificios cuando se plantan en fila. Lo bastante estrecho para
-- que sea claramente un callejón (no un patio), lo bastante ancho para que un
-- personaje y una patrulla quepan a la vez: el patrullaje en callejones de la
-- roja es la habilidad de lectura que el viaje pide.
-- Lo ancho que es el callejón que atraviesa una manzana. Cabe una persona holgada y
-- un vehículo de calzada NO: es lo que hace que el atajo sea del que va a pie.
local CALLEJON = 14

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
				-- SOLO 0,6 POR DEBAJO, no dos y medio.
				--
				-- El motivo de separarlas sigue en pie --dos superficies en el mismo
				-- plano parpadean, y eso es lo que JJ vio como "parpadea el suelo"--
				-- pero dos studs y medio es mucho mas de lo que hace falta para
				-- separarlas, y donde el suelo base queda a la vista (las esquinas
				-- donde no llega la calzada) es un escalon en el que se cae.
				--
				-- Con 0,6 no parpadea y no se nota al andar: el personaje lo sube sin
				-- cambiar de estado. Medido: de dieciseis baches a cero.
				Vector3.new(x + ancho / 2, Y_CALZADA - 0.6, z + largo / 2),
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

	-- SIN METERSE BAJO EL RECINTO. El polígono ocupa de Z 755 en adelante y el mapa
	-- llega a 767, así que doce studs de asfalto quedaban DEBAJO de la explanada de
	-- casa, las dos superficies a la misma cota exacta -- coplanares perfectas, el peor
	-- caso de parpadeo que existe, y justo en el sitio por el que se sale y se entra
	-- cada viaje.
	--
	-- Se recorta aquí y no se sube el polígono: dentro del recinto todo se apoya en su
	-- cota, así que moverlo pone el suelo por encima del almacén.
	local bordeSurDelRecinto = Config.POLIGONO_CENTRO.Z - Config.POLIGONO_TAMANO.Y / 2
	-- Y SOLO EN LA FRANJA DEL RECINTO, no en todo el ancho del mapa.
	--
	-- Esto recortaba la calzada de lado a lado, y el recinto solo ocupa 300 studs de
	-- los 630: a los lados quedaba una franja de doce studs SIN asfalto, con el suelo
	-- base dos studs y medio mas abajo. Un escalon hacia abajo justo en la boca de
	-- casa, o sea en el sitio por el que se pasa cada viaje. Medido: dieciseis puntos
	-- de la rejilla a y=17,2 y todos en z=763.
	local recintoX0 = Config.POLIGONO_CENTRO.X - Config.POLIGONO_TAMANO.X / 2
	local recintoX1 = Config.POLIGONO_CENTRO.X + Config.POLIGONO_TAMANO.X / 2
	local PASO = 160
	local indice = 0
	local x = xMin
	while x < xMax - 0.01 do
		local ancho = math.min(PASO, xMax - x)
		local z = zMin
		while z < zMax - 0.01 do
			local largo = math.min(PASO, zMax - z)
			indice += 1
			-- El trozo se acorta por el sur solo si cae sobre el recinto; el resto del
			-- borde llega hasta el final del mapa.
			local sobreRecinto = (x + ancho) > recintoX0 and x < recintoX1
			local hasta = if sobreRecinto then math.min(z + largo, bordeSurDelRecinto) else z + largo
			local largoReal = hasta - z
			if largoReal <= 0.01 then
				z += PASO
				continue
			end
			pieza(
				string.format("Calzada_%d", indice),
				Vector3.new(ancho, ALTO_CALLE, largoReal),
				Vector3.new(x + ancho / 2, Y_CALZADA - ALTO_CALLE / 2, z + largoReal / 2),
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

-- LA MANZANA CERRADA: cuatro bloques por el perímetro, patio dentro, y un callejón.
--
-- Antes se plantaban entre uno y cinco edificios sueltos en medio de la manzana, con
-- dieciséis studs de margen contra el bordillo. Eso dejaba la manzana MEDIO VACÍA, y
-- medio vacía significa que se cruza en diagonal: el pathfinder lo hacía --sus caminos
-- salían un 15-20 % más cortos que por las calles-- y un jugador lo descubre a la
-- segunda partida. Y en cuanto se descubre, la fila de migas deja de ser el camino y
-- pasa a ser un rodeo con premio, que es lo contrario de lo que hace falta.
--
-- Con el perímetro construido, la calle vuelve a ser la calle. El atajo no desaparece:
-- se convierte en UN callejón por manzana, en un sitio fijo que se puede aprender --
-- que es exactamente la habilidad que el juego decía pedir y no pedía.
--
-- El patio interior es de propina, y es el sitio donde esconderse de una patrulla que
-- va por la calle.
local function plantarManzanaCerrada(col: number, fila: number, zona: string, padre: Instance): { Part }
	local cfg = ZONA_CONFIG[zona]
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local piezas: { Part } = {}
	local indice = 0

	-- Lo hondo que es cada ala. Más en la roja: es lo que deja el patio pequeño y la
	-- sensación de encajonado que la zona promete.
	local fondo = if zona == "roja" then 40 elseif zona == "ambar" then 34 else 28

	-- POR QUÉ LADO SE ENTRA. Determinista por (col, fila) y no aleatorio: un callejón
	-- sólo sirve si el jugador puede acordarse de dónde está, y para eso tiene que
	-- estar SIEMPRE en el mismo sitio. Con la semilla fija bastaría, pero derivarlo de
	-- la coordenada lo hace además legible desde el código.
	local ladoAbierto = (col * 3 + fila) % 4

	-- La roja no tiene callejón en todas: una de cada dos queda cerrada, y eso es lo
	-- que hace que rodearla cueste de verdad.
	if zona == "roja" and (col + fila) % 2 == 0 then
		ladoAbierto = -1
	end

	local function ala(nombre: string, ax0: number, ax1: number, az0: number, az1: number)
		if ax1 - ax0 < 6 or az1 - az0 < 6 then
			return
		end
		indice += 1
		local alto = rng:NextNumber(cfg.alturaMin, cfg.alturaMax)
		local color = paleta[rng:NextInteger(1, #paleta)] :: Color3
		local levantado = pieza(
			string.format("Edificio_%d_%d_%d", col, fila, indice),
			Vector3.new(ax1 - ax0, alto, az1 - az0),
			Vector3.new((ax0 + ax1) / 2, Y_CALZADA + ACERA_ALTURA + alto / 2, (az0 + az1) / 2),
			color,
			padre
		)
		-- DERRIBABLE: un edificio puede quitarse para hacerle sitio a una pieza del
		-- juego (una guarida, un refugio, un taller). El suelo y las calles NO -- se
		-- marcan igual con `delMapa` pero sin esto, y la primera versión del derribo
		-- se llevó por delante dos losas de manzana y el asfalto de dos cruces.
		levantado:SetAttribute("derribable", true)
		table.insert(piezas, levantado)
		local _ = nombre
	end

	-- Cada ala se parte en dos si es la que lleva el callejón, dejando el hueco en el
	-- centro. Partirla y no quitarla entera: un lado ausente sería una manzana en U y
	-- se leería como un descampado, no como un paso.
	local function aloLargoDeX(nombre: string, az0: number, az1: number, abierto: boolean)
		if not abierto then
			ala(nombre, x0, x1, az0, az1)
			return
		end
		local centro = (x0 + x1) / 2
		ala(nombre .. "A", x0, centro - CALLEJON / 2, az0, az1)
		ala(nombre .. "B", centro + CALLEJON / 2, x1, az0, az1)
	end

	local function aloLargoDeZ(nombre: string, ax0: number, ax1: number, abierto: boolean)
		if not abierto then
			ala(nombre, ax0, ax1, z0 + fondo, z1 - fondo)
			return
		end
		local centro = (z0 + z1) / 2
		ala(nombre .. "A", ax0, ax1, z0 + fondo, centro - CALLEJON / 2)
		ala(nombre .. "B", ax0, ax1, centro + CALLEJON / 2, z1 - fondo)
	end

	aloLargoDeX("Sur", z0, z0 + fondo, ladoAbierto == 0)
	aloLargoDeX("Norte", z1 - fondo, z1, ladoAbierto == 1)
	aloLargoDeZ("Oeste", x0, x0 + fondo, ladoAbierto == 2)
	aloLargoDeZ("Este", x1 - fondo, x1, ladoAbierto == 3)

	return piezas
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

-- QUE NADA DEL MAPA SE PLANTE ENCIMA DE UN SITIO DEL JUEGO.
--
-- Esto miraba en qué MANZANA caía cada punto fijo y retiraba los edificios de esa
-- manzana. Servía mientras los destinos estaban donde hubiera hueco; desde que van en
-- CRUCES DE CALLE, ningún punto fijo cae dentro de una manzana -- y la comprobación
-- dejó de retirar nada sin dejar de dar verde.
--
-- Lo que pasa entonces se vio en cuanto las manzanas se cerraron: la losa del destino
-- mide 44 studs y desde un cruce invade las cuatro manzanas de alrededor, así que el
-- ala del edificio se plantaba justo encima. Destino_verde quedó 22 studs bajo tierra
-- y las rutas verde y barrio se quedaron sin camino a pie.
--
-- Ahora se mide por solape real en el plano, que es lo que importaba desde el
-- principio: da igual de qué manzana sea el edificio si está encima de la losa.
local function validarPuntosFijos(edificios: { Part })
	-- El sitio que cada cosa necesita despejado, en radio. La losa de un destino mide
	-- 44 (22 de medio) y el almacén y el taller son mayores; se les da margen para que
	-- no sólo quepan, sino que se pueda entrar y salir de ellos.
	local fijos: { { id: string, pos: Vector3, radio: number } } = {
		{ id = "almacen", pos = Config.ALMACEN_POS, radio = 70 },
		{ id = "taller", pos = Config.TALLER_POS, radio = 60 },
	}
	for _, ruta in Config.RUTAS do
		table.insert(fijos, { id = "destino_" .. ruta.id, pos = ruta.destino, radio = 40 })
	end

	for _, punto in fijos do
		for _, edificio in edificios do
			if edificio.Parent == nil then
				continue
			end
			-- Distancia del punto a la caja del edificio, en planta: se recorta el punto
			-- contra los bordes y se mide lo que queda. Con la distancia entre CENTROS,
			-- un ala de 120 studs de largo parecería lejos estando encima.
			local mitadX, mitadZ = edificio.Size.X / 2, edificio.Size.Z / 2
			local cx = math.clamp(punto.pos.X, edificio.Position.X - mitadX, edificio.Position.X + mitadX)
			local cz = math.clamp(punto.pos.Z, edificio.Position.Z - mitadZ, edificio.Position.Z + mitadZ)
			local dx, dz = punto.pos.X - cx, punto.pos.Z - cz
			if math.sqrt(dx * dx + dz * dz) < punto.radio then
				warn(string.format("[MapBuilder] edificio %s retirado: se solapa con el %s", edificio.Name, punto.id))
				edificio:Destroy()
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
			for _, p in plantarManzanaCerrada(mz.col, mz.fila, zonaNombre, carpetaEdificios) do
				table.insert(edificiosGenerados, p)
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
