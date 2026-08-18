--!strict
--[[
	Popups.luau — los números que salen del personaje al ganar algo.

	POR QUÉ EXISTE. En el juego que inspiró esta tanda, cada paso saca un "+1" de
	la cabeza del muñeco, y eso es la mitad de por qué andar por su mapa se siente
	como progresar. Aquí las mismas cifras ya se ganaban: sólo que se enteraba una
	esquina del HUD, en silencio, cambiando un número.

	NO TOCA NINGUNA REGLA. El cliente no decide nada: pinta la diferencia entre dos
	estados que le ha mandado el servidor. Si alguien manipula esto, lo único que
	consigue es mentirse a sí mismo con un número bonito.

	La animación la lleva TweenService y no un bucle nuestro. Con la ventana sin
	foco, RenderStepped da cero llamadas por segundo -- medido, y costó dos horas
	con la brújula --, así que cualquier cosa que se mueva por su cuenta es mejor
	dársela al motor.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Popups = {}

-- Cuántos pueden estar vivos a la vez. Recogiendo contactos seguidos se solapan y
-- el efecto se convierte en ruido: seis caben en pantalla, siete ya es una mancha.
local MAXIMO = 6
local DURACION = 1.2
local SUBIDA = 4

local vivos: { BillboardGui } = {}

local function raiz(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Popups.mostrar(texto: string, color: Color3, pequeno: boolean?)
	local root = raiz()
	if not root then
		return
	end

	-- El más viejo se va antes de que entre el nuevo: así el tope es un tope de
	-- verdad y no una cola que crece mientras dure la racha.
	while #vivos >= MAXIMO do
		local viejo = table.remove(vivos, 1)
		if viejo then
			viejo:Destroy()
		end
	end

	local cartel = Instance.new("BillboardGui")
	cartel.Name = "Popup"
	cartel.Size = if pequeno then UDim2.fromOffset(90, 34) else UDim2.fromOffset(150, 54)
	cartel.AlwaysOnTop = true
	-- Sale ligeramente descolocado a un lado y otro para que dos seguidos no se
	-- pisen exactamente. No es aleatorio de verdad: alterna, que basta y no
	-- depende de una semilla.
	local lado = if #vivos % 2 == 0 then 1.6 else -1.6
	cartel.StudsOffsetWorldSpace = Vector3.new(lado, 2.6, 0)
	cartel.Adornee = root
	cartel.Parent = root

	local texto2 = Instance.new("TextLabel")
	texto2.Size = UDim2.fromScale(1, 1)
	texto2.BackgroundTransparency = 1
	texto2.TextColor3 = color
	texto2.TextScaled = true
	texto2.Font = Enum.Font.GothamBold
	-- Contorno oscuro: el mundo es cielo claro y edificios claros, y un número
	-- dorado sobre eso no se lee.
	texto2.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
	texto2.TextStrokeTransparency = 0.2
	texto2.Text = texto
	texto2.Parent = cartel

	table.insert(vivos, cartel)

	local info = TweenInfo.new(DURACION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(cartel, info, {
		StudsOffsetWorldSpace = Vector3.new(lado, 2.6 + SUBIDA, 0),
	}):Play()
	TweenService:Create(texto2, info, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	task.delay(DURACION + 0.05, function()
		local i = table.find(vivos, cartel)
		if i then
			table.remove(vivos, i)
		end
		cartel:Destroy()
	end)
end

-- Al reaparecer el personaje, los carteles viejos se van con él: son hijos del
-- HumanoidRootPart. Limpiar la lista evita quedarnos apuntando a instancias
-- muertas y que el tope cuente fantasmas.
function Popups.build()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		vivos = {}
	end)
end

return Popups
