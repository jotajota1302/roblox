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

-- Dónde estaba cada uno en la vuelta anterior del bucle. Lo usa `velocidadReal`
-- para saber quién se está moviendo de verdad (ver su cabecera).
--
-- Se declara AQUÍ ARRIBA, con las demás tablas, y no junto a la función que la
-- usa: `RoadService.olvidar` la limpia y está por encima, y en Lua un nombre usado
-- antes de declararse como local se resuelve como global nil -- sin error, sin
-- aviso, y con la limpieza escribiendo en una tabla que no es ésta.
local ultimoSitio: { [Player]: Vector3 } = {}

-- Y hacia donde iba. De comparar esta direccion con la de ahora sale el DERRAPE:
-- girar mucho yendo deprisa. Vive aqui arriba con las demas por el mismo motivo
-- que `ultimoSitio` -- `RoadService.olvidar` la limpia y esta por encima, y un
-- nombre usado antes de declararse como local se resuelve como global nil, sin
-- error y sin aviso.
local ultimoRumbo: { [Player]: Vector3 } = {}

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
	ultimoSitio[player] = nil
	ultimoRumbo[player] = nil
end

-- LOS EFECTOS DE MOVERSE: polvo bajo los pies y estela cuando vas lanzado.
--
-- POR QUÉ, dicho por JJ: *"mejorar los efectos cuando vamos en vehículo o
-- movimientos"*. Y no es sólo vistosidad -- el juego tenía un problema concreto de
-- lectura: ir a 12 studs/s y a 22 se veía **exactamente igual**. El motor cambiaba
-- de tono, sí, pero la velocidad es la moneda del viaje desde que entró el rastro
-- (la racha da +51 %) y no se notaba en pantalla en absoluto.
--
-- Se montan en el SERVIDOR, como la carga visible y por lo mismo: la velocidad del
-- otro es información. Ver pasar a alguien dejando estela dice "ése lleva racha" y
-- eso decide si te merece la pena perseguirle.
--
-- BARATOS A PROPÓSITO. Se crean UNA vez por personaje y después sólo se les mueve
-- un número; nada de crear y destruir por fotograma. Las texturas son `rbxasset://`
-- --las que trae el propio cliente-- y no `rbxassetid://`: las segundas hay que
-- publicarlas y no se ven hasta entonces, que es una trampa que este proyecto ya
-- pagó con los meshes.
-- CUÁNTO SE MUEVE DE VERDAD, medido por dónde estaba hace un tercio de segundo.
--
-- Es la tercera forma de preguntarlo y la única que funciona desde el servidor. Las
-- dos anteriores se probaron y se midieron fallando:
--
--   · `MoveDirection` dice si el jugador está pulsando algo. Vale para el sonido
--     del motor --un ralentí es que tienes el vehículo encendido, no que te
--     muevas-- pero el personaje es propiedad de RED DEL CLIENTE, así que en el
--     servidor se queda a cero salvo que haya alguien pulsando de verdad;
--   · `AssemblyLinearVelocity` tiene el mismo dueño y el mismo problema: se le
--     puede escribir un 18 desde aquí y leer un 0 al instante siguiente.
--
-- La POSICIÓN sí se replica siempre --es lo que ve todo el mundo-- así que restar
-- dos posiciones seguidas da la velocidad real sin depender de quién manda en la
-- física. Y de paso sale un dato mejor que WalkSpeed: WalkSpeed es lo que PODRÍAS
-- correr, y esto es lo que estás corriendo.
-- Devuelve la velocidad y CUANTO HA GIRADO desde la muestra anterior, en grados.
--
-- Las dos salen de lo mismo --restar dos posiciones-- y por eso van juntas: son la
-- misma medida vista por sus dos componentes, el modulo y el angulo. Separarlas
-- obligaria a guardar la posicion anterior dos veces y garantizaria que un dia una
-- se actualice y la otra no.
local function velocidadReal(player: Player, root: BasePart): (number, number)
	local antes = ultimoSitio[player]
	ultimoSitio[player] = root.Position
	if antes == nil then
		return 0, 0
	end
	local dx, dz = root.Position.X - antes.X, root.Position.Z - antes.Z
	local recorrido = math.sqrt(dx * dx + dz * dz)
	local velocidad = recorrido / PERIODO

	-- El giro solo tiene sentido si te estas moviendo: parado, la direccion es ruido
	-- y saldrian derrapes por quedarse quieto.
	local giro = 0
	if recorrido > 1 then
		local rumbo = Vector3.new(dx, 0, dz).Unit
		local anterior = ultimoRumbo[player]
		if anterior ~= nil then
			-- Producto escalar de dos unitarios = coseno del angulo entre ellos. Se
			-- recorta a [-1,1] porque el redondeo puede sacarlo por una millonesima y
			-- `math.acos` de 1,0000001 devuelve nan -- que se propaga en silencio y
			-- deja el efecto encendido para siempre.
			giro = math.deg(math.acos(math.clamp(rumbo:Dot(anterior), -1, 1)))
		end
		ultimoRumbo[player] = rumbo
	end
	return velocidad, giro
