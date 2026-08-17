--!strict
--[[
	PatrolService.luau — la policía que te busca cuando te has calentado.

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

local Config = require(game.ReplicatedStorage.Shared.Config)
local Heat = require(game.ReplicatedStorage.Shared.Heat)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local CargoService = require(script.Parent.CargoService)
local HeatService = require(script.Parent.HeatService)
local PlayerState = require(script.Parent.PlayerState)
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

type Patrulla = {
	modelo: Model,
	humanoid: Humanoid,
	raiz: BasePart,
	viva: boolean,
}

local escoltas: { [Player]: { Patrulla } } = {}
local carpeta: Folder? = nil

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
local function crearAgente(donde: Vector3, velocidad: number): Patrulla?
	local ok, resultado = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		local modelo = Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R6)
		modelo.Name = "Patrulla"

		local humanoid = modelo:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = velocidad
		-- Que no se pueda matar ni empujar: es un obstáculo del mundo, no un rival.
		-- Un agente al que se le puede tirar por un barranco convierte el sistema en
		-- un puzle de física en vez de en una persecución.
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge

		-- Azul policía en todo el cuerpo, para que se reconozca de un vistazo desde
		-- lejos. En una ciudad llena de gente de bloques, un perseguidor que parece
		-- un peatón cualquiera no avisa de nada.
		for _, parte in modelo:GetDescendants() do
			if parte:IsA("BasePart") then
				parte.Color = Palette.TALLER
				parte.Material = Enum.Material.SmoothPlastic
			end
		end

		local cabeza = modelo:FindFirstChild("Head")
		if cabeza and cabeza:IsA("BasePart") then
			-- Luz azul giratoria: la señal de "te están buscando" tiene que verse
			-- por el rabillo del ojo mientras corres mirando al frente.
			local luz = Instance.new("PointLight")
			luz.Color = Color3.fromRGB(90, 150, 255)
			luz.Range = 26
			luz.Brightness = 2.4
			luz.Parent = cabeza
		end

		modelo:PivotTo(CFrame.new(donde))
		modelo.Parent = contenedor()

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
local function puntoDeAparicion(centro: Vector3, rng: Random): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { contenedor() }

	for _ = 1, 8 do
		local angulo = rng:NextNumber(0, math.pi * 2)
		local radio = rng:NextNumber(APARICION_MIN, APARICION_MAX)
		local x = centro.X + math.cos(angulo) * radio
		local z = centro.Z + math.sin(angulo) * radio
		local golpe = workspace:Raycast(Vector3.new(x, centro.Y + 200, z), Vector3.new(0, -500, 0), params)
		if golpe then
			return golpe.Position + Vector3.new(0, 4, 0)
		end
	end
	return nil
end

local function retirar(player: Player)
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
	local cuantas = Heat.cajasIncautadas(#estado.cajas)
	if cuantas > 0 then
		for _ = 1, cuantas do
			table.remove(estado.cajas)
		end
		CargoService.aplicarVelocidad(player)
		CargoService.mostrarCarga(player)
	end

	Remotes.event(Remotes.AVISO):FireClient(
		player,
		cuantas > 0 and string.format("Te han pillado: se llevan %d cajas", cuantas)
			or "Te han pillado, pero ibas de vacío",
		Palette.AVISO_MALO
	)
	Telemetry.evento(player, "patrulla_alcanza", { cajas = cuantas })

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

			if separacion <= Config.PATRULLA_ALCANCE then
				alcanzar(player)
				break
			end
			if separacion > ABANDONO then
				break
			end

			-- Te ve: mientras esté encima, el calor no baja.
			HeatService.marcarPerseguido(player, separacion < 120)

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
					patrulla.humanoid:MoveTo(puntos[i].Position)
					patrulla.humanoid.MoveToFinished:Wait()
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

local rng = Random.new(os.clock() * 1000)

-- Ajusta cuántas patrullas hay encima de un jugador a lo que pide su calor.
local function ajustar(player: Player)
	local nivel = HeatService.nivel(player)
	local quieren = Heat.patrullas(nivel)

	if quieren == 0 then
		if escoltas[player] then
			Remotes.event(Remotes.AVISO):FireClient(player, "Los has despistado", Palette.AVISO_BUENO)
			retirar(player)
		end
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

	local velocidad = Heat.velocidadPatrulla(nivel)
	for _, p in lista do
		p.humanoid.WalkSpeed = velocidad
	end

	local objetivo = raiz(player)
	if not objetivo then
		return
	end

	while #lista < quieren do
		local donde = puntoDeAparicion(objetivo.Position, rng)
		if not donde then
			break
		end
		local nueva = crearAgente(donde, velocidad)
		if not nueva then
			break
		end
		table.insert(lista, nueva)
		perseguir(nueva, player)
		if #lista == 1 then
			Remotes.event(Remotes.AVISO):FireClient(player, "Te están buscando", Palette.AVISO_MALO)
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
