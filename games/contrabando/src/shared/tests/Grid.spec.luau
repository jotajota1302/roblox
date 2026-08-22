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
	kit.eq("la ultima calle vertical cierra el este", Grid.xDeCalle(Grid.COL_MAX), -182)
	kit.eq("la ultima calle horizontal es la del recinto", Grid.zDeCalle(Grid.FILA_MAX), 754)
	kit.eq("la primera cierra el sur", Grid.zDeCalle(0), 316)

	-- El paso, constante. Es lo que hace que esto sea una retícula y no un plano
	-- dibujado a mano: en cuanto una calle se mueve "un poco", el jugador deja de
	-- poder predecir dónde está la siguiente.
	for i = Grid.COL_MIN + 1, Grid.COL_MAX do
		kit.eq("paso constante entre calles verticales " .. i, Grid.xDeCalle(i) - Grid.xDeCalle(i - 1), Grid.PASO)
	end
	for j = Grid.FILA_MIN + 1, Grid.FILA_MAX do
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
	local boca = Vector3.new(Grid.xDeCalle(1), Grid.Y, Grid.zDeCalle(Grid.FILA_MAX))
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
	-- El centro se corre 6 studs al este porque la manzana (1,2) da a la avenida por
	-- su lado oeste: la calle 1 se ensancho de 26 a 50 y la manzana perdio 12 por ahi.
	kit.eq("y ese centro es el que dice el plano", centro, Vector3.new(-541, Grid.Y, 681))

	-- CADA MANZANA MIDE LO NOMINAL MENOS LO QUE LE COMAN SUS AVENIDAS, y esta es la
	-- regla de verdad desde que hay dos anchos de calle. Antes se comprobaba contra
	-- `LADO_MANZANA` a secas, lo cual era la misma regla escrita para un mapa en el
	-- que todas las calles median igual.
	--
	-- Se deriva de `anchoDeCalleX/Z` en vez de escribir 108 y 96 a mano: asi la
	-- prueba sigue siendo cierta el dia que se mueva una avenida o cambie su ancho,
	-- que es lo unico que distingue una prueba de una foto del estado actual.
	for col = Grid.COL_MIN, Grid.COL_MAX - 1 do
		for fila = Grid.FILA_MIN, Grid.FILA_MAX - 1 do
			local x0, x1, z0, z1 = Grid.manzana(col, fila)
			local comeX = (Grid.anchoDeCalleX(col) + Grid.anchoDeCalleX(col + 1)) / 2 - Grid.ANCHO_CALLE
			local comeZ = (Grid.anchoDeCalleZ(fila) + Grid.anchoDeCalleZ(fila + 1)) / 2 - Grid.ANCHO_CALLE
			kit.eq(string.format("ancho de la manzana %d,%d", col, fila), x1 - x0, Grid.LADO_MANZANA - comeX)
			kit.eq(string.format("largo de la manzana %d,%d", col, fila), z1 - z0, Grid.LADO_MANZANA - comeZ)
		end
	end

	-- El mapa entero: 902 x 610 desde la segunda ampliacion (22/08). Fue 610 x 464 con
	-- la reticula en 4x3 y 756 x 610 con la de 5x4. Las dos veces crecio por indices
	-- NEGATIVOS --al oeste y al norte-- que es lo que permite ampliar sin mover una
	-- sola coordenada de las que ya estaban escritas. Encoger un mapa al que ya se le
	-- ha colgado contenido no es igual de barato, y por eso se crece despacio.
	local xMin, xMax, zMin, zMax = Grid.limites()
	kit.eq("el mapa mide 902 de ancho", xMax - xMin, 902)
	kit.eq("y 610 de largo", zMax - zMin, 610)
	kit.eq(
		"el ancho sale de las columnas",
		xMax - xMin,
		(Grid.COL_MAX - Grid.COL_MIN) * Grid.LADO_MANZANA + (Grid.COL_MAX - Grid.COL_MIN + 1) * Grid.ANCHO_CALLE
	)
	kit.eq(
		"y el largo de las filas",
		zMax - zMin,
		(Grid.FILA_MAX - Grid.FILA_MIN) * Grid.LADO_MANZANA + (Grid.FILA_MAX - Grid.FILA_MIN + 1) * Grid.ANCHO_CALLE
	)

	-- LA RUTA DEL GPS. Lo que la hace un GPS y no un dibujo es que EMPIEZA DONDE
	-- ESTAS: si el primer punto no eres tu, la linea del plano se queda quieta
	-- mientras el jugador se mueve, y entonces solo acierta si vas por donde ella
	-- creia. Eso es una ilustracion, no una guia.
	local yo = Vector3.new(Grid.xDeCalle(1) + 30, Grid.Y, Grid.zDeCalle(2) + 10)
	local meta = Grid.cruce(3, 0)
	local ruta = Grid.rutaGps(yo, meta)
	kit.truthy("la ruta tiene al menos dos puntos", #ruta >= 2)
	kit.near("empieza donde estas (X)", ruta[1].X, yo.X, 0.01)
	kit.near("y donde estas (Z)", ruta[1].Z, yo.Z, 0.01)
	kit.near("acaba en el destino (X)", ruta[#ruta].X, meta.X, 0.01)
	kit.near("y en el destino (Z)", ruta[#ruta].Z, meta.Z, 0.01)

	-- CADA TRAMO VA POR UN SOLO EJE. Un tramo en diagonal en una reticula significa
	-- cruzar por dentro de una manzana: el plano estaria dibujando un camino que no
	-- existe, que es peor que no dibujar ninguno.
	local diagonales = 0
	for i = 2, #ruta do
		local a, b = ruta[i - 1], ruta[i]
		if math.abs(a.X - b.X) > 0.5 and math.abs(a.Z - b.Z) > 0.5 then
			diagonales += 1
		end
	end
	kit.eq("ningun tramo va en diagonal", diagonales, 0)

	-- Y NINGUN TRAMO DE LONGITUD CERO: no se pueden dibujar y ademas rompen la
	-- cuenta del siguiente giro, que es lo que mira la brujula.
	local vacios = 0
	for i = 2, #ruta do
		if (ruta[i] - ruta[i - 1]).Magnitude < 1 then
			vacios += 1
		end
	end
	kit.eq("ni ninguno de longitud cero", vacios, 0)

	-- ESTANDO YA EN UNA CALLE no hay que apartarse: la ruta no debe empezar con un
	-- quiebro absurdo hacia el lado.
	local enCalle = Vector3.new(Grid.xDeCalle(1), Grid.Y, Grid.zDeCalle(2) + 40)
	local recta = Grid.rutaGps(enCalle, Grid.cruce(1, 0))
	kit.eq("desde una calle recta, la ruta es un solo tramo", #recta, 2)

	-- EL SIGUIENTE PASO es el vertice al que hay que ir AHORA, no el destino final.
	-- Apuntar en linea recta al destino es lo que hacia la brujula, y en una ciudad
	-- eso senala a traves de una manzana que no puedes atravesar.
	local paso = Grid.siguientePaso(ruta, yo, 12)
	kit.truthy("hay un siguiente paso", paso ~= nil)
	kit.truthy("y no es el destino mientras queden giros", #ruta <= 2 or (paso :: Vector3) ~= ruta[#ruta])
	-- Pegado al final, el siguiente paso ES el final: si no, la brujula se quedaria
	-- apuntando a un vertice que ya has pisado.
	local casi = ruta[#ruta] - Vector3.new(0, 0, 3)
	kit.eq("al lado del destino, el paso es el destino", Grid.siguientePaso(ruta, casi, 12), ruta[#ruta])

	-- LA ACERA, que es donde van las camaras desde que JJ pidio que apuntaran a la
	-- calle. Dos cosas que comprobar y las dos importan: que el punto sale FUERA de
	-- la calzada (si no, un vehiculo lo atraviesa) y que el rumbo mira HACIA el eje
	-- de la calle (si no, la camara vigila una pared).
	local medio = Grid.ANCHO_CALLE / 2
	for i = Grid.COL_MIN, Grid.COL_MAX do
		for _, lado in { 1, -1 } do
			local dentro =
				Vector3.new(Grid.xDeCalle(i) + lado * (medio + 20), Grid.Y, Grid.zDeCalle(0) + Grid.LADO_MANZANA / 2)
			local sitio, rumbo = Grid.aceraDe(dentro)
			kit.falsy(
				string.format("la acera de la calle %d lado %d no esta en calzada", i, lado),
				Grid.enCalle(sitio.X, sitio.Z)
			)
			-- El rumbo apunta al eje: el vector de mirada tiene que acercarte a el.
			local mira = (CFrame.Angles(0, math.rad(rumbo), 0) * CFrame.new(0, 0, -1)).Position
			local haciaElEje = Grid.xDeCalle(i) - sitio.X
			kit.truthy(string.format("y mira hacia la calle %d lado %d", i, lado), mira.X * haciaElEje > 0)
		end
	end

	-- Y DESDE UN CRUCE, que es donde fallaba: apartarse de una calle dejaba el poste
	-- dentro de la otra. Medido en el mundo antes de arreglarlo: 14 camaras de 43
	-- plantadas en plena calzada, todas en esquinas.
	for i = Grid.COL_MIN, Grid.COL_MAX do
		for j = Grid.FILA_MIN, Grid.FILA_MAX do
			local cruce = Grid.cruce(i, j)
			local sitio = Grid.aceraDe(cruce + Vector3.new(4, 0, 4))
			kit.falsy(string.format("la acera del cruce %d,%d no cae en calzada", i, j), Grid.enCalle(sitio.X, sitio.Z))
		end
	end

	-- Y da igual desde donde se pregunte: un punto en mitad de la manzana tiene que
	-- salir en una acera de verdad, no a medio camino.
	local centro = Grid.centroManzana(1, 1)
	local sitioC, _ = Grid.aceraDe(centro)
	kit.falsy("la acera del centro de una manzana tampoco cae en calzada", Grid.enCalle(sitioC.X, sitioC.Z))
	kit.near("y conserva la altura que se le pasa", sitioC.Y, centro.Y)

	-- ── LAS AVENIDAS ──────────────────────────────────────────────────────────
	--
	-- LO QUE MAS IMPORTA DE TODO ESTO: que ensanchar una calle NO haya movido nada.
	-- Es la promesa entera del diseno --por eso el ancho de mas se come manzana en
	-- vez de correr el eje-- y es tambien la trampa que ya se pago una vez, cuando
	-- ampliar la reticula por el lado equivocado habria movido los tres destinos y la
	-- salida de casa sin dar un solo error.
	kit.eq("la calle de casa sigue en su X de siempre", Grid.xDeCalle(1), -620)
	kit.eq("y la calle norte, la de la boca del recinto, tambien", Grid.cruce(1, 3), Vector3.new(-620, Grid.Y, 754))
	kit.eq("el paso entre ejes no lo toca una avenida", Grid.PASO, Grid.LADO_MANZANA + Grid.ANCHO_CALLE)

	kit.truthy("una avenida es mas ancha que una calle", Grid.ANCHO_AVENIDA > Grid.ANCHO_CALLE)
	kit.truthy("la calle 1 es avenida", Grid.esAvenidaX(1))
	kit.falsy("la 0 no", Grid.esAvenidaX(0))
	kit.eq("y su ancho lo dice", Grid.anchoDeCalleX(1), Grid.ANCHO_AVENIDA)
	kit.eq("el de una normal tambien", Grid.anchoDeCalleX(0), Grid.ANCHO_CALLE)
	kit.eq("la rotonda va donde se cruzan las dos", Grid.cruceDeAvenidas(), Grid.cruce(1, 1))

	-- El ancho de mas es asfalto de verdad: un punto que en una calle normal estaria
	-- sobre la acera, en la avenida esta en calzada.
	local aLado = Grid.ANCHO_CALLE / 2 + 4
	kit.truthy("a 17 del eje de la avenida todavia se pisa asfalto", Grid.enCalle(Grid.xDeCalle(1) + aLado, 500))
	kit.falsy("y a esa misma distancia de una calle normal, no", Grid.enCalle(Grid.xDeCalle(0) + aLado, 500))

	-- NINGUNA MANZANA SE QUEDA SIN SITIO. Es el limite de cuanto se puede ensanchar:
	-- una manzana con avenida en sus cuatro lados perderia 48 studs, y ahi ya no cabe
	-- lo que se planta dentro. Se comprueba contra la mas pequena que exista, que es
	-- la unica forma de que este numero siga significando algo si manana hay tres
	-- avenidas.
	local MINIMO_UTIL = 90
	for col = Grid.COL_MIN, Grid.COL_MAX - 1 do
		for fila = Grid.FILA_MIN, Grid.FILA_MAX - 1 do
			local ancho, largo = Grid.tamanoManzana(col, fila)
			kit.truthy(
				string.format("la manzana %d,%d conserva sitio utilizable (%dx%d)", col, fila, ancho, largo),
				ancho >= MINIMO_UTIL and largo >= MINIMO_UTIL
			)
		end
	end

	-- Y LA ACERA DE LA AVENIDA ESTA FUERA DE SU ASFALTO, que es donde `aceraDe` se
	-- habria equivocado callando: con el ancho global el poste caia doce studs dentro
	-- de la calzada -- plantado, sin error, y en medio del carril.
	for _, j in { Grid.FILA_MIN, 0, 1, 2 } do
		local sobreLaAvenida = Vector3.new(Grid.xDeCalle(1) + 6, Grid.Y, Grid.zDeCalle(j) + 40)
		local acera = Grid.aceraDe(sobreLaAvenida)
		kit.falsy(
			string.format("la acera junto a la avenida (fila %d) no cae en su calzada", j),
			Grid.enCalle(acera.X, acera.Z)
		)
	end
end