end

-- CUANDO CUENTA COMO DERRAPE. Lo pidio JJ: *"podriamos tener efectos al correr o
-- girar rapido, tipo derrape"*.
--
-- Dos condiciones a la vez, y las dos hacen falta: girar despacio no derrapa (es
-- una curva) y correr recto tampoco (para eso ya esta el polvo). Lo que se ve es
-- justo el cruce de ambas -- ir lanzado y cambiar de direccion de golpe.
--
-- Los numeros salen del bucle: se muestrea cada 0,3 s, asi que 45 grados entre
-- muestras es un giro de casi 150 grados por segundo. A pie eso no pasa andando;
-- pasa cuando das la vuelta huyendo, que es exactamente el momento que el efecto
-- quiere subrayar.
local DERRAPE_GIRO = 45
local DERRAPE_VELOCIDAD = 17

-- Las marcas de neumatico duran esto y se van solas. Cortas: son la huella de un
-- instante, y un mapa que se llena de rayas negras deja de leerse -- que es la
-- averia que ya costo una vez el rastro de migas.
local MARCA_SEGUNDOS = 5

local function derrapar(root: BasePart, rumbo: Vector3, motor: boolean)
	-- La rafaga de humo. El emisor se crea UNA vez y despues solo se le pide que
	-- dispare: crear y destruir uno por derrape es la fuga lenta que este mismo
	-- fichero ya pago con el polvo -- 1.658 emisores colgando de un jugador tras
	-- diez minutos, sin error y sin sintoma hasta que el movil va a tirones.
	local ancla = root:FindFirstChild("AnclaPies") :: Attachment?
	if ancla ~= nil then
		local humo = ancla:FindFirstChild("HumoDerrape") :: ParticleEmitter?
		if humo == nil then
			local e = Instance.new("ParticleEmitter")
			e.Name = "HumoDerrape"
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(220, 216, 208))
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2),
				NumberSequenceKeypoint.new(1, 4.5),
			})
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Lifetime = NumberRange.new(0.4, 0.8)
			e.Speed = NumberRange.new(2, 6)
			e.SpreadAngle = Vector2.new(40, 40)
			e.LightEmission = 0.2
			e.Rate = 0
			e.Parent = ancla
			humo = e
		end
		(humo :: ParticleEmitter):Emit(if motor then 16 else 9)
	end

	-- Y LA HUELLA EN EL SUELO, que es lo que de verdad dice "aqui he derrapado": el
	-- humo se lo lleva el aire en medio segundo y la marca se queda mirandote.
	--
	-- Va PERPENDICULAR al rumbo y no a lo largo: una rueda que patina deja la raya
	-- cruzada respecto a donde iba, y ese detalle es la diferencia entre que parezca
	-- un frenazo y que parezca una alfombra.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	local golpe = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	if golpe == nil then
		return
	end
	local marca = Instance.new("Part")
	marca.Name = "Derrape"
	marca.Size = Vector3.new(if motor then 5 else 3, 0.08, 1.1)
	marca.CFrame =
		CFrame.lookAt(golpe.Position + Vector3.new(0, 0.06, 0), golpe.Position + rumbo + Vector3.new(0, 0.06, 0))
	marca.Anchored = true
	marca.CanCollide = false
	marca.CanQuery = false
	marca.CanTouch = false
	marca.CastShadow = false
	marca.Color = Color3.fromRGB(38, 36, 36)
	marca.Material = Enum.Material.SmoothPlastic
	marca.Transparency = 0.35
	marca.Parent = workspace
	game:GetService("Debris"):AddItem(marca, MARCA_SEGUNDOS)
end

