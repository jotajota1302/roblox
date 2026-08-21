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

local Bounds = require(game.ReplicatedStorage.Shared.Bounds)
local StreetProps = require(script.Parent.StreetProps)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Districts = require(game.ReplicatedStorage.Shared.Districts)
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

-- LO QUE LA ACERA SE LLEVA POR CADA LADO antes de que empiece a construirse nada.
--
-- Estaba escrito dentro de `plantarManzanaCerrada`, que era su unico usuario. Desde
-- que cada manzana se construye a su manera lo necesitan los ocho usos, y dos ochos
-- en dos sitios es como una fachada acaba dos studs por delante de la de al lado.
--
-- Los ocho salen de un reparto: bordillo en los dos primeros studs, mobiliario a los
-- cuatro, fachada a los ocho. Retranquear abrio la franja que le faltaba a la ciudad
-- -- antes los edificios arrancaban en el borde exacto de la manzana, o sea con la
-- fachada pegada al bordillo, y las farolas y los arboles de la acera acababan
-- DENTRO de los edificios (97 pares de piezas solapadas, los canto la sonda).
local ACERA_ANCHO = 8

-- LA COTA POR LA QUE SE ANDA, y todo lo que se planta se cuelga de ella. Antes el
-- mapa vivía en y=0 y el resto del juego en 19,2, porque el mapa se generaba para
-- probarse solo y el recinto estaba puesto sobre un terreno ajeno. Tener dos alturas
-- distintas para el mismo suelo es exactamente cómo aparece un canto de tres studs
-- que corta el navmesh sin que nada dé error.
local Y_CALZADA = Grid.Y

