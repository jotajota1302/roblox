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

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local TOUCH_MIN = 48

local Hud = {}
local dineroLabel: TextLabel
local cargaLabel: TextLabel
local almacenLabel: TextLabel
local avisoLabel: TextLabel
local comprarBoton: TextButton
-- Los botones de acción, para poder apagarlos en bloque mientras hay una
-- pantalla modal delante. Medido en un Galaxy A06 (705x338): el selector de ruta
-- se superponía a los tres y asomaban por detrás, ilegibles y pulsables. Ocultar,
-- no sólo tapar: un botón invisible que sigue respondiendo es peor que uno visible.
local accionBotones: { TextButton } = {}
local modal = false

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

	-- La columna de acciones: derecha, y con los tres repartidos entre 0,26 y 0,58
	-- de la altura. No son cifras estéticas. MEDIDO en un Galaxy A06 (705x338): con
	-- el de comprar en 0,68 su borde inferior caía en y=196 y el botón de SALTO de
	-- Roblox empieza en y=190 -- seis píxeles de solape con un control del sistema
	-- que no podemos mover y que el jugador va a pulsar sin mirar. La regla del
	-- proyecto ("nada en las esquinas inferiores: son del joystick y del salto") no
	-- se cumple sola: hay que comprobarla con las posiciones reales.
	local entregar = Instance.new("TextButton")
	entregar.Name = "Entregar"
	entregar.AnchorPoint = Vector2.new(1, 0.5)
	entregar.Position = UDim2.fromScale(0.97, 0.42)
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
	recoger.Position = UDim2.fromScale(0.97, 0.26)
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

	-- Botón de compra. Empieza oculto y sólo aparece cuando de verdad hay algo que
	-- comprar: un botón permanentemente deshabilitado ocupa sitio en una pantalla
	-- de móvil y no informa de nada.
	comprarBoton = Instance.new("TextButton")
	comprarBoton.Name = "Comprar"
	comprarBoton.AnchorPoint = Vector2.new(1, 0.5)
	comprarBoton.Position = UDim2.fromScale(0.97, 0.58)
	comprarBoton.Size = UDim2.fromScale(0.22, 0.12)
	comprarBoton.BackgroundColor3 = Color3.fromRGB(70, 90, 130)
	comprarBoton.TextColor3 = Color3.fromRGB(255, 255, 255)
	comprarBoton.TextScaled = true
	comprarBoton.Font = Enum.Font.GothamBold
	comprarBoton.Text = ""
	comprarBoton.Visible = false
	comprarBoton.Parent = gui

	local comprarSize = Instance.new("UISizeConstraint")
	comprarSize.MinSize = Vector2.new(TOUCH_MIN * 2.5, TOUCH_MIN)
	comprarSize.MaxSize = Vector2.new(240, 90)
	comprarSize.Parent = comprarBoton

	comprarBoton.Activated:Connect(function()
		-- El id viaja como atributo del propio botón: es el servidor quien decidió
		-- qué se ofrece (mejorasPara), y el cliente sólo devuelve lo que le dieron.
		local id = comprarBoton:GetAttribute("vehiculo")
		if typeof(id) == "string" then
			Remotes.event(Remotes.COMPRAR):FireServer(id)
		end
	end)

	accionBotones = { entregar, recoger }

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

export type EstadoHud = {
	dinero: number,
	cajas: { any },
	almacenCajas: number?,
	capacidad: number?,
	vehiculoNombre: string?,
	mejoras: { { id: string, nombre: string, coste: number, capacidad: number } }?,
}

function Hud.update(estado: EstadoHud)
	if not dineroLabel then
		return
	end
	dineroLabel.Text = string.format("Dinero: %d", estado.dinero)
	-- Carga sobre capacidad, no un número suelto: "2 cajas" no dice si te queda
	-- sitio, y de ese hueco depende toda la decisión de qué te llevas.
	local capacidad = estado.capacidad or Config.CAPACIDAD_A_PIE
	cargaLabel.Text = string.format("Carga: %d/%d  %s", #estado.cajas, capacidad, estado.vehiculoNombre or "")
	almacenLabel.Text = string.format("Almacen: %d/%d", estado.almacenCajas or 0, Config.ALMACEN_TOPE)

	if not comprarBoton then
		return
	end
	local mejoras = estado.mejoras
	local siguiente = mejoras and mejoras[1]
	if siguiente and not modal then
		comprarBoton:SetAttribute("vehiculo", siguiente.id)
		comprarBoton.Text = string.format("%s\n%d", siguiente.nombre, siguiente.coste)
		comprarBoton.Visible = true
		-- Apagado en gris cuando no llega el dinero: enseñar el precio que aún no
		-- puedes pagar es la mitad del motivo para hacer otro viaje. Ocultarlo
		-- dejaría el dinero sin destino visible, que es el problema que el taller
		-- viene a resolver.
		local alcanza = estado.dinero >= siguiente.coste
		comprarBoton.BackgroundColor3 = if alcanza then Color3.fromRGB(70, 90, 130) else Color3.fromRGB(60, 60, 66)
		comprarBoton.TextTransparency = if alcanza then 0 else 0.35
	else
		comprarBoton.Visible = false
	end
end

-- Llamada por Main.client cuando aparece o desaparece el selector de ruta. El
-- botón de comprar no se reenciende aquí: tiene además su propia condición (que
-- quede algo que comprar), y de eso decide el siguiente Hud.update.
function Hud.setModal(activo: boolean)
	modal = activo
	for _, boton in accionBotones do
		boton.Visible = not activo
	end
	if activo and comprarBoton then
		comprarBoton.Visible = false
	end
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
