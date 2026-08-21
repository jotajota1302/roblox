--!strict
-- La cuenta que decide si un personaje anda hacia delante o hacia atras. Se prueba
-- aqui porque es aritmetica de CFrames y no necesita ni rig ni Studio -- y porque el
-- fallo que evita no da error: da un patinador de espaldas, o dos piernas moviendose
-- a la vez, que es lo que paso en `Patrullas` el 21/08.
local Pose = require(script.Parent.Parent.Pose)

return function(kit)
	-- El C0 de una cadera R6: girado +90 en Y la derecha, -90 la izquierda. La
	-- traslacion no importa para esto, solo la rotacion.
	local derecha = CFrame.Angles(0, math.rad(90), 0)
	local izquierda = CFrame.Angles(0, math.rad(-90), 0)
	-- Donde cae el pie respecto a la cadera, en el marco de la junta.
	local PIE = Vector3.new(0, -1.5, 0)

	local function desplazamiento(base: CFrame, grados: number): Vector3
		local reposo = base * PIE
		local movido = (base * Pose.enTorso(base, Pose.DERECHA, grados)) * PIE
		return movido - reposo
	end

	-- POSITIVO ES ADELANTE, y en Roblox delante es -Z. Es la constante que estaba mal
	-- en la primera version de `Riders`: con el signo invertido, la pierna de apoyo se
	-- iba detras y la que empuja delante -- o sea el patinador entero al reves.
	local d = desplazamiento(derecha, 30)
	kit.truthy(string.format("un angulo positivo lleva el pie hacia delante (dZ=%.2f)", d.Z), d.Z < -0.5)
	kit.eq("y la constante ADELANTE lo dice", Pose.ADELANTE, 1)

	-- Y AL REVES, HACIA ATRAS. Sin esta, un `math.abs` perdido en la formula pasaria
	-- desapercibido: la prueba de arriba seguiria en verde.
	local atras = desplazamiento(derecha, -30)
	kit.truthy(string.format("y uno negativo, hacia atras (dZ=%.2f)", atras.Z), atras.Z > 0.5)

	-- LOS DOS LADOS RESPONDEN IGUAL AL MISMO NUMERO. Es el punto entero del modulo: el
	-- espejo del R6 se cancela en la traduccion, asi que quien escribe una pose no
	-- tiene que saber que el C0 izquierdo viene al reves. Si esto se rompe, volvemos a
	-- los signos magicos y a las dos piernas moviendose a la vez.
	local dIzq = desplazamiento(izquierda, 30)
	kit.near("la cadera izquierda va igual que la derecha en Z", dIzq.Z, d.Z, 0.001)
	kit.near("y tambien en Y", dIzq.Y, d.Y, 0.001)

	-- NADA SE VA DE LADO. Girar sobre el eje "derecha" del torso solo puede mover el
	-- pie en el plano de avance: si aparece componente X, el eje esta mal traducido --
	-- que es exactamente lo que pasaba usando X local en vez de Z en un R6, y se veia
	-- como un personaje abriendose de piernas en cruz.
	kit.near("la pierna no se abre de lado", d.X, 0, 0.001)
	kit.near("ni la izquierda", dIzq.X, 0, 0.001)

	-- Y SIN ANGULO, SIN MOVIMIENTO. Parece obvio y no lo es: una traduccion de marcos
	-- mal montada puede desplazar la junta con angulo cero.
	local quieto = desplazamiento(derecha, 0)
	kit.near("con cero grados el pie no se mueve", quieto.Magnitude, 0, 0.001)
end
