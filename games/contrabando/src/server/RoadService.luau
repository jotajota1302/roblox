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
local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Strings = require(game.ReplicatedStorage.Shared.Strings)
local PlayerState = require(script.Parent.PlayerState)
local CargoService = require(script.Parent.CargoService)
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

-- Quien se acaba de bajar A PROPÓSITO no se vuelve a subir solo. Sin esto, el
-- botón de bajarse no sirve para nada: te bajas, y como sigues a dos pasos del
-- vehículo, la vuelta siguiente del bucle te monta otra vez. Se olvida en cuanto
-- te alejas, que es la forma de decir "ya no lo quiero aquí".
local bajadoAProposito: { [Player]: boolean } = {}

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

local function avisar(player: Player, clave: string, args: { [string]: any }?, color: Color3?)
	Remotes.event(Remotes.AVISO):FireClient(player, clave, args, color)
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
	if Perimeter.dentro(root.Position) then
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

-- LA CARGA SE QUEDA CON EL VEHÍCULO.
--
-- MEDIDO JUGANDO, y es de las cosas que sólo se ven jugando: con la bicicleta
-- cargada de siete bultos, bajarse al pisar césped dejaba al personaje andando a
-- OCHO studs por segundo -- el suelo mínimo. El viaje a la ruta verde no se
-- completó en dos minutos y medio. La regla de la calzada, sin esto, convierte
-- cualquier vehículo grande en una trampa.
--
-- Y la solución es la obvia en cuanto se piensa en lo que representa: un
-- repartidor no se echa veinte bultos a la espalda al bajarse de la furgoneta.
-- Lo que no puedes llevar a pie se queda dentro, y vuelve contigo cuando
-- recuperas el vehículo. De paso, bajarse pasa a ser una decisión con precio:
-- dejas la carga ahí, a la vista.
local function descargarEnElVehiculo(player: Player, estado: any): number
	local aPie = Cargo.capacidad(Config.VEHICULO_INICIAL)
	local dejadas = {}
	while Cargo.pesoTotal(estado.cajas) > aPie and #estado.cajas > 0 do
		table.insert(dejadas, table.remove(estado.cajas))
	end
	if #dejadas == 0 then
		return 0
	end
	estado.cajasEnVehiculo = estado.cajasEnVehiculo or {}
	for _, caja in dejadas do
		table.insert(estado.cajasEnVehiculo, caja)
	end
	CargoService.mostrarCarga(player)
	return #dejadas
end

-- Y vuelve contigo al recuperarlo.
local function recuperarDelVehiculo(player: Player, estado: any): number
	local guardadas = estado.cajasEnVehiculo or {}
	if #guardadas == 0 then
		return 0
	end
	for _, caja in guardadas do
		table.insert(estado.cajas, caja)
	end
	estado.cajasEnVehiculo = {}
	CargoService.mostrarCarga(player)
	return #guardadas
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
	cartel.Size = UDim2.fromOffset(200, 46)
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
	texto.Text = Strings.get("SIGN_PARKED")
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

