--!strict
--[[
	Grid.spec — que el plano de la ciudad siga siendo el plano.

	Estas comprobaciones parecen tontas ("la calle 0 está en -766") y son las más
	útiles del proyecto, porque la retícula es el sitio donde un dedazo no da ningún
	error: el mundo se construye igual, el juego arranca igual, y lo único que pasa es
	que un destino deja de estar en un cruce y hay que volver a jugar media hora para
	notarlo.

	Lo que se comprueba no son valores bonitos sino las dos promesas del diseño: que
	el paso es constante --si alguien mueve una calle a mano, la ciudad deja de ser
	una retícula-- y que desde la boca del recinto se llega a cualquier destino con un
	giro o ninguno, que es "sé a dónde voy" escrito como una prueba.
]]

local Grid = require(script.Parent.Parent.Grid)

return function(kit)
	-- Las cuatro esquinas del plano.
	kit.eq("la calle 0 esta en el borde oeste", Grid.xDeCalle(0), -766)
	kit.eq("la calle 1 pasa por la boca del recinto", Grid.xDeCalle(1), -620)
	kit.eq("la ultima calle vertical cierra el este", Grid.xDeCalle(Grid.COLUMNAS), -182)
	kit.eq("la ultima calle horizontal es la del recinto", Grid.zDeCalle(Grid.FILAS), 754)
	kit.eq("la primera cierra el sur", Grid.zDeCalle(0), 316)

	-- El paso, constante. Es lo que hace que esto sea una retícula y no un plano
	-- dibujado a mano: en cuanto una calle se mueve "un poco", el jugador deja de
	-- poder predecir dónde está la siguiente.
	for i = 1, Grid.COLUMNAS do
		kit.eq("paso constante entre calles verticales " .. i, Grid.xDeCalle(i) - Grid.xDeCalle(i - 1), Grid.PASO)
	end
	for j = 1, Grid.FILAS do
		kit.eq("paso constante entre calles horizontales " .. j, Grid.zDeCalle(j) - Grid.zDeCalle(j - 1), Grid.PASO)
	end
	kit.eq("y el paso es manzana mas calle", Grid.PASO, Grid.LADO_MANZANA + Grid.ANCHO_CALLE)

	-- Las bandas, ordenadas: alejarse de casa es entrar en zona peor.
	kit.eq("la fila alta, la de casa, es la verde", Grid.zonaDeFila(2), "verde")
	kit.eq("la del medio es la ambar", Grid.zonaDeFila(1), "ambar")
	kit.eq("la del fondo es la roja", Grid.zonaDeFila(0), "roja")
	for _, zona in { "verde", "ambar", "roja" } do
		kit.eq("y la vuelta encaja para " .. zona, Grid.zonaDeFila(Grid.filaDeZona(zona)), zona)
	end

	-- LA COMPROBACIÓN QUE JUSTIFICA EL REDISEÑO. Tres partidas seguidas con "no sé
	-- a dónde tengo que ir"; esto es esa queja convertida en algo que falla solo.
	local boca = Vector3.new(Grid.xDeCalle(1), Grid.Y, Grid.zDeCalle(Grid.FILAS))
	kit.eq("a la verde se va recto, sin girar", Grid.giros(boca, Grid.cruce(1, 2)), 0)
	kit.eq("a la ambar, un giro", Grid.giros(boca, Grid.cruce(2, 1)), 1)
	kit.eq("a la roja, un giro", Grid.giros(boca, Grid.cruce(3, 0)), 1)

	-- Y LA PROGRESION DE CAMINOS, que desde el 20/08 sale redonda: 146, 438 y 730 son
	-- dos pasos de reticula de diferencia entre una ruta y la siguiente. Con la verde
	-- en su sitio viejo (292) los tres saltos eran 146, 146 y 292, o sea que elegir
	-- entre la verde y la ambar significaba la mitad que elegir entre la ambar y la
	-- roja. Ahora cada escalon vale lo mismo.
	kit.eq("camino a la verde", Grid.camino(boca, Grid.cruce(1, 2)), 146)
	kit.eq("camino a la ambar", Grid.camino(boca, Grid.cruce(2, 1)), 438)
	kit.eq("camino a la roja", Grid.camino(boca, Grid.cruce(3, 0)), 730)
	local paso = 2 * Grid.PASO
	kit.eq(
		"de la verde a la ambar, dos pasos",
		Grid.camino(boca, Grid.cruce(2, 1)) - Grid.camino(boca, Grid.cruce(1, 2)),
		paso
	)
	kit.eq(
		"y de la ambar a la roja, otros dos",
		Grid.camino(boca, Grid.cruce(3, 0)) - Grid.camino(boca, Grid.cruce(2, 1)),
		paso
	)

	-- LOS DESTINOS, DISTINGUIBLES ENTRE SÍ. La primera versión de esta prueba exigía
	-- cuatro direcciones distintas y era imposible de cumplir: la boca está en el
	-- borde norte y el mapa cae entero hacia el sur, así que sólo existen tres
	-- direcciones -- suroeste, sur y sureste. Pedir cuatro habría obligado a mover un
	-- destino a un sitio peor para que cuadrara una frase bonita.
	--
	-- Lo que sí se puede exigir, y es lo que de verdad importa para no confundirlos:
	-- dos destinos en la misma dirección tienen que estar a DOS PASOS de retícula de
	-- diferencia. Con uno solo se ven desde el mismo sitio y se llega al que no era.
	local destinos = { Grid.cruce(1, 2), Grid.cruce(2, 1), Grid.cruce(3, 0) }
	for i = 1, #destinos do
		for j = i + 1, #destinos do
			local a, b = destinos[i], destinos[j]
			local da, db = a - boca, b - boca
			local mismaDireccion = math.sign(da.X) == math.sign(db.X) and math.sign(da.Z) == math.sign(db.Z)
			if mismaDireccion then
				local diferencia = math.abs(Grid.camino(boca, a) - Grid.camino(boca, b))
				kit.truthy(
					string.format("los destinos %d y %d comparten rumbo pero no profundidad", i, j),
					diferencia >= 2 * Grid.PASO
				)
			end
		end
	end

	-- Calzada y manzana no se confunden: los destinos van en cruces, los edificios
	-- dentro de las manzanas, y nada puede caer en los dos sitios.
	kit.truthy("un cruce esta en calzada", Grid.enCalle(Grid.xDeCalle(1), Grid.zDeCalle(2)))
	local centro = Grid.centroManzana(1, 2)
	kit.falsy("el centro de una manzana no lo esta", Grid.enCalle(centro.X, centro.Z))
	kit.eq("y ese centro es el que dice el plano", centro, Vector3.new(-547, Grid.Y, 681))

	-- Cada manzana mide lo que dice medir. Si esto falla, las calles se solapan con
	-- los edificios y el pathfinding empieza a dar rodeos que nadie entiende.
	for col = 0, Grid.COLUMNAS - 1 do
		for fila = 0, Grid.FILAS - 1 do
			local x0, x1, z0, z1 = Grid.manzana(col, fila)
			kit.eq(string.format("ancho de la manzana %d,%d", col, fila), x1 - x0, Grid.LADO_MANZANA)
			kit.eq(string.format("largo de la manzana %d,%d", col, fila), z1 - z0, Grid.LADO_MANZANA)
		end
	end

	-- El mapa entero cabe donde dice el spec: 610 x 464. Es un mapa PEQUEÑO a
	-- propósito -- el problema medido es que no se entiende dónde se está, no que
	-- falte sitio-- y crecer luego es añadir una columna, que es barato; encoger un
	-- mapa al que ya se le ha colgado contenido, no.
	local xMin, xMax, zMin, zMax = Grid.limites()
	kit.eq("el mapa mide 610 de ancho", xMax - xMin, 610)
	kit.eq("y 464 de largo", zMax - zMin, 464)
	kit.eq(
		"el ancho sale de las columnas",
		xMax - xMin,
		Grid.COLUMNAS * Grid.LADO_MANZANA + (Grid.COLUMNAS + 1) * Grid.ANCHO_CALLE
	)
	kit.eq("y el largo de las filas", zMax - zMin, Grid.FILAS * Grid.LADO_MANZANA + (Grid.FILAS + 1) * Grid.ANCHO_CALLE)
end
