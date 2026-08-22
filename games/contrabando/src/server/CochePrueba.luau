--!strict
--[[
	CochePrueba.luau — UN COCHE DE VERDAD, para contestar una pregunta jugándola.

	POR QUÉ EXISTE. *"Mi hijo está jugando a un juego de Roblox de conducción que va
	perfecto, ¿por qué nosotros no podíamos usar coches?"* (JJ, 22/08). La respuesta
	corta es que sí se puede, y que lo que se midió --106 grados de giro en una décima
	de segundo, o sea pivotar como una peonza-- no era "Roblox no sabe", era que **el
	coche del juego no es un coche**: es `WalkSpeed` más veinte piezas soldadas al
	personaje, y sigues siendo un peatón con una caja encima.

	ESTO ES LO OTRO. Un `Model` aparte del jugador, con su asiento, sus cuatro ruedas
	unidas por constraints y su motor: la física lo mueve, no el `Humanoid`. Tiene
	inercia, radio de giro y morro que apunta a donde vas.

	NO TOCA NADA DEL JUEGO, y eso es la mitad del punto. Se planta si
	`Config.PROTOTIPO_COCHE` está a true y no se entera nadie más: ni el garaje, ni la
	carga, ni la policía, ni `Roads`. Es una pregunta puesta en el mapa -- se sube uno,
	da una vuelta y decide. Si no convence, se borra la constante y con ella el fichero,
	y no ha costado nada.

	LO QUE ESTE PROTOTIPO NO CONTESTA, y hay que decirlo antes de que lo parezca:

	  · si las patrullas pueden alcanzarlo (hoy van a pie: contra esto, o corren igual
	    o el PvP se muere, que es la regla que sostiene el juego entero);
	  · qué pasa al aparcarlo y volver a por él;
	  · cómo se replica entre dos jugadores;
	  · ni si las calles de 26 studs aguantan un radio de giro creíble.

	Contesta UNA cosa, que es la que se preguntó: cómo se siente conducir aquí.

	SIN SUSPENSIÓN, a propósito. Un chasis con muelles es lo siguiente y cuesta el
	doble; la ciudad es plana y sin baches, así que cuatro ruedas rígidas dan la
	sensación entera. Si la respuesta es que sí, la suspensión entra en la versión de
	verdad, no aquí.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Grid = require(game.ReplicatedStorage.Shared.Grid)

local CochePrueba = {}

-- Medidas, en studs. Un coche de Roblox ronda esto, y lo importante es la relación:
-- ANCHO Y BAJO no vuelca, alto y estrecho sí. La primera regla de un coche de juguete
-- es que se quede sobre sus ruedas.
local LARGO = 12
local ANCHO = 6
local ALTO_CHASIS = 1.6
local RADIO_RUEDA = 1.7
local ANCHO_RUEDA = 1

-- Lo que se siente al conducir, y son los tres números que hay que tocar si la
-- respuesta es "va raro":
--
--   · VELOCIDAD es el tope en studs/s. 70 parece mucho al lado de los 36 de la moto,
--     y no lo es: la moto se mueve como un peatón rápido y esto tiene que ACELERAR
--     hasta ahí, que es otra cosa muy distinta de teletransportarse a la velocidad
--     final en un fotograma.
--   · FUERZA es lo que empuja. Corta, arranca despacio; pasada, derrapa en cada salida.
--   · GIRO son los grados que tuercen las ruedas de delante. Treinta es un coche
--     normal; con más, se vuelve un kart y se vuelca en las esquinas.
-- BAJADA de 70 a 58 despues de medir la curva: a setenta el radio salia de 22 studs
-- sobre una calle de 26, o sea que cada esquina de la ciudad se tomaba al limite. No es
-- que el coche no pueda ir a 70 -- es que ESTE mapa no da para ello, y el dato importa
-- mas que el numero: unas calles pensadas para andar no se convierten en circuito por
-- meterles un motor.
local VELOCIDAD = 58
-- SUBIDA a 250.000 despues de medir. Veintidos mil sonaba a mucho y no movia el coche:
-- un chasis de 6x1,6x12 mas cuatro ruedas pesa lo suyo, y el par tiene que vencer eso
-- Y el rozamiento de las ruedas contra el suelo, que aqui esta a proposito muy alto
-- para que agarren. Los coches de Roblox suelen ir con cifras de este orden.
local FUERZA = 250000
local GIRO = 30

local function pieza(nombre: string, tamano: Vector3, cf: CFrame, color: Color3, padre: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.Parent = padre
	return p
end

local function enganche(nombre: string, padre: BasePart, pos: Vector3, eje: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = nombre
	a.Position = pos
	a.Axis = eje
	a.Parent = padre
	return a
end

-- UNA RUEDA, con su mangueta si dirige.
--
-- La dirección necesita DOS articulaciones y no una: la mangueta gira sobre un eje
-- VERTICAL respecto al chasis (eso es torcer el volante) y la rueda gira sobre un eje
-- HORIZONTAL respecto a la mangueta (eso es rodar). Intentarlo con una sola es lo que
-- lleva a girar el coche entero sobre su centro, que es justo el defecto del que se
-- viene huyendo.
local function rueda(
	coche: Model,
	chasis: BasePart,
	lado: number,
	delante: boolean,
	ejesDireccion: { Attachment }
): HingeConstraint?
	-- SEPARADAS DEL CHASIS, no metidas en el. Con `- 0.2` la rueda se solapaba dos
	-- decimas con el costado --de 2,8 a 3,8 contra un chasis que acaba en 3,0-- y dos
	-- piezas del mismo ensamblaje que se tocan rozan: medido, el coche hacia 7 studs en
	-- dos segundos con el motor pedido a 70. El sintoma es identico al de un motor
	-- flojo, y por eso se persigue el numero equivocado.
	local x = lado * (ANCHO / 2 + ANCHO_RUEDA / 2 + 0.15)
	local z = if delante then -LARGO / 2 + 2.6 else LARGO / 2 - 2.6
	local centro = chasis.CFrame * CFrame.new(x, -ALTO_CHASIS / 2 - 0.2, z)

	-- SIN ROTAR, Y ESO ERA EL FALLO. Un cilindro de Roblox tiene su eje de revolución
	-- en su X LOCAL, que aquí ya apunta a los lados del coche porque `centro` hereda la
	-- orientación del chasis. La primera versión lo giraba 90 grados en Z "para
	-- ponerlo de pie" y lo que hacía era tumbarlo: medido, el eje de la rueda trasera
	-- apuntaba a los lados del coche con un 0,00 --o sea, un disco tumbado-- y el coche
	-- recorría 3 studs en dos segundos con un motor pedido a 70.
	--
	-- No daba ningún error, y desde fuera parecía un problema de fuerza. Se ve
	-- preguntándole a la pieza hacia dónde mira su eje, no mirándola.
	local r = pieza(
		(if delante then "RuedaDel" else "RuedaTras") .. (if lado > 0 then "Der" else "Izq"),
		Vector3.new(ANCHO_RUEDA, RADIO_RUEDA * 2, RADIO_RUEDA * 2),
		centro,
		Color3.fromRGB(28, 28, 32),
		coche
	)
	r.Shape = Enum.PartType.Cylinder
	-- AGARRE: sin esto las ruedas patinan sobre el asfalto y el coche se va de lado en
	-- cuanto tuerces. Es el ajuste que separa "conduce" de "flota".
	r.CustomPhysicalProperties = PhysicalProperties.new(0.7, 2, 0, 100, 1)

	local ejeRueda = Vector3.new(1, 0, 0)
	local dondeVa = Vector3.new(x, -ALTO_CHASIS / 2 - 0.2, z)

	if not delante then
		-- TRACCIÓN ATRÁS: motor directo entre el chasis y la rueda.
		local aChasis = enganche("EjeTras", chasis, dondeVa, ejeRueda)
		local aRueda = enganche("Centro", r, Vector3.zero, ejeRueda)
		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor"
		motor.Attachment0 = aChasis
		motor.Attachment1 = aRueda
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = FUERZA
		motor.MotorMaxAcceleration = 90
		motor.AngularVelocity = 0
		motor.Parent = chasis
		return motor
	end

	-- DELANTE: RUEDA LIBRE, Y SE DIRIGE ROTANDO EL EJE DEL ENGANCHE.
	--
	-- La primera versión hacía lo "correcto": una mangueta unida al chasis con un servo
	-- (eso es el volante) y la rueda unida a la mangueta con otro hinge (eso es rodar).
	-- Es como está hecho un coche de verdad y aquí no funcionó -- medido, con el volante
	-- a tope el servo pedía 30 grados y las ruedas se quedaban en 0 y -5. El servo tiene
	-- que vencer a la rueda agarrada al asfalto a través de una mangueta que no pesa
	-- nada, y no puede por mucho par que se le dé.
	--
	-- LO QUE SÍ FUNCIONA es más simple: la rueda cuelga del chasis con un hinge LIBRE, y
	-- para dirigir se gira el EJE de su enganche. Rotar el eje del hinge reorienta la
	-- rueda sin pelearse con nada, porque no hay ninguna articulación intermedia que
	-- tenga que empujar. Dos piezas menos y una cosa menos que se atasca.
	--
	-- No es un truco sucio: es exactamente lo que hace el coche -- el eje delantero
	-- apunta a otro sitio-- sin modelar el mecanismo que lo consigue. Un prototipo tiene
	-- que contestar cómo se SIENTE, no cómo está hecho por dentro.
	local aChasis = enganche("EjeDir", chasis, dondeVa, ejeRueda)
	local aRueda = enganche("Centro", r, Vector3.zero, ejeRueda)
	local libre = Instance.new("HingeConstraint")
	libre.Name = "Libre"
	libre.Attachment0 = aChasis
	libre.Attachment1 = aRueda
	libre.ActuatorType = Enum.ActuatorType.None
	libre.Parent = chasis

	table.insert(ejesDireccion, aChasis)
	return nil
end

-- Planta el coche aparcado en la calle de casa, mirando hacia la ciudad.
function CochePrueba.plantar(padre: Instance): Model?
	local coche = Instance.new("Model")
	coche.Name = "CochePrueba"

	-- APARCADO EN LA CALLE DE LA BOCA, unos studs al este del almacén: en la calzada
	-- (para que ruede desde el primer metro) y a la vista al salir de casa, que si hay
	-- que buscarlo ya empieza mal la prueba.
	local sitio = Vector3.new(Grid.xDeCalle(1) + 8, Grid.Y + 4, Config.POLIGONO_SALIDA.Z - 30)
	local base = CFrame.new(sitio) * CFrame.Angles(0, math.rad(180), 0)

	local chasis = pieza("Chasis", Vector3.new(ANCHO, ALTO_CHASIS, LARGO), base, Color3.fromRGB(178, 62, 52), coche)
	-- LIGERO Y CON AGARRE. Un chasis pesado sobre ruedas pequeñas se hunde y arrastra;
	-- lo que se quiere es que las ruedas manden.
	-- DENSO ABAJO Y LIGERO ARRIBA: es lo que baja el centro de masas y lo que impide
	-- que vuelque. Medido sin esto: a 70 studs/s trazaba la curva con radio 22 y se iba
	-- de lado a mitad de giro. Un coche de juguete no se sostiene por la suspension
	-- --que aqui no hay-- sino por tener el peso abajo.
	--
	-- Y 3,2 Y NO 8, que fue el primer intento: con densidad 8 el chasis pesa tanto que
	-- las ruedas de delante no lo tuercen -- medido, 5 grados de giro en 91 studs, o sea
	-- un radio de mil. Pasar de "vuelca en cada curva" a "no gira" es cambiar un fallo
	-- por otro; el numero bueno esta en medio y solo se encuentra midiendo las dos cosas
	-- a la vez, el vuelco Y el radio.
	chasis.CustomPhysicalProperties = PhysicalProperties.new(3.2, 0.3, 0.5, 1, 1)
	coche.PrimaryPart = chasis

	-- La carrocería, sólo para que se lea como un coche desde fuera. Sin colisión: lo
	-- que choca es el chasis, y una cabina con cuerpo propio engancha en cada bordillo.
	local techo = pieza(
		"Cabina",
		Vector3.new(ANCHO - 0.8, 2.2, LARGO * 0.42),
		base * CFrame.new(0, ALTO_CHASIS / 2 + 1.1, 0.6),
		Color3.fromRGB(150, 52, 44),
		coche
	)
	techo.CanCollide = false
	-- Casi sin peso: lo que va arriba es lo que vuelca.
	techo.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.3, 0.5, 1, 1)
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = chasis
	soldadura.Part1 = techo
	soldadura.Parent = chasis

	local asiento = Instance.new("VehicleSeat")
	asiento.Name = "Asiento"
	asiento.Size = Vector3.new(2.4, 0.4, 2.4)
	asiento.CFrame = base * CFrame.new(0, ALTO_CHASIS / 2 + 0.2, 1.2)
	asiento.Color = Color3.fromRGB(40, 40, 46)
	-- El `VehicleSeat` de Roblox trae su propio control de dirección para partes
	-- soldadas, y aquí estorbaría: la dirección la llevan las manguetas. Lo que se le
	-- pide es sólo que lea el mando del jugador (`Throttle` y `Steer`).
	asiento.MaxSpeed = 0
	asiento.Torque = 0
	asiento.TurnSpeed = 0
	asiento.Parent = coche
	local soldarAsiento = Instance.new("WeldConstraint")
	soldarAsiento.Part0 = chasis
	soldarAsiento.Part1 = asiento
	soldarAsiento.Parent = chasis

	local motores: { HingeConstraint } = {}
	local ejesDireccion: { Attachment } = {}
	for _, lado in { -1, 1 } do
		local m = rueda(coche, chasis, lado, false, ejesDireccion)
		if m then
			table.insert(motores, m)
		end
		rueda(coche, chasis, lado, true, ejesDireccion)
	end

	coche.Parent = padre

	-- EL MANDO: se lee lo que pide el jugador y se traduce a ruedas. Es todo el
	-- "código de conducción" que hace falta, y cabe en diez líneas -- lo que cuesta un
	-- coche no es esto, es todo lo demás (persecución, aparcar, replicación).

	task.spawn(function()
		while coche.Parent ~= nil do
			local gas = asiento.Throttle
			local volante = asiento.Steer
			for _, m in motores do
				-- La velocidad angular sale de la lineal: una rueda de radio R que gira
				-- a W rad/s avanza W*R studs/s. Sin esta cuenta el número no significa
				-- nada y hay que buscarlo a ojo.
				m.AngularVelocity = -gas * (VELOCIDAD / RADIO_RUEDA)
			end
			-- Dirigir es reorientar el eje de las ruedas de delante en el plano del
			-- suelo. `Axis` es local al chasis, así que basta con girar el (1,0,0).
			local a = math.rad(volante * GIRO)
			local eje = Vector3.new(math.cos(a), 0, math.sin(a))
			for _, at in ejesDireccion do
				at.Axis = eje
			end
			task.wait(0.05)
		end
	end)

	print(
		string.format(
			"[Prototipo] coche de prueba aparcado en (%.0f, %.0f). Subete y prueba; se quita con Config.PROTOTIPO_COCHE = false",
			sitio.X,
			sitio.Z
		)
	)
	return coche
end

return CochePrueba