-- BAJARSE Y SUBIRSE A VOLUNTAD, que es lo que faltaba: hasta ahora sólo te bajabas
-- saliéndote del asfalto, así que con un coche no había forma de ir a pie a
-- ninguna parte -- "¿cómo te bajas del coche? porque no puedo" (JJ).
--
-- Es UNA sola acción y no dos (subir/bajar) a propósito: el jugador pulsa lo
-- mismo siempre y el juego decide qué toca. Dos botones para dos estados que se
-- excluyen son un botón apagado la mitad del tiempo.
function RoadService.alternar(player: Player)
	local estado = PlayerState.peek(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if estado == nil or root == nil then
		return
	end
	local vehiculo = estado.vehiculo
	if vehiculo == nil or vehiculo == Config.VEHICULO_INICIAL then
		avisar(player, "RIDE_NONE_YET", nil, Color3.fromRGB(232, 176, 64))
		return
	end

	if estado.montado ~= false then
		-- Se baja AQUÍ MISMO, no en la última calzada: bajarse a propósito es
		-- decir "lo dejo en este sitio", y moverlo a otro sería desobedecer.
		estado.montado = false
		bajadoAProposito[player] = true
		Ride.montar(character, nil)
		guardarAparcado(player, vehiculo, root.Position)
		local dejadas = descargarEnElVehiculo(player, estado)
		avisar(
			player,
			if dejadas > 0 then "RIDE_PARKED_WITH_CARGO" else "RIDE_PARKED",
			{ cuantas = dejadas },
			Color3.fromRGB(232, 176, 64)
		)
		PlayerState.sync(player)
		return
	end

	local guardado = aparcados[player]
	if guardado == nil then
		-- No debería pasar, pero si el vehículo se perdió por lo que sea, no se
		-- deja al jugador a pie para siempre: se le devuelve.
		estado.montado = true
		Ride.montar(character, vehiculo)
		PlayerState.sync(player)
		return
	end

	local donde = guardado.modelo:GetPivot().Position
	local cerca = (root.Position - donde).Magnitude
	if cerca > DISTANCIA_RECOGIDA then
		avisar(player, "RIDE_TOO_FAR", { metros = math.floor(cerca) }, Color3.fromRGB(232, 176, 64))
		return
	end

	estado.montado = true
	bajadoAProposito[player] = nil
	recoger(player)
	Ride.montar(character, vehiculo)
	local recuperadas = recuperarDelVehiculo(player, estado)
	if recuperadas > 0 then
		avisar(player, "RIDE_CARGO_BACK", { cuantas = recuperadas }, Color3.fromRGB(150, 220, 160))
	end
	PlayerState.sync(player)
end

function RoadService.aparcarDe(player: Player): Vector3?
	local guardado = aparcados[player]
	return guardado and guardado.modelo:GetPivot().Position or nil
end

-- Se le llama desde fuera cuando el jugador pierde el cuerpo (muerte, salida):
-- una moto aparcada de alguien que ya no está sólo estorba.
function RoadService.olvidar(player: Player)
	recoger(player)
	bajadoAProposito[player] = nil
	ultimaCalzada[player] = nil
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

	if guardado ~= nil and Perimeter.dentro(root.Position) then
		-- EL VEHÍCULO VUELVE A CASA CONTIGO. "Si he vuelto al almacén debería estar
		-- en el taller ya" (JJ), y tiene razón: obligar a cruzar media ciudad a pie
		-- para recuperar la moto que dejaste tirada es un castigo que no decide
		-- nada -- ya pagaste el precio al bajarte, que fue hacer el resto del viaje
		-- andando.
		--
		-- Vuelve AL GARAJE, no a tus manos: lo sacas en el taller cuando quieras,
		-- con la carga que llevara dentro. Y así el garaje sigue siendo el único
		-- sitio donde se cambia de vehículo.
		recoger(player)
		bajadoAProposito[player] = nil
		avisar(player, "RIDE_SENT_HOME", nil, Color3.fromRGB(150, 220, 160))
		PlayerState.sync(player)
	elseif montado and Roads.exigeCalzada(vehiculo) and not enCalzada then
		-- SE BAJA, y el vehículo se queda en el último asfalto que pisó: dejarlo
		-- donde te saliste es dejarlo dentro del seto.
		estado.montado = false
		Ride.montar(character, nil)
		guardarAparcado(player, vehiculo :: string, ultimaCalzada[player] or root.Position)
		local dejadas = descargarEnElVehiculo(player, estado)
		avisar(
			player,
			if dejadas > 0 then "RIDE_GET_OFF_WITH_CARGO" else "RIDE_GET_OFF_NO_ROAD",
			{ cuantas = dejadas },
			Color3.fromRGB(232, 176, 64)
		)
		PlayerState.sync(player)
	elseif not montado and guardado ~= nil then
		local cerca = (root.Position - guardado.modelo:GetPivot().Position).Magnitude
		if cerca > DISTANCIA_RECOGIDA then
			-- Te has alejado: si te bajaste a propósito, ya no cuenta.
			bajadoAProposito[player] = nil
		end
		-- SIN exigir estar en asfalto para recogerlo: te acercas por donde te
		-- acerques. Exigirlo era la otra mitad del vehículo irrecuperable.
		if cerca <= DISTANCIA_RECOGIDA and not bajadoAProposito[player] then
			-- Y SE SUBE, sin pulsar nada: llegar hasta tu vehículo ES la intención.
			estado.montado = true
			recoger(player)
			Ride.montar(character, estado.vehiculo)
			local recuperadas = recuperarDelVehiculo(player, estado)
			avisar(
				player,
				if recuperadas > 0 then "RIDE_BACK_ON_WITH_CARGO" else "RIDE_BACK_ON",
				{ cuantas = recuperadas },
				Color3.fromRGB(150, 220, 160)
			)
			PlayerState.sync(player)
		end
	end

	-- Y la velocidad, siempre: es lo que hace que la regla se NOTE. A pie con la
	-- moto aparcada se va a 16 aunque la moto sea tuya.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local cuenta = Roads.vehiculoQueCuenta(estado.vehiculo, estado.montado ~= false)
		-- Con la racha del viaje encima (ver CargoService.aplicarVelocidad): los dos
		-- sitios que escriben WalkSpeed tienen que decir lo mismo, o bajarse del
		-- vehículo borraría lo que has acelerado.
		local velocidad = Contacts.velocidadConRacha(Cargo.velocidad(estado.cajas, cuenta), estado.recogidos or 0)
		humanoid.WalkSpeed = velocidad

		-- Y EL MOTOR SUBE DE TONO CON LA VELOCIDAD. Es lo que separa un ruido de
		-- fondo de una respuesta: cargado hasta arriba el motor se oye ahogado, y
		-- vacío por una recta se oye cómo tira. El bucle ya está sonando (lo monta
		-- Ride); aquí sólo se le mueve el tono.
		local ruido = root:FindFirstChild("RuidoVehiculo") :: Sound?
		local def = Config.SONIDOS_VEHICULO[cuenta or ""]
		if ruido and def then
			local nominal = Cargo.velocidad({}, cuenta)
			-- Entre el 82 % y el 100 % del tono según lo cargado que vayas. Poco
			-- margen a propósito: un motor que cambia de tono a lo bruto suena a
			-- juguete estropeado.
			local proporcion = if nominal > 0 then math.clamp(velocidad / nominal, 0.55, 1) else 1
			ruido.PlaybackSpeed = def.tono * (0.82 + 0.18 * proporcion)
			-- Y CALLA SEGÚN LO QUE SEA. Un motor parado sigue sonando --su ralentí
			-- es la mitad de lo que dice "vas en moto"-- pero una rueda parada no
			-- hace ningún ruido, y tratarlas igual daba un siseo permanente que
			-- JJ describió como insoportable, con toda la razón.
			local quieto = humanoid.MoveDirection.Magnitude < 0.1
			if quieto then
				ruido.Volume = if def.motor then def.volumen * 0.3 else 0
			else
				ruido.Volume = def.volumen
			end
		end
	end
end

function RoadService.start()
	Players.PlayerRemoving:Connect(RoadService.olvidar)

	Remotes.event(Remotes.MONTAR).OnServerEvent:Connect(function(player)
		local ok, err = pcall(RoadService.alternar, player)
		if not ok then
			warn("[Contrabando] fallo al montar/bajar: " .. tostring(err))
		end
	end)

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
