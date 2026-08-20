--!strict
--[[
	PatrolService.luau — los ladrones que te buscan cuando llevas algo que vale.

	Es la pieza que llena el viaje. Sin ella el calor es un número que sube y no
	le pasa nada a nadie; con ella, cada quince o veinte segundos hay algo que
	resolver, que es exactamente lo que faltaba (ver PRIMERA-PARTIDA.md).

	VAN A PIE, Y NO ES UNA ELECCIÓN ESTÉTICA. Medido con PathfindingService sobre
	esta ciudad: con el salto desactivado --un coche-- sólo la ruta ámbar tiene
	camino; verde y roja devuelven NoPath, porque llegar exige subir un bordillo en
	algún punto. Un coche que salta aceras es ridículo y uno que no salta NO PUEDE
	ALCANZAR DOS DE LAS TRES ZONAS, así que el mecanismo no puede ser un coche. Los
	coches de patrulla llegarán como presencia por las calles principales; los que
	persiguen son estos.

	EL EQUILIBRIO, que es lo que separa un juego de un impuesto: la patrulla es MÁS
	RÁPIDA que el jugador (18-22 contra 9,9-16) pero va por donde va la gente. Tú
	eres más lento y puedes cortar por parques, solares y callejones. Escapar es
	leer el mapa, no ganar una carrera -- y esa es la única razón de peso para
	jugar en una ciudad en vez de en una recta.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Heat = require(game.ReplicatedStorage.Shared.Heat)
local Lairs = require(game.ReplicatedStorage.Shared.Lairs)
local Vision = require(game.ReplicatedStorage.Shared.Vision)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local CargoService = require(script.Parent.CargoService)
local HeatService = require(script.Parent.HeatService)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
local Strings = require(game.ReplicatedStorage.Shared.Strings)
local Cone = require(script.Parent.Cone)
local PlayerState = require(script.Parent.PlayerState)
local Ride = require(script.Parent.Ride)
local Telemetry = require(script.Parent.Telemetry)

-- Cada cuánto se replantea el camino. No más a menudo: calcular una ruta en este
-- mapa cuesta entre 0,6 y 1,3 s (medido), así que pedirla cada décima dejaría al
-- agente pensando en vez de andando. Entre replanteos sigue los puntos ya
-- calculados, que es lo que hace que se vea decidido en vez de a trompicones.
local REPLANTEO = 2

-- A qué distancia del jugador aparecen. Ni encima -- que sería una emboscada sin
-- salida -- ni tan lejos que no lleguen nunca.
local APARICION_MIN = 90
local APARICION_MAX = 140

-- Se rinden si el jugador se les va del todo. Sin esto, una patrulla creada en la
-- ruta roja seguiría al jugador hasta su propio almacén, y la zona segura dejaría
-- de serlo por la puerta de atrás.
local ABANDONO = 320

local PatrolService = {}

-- De dónde salen. Vacío hasta que el mundo se construya: sin guaridas el servicio
-- sigue funcionando con el método viejo, que es lo que hace que un mapa sin ellas
-- (o un fallo al plantarlas) no deje al juego sin amenaza.
local guaridas: { Vector3 } = {}

type Patrulla = {
	modelo: Model,
	humanoid: Humanoid,
	raiz: BasePart,
	viva: boolean,
}

local escoltas: { [Player]: { Patrulla } } = {}
local carpeta: Folder? = nil

-- ARRIBA DEL TODO, con las demás. Estaba declarada más abajo, junto a ajustar(),
-- y en cuanto perseguir() pasó a necesitarla para reubicar a una patrulla
-- encallada se convirtió en un global nil: reventaría exactamente en el caso raro
-- que viene a arreglar, y en ningún otro. Este proyecto ya ha pagado ese mismo
-- error tres veces (tieneLegendaria, suelo del decorado, perseguidos).
local rng = Random.new(os.clock() * 1000)

local function contenedor(): Folder
	if carpeta and carpeta.Parent then
		return carpeta
	end
	local f = Instance.new("Folder")
	f.Name = "Patrullas"
	f.Parent = workspace
	carpeta = f
	return f
end

local function raiz(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Un agente. Se construye con el MISMO truco que los jugadores (rig R6 desde una
-- HumanoidDescription): está hecho de Part, así que se ve aunque el place no esté
-- publicado y no hay que descargar ninguna malla. Ver la cabecera de Avatar.luau,
-- que cuenta por qué esto importa tanto en este proyecto.
-- En qué va a venir el que te persigue. ESCALA CONTIGO, y por eso es legible:
-- si tú vas en moto, el que aparece por la esquina viene en moto, y lo sabes de
-- un vistazo sin leer nada. Un perseguidor a pie detrás de una furgoneta sería
-- una amenaza que el jugador aprende a ignorar; uno en moto detrás de otra moto
-- se entiende solo.
--
-- Un peldaño POR DEBAJO del jugador a propósito: la velocidad ya se iguala aparte
-- (ver ajustar), y el vehículo aquí es información, no potencia. Que el suyo se
-- vea un punto peor deja el mensaje correcto -- tu dinero sirve para algo -- sin
-- que deje de alcanzarte.
local function vehiculoDelPerseguidor(vehiculoDelJugador: string?): string?
	local escalera = Config.VEHICULOS
	local indice = 1
	for i, v in escalera do
		if v.id == (vehiculoDelJugador or Config.VEHICULO_INICIAL) then
			indice = i
			break
		end
	end
	local suyo = escalera[math.max(1, indice - 1)]
	return if Ride.existe(suyo.id) then suyo.id else nil
end

-- CÓMO SE VE UN LADRÓN, que es lo primero que preguntó JJ después de jugar: "no
-- veo a los ladrones con su zona de detección" y "los diseños de los ladrones
-- están poco trabajados".
--
-- Las dos cosas son el mismo problema. Un muñeco oscuro entre muñecos de bloques
-- no se distingue de un peatón, y lo que hace falta saber cuando aparece uno no
-- es que es "malo": es CUÁNTO TIENE QUE ACERCARSE para quitarte la carga. Ese
-- número existe (Config.PATRULLA_ALCANCE, seis studs) y hasta ahora no se veía
-- por ningún lado, así que el robo llegaba sin aviso y parecía arbitrario.
--
-- Todo con Part, nada de mallas: los meshes no cargan sin publicar el place (ver
-- CLAUDE.md), y un ladrón invisible sería peor que uno tosco.
local function pieza(nombre: string, tamano: Vector3, color: Color3, padre: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = padre
	return p
end

local function pegar(pieza: BasePart, a: BasePart, offset: CFrame)
	pieza.CFrame = a.CFrame * offset
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = a
	soldadura.Part1 = pieza
	soldadura.Parent = pieza
end

local function vestir(modelo: Model)
	local cabeza = modelo:FindFirstChild("Head") :: BasePart?
	local torso = modelo:FindFirstChild("Torso") :: BasePart?
	local raiz = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?

	if cabeza then
		-- Gorro y antifaz: dos piezas y el muñeco genérico pasa a ser un tipo con
		-- la cara tapada. Es lo mínimo que se lee a treinta metros.
		local gorro = pieza("Gorro", Vector3.new(2.1, 0.8, 1.3), Color3.fromRGB(28, 28, 34), modelo)
		pegar(gorro, cabeza, CFrame.new(0, 0.75, 0))
		local visera = pieza("Visera", Vector3.new(2.1, 0.25, 0.9), Color3.fromRGB(20, 20, 24), modelo)
		pegar(visera, cabeza, CFrame.new(0, 0.42, -0.9))
		local antifaz = pieza("Antifaz", Vector3.new(2.05, 0.6, 1.25), Color3.fromRGB(18, 18, 22), modelo)
		pegar(antifaz, cabeza, CFrame.new(0, -0.05, 0))
	end

	if torso then
		-- La mochila del botín: dice qué viene a hacer sin una palabra.
		local mochila = pieza("Mochila", Vector3.new(1.6, 1.7, 0.9), Color3.fromRGB(64, 46, 34), modelo)
		pegar(mochila, torso, CFrame.new(0, 0.1, 0.85))
		local correa = pieza("Correa", Vector3.new(2.1, 0.35, 1.15), Color3.fromRGB(30, 26, 24), modelo)
		pegar(correa, torso, CFrame.new(0, 0.5, 0))
	end

	if raiz then
		-- EL ANILLO DE ALCANCE, pegado a los pies. Es su "zona de detección" hecha
		-- visible: dentro de este círculo te roba, fuera no. Con él, la persecución
		-- pasa de "aparece un mensaje y pierdes la mitad" a un juego de distancias
		-- que se puede leer mientras corres.
		local anillo = pieza(
			"Alcance",
			Vector3.new(0.3, Config.PATRULLA_ALCANCE * 2, Config.PATRULLA_ALCANCE * 2),
			Color3.fromRGB(255, 70, 60),
			modelo
		)
		anillo.Shape = Enum.PartType.Cylinder
		anillo.Material = Enum.Material.Neon
		anillo.Transparency = 0.72
		anillo.CastShadow = false
		-- El cilindro de Roblox crece a lo largo de su eje X, así que hay que
		-- tumbarlo un cuarto de vuelta para que quede como un disco en el suelo.
		pegar(anillo, raiz, CFrame.new(0, -2.9, 0) * CFrame.Angles(0, 0, math.rad(90)))

		-- AQUI HABIA UN PILAR DE LUZ DE 70 STUDS, y se ha ido por donde se fue todo lo
		-- demas vertical. Nacio contra una queja buena --*"no los veo a lo lejos"*-- y
		-- se midio bien: sin columna, seis de cada diez veces el ladron que viene a por
		-- ti no se puede ver aunque mires hacia el.
		--
		-- Pero resolvia el problema pasandose de largo. JJ, viendolo funcionar el
		-- 20/08: *"quitales el rectangulo ese hacia arriba, que los hace demasiado
		-- evidentes"*. Y tiene razon: un ladron que se ve desde el otro lado de la
		-- ciudad no se esquiva, se ignora -- sabes exactamente donde esta todo el rato
		-- y el juego deja de pedirte que mires.
		--
		-- Lo que se queda para verlos llegar es el `Highlight`, que contornea al ladron
		-- de rojo a traves de las paredes: dice POR DONDE viene sin plantar una torre
		-- en mitad de la calle.
		--
		-- Y AHORA SE VE HACIA DONDE MIRA, que es lo que convierte esto en una decision.
		--
		-- LA PRIMERA VERSION ERAN SIETE BARRAS radiando desde los pies, y duro un dia:
		-- *"el rayo ese que sale del ladron es muy cutre"* (JJ, 20/08). Tenia razon --
		-- unas varillas separadas no dicen "esta zona la ve", dicen "hay unos palos".
		-- Se eligieron porque un sector en planta parecia imposible de comprobar sin
		-- mirar la pantalla, y en Play no hay capturas. El error era ese "sin mirar":
		-- en EDIT las capturas SI funcionan, y ademas la forma se mide con una rejilla
		-- de rayos hacia abajo. Hacian falta las dos -- la primera version del abanico
		-- de cunas salia en estrella de tres puntas y con fugas hasta los 100 grados,
		-- y eso una captura no lo mide. El como esta en `Cone.luau`.
		-- La figura la dibuja `Cone`, compartida con la esquina vigilada: si el ojo
		-- tuviera que aprender dos simbolos para "aqui te ven", el segundo no lo
		-- aprende nadie.
		for _, pieza in
			Cone.piezas(
				CFrame.new(0, 0, 0),
				Config.LADRON_VISION_ANGULO,
				Config.LADRON_VISION_ALCANCE,
				Color3.fromRGB(255, 132, 58),
				0.8
			)
		do
			pieza.Parent = modelo
			-- Se suelda a los pies: `Cone` las construye alrededor del origen, asi que
			-- basta con llevar ese origen a la raiz y bajarlo a la altura del suelo.
			pegar(pieza, raiz, CFrame.new(0, -2.6, 0) * pieza.CFrame)
		end

		-- Y su nombre, para que se distinga de un peatón en una ciudad llena de
		-- muñecos. Sin AlwaysOnTop, igual que las placas de los jugadores: si se
		-- viera a través de los edificios, esconderse dejaría de servir de nada.
		--
		-- El alcance de la placa llega ahora hasta donde el ladrón abandona la
		-- persecución (320): con 180 había un tramo entero --de 180 a 320-- en el
		-- que te perseguía alguien de quien no podías saber ni qué era.
		local placa = Instance.new("BillboardGui")
		placa.Name = "Placa"
		placa.Size = UDim2.fromOffset(120, 32)
		placa.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
		placa.AlwaysOnTop = false
		placa.MaxDistance = 320
		placa.Adornee = cabeza or raiz
		placa.Parent = cabeza or raiz

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Color3.fromRGB(255, 96, 86)
		texto.TextStrokeTransparency = 0.3
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = Strings.get("THIEF_PLATE")
		texto.Parent = placa
	end
end

local function crearAgente(donde: Vector3, velocidad: number, vehiculo: string?): Patrulla?
	local ok, resultado = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		local modelo = Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R6)
		modelo.Name = "Patrulla"

		local humanoid = modelo:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = velocidad
		-- Que no se pueda matar ni empujar: es un obstáculo del mundo, no un rival.
		-- Un agente al que se le puede tirar por un barranco convierte el sistema en
		-- un puzle de física en vez de en una persecución.
		-- Un número grande, no math.huge: el infinito viaja mal por la replicación
		-- y deja la barra de vida en un estado indefinido en el cliente.
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6

		-- Oscuros de arriba abajo, para que se reconozcan de un vistazo desde lejos.
		-- En una ciudad llena de gente de bloques, un perseguidor que parece un
		-- peatón cualquiera no avisa de nada -- y avisar es la mitad de su trabajo:
		-- una amenaza que no se ve venir no es tensión, es una emboscada.
		--
		-- Y NO azul: ese color queda reservado entero para las comisarías desde el
		-- cambio de tema. Si el que te persigue y el sitio donde te refugias
		-- comparten tono, el jugador tiene que pararse a mirar cuál es cuál justo
		-- cuando no puede pararse.
		for _, parte in modelo:GetDescendants() do
			if parte:IsA("BasePart") then
				parte.Color = Palette.LADRON
				parte.Material = Enum.Material.SmoothPlastic
			end
		end

		vestir(modelo)

		local cabeza = modelo:FindFirstChild("Head")
		if cabeza and cabeza:IsA("BasePart") then
			-- Un halo rojo: la señal de "vienen a por lo tuyo" tiene que verse por el
			-- rabillo del ojo mientras corres mirando al frente.
			--
			-- ROJO Y NO AZUL desde que los perseguidores son ladrones. El azul queda
			-- reservado entero para las comisarías, que son exactamente lo contrario
			-- --el sitio al que corres-- y compartir color con la amenaza obligaría al
			-- jugador a pararse a distinguirlos justo cuando no puede pararse.
			local luz = Instance.new("PointLight")
			luz.Color = Color3.fromRGB(255, 90, 80)
			luz.Range = 26
			luz.Brightness = 2.4
			luz.Parent = cabeza
		end

		modelo:PivotTo(CFrame.new(donde))
		-- QUE SE VEA VENIR DESDE LEJOS. "No veo los enemigos a lo lejos" (JJ), dicho
		-- tres veces con distintas palabras. Ya salen por delante y no a la espalda,
		-- pero un R6 gris a ciento treinta studs, entre edificios grises, no lo
		-- distingue nadie -- y un peligro que no se ve no se puede esquivar, así que
		-- deja de ser una decisión y vuelve a ser un impuesto.
		--
		-- Un Highlight lo contornea de rojo Y SE VE A TRAVÉS DE LAS PAREDES. Eso último
		-- es deliberado: lo que hace falta saber es POR DÓNDE viene, para meterse por
		-- otra calle antes de tenerlo encima. Si sólo se viera en línea recta, te
		-- enterarías al doblar la esquina, que es tarde.
		--
		-- No es una torre ni una columna: va pegado al ladrón y se mueve con él.
		local aviso = Instance.new("Highlight")
		aviso.Name = "Aviso"
		aviso.FillColor = Color3.fromRGB(220, 60, 50)
		aviso.FillTransparency = 0.55
		aviso.OutlineColor = Color3.fromRGB(255, 120, 100)
		aviso.OutlineTransparency = 0
		aviso.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		aviso.Parent = modelo

		modelo.Parent = contenedor()

		-- Su vehículo, si le toca uno. Va DESPUÉS de meterlo en el mundo porque
		-- Ride suelda contra el HumanoidRootPart, y ése no existe hasta entonces.
		if vehiculo then
			Ride.montar(modelo, vehiculo)
		end

		local root = modelo:FindFirstChild("HumanoidRootPart") :: BasePart
		return { modelo = modelo, humanoid = humanoid, raiz = root, viva = true } :: Patrulla
	end)

	if not ok then
		warn("[Contrabando] no se pudo crear una patrulla: " .. tostring(resultado))
		return nil
	end
	return resultado
end

-- Un punto de aparición con suelo debajo, alrededor del jugador. Se prueban varios
-- ángulos y se coge el primero que tenga suelo: soltar un agente sobre un hueco lo
-- deja cayendo al vacío, y una patrulla que se suicida al aparecer no persigue a
-- nadie -- y encima el jugador no se entera de nada.
-- Por encima de esto ya no es calle, es tejado. La calzada esta a 19,2 y las losas
-- del juego a 22; treinta deja margen para aceras y zocalos sin llegar a confundir una
-- azotea con un sitio donde se puede estar.
local COTA_PISABLE = 30

-- EL SUELO PISABLE BAJO UN PUNTO, saltandose lo que estorbe por arriba.
--
-- ESTO EXISTE POR EL PEOR FALLO MEDIDO EN ESTE PROYECTO, y es de los que no dan
-- ningun error. Un rayo desde el cielo devuelve LO PRIMERO que toca, y sobre una
-- guarida lo primero es su nave: 26x18x26 macizos encima de la losa. Los ladrones
-- nacian a Y=44, sobre el tejado, sin camino para bajar.
--
-- Medido el 20/08 quedandome QUIETO cuarenta segundos en mitad de la ruta roja con
-- siete cajas y el calor al maximo: los tres perseguidores se quedaron clavados entre
-- 122 y 132 studs y en cuarenta segundos avanzaron DIEZ. `ComputeAsync` desde ellos
-- hasta mi devolvia `NoPath`. O sea que el calor, las guaridas, los ladrones, los
-- refugios y la ruta roja pagando x10 estaban ahi, se veian en el mapa, costaban
-- CPU... y no hacian absolutamente nada. El juego no tenia riesgo.
--
-- Es la trampa que este repo ya tiene escrita para los arboles --"un rayo desde el
-- cielo se para en la copa"-- y la misma que puso quince detectores en las azoteas.
-- Se paga una vez por cada sistema que planta algo en el mundo.
local function sueloPisable(x: number, z: number, desdeY: number, params: RaycastParams): Vector3?
	local altura = desdeY
	-- Seis rebotes: sobre una guarida hay losa, nave y tejado en la misma vertical, y
	-- con margen por si alguna vez se apila algo mas.
	for _ = 1, 6 do
		local golpe = workspace:Raycast(Vector3.new(x, altura, z), Vector3.new(0, -500, 0), params)
		if golpe == nil then
			return nil
		end
		if golpe.Position.Y <= COTA_PISABLE then
			return golpe.Position
		end
		-- Lo que ha tocado es un tejado: se sigue bajando desde justo debajo.
		altura = golpe.Position.Y - 1
	end
	return nil
end

local function puntoDeAparicion(centro: Vector3, rng: Random, haciaDonde: Vector3?): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { contenedor() }

	-- PRIMERO, LA GUARIDA. Es el cambio que pidió JJ: "te aparecen de repente;
	-- deberías poder mirar el mapa y planear por dónde ir". Un ladrón que sale de
	-- un sitio marcado en el mapa se puede rodear; uno que se materializa a tu
	-- espalda, no -- y eso no es tensión, es un impuesto.
	--
	-- Sólo si la guarida cae en la ventana buena (ver Lairs.sirve): pegada encima
	-- sería una emboscada, y al otro lado del barrio llegaría cuando el viaje ya ha
	-- terminado. Fuera de la ventana se cae al método de siempre -- antes un ladrón
	-- sin guarida que ningún ladrón.
	local cerca, distancia = Lairs.masCercana(centro, guaridas)
	if cerca ~= nil and Lairs.sirve(distancia, APARICION_MIN) then
		-- A LA CALLE, NO AL PATIO. Dos razones, y las dos medidas.
		--
		-- En el CENTRO esta la nave: 26x18x26 macizos. Salir de dentro de un edificio
		-- cerrado es no salir, y el rayo llega ahi porque atraviesa el tejado rebotando.
		--
		-- Y SOBRE LA LOSA tampoco vale, aunque parezca el sitio natural. La losa de la
		-- guarida esta a 22 y la calzada a 19,2: un escalon de 2,8 que el pathfinder
		-- SIN SALTOS no baja. Medido: desde radio 15 --sobre la losa-- `ComputeAsync`
		-- devuelve NoPath; desde radio 20 --ya en el asfalto-- devuelve Success. Es el
		-- mismo escalon que un dia dejo sin camino a pie a las cuatro rutas a la vez.
		--
		-- Asi que se empieza FUERA de la losa (mide 34 de lado, o sea 17 de radio) y se
		-- va abriendo. Un ladron que sale a la calle es ademas lo que el jugador espera
		-- ver: sale por la puerta, no aparece en un patio elevado.
		for _, radio in { 20, 24, 28 } do
			for k = 0, 7 do
				local a = (k / 8) * math.pi * 2
				local x = cerca.X + math.cos(a) * radio
				local z = cerca.Z + math.sin(a) * radio
				local suelo = sueloPisable(x, z, cerca.Y + 60, params)
				if suelo ~= nil then
					return suelo + Vector3.new(0, 4, 0)
				end
			end
		end
	end

	-- SI NO HAY GUARIDA ÚTIL, POR DELANTE. No en un ángulo cualquiera.
	--
	-- El respaldo repartía la aparición por todo el círculo, así que la mitad de las
	-- veces el ladrón salía a la espalda del jugador y lo primero que se sabía de él
	-- era que ya te estaba encima. JJ lo dijo dos veces con las mismas palabras --
	-- "los enemigos aparecen de repente y no los veo a distancia", "enemigos por el
	-- camino que se vean"-- y no es un problema de distancia: a noventa studs se ve
	-- perfectamente CUALQUIER cosa, si está delante.
	--
	-- Con un cono de sesenta grados hacia donde vas, el ladrón aparece en tu campo de
	-- visión y la persecución empieza cuando tú lo ves, no cuando él te alcanza. Eso
	-- convierte el peligro en una decisión --rodeo, acelero, me meto por otra calle--
	-- que es lo que un impuesto no es.
	local rumbo: number? = nil
	if haciaDonde ~= nil then
		local d = haciaDonde - centro
		local plano = Vector3.new(d.X, 0, d.Z)
		if plano.Magnitude > 1 then
			rumbo = math.atan2(plano.Z, plano.X)
		end
	end

	for _ = 1, 8 do
		local angulo = if rumbo ~= nil
			then rumbo + rng:NextNumber(-math.pi / 3, math.pi / 3)
			else rng:NextNumber(0, math.pi * 2)
		local radio = rng:NextNumber(APARICION_MIN, APARICION_MAX)
		local x = centro.X + math.cos(angulo) * radio
		local z = centro.Z + math.sin(angulo) * radio
		local suelo = sueloPisable(x, z, centro.Y + 200, params)
		if suelo ~= nil then
			return suelo + Vector3.new(0, 4, 0)
		end
	end
	return nil
end

-- Las guaridas del mapa, que las planta CityBuilder. Se registran igual que los
-- refugios en HeatService: el servicio no las busca por su cuenta en workspace
-- porque entonces cada uno tendría su propia idea de qué es una guarida.
function PatrolService.registrarGuaridas(sitios: { Vector3 })
	guaridas = sitios
end

-- EL SEÑUELO: un cebo que se suelta en el suelo y al que van los ladrones que
-- estén cerca. Es la única habilidad que se PULSA, y es la mitad de por qué el
-- viaje pasa de aguantar a decidir.
--
-- RETRASA, NO ANULA, y eso no es un detalle de equilibrio: es la regla de oro. La
-- persecución sigue viva todo el rato -- sólo cambia a dónde van mientras dura --
-- y tiene recarga, así que nadie se vuelve inalcanzable por comprarlo.
-- LO ULTIMO QUE VIO CADA LADRON. En memoria y por patrulla: es lo que le permite
-- seguirte hasta la esquina por la que desapareciste sin volverse omnisciente.
local visto: { [any]: Vision.Recuerdo } = {}

local senuelos: { [Player]: { donde: Vector3, hasta: number } } = {}

function PatrolService.senuelo(player: Player, donde: Vector3, hasta: number)
	senuelos[player] = { donde = donde, hasta = hasta }
end

-- Dónde tiene que ir quien persigue a este jugador: el cebo si está vivo y la
-- patrulla lo tiene cerca, o el jugador. La distancia se mide desde LA PATRULLA,
-- no desde el jugador: un cebo soltado al otro lado del mapa no debe apartar a
-- nadie de su presa.
local function objetivoDe(player: Player, desde: Vector3, ahora: number): Vector3?
	local cebo = senuelos[player]
	if not cebo then
		return nil
	end
	if ahora >= cebo.hasta then
		senuelos[player] = nil
		return nil
	end
	if (cebo.donde - desde).Magnitude > Config.SENUELO_RADIO then
		return nil
	end
	return cebo.donde
end

local function retirar(player: Player)
	senuelos[player] = nil
	local lista = escoltas[player]
	if not lista then
		return
	end
	for _, p in lista do
		p.viva = false
		if p.modelo.Parent then
			p.modelo:Destroy()
		end
	end
	escoltas[player] = nil
	HeatService.marcarPerseguido(player, false)
end

-- Te ha alcanzado. NO MATA: perder mercancía es que te salga mal un viaje y quieras
-- otro; morir es que te echen de la sesión, y de una sesión interrumpida no se
-- vuelve.
local function alcanzar(player: Player)
	local estado = PlayerState.get(player)
	-- Lo que te quitan depende de EN QUÉ VAS: a pie lo sueltas todo, en furgoneta
	-- pierdes bastante menos. Es el otro lado de que la furgoneta se vea venir de
	-- más lejos (Vehicles.bulto).
	-- El vehículo y el AGUANTE, juntos: los dos son factores sobre lo mismo, y
	-- Heat.cajasIncautadas les pone el suelo para que nunca salga cero.
	local cuantas =
		Heat.cajasIncautadas(#estado.cajas, Vehicles.expone(estado.vehiculo) * Skills.factorRobo(estado.habilidades))
	if cuantas > 0 then
		for _ = 1, cuantas do
			table.remove(estado.cajas)
		end
		CargoService.aplicarVelocidad(player)
		CargoService.mostrarCarga(player)
	end

	Remotes.event(Remotes.AVISO)
		:FireClient(player, if cuantas > 0 then "ROBBED" else "ROBBED_EMPTY", { cuantas = cuantas }, Palette.AVISO_MALO)
	Telemetry.evento(player, "ladron_alcanza", { cajas = cuantas })

	-- Y LA RACHA, ENTERA. Es el paso en falso: pierdes la carga y pierdes la
	-- velocidad que habías acumulado recogiendo. Que las dos cosas se vayan en el
	-- mismo golpe es lo que convierte el robo en un momento, y no hace falta
	-- explicarlo -- se nota en el paso siguiente.
	CargoService.reiniciarRacha(player)

	-- El calor a cero y las patrullas fuera. Si siguieran encima, el jugador
	-- perdería la otra mitad tres segundos después y el mensaje que se llevaría es
	-- que no hay nada que hacer -- que es justo cuando se cierra el juego.
	HeatService.capturado(player)
	retirar(player)
	PlayerState.sync(player)
end

-- El cerebro de una patrulla, en su propio hilo. Replantea el camino cada dos
-- segundos y recorre los puntos calculados mientras tanto.
local function perseguir(patrulla: Patrulla, player: Player)
	task.spawn(function()
		-- Tramos seguidos sin avanzar. Vive fuera del bucle de waypoints a
		-- propósito: encallarse es un patrón que sólo se ve mirando VARIOS tramos
		-- seguidos -- uno suelto puede ser un roce con una farola.
		local atascos = 0
		local camino = PathfindingService:CreatePath({
			AgentRadius = 3,
			AgentHeight = 6,
			-- CON SALTO. Sin él, dos de las tres zonas son inalcanzables: es el
			-- hallazgo que decidió que la policía fuese a pie.
			AgentCanJump = true,
		})

		while patrulla.viva and patrulla.modelo.Parent do
			local objetivo = raiz(player)
			if not objetivo or not player.Parent then
				break
			end

			local separacion = (objetivo.Position - patrulla.raiz.Position).Magnitude

			-- DENTRO DE UN REFUGIO NO TE ALCANZAN. Es la promesa entera del sistema
			-- y no admite excepciones: si te pillaran en el último paso, entrar
			-- dejaría de ser una decisión y pasaría a ser una apuesta -- y nadie
			-- vuelve a fiarse de un refugio que le ha fallado una vez.
			if HeatService.enRefugio(objetivo.Position) then
				-- Se queda rondando fuera en vez de irse: el jugador tiene que ver
				-- que le esperan, porque eso es lo que convierte estar a salvo en
				-- una decisión (salir ahora y correr, o esperar a que se enfríe).
				patrulla.humanoid:MoveTo(objetivo.Position)
				task.wait(1.5)
				continue
			end

			-- ¿Hay cebo? Entonces va al cebo, y NO alcanza mientras tanto. Que no
			-- alcance es la mitad del truco: si siguiera robando de camino al
			-- señuelo, el señuelo no serviría de nada.
			local cebo = objetivoDe(player, patrulla.raiz.Position, os.clock())
			if cebo then
				patrulla.humanoid:MoveTo(cebo)
				task.wait(0.5)
				continue
			end

			-- ¿TE VE? Es la regla que le da espalda al peligro.
			--
			-- Se mira ANTES que el alcance: un ladron que te roba de espaldas no tiene
			-- campo de vision, tiene una excusa. Y se mira contra su LookVector real, no
			-- contra hacia donde va, porque lo que el jugador ve en el suelo es el cono
			-- --el abanico de rayos-- y las dos cosas tienen que decir lo mismo. Que el
			-- dibujo y la regla se separen es como se pierde la confianza en un sistema.
			local mirando = patrulla.raiz.CFrame.LookVector
			local teVe = Vision.dentroDelCono(
				patrulla.raiz.Position,
				mirando,
				objetivo.Position,
				Config.LADRON_VISION_ANGULO,
				Config.LADRON_VISION_ALCANCE
			)
			-- Y CON LA PARED DE POR MEDIO TAMPOCO. Sin esto, el cono atravesaria una
			-- manzana entera y esconderse detras de un edificio no serviria de nada, que
			-- es justo la mitad de lo que se venia a arreglar.
			if teVe then
				local rayo = RaycastParams.new()
				rayo.FilterType = Enum.RaycastFilterType.Exclude
				rayo.FilterDescendantsInstances = { patrulla.modelo, player.Character :: any, contenedor() }
				local golpe =
					workspace:Raycast(patrulla.raiz.Position, objetivo.Position - patrulla.raiz.Position, rayo)
				if golpe ~= nil then
					teVe = false
				end
			end

			if teVe then
				visto[patrulla] = { donde = objetivo.Position, cuando = os.clock() }
			end

			-- SI NO TE VE, VA A DONDE TE VIO. Un ladron que se queda plantado se nota
			-- tonto enseguida; uno que sigue sabiendo donde estas no tiene espalda. La
			-- memoria corta resuelve las dos: viene hasta la esquina por la que
			-- desapareciste, y si al llegar no estas, te ha perdido de verdad.
			if not teVe then
				local rastro = Vision.aDondeVa(visto[patrulla], os.clock(), Config.LADRON_MEMORIA)
				if rastro == nil then
					-- Te ha perdido. Se queda donde esta en vez de morirse: el calor
					-- sigue alto y en cuanto vuelvas a cruzarte te ve otra vez.
					task.wait(0.6)
					continue
				end
				patrulla.humanoid:MoveTo(rastro)
				task.wait(0.5)
				continue
			end

			if separacion <= Config.PATRULLA_ALCANCE then
				alcanzar(player)
				break
			end
			if separacion > ABANDONO then
				break
			end

			-- Aquí NO se toca "te están viendo". Lo decide ajustar(), mirando todas
			-- las patrullas a la vez, y el motivo es un fallo real que tenía este
			-- código: con tres perseguidores escribiendo el MISMO booleano, la
			-- última en pasar por aquí ganaba. Bastaba con que una se quedara atrás
			-- (a más de 120) para que apagara la señal que las otras dos, encima del
			-- jugador, acababan de encender -- y el calor se ponía a enfriar en plena
			-- persecución. Peor aún: al salir de este bucle por cualquier vía que no
			-- fuera alejarse (el jugador muere, se desconecta, reaparece), el
			-- booleano se quedaba en `true` PARA SIEMPRE y el calor no volvía a bajar
			-- nunca. Ninguna de las dos cosas revienta ni deja rastro: el juego
			-- simplemente se vuelve más fácil o imposible sin que nadie sepa por qué.
			local ok = pcall(function()
				camino:ComputeAsync(patrulla.raiz.Position, objetivo.Position)
			end)

			if ok and camino.Status == Enum.PathStatus.Success then
				local puntos = camino:GetWaypoints()
				local t0 = os.clock()
				for i = 2, #puntos do
					if not patrulla.viva or not patrulla.modelo.Parent then
						return
					end
					if puntos[i].Action == Enum.PathWaypointAction.Jump then
						patrulla.humanoid.Jump = true
					end
					local antes = patrulla.raiz.Position
					patrulla.humanoid:MoveTo(puntos[i].Position)
					patrulla.humanoid.MoveToFinished:Wait()

					-- ¿SE HA QUEDADO ENCALLADA? Medido recorriendo el mapa: hay 116
					-- vallas repartidas por la ciudad, y el pathfinding manda contra
					-- ellas -- una sonda acabó empujando una durante minutos, en
					-- estado Running, a 11,8 de velocidad y avanzando cero.
					--
					-- A un jugador esto no le pasa: ve la valla y la rodea. A un PNJ
					-- sí, y ahí es donde duele: una patrulla clavada detrás de una
					-- valla deja de perseguir para siempre y el jugador NO SE ENTERA
					-- de nada -- sigue corriendo con tres estrellas creyendo que le
					-- pisan los talones. El sistema se apaga solo y en silencio, que
					-- es la peor forma de fallar que tiene este juego.
					if (patrulla.raiz.Position - antes).Magnitude < 2 then
						atascos += 1
						if atascos >= 3 then
							-- Tres tramos seguidos sin moverse: no es un roce, está
							-- encajada. Se la reubica cerca del jugador en vez de
							-- destruirla, para que la persecución siga existiendo.
							-- Reaparecer a 90-140 studs no regala nada: es la misma
							-- distancia a la que habría salido de nuevas.
							local sitio = puntoDeAparicion(objetivo.Position, rng)
							if sitio then
								patrulla.modelo:PivotTo(CFrame.new(sitio))
							end
							atascos = 0
						end
						break -- y en cualquier caso, replantear el camino
					else
						atascos = 0
					end
					-- Se abandona el camino calculado en cuanto caduca: perseguir
					-- hasta el final una ruta hacia donde el jugador ESTABA es la
					-- diferencia entre un perseguidor y un sonámbulo.
					if os.clock() - t0 > REPLANTEO then
						break
					end
				end
			else
				-- Sin camino (el jugador se ha metido donde no se llega andando):
				-- se acerca en línea recta, que al menos mantiene la presión.
				patrulla.humanoid:MoveTo(objetivo.Position)
				task.wait(REPLANTEO)
			end
		end

		patrulla.viva = false
		if patrulla.modelo.Parent then
			patrulla.modelo:Destroy()
		end
	end)
end

-- Ajusta cuántas patrullas hay encima de un jugador a lo que pide su calor.
local function ajustar(player: Player)
	local nivel = HeatService.nivel(player)
	-- Y UNO MÁS SI LLEVA ALGO CARO. La decisión es del jugador --se la ha cargado él
	-- a la espalda-- y por eso puede escalar la amenaza sin castigar el progreso.
	local quieren = Heat.patrullas(nivel, Heat.cargaLlamativa(PlayerState.get(player).cajas))

	if quieren == 0 then
		if escoltas[player] then
			Remotes.event(Remotes.AVISO):FireClient(player, "CHASE_LOST_THEM", nil, Palette.AVISO_BUENO)
			retirar(player)
		end
		-- Y la señal se apaga SIEMPRE, no sólo cuando había escoltas que retirar.
		-- Sin patrullas no hay nadie mirando, por definición; dejarlo a medias
		-- permitiría que un `true` colgado de una persecución anterior impidiera
		-- enfriar para siempre, con el jugador solo en mitad de la calle sin
		-- entender por qué no le baja el calor.
		HeatService.marcarPerseguido(player, false)
		return
	end

	local lista = escoltas[player]
	if not lista then
		lista = {}
		escoltas[player] = lista
	end

	-- Las que se hayan quedado por el camino (destruidas, abandonadas) salen de la
	-- lista antes de contar: si no, el recuento diría que hay tres cuando ya sólo
	-- persigue una, y el calor 3 acabaría siendo más flojo que el calor 1.
	for i = #lista, 1, -1 do
		if not lista[i].viva or not lista[i].modelo.Parent then
			table.remove(lista, i)
		end
	end

	-- La velocidad de la patrulla NUNCA baja de la del perseguido más un margen.
	--
	-- El diseño tenía una regla tajante --"ningún vehículo te hace inatrapable: en
	-- el momento en que alguien es inalcanzable, el PvP muere y las rutas rojas
	-- pasan a ser dinero gratis"-- y la escalera de vehículos, que sí sube la
	-- velocidad, la rompía por la letra: con la furgoneta a 22 y las patrullas a 22,
	-- nadie te alcanza jamás.
	--
	-- Se conserva el ESPÍRITU en vez de la letra, y sale más barato que congelar la
	-- progresión: el perseguidor escala contigo. Lo que sigue decidiendo la
	-- persecución es lo de siempre -- él va más rápido pero atado a las calles, y tú
	-- puedes cortar por parques. Comprar una moto te hace llegar antes, no
	-- invisible.
	local velocidad = math.max(
		Heat.velocidadPatrulla(nivel),
		Cargo.velocidad(PlayerState.get(player).cajas, PlayerState.get(player).vehiculo) + 3
	)
	for _, p in lista do
		p.humanoid.WalkSpeed = velocidad
	end

	local objetivo = raiz(player)
	if not objetivo then
		return
	end

	-- "¿Te está viendo alguna?", decidido AQUÍ y en un solo sitio: un único
	-- escritor, una vez por segundo, mirando a todas. Es lo que impide que tres
	-- perseguidores se pisen el mismo booleano y que quede encendido para siempre
	-- cuando una muere lejos. Basta con que UNA esté encima para que el calor no
	-- enfríe -- que es lo que el jugador percibe: si los tienes detrás, no los has
	-- perdido.
	local alguienTeVe = false
	for _, p in lista do
		if p.viva and p.modelo.Parent and (objetivo.Position - p.raiz.Position).Magnitude < 120 then
			alguienTeVe = true
			break
		end
	end
	HeatService.marcarPerseguido(player, alguienTeVe)

	while #lista < quieren do
		-- Hacia donde va: el destino de su ruta. Si va de vacío o sin ruta, no hay
		-- rumbo que respetar y se cae al círculo completo.
		local rutaActual = PlayerState.get(player).ruta
		local haciaDonde = if typeof(rutaActual) == "string" and Routes.existe(rutaActual)
			then Routes.get(rutaActual).destino
			else nil
		local donde = puntoDeAparicion(objetivo.Position, rng, haciaDonde)
		if not donde then
			break
		end
		local nueva = crearAgente(donde, velocidad, vehiculoDelPerseguidor(PlayerState.get(player).vehiculo))
		if not nueva then
			break
		end
		table.insert(lista, nueva)
		perseguir(nueva, player)
		if #lista == 1 then
			Remotes.event(Remotes.AVISO):FireClient(player, "CHASE_ON_YOU", nil, Palette.AVISO_MALO)
		end
	end
end

function PatrolService.start()
	Players.PlayerRemoving:Connect(retirar)

	task.spawn(function()
		while true do
			task.wait(1)
			PlayerState.forEach(function(player)
				local ok, err = pcall(function()
					ajustar(player)
				end)
				if not ok then
					warn("[Contrabando] fallo ajustando patrullas: " .. tostring(err))
				end
			end)
		end
	end)
end

return PatrolService
