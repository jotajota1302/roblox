--!strict
--[[
	Compass.luau — hacia dónde vas y cuánto queda.

	EXISTE POR UN PROBLEMA QUE SÓLO APARECIÓ AL MUDARNOS A LA CIUDAD. En la recta
	de antes bastaba con mirar al frente: el destino estaba literalmente delante y
	la baliza se veía desde el primer paso. En una ciudad de 1.500 studs con
	manzanas de edificios, la baliza queda tapada la mayor parte del tiempo y el
	jugador no sabe si va bien -- "en un mundo tan grande no se ve nada" (JJ). Eso
	no es exploración: es andar sin saber, que es la forma más rápida de dejar una
	partida.

	La flecha gira respecto a LA CÁMARA, no respecto al norte. Una brújula de norte
	obliga a traducir mentalmente dos veces (dónde miro yo, dónde está el norte,
	dónde queda entonces el destino); una flecha relativa a la cámara se lee sin
	pensar: apunta arriba, sigue recto; apunta a la izquierda, gira a la izquierda.

	Va ARRIBA Y CENTRADA, que es la única franja de la pantalla que este juego
	tiene libre: la izquierda es el panel de estado, la derecha son los botones de
	acción, y las dos esquinas de abajo son del joystick y del salto de Roblox.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bearing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Bearing"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))
local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

local Compass = {}
local marco: Frame? = nil
local aguja: TextLabel? = nil
local titulo: TextLabel? = nil
local distancia: TextLabel? = nil

-- Qué se está persiguiendo ahora mismo. Lo pone Main.client cuando cambia el
-- estado: con ruta elegida, el destino; sin ella, el almacén, porque volver a por
-- más es la otra mitad del bucle y también hay que saber por dónde se vuelve.
local objetivo: Vector3? = nil
local etiqueta = ""
local tono = UiKit.PAPEL

function Compass.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Brujula"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.03)
	panel.Size = UDim2.fromScale(0.26, 0.11)
	panel.BackgroundColor3 = UiKit.TINTA
	panel.BackgroundTransparency = 0.22
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	UiKit.redondear(panel, 10)
	UiKit.borde(panel, Color3.fromRGB(90, 88, 96), 1.5, 0.35)

	local tamano = Instance.new("UISizeConstraint")
	tamano.MinSize = Vector2.new(150, 46)
	tamano.MaxSize = Vector2.new(280, 74)
	tamano.Parent = panel

	-- La aguja es un carácter de texto y no una imagen a propósito: una imagen
	-- necesita un asset subido, y un asset no carga con el place sin publicar --
	-- que es justo la trampa que ya nos dejó sin avatar y sin decorado. Un
	-- triángulo de texto se dibuja siempre.
	local punta = Instance.new("TextLabel")
	punta.Name = "Aguja"
	punta.AnchorPoint = Vector2.new(0.5, 0.5)
	punta.Position = UDim2.fromScale(0.13, 0.5)
	punta.Size = UDim2.fromScale(0.22, 0.8)
	punta.BackgroundTransparency = 1
	punta.TextColor3 = tono
	punta.TextScaled = true
	punta.Font = Enum.Font.GothamBlack
	punta.Text = "^"
	punta.Parent = panel
	aguja = punta

	local nombre = Instance.new("TextLabel")
	nombre.Name = "Objetivo"
	nombre.Position = UDim2.fromScale(0.28, 0.08)
	nombre.Size = UDim2.fromScale(0.68, 0.5)
	nombre.BackgroundTransparency = 1
	nombre.TextColor3 = tono
	nombre.TextScaled = true
	nombre.Font = Enum.Font.GothamBold
	nombre.TextXAlignment = Enum.TextXAlignment.Left
	nombre.Text = ""
	nombre.Parent = panel
	titulo = nombre

	local metros = Instance.new("TextLabel")
	metros.Name = "Distancia"
	metros.Position = UDim2.fromScale(0.28, 0.55)
	metros.Size = UDim2.fromScale(0.68, 0.38)
	metros.BackgroundTransparency = 1
	metros.TextColor3 = UiKit.APAGADO
	metros.TextScaled = true
	metros.Font = Enum.Font.GothamMedium
	metros.TextXAlignment = Enum.TextXAlignment.Left
	metros.Text = ""
	metros.Parent = panel
	distancia = metros

	marco = panel

	local avisado = false
	-- HEARTBEAT Y NO RenderStepped. Los dos van al ritmo del monitor, pero
	-- RenderStepped SÓLO corre mientras el cliente dibuja: con la ventana en
	-- segundo plano se para en seco, y con ella la brújula entera -- se queda
	-- apagada, sin error y sin girar, exactamente igual que si no hubiera destino.
	-- Medido en Studio: cero llamadas por segundo con el cliente sin foco. Es una
	-- pieza de información, no una animación; que dependa del foco de la ventana
	-- sólo puede dar disgustos.
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(Compass.refrescar)
		if not ok then
			if panel then
				panel.Visible = false
			end
			-- Una sola vez: esto corre sesenta veces por segundo. Pero que se oiga
			-- ALGUNA: apagar la brújula en silencio deja el mismo aspecto que "no hay
			-- destino", y esa confusión ya costó una tarde de diagnóstico.
			if not avisado then
				avisado = true
				warn("[Contrabando] la brujula fallo: " .. tostring(err))
			end
		end
	end)
end

function Compass.apuntar(destino: Vector3?, nombre: string, color: Color3?)
	objetivo = destino
	etiqueta = nombre
	tono = color or UiKit.PAPEL
end

function Compass.refrescar()
	local panel = marco
	if not panel then
		return
	end
	local destino = objetivo
	if not destino then
		panel.Visible = false
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camara = workspace.CurrentCamera
	if not root or not camara then
		panel.Visible = false
		return
	end

	panel.Visible = true

	-- El rótulo y el color, ANTES de mirar la distancia. Si se dejan para después,
	-- plantarse encima del objetivo (que es lo que pasa al llegar al almacén) sale
	-- por el return de abajo con la etiqueta del destino ANTERIOR puesta: la
	-- brújula se queda diciendo "de vuelta al almacén" cuando ya estás en él.
	if titulo then
		titulo.Text = etiqueta
		titulo.TextColor3 = tono
	end
	if aguja then
		aguja.TextColor3 = tono
	end

	local haciaAlla = destino - root.Position
	local plano = Vector3.new(haciaAlla.X, 0, haciaAlla.Z)
	if plano.Magnitude < 1 then
		if distancia then
			distancia.Text = Strings.get("COMPASS_HERE")
		end
		return
	end

	-- El rumbo lo calcula Bearing, que es puro y está probado con los cuatro casos
	-- de cabeza. NO se hace aquí a mano: la primera versión tenía el signo
	-- invertido y la brújula apuntaba al lado contrario sin dar el menor error --
	-- la flecha se movía con suavidad y parecía correcta hasta que la seguías.
	local giro = Bearing.grados(camara.CFrame.LookVector, plano)
	if giro == nil then
		-- Sin rumbo que dar (cámara en vertical): se deja la aguja como está en vez
		-- de mandarla a cero, que significaría "sigue recto".
		return
	end

	if aguja then
		aguja.Rotation = giro
	end
	if distancia then
		-- En "m" aunque sean studs: es la unidad que el jugador entiende, y el
		-- número absoluto da igual mientras sea consistente. Lo que se lee es si
		-- baja.
		distancia.Text = Strings.get("COMPASS_METERS", { metros = math.floor(plano.Magnitude) })
	end
end

return Compass
