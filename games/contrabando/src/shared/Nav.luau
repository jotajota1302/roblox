--!strict
--[[
	Nav.luau — a qué botón se salta con una flecha. Módulo PURO.

	POR QUÉ EXISTE, y por qué es puro. *"La eleccion del objetivo deberia poder hacerse
	con el mando o las flechas y el enter o algun boton, no solo con el raton"* (JJ,
	22/08). La navegación por selección de Roblox la mueve el mando y NADA MÁS: con
	teclado hay que decidir a mano a qué botón lleva cada flecha.

	Y esa decisión es la única parte con riesgo de todo el asunto -- lo demás es
	enlazar teclas. Vive aquí, separada de `Pad`, porque **es aritmética sobre cuatro
	números y se puede probar sin abrir Studio**, que en este proyecto no es una
	preferencia: `user_keyboard_input` del MCP NO entrega teclas cuando Studio está en
	segundo plano (medido el 22/08 con un espía a prioridad 9000 y un `InputBegan`
	crudo, los dos vacíos), así que una navegación escrita dentro de `Pad` no se podría
	comprobar de ninguna manera hasta que alguien la jugara.

	EL CRITERIO: de lo que hay seleccionado, se salta al botón más cercano HACIA DONDE
	SE HA PULSADO, y la desviación pesa el triple que el avance. Ese tres es lo que
	hace que una columna de botones se recorra en orden con la flecha de abajo en vez
	de irse en diagonal a lo que quede un poco más cerca en línea recta -- y es la
	diferencia entre una navegación que se entiende sola y una que parece rota.
]]

local Nav = {}

-- Un botón, reducido a lo que hace falta para decidir. `id` es lo que se devuelve, y
-- así el módulo no sabe nada de instancias de Roblox: es lo que lo hace probable.
export type Candidato = {
	id: any,
	centro: Vector2,
}

-- El candidato al que lleva la flecha `(dx, dy)` desde `desde`, o nil si no hay
-- ninguno en esa dirección.
--
-- OJO CON EL EJE Y: en pantalla crece HACIA ABAJO, así que la flecha de abajo es
-- `dy = 1`. Escribirlo al revés da una navegación en la que todo va del revés y que
-- parece un fallo de otra cosa.
function Nav.siguiente(candidatos: { Candidato }, desde: Vector2, dx: number, dy: number): any?
	local mejor: any = nil
	local mejorCoste = math.huge
	for _, c in candidatos do
		local ex, ey = c.centro.X - desde.X, c.centro.Y - desde.Y
		local avance = ex * dx + ey * dy
		-- UN STUD DE MARGEN, no cero: dos botones de la misma fila tienen centros que
		-- difieren en decimales por el redondeo del layout, y con `> 0` la flecha de
		-- abajo saltaría a uno de al lado por medio píxel de diferencia.
		if avance <= 1 then
			continue
		end
		local desviacion = math.abs(ex * dy) + math.abs(ey * dx)
		local coste = avance + desviacion * 3
		if coste < mejorCoste then
			mejorCoste, mejor = coste, c.id
		end
	end
	return mejor
end

return Nav
