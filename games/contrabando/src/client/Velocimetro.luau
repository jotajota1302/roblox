--!strict
--[[
	Velocimetro.luau — a cuánto vas y cuándo estás frenando, mientras conduces.

	POR QUÉ EXISTE. Se midió el coche por la ciudad terminada y el número que salió
	fue éste: **frenar de 56 studs/s a parado son 115 studs, y una manzana mide
	120**. O sea que a tope de gas no llegas a tiempo de frenar para la esquina del
	final de la manzana -- y esa curva se pasaba el 67 % del tiempo subido a la
	acera. Bajar el tope a 40 arregla la física; esto arregla la otra mitad, que es
	que **el jugador no tenía forma de saberlo**. No había velocímetro, no había
	freno visible, y "voy demasiado rápido para la esquina que viene" es justo la
	clase de cosa que no se aprende chocando, se aprende viéndola.

	SÓLO SALE AL VOLANTE, y se va solo al bajarse. Un velocímetro permanente sería
	ruido las nueve décimas partes de la partida, que se juegan a pie.

	NO SABE NADA DEL PROTOTIPO. Se engancha a cualquier `VehicleSeat` que publique
	el atributo `tope`, así que el día que el coche de pruebas se convierta en un
	vehículo del juego --o haya dos-- esto sigue funcionando sin tocarlo. El
	servidor publica `velocidad`, `tope` y `frenando` en el asiento; los atributos
	replican solos, que para estado continuo de UNA pieza es más barato y más simple
	que un remote por fotograma.

	ABAJO Y AL CENTRO. Las dos esquinas de abajo son de Roblox en móvil --joystick a
	la izquierda, salto a la derecha-- y arriba a la izquierda vive el HUD. El centro
	inferior es el único sitio libre, y además es donde el ojo ya está mirando cuando
	conduce.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

local Velocimetro = {}

local FONDO = Color3.fromRGB(24, 24, 28)
local TEXTO = Color3.fromRGB(238, 236, 230)
-- El color de la aguja según lo lanzado que vayas. No es decoración: es lo único
-- que dice "a esta velocidad la próxima esquina no te sale", que es toda la lección
-- que este cacharro tiene que enseñar.
local TRANQUILO = Color3.fromRGB(120, 200, 130)
local LANZADO = Color3.fromRGB(235, 190, 80)
local DEMASIADO = Color3.fromRGB(235, 90, 80)
local FRENO = Color3.fromRGB(120, 190, 240)

-- A partir de qué fracción del tope se avisa. Sale de lo medido: la esquina se toma
-- limpia entrando a unos 19 studs/s, o sea a la mitad del tope nuevo (40). Por
-- encima de tres cuartos ya no da tiempo a frenar dentro de una manzana.
local COMODO = 0.5
local LIMITE = 0.75

local marco: Frame? = nil
local numero: TextLabel? = nil
local aguja: Frame? = nil
local aviso: TextLabel? = nil
local pista: TextLabel? = nil

-- El asiento en el que va el jugador, si va en alguno que publique velocidad.
local function alVolante(): VehicleSeat?
	local pj = Players.LocalPlayer.Character
	local humanoid = pj and pj:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	local asiento = humanoid.SeatPart
	if asiento and asiento:IsA("VehicleSeat") and asiento:GetAttribute("tope") ~= nil then
		return asiento
	end
	return nil
end

function Velocimetro.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContrabandoVelocimetro"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -14)
	-- En Scale, con tope en píxeles: en una tablet no tiene que ocupar media
	-- pantalla, y en un móvil estrecho no puede encogerse hasta ser ilegible.
	panel.Size = UDim2.new(0.36, 0, 0, 62)
	panel.BackgroundColor3 = FONDO
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local limite = Instance.new("UISizeConstraint")
	limite.MinSize = Vector2.new(180, 62)
	limite.MaxSize = Vector2.new(330, 62)
	limite.Parent = panel

	UiKit.redondear(panel, 10)
	UiKit.borde(panel, Color3.fromRGB(90, 88, 96), 1.5, 0.35)

	local v = Instance.new("TextLabel")
	v.Name = "Numero"
	v.BackgroundTransparency = 1
	v.Position = UDim2.new(0, 12, 0, 4)
	v.Size = UDim2.new(1, -24, 0, 26)
	v.Font = Enum.Font.GothamBold
	v.TextSize = 22
	v.TextXAlignment = Enum.TextXAlignment.Left
	v.TextColor3 = TEXTO
	v.Text = ""
	v.Parent = panel

	local a = Instance.new("TextLabel")
	a.Name = "Aviso"
	a.BackgroundTransparency = 1
	a.Position = UDim2.new(0, 12, 0, 4)
	a.Size = UDim2.new(1, -24, 0, 26)
	a.Font = Enum.Font.GothamBold
	a.TextSize = 16
	a.TextXAlignment = Enum.TextXAlignment.Right
	a.TextColor3 = FRENO
	a.Text = ""
	a.Parent = panel

	-- LA BARRA, que es lo que de verdad se lee de un vistazo. El número exacto casi
	-- nunca importa; lo que importa es cuánto queda para el rojo.
	local canal = Instance.new("Frame")
	canal.Name = "Canal"
	canal.Position = UDim2.new(0, 12, 0, 33)
	canal.Size = UDim2.new(1, -24, 0, 7)
	canal.BackgroundColor3 = Color3.fromRGB(58, 57, 64)
	canal.BorderSizePixel = 0
	canal.Parent = panel
	UiKit.redondear(canal, 4)

	local barra = Instance.new("Frame")
	barra.Name = "Aguja"
	barra.Size = UDim2.new(0, 0, 1, 0)
	barra.BackgroundColor3 = TRANQUILO
	barra.BorderSizePixel = 0
	barra.Parent = canal
	UiKit.redondear(barra, 4)

	-- LA MARCA DEL LIMITE: donde deja de dar tiempo a frenar para la esquina. Un
	-- numero suelto no dice nada; una raya en la barra convierte "vas a 34" en "vas
	-- pasado", que es la misma informacion en algo que se lee sin pensar.
	local marca = Instance.new("Frame")
	marca.Name = "Limite"
	marca.AnchorPoint = Vector2.new(0.5, 0)
	marca.Position = UDim2.new(LIMITE, 0, 0, -2)
	marca.Size = UDim2.new(0, 2, 1, 4)
	marca.BackgroundColor3 = Color3.fromRGB(200, 198, 190)
	marca.BackgroundTransparency = 0.35
	marca.BorderSizePixel = 0
	marca.ZIndex = 3
	marca.Parent = canal

	local p = Instance.new("TextLabel")
	p.Name = "Pista"
	p.BackgroundTransparency = 1
	p.Position = UDim2.new(0, 12, 0, 42)
	p.Size = UDim2.new(1, -24, 0, 16)
	p.Font = Enum.Font.Gotham
	p.TextSize = 11
	p.TextXAlignment = Enum.TextXAlignment.Left
	p.TextColor3 = Color3.fromRGB(160, 158, 166)
	p.Text = Strings.get("DRIVE_HINT")
	p.Parent = panel

	marco, numero, aguja, aviso, pista = panel, v, barra, a, p

	-- CADA FOTOGRAMA, y no en el bucle de sincronización del juego. Ese corre unas
	-- pocas veces por segundo --le sobra para el dinero y la carga-- y una aguja que
	-- salta a tirones se lee peor que no tenerla.
	RunService.RenderStepped:Connect(function()
		Velocimetro.actualizar()
	end)
end

function Velocimetro.actualizar()
	local panel = marco
	if panel == nil then
		return
	end
	local asiento = alVolante()
	if asiento == nil then
		panel.Visible = false
		return
	end
	panel.Visible = true

	local tope = math.max(tonumber(asiento:GetAttribute("tope")) or 40, 1)
	local v = tonumber(asiento:GetAttribute("velocidad")) or 0
	local frenando = asiento:GetAttribute("frenando") == true
	local parte = math.clamp(v / tope, 0, 1)

	if numero then
		numero.Text = Strings.get("DRIVE_SPEED", { v = math.floor(v + 0.5) })
	end
	if aguja then
		aguja.Size = UDim2.new(parte, 0, 1, 0)
		aguja.BackgroundColor3 = if frenando
			then FRENO
			elseif parte >= LIMITE then DEMASIADO
			elseif parte >= COMODO then LANZADO
			else TRANQUILO
	end
	if aviso then
		aviso.Text = if frenando then Strings.get("DRIVE_BRAKING") else ""
	end
	-- La pista de los mandos sólo mientras vas despacio: es para el primer viaje, y
	-- a partir de ahí estorba justo cuando hay que mirar la barra.
	if pista then
		pista.Visible = parte < COMODO
	end
end

return Velocimetro