-- QUE ES CADA MANZANA: en `shared/Districts.luau`, no aqui.
--
-- Aqui vivian tres tablas --las zonas, la plaza y los solares-- y las tres decian lo
-- mismo desde tres sitios: cual de las doce manzanas era especial. Con el mapa de
-- usos hay UNA sola respuesta por manzana y se puede probar sin abrir Studio, que es
-- la regla de esta casa: el plano es un dato puro y esto solo lo planta.
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
	-- LAS AFUERAS, MAS BAJAS QUE LA VERDE. Es lo que hace que se lean como afueras
	-- desde dentro de la ciudad: el caserio BAJA al alejarse en vez de subir, y esa
	-- silueta descendente dice "aqui se acaba" sin ningun cartel.
	afueras = { alturaMin = 9, alturaMax = 18 },
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
-- La pintura de la calzada. Blanco sucio y no blanco puro: el blanco puro sobre
-- asfalto oscuro es el contraste más alto que hay en pantalla y se lleva la mirada
-- que tiene que ir a los recogibles y a los ladrones. Una marca vial dice "esto es
-- una carretera" con el rabillo del ojo; no hace falta que grite.
local COLOR_LINEA = Color3.fromRGB(198, 194, 182)
-- El bordillo, un tono más claro que la acera para que el canto se lea desde lejos.
-- La acera sólo sube 0,2 studs --a propósito, para que no se tropiece-- así que la
-- separación entre calzada y acera la tiene que hacer el COLOR, no la altura.
local COLOR_BORDILLO = Color3.fromRGB(176, 174, 168)

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
	-- Las afueras, en tonos de ladrillo y chapa: es lo que separa un poligono
	-- industrial de un barrio a doscientos studs de distancia, mucho antes de que se
	-- distinga una nave de una casa.
	afueras = {
		Color3.fromRGB(122, 100, 84),
		Color3.fromRGB(104, 96, 88),
		Color3.fromRGB(112, 86, 72),
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

-- Decorado: sin cuerpo y sin consultas. Es la primera regla de `StreetProps` y vale
-- igual aqui -- un rayo que se para en un toldo devuelve "el suelo esta a nueve
-- studs" y descarta el sitio para todo lo que se siembre despues.
local function adorno(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
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
	-- DE `Bounds.mundo()` Y NO DE `Grid.limites()`, y la diferencia es un agujero: la
	-- retícula de calles acaba en z=767 pero el RECINTO del almacén cuelga hasta 905.
	-- Medido cuando salía de la retícula: 1.444 puntos del mapa sin suelo debajo,
	-- todos rodeando el sitio donde empieza cada partida.
	local xMin, xMax, zMin, zMax = Bounds.mundo()
	local MARGEN = 60
	xMin, xMax, zMin, zMax = xMin - MARGEN, xMax + MARGEN, zMin - MARGEN, zMax + MARGEN

	-- UNA SOLA PIEZA, Y BIEN ABAJO. Las dos cosas por el mismo motivo: *"sigo viendo
	-- el suelo extraño con cuadrados solapados"* (JJ), y era una regresión mía.
	--
	-- Esto eran piezas de 200 con la cara a 0,1 studs por debajo de la calzada, que
	-- va en piezas de 160. Dos superficies grandes separadas 0,1 studs PELEAN POR EL
	-- Z-BUFFER: a la distancia a la que se juega, la tarjeta no puede decidir cuál
	-- está delante y va enseñando trozos de una y de otra. Como las dos rejillas
	-- tienen pasos distintos, sus juntas no coinciden y el resultado es exactamente
	-- lo que describió: cuadrados solapados.
	--
	-- El 0,1 lo puse yo el 20/08 para matar unos baches, sin caer en que la
	-- separación era justo lo que evitaba el parpadeo. Los baches ya no dependen de
	-- esta cota --se arreglaron recortando la calzada sólo en la banda del recinto--
	-- así que se puede bajar de nuevo, y con 2,4 studs no hay pelea posible.
	--
	-- Y en UNA pieza porque una pieza no tiene juntas. Hoy mide 1.022 x 851 studs y el
	-- limite de Roblox son 2.048 por eje, asi que sobra sitio -- pero ese "sobra sitio"
	-- es una afirmacion con fecha de caducidad, y ya caduco una: la RED DE SEGURIDAD
	-- de `CityBuilder` era una pieza por el mismo motivo, la ciudad crecio a 902 de
	-- ancho y su caja paso de 2.048; Roblox la recorto sin decir nada y dejo 27 studs
	-- sin red en cada borde. Por eso esto avisa en vez de fiarse: el dia que el mapa
	-- llegue ahi, saldra en la consola en vez de aparecer como un agujero.
	if xMax - xMin > 2040 or zMax - zMin > 2040 then
		warn(
			string.format(
				"[MapBuilder] el suelo base pide %.0f x %.0f: pasa del limite de 2048 por eje y Roblox lo recortara. Hay que plantarlo por baldosas, como la red de CityBuilder.",
				xMax - xMin,
				zMax - zMin
			)
		)
	end
	pieza(
		"SueloBase",
		Vector3.new(xMax - xMin, 1, zMax - zMin),
		Vector3.new((xMin + xMax) / 2, Y_CALZADA - 3, (zMin + zMax) / 2),
		COLOR_SUELO_BASE,
		padre
	)
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
	-- HASTA DONDE LLEGA EL SUELO BASE, no hasta el último bordillo.
	--
	-- Antes cubría sólo `Grid.limites()`, así que en los 60 studs de margen de las
	-- afueras lo que se pisaba era el suelo base -- tres studs más abajo y de otro
	-- color. Un escalón y un cambio de material justo donde uno se asoma al borde del
	-- mapa. Cubriendo lo mismo que él, el suelo base deja de verse por completo:
	-- vuelve a ser lo que dice su comentario, una red por si algo falla.
	local xMin, xMax, zMin, zMax = Bounds.mundo()
	local MARGEN = 60
	xMin, xMax, zMin, zMax = xMin - MARGEN, xMax + MARGEN, zMin - MARGEN, zMax + MARGEN

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

-- LAS MARCAS VIALES: lo que convierte una explanada de asfalto en una calle.
--
-- *"Las calles ya deberían ser carreteras... podríamos trabajar el mapa para que sean
-- carriles reales"* (JJ). Y el diagnóstico es correcto: el asfalto de este mapa es
-- una alfombra continua con manzanas encima, así que técnicamente son calles, pero no
-- se LEEN como calles -- no hay nada que diga por dónde va el tráfico ni dónde acaba
-- la calzada. Un suelo gris uniforme es un suelo, no una ciudad.
--
-- Dos marcas y sobra: el EJE discontinuo por el centro y las dos líneas de BORDE
-- continuas. Es la gramática mínima de una carretera y la reconoce cualquiera sin
-- mirarla. Pasos de cebra, flechas y carriles de giro vendrían después, si el mapa
-- llega a merecerlos.
--
-- El eje NO SE PINTA EN LOS CRUCES. Una raya cruzando otra en perpendicular no existe
-- en ninguna calle de verdad y en pantalla se lee como suciedad, no como señal. Y de
-- paso deja los cruces despejados, que es donde el jugador tiene que decidir.
local function plantarMarcasViales(padre: Instance)
	local medio = ANCHO_CALLE / 2
	local xMin, xMax, zMin, zMax = Grid.limites()
	-- Trazo y hueco de una discontinua normal. Con el trazo más corto que el hueco se
	-- lee como "puedes cruzar", que es lo que toca en una ciudad.
	local TRAZO, HUECO = 6, 10
	-- Por encima del asfalto lo justo para que no peleen por el z-buffer. Es la misma
	-- lección que el suelo base acaba de pagar: dos superficies casi coplanares
	-- parpadean, y 0,08 studs ya es suficiente separación para una pieza tan fina.
	local SUBE = 0.08
	local ALTO = 0.12
	local ANCHO_RAYA = 0.9
	local indice = 0

	local function raya(tamano: Vector3, centro: Vector3)
		indice += 1
		local m = pieza(string.format("Marca_%d", indice), tamano, centro, COLOR_LINEA, padre)
		-- Ni colisión ni consultas: es pintura. Que un raycast del juego se pare en
		-- una raya de la carretera daría cotas 0,2 studs más altas en unos sitios que
		-- en otros, y de ahí salen las sondas que fallan sin motivo aparente.
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.CastShadow = false
	end

	local y = Y_CALZADA + SUBE + ALTO / 2

	-- ¿Cae este punto dentro de un cruce? Se pregunta por el eje contrario: para una
	-- calle vertical, si su Z está dentro del ancho de alguna calle horizontal.
	local function enCruceZ(z: number): boolean
		for j = Grid.FILA_MIN, Grid.FILA_MAX do
			if math.abs(z - Grid.zDeCalle(j)) < medio + 2 then
				return true
			end
		end
		return false
	end
	local function enCruceX(x: number): boolean
		for i = Grid.COL_MIN, Grid.COL_MAX do
			if math.abs(x - Grid.xDeCalle(i)) < medio + 2 then
				return true
			end
		end
		return false
	end

	-- CALLES VERTICALES (corren en Z)
	for i = Grid.COL_MIN, Grid.COL_MAX do
		local x = Grid.xDeCalle(i)
		local z = zMin
		while z < zMax do
			if not enCruceZ(z + TRAZO / 2) then
				raya(Vector3.new(ANCHO_RAYA, ALTO, TRAZO), Vector3.new(x, y, z + TRAZO / 2))
			end
			z += TRAZO + HUECO
		end
		-- Y los dos bordes: las lineas que dicen donde acaba el asfalto.
		--
		-- POR TRAMOS ENTRE CRUCES, no de una pieza. De una pieza cruzaban por encima
		-- de las lineas de las calles perpendiculares, a la MISMA cota, y eso son
		-- superficies coplanares -- 176 pares, canto la sonda del mundo. Ademas de
		-- parpadear estaba mal dibujado: en una calle de verdad la linea de borde se
		-- interrumpe en el cruce, porque por ahi se cruza.
		for _, lado in { -1, 1 } do
			local bx = x + lado * (medio - 1.6)
			local desde = zMin
			for j = Grid.FILA_MIN, Grid.FILA_MAX do
				local corte = Grid.zDeCalle(j)
				local hasta = corte - medio
				if hasta - desde > 1 then
					raya(Vector3.new(ANCHO_RAYA, ALTO, hasta - desde), Vector3.new(bx, y, (desde + hasta) / 2))
				end
				desde = corte + medio
			end
			if zMax - desde > 1 then
				raya(Vector3.new(ANCHO_RAYA, ALTO, zMax - desde), Vector3.new(bx, y, (desde + zMax) / 2))
			end
		end
	end

	-- CALLES HORIZONTALES (corren en X)
	for j = Grid.FILA_MIN, Grid.FILA_MAX do
		local z = Grid.zDeCalle(j)
		local x = xMin
		while x < xMax do
			if not enCruceX(x + TRAZO / 2) then
				raya(Vector3.new(TRAZO, ALTO, ANCHO_RAYA), Vector3.new(x + TRAZO / 2, y, z))
			end
			x += TRAZO + HUECO
		end
		for _, lado in { -1, 1 } do
			local bz = z + lado * (medio - 1.6)
			local desde = xMin
			for i = Grid.COL_MIN, Grid.COL_MAX do
				local corte = Grid.xDeCalle(i)
				local hasta = corte - medio
				if hasta - desde > 1 then
					raya(Vector3.new(hasta - desde, ALTO, ANCHO_RAYA), Vector3.new((desde + hasta) / 2, y, bz))
				end
				desde = corte + medio
			end
			if xMax - desde > 1 then
				raya(Vector3.new(xMax - desde, ALTO, ANCHO_RAYA), Vector3.new((desde + xMax) / 2, y, bz))
			end
		end
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
local function plantarLosaManzana(col: number, fila: number, padre: Instance, pintura: Instance)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local alto = ACERA_ALTURA + 0.3
	pieza(
		string.format("Manzana_%d_%d", col, fila),
		Vector3.new(x1 - x0, alto, z1 - z0),
		Vector3.new((x0 + x1) / 2, Y_CALZADA + ACERA_ALTURA - alto / 2, (z0 + z1) / 2),
		COLOR_ACERA,
		padre
	)

	-- EL BORDILLO, y es pintura, no un escalón.
	--
	-- La losa sólo sube 0,2 studs sobre el asfalto -- lo pidió JJ explícito el 20/08
	-- (*"que sólo se vean carreteras a nivel"*) y no se toca: un bordillo de verdad
	-- te frena en cada esquina, y este juego consiste en desplazarse. Pero a 0,2
	-- studs el canto no se ve desde la altura de la cámara, así que la frontera entre
	-- calzada y acera no existía para el ojo: se andaba por una superficie gris que
	-- cambiaba de tono sin motivo aparente.
	--
	-- Lo resuelve el COLOR. Una banda de dos studs, un tono más claro, por los cuatro
	-- lados: desde arriba se lee como bordillo aunque no lo sea, y sigue sin frenar a
	-- nadie. Es el mismo truco que el paso de la acera -- la información la da el
	-- material, no la geometría.
	local GRUESO = 2
	-- APOYADO SOBRE la cara de la acera, no hundido en ella. Con el centro 0,05 por
	-- DEBAJO su cara quedaba a 0,01 de la losa, y la sonda de parpadeo salta a 0,02
	-- -- con razon: a esa distancia dos superficies pelean por el z-buffer y se ve
	-- exactamente el defecto que este bordillo venia a evitar. Apoyado, la cara sube
	-- a 0,06 sobre la acera: separacion de sobra para la tarjeta grafica, y un
	-- escalon que ni se nota al andar (el personaje sube 0,2 sin cambiar de estado).
	local y = Y_CALZADA + ACERA_ALTURA
	-- LOS DE LOS LADOS, ACORTADOS EN LAS ESQUINAS. Las cuatro bandas a la misma cota
	-- se cruzaban en las cuatro esquinas de cada manzana: 48 pares coplanares, que es
	-- otra vez el parpadeo. Las de arriba y abajo cubren todo el ancho y las de los
	-- lados se meten entre ellas, como una moldura.
	local largoLateral = (z1 - z0) - 2 * GRUESO
	local bordes = {
		{ Vector3.new(x1 - x0, 0.12, GRUESO), Vector3.new((x0 + x1) / 2, y, z0 + GRUESO / 2) },
		{ Vector3.new(x1 - x0, 0.12, GRUESO), Vector3.new((x0 + x1) / 2, y, z1 - GRUESO / 2) },
		{ Vector3.new(GRUESO, 0.12, largoLateral), Vector3.new(x0 + GRUESO / 2, y, (z0 + z1) / 2) },
		{ Vector3.new(GRUESO, 0.12, largoLateral), Vector3.new(x1 - GRUESO / 2, y, (z0 + z1) / 2) },
	}
	for k, borde in bordes do
		local b = pieza(string.format("Bordillo_%d_%d_%d", col, fila, k), borde[1], borde[2], COLOR_BORDILLO, pintura)
		-- Como las marcas viales: es pintura. Sin colisión y sin consultas, para que
		-- ningún raycast del juego se pare aquí y devuelva una cota distinta según en
		-- qué stud caiga.
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
	end
end

-- HACIA QUE CALLE DA UN EDIFICIO. Es lo que hace falta para saber en que cara va el
-- portal, y sin ello no hay identidad posible: un portal en la cara de atras --la que
-- da al patio-- no lo ve nadie nunca, y ademas dice lo contrario de lo que tiene que
-- decir.
--
-- Se elige la calle mas cercana, igual que `Grid.aceraDe`, y por el mismo motivo: un
-- edificio en el perimetro de una manzana tiene su calle a un lado y el patio al
-- otro, asi que "la mas cercana" es siempre la de su fachada.
local function caraALaCalle(cx: number, cz: number): Vector3
	local mejorX, distX = 0, math.huge
	for i = Grid.COL_MIN, Grid.COL_MAX do
		local d = math.abs(cx - Grid.xDeCalle(i))
		if d < distX then
			distX, mejorX = d, Grid.xDeCalle(i)
		end
	end
	local mejorZ, distZ = 0, math.huge
	for j = Grid.FILA_MIN, Grid.FILA_MAX do
		local d = math.abs(cz - Grid.zDeCalle(j))
		if d < distZ then
			distZ, mejorZ = d, Grid.zDeCalle(j)
		end
	end
	if distX <= distZ then
		return Vector3.new(if mejorX >= cx then 1 else -1, 0, 0)
	end
	return Vector3.new(0, 0, if mejorZ >= cz then 1 else -1)
end

-- UN EDIFICIO: la caja, y las cuatro cosas que la convierten en un edificio.
--
-- Es la unidad de construccion de toda la ciudad -- un ala de manzana, una torre, una
-- nave del poligono. Vive fuera de `plantarManzanaCerrada` desde que cada manzana se
-- construye a su manera: con la funcion metida dentro, cada uso nuevo se traia una
-- copia de las bandas, y la tercera copia es donde una deja de estar de acuerdo con
-- las otras.
--
-- QUE HACE QUE UNA CAJA SE LEA COMO UN EDIFICIO (22/08). *"Quiero un mapa muy
-- trabajado... que los edificios tengan identidad"* (JJ). Hasta hoy un edificio era
-- una caja de color con unas franjas de cristal, y con eso una ciudad entera se ve
-- como un monton de cajas: no hay arriba ni abajo, no hay delante ni detras, y no hay
-- forma de decir "el de la puerta verde" porque ninguno tiene puerta.
--
-- Son CUATRO piezas mas por edificio, elegidas por lo que aportan y no por realismo:
--
--   · EL ZOCALO. Los bajos, en otro tono y sobresaliendo medio stud. Es lo que separa
--     el suelo de la fachada, y de un vistazo dice donde termina la calle. Sin el, un
--     bloque de cuarenta studs parece empezar en el cielo.
--   · EL PORTAL, en la cara que da a la calle. Es la pieza mas barata y la que mas
--     dice: convierte "una caja" en "una casa", y sobre todo da ORIENTACION -- desde
--     dentro de una manzana se sabe hacia donde esta la calle mirando las puertas.
--   · LA CORNISA. Un remate que vuela un stud sobre la coronacion. Recorta la silueta
--     contra el cielo, que es donde el ojo lee la ciudad de lejos.
--   · LA AZOTEA, solo en los altos: la caja del ascensor. Rompe el canto plano y hace
--     que dos torres de la misma altura no se vean como la misma torre.
--
-- CADA UNA CON SU MEDIDA SACADA DEL GENERADOR, y eso no es capricho: las cuatro alas
-- de una manzana se tocan en las esquinas, asi que con la misma altura de zocalo sus
-- caras superiores caerian a la cota EXACTA y parpadearian. Es el mismo motivo por el
-- que las bandas de ventanas llevan altura de planta propia, y ya se pago una vez con
-- 96 pares coplanares.
--
-- `estilo` cambia lo que se le cuelga: "nave" no tiene portal de persona sino una
-- puerta de carga ancha, y no lleva bandas de pisos porque una nave no tiene pisos.
local function edificio(
	nombre: string,
	ax0: number,
	ax1: number,
	az0: number,
	az1: number,
	alto: number,
	color: Color3,
	padre: Instance,
	estilo: string?
): Part
	local cual = estilo or "vivienda"
	local ancho, fondo = ax1 - ax0, az1 - az0
	local cx, cz = (ax0 + ax1) / 2, (az0 + az1) / 2
	local base = Y_CALZADA + ACERA_ALTURA

	-- UN TONO PROPIO POR EDIFICIO, dentro de la paleta de su zona. La paleta tiene
	-- tres colores y una manzana tiene cuatro alas: sin esto, dos alas contiguas salen
	-- del mismo color una de cada tres veces y se funden en un solo bloque. Un 10 % de
	-- desvio no cambia el color de la zona, y si separa a dos vecinos.
	local hacia = if rng:NextNumber() < 0.5 then Color3.fromRGB(18, 18, 22) else Color3.fromRGB(228, 226, 220)
	local tono = color:Lerp(hacia, rng:NextNumber(0, 0.1))

	local levantado = pieza(nombre, Vector3.new(ancho, alto, fondo), Vector3.new(cx, base + alto / 2, cz), tono, padre)
	-- DERRIBABLE: un edificio puede quitarse para hacerle sitio a una pieza del
	-- juego (una guarida, un refugio, un taller). El suelo y las calles NO -- se
	-- marcan igual con `delMapa` pero sin esto, y la primera versión del derribo
	-- se llevó por delante dos losas de manzana y el asfalto de dos cruces.
	levantado:SetAttribute("derribable", true)

	-- LAS MOLDURAS CUELGAN DEL EDIFICIO, no de la carpeta, y esa linea de mas es la
	-- diferencia entre una ciudad y una ciudad con basura flotando.
	--
	-- Un edificio se DERRIBA: `validarPuntosFijos` retira el que pisa un destino, y
	-- `CityBuilder` retira los que estorban a una guarida o a un refugio. Las dos
	-- llaman a `Destroy()` sobre la pieza que devuelve esta funcion, que hasta el
	-- 22/08 era la unica que existia. Con zocalo, portal, marquesina, cornisa, azotea
	-- y bandas plantados como HERMANOS, derribar el bloque dejaba todo eso en el aire:
	-- medido en una partida real, NUEVE edificios retirados y 79 piezas huerfanas
	-- flotando -- una puerta a metro y medio del suelo con su tejadillo, y seis
	-- laminas de cristal apiladas donde no habia nada.
	--
	-- Como hijos, se van con el. Y no hace falta acordarse en ninguno de los dos sitios
	-- que derriban, que es lo que importa: quien anada el septimo adorno manana no
	-- tiene que saber que esto existe.
	local fachada = caraALaCalle(cx, cz)
	-- Lo ancha que es la cara que da a la calle, y por que eje sale. Con la fachada
	-- en X, la cara mide lo que el FONDO del edificio.
	local enX = fachada.X ~= 0
	local anchoCara = if enX then fondo else ancho

	-- EL ZOCALO. Nunca mas de un tercio del edificio: en una casa baja de la verde, un
	-- zocalo de seis studs sobre doce seria medio edificio.
	local altoZocalo = math.min(alto / 3, 5.4 + rng:NextNumber(0, 2.1))
	if altoZocalo > 1.5 then
		local zocalo = pieza(
			nombre .. "_Z",
			Vector3.new(ancho + 1, altoZocalo, fondo + 1),
			Vector3.new(cx, base + altoZocalo / 2, cz),
			tono:Lerp(Color3.fromRGB(40, 40, 46), 0.45),
			levantado
		)
		-- Sin cuerpo: el zocalo vuela medio stud sobre la fachada y con colision seria
		-- un escalon invisible en el que se engancha todo el que roce la pared.
		adorno(zocalo)
	end

	-- EL PORTAL, o la puerta de carga si es una nave. Va 0,3 studs por delante de la
	-- fachada -- lo justo para que no comparta cara con ella y no parpadee.
	local esNave = cual == "nave"
	local altoPuerta = if esNave then math.min(alto * 0.62, 13) else math.min(alto * 0.5, 8.4)
	local anchoPuerta = if esNave then math.min(anchoCara * 0.6, 26) else math.min(anchoCara * 0.34, 9)
	if altoPuerta > 3 and anchoPuerta > 3 then
		local colorPuerta = if esNave
			then Color3.fromRGB(150, 148, 142)
			else tono:Lerp(Color3.fromRGB(26, 24, 30), 0.72)
		local tamano = if enX
			then Vector3.new(0.6, altoPuerta, anchoPuerta)
			else Vector3.new(anchoPuerta, altoPuerta, 0.6)
		local centro = Vector3.new(cx, base + altoPuerta / 2, cz)
			+ fachada * ((if enX then ancho / 2 else fondo / 2) + 0.3)
		adorno(pieza(nombre .. "_P", tamano, centro, colorPuerta, levantado))

		-- Y LA MARQUESINA ENCIMA, que es lo que hace que la puerta se vea desde un
		-- angulo. Una pieza plana pegada a la pared desaparece en cuanto se mira de
		-- lado; un voladizo de stud y medio proyecta sombra y se sigue leyendo.
		local vuelo = 1.6
		local techoTam = if enX
			then Vector3.new(vuelo, 0.5, anchoPuerta + 2.4)
			else Vector3.new(anchoPuerta + 2.4, 0.5, vuelo)
		local techoPos = Vector3.new(cx, base + altoPuerta + 0.4, cz)
			+ fachada * ((if enX then ancho / 2 else fondo / 2) + vuelo / 2)
		adorno(pieza(nombre .. "_M", techoTam, techoPos, Color3.fromRGB(64, 66, 74), levantado))
	end

	-- LA CORNISA: el remate contra el cielo.
	--
	-- CORONA POR ENCIMA, medio stud por fuera del edificio, y no enrasada con el. La
	-- primera version la puso a ras --centro en `alto - altoCornisa/2`-- y su cara
	-- superior caia en la cota EXACTA del bloque: cincuenta y siete pares coplanares
	-- de golpe, y los canto la sonda del mundo antes de abrir Studio. Un remate que no
	-- sobresale ademas no es un remate; es una raya pintada.
	--
	-- Y VUELA MEDIO STUD POR LADO, NO NUEVE DECIMAS. Con 0,9 quedaba un par coplanar
	-- --dos alas de la misma manzana cuyas alturas de generador cayeron a menos de
	-- quince centesimas-- porque dos cornisas contiguas se rozaban 1,8 studs y eso
	-- supera el solape minimo que la sonda considera parpadeo. Con medio stud el roce
	-- es de uno exacto, o sea justo por debajo del umbral, y ademas es el mismo vuelo
	-- que el zocalo: las dos molduras del edificio alineadas se leen mejor que dos
	-- vuelos distintos.
	local altoCornisa = 1 + rng:NextNumber(0, 0.9)
	adorno(
		pieza(
			nombre .. "_C",
			Vector3.new(ancho + 1, altoCornisa, fondo + 1),
			Vector3.new(cx, base + alto + 0.6 - altoCornisa / 2, cz),
			tono:Lerp(Color3.fromRGB(34, 34, 40), 0.55),
			levantado
		)
	)

	-- LA AZOTEA de los altos: la caja del ascensor, descentrada a proposito. Centrada
	-- se leeria como parte del edificio; a un lado se lee como lo que hay ARRIBA, que
	-- es lo que rompe el canto.
	if alto >= 28 and ancho > 14 and fondo > 14 then
		local ladoX = ancho * rng:NextNumber(0.24, 0.34)
		local ladoZ = fondo * rng:NextNumber(0.24, 0.34)
		local altoCaseta = 4 + rng:NextNumber(0, 3.4)
		adorno(
			pieza(
				nombre .. "_A",
				Vector3.new(ladoX, altoCaseta, ladoZ),
				Vector3.new(
					cx + (ancho / 2 - ladoX / 2 - 2) * rng:NextNumber(-0.7, 0.7),
					base + alto + 0.6 + altoCaseta / 2,
					cz + (fondo / 2 - ladoZ / 2 - 2) * rng:NextNumber(-0.7, 0.7)
				),
				tono:Lerp(Color3.fromRGB(52, 52, 58), 0.5),
				levantado
			)
		)
	end

	-- LAS BANDAS DE VENTANAS, que es lo que convierte una caja de color en un
	-- edificio con pisos.
	--
	-- UNA banda que rodea el edificio entero por cada planta, y no ventanas sueltas.
	-- Ventanas de verdad serian cuatro caras por doce huecos por cien edificios
	-- --miles de piezas-- para un detalle que a la distancia a la que se juega no se
	-- distingue. Una franja oscura horizontal cada ocho studs se lee como "esto tiene
	-- pisos" desde la otra punta de la calle, que es toda la informacion que hace
	-- falta, y cuesta tres piezas por edificio.
	--
	-- Una NAVE no lleva: no tiene pisos, y ponerselos es exactamente lo que hacia que
	-- el poligono de las afueras se viera igual que el barrio.
	--
	-- CADA BLOQUE CON SU PROPIA ALTURA DE PLANTA, y no es un adorno: las cuatro alas
	-- de una manzana se tocan en las esquinas, asi que con la misma altura de planta
	-- para todas sus bandas caian a la cota EXACTA y se solapaban -- 96 pares
	-- coplanares, los canto la sonda. El desfase sale del generador y no de una
	-- formula sobre el indice: con `(indice % 4) * 0.7` bajaron de 96 a 11, pero
	-- quedaron once -- cualquier formula corta acaba teniendo coincidencias asi.
	local ALTO_PLANTA = 7.4 + rng:NextNumber(0, 2.4)
	local plantas = math.floor(alto / ALTO_PLANTA)
	if plantas > 1 and not esNave then
		local tonoV = tono:Lerp(Color3.fromRGB(24, 26, 34), 0.62)
		for planta = 1, plantas - 1 do
			local yBanda = base + planta * ALTO_PLANTA
			-- Las que caerian dentro del zocalo o de la cornisa no se plantan: se
			-- verian como una raya partida a media altura de otra pieza.
			if yBanda > base + altoZocalo + 1.2 and yBanda < base + alto - altoCornisa - 1.2 then
				local banda = pieza(
					nombre .. "_V" .. planta,
					Vector3.new(ancho + 0.6, 1.6, fondo + 0.6),
					Vector3.new(cx, yBanda, cz),
					tonoV,
					levantado
				)
				banda.Material = Enum.Material.Glass
				-- Como el resto del decorado: invisible para los rayos y sin cuerpo. Un
				-- raycast que se pare en la cornisa de un edificio devuelve una cota
				-- absurda, y de eso ya se han descartado sitios enteros por imposibles.
				adorno(banda)
			end
		end
	end

	return levantado
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

	-- LA ACERA, y esta vez de verdad. Hasta aqui los edificios arrancaban en el borde
	-- exacto de la manzana, o sea con la fachada pegada al bordillo: no habia por
	-- donde andar, y las farolas y los arboles que se plantaron en la acera acabaron
	-- DENTRO de los edificios -- 97 pares de piezas solapadas, los canto la sonda.
	--
	-- Retranquear ocho studs abre la franja que le faltaba a la ciudad y le da sitio
	-- a lo que va en ella: bordillo en los dos primeros studs, mobiliario a los
	-- cuatro, fachada a los ocho. Los edificios pierden dieciseis studs por eje --de
	-- 120 a 104-- que es un precio bajo por dejar de ser una pared continua.
	x0, x1 = x0 + ACERA_ANCHO, x1 - ACERA_ANCHO
	z0, z1 = z0 + ACERA_ANCHO, z1 - ACERA_ANCHO

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
		table.insert(
			piezas,
			edificio(string.format("Edificio_%d_%d_%d", col, fila, indice), ax0, ax1, az0, az1, alto, color, padre)
		)
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

-- ────────────────────────────────────────────────────────────────────────────────
-- LAS MANZANAS QUE NO SON MANZANAS
--
-- Todo lo que sigue existe por una frase: *"la ciudad no esta acabada... ir zona por
-- zona dejando cada manzana trabajada... creciendo desde el sentido y la logica, no
-- copy paste"* (JJ). Cual le toca a cada una se decide en `shared/Districts.luau`;
-- aqui solo se planta.
--
-- LA REGLA COMUN A TODAS: la silueta manda. Lo que distingue un mercado de unas
-- naves a cien studs no es el detalle, es el PERFIL -- alto y separado, bajo y
-- continuo, plano y pintado. Si dos usos se ven igual desde la calle, sobra uno.
-- ────────────────────────────────────────────────────────────────────────────────

-- Lo que la acera se lleva por cada lado antes de que empiece a construirse nada. Es
-- el mismo numero que usa la manzana cerrada y sale de ahi: bordillo en los dos
-- primeros studs, mobiliario a los cuatro, fachada a los ocho.
local COLOR_ASFALTO_PATIO = Color3.fromRGB(58, 58, 64)
local COLOR_HORMIGON = Color3.fromRGB(146, 144, 138)
local COLOR_VALLA = Color3.fromRGB(178, 150, 62)
local COLOR_ESCOMBRO = Color3.fromRGB(122, 112, 100)
local COLOR_ANDAMIO = Color3.fromRGB(168, 122, 54)
-- Los toldos del mercado. Es el unico sitio del mapa con color saturado a proposito:
-- un mercado sin color no es un mercado, y ademas le da a la banda ambar un punto
-- del que acordarse.
local COLOR_TOLDO: { Color3 } = {
	Color3.fromRGB(186, 84, 64),
	Color3.fromRGB(72, 124, 148),
	Color3.fromRGB(196, 158, 70),
	Color3.fromRGB(104, 138, 88),
}
local COLOR_CONTENEDOR: { Color3 } = {
	Color3.fromRGB(128, 78, 60),
	Color3.fromRGB(74, 96, 112),
	Color3.fromRGB(96, 106, 78),
}
local COLOR_COCHE: { Color3 } = {
	Color3.fromRGB(158, 88, 72),
	Color3.fromRGB(84, 104, 128),
	Color3.fromRGB(132, 132, 138),
	Color3.fromRGB(96, 112, 90),
}

-- La huella util de una manzana: sus cuatro bordes ya descontada la acera.
local function huella(col: number, fila: number): (number, number, number, number)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	return x0 + ACERA_ANCHO, x1 - ACERA_ANCHO, z0 + ACERA_ANCHO, z1 - ACERA_ANCHO
end

-- La solera de una manzana que no es un edificio: el suelo propio del uso, por
-- encima de la losa de la acera. Sube 0,14 por la razon de siempre -- dos caras a la
-- misma cota parpadean.
local function solera(
	nombre: string,
	col: number,
	fila: number,
	color: Color3,
	material: Enum.Material,
	padre: Instance
): Part
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local p = pieza(
		nombre,
		Vector3.new(x1 - x0 - 4, 0.2, z1 - z0 - 4),
		Vector3.new((x0 + x1) / 2, Y_CALZADA + ACERA_ALTURA + 0.14, (z0 + z1) / 2),
		color,
		padre
	)
	p.Material = material
	-- SIN `CanQuery`, y esto SI importa: quien siembra el mundo busca suelo con un
	-- rayo hacia abajo, y esta losa esta 0,24 studs por encima del suelo real. Con
	-- consultas activas, cada alijo y cada refugio de esta manzana quedaria flotando
	-- esa cuarta de stud -- poco, pero es exactamente el hueco por el que se cuelan
	-- las cosas que "se ven y no se pueden coger".
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- TORRES. Dos o tres bloques altos y SEPARADOS sobre un zocalo bajo.
--
-- Es el unico uso que se ve desde el otro extremo del mapa, y por eso esta en la
-- roja: la silueta alta al fondo de la calle dice "por ahi esta el centro" sin
-- ningun cartel -- que era la funcion de los hitos de zona que se quitaron el 19/08
-- por taparlo todo. Estas no tapan porque estan DENTRO de la manzana y no plantadas
-- en mitad de la calle.
--
-- Separadas y no pegadas: entre dos torres se ve el cielo, y ese hueco vertical es
-- lo que las distingue de un bloque macizo a doscientos studs.
local function plantarTorres(col: number, fila: number, zona: string, padre: Instance, mobiliario: Instance): { Part }
	local cfg = ZONA_CONFIG[zona]
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = huella(col, fila)
	local piezas: { Part } = {}

	-- El zocalo: la plataforma comercial de los bajos. Ademas de leerse bien, es lo
	-- que hace que las torres no parezcan clavadas en el cesped.
	adorno(solera("ZocaloTorres_" .. col .. "_" .. fila, col, fila, COLOR_HORMIGON, Enum.Material.Concrete, mobiliario))

	-- Dos torres en diagonal y una tercera baja de remate. La diagonal es lo que deja
	-- pasar la vista: en linea recta las tres tapan lo mismo que una pared.
	local sitios = {
		{ x0 + 4, x0 + 42, z0 + 4, z0 + 42, 1.0 },
		{ x1 - 44, x1 - 4, z1 - 44, z1 - 4, 0.82 },
		{ x1 - 34, x1 - 6, z0 + 8, z0 + 34, 0.45 },
	}
	for i, t in sitios do
		local alto = rng:NextNumber(cfg.alturaMin, cfg.alturaMax) * t[5]
		local color = paleta[rng:NextInteger(1, #paleta)] :: Color3
		table.insert(
			piezas,
			edificio(string.format("Torre_%d_%d_%d", col, fila, i), t[1], t[2], t[3], t[4], alto, color, padre)
		)
	end
	return piezas
end

-- MERCADO. Dos naves de soportales enfrentadas y los puestos en medio.
--
-- Se ATRAVIESA, y es la unica manzana construida que se puede cruzar: se entra por
-- un extremo del pasillo central y se sale por el otro. Eso la hace util --un atajo
-- que ademas es un sitio-- y explica por que esta en la ambar, la banda que se cruza
-- para casi todo.
local function plantarMercado(col: number, fila: number, zona: string, padre: Instance, mobiliario: Instance): { Part }
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = huella(col, fila)
	local piezas: { Part } = {}

	adorno(solera("SueloMercado_" .. col .. "_" .. fila, col, fila, COLOR_HORMIGON, Enum.Material.Concrete, mobiliario))

	-- Las dos naves, bajas y largas. Bajas a proposito: un mercado alto seria un
	-- centro comercial, y ademas taparia la manzana de detras.
	for i, lado in { z0, z1 - 26 } do
		local color = paleta[rng:NextInteger(1, #paleta)] :: Color3
		table.insert(
			piezas,
			edificio(
				string.format("Mercado_%d_%d_%d", col, fila, i),
				x0,
				x1,
				lado,
				lado + 26,
				rng:NextNumber(11, 14),
				color,
				padre
			)
		)
	end

	-- LOS PUESTOS, en dos hileras a lo largo del pasillo. Mesa, dos postes y toldo.
	local cz = (z0 + z1) / 2
	local puesto = 0
	for hilera = -1, 1, 2 do
		local pz = cz + hilera * 13
		local px = x0 + 10
		while px < x1 - 10 do
			puesto += 1
			local color = COLOR_TOLDO[(puesto % #COLOR_TOLDO) + 1] :: Color3
			local base = Y_CALZADA + ACERA_ALTURA + 0.24
			adorno(
				pieza(
					string.format("PuestoMesa_%d_%d_%d", col, fila, puesto),
					Vector3.new(9, 1.2, 5),
					Vector3.new(px, base + 1.5, pz),
					COLOR_HORMIGON,
					mobiliario
				)
			).Material =
				Enum.Material.WoodPlanks
			for _, dx in { -4, 4 } do
				adorno(
					pieza(
						string.format("PuestoPoste_%d_%d_%d", col, fila, puesto),
						Vector3.new(0.4, 5.2, 0.4),
						Vector3.new(px + dx, base + 2.6, pz),
						COLOR_HORMIGON,
						mobiliario
					)
				)
			end
			-- El toldo, INCLINADO. Plano se lee como una tapa; con siete grados de
			-- caida se lee como tela, y no cuesta una pieza mas.
			local toldo = adorno(
				pieza(
					string.format("PuestoToldo_%d_%d_%d", col, fila, puesto),
					Vector3.new(10, 0.3, 6.4),
					Vector3.new(px, base + 5.3, pz),
					color,
					mobiliario
				)
			)
			toldo.Material = Enum.Material.Fabric
			toldo.CFrame = CFrame.new(toldo.Position) * CFrame.Angles(math.rad(hilera * 7), 0, 0)
			px += 16
		end
	end
	return piezas
end

-- TALLERES. Naves anchas y bajas con el patio delante, y contenedores en el patio.
--
-- Van pegadas al almacen del jugador (manzana 0,2) y en las afueras, y las dos cosas
-- son la misma decision: es lo que habria alrededor de una nave de reparto. Un
-- poligono industrial junto a tu propia nave explica el sitio donde vives sin una
-- sola linea de texto.
local function plantarTalleres(col: number, fila: number, zona: string, padre: Instance, mobiliario: Instance): { Part }
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = huella(col, fila)
	local piezas: { Part } = {}

	adorno(
		solera(
			"PatioTalleres_" .. col .. "_" .. fila,
			col,
			fila,
			COLOR_ASFALTO_PATIO,
			Enum.Material.Asphalt,
			mobiliario
		)
	)

	-- Tres naves en L: dos largas al norte y una corta al oeste. La L deja el patio
	-- abierto a dos calles, que es lo que hace que se vea que hay algo dentro.
	local naves = {
		{ x0, x0 + 52, z1 - 34, z1 },
		{ x0 + 58, x1, z1 - 34, z1 },
		{ x0, x0 + 30, z0 + 6, z1 - 40 },
	}
	for i, n in naves do
		local color = paleta[rng:NextInteger(1, #paleta)] :: Color3
		table.insert(
			piezas,
			edificio(
				string.format("Nave_%d_%d_%d", col, fila, i),
				n[1],
				n[2],
				n[3],
				n[4],
				rng:NextNumber(12, 17),
				color,
				padre,
				-- NAVE: puerta de carga en vez de portal, y sin bandas de pisos. Una
				-- nave con ventanas de vivienda es exactamente lo que hacia que el
				-- poligono se leyera igual que el barrio.
				"nave"
			)
		)
	end

	-- Los contenedores del patio, apilados de dos en dos en un par de sitios. Es lo
	-- que da escala: sin nada suelto en el suelo, un patio de asfalto no dice si mide
	-- veinte studs o cien.
	for k = 0, 5 do
		local cx = x0 + 42 + (k % 3) * 18
		local cz = z0 + 10 + math.floor(k / 3) * 16
		local pisos = if k % 4 == 0 then 2 else 1
		for piso = 1, pisos do
			local c = adorno(
				pieza(
					string.format("Contenedor_%d_%d_%d_%d", col, fila, k, piso),
					Vector3.new(14, 7, 8),
					Vector3.new(cx, Y_CALZADA + ACERA_ALTURA + 0.3 + 3.5 + (piso - 1) * 7.1, cz),
					COLOR_CONTENEDOR[((k + piso) % #COLOR_CONTENEDOR) + 1] :: Color3,
					mobiliario
				)
			)
			c.Material = Enum.Material.CorrodedMetal
			c.CFrame = CFrame.new(c.Position) * CFrame.Angles(0, math.rad((k % 2) * 90), 0)
		end
	end
	return piezas
end

-- SOLAR. La obra parada: vallada, con montones y un andamio sin edificio detras.
--
-- Sustituye a los "lotes vacantes", que eran losas peladas. La funcion de juego es la
-- misma --se corta por dentro y la patrulla, atada a las calles, tiene que rodear--
-- pero ahora se ve POR QUE esta vacio, y una valla con una abertura ensena por donde
-- se entra sin tener que probar las cuatro esquinas.
local function plantarSolar(col: number, fila: number, mobiliario: Instance): { Part }
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	adorno(solera("SueloSolar_" .. col .. "_" .. fila, col, fila, COLOR_ESCOMBRO, Enum.Material.Ground, mobiliario))

	-- LA VALLA, con un hueco en el lado sur. Los postes van sin cuerpo como todo el
	-- decorado: una valla con colision atasca el pathfinding de las patrullas, y eso
	-- ya se pago con las del mapa prestado.
	local base = Y_CALZADA + ACERA_ALTURA + 0.3
	local HUECO = 22
	local n = 0
	local function tramo(ax: number, az: number, largoX: number, largoZ: number)
		n += 1
		local v = adorno(
			pieza(
				string.format("Valla_%d_%d_%d", col, fila, n),
				Vector3.new(largoX, 5, largoZ),
				Vector3.new(ax, base + 2.5, az),
				COLOR_VALLA,
				mobiliario
			)
		)
		v.Material = Enum.Material.Metal
		v.Transparency = 0.25
	end
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local ancho, largo = x1 - x0 - 6, z1 - z0 - 6
	tramo(cx, z1 - 3, ancho, 0.6)
	tramo(x0 + 3, cz, 0.6, largo)
	tramo(x1 - 3, cz, 0.6, largo)
	-- El lado sur, partido: por ahi se entra.
	local mitad = (ancho - HUECO) / 2
	tramo(cx - (HUECO / 2 + mitad / 2), z0 + 3, mitad, 0.6)
	tramo(cx + (HUECO / 2 + mitad / 2), z0 + 3, mitad, 0.6)

	-- Tres montones de tierra y un andamio: lo justo para que se lea como obra y no
	-- como descampado.
	for i = 1, 3 do
		local m = adorno(
			pieza(
				string.format("Monton_%d_%d_%d", col, fila, i),
				Vector3.new(16 - i * 2, 6, 16 - i * 2),
				Vector3.new(cx + (i - 2) * 26, base + 3, cz - 14 + i * 9),
				COLOR_ESCOMBRO,
				mobiliario
			)
		)
		m.Material = Enum.Material.Ground
		m.CFrame = CFrame.new(m.Position) * CFrame.Angles(0, math.rad(i * 30), 0)
	end

	-- El andamio: cuatro pies y dos plataformas. Es lo unico vertical del solar, y es
	-- lo que hace que la manzana no sea un agujero en la silueta de la calle.
	local ax, az = cx + 22, cz + 20
	local pie = 0
	for _, dx in { -7, 7 } do
		for _, dz in { -5, 5 } do
			pie += 1
			adorno(
				pieza(
					string.format("AndamioPie_%d_%d_%d", col, fila, pie),
					Vector3.new(0.7, 18, 0.7),
					Vector3.new(ax + dx, base + 9, az + dz),
					COLOR_ANDAMIO,
					mobiliario
				)
			).Material =
				Enum.Material.Metal
		end
	end
	for piso = 1, 2 do
		adorno(
			pieza(
				string.format("AndamioPiso_%d_%d_%d", col, fila, piso),
				Vector3.new(15.4, 0.5, 11.4),
				Vector3.new(ax, base + piso * 8, az),
				COLOR_ANDAMIO,
				mobiliario
			)
		).Material =
			Enum.Material.WoodPlanks
	end

	-- Sin edificios: el solar no aporta ninguno a la lista que se valida despues.
	return {}
end

-- APARCAMIENTO. La explanada pintada, con coches quietos y una caseta.
--
-- Es la manzana mas plana del mapa y eso es justo lo que aporta: desde una calle se
-- VE la de enfrente por encima de ella. Un mapa donde todo tapa es un laberinto; uno
-- con un par de huecos por los que se ve lejos se puede leer desde dentro.
local function plantarAparcamiento(
	col: number,
	fila: number,
	zona: string,
	padre: Instance,
	mobiliario: Instance
): { Part }
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = huella(col, fila)
	local piezas: { Part } = {}

	adorno(
		solera("SueloParking_" .. col .. "_" .. fila, col, fila, COLOR_ASFALTO_PATIO, Enum.Material.Asphalt, mobiliario)
	)

	local base = Y_CALZADA + ACERA_ALTURA + 0.3
	-- Las lineas de las plazas, en dos bandas con un pasillo en medio.
	local marca = 0
	for _, banda in { z0 + 12, z1 - 26 } do
		local px = x0 + 6
		while px < x1 - 6 do
			marca += 1
			adorno(
				pieza(
					string.format("Plaza_%d_%d_%d", col, fila, marca),
					Vector3.new(0.5, 0.12, 14),
					Vector3.new(px, base, banda + 7),
					COLOR_LINEA,
					mobiliario
				)
			)
			px += 9
		end
	end

	-- Los coches. Caja y cabina: dos piezas por coche y se lee perfectamente desde la
	-- altura de la camara. Uno de cada tres se deja fuera para que no parezca una
	-- exposicion, y eso ademas deja hueco por donde cruzar.
	local coche = 0
	for k = 0, 13 do
		if k % 3 == 2 then
			continue
		end
		coche += 1
		local px = x0 + 10 + (k % 7) * 13
		local pz = if k < 7 then z0 + 19 else z1 - 19
		local color = COLOR_COCHE[(coche % #COLOR_COCHE) + 1] :: Color3
		adorno(
			pieza(
				string.format("CocheQuieto_%d_%d_%d", col, fila, coche),
				Vector3.new(4.4, 2.2, 9),
				Vector3.new(px, base + 1.4, pz),
				color,
				mobiliario
			)
		)
		adorno(
			pieza(
				string.format("CocheTecho_%d_%d_%d", col, fila, coche),
				Vector3.new(4, 1.8, 4.6),
				Vector3.new(px, base + 3.3, pz - 0.6),
				color:Lerp(Color3.fromRGB(20, 22, 28), 0.45),
				mobiliario
			)
		).Material =
			Enum.Material.Glass
	end

	-- Y la caseta del vigilante, que es lo unico construido: sin ella la manzana no
	-- tendria ni una sombra y se leeria como un solar mas.
	table.insert(
		piezas,
		edificio(
			string.format("Caseta_%d_%d", col, fila),
			x1 - 20,
			x1 - 4,
			z0 + 4,
			z0 + 18,
			9,
			paleta[1] :: Color3,
			padre
		)
	)
	return piezas
end

-- ESCUELA. Un edificio en U abrazando un patio de recreo, y el conjunto vallado.
--
-- Es el primero de los tres usos del 22/08, y los tres responden a lo mismo: *"quiero
-- un mapa muy trabajado... que los edificios tengan identidad, haya plazas, jardines
-- etc"* (JJ). Los usos que habia hasta ahora describian TEJIDO --residencial, torres,
-- talleres-- o eran explanadas. De un tejido no te acuerdas; de un sitio, si. En una
-- ciudad hay una escuela, no doce, y por eso sirve para decir donde estas.
--
-- NO SE ATRAVIESA, y ahi esta su papel de juego. Al lado de la plaza --la manzana mas
-- abierta del mapa-- hay ahora una manzana grande que hay que RODEAR: la pareja
-- ensena de golpe las dos reglas del mapa, que por unas se corta y por otras no.
local function plantarEscuela(col: number, fila: number, zona: string, padre: Instance, mobiliario: Instance): { Part }
	local paleta = COLOR_EDIFICIO[zona]
	local x0, x1, z0, z1 = huella(col, fila)
	local piezas: { Part } = {}
	local base = Y_CALZADA + ACERA_ALTURA

	adorno(solera("PatioEscuela_" .. col .. "_" .. fila, col, fila, COLOR_HORMIGON, Enum.Material.Concrete, mobiliario))

	-- LA U, abierta al sur. Dos plantas y media: mas alto que una casa de la verde y
	-- mucho mas bajo que sus torres, que es la silueta de un edificio publico.
	local color = paleta[1] :: Color3
	--
	-- LAS ALAS LATERALES BAJAN HASTA EL BORDE SUR, y esa es la diferencia entre una
	-- manzana que se rodea y una que no. La primera version las cortaba 18 studs antes
	-- --para que el patio se viera desde la calle-- y eso dejaba una franja libre de
	-- lado a lado por debajo de ellas: la escuela se cruzaba de este a oeste sin
	-- enterarse, o sea que era atravesable de hecho mientras el plano decia que no. Y
	-- el plano no es decorativo: de el salen la sonda de conectividad y el reparto
	-- entre atajos y muros, que es lo que hace que la calle siga siendo la calle.
	--
	-- Cerradas hasta abajo, la U es un CALLEJON SIN SALIDA: se entra por la boca del
	-- sur y no se sale por ningun otro lado. Entrar sigue siendo posible --y con una
	-- patrulla detras es una mala idea, que es justo la decision que se busca-- pero
	-- cruzar, no.
	local ALA = 26
	local alas = {
		{ x0, x1, z1 - ALA, z1 },
		{ x0, x0 + ALA, z0, z1 - ALA },
		{ x1 - ALA, x1, z0, z1 - ALA },
	}
	-- UNA ALTURA POR ALA, y no las tres iguales. Ademas de leerse mejor --una U con el
	-- cuerpo central mas alto es un edificio; tres cajas iguales son tres cajas-- es lo
	-- que impide que sus tres cornisas caigan en la misma cota y parpadeen: con 17,5
	-- para las tres salian cinco pares coplanares en esta sola manzana.
	local ALTURAS = { 19.5, 16.2, 17.4 }
	for i, a in alas do
		table.insert(
			piezas,
			edificio(
				string.format("Escuela_%d_%d_%d", col, fila, i),
				a[1],
				a[2],
				a[3],
				a[4],
				ALTURAS[i] :: number,
				color,
				padre
			)
		)
	end

	-- LA VERJA, en la boca que dejan las dos alas. Postes y barandilla: dice "esto es
	-- un recinto" sin levantar un muro que taparia el edificio desde la calle.
	--
	-- NO CIERRA NADA, Y NO TIENE QUE HACERLO. Es decorado --sin cuerpo, como todo el
	-- mobiliario-- y aunque lo tuviera daria igual: el jugador salta diez studs
	-- (`Config.SALTO_ALTURA`) y ninguna valla creible llega a esa altura. Lo que hace
	-- que esta manzana no se cruce son las tres alas, no la verja.
	local bocaX0, bocaX1 = x0 + ALA, x1 - ALA
	for k = 0, 7 do
		local px = bocaX0 + 2 + k * ((bocaX1 - bocaX0 - 4) / 7)
		adorno(
			pieza(
				string.format("VerjaPoste_%d_%d_%d", col, fila, k),
				Vector3.new(0.9, 6, 0.9),
				Vector3.new(px, base + 3, z0 + 2),
				Color3.fromRGB(72, 76, 84),
				mobiliario
			)
		)
	end
	adorno(
		pieza(
			string.format("VerjaBarra_%d_%d", col, fila),
			Vector3.new(bocaX1 - bocaX0 - 4, 0.6, 0.6),
			Vector3.new((x0 + x1) / 2, base + 5.2, z0 + 2),
			Color3.fromRGB(72, 76, 84),
			mobiliario
		)
	)

	-- LA PISTA pintada del patio, con sus dos canastas. Es lo unico del conjunto que
	-- se ve desde arriba en el mapa pequeno, asi que es lo que lo identifica ahi.
	local pista = adorno(
		pieza(
			string.format("PistaEscuela_%d_%d", col, fila),
			Vector3.new(x1 - x0 - 34, 0.16, 30),
			Vector3.new((x0 + x1) / 2, base + 0.4, z0 + 26),
			Color3.fromRGB(126, 92, 74),
			mobiliario
		)
	)
	pista.Material = Enum.Material.Concrete
	for lado = -1, 1, 2 do
		local cx = (x0 + x1) / 2 + lado * ((x1 - x0 - 40) / 2)
		adorno(
			pieza(
				string.format("Canasta_%d_%d_%d", col, fila, lado + 2),
				Vector3.new(0.8, 11, 0.8),
				Vector3.new(cx, base + 5.5, z0 + 26),
				Color3.fromRGB(150, 148, 142),
				mobiliario
			)
		)
		adorno(
			pieza(
				string.format("Tablero_%d_%d_%d", col, fila, lado + 2),
				Vector3.new(0.5, 4, 6),
				Vector3.new(cx - lado * 1.4, base + 12, z0 + 26),
				Color3.fromRGB(220, 218, 210),
				mobiliario
			)
		)
	end
	return piezas
end

-- CANCHA. Una pista deportiva con gradas, y se cruza POR LAS BANDAS.
--
-- Su gracia como atajo es distinta de la de un solar: el solar se cruza en diagonal y
-- esto no --las gradas y las porterias estorban-- asi que el paso util son las dos
-- bandas laterales, que son estrechas y estan a la vista. Cortar por aqui con una
-- patrulla cerca es una apuesta, no un regalo.
local function plantarCancha(col: number, fila: number, mobiliario: Instance): { Part }
	local x0, x1, z0, z1 = huella(col, fila)
	local base = Y_CALZADA + ACERA_ALTURA
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2

	local suelo = adorno(
		solera(
			"SueloCancha_" .. col .. "_" .. fila,
			col,
			fila,
			Color3.fromRGB(78, 104, 76),
			Enum.Material.Grass,
			mobiliario
		)
	)
	suelo.Name = "SueloCancha_" .. col .. "_" .. fila

	-- EL CAMPO, con su linea de medio y su circulo aproximado por ocho tramos. Un
	-- circulo de verdad pediria una malla; ocho piezas cortas se leen como un circulo
	-- desde la altura a la que se juega y cuestan ocho piezas.
	local campo = adorno(
		pieza(
			string.format("Campo_%d_%d", col, fila),
			Vector3.new(x1 - x0 - 30, 0.16, z1 - z0 - 34),
			Vector3.new(cx, base + 0.4, cz),
			Color3.fromRGB(96, 126, 88),
			mobiliario
		)
	)
	campo.Material = Enum.Material.Grass
	adorno(
		pieza(
			string.format("Medio_%d_%d", col, fila),
			Vector3.new(x1 - x0 - 30, 0.14, 0.8),
			Vector3.new(cx, base + 0.56, cz),
			COLOR_LINEA,
			mobiliario
		)
	)
	for k = 0, 7 do
		local ang = k * math.pi / 4
		local p = adorno(
			pieza(
				string.format("Circulo_%d_%d_%d", col, fila, k),
				Vector3.new(7, 0.14, 0.8),
				Vector3.new(cx + math.cos(ang) * 9, base + 0.56, cz + math.sin(ang) * 9),
				COLOR_LINEA,
				mobiliario
			)
		)
		p.CFrame = CFrame.new(p.Position) * CFrame.Angles(0, -ang + math.pi / 2, 0)
	end

	-- LAS PORTERIAS, en los fondos.
	for lado = -1, 1, 2 do
		local pz = cz + lado * ((z1 - z0 - 38) / 2)
		adorno(
			pieza(
				string.format("Porteria_%d_%d_%d", col, fila, lado + 2),
				Vector3.new(18, 0.7, 0.7),
				Vector3.new(cx, base + 7, pz),
				Color3.fromRGB(228, 226, 218),
				mobiliario
			)
		)
		for palo = -1, 1, 2 do
			adorno(
				pieza(
					string.format("Palo_%d_%d_%d_%d", col, fila, lado + 2, palo + 2),
					Vector3.new(0.7, 7, 0.7),
					Vector3.new(cx + palo * 9, base + 3.5, pz),
					Color3.fromRGB(228, 226, 218),
					mobiliario
				)
			)
		end
	end

	-- LAS GRADAS: tres escalones a un lado. Son lo que hace que esto no se confunda
	-- con un parque desde la calle -- un volumen escalonado no lo tiene nada mas en
	-- todo el mapa.
	for escalon = 1, 3 do
		adorno(
			pieza(
				string.format("Grada_%d_%d_%d", col, fila, escalon),
				Vector3.new(x1 - x0 - 24, 1.6, 5),
				Vector3.new(cx, base + 0.8 + (escalon - 1) * 1.55, z1 - 6 - (escalon - 1) * 5),
				Color3.fromRGB(150, 146, 138),
				mobiliario
			)
		)
	end
	return {}
end

-- GASOLINERA. Marquesina sobre cuatro pilares, cuatro surtidores y una tienda.
--
-- Es la explanada MAS abierta del mapa a proposito, y esta en la salida oeste porque
-- es donde estaria. Aporta dos cosas que no tenia ninguna otra manzana: un techo bajo
-- el que se pasa --el unico sitio donde se puede estar a cubierto sin entrar en
-- ningun sitio-- y una silueta que se reconoce desde muy lejos por la losa plana
-- flotando a nueve studs.
local function plantarGasolinera(
	col: number,
	fila: number,
	zona: string,
	padre: Instance,
	mobiliario: Instance
): { Part }
	local x0, x1, z0, z1 = huella(col, fila)
	local base = Y_CALZADA + ACERA_ALTURA
	local piezas: { Part } = {}

	adorno(
		solera("SueloEstacion_" .. col .. "_" .. fila, col, fila, COLOR_HORMIGON, Enum.Material.Concrete, mobiliario)
	)

	-- LA TIENDA, al fondo. Baja y ancha, con su escaparate: es el unico edificio del
	-- conjunto y va detras para que la marquesina se vea desde la calle.
	local paleta = COLOR_EDIFICIO[zona]
	table.insert(
		piezas,
		edificio(
			string.format("Tienda_%d_%d", col, fila),
			x0 + 8,
			x0 + 56,
			z1 - 24,
			z1 - 2,
			11,
			paleta[3] :: Color3,
			padre
		)
	)

	-- LA MARQUESINA. Nueve studs de galibo: pasa un jugador y pasa una furgoneta, que
	-- es justo lo que tiene que pasar por debajo.
	local mx, mz = (x0 + x1) / 2 + 6, z0 + 34
	local GALIBO = 9
	local techo = adorno(
		pieza(
			string.format("Marquesina_%d_%d", col, fila),
			Vector3.new(54, 1.6, 34),
			Vector3.new(mx, base + GALIBO + 0.8, mz),
			Color3.fromRGB(206, 202, 192),
			mobiliario
		)
	)
	techo.Material = Enum.Material.Metal
	-- La banda de color del canto. Es lo unico saturado de la manzana y es lo que se
	-- ve a doscientos studs -- el resto del conjunto a esa distancia es una losa gris.
	adorno(
		pieza(
			string.format("MarquesinaBanda_%d_%d", col, fila),
			Vector3.new(55, 1, 35),
			Vector3.new(mx, base + GALIBO - 0.2, mz),
			Color3.fromRGB(196, 84, 56),
			mobiliario
		)
	)
	for k = 0, 3 do
		local px = mx + (if k % 2 == 0 then -22 else 22)
		local pz = mz + (if k < 2 then -13 else 13)
		adorno(
			pieza(
				string.format("PilarEstacion_%d_%d_%d", col, fila, k),
				Vector3.new(2.6, GALIBO, 2.6),
				Vector3.new(px, base + GALIBO / 2, pz),
				Color3.fromRGB(190, 188, 180),
				mobiliario
			)
		)
	end

	-- LOS SURTIDORES, en dos islas bajo el techo. Cada uno sobre su bordillo: sin el,
	-- cuatro cajas sueltas en el hormigon se leen como escombros.
	for isla = 0, 1 do
		local iz = mz + (if isla == 0 then -8 else 8)
		adorno(
			pieza(
				string.format("IslaSurtidor_%d_%d_%d", col, fila, isla),
				Vector3.new(30, 0.8, 5),
				Vector3.new(mx, base + 0.4, iz),
				Color3.fromRGB(168, 166, 158),
				mobiliario
			)
		)
		for s = 0, 1 do
			adorno(
				pieza(
					string.format("Surtidor_%d_%d_%d_%d", col, fila, isla, s),
					Vector3.new(2.4, 5, 3.4),
					Vector3.new(mx + (if s == 0 then -9 else 9), base + 3.3, iz),
					Color3.fromRGB(216, 212, 204),
					mobiliario
				)
			)
		end
	end
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
	for col = Grid.COL_MIN, Grid.COL_MAX - 1 do
		for fila = Grid.FILA_MIN, Grid.FILA_MAX - 1 do
			if enManzana(x, z, col, fila) then
				return { col = col, fila = fila }
			end
		end
	end
	return nil
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

-- LA VERIFICACION DE CONECTIVIDAD SE FUE A `SelfCheck` (22/08), y no por orden.
--
-- Corria aqui, al final de `buildCiudad`, y medía el camino a pie desde cada manzana
-- atravesable hasta `Config.ALMACEN_POS`. El problema es CUANDO: en ese momento la
-- ciudad esta puesta pero el recinto, el almacen y el taller todavia no existen --
-- los planta `CityBuilder` despues-- asi que el destino del camino era un punto en
-- el aire y el pathfinder contestaba `NoPath` para todas. Nueve avisos rojos en la
-- consola de arranque, y las nueve mentira: medido con el mundo ya terminado, hay
-- camino desde las dos manzanas mas lejanas (115 y 158 puntos de ruta).
--
-- Es la trampa de siempre en este proyecto -- *cada cosa que se planta cambia el
-- mundo que la siguiente mide*-- y la cura tambien: la sonda va al final DEL TODO,
-- no al final de su fichero.

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

	-- LA PINTURA VA APARTE, y no es manía de orden: las sondas del mundo miden POR
	-- CARPETA. Con las marcas viales dentro de `Calles`, la sonda de cotas las contó
	-- como calzada y dio rojo ("las calles de 19,20 a 19,40") por unas rayas de 0,12
	-- studs; y los bordillos dentro de `Manzanas` hicieron que "hay una losa por
	-- manzana" contara 60 en vez de 12. Las dos sondas estaban en lo cierto sobre lo
	-- que medían: lo que estaba mal era meter pintura donde se cuenta geometría.
	local carpetaPintura = Instance.new("Folder")
	carpetaPintura.Name = "Pintura"
	carpetaPintura.Parent = ciudad

	-- Y el mobiliario urbano en la suya, por el mismo motivo que la pintura: las
	-- sondas miden por carpeta, y un arbol dentro de `Edificios` cuenta como edificio.
	local carpetaMobiliario = Instance.new("Folder")
	carpetaMobiliario.Name = "Mobiliario"
	carpetaMobiliario.Parent = ciudad
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

	-- 2b. Y la pintura encima del asfalto, antes de que las manzanas lo tapen: las
	-- rayas que caen bajo una manzana quedan enterradas y no se ven, que es
	-- exactamente lo que tiene que pasar.
	plantarMarcasViales(carpetaPintura)

	-- 3. Para cada zona, plantar sus manzanas con sus edificios
	local edificiosGenerados: { Part } = {}

	-- 3. CADA MANZANA, SEGUN LO QUE ES. El plano vive en `Districts`; esto es el
	-- despacho, y a proposito es una cadena de `if` legible y no una tabla de
	-- funciones: quien venga a anadir un uso tiene que tocar dos sitios --el plano y
	-- esta lista-- y la prueba de `Districts` le avisa si se deja uno.
	local cotaAcera = Y_CALZADA + ACERA_ALTURA
	for _, mz in Districts.manzanas() do
		plantarLosaManzana(mz.col, mz.fila, carpetaManzanas, carpetaPintura)

		local nuevos: { Part } = {}
		if mz.uso == Districts.PLAZA then
			StreetProps.jardin(mz.col, mz.fila, cotaAcera, carpetaMobiliario)
		elseif mz.uso == Districts.PARQUE then
			StreetProps.parque(mz.col, mz.fila, cotaAcera, carpetaMobiliario)
		elseif mz.uso == Districts.SOLAR then
			nuevos = plantarSolar(mz.col, mz.fila, carpetaMobiliario)
		elseif mz.uso == Districts.TORRES then
			nuevos = plantarTorres(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		elseif mz.uso == Districts.MERCADO then
			nuevos = plantarMercado(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		elseif mz.uso == Districts.TALLERES then
			nuevos = plantarTalleres(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		elseif mz.uso == Districts.APARCAMIENTO then
			nuevos = plantarAparcamiento(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		elseif mz.uso == Districts.ESCUELA then
			nuevos = plantarEscuela(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		elseif mz.uso == Districts.CANCHA then
			nuevos = plantarCancha(mz.col, mz.fila, carpetaMobiliario)
		elseif mz.uso == Districts.GASOLINERA then
			nuevos = plantarGasolinera(mz.col, mz.fila, mz.zona, carpetaEdificios, carpetaMobiliario)
		else
			nuevos = plantarManzanaCerrada(mz.col, mz.fila, mz.zona, carpetaEdificios)
		end
		for _, pz in nuevos do
			table.insert(edificiosGenerados, pz)
		end

		-- Y LAS ACERAS SIEMPRE, sea la manzana lo que sea. Las farolas y los arboles
		-- van FUERA de la huella construida --en la franja de ocho studs que se le
		-- descuenta a todo uso-- asi que valen igual para un parque que para una
		-- torre, y son lo que hace que la calle siga siendo una calle al pasar de un
		-- barrio a otro.
		StreetProps.acerasDe(mz.col, mz.fila, cotaAcera, carpetaMobiliario)
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
	local porUso: { [string]: number } = {}
	for _, mz in Districts.manzanas() do
		porUso[mz.uso] = (porUso[mz.uso] or 0) + 1
	end

	print(string.format("[MapBuilder] %d edificios en %d manzanas:", totalEdificios, #Districts.manzanas()))
	local usos: { string } = {}
	for uso in porUso do
		table.insert(usos, uso)
	end
	table.sort(usos)
	for _, uso in usos do
		print(string.format("  · %-13s %d", uso, porUso[uso]))
	end

	ciudad.Parent = padre
	return ciudad
end

return MapBuilder
