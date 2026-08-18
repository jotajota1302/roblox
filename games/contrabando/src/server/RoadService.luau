--!strict
--[[
	RoadService.luau — hace cumplir la regla de la calle.

	Las reglas están en Shared.Roads (puro y probado); aquí sólo se mira dónde pisa
	cada jugador y se actúa: bajarlo del vehículo al salirse del asfalto, dejar el
	vehículo aparcado donde lo dejó, y volverlo a montar cuando regresa a por él.

	POR QUÉ EN EL SERVIDOR: la velocidad y el vehículo montado son estado del
	juego, no dibujo. Un cliente que decidiera por su cuenta "voy en moto" iría a
	34 studs/s por dentro de un parque.

	VA EN SU PROPIO BUCLE y no colgado del movimiento del personaje: Roblox no
	avisa de "he cambiado de superficie", y un raycast por jugador tres veces por
	segundo es despreciable (medido: 50 jugadores son 150 rayos/s, menos de lo que
	cuesta una sola llamada de pathfinding).
]]

local Players = game:GetService("Players")

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local PlayerState = require(script.Parent.PlayerState)
local Ride = require(script.Parent.Ride)

-- Cada cuánto se mira el suelo. Tres veces por segundo: a 34 studs/s eso son 11
-- studs entre muestras, menos que el ancho de un carril, así que no se puede
-- cruzar una calle entera sin que se note.
local PERIODO = 0.3

-- A qué distancia se recupera el vehículo aparcado. Generoso a propósito: buscar
-- el punto exacto donde lo dejaste sería un juego de precisión que nadie ha
-- pedido.
local DISTANCIA_RECOGIDA = 12

local RoadService = {}

-- Los vehículos aparcados, por jugador. Viven aquí y no en PlayerState porque son
-- una pieza del mundo (un modelo con su sitio), no un dato que haya que guardar
-- en la nube: si te desconectas, tu moto no se queda en la calle para siempre.
type Aparcado = {
	vehiculo: string,
	modelo: Model,
}
local aparcados: { [Player]: Aparcado } = {}

-- El último sitio con asfalto donde se le vio. Es DONDE SE APARCA el vehículo, y
-- no el punto exacto en que se salió: medido jugando, salirse deja el punto de
-- salida ya sobre el césped, así que la moto quedaba tirada en mitad de un parque
-- -- y como para recuperarla hay que estar en asfalto, no se podía recuperar
-- NUNCA. Un vehículo de 4.500 monedas perdido por cruzar un seto.
local ultimaCalzada: { [Player]: Vector3 } = {}

local function contenedor(): Folder
	local f = workspace:FindFirstChild("VehiculosAparcados")
	if f then
		return f :: Folder
	end
	local nuevo = Instance.new("Folder")
	nuevo.Name = "VehiculosAparcados"
	nuevo.Parent = workspace
	return nuevo
end

local function avisar(player: Player, texto: string, color: Color3)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, color)
end

-- Qué hay bajo los pies. Devuelve si es rodable y el punto.
--
-- Nuestras propias losas cuentan SIEMPRE como rodables aunque sean verdes o
-- ámbar: el almacén, el taller, los destinos y el sendero son sitios del juego, y
-- que la moto se apagara al entrar en tu propio muelle sería absurdo. Lo dice un
-- atributo puesto por CityBuilder, no el color.
local function sueloBajoLosPies(root: BasePart): (boolean, Vector3?)
	-- TU PROPIO RECINTO ES RODABLE ENTERO. Dentro hay césped entre el almacén, el
	-- taller y la salida, y sin esta regla comprar una moto significaría bajarse de
	-- ella tres veces antes de salir de casa. El patio es tuyo: ahí se rueda.
	if Perimeter.dentro(root.Position, Config.ALMACEN_POS) then
		return true, root.Position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, contenedor() }
	local golpe = workspace:Raycast(root.Position, Vector3.new(0, -14, 0), params)
	if golpe == nil then
		-- En el aire (un salto, una caída): no es motivo para bajarse. Se conserva
		-- el estado anterior en vez de inventarse uno.
		return true, nil
	end
	if golpe.Instance:GetAttribute("rodable") == true then
		return true, golpe.Position
	end
	return Roads.esCalzada(golpe.Instance.Color), golpe.Position
end

