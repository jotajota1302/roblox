--!strict
--[[
	Patrullas.luau — que los ladrones ANDEN en vez de deslizarse.

	POR QUE EXISTE, y es un fallo de los que este proyecto colecciona: no revienta,
	no avisa, y lo que se ve es *"los ladrones siguen siendo muy tontos y con mal
	diseno y movimientos"* (JJ).

	La causa, medida: `Players:CreateHumanoidModelFromDescription` devuelve el
	personaje con su script `Animate` dentro... y ese script es un **LocalScript**.
	Un LocalScript solo corre en el cliente y solo dentro del personaje de un
	JUGADOR: en un PNJ que vive en el Workspace del servidor no se ejecuta jamas.
	O sea que las patrullas nunca han tenido una sola animacion. Cruzaban la ciudad
	rectas como un maniqui sobre ruedas -- y eso, mas que feo, se lee como TONTO:
	un personaje que no mueve las piernas parece que no ha decidido moverse.

	POR QUE NO SE CARGAN LAS ANIMACIONES OFICIALES. Serian cuatro lineas
	(`Animator:LoadAnimation` con los ids R6 de Roblox), y no valen aqui: un
	`rbxassetid://` no carga mientras el place no este publicado -- la misma trampa
	que los meshes y el DataStore, ya pagada dos veces en este repo. El juego tiene
	que verse bien en Studio, que es donde se prueba.

	ASI QUE SE ANIMA A MANO, moviendo los Motor6D del R6 -- que son piezas, y las
	piezas siempre funcionan. Es la regla de esta casa: todo lo que dependa de un
	asset necesita un respaldo construido con `Part`.

	Y VA EN EL CLIENTE, igual que el `Animate` de un jugador normal: mover cuatro
	articulaciones por patrulla a sesenta por segundo desde el servidor serian
	cientos de actualizaciones de red que no cambian NADA del juego -- ni la
	posicion, ni la velocidad, ni a quien alcanza. Es dibujo, y el dibujo es de cada
	maquina.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Patrullas = {}

-- Cuanto abre la zancada, en radianes, a velocidad de crucero. Medio radian son
-- unos 29 grados: es el paso largo de alguien que persigue, no el de un paseo.
local ZANCADA = 0.55
-- Los brazos acompanan menos que las piernas. Con la misma amplitud parece que
-- nada, no que corre.
local BRAZO = 0.75
-- Cuantas zancadas por segundo y por stud de velocidad. Sale de la proporcion de
-- siempre: a 16 studs/s (el paso normal de Roblox) toca algo mas de un ciclo por
-- segundo, que es lo que hace que el pie parezca agarrarse al suelo en vez de
-- patinar.
local CADENCIA = 0.55

-- A partir de que velocidad se considera que anda. Por debajo esta parado, y un
-- personaje parado tiene que quedarse quieto: balancear a un tipo que no avanza es
-- exactamente lo que hace que un PNJ parezca roto.
local ANDANDO = 0.6

-- Hasta donde se anima. Mas lejos no se distingue una pierna de otra, y las
-- patrullas son pocas pero el bucle corre en cada fotograma.
local CERCA = 400

type Marioneta = {
	modelo: Model,
	raiz: BasePart,
	humanoid: Humanoid,
	motores: { Motor6D },
	bases: { CFrame },
	signos: { number },
	tronco: Motor6D?,
	troncoBase: CFrame?,
	-- El reloj de la zancada. Es SUYO y no global: dos ladrones andando al mismo
	-- paso y en la misma fase se leen como una sola cosa duplicada.
	fase: number,
}

local marionetas: { [Model]: Marioneta } = {}

-- Las cuatro articulaciones que hacen falta y en que sentido va cada una. En un R6
-- las caderas y los hombros tienen el C0 girado un cuarto de vuelta en Y, asi que
-- lo que balancea adelante y atras es un giro sobre su Z local -- no sobre X, que
-- es lo que uno escribiria a ojo. Se comprobo midiendo: con el giro en Z, el pie se
-- desplaza en el eje de avance del torso; con X, se abre en cruz.
--
-- LOS PARES LLEVAN EL MISMO SIGNO, Y ESO NO ES LO QUE UNO ESCRIBIRIA. Para que la
-- pierna izquierda vaya en contrafase con la derecha hay que darles el MISMO
-- numero, porque el R6 ya trae la articulacion izquierda espejada (su C0 gira -90
-- en Y en vez de +90): el espejo invierte el sentido, y poner ademas el signo
-- contrario lo cancela.
--
-- Se escribio primero con los signos alternados --que es lo logico sobre el papel--
-- y se midio: el pie izquierdo daba EXACTAMENTE los mismos valores que el derecho,
-- doce muestras seguidas. O sea las dos piernas a la vez: un salto de conejo.
--
-- Lo que si alterna es brazo contra pierna: el brazo derecho acompana a la pierna
-- IZQUIERDA, que es como anda todo el mundo, y por eso los hombros llevan el signo
-- contrario al de las caderas.
local ARTICULACIONES: { { nombre: string, signo: number, amplitud: number } } = {
	{ nombre = "Right Hip", signo = 1, amplitud = 1 },
	{ nombre = "Left Hip", signo = 1, amplitud = 1 },
	{ nombre = "Right Shoulder", signo = -1, amplitud = BRAZO },
	{ nombre = "Left Shoulder", signo = -1, amplitud = BRAZO },
}

local function adoptar(modelo: Model): Marioneta?
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	local raiz = modelo:FindFirstChild("HumanoidRootPart")
	local torso = modelo:FindFirstChild("Torso")
	if humanoid == nil or raiz == nil or torso == nil or not raiz:IsA("BasePart") then
		return nil
	end

	local motores: { Motor6D } = {}
	local bases: { CFrame } = {}
	local signos: { number } = {}
	for _, art in ARTICULACIONES do
		local motor = torso:FindFirstChild(art.nombre)
		if motor and motor:IsA("Motor6D") then
			table.insert(motores, motor)
			-- El C0 DE FABRICA, guardado antes de tocar nada: la animacion se aplica
			-- siempre sobre el, nunca sobre el ultimo valor. Acumular sobre lo ya
			-- girado es como una pierna acaba dando la vuelta entera en diez segundos.
			table.insert(bases, motor.C0)
			table.insert(signos, art.signo * art.amplitud)
		end
	end
	if #motores == 0 then
		return nil
	end

	local tronco = raiz:FindFirstChild("RootJoint")
	return {
		modelo = modelo,
		raiz = raiz,
		humanoid = humanoid,
		motores = motores,
		bases = bases,
		signos = signos,
		tronco = if tronco and tronco:IsA("Motor6D") then tronco else nil,
		troncoBase = if tronco and tronco:IsA("Motor6D") then tronco.C0 else nil,
		fase = 0,
	}
end

local function animar(m: Marioneta, delta: number, dondeEstoy: Vector3?)
	if m.modelo.Parent == nil then
		marionetas[m.modelo] = nil
		return
	end
	if dondeEstoy and (m.raiz.Position - dondeEstoy).Magnitude > CERCA then
		return
	end

	-- La velocidad se mide del cuerpo y no de `Humanoid.WalkSpeed`: lo segundo es lo
	-- que PODRIA correr, y lo que hay que dibujar es lo que esta haciendo. Un ladron
	-- atascado contra una valla tiene WalkSpeed 12 y avanza cero, y ahi lo correcto
	-- es que se quede quieto -- forcejeando, no paseando.
	local velocidad = Vector3.new(m.raiz.AssemblyLinearVelocity.X, 0, m.raiz.AssemblyLinearVelocity.Z).Magnitude

	if velocidad < ANDANDO then
		-- Vuelta suave a la postura de fabrica. De golpe seria un tiron al pararse.
		for i, motor in m.motores do
			motor.C0 = motor.C0:Lerp(m.bases[i], math.min(1, delta * 8))
		end
		if m.tronco and m.troncoBase then
			m.tronco.C0 = m.tronco.C0:Lerp(m.troncoBase, math.min(1, delta * 8))
		end
		return
	end

	m.fase += delta * velocidad * CADENCIA
	local balanceo = math.sin(m.fase * math.pi * 2) * ZANCADA
	for i, motor in m.motores do
		motor.C0 = m.bases[i] * CFrame.Angles(0, 0, balanceo * m.signos[i])
	end

	-- Y SE INCLINA HACIA DELANTE con la velocidad. Es lo que separa "anda" de
	-- "viene a por ti": un cuerpo recto es un paseo, y este tipo esta corriendo.
	-- Se recorta para que no acabe doblado sobre si mismo cuando le toque una moto.
	if m.tronco and m.troncoBase then
		local inclina = math.min(velocidad / 40, 0.35)
		m.tronco.C0 = (m.troncoBase :: CFrame) * CFrame.Angles(-inclina, 0, 0)
	end
end

local arrancado = false
local avisado = false

function Patrullas.build()
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
			local carpeta = workspace:FindFirstChild("Patrullas")
			if carpeta == nil then
				return
			end
			local raiz = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dondeEstoy = if raiz then raiz.Position else nil

			-- Se adoptan las nuevas cada vuelta: una patrulla nace cuando sube el
			-- calor y muere cuando te pierde, asi que no hay un momento fijo en el que
			-- registrarlas. Recorrer una carpeta de tres o cuatro modelos por
			-- fotograma no cuesta nada; escuchar `ChildAdded` seria mas fino y ademas
			-- habria que escuchar el `Destroying` -- mas piezas para el mismo efecto.
			for _, hijo in carpeta:GetChildren() do
				if hijo:IsA("Model") and marionetas[hijo] == nil then
					local m = adoptar(hijo)
					if m then
						-- DESFASADA AL NACER: dos que salgan a la vez de la misma guarida
						-- no pueden andar como un desfile.
						--
						-- El desfase sale de su POSICION y no de un identificador del
						-- objeto. La primera version usaba `GetDebugId()` y eso costo la
						-- animacion entera: es una funcion reservada a los plugins, asi
						-- que lanzaba en la primera patrulla, el pcall se la tragaba, y
						-- lo que se veia era exactamente lo de antes -- ladrones
						-- deslizandose por la calle. Lo canto `LogService:GetLogHistory()`
						-- en un segundo.
						local donde = m.raiz.Position
						m.fase = ((math.abs(donde.X) + math.abs(donde.Z)) % 7) * 0.13
						marionetas[hijo] = m
					end
				end
			end

			for _, m in marionetas do
				animar(m, delta, dondeEstoy)
			end
		end)
		if not ok and not avisado then
			avisado = true
			warn("[Contrabando] fallo animando las patrullas: " .. tostring(err))
		end
	end)
end

return Patrullas