-- LA BOLA DEL ESCUDO, que se enciende y se apaga sola con el efecto.
--
-- La pidio JJ por su nombre: *"que salga una bola de escudo tipo Sonic"*, y no es
-- una referencia cualquiera -- esa burbuja funciona porque dice DOS cosas a la vez
-- sin una palabra: que estas protegido, y cuanto te queda (parpadea al acabarse).
--
-- Va en el SERVIDOR y la ve todo el mundo, igual que la carga a la espalda y por lo
-- mismo: en un juego donde puedes robar, saber si el otro esta protegido es la
-- informacion que decide si te merece la pena ir a por el. Una burbuja que solo
-- viera su dueno seria justo la mitad inutil del efecto.
--
-- Se crea UNA vez por personaje y despues solo se le mueve la transparencia. Crear
-- y destruir una esfera por activacion es la fuga lenta que este fichero ya pago
-- con el polvo -- 1.658 emisores colgando de un jugador tras diez minutos.
local function burbuja(root: BasePart, quedan: number)
	local bola = root:FindFirstChild("BurbujaEscudo") :: BasePart?
	if bola == nil then
		if quedan <= 0 then
			return -- no se monta nada hasta que haga falta
		end
		local nueva = Instance.new("Part")
		nueva.Name = "BurbujaEscudo"
		nueva.Shape = Enum.PartType.Ball
		nueva.Size = Vector3.new(8.5, 8.5, 8.5)
		nueva.Color = Color3.fromRGB(150, 240, 150)
		nueva.Material = Enum.Material.ForceField
		nueva.CanCollide = false
		nueva.CanQuery = false
		nueva.CanTouch = false
		nueva.Massless = true
		nueva.CastShadow = false
		nueva.Parent = root.Parent
		local pegada = Instance.new("WeldConstraint")
		pegada.Part0 = root
		pegada.Part1 = nueva
		pegada.Parent = nueva
		nueva.CFrame = root.CFrame
		bola = nueva
	end

	local b = bola :: BasePart
	if quedan <= 0 then
		b.Transparency = 1
		return
	end
	-- LOS ULTIMOS TRES SEGUNDOS PARPADEA. Es la mitad del trabajo de la burbuja: un
	-- escudo que se apaga de golpe te deja pensando que sigue puesto justo cuando ya
	-- no lo esta, y esa es la unica forma de perder la carga sin haber decidido nada.
	local base = 0.55
	if quedan <= 3 then
		b.Transparency = base + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 14))
	else
		b.Transparency = base
	end
end

