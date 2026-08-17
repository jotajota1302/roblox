--!strict
local Bearing = require(script.Parent.Parent.Bearing)

return function(kit)
	-- Los cuatro casos que cualquiera puede comprobar de cabeza, mirando hacia -Z
	-- (el "adelante" habitual de Roblox). Existen porque el signo estuvo invertido
	-- y la brújula apuntaba al lado contrario SIN dar ningún error: la flecha se
	-- movía con suavidad y parecía correcta hasta que la seguías.
	--
	-- La clave, que se olvida siempre: la UI de Roblox rota en sentido HORARIO con
	-- Rotation positivo, y el producto cruzado mide en el sentido contrario.
	local mirando = Vector3.new(0, 0, -1)

	kit.near("lo que tienes delante no gira la aguja", Bearing.grados(mirando, Vector3.new(0, 0, -1)) or -1, 0)
	kit.near("lo de la derecha la gira en horario", Bearing.grados(mirando, Vector3.new(1, 0, 0)) or -1, 90)
	kit.near("lo de la izquierda, al reves", Bearing.grados(mirando, Vector3.new(-1, 0, 0)) or -1, -90)
	kit.near("lo de detras la pone del reves", math.abs(Bearing.grados(mirando, Vector3.new(0, 0, 1)) or 0), 180)

	-- Y girando la cámara, el resultado tiene que girar con ella: es una brújula
	-- relativa a la vista, no al norte. Mirando hacia +X, lo que está en +X pasa a
	-- estar delante.
	kit.near(
		"mirando al este, el este esta delante",
		Bearing.grados(Vector3.new(1, 0, 0), Vector3.new(1, 0, 0)) or -1,
		0
	)
	kit.near("y el sur queda a la derecha", Bearing.grados(Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)) or -1, 90)

	-- La altura no cuenta: un objetivo en una azotea justo encima sigue estando
	-- "delante", no arriba. Una brújula que reaccionara a la altura haría cosas
	-- raras cada vez que el jugador sube una rampa.
	kit.near("la altura del objetivo no cambia el rumbo", Bearing.grados(mirando, Vector3.new(1, 200, 0)) or -1, 90)
	kit.near(
		"ni la inclinacion de la camara",
		Bearing.grados(Vector3.new(0, -0.8, -0.6), Vector3.new(1, 0, 0)) or -1,
		90
	)

	-- Cuando la pregunta no tiene respuesta se dice, en vez de devolver un cero que
	-- significaria "sigue recto" y mandaria al jugador de frente contra un muro.
	kit.falsy("camara en vertical no da rumbo", Bearing.grados(Vector3.new(0, 1, 0), Vector3.new(1, 0, 0)) ~= nil)
	kit.falsy("un objetivo bajo tus pies tampoco", Bearing.grados(mirando, Vector3.new(0, 5, 0)) ~= nil)
end
