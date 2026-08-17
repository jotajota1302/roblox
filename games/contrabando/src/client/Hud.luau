--!strict
--[[
	Hud.luau — interfaz mínima, móvil primero.

	Reglas que no son opcionales (aprendidas midiendo el piloto en un Galaxy A06 de
	705x338 px, donde 12 elementos quedaban fuera de sitio y el botón de cerrar la
	tienda ni siquiera se veía):

	  · tamaños en Scale con UISizeConstraint, nunca en píxeles sueltos
	  · botones de 48 px mínimo
	  · nada en las esquinas inferiores: son del joystick y del botón de salto
	  · sin emojis en TextLabel (salen como cuadrados)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local TOUCH_MIN = 48

local Hud = {}
local dineroLabel: TextLabel
local cargaLabel: TextLabel
local almacenLabel: TextLabel
local avisoLabel: TextLabel

function Hud.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContrabandoHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromScale(0.02, 0.03)
	panel.Size = UDim2.fromScale(0.3, 0.19)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(140, 78)
	panelSize.MaxSize = Vector2.new(280, 110)
	panelSize.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	local function linea(nombre: string, orden: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = nombre
		label.LayoutOrder = orden
		label.Size = UDim2.fromScale(1, 0.33)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(235, 235, 240)
		label.TextScaled = true
		label.Font = Enum.Font.GothamMedium
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = ""
		label.Parent = panel
		return label
	end

	dineroLabel = linea("Dinero", 1)
	cargaLabel = linea("Carga", 2)
	almacenLabel = linea("Almacen", 3)

	-- Botón de entregar: centro-derecha, lejos del joystick y del salto.
	local entregar = Instance.new("TextButton")
	entregar.Name = "Entregar"
	entregar.AnchorPoint = Vector2.new(1, 0.5)
	entregar.Position = UDim2.fromScale(0.97, 0.5)
	entregar.Size = UDim2.fromScale(0.18, 0.12)
	entregar.BackgroundColor3 = Color3.fromRGB(60, 140, 70)
	entregar.TextColor3 = Color3.fromRGB(255, 255, 255)
	entregar.TextScaled = true
	entregar.Font = Enum.Font.GothamBold
	entregar.Text = "Entregar"
	entregar.Parent = gui

	local botonSize = Instance.new("UISizeConstraint")
	botonSize.MinSize = Vector2.new(TOUCH_MIN * 2, TOUCH_MIN)
	botonSize.MaxSize = Vector2.new(200, 90)
	botonSize.Parent = entregar

	entregar.Activated:Connect(function()
		Remotes.event(Remotes.ENTREGAR):FireServer()
	end)

	local recoger = Instance.new("TextButton")
	recoger.Name = "Recoger"
	recoger.AnchorPoint = Vector2.new(1, 0.5)
	recoger.Position = UDim2.fromScale(0.97, 0.32)
	recoger.Size = UDim2.fromScale(0.18, 0.12)
	recoger.BackgroundColor3 = Color3.fromRGB(120, 100, 60)
	recoger.TextColor3 = Color3.fromRGB(255, 255, 255)
	recoger.TextScaled = true
	recoger.Font = Enum.Font.GothamBold
	recoger.Text = "Recoger"
	recoger.Parent = gui

	local recogerSize = Instance.new("UISizeConstraint")
	recogerSize.MinSize = Vector2.new(TOUCH_MIN * 2, TOUCH_MIN)
	recogerSize.MaxSize = Vector2.new(200, 90)
	recogerSize.Parent = recoger

	recoger.Activated:Connect(function()
		Remotes.event(Remotes.RECLAMAR):FireServer()
	end)

	avisoLabel = Instance.new("TextLabel")
	avisoLabel.Name = "Aviso"
	avisoLabel.AnchorPoint = Vector2.new(0.5, 0)
	avisoLabel.Position = UDim2.fromScale(0.5, 0.12)
	avisoLabel.Size = UDim2.fromScale(0.6, 0.09)
	avisoLabel.BackgroundTransparency = 1
	avisoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	avisoLabel.TextScaled = true
	avisoLabel.Font = Enum.Font.GothamBold
	avisoLabel.Text = ""
	avisoLabel.Parent = gui
end

function Hud.update(estado: { dinero: number, cajas: { any }, almacenCajas: number? })
	if not dineroLabel then
		return
	end
	dineroLabel.Text = string.format("Dinero: %d", estado.dinero)
	cargaLabel.Text = string.format("Carga: %d cajas", #estado.cajas)
	almacenLabel.Text = string.format("Almacen: %d/%d", estado.almacenCajas or 0, 10)
end

local avisoId = 0

function Hud.aviso(texto: string, color: Color3)
	if not avisoLabel then
		return
	end
	avisoId += 1
	local id = avisoId
	avisoLabel.Text = texto
	avisoLabel.TextColor3 = color
	task.delay(3, function()
		-- Sólo se borra si nadie ha escrito otro aviso mientras tanto.
		if avisoId == id then
			avisoLabel.Text = ""
		end
	end)
end

return Hud
