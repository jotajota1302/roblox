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
local MeshCatalog = require(game.ReplicatedStorage.Shared.MeshCatalog)

local CochePrueba = {}

-- Medidas, en studs. Un coche de Roblox ronda esto, y lo importante es la relación:
-- ANCHO Y BAJO no vuelca, alto y estrecho sí. La primera regla de un coche de juguete
-- es que se quede sobre sus ruedas.
local LARGO = 12
-- ESTRECHADO de 6 a 5,2 al ponerle carroceria, y el motivo es que las ruedas van
-- FUERA del chasis (se separaron para que no rozaran) -- o sea que el ancho del
-- chasis decide la via, y la via decide si las ruedas caben dentro del coche o
-- asoman como las de un monster truck. Con 6 la via acababa en 8,3 y ninguna
-- carroceria de proporciones creibles la tapaba.
--
-- NO ES GRATIS Y HAY QUE MEDIRLO: una via mas estrecha vuelca antes, y el vuelco ya
-- costo una ronda entera de ajuste. Lo que lo compensa es que el peso sigue abajo
-- --chasis a densidad 3,2, carroceria a 0,05-- que es lo que de verdad sostiene un
-- coche de juguete.
local ANCHO = 5.2
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
-- Y BAJADA OTRA VEZ, de 58 a 40, conduciendola por la ciudad terminada. El numero
-- que lo decide no es el radio de giro sino LA DISTANCIA DE FRENADA: de 56 studs/s a
-- parado eran 115 studs, y una manzana mide 120. O sea que a tope de gas el coche NO
-- llegaba a tiempo de frenar para la esquina del final de la manzana -- y esa curva la
-- pasaba el 67 % del tiempo subido a la acera.
--
-- Con 40, la frenada cabe en media manzana y acelerar Y frenar caben en un tramo, que
-- es lo que hace conducible una ciudad. Se pierde punta y no se pierde sensacion: 40
-- studs/s siguen siendo el doble que la moto, y la sensacion de velocidad la da el
-- acelerar, no el numero.
local VELOCIDAD = 40
-- SUBIDA a 250.000 despues de medir. Veintidos mil sonaba a mucho y no movia el coche:
-- un chasis de 6x1,6x12 mas cuatro ruedas pesa lo suyo, y el par tiene que vencer eso
-- Y el rozamiento de las ruedas contra el suelo, que aqui esta a proposito muy alto
-- para que agarren. Los coches de Roblox suelen ir con cifras de este orden.
local FUERZA = 250000
local GIRO = 30

-- EL FRENO, y hasta hoy no habia ninguno.
--
-- Lo que habia era esto: soltar el gas dejaba el motor pidiendo cero vueltas, lo cual
-- frena --34 studs desde velocidad de crucero-- pero por accidente, no por diseno. Y
-- dar gas hacia atras era peor todavia: las ruedas giran al reves contra el asfalto,
-- patinan, y tardaba 115 studs en parar, tres veces mas que no hacer nada. Un freno
-- que frena menos que soltar el pie no es un freno.
--
-- Y LA PRIMERA VERSION DEL ARREGLO FUE PEOR, que es la parte que hay que contar. Se
-- hizo subiendo el PAR de frenado (`MotorMaxTorque`) y pidiendo cero vueltas, y no
-- sirve de nada: **lo que limita una frenada aqui no es el par sino el agarre**. Con
-- friccion 100 --puesta a proposito para que las ruedas no patinen en las curvas--
-- cualquier par razonable bloquea la rueda, y una rueda bloqueada con ese agarre para
-- el coche en once studs y medio segundo, o sea seis ges. Bajar el par de 2,2 a 0,35
-- veces la fuerza no cambio NADA: 11 studs las dos veces.
--
-- El efecto de verdad no era la brusquedad, era que el coche se clavaba antes de
-- llegar a la curva: las dos primeras pruebas de la esquina salieron "0 % fuera del
-- asfalto" habiendo girado CERO grados. Aprobar por no haberse movido.
--
-- LO QUE SI FUNCIONA es frenar por la VELOCIDAD PEDIDA en vez de por el par: el motor
-- mantiene siempre su fuerza y lo que se mueve es a cuantas vueltas se le pide girar.
-- Frenar es bajar esa cifra a un ritmo, acelerar es subirla a otro, y soltar el gas es
-- dejarla caer despacio. Tres numeros en studs/s^2 --que es una unidad que se puede
-- razonar contra el mapa-- en vez de un par que no dice nada.
--
-- Los tres salen de la ciudad, como todo lo demas de este fichero:
--   · ACELERACION: de 0 al tope en poco menos de un segundo. Un coche de juego tiene
--     que responder; el realismo aqui se paga en aburrimiento.
--   · FRENADO: 40 studs/s a cero en unos 30 studs, o sea media manzana holgada. Es el
--     numero que hace que la esquina del final de la manzana sea tomable.
--   · RETENCION: soltar el gas frena, pero en unos cien studs. Tiene que notarse y
--     tiene que dejar clarisimo que el freno hace otra cosa.
local ACELERACION = 55
local FRENADO = 26
local RETENCION = 8

