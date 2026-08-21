--!strict
--[[
	Pose.luau — posar articulaciones sin pelearse con el rig. Modulo PURO.

	POR QUE EXISTE, y son dos tardes pagadas por la misma cuenta.

	En un R6 las caderas y los hombros vienen con el C0 girado un cuarto de vuelta en
	Y, asi que lo que balancea una pierna adelante y atras es un giro sobre su Z
	local -- no sobre X, que es lo que uno escribiria a ojo. Y ademas el lado
	IZQUIERDO viene espejado (su C0 gira -90 en vez de +90), de modo que el mismo
	numero significa lo contrario en cada pierna.

	Eso ya costo una tarde en `Patrullas`: los signos alternados --que es lo logico
	sobre el papel-- daban el pie izquierdo con EXACTAMENTE los mismos valores que el
	derecho, doce muestras seguidas. Las dos piernas a la vez: un salto de conejo.

	La solucion de entonces fue aprenderse los signos correctos. La de ahora es no
	tener que aprenderselos: se pide la rotacion en el marco del TORSO --donde X es
	"hacia tu derecha" pase lo que pase-- y se traduce al marco de cada junta con su
	propio C0. El espejo se cancela solo, y de regalo el mismo codigo vale para un
	R15, cuyos C0 no llevan ese giro.

	Y ESTA MEDIDO, no deducido. La bateria comprueba las dos cosas que importan: que
	un angulo positivo mueve el pie hacia delante (-Z en Roblox) y que dos caderas
	espejadas responden IGUAL al mismo numero. La primera version de `Riders` tenia
	el signo al reves y el patinador habria ido de espaldas -- lo canto esta cuenta
	antes de abrir Studio.
]]

local Pose = {}

-- Los ejes, en el marco del torso.
Pose.DERECHA = Vector3.new(1, 0, 0) -- girar sobre el: adelante y atras
Pose.ARRIBA = Vector3.new(0, 1, 0) -- girar sobre el: abrirse de lado
Pose.FRENTE = Vector3.new(0, 0, -1) -- girar sobre el: inclinarse a un lado

-- El signo de "hacia delante" al girar sobre DERECHA. Medido: con +30 grados el pie
-- se desplaza -0,75 en Z, y en Roblox -Z es el frente. O sea que positivo es
-- adelante, y la constante existe para que quien lea la pose no tenga que acordarse.
Pose.ADELANTE = 1

-- Una rotacion pedida en el marco del torso, expresada en el marco de la junta.
--
-- Se aplica como `motor.C0 = base * Pose.enTorso(base, eje, grados)`: multiplicando
-- POR LA DERECHA se gira alrededor del origen de la junta, que es la cadera o el
-- hombro. Por la izquierda giraria alrededor del origen del torso, y entonces la
-- pierna no se dobla: se traslada en arco.
function Pose.enTorso(base: CFrame, eje: Vector3, grados: number): CFrame
	return CFrame.fromAxisAngle(base:VectorToObjectSpace(eje), math.rad(grados))
end

return Pose
