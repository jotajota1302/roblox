--!strict
-- La navegación con flechas. Es lo único del control por teclado que se puede probar
-- sin jugar, y por eso está separada de `Pad`: el resto es enlazar teclas, y las
-- teclas no se pueden mandar desde aquí (`user_keyboard_input` del MCP no las entrega
-- con Studio en segundo plano, medido el 22/08).
local Nav = require(script.Parent.Parent.Nav)

return function(kit)
	local function punto(id, x, y)
		return { id = id, centro = Vector2.new(x, y) }
	end

	-- UNA CRUZ: cada flecha lleva a su brazo y a ninguno de los otros tres. Es el caso
	-- mínimo, y falla en cuanto alguien confunde el signo de la Y.
	local cruz = {
		punto("arriba", 100, 50),
		punto("abajo", 100, 150),
		punto("izq", 50, 100),
		punto("der", 150, 100),
	}
	local centro = Vector2.new(100, 100)
	kit.eq("la flecha de arriba sube", Nav.siguiente(cruz, centro, 0, -1), "arriba")
	kit.eq("la de abajo baja", Nav.siguiente(cruz, centro, 0, 1), "abajo")
	kit.eq("la de la izquierda va a la izquierda", Nav.siguiente(cruz, centro, -1, 0), "izq")
	kit.eq("y la de la derecha, a la derecha", Nav.siguiente(cruz, centro, 1, 0), "der")

	-- EN EL BORDE NO SE SALE. Un menú tiene un primer y un último botón, y la flecha
	-- que apunta fuera tiene que no hacer nada -- envolver hasta el otro extremo se
	-- siente como un salto aleatorio cuando no lo esperas.
	kit.eq("desde el brazo de arriba no se sube mas", Nav.siguiente(cruz, Vector2.new(100, 50), 0, -1), nil)

	-- UNA COLUMNA SE RECORRE EN ORDEN, que es el caso de verdad: el menú lateral y el
	-- selector de rutas son columnas.
	local columna = { punto("a", 100, 100), punto("b", 100, 160), punto("c", 100, 220) }
	kit.eq("de la primera a la segunda", Nav.siguiente(columna, Vector2.new(100, 100), 0, 1), "b")
	kit.eq("de la segunda a la tercera", Nav.siguiente(columna, Vector2.new(100, 160), 0, 1), "c")
	kit.eq("y de la tercera no se pasa", Nav.siguiente(columna, Vector2.new(100, 220), 0, 1), nil)

	-- Y NO SE VA EN DIAGONAL. Este es el que justifica que la desviación pese el
	-- triple: `lejos` está más abajo en línea recta, pero `alLado` está a un palmo en
	-- diagonal y con un peso de 1 ganaría -- la flecha de abajo saltaría de columna, y
	-- eso es exactamente lo que hace que una navegación parezca rota.
	local diagonal = {
		punto("justoDebajo", 100, 200),
		punto("alLado", 190, 130),
	}
	kit.eq(
		"la flecha de abajo baja aunque haya algo mas cerca en diagonal",
		Nav.siguiente(diagonal, Vector2.new(100, 100), 0, 1),
		"justoDebajo"
	)

	-- LOS DECIMALES DE LA MISMA FILA NO CUENTAN COMO "ARRIBA". El layout deja centros
	-- que difieren en fracciones de píxel, y con un umbral de cero la flecha de arriba
	-- saltaría a un botón de al lado por medio píxel. Se pide un stud de avance real.
	local fila = { punto("mismaFila", 200, 100.4) }
	kit.eq("medio pixel no es estar debajo", Nav.siguiente(fila, Vector2.new(100, 100), 0, 1), nil)
	kit.eq("pero sigue estando a la derecha", Nav.siguiente(fila, Vector2.new(100, 100), 1, 0), "mismaFila")

	-- UNA REJILLA: dos filas de tres, que es la forma del garaje.
	local rejilla = {}
	for f = 0, 1 do
		for c = 0, 2 do
			table.insert(rejilla, punto(string.format("%d%d", f, c), 100 + c * 80, 100 + f * 90))
		end
	end
	kit.eq("dentro de la fila, a la derecha", Nav.siguiente(rejilla, Vector2.new(100, 100), 1, 0), "01")
	kit.eq("y abajo se cambia de fila por la misma columna", Nav.siguiente(rejilla, Vector2.new(100, 100), 0, 1), "10")

	-- SIN CANDIDATOS NO REVIENTA. Un panel puede quedarse sin botones visibles a mitad
	-- de un repintado, y eso no puede tirar el control del jugador.
	kit.eq("una lista vacia no da nada", Nav.siguiente({}, centro, 0, 1), nil)
end
