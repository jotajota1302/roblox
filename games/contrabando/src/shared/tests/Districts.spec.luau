--!strict
-- El plano de la ciudad. Lo que se fija aqui no es "que manzana es cada cosa" --eso
-- es una decision de diseno y se cambia cuando toque-- sino las dos propiedades que
-- hacen que la ciudad se lea: que no haya un patron visible, y que cada zona tenga a
-- la vez por donde cortar y por donde no.
local Districts = require(script.Parent.Parent.Districts)
local Grid = require(script.Parent.Parent.Grid)

return function(kit)
	local manzanas = Districts.manzanas()
	local cuantas = (Grid.COL_MAX - Grid.COL_MIN) * (Grid.FILA_MAX - Grid.FILA_MIN)
	kit.eq("la ciudad tiene una manzana por hueco de la reticula", #manzanas, cuantas)

	-- TODAS TIENEN USO, Y NINGUNA LO TIENE POR DESCUIDO. El respaldo de `uso` devuelve
	-- residencial para lo que no este en el plano, asi que una manzana olvidada no da
	-- error -- sale como una manzana normal y nadie se entera. Se comprueba contra el
	-- plano escrito, no contra el respaldo.
	local sinPlano = 0
	for _, m in manzanas do
		if not Districts.declarado(m.col, m.fila) then
			sinPlano += 1
		end
	end
	kit.eq("ninguna manzana se queda fuera del plano", sinPlano, 0)

	-- NI TRES IGUALES SEGUIDAS EN UNA FILA NI EN UNA COLUMNA. Es la definicion
	-- operativa de "copy paste": dos manzanas parecidas es un barrio, tres en linea
	-- es un patron -- y en cuanto el ojo ve el patron, deja de usar la ciudad para
	-- orientarse. Es justo lo que pasaba con la version anterior, donde las doce eran
	-- la misma.
	local trios = 0
	for fila = Grid.FILA_MIN, Grid.FILA_MAX - 1 do
		for col = Grid.COL_MIN, Grid.COL_MAX - 3 do
			local a = Districts.uso(col, fila)
			if a == Districts.uso(col + 1, fila) and a == Districts.uso(col + 2, fila) then
				trios += 1
			end
		end
	end
	for col = Grid.COL_MIN, Grid.COL_MAX - 1 do
		for fila = Grid.FILA_MIN, Grid.FILA_MAX - 3 do
			local a = Districts.uso(col, fila)
			if a == Districts.uso(col, fila + 1) and a == Districts.uso(col, fila + 2) then
				trios += 1
			end
		end
	end
	kit.eq("no hay tres manzanas iguales en linea", trios, 0)

	-- CADA ZONA, LAS DOS COSAS. Una banda entera cerrada obliga a ir por la calle
	-- siempre --y entonces la persecucion no tiene lectura-- y una banda entera
	-- abierta es un descampado por el que se corta en diagonal, que fue justamente el
	-- motivo de cerrar las manzanas el 19/08.
	local abiertas: { [string]: number } = {}
	local cerradas: { [string]: number } = {}
	for _, m in manzanas do
		if Districts.atravesable(m.uso) then
			abiertas[m.zona] = (abiertas[m.zona] or 0) + 1
		else
			cerradas[m.zona] = (cerradas[m.zona] or 0) + 1
		end
	end
	for _, zona in { "verde", "ambar", "roja", "afueras" } do
		kit.truthy("la zona " .. zona .. " tiene por donde cortar", (abiertas[zona] or 0) >= 1)
		kit.truthy("y la zona " .. zona .. " tiene algo que rodear", (cerradas[zona] or 0) >= 1)
	end

	-- Y EN CONJUNTO, MAS CERRADO QUE ABIERTO. Con media ciudad atravesable el trazado
	-- de calles deja de significar nada: el camino mas corto seria siempre la linea
	-- recta, y toda la decision de por donde ir se evapora.
	local totalAbiertas = 0
	for _, m in manzanas do
		if Districts.atravesable(m.uso) then
			totalAbiertas += 1
		end
	end
	kit.truthy(
		string.format("se cruza menos de la mitad de la ciudad (%d de %d)", totalAbiertas, #manzanas),
		totalAbiertas * 2 < #manzanas
	)

	-- LA PLAZA, ENFRENTE DE LA BOCA. Es el unico punto de referencia que ve TODO el
	-- mundo en TODAS las partidas --la salida de casa da a ella-- y por eso su sitio
	-- se fija aqui: moverla a una esquina del mapa no rompe nada y deja al jugador sin
	-- el unico sitio del que se acuerda.
	kit.eq("la plaza sigue enfrente de la salida del recinto", Districts.uso(1, 2), Districts.PLAZA)

	-- TODOS LOS USOS DECLARADOS SE USAN. Un uso que no aparece en el plano es codigo
	-- muerto que ademas hay que mantener: cada uno tiene su plantador en MapBuilder.
	local usados: { [string]: boolean } = {}
	for _, m in manzanas do
		usados[m.uso] = true
	end
	for _, uso in
		{
			Districts.RESIDENCIAL,
			Districts.TORRES,
			Districts.MERCADO,
			Districts.TALLERES,
			Districts.PLAZA,
			Districts.PARQUE,
			Districts.SOLAR,
			Districts.APARCAMIENTO,
		}
	do
		kit.truthy("el uso " .. uso .. " esta en el plano", usados[uso] == true)
	end

	-- LAS AFUERAS SON DE EXPLORACION, NO DE PASO. La fila -1 no tiene ruta: si algun
	-- dia un destino cayera ahi, la banda dejaria de premiar salirse del camino y
	-- pasaria a ser un tramo mas del viaje.
	for _, m in manzanas do
		if m.fila == Grid.FILA_MIN then
			kit.eq("la fila mas lejana es afueras", m.zona, "afueras")
		end
	end
end
