--!strict
--[[
	Riders.luau — que quien va en tabla CONDUZCA, en vez de posar encima.

	POR QUE EXISTE, con las palabras exactas: *"la fisica de conducir el monopatin es
	lamentable, va encima de el sin moverse como una estatua"* (JJ). Y "estatua" no es
	una exageracion: es el diagnostico literal.

	LA CAUSA, en `Ride.postura`: al montar CUALQUIER vehiculo se desactiva el script
	`Animate` --el que Roblox mete en cada personaje para mover las extremidades-- y
	despues se coloca una pose a mano SOLO para los vehiculos en los que se va
	sentado (moto, bici, coche, furgoneta). Los de pie --monopatin, patinete-- se
	quedaron en tierra de nadie: sin el script que los animaba y sin pose que lo
	sustituyera. O sea rigidos en posicion de reposo, deslizandose por la calle.

	Es el mismo fallo que tenian las patrullas y por el mismo motivo: apagar algo es
	la mitad del trabajo. El comentario de `Ride` decia *"en los otros vas de pie
	encima, que es como se va de verdad y ademas no necesita postura ninguna"*, y ahi
	esta el error de razonamiento -- ir de pie no necesita una pose DISTINTA, pero
	sigue necesitando UNA.

	QUE SE DIBUJA AQUI, por orden de lo que aporta:

	  · LA POSTURA. Un pie delante y otro detras, el cuerpo abierto hacia el lado.
	    Es lo que hace que la silueta diga "va en tabla" hasta en una captura fija.
	  · LA PATADA. Cada segundo y pico la pierna de atras empuja contra el suelo. Es
	    el gesto que nadie confunde con otro, y lo unico que convierte deslizarse en
	    avanzar por tu propio pie.
	  · EL BALANCEO EN CURVA. El cuerpo se inclina hacia dentro segun lo que esta
	    girando. Es lo que se siente como "fisica" sin que haya fisica ninguna
	    debajo: el ojo lee inercia donde solo hay una interpolacion.

	VA EN EL CLIENTE, igual que `Patrullas` y por lo mismo: mover cinco
	articulaciones a sesenta por segundo desde el servidor serian cientos de
	actualizaciones de red que no cambian NADA del juego. Es dibujo, y el dibujo es
	de cada maquina -- y como cada cliente anima a todos los que ve, los demas
	jugadores tambien te ven patinar.

	Y SIN ANIMACIONES OFICIALES. Serian dos lineas y no cargan mientras el place no
	este publicado: la trampa de los meshes y el DataStore, ya pagada tres veces
	aqui. Los Motor6D son piezas, y las piezas siempre funcionan.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Pose = require(game.ReplicatedStorage.Shared.Pose)

local Riders = {}

-- Los ejes y la traduccion de marcos viven en `shared/Pose.luau`, con su prueba.
--
-- POR QUE NO SE ESCRIBEN AQUI. En un R6 las caderas traen el C0 girado un cuarto de
-- vuelta en Y --asi que "doblar hacia delante" es girar sobre su Z local-- y el lado
-- izquierdo viene ademas espejado, de modo que el mismo numero significa lo contrario
-- en cada pierna. Eso costo una tarde en `Patrullas` (los signos alternados, que es
-- lo logico sobre el papel, daban las dos piernas a la vez) y estuvo a punto de
-- costar otra aqui: la primera version de este fichero tenia `ADELANTE = -1` escrito
-- a ojo, y con ese signo el patinador habria patinado de espaldas.
--
-- Lo canto la cuenta, no Studio: con el eje pedido en el marco del torso, un angulo
-- de +30 grados desplaza el pie -0,75 en Z, y en Roblox -Z es el frente. Ahora esa
-- medicion es una prueba pura que corre en cada `verificar.ps1`.
local DERECHA = Pose.DERECHA
local ARRIBA = Pose.ARRIBA
local FRENTE = Pose.FRENTE
local ADELANTE = Pose.ADELANTE

-- LA POSTURA, en grados. La pierna de delante casi recta y la de atras retrasada:
-- es la silueta de alguien sobre una tabla, y se reconoce sin ver la tabla.
local PIE_DELANTERO = 12
local PIE_TRASERO = -20
-- Los brazos, abiertos para equilibrar. Poco: un patinador con los brazos en cruz
-- parece que se cae, no que va.
local BRAZO_ABIERTO = 26
local BRAZO_ADELANTE = 14
-- El cuerpo, girado hacia su lado y algo agachado. El giro es media postura: de
-- frente al avance se lee como "de pie sobre algo", no como patinar.
local CUERPO_ABIERTO = 24
local CUERPO_AGACHADO = 8

-- LA PATADA: cada cuanto empuja y cuanto dura el gesto.
--
-- Espaciado y no un pataleo. A 1,25 s se lee como impulso --das un pie, ruedas,
-- vuelves a dar-- y por debajo de 0,8 parece que corre encima de la tabla, que es
-- justo el defecto que esto viene a arreglar.
local PATADA_CADA = 1.25
local PATADA_DURA = 0.42
-- Lo que baja la pierna al empujar, sumado a su angulo de reposo.
local PATADA_ARCO = 42

-- EL BALANCEO EN CURVA: cuanto se inclina como maximo, y a que velocidad de giro
-- llega a ese maximo. Los 2,2 rad/s son un viraje decidido; girar despacio inclina
-- poco, que es lo que hace que la inclinacion signifique algo.
local BALANCEO_MAX = 16
local GIRO_LLENO = 2.2

-- A partir de que velocidad se considera que rueda. Parado no se patea ni se
-- inclina: un patinador quieto que sigue empujando es lo mismo que un ladron
-- balanceandose sin avanzar -- se lee como roto.
local RODANDO = 3

-- Hasta donde se anima. Mas lejos no se distingue una pierna de otra.
local CERCA = 400

type Patinador = {
	personaje: Model,
	raiz: BasePart,
	caderaD: Motor6D?,
	caderaI: Motor6D?,
	hombroD: Motor6D?,
	hombroI: Motor6D?,
	tronco: Motor6D?,
	bases: { [Motor6D]: CFrame },
	-- El reloj de la patada, SUYO: dos patinadores en la misma calle empujando a la
	-- vez se leen como una animacion en bucle, no como dos personas.
	fase: number,
	-- El rumbo de la vuelta anterior, para saber cuanto esta girando. Se guarda el
	-- vector y no el angulo: restar angulos cerca de 180 grados da un salto de una
	-- vuelta entera, y el patinador se tira al suelo de golpe.
	rumbo: Vector3,
	balanceo: number,
}

local patinadores: { [Model]: Patinador } = {}

-- La articulacion, se llame como se llame. Los dos rigs conviven en este juego --el
-- avatar de respaldo es R6 y un jugador con el place publicado viene en R15-- y los
-- nombres cambian: "Right Hip" con espacio en el clasico, "RightHip" pegado en el
-- moderno, y el tronco es "RootJoint" en uno y "Root" en el otro.
local function junta(personaje: Model, nombres: { string }): Motor6D?
	for _, hijo in personaje:GetDescendants() do
		if hijo:IsA("Motor6D") then
			for _, nombre in nombres do
				if hijo.Name == nombre then
					return hijo
				end
			end
		end
	end
	return nil
end

local function adoptar(personaje: Model): Patinador?
	local raiz = personaje:FindFirstChild("HumanoidRootPart")
	if raiz == nil or not raiz:IsA("BasePart") then
		return nil
	end

	local p: Patinador = {
		personaje = personaje,
		raiz = raiz,
		caderaD = junta(personaje, { "Right Hip", "RightHip" }),
		caderaI = junta(personaje, { "Left Hip", "LeftHip" }),
		hombroD = junta(personaje, { "Right Shoulder", "RightShoulder" }),
		hombroI = junta(personaje, { "Left Shoulder", "LeftShoulder" }),
		tronco = junta(personaje, { "RootJoint", "Root" }),
		bases = {},
		fase = 0,
		rumbo = raiz.CFrame.LookVector,
		balanceo = 0,
	}

	-- Sin una sola articulacion no hay nada que animar: un rig con articulaciones
	-- por restriccion (el avatar nuevo de Roblox) no se posa asi, y forzarlo seria
	-- escribir en propiedades que no hacen nada.
	if p.caderaD == nil and p.caderaI == nil and p.tronco == nil then
		return nil
	end

	-- EL C0 DE FABRICA, guardado antes de tocar nada. La pose se aplica siempre
	-- sobre el, nunca sobre el ultimo valor: acumular sobre lo ya girado es como una
	-- pierna acaba dando la vuelta entera en diez segundos.
	for _, motor in { p.caderaD, p.caderaI, p.hombroD, p.hombroI, p.tronco } do
		if motor then
			p.bases[motor] = motor.C0
		end
	end
	return p
end

-- Lleva una junta a su pose, persiguiendola en vez de saltando: el `Lerp` es lo que
-- convierte un cambio de postura en un gesto.
local function posar(p: Patinador, motor: Motor6D?, giro: (CFrame) -> CFrame, suave: number)
	if motor == nil then
		return
	end
	local base = p.bases[motor]
	if base == nil then
		return
	end
	motor.C0 = motor.C0:Lerp(base * giro(base), suave)
end

local function soltar(p: Patinador)
	for motor, base in p.bases do
		if motor.Parent ~= nil then
			motor.C0 = base
		end
	end
end

local function animar(p: Patinador, delta: number, dondeEstoy: Vector3?)
	if p.personaje.Parent == nil then
		patinadores[p.personaje] = nil
		return
	end
	-- EL ATRIBUTO SE MIRA CADA VUELTA y no se escucha su cambio: bajarse del
	-- monopatin tiene que devolver el cuerpo a su sitio, y un
	-- `GetAttributeChangedSignal` por personaje son conexiones que hay que acordarse
	-- de soltar cuando el personaje muere -- y aqui muere a menudo.
	if p.personaje:GetAttribute("vehiculoDePie") ~= true then
		soltar(p)
		patinadores[p.personaje] = nil
		return
	end
	if dondeEstoy and (p.raiz.Position - dondeEstoy).Magnitude > CERCA then
		return
	end

	local cf = p.raiz.CFrame
	local velocidad = Vector3.new(p.raiz.AssemblyLinearVelocity.X, 0, p.raiz.AssemblyLinearVelocity.Z).Magnitude
	local rodando = velocidad > RODANDO

	-- CUANTO ESTA GIRANDO, en radianes por segundo. Sale del rumbo de la vuelta
	-- anterior contra el de ahora, con el signo del producto vectorial vertical:
	-- positivo girando hacia su derecha.
	local ahora = cf.LookVector
	local giro = 0
	if delta > 0.0001 then
		local seno = p.rumbo.X * ahora.Z - p.rumbo.Z * ahora.X
		local coseno = math.clamp(p.rumbo:Dot(ahora), -1, 1)
		giro = math.atan2(seno, coseno) / delta
	end
	p.rumbo = ahora

	-- El balanceo PERSIGUE al giro en vez de copiarlo. Copiarlo lo dejaria pegado al
	-- volantazo --el personaje gira en un fotograma-- y se veria un tiron lateral;
	-- persiguiendolo, entra y sale como entraria un cuerpo con inercia.
	local objetivo = if rodando then math.clamp(giro / GIRO_LLENO, -1, 1) * BALANCEO_MAX else 0
	p.balanceo += (objetivo - p.balanceo) * math.min(1, delta * 6)

	-- LA PATADA, solo mientras rueda. El reloj sigue corriendo parado a proposito:
	-- asi al arrancar no empieza siempre por el mismo punto del gesto.
	p.fase += delta
	local empuje = 0
	if rodando then
		local t = p.fase % PATADA_CADA
		if t < PATADA_DURA then
			-- Ida y vuelta en un solo seno: baja al empujar y se recoge, sin el salto
			-- que dejaria una rampa lineal al reiniciarse.
			empuje = math.sin((t / PATADA_DURA) * math.pi)
		end
	end

	local suave = math.min(1, delta * 12)

	-- EL TRONCO: abierto de lado, algo agachado y balanceandose en las curvas. Lleva
	-- la mayor parte de la lectura -- las piernas dicen "va en tabla" y el tronco
	-- dice "esta girando".
	local agacha = (CUERPO_AGACHADO + empuje * 5) * ADELANTE
	posar(p, p.tronco, function(base)
		return Pose.enTorso(base, ARRIBA, CUERPO_ABIERTO)
			* Pose.enTorso(base, DERECHA, agacha)
			* Pose.enTorso(base, FRENTE, p.balanceo)
	end, suave)

	-- LAS PIERNAS: la de delante fija, la de atras es la que empuja.
	posar(p, p.caderaD, function(base)
		return Pose.enTorso(base, DERECHA, PIE_DELANTERO * ADELANTE)
	end, suave)
	local trasera = (PIE_TRASERO - empuje * PATADA_ARCO) * ADELANTE
	posar(p, p.caderaI, function(base)
		return Pose.enTorso(base, DERECHA, trasera)
	end, suave)

	-- LOS BRAZOS, abiertos y contrapesando el balanceo: el de fuera de la curva sube
	-- y el de dentro baja. Es como se equilibra cualquiera, y en pantalla es lo que
	-- remata la sensacion de peso.
	local contrapeso = p.balanceo * 0.5
	posar(p, p.hombroD, function(base)
		return Pose.enTorso(base, FRENTE, -BRAZO_ABIERTO - contrapeso)
			* Pose.enTorso(base, DERECHA, BRAZO_ADELANTE * ADELANTE)
	end, suave)
	posar(p, p.hombroI, function(base)
		return Pose.enTorso(base, FRENTE, BRAZO_ABIERTO - contrapeso)
			* Pose.enTorso(base, DERECHA, BRAZO_ADELANTE * ADELANTE)
	end, suave)
end

local arrancado = false
local avisado = false

function Riders.build()
	if arrancado then
		return
	end
	arrancado = true

	local jugador = Players.LocalPlayer

	-- En Heartbeat y no en RenderStepped: esto no va sincronizado con la camara, y
	-- ademas RenderStepped se para en seco cuando la ventana pierde el foco -- con lo
	-- que la animacion no se puede medir desde fuera. Ver la misma nota en `Alerta`.
	RunService.Heartbeat:Connect(function(delta)
		local ok, err = pcall(function()
			local raiz = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dondeEstoy = if raiz then raiz.Position else nil

			-- A QUIEN SE MIRA: a los jugadores y a las patrullas. Recorrer el Workspace
			-- entero por fotograma para encontrar cinco personajes seria pagar el mapa
			-- de siete mil piezas sesenta veces por segundo.
			local candidatos: { Model } = {}
			for _, otro in Players:GetPlayers() do
				if otro.Character then
					table.insert(candidatos, otro.Character)
				end
			end
			local carpeta = workspace:FindFirstChild("Patrullas")
			if carpeta then
				for _, hijo in carpeta:GetChildren() do
					if hijo:IsA("Model") then
						table.insert(candidatos, hijo)
					end
				end
			end

			for _, personaje in candidatos do
				if patinadores[personaje] == nil and personaje:GetAttribute("vehiculoDePie") == true then
					local p = adoptar(personaje)
					if p then
						-- Desfasado al montar, para que dos patinadores no empujen a la vez.
						local donde = p.raiz.Position
						p.fase = (math.abs(donde.X) + math.abs(donde.Z)) % PATADA_CADA
						patinadores[personaje] = p
					end
				end
			end

			for _, p in patinadores do
				animar(p, delta, dondeEstoy)
			end
		end)
		if not ok and not avisado then
			avisado = true
			warn("[Contrabando] fallo animando a los patinadores: " .. tostring(err))
		end
	end)
end

return Riders