-- El tono del motor parado y a tope. Graves los dos --un coche es lo mas grande que
-- se conduce aqui-- y con poco recorrido entre ellos a proposito: un motor que salta
-- de tono a lo bruto suena a juguete estropeado, que es la queja exacta que costo el
-- sonido de los patines.
local TONO_RALENTI = 0.62
local TONO_PUNTA = 0.95
local VOLUMEN_RALENTI = 0.12
local VOLUMEN_PUNTA = 0.5

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

	-- LA CARROCERÍA. *"Veo un modelo 3D muy feo"* (JJ, 22/08), y lo era: una caja roja
	-- con otra caja encima. Ahora es una furgoneta de verdad, y lo que lo ha hecho
	-- posible no es el modelo sino que **el place esté publicado** -- hasta el 22/08
	-- `CreateMeshPartAsync` fallaba con cualquier id y todo el arte del juego era
	-- teórico. Comprobado ese mismo día: las tres mallas del catálogo cargan.
	--
	-- SIN COLISIÓN Y SIN PESO, exactamente igual que la caja que sustituye: lo que
	-- choca es el chasis y lo que vuelca es lo que pesa arriba. Vestir un coche no
	-- puede cambiar cómo se conduce, o habría que recalibrar la física cada vez que se
	-- cambia el color.
	--
	-- Y SI FALLA, LA CAJA. No es una red teórica: un id del catálogo ya se subió mal
	-- una vez y devolvía "Failed to load mesh asset" mientras sus tres hermanos
	-- cargaban. Un coche feo se conduce; un coche invisible, no.
	local function vestir(): BasePart
		local def = MeshCatalog.COCHE
		local ok, malla = pcall(function()
			return game:GetService("AssetService"):CreateMeshPartAsync(def.mesh)
		end)
		if ok and malla then
			malla.Name = "Carroceria"
			malla.Size = def.tamano
			malla.TextureID = def.textura
			-- LA BASE DE LA CARROCERÍA AL SUELO, que es donde acaban sus ruedas
			-- pintadas: el generador las dibuja tocando el fondo de su caja. Así las de
			-- física --que sí giran-- caen justo encima de las suyas y las tapan.
			malla.CFrame = base * CFrame.new(0, -ALTO_CHASIS / 2 - 0.2 - RADIO_RUEDA + def.tamano.Y / 2, 0)
			malla.Parent = coche
			return malla
		end
		return pieza(
			"Cabina",
			Vector3.new(ANCHO - 0.8, 2.2, LARGO * 0.42),
			base * CFrame.new(0, ALTO_CHASIS / 2 + 1.1, 0.6),
			Color3.fromRGB(150, 52, 44),
			coche
		)
	end

	local techo = vestir()
	techo.CanCollide = false
	techo.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.3, 0.5, 1, 1)
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = chasis
	soldadura.Part1 = techo
	soldadura.Parent = chasis

	local asiento = Instance.new("VehicleSeat")
	asiento.Name = "Asiento"
	asiento.Size = Vector3.new(2.4, 0.4, 2.4)
	-- A LA ALTURA DE LA CABINA, no pegado al chasis. Con la carroceria puesta el
	-- asiento quedaba a la altura de los bajos, o sea el jugador conduciendo desde
	-- debajo del motor -- que ademas era la otra mitad de por que habia que saltar para
	-- entrar.
	asiento.CFrame = base * CFrame.new(0, ALTO_CHASIS / 2 + 1.2, 1.2)
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

	-- SE ENTRA PULSANDO, NO SALTANDO. *"Hay que saltar para meterse dentro en vez de
	-- subirse"* (JJ, 22/08), y tenia razon: un `VehicleSeat` de Roblox se ocupa
	-- TOCANDOLO con el personaje, asi que con el asiento hundido entre el chasis y el
	-- techo la unica forma de rozarlo era caerle encima. Eso no es un detalle de
	-- acabado -- es la primera cosa que hace el jugador con el coche, y si esa sale
	-- torpe ya no importa como conduzca.
	--
	-- `ProximityPrompt` es la misma pieza con la que se entrega, se compra y se saca
	-- del garaje: sale sola al acercarse, es tecla en el ordenador y boton en el movil,
	-- y nadie tiene que aprender nada nuevo.
	--
	-- EN INGLES Y FIJO, y esto no se me olvida: lo que el SERVIDOR planta en el mundo
	-- lo ven todos los jugadores a la vez, asi que no se puede traducir por persona.
	-- Se deja en ingles en la instancia y lo traduce el motor al dibujarlo, que es la
	-- excepcion que documenta `Strings.luau`.
	local subir = Instance.new("ProximityPrompt")
	subir.Name = "PromptConducir"
	subir.ActionText = "Drive"
	subir.ObjectText = "Car"
	-- Desde la acera de al lado. La puerta de un coche esta en su costado, y pedir
	-- que te pegues al asiento seria repetir el problema por otro camino.
	subir.MaxActivationDistance = 12
	subir.HoldDuration = 0
	subir.RequiresLineOfSight = false -- el propio techo del coche lo apagaria
	subir.Parent = asiento

	subir.Triggered:Connect(function(jugador: Player)
		local pj = jugador.Character
		local humanoid = pj and pj:FindFirstChildOfClass("Humanoid")
		if humanoid then
			asiento:Sit(humanoid)
		end
	end)

	-- Y ESTANDO DENTRO NO SE OFRECE ENTRAR. Un aviso que sigue diciendo "Drive"
	-- mientras conduces es ruido, y ademas taparia el parabrisas.
	asiento:GetPropertyChangedSignal("Occupant"):Connect(function()
		subir.Enabled = asiento.Occupant == nil
	end)

	-- EL MOTOR SE OYE. *"Me falta audio para cuando vas en coche"* (JJ, 22/08).
	--
	-- REUTILIZA EL SAMPLE QUE YA HAY (`Config.SONIDO_MOTOR`, el mismo de la moto y el
	-- patinete) A OTRO TONO. Es la regla que ya sigue el resto del juego y que aqui
	-- vale doble: lo que distingue un coche de una moto es sobre todo lo GRAVE que
	-- suena, asi que 0,62 contra el 1,1 de la moto son dos vehiculos distintos sin
	-- descargar nada nuevo ni pasar otra moderacion.
	--
	-- EN EL CHASIS, o sea ESPACIAL: se oye venir el coche por la calle de al lado. En
	-- un juego de robar eso no es adorno, es informacion -- exactamente el mismo
	-- motivo por el que el ruido de los vehiculos vive en el servidor y no en quien lo
	-- conduce.
	local ruido = Instance.new("Sound")
	ruido.Name = "RuidoMotor"
	ruido.SoundId = Config.SONIDO_MOTOR
	ruido.Looped = true
	ruido.Volume = 0
	ruido.PlaybackSpeed = TONO_RALENTI
	-- Mas lejos que los demas (90) porque es mas grande y mas ruidoso, pero sin pasarse:
	-- con 200 studs, diez coches en la ciudad serian diez motores sonando siempre.
	ruido.RollOffMaxDistance = 140
	ruido.RollOffMode = Enum.RollOffMode.InverseTapered
	ruido.Parent = chasis

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

	-- LA VELOCIDAD QUE SE LE PIDE AL MOTOR, en studs/s. Es el estado del que sale
	-- todo: el gas la sube, el freno la baja deprisa y soltar la baja despacio.
	local pedida = 0
	local ultimo = os.clock()

	task.spawn(function()
		while coche.Parent ~= nil do
			local ahora = os.clock()
			-- Acotado: si Studio se congela un segundo, un `dt` gigante haria que el
			-- coche pasara de parado a tope --o al reves-- en un solo fotograma.
			local dt = math.clamp(ahora - ultimo, 0, 0.2)
			ultimo = ahora
			local gas = asiento.Throttle
			local volante = asiento.Steer

			-- EL MOTOR, CON LA VELOCIDAD DE VERDAD Y NO CON LA PEDIDA. Es lo que separa
			-- un ruido de fondo de una respuesta: cuesta arriba el gas esta a tope y el
			-- coche no tira, y el motor tiene que decir eso. `AssemblyLinearVelocity` es
			-- lo que se esta moviendo el ensamblaje entero, medido por la fisica.
			--
			-- Y CALLA CON EL COCHE VACIO. Un coche aparcado sonando a ralenti en mitad de
			-- la calle es de las cosas que se notan sin saber por que -- y aqui se notaria
			-- el doble, porque lo primero que ve el jugador al salir de casa es este coche
			-- parado.
			if asiento.Occupant == nil then
				if ruido.IsPlaying then
					ruido:Stop()
				end
			else
				if not ruido.IsPlaying then
					ruido:Play()
				end
				local real = chasis.AssemblyLinearVelocity.Magnitude
				local prop = math.clamp(real / VELOCIDAD, 0, 1)
				ruido.PlaybackSpeed = TONO_RALENTI + (TONO_PUNTA - TONO_RALENTI) * prop
				ruido.Volume = VOLUMEN_RALENTI + (VOLUMEN_PUNTA - VOLUMEN_RALENTI) * prop
			end
			-- GAS, FRENO Y MARCHA ATRAS con un solo mando, que es como se conduce en
			-- cualquier juego: la tecla de atras FRENA mientras el coche avanza, y solo
			-- da marcha atras cuando ya esta casi parado. Nadie tiene que aprenderse una
			-- tecla nueva, y sobre todo nadie descubre a base de chocar que el freno
			-- estaba donde no lo buscaba.
			--
			-- `hacia` es lo que avanza el coche en la direccion en la que MIRA: es lo
			-- que distingue "voy hacia delante" de "voy hacia atras", y sin eso el freno
			-- se convertiria en acelerador en cuanto empezara a rodar hacia atras.
			local hacia = chasis.CFrame.LookVector:Dot(chasis.AssemblyLinearVelocity)
			local frenando = (gas > 0 and hacia < -4) or (gas < 0 and hacia > 4)
			local suelto = gas == 0 and math.abs(pedida) > 0.5

			if frenando then
				-- SE FRENA DESDE LO QUE EL COCHE VA DE VERDAD, no desde lo que se le
				-- estaba pidiendo. Si venia empujando contra una cuesta --pedida 40,
				-- real 22-- arrancar la frenada en 40 regalaria casi un segundo de
				-- freno que no frena nada, que es justo cuando el jugador lo pulsa.
				pedida = math.min(pedida, math.abs(hacia))
				pedida = math.max(pedida - FRENADO * dt, 0)
			elseif suelto then
				pedida = math.max(pedida - RETENCION * dt, 0)
			elseif gas ~= 0 then
				-- MARCHA ATRAS A LA MITAD: ningun coche va hacia atras tan rapido como
				-- hacia delante, y aqui ademas evita que la tecla de frenar se convierta
				-- en un segundo acelerador en cuanto el coche se para.
				local tope = if gas < 0 then VELOCIDAD * 0.45 else VELOCIDAD
				pedida = math.min(pedida + ACELERACION * dt, tope)
			end

			-- El sentido es del mando; la magnitud, de la cuenta de arriba. Separarlos
			-- es lo que deja que frenar y dar marcha atras sean la misma tecla.
			local sentido = if frenando
				then (if hacia >= 0 then 1 else -1)
				elseif gas ~= 0 then gas
				else (if hacia >= 0 then 1 else -1)
			for _, m in motores do
				m.MotorMaxTorque = FUERZA
				-- La velocidad angular sale de la lineal: una rueda de radio R que gira
				-- a W rad/s avanza W*R studs/s. Sin esta cuenta el número no significa
				-- nada y hay que buscarlo a ojo.
				m.AngularVelocity = -sentido * (pedida / RADIO_RUEDA)
			end
			-- LO QUE PASA, PUBLICADO EN EL PROPIO COCHE. El velocimetro vive en el
			-- cliente y necesita saber dos cosas: a cuanto va y si esta frenando. Van
			-- como atributos del asiento --que es lo que el cliente ya tiene a mano al
			-- sentarse-- en vez de por un remote: es estado continuo de UNA pieza, y
			-- para eso los atributos replican solos.
			asiento:SetAttribute("velocidad", chasis.AssemblyLinearVelocity.Magnitude)
			asiento:SetAttribute("tope", VELOCIDAD)
			asiento:SetAttribute("frenando", frenando or suelto)

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