local function guardarAparcado(player: Player, vehiculo: string, donde: Vector3)
	local modelo = Instance.new("Model")
	modelo.Name = "Aparcado_" .. player.Name
	modelo.Parent = contenedor()

	-- Se reutiliza el mismo dibujo que lleva el jugador encima: un vehículo
	-- aparcado que no se pareciera al que conducías no se reconocería como tuyo.
	local maniqui = Instance.new("Part")
	maniqui.Name = "HumanoidRootPart"
	maniqui.Size = Vector3.new(2, 2, 1)
	maniqui.Transparency = 1
	maniqui.CanCollide = false
	maniqui.Anchored = true
	maniqui.CFrame = CFrame.new(donde + Vector3.new(0, 3, 0))
	maniqui.Parent = modelo
	modelo.PrimaryPart = maniqui

	local ok = pcall(function()
		Ride.montar(modelo, vehiculo)
	end)
	if not ok then
		modelo:Destroy()
		return nil
	end
	-- Todo anclado: el modelo va soldado a un maniquí que no tiene humanoide, así
	-- que sin anclar se caería al suelo en cuanto la física lo tocara.
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- La marca para encontrarlo: una baliza corta y su nombre. Sin esto, dejar el
	-- vehículo en un callejón es perderlo.
	local baliza = Instance.new("Part")
	baliza.Name = "Baliza"
	baliza.Size = Vector3.new(1.2, 26, 1.2)
	baliza.Position = donde + Vector3.new(0, 13, 0)
	baliza.Color = Palette.TALLER
	baliza.Material = Enum.Material.Neon
	baliza.Transparency = 0.4
	baliza.Anchored = true
	baliza.CanCollide = false
	baliza.CastShadow = false
	baliza.Parent = modelo

	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Cartel"
	cartel.Size = UDim2.fromScale(9, 2.4)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
	cartel.AlwaysOnTop = true
	cartel.MaxDistance = 320
	cartel.Adornee = baliza
	cartel.Parent = baliza

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(255, 240, 200)
	texto.TextStrokeTransparency = 0.3
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = "aquí dejaste tu vehículo"
	texto.Parent = cartel

	aparcados[player] = { vehiculo = vehiculo, modelo = modelo }
	return modelo
end

local function recoger(player: Player)
	local guardado = aparcados[player]
	if not guardado then
		return
	end
	guardado.modelo:Destroy()
	aparcados[player] = nil
end

function RoadService.aparcarDe(player: Player): Vector3?
	local guardado = aparcados[player]
	return guardado and guardado.modelo:GetPivot().Position or nil
end

-- Se le llama desde fuera cuando el jugador pierde el cuerpo (muerte, salida):
-- una moto aparcada de alguien que ya no está sólo estorba.
function RoadService.olvidar(player: Player)
	recoger(player)
end

local function paso(player: Player)
	local estado = PlayerState.peek(player)
	if estado == nil then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local vehiculo = estado.vehiculo
	local montado = estado.montado ~= false
	local guardado = aparcados[player]
	local enCalzada, punto = sueloBajoLosPies(root)

	if enCalzada and punto ~= nil then
		ultimaCalzada[player] = punto
	end

	if montado and Roads.exigeCalzada(vehiculo) and not enCalzada then
		-- SE BAJA, y el vehículo se queda en el último asfalto que pisó: dejarlo
		-- donde te saliste es dejarlo dentro del seto.
		estado.montado = false
		Ride.montar(character, nil)
		guardarAparcado(player, vehiculo :: string, ultimaCalzada[player] or root.Position)
		avisar(player, "Te bajas: aquí no se puede rodar", Color3.fromRGB(232, 176, 64))
		PlayerState.sync(player)
	elseif not montado and guardado ~= nil then
		local cerca = (root.Position - guardado.modelo:GetPivot().Position).Magnitude
		-- SIN exigir estar en asfalto para recogerlo: te acercas por donde te
		-- acerques. Exigirlo era la otra mitad del vehículo irrecuperable.
		if cerca <= DISTANCIA_RECOGIDA then
			-- Y SE SUBE, sin pulsar nada: llegar hasta tu vehículo ES la intención.
			estado.montado = true
			recoger(player)
			Ride.montar(character, estado.vehiculo)
			avisar(player, "De vuelta al volante", Color3.fromRGB(150, 220, 160))
			PlayerState.sync(player)
		end
	end

	-- Y la velocidad, siempre: es lo que hace que la regla se NOTE. A pie con la
	-- moto aparcada se va a 16 aunque la moto sea tuya.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local cuenta = Roads.vehiculoQueCuenta(estado.vehiculo, estado.montado ~= false)
		humanoid.WalkSpeed = Cargo.velocidad(estado.cajas, cuenta)
	end
end

function RoadService.start()
	Players.PlayerRemoving:Connect(RoadService.olvidar)

	task.spawn(function()
		while true do
			task.wait(PERIODO)
			PlayerState.forEach(function(player)
				local ok, err = pcall(paso, player)
				if not ok then
					warn("[Contrabando] fallo mirando la calzada: " .. tostring(err))
				end
			end)
		end
	end)
end

return RoadService
