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
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

local RoutePicker = {}
local gui: ScreenGui? = nil

function RoutePicker.build(alElegir: (string) -> ())
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "SelectorRuta"
	pantalla.ResetOnSpawn = false
	pantalla.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	pantalla.Enabled = false
	pantalla.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Velo oscuro a pantalla completa. Elegir ruta es la decisión central del
	-- juego y merece ser modal: sin el velo, en un móvil pequeño el selector se
	-- superponía a los botones del HUD y todo se leía a la vez, que es la manera
	-- más segura de que no se lea nada.
	local velo = Instance.new("Frame")
	velo.Name = "Velo"
	velo.Size = UDim2.fromScale(1, 1)
	velo.Position = UDim2.fromScale(0, 0)
	velo.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	velo.BackgroundTransparency = 0.45
	velo.BorderSizePixel = 0
	velo.ZIndex = 0
	velo.Parent = pantalla

	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	-- A 0,24 y no más abajo: el panel de estado sigue visible bajo el velo (a
	-- propósito, porque el dinero y la carga son justo lo que se mira para
	-- decidir) y ocupa la esquina superior izquierda hasta el 26 % de la altura.
	-- Un título más bajo o más ancho se le monta encima.
	titulo.AnchorPoint = Vector2.new(0.5, 1)
	titulo.Position = UDim2.fromScale(0.6, 0.24)
	titulo.Size = UDim2.fromScale(0.52, 0.11)
	titulo.BackgroundTransparency = 1
	titulo.TextColor3 = UiKit.PAPEL
	titulo.TextScaled = true
	titulo.Font = Enum.Font.GothamBold
	titulo.TextStrokeTransparency = 0.5
	titulo.Text = "Por donde sales?"
	titulo.ZIndex = 2
	titulo.Parent = pantalla

	local tituloSize = Instance.new("UISizeConstraint")
	tituloSize.MaxSize = Vector2.new(380, 46)
	tituloSize.Parent = titulo

	local fila = Instance.new("Frame")
	fila.AnchorPoint = Vector2.new(0.5, 0.5)
	fila.Position = UDim2.fromScale(0.5, 0.52)
	fila.Size = UDim2.fromScale(0.9, 0.34)
	fila.BackgroundTransparency = 1
	fila.ZIndex = 2
	fila.Parent = pantalla

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	-- Por LayoutOrder, no por nombre. Con el orden por defecto los botones salían
	-- alfabéticos -- AMBAR, ROJA, VERDE -- y el gradiente de riesgo, que es lo
	-- único que esta pantalla tiene que comunicar de un vistazo, quedaba
	-- desordenado: el x10 en el centro y el seguro a la derecha.
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = fila

	for orden, ruta in Routes.todas() do
		local boton = Instance.new("TextButton")
		boton.Name = ruta.id
		boton.LayoutOrder = orden
		boton.ZIndex = 2
		boton.Size = UDim2.fromScale(0.3, 1)
		boton.BackgroundColor3 = Palette.ruta(ruta.id)
		boton.AutoButtonColor = true
		-- El texto va en tres etiquetas hijas, no en una cadena con saltos de
		-- línea. Con TextScaled sobre tres líneas, Roblox reduce todo al tamaño
		-- que le cabe a la más larga y las tres acaban pesando lo mismo -- pero el
		-- multiplicador es la cifra por la que se elige, y tiene que dominar la
		-- tarjeta. Separarlas es la única forma de darle su propio tamaño.
		boton.Text = ""
		boton.Parent = fila
		UiKit.redondear(boton, 14)
		-- Borde grueso en vez de sombra: estas tarjetas viven dentro de un
		-- UIListLayout, que reparte el espacio entre todos sus hijos, y una sombra
		-- sería un hijo más (ver UiKit.sombra, que por eso se niega a crearla
		-- aquí). El borde da la misma separación del fondo sin tocar el reparto.
		UiKit.borde(boton, UiKit.oscurecer(Palette.ruta(ruta.id), 0.3), 4)
		UiKit.volumen(boton, 0.22)
		UiKit.margen(boton, 8)

		local pila = Instance.new("UIListLayout")
		pila.FillDirection = Enum.FillDirection.Vertical
		pila.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pila.VerticalAlignment = Enum.VerticalAlignment.Center
		pila.SortOrder = Enum.SortOrder.LayoutOrder
		pila.Parent = boton

		local function texto(
			nombre: string,
			orden: number,
			alto: number,
			contenido: string,
			fuente: Enum.Font,
			opacidad: number
		)
			local t = Instance.new("TextLabel")
			t.Name = nombre
			t.LayoutOrder = orden
			t.Size = UDim2.fromScale(1, alto)
			t.BackgroundTransparency = 1
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.TextTransparency = opacidad
			t.TextScaled = true
			t.Font = fuente
			t.TextStrokeTransparency = 0.55
			t.Text = contenido
			t.ZIndex = 2
			t.Parent = boton
			return t
		end

		texto("Nombre", 1, 0.24, string.upper(ruta.id), Enum.Font.GothamMedium, 0.15)
		texto("Multiplicador", 2, 0.5, string.format("x%d", ruta.multiplicador), Enum.Font.GothamBlack, 0)
		texto("Distancia", 3, 0.2, string.format("%d m", ruta.distancia), Enum.Font.GothamMedium, 0.35)

		local size = Instance.new("UISizeConstraint")
		size.MinSize = Vector2.new(90, 96)
		-- Y un techo: sin él, en un portátil de 1365x768 cada botón salía de
		-- 368x261 px, con el texto a un tamaño de cartel. No es sólo feo — un
		-- elemento que ocupa un tercio de la pantalla tapa el mundo justo cuando
		-- el jugador quiere mirar hacia dónde va a salir.
		size.MaxSize = Vector2.new(260, 190)
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
