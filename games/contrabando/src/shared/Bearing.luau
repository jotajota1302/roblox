--!strict
--[[
	Bearing.luau — cuánto hay que girar la aguja de la brújula. Módulo PURO.

	Vive aparte del widget POR UN FALLO QUE SÓLO SE VE JUGANDO. La primera versión
	tenía el signo invertido: con el objetivo a la derecha la aguja giraba −90 en
	vez de +90, así que apuntaba exactamente al lado contrario. No hay error, no hay
	aviso, no hay nada raro en pantalla -- la flecha se mueve con suavidad y parece
	perfectamente correcta hasta que sigues su dirección y acabas donde no era.

	El detalle que lo causa, y que se olvida siempre: **la UI de Roblox rota en
	sentido HORARIO con Rotation positivo**, mientras que el producto cruzado da el
	ángulo en el sentido matemático (antihorario). Los dos convenios son razonables
	y opuestos, y el único modo de no volver a equivocarse es fijarlo en una prueba
	con cuatro casos que cualquiera puede comprobar de cabeza.
]]

local Bearing = {}

-- Grados que hay que rotar una aguja que apunta ARRIBA para que señale a `hacia`,
-- estando la cámara orientada según `mirada`.
--
-- Relativo a la cámara y no al norte a propósito: una brújula de norte obliga a
-- traducir dos veces (hacia dónde miro, dónde está el norte, dónde queda entonces
-- el objetivo). Ésta se lee sin pensar -- si la aguja apunta arriba, sigue recto.
--
-- Devuelve nil cuando la pregunta no tiene respuesta: cámara mirando en vertical,
-- o el objetivo justo bajo tus pies. Quien llame decide qué hacer, en vez de
-- recibir un cero que significaría "sigue recto".
function Bearing.grados(mirada: Vector3, hacia: Vector3): number?
	local m = Vector3.new(mirada.X, 0, mirada.Z)
	local o = Vector3.new(hacia.X, 0, hacia.Z)
	if m.Magnitude < 0.001 or o.Magnitude < 0.001 then
		return nil
	end
	m, o = m.Unit, o.Unit

	-- atan2 del cruzado y el escalar: da el giro CON SIGNO, que es lo que separa
	-- "gira a la izquierda" de "gira a la derecha". Y negado, porque el cruzado
	-- mide en antihorario y Rotation gira en horario.
	return -math.deg(math.atan2(m:Cross(o).Y, m:Dot(o)))
end

return Bearing
