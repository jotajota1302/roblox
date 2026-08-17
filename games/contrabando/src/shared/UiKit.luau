--!strict
--[[
	UiKit.luau — los cuatro adornos que separan una interfaz de una caja de color.

	Existe porque el HUD se escribió cuando TODO el juego eran cubos de colores, y
	ahí unos rectángulos planos eran coherentes. Con los modelos 3D puestos dejaron
	de serlo: el mundo pasó a tener textura y volumen y la interfaz se quedó
	pareciendo un depurador encima.

	Nada de aquí cambia una regla ni una posición. Sólo bordes, esquinas, degradado
	y sombra — y todo se aplica DESPUÉS de que el elemento esté colocado, para que
	las medidas que se verificaron en las tres pantallas sigan siendo las mismas.
]]

local UiKit = {}

-- Negro y blanco puros no existen en la naturaleza y en pantalla se ven como un
-- error. Estos son los tonos base de toda la interfaz.
UiKit.TINTA = Color3.fromRGB(18, 19, 24)
UiKit.PAPEL = Color3.fromRGB(238, 236, 232)
UiKit.APAGADO = Color3.fromRGB(150, 150, 158)

function UiKit.redondear(obj: GuiObject, radio: number): UICorner
	local esquina = Instance.new("UICorner")
	esquina.CornerRadius = UDim.new(0, radio)
	esquina.Parent = obj
	return esquina
end

function UiKit.borde(obj: GuiObject, color: Color3, grosor: number, transparencia: number?): UIStroke
	local trazo = Instance.new("UIStroke")
	trazo.Color = color
	trazo.Thickness = grosor
	trazo.Transparency = transparencia or 0
	-- Border, no Contextual: sin esto el trazo se dibuja a caballo del borde y en
	-- un botón pequeño se come el texto.
	trazo.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trazo.Parent = obj
	return trazo
end

-- Degradado vertical claro-arriba / oscuro-abajo. Es el truco más barato que
-- existe para que un rectángulo parezca un objeto: sugiere una luz cenital, que
-- es de donde viene la del mundo.
--
-- CUIDADO: un UIGradient MULTIPLICA el color del elemento, así que sólo puede
-- oscurecer -- arriba se deja en blanco (factor 1, sin tocar) y se oscurece hacia
-- abajo. El intento evidente, aclarar arriba con Color3.new(1.14, 1.14, 1.14),
-- REVIENTA: los componentes de un Color3 tienen que estar en [0,1]. Y reventó
-- caro: la excepción mató Hud.build() entero justo después del primer botón, así
-- que el juego arrancó con medio HUD, sin selector de ruta y sin ningún error a
-- la vista -- sólo una pantalla a la que le faltaban cosas.
function UiKit.volumen(obj: GuiObject, fuerza: number?): UIGradient
	local f = math.clamp(fuerza or 0.18, 0, 0.9)
	local degradado = Instance.new("UIGradient")
	degradado.Rotation = 90
	degradado.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1 - f, 1 - f, 1 - f)),
	})
	degradado.Parent = obj
	return degradado
end

-- Sombra: un hermano detrás, desplazado. No se puede usar un hijo porque quedaría
-- por delante, y no hay sombras nativas en la interfaz de Roblox.
--
-- NO SIRVE dentro de un contenedor con UIListLayout o UIGridLayout, y por eso
-- esta función se niega a crearla ahí: el layout reparte el espacio entre TODOS
-- sus hijos, y una sombra es un hijo más. Medido: los tres botones de ruta con
-- sombra pasaron a ser seis elementos en la fila, el reparto se descuadró y la
-- tarjeta roja acabó fuera de la pantalla. En una pantalla donde se elige entre
-- tres opciones, una de ellas dejó de existir.
function UiKit.sombra(obj: GuiObject, radio: number): Frame?
	local padre = obj.Parent
	if padre and (padre:FindFirstChildOfClass("UIListLayout") or padre:FindFirstChildOfClass("UIGridLayout")) then
		return nil
	end
	local s = Instance.new("Frame")
	s.Name = obj.Name .. "Sombra"
	s.AnchorPoint = obj.AnchorPoint
	s.Position = obj.Position + UDim2.fromOffset(0, 3)
	s.Size = obj.Size
	s.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	s.BackgroundTransparency = 0.72
	s.BorderSizePixel = 0
	-- Justo por detrás del elemento al que acompaña, sea cual sea su capa.
	s.ZIndex = obj.ZIndex - 1
	s.Parent = obj.Parent
	UiKit.redondear(s, radio)

	-- La sombra sigue al elemento: los botones se reposicionan y se redimensionan
	-- por restricciones (UISizeConstraint), no sólo al crearse, y una sombra que
	-- se quedara en el sitio original sería más visible que no tener ninguna.
	obj:GetPropertyChangedSignal("Size"):Connect(function()
		s.Size = obj.Size
	end)
	obj:GetPropertyChangedSignal("Position"):Connect(function()
		s.Position = obj.Position + UDim2.fromOffset(0, 3)
	end)
	obj:GetPropertyChangedSignal("Visible"):Connect(function()
		s.Visible = obj.Visible
	end)
	s.Visible = obj.Visible

	return s
end

function UiKit.margen(obj: GuiObject, px: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = obj
	return p
end

-- Una versión más oscura del mismo color, para bordes y sombras que tienen que
-- pertenecer a la pieza en vez de ser una línea negra pegada encima.
function UiKit.oscurecer(color: Color3, cuanto: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s + cuanto * 0.35), math.max(0, v - cuanto))
end

-- Separador de millares. "12500" obliga a contar dígitos; "12.500" se lee de un
-- golpe, y el dinero es el número que el jugador mira más veces por partida.
function UiKit.millares(n: number): string
	local texto = string.format("%d", math.floor(n))
	local signo = ""
	if string.sub(texto, 1, 1) == "-" then
		signo = "-"
		texto = string.sub(texto, 2)
	end
	local partes = {}
	while #texto > 3 do
		table.insert(partes, 1, string.sub(texto, -3))
		texto = string.sub(texto, 1, -4)
	end
	table.insert(partes, 1, texto)
	return signo .. table.concat(partes, ".")
end

return UiKit