local function efectos(root: BasePart, velocidad: number, quieto: boolean, racha: number, motor: boolean)
	-- OJO AL SITIO DONDE SE BUSCA. El emisor cuelga del ANCLA, no de root, asi que
	-- `root:FindFirstChild("PolvoPies")` devolvia nil SIEMPRE y este bloque creaba un
	-- ancla y un emisor nuevos en cada tick. Medido en una partida real: 1.658 de
	-- cada uno colgando del jugador. No daba error, no se veia y no rompia nada --
	-- solo iba pesando mas cuanto mas jugabas, que es la averia que no se busca.
	local ancla = root:FindFirstChild("AnclaPies") :: Attachment?
	local polvo = ancla and ancla:FindFirstChild("PolvoPies") :: ParticleEmitter?
	if polvo == nil then
		local pies = ancla or Instance.new("Attachment")
		pies.Name = "AnclaPies"
		pies.Position = Vector3.new(0, -2.6, 0)
		pies.Parent = root

		polvo = Instance.new("ParticleEmitter")
		local p = polvo :: ParticleEmitter
		p.Name = "PolvoPies"
		p.Texture = "rbxasset://textures/particles/smoke_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(150, 140, 122))
		p.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1.7),
		})
		p.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		p.Lifetime = NumberRange.new(0.32, 0.55)
		p.Speed = NumberRange.new(0.5, 1.6)
		p.SpreadAngle = Vector2.new(24, 24)
		p.Rate = 0
		p.LightEmission = 0.1
		p.Parent = pies
	end

	local estela = root:FindFirstChild("EstelaRacha") :: Trail?
	if estela == nil then
		local a0 = Instance.new("Attachment")
		a0.Name = "EstelaA"
		a0.Position = Vector3.new(-0.7, 0.4, 0.4)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "EstelaB"
		a1.Position = Vector3.new(0.7, -0.7, 0.4)
		a1.Parent = root

		estela = Instance.new("Trail")
		local t = estela :: Trail
		t.Name = "EstelaRacha"
		t.Attachment0 = a0
		t.Attachment1 = a1
		-- Del color de los contactos: la estela es LO QUE HAS RECOGIDO convertido en
		-- velocidad, así que tiene que leerse como lo mismo.
		t.Color = ColorSequence.new(Color3.fromRGB(255, 214, 130))
		t.Lifetime = 0.32
		t.MinLength = 0.4
		t.LightEmission = 0.6
		t.Enabled = false
		t.Parent = root
	end

	-- EL POLVO SE CALLA PARADO, igual que el motor y por el mismo motivo: una nube
	-- permanente alrededor de alguien quieto es ruido visual, no información.
	local emisor = polvo :: ParticleEmitter
	if quieto then
		emisor.Rate = 0
	else
		-- Escala con lo rápido que vas de verdad, no con lo que podrías ir. Y algo
		-- más si llevas motor: una moto levanta más que unas zapatillas.
		local intensidad = math.clamp((velocidad - 8) / 18, 0, 1)
		emisor.Rate = intensidad * (if motor then 26 else 14)
	end

	-- LA ESTELA SÓLO CON RACHA DE VERDAD. A partir de la mitad del tope: si saliera
	-- con la primera píldora estaría encendida todo el viaje y dejaría de decir
	-- nada. Encendida significa "éste va lanzado", y tiene que costar.
	local t = estela :: Trail
	local encendida = not quieto and racha >= Config.RACHA_MAXIMA / 2
	t.Enabled = encendida
	if encendida then
		-- Y crece con la racha, para que el tope se vea: entre media y una vez el
		-- ancho, según lo cerca que estés del máximo.
		local cuanto = math.clamp(racha / Config.RACHA_MAXIMA, 0, 1)
		t.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45 + 0.55 * cuanto),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
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

		-- Y EL SALTO, que es el otro recogible. Se escribe AQUI y no al nacer el
		-- personaje --que es donde vive el salto base-- porque ahora deja de ser una
		-- constante: sube al coger una flecha y baja sola al caducar.
		--
		-- Se compara contra el reloj en vez de descontar un contador, asi que el
		-- impulso se apaga aunque este bucle se salte una vuelta. `UseJumpPower` se
		-- vuelve a poner a false por si el personaje es nuevo: escribir JumpHeight
		-- con la medida vieja activa no hace nada y no avisa nadie.
		local conImpulso = (estado.saltoHasta or 0) > os.clock()
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = if conImpulso
			then Config.SALTO_ALTURA * Config.SALTO_IMPULSO_FACTOR
			else Config.SALTO_ALTURA

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

		-- Y LO QUE SE VE, con los mismos números que acaban de decidir lo que se
		-- oye. Van juntos porque son la misma pregunta --¿cómo de rápido va éste?--
		-- y separarlos garantizaría que un día el motor diga una cosa y el polvo
		-- otra. Se calcula el estar quieto aquí porque arriba vive dentro del `if`
		-- del sonido, que sólo existe cuando hay vehículo con ruido.
		-- Con la velocidad MEDIDA, no la teórica: el polvo responde a lo que está
		-- pasando, no a lo que el vehículo podría dar si el jugador acelerase.
		local real, giro = velocidadReal(player, root)
		local conMotor = def ~= nil and def.motor == true

		-- LA BURBUJA DEL ESCUDO, con el mismo reloj que decide si te roban: si se
		-- dibujara con su propio contador acabaria diciendo una cosa mientras el
		-- servidor hace otra, y el jugador aprenderia a no fiarse de ella.
		local restaEscudo = (estado.escudoHasta or 0) - os.clock()
		local okBurbuja, errBurbuja = pcall(burbuja, root, restaEscudo)
		if not okBurbuja then
			warn("[Contrabando] fallo pintando el escudo: " .. tostring(errBurbuja))
		end
		efectos(root, real, real < 2, Contacts.racha(estado.recogidos or 0), conMotor)

		-- EL DERRAPE, con los mismos numeros que acaban de decidir el polvo. Va
		-- despues y no dentro de `efectos` porque no es un estado continuo sino un
		-- INSTANTE: el polvo se enciende y se apaga, esto ocurre una vez y se acaba.
		if giro >= DERRAPE_GIRO and real >= DERRAPE_VELOCIDAD then
			local rumbo = ultimoRumbo[player]
			if rumbo ~= nil then
				local ok, err = pcall(derrapar, root, rumbo, conMotor)
				if not ok then
					warn("[Contrabando] fallo derrapando: " .. tostring(err))
				end
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
