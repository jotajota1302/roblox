--!strict
--[[
	RoutePicker.luau — los tres destinos con su precio, al salir del almacén.

	Es la pantalla donde se toma la decisión central del juego, así que enseña el
	multiplicador y la distancia SIN adornos: la elección tiene que poder hacerse
	de un vistazo, no leyendo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))

local RoutePicker = {}
local gui: ScreenGui? = nil

function RoutePicker.build(alElegir: (string) -> ())
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "SelectorRuta"
	pantalla.ResetOnSpawn = false
	pantalla.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	pantalla.Enabled = false
	pantalla.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local fila = Instance.new("Frame")
	fila.AnchorPoint = Vector2.new(0.5, 0.5)
	fila.Position = UDim2.fromScale(0.5, 0.5)
	fila.Size = UDim2.fromScale(0.9, 0.34)
	fila.BackgroundTransparency = 1
	fila.Parent = pantalla

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = fila

	for _, ruta in Routes.todas() do
		local boton = Instance.new("TextButton")
		boton.Name = ruta.id
		boton.Size = UDim2.fromScale(0.3, 1)
		boton.BackgroundColor3 = Palette.ruta(ruta.id)
		boton.TextColor3 = Color3.fromRGB(255, 255, 255)
		boton.TextScaled = true
		boton.Font = Enum.Font.GothamBold
		boton.Text = string.format("%s\nx%d\n%d m", string.upper(ruta.id), ruta.multiplicador, ruta.distancia)
		boton.Parent = fila

		local size = Instance.new("UISizeConstraint")
		size.MinSize = Vector2.new(90, 96)
		size.Parent = boton

		boton.Activated:Connect(function()
			alElegir(ruta.id)
			RoutePicker.ocultar()
		end)
	end

	gui = pantalla
end

function RoutePicker.mostrar()
	if gui then
		gui.Enabled = true
	end
end

function RoutePicker.ocultar()
	if gui then
		gui.Enabled = false
	end
end

return RoutePicker
