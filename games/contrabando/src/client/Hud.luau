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
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

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
-- El borde del botón de comprar, guardado porque cambia de color cuando el
-- dinero alcanza: es la señal de "ya puedes" sin tener que leer la cifra.
local comprarTrazo: UIStroke? = nil

-- El acabado común de un botón: esquinas, borde del mismo color pero más oscuro
-- (un borde negro se ve pegado encima; uno del mismo tono pertenece a la pieza),
-- degradado vertical que sugiere la luz cenital del mundo, y sombra.
--
-- Va DESPUÉS del UISizeConstraint a propósito: la sombra copia posición y tamaño
-- del botón, y las restricciones cambian el tamaño real. Y ninguna de estas
-- líneas mueve nada, así que las posiciones verificadas en las tres pantallas
-- siguen siendo exactamente las mismas.
local function acabado(boton: TextButton, base: Color3): UIStroke
	UiKit.redondear(boton, 10)
	local trazo = UiKit.borde(boton, UiKit.oscurecer(base, 0.22), 2)
	UiKit.volumen(boton, 0.14)
	UiKit.sombra(boton, 10)
	boton.AutoButtonColor = true
	boton.TextStrokeTransparency = 0.6
	return trazo
end

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
	panel.BackgroundColor3 = UiKit.TINTA
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.Parent = gui
	UiKit.redondear(panel, 10)
	UiKit.borde(panel, Color3.fromRGB(90, 88, 96), 1.5, 0.35)
	UiKit.margen(panel, 8)

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(140, 78)
	panelSize.MaxSize = Vector2.new(280, 110)
	panelSize.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	-- Cada línea es etiqueta + valor, no una cadena única. Con "Dinero: 3200" todo
	-- pesa lo mismo y el ojo tiene que leerlo entero para encontrar la cifra; con
	-- la etiqueta apagada a la izquierda y el valor destacado a la derecha, el
	-- número se ve sin leer nada.
	local function linea(nombre: string, orden: number, etiqueta: string): TextLabel
		local fila = Instance.new("Frame")
		fila.Name = nombre
		fila.LayoutOrder = orden
		fila.Size = UDim2.fromScale(1, 0.33)
		fila.BackgroundTransparency = 1
		fila.Parent = panel

		local titulo = Instance.new("TextLabel")
		titulo.Name = "Etiqueta"
		titulo.Size = UDim2.fromScale(0.42, 1)
		titulo.BackgroundTransparency = 1
		titulo.TextColor3 = UiKit.APAGADO
		titulo.TextScaled = true
		titulo.Font = Enum.Font.GothamMedium
		titulo.TextXAlignment = Enum.TextXAlignment.Left
		titulo.Text = etiqueta
		titulo.Parent = fila

		local valor = Instance.new("TextLabel")
		valor.Name = "Valor"
		valor.AnchorPoint = Vector2.new(1, 0)
		valor.Position = UDim2.fromScale(1, 0)
		valor.Size = UDim2.fromScale(0.56, 1)
		valor.BackgroundTransparency = 1
		valor.TextColor3 = UiKit.PAPEL
		valor.TextScaled = true
		valor.Font = Enum.Font.GothamBold
		valor.TextXAlignment = Enum.TextXAlignment.Right
		valor.Text = ""
		valor.Parent = fila

		return valor
	end

	dineroLabel = linea("Dinero", 1, "Dinero")
	cargaLabel = linea("Carga", 2, "Carga")
	almacenLabel = linea("Almacen", 3, "Almacen")
	-- El dinero es el número que más se mira: se le da el color del oro para que
	-- destaque entre los otros dos sin necesidad de leer la etiqueta.
	dineroLabel.TextColor3 = Color3.fromRGB(238, 202, 122)

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
	acabado(entregar, entregar.BackgroundColor3)

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
	acabado(recoger, recoger.BackgroundColor3)

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
	comprarTrazo = acabado(comprarBoton, comprarBoton.BackgroundColor3)

	comprarBoton.Activated:Connect(function()
		-- El id viaja como atributo del propio botón: es el servidor quien decidió
		-- qué se ofrece (mejorasPara), y el cliente sólo devuelve lo que le dieron.
		local id = comprarBoton:GetAttribute("vehiculo")
		if typeof(id) == "string" then
			Remotes.event(Remotes.COMPRAR):FireServer(id)
		end
	end)

	accionBotones = { entregar, recoger }

	-- El aviso lleva su propio fondo. Antes era texto blanco suelto sobre el
	-- mundo, y el mundo aquí es un cielo claro y un edificio claro: justo donde
	-- aparece "te vienen detras", que es el aviso que hay que leer sin pensarlo.
	avisoLabel = Instance.new("TextLabel")
	avisoLabel.Name = "Aviso"
	-- Colocado por medición, no a ojo. En 0,12 y con 0,6 de ancho se montaba
	-- encima del panel de estado (que ocupa hasta el 26 % de la altura y el 32 %
	-- del ancho) y por la derecha rozaba el botón de Recoger. Aquí queda en tierra
	-- de nadie: por debajo del panel y a la izquierda de la columna de botones.
	avisoLabel.AnchorPoint = Vector2.new(0.5, 0)
	avisoLabel.Position = UDim2.fromScale(0.46, 0.3)
	avisoLabel.Size = UDim2.fromScale(0.5, 0.09)
	avisoLabel.BackgroundColor3 = UiKit.TINTA
	avisoLabel.BackgroundTransparency = 1 -- se enciende sólo cuando hay texto
	avisoLabel.TextColor3 = UiKit.PAPEL
	avisoLabel.TextScaled = true
	avisoLabel.Font = Enum.Font.GothamBold
	avisoLabel.TextStrokeTransparency = 0.5
	avisoLabel.Text = ""
	avisoLabel.Parent = gui
	UiKit.redondear(avisoLabel, 8)
	UiKit.margen(avisoLabel, 6)

	local avisoSize = Instance.new("UISizeConstraint")
	avisoSize.MaxSize = Vector2.new(520, 46)
	avisoSize.Parent = avisoLabel
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
	dineroLabel.Text = UiKit.millares(estado.dinero)
	-- Carga sobre capacidad, no un número suelto: "2 cajas" no dice si te queda
	-- sitio, y de ese hueco depende toda la decisión de qué te llevas.
	local capacidad = estado.capacidad or Config.CAPACIDAD_A_PIE
	cargaLabel.Text = string.format("%d/%d", #estado.cajas, capacidad)
	-- La etiqueta de esa línea es el vehículo, no la palabra "Carga": ya se
	-- entiende que "2/10" es carga, y así el jugador ve en qué va sin gastar una
	-- cuarta línea en un panel que tiene tres.
	local etiquetaCarga = cargaLabel.Parent and cargaLabel.Parent:FindFirstChild("Etiqueta") :: TextLabel?
	if etiquetaCarga then
		etiquetaCarga.Text = estado.vehiculoNombre or "Carga"
	end
	almacenLabel.Text = string.format("%d/%d", estado.almacenCajas or 0, Config.ALMACEN_TOPE)

	-- El zurrón lleno se pinta en ámbar: es la señal de "ya no te cabe más, vete",
	-- y es lo que separa un viaje aprovechado de otro a medias.
	cargaLabel.TextColor3 = if #estado.cajas >= capacidad then Color3.fromRGB(230, 180, 70) else UiKit.PAPEL
	-- Y el almacén al tope, también: a partir de ahí deja de producir y cada
	-- minuto fuera es tiempo tirado.
	almacenLabel.TextColor3 = if (estado.almacenCajas or 0) >= Config.ALMACEN_TOPE
		then Color3.fromRGB(230, 180, 70)
		else UiKit.PAPEL

	if not comprarBoton then
		return
	end
	local mejoras = estado.mejoras
	local siguiente = mejoras and mejoras[1]
	if siguiente and not modal then
		comprarBoton:SetAttribute("vehiculo", siguiente.id)
		comprarBoton.Text = string.format("%s\n%s", siguiente.nombre, UiKit.millares(siguiente.coste))
		comprarBoton.Visible = true
		-- Apagado en gris cuando no llega el dinero: enseñar el precio que aún no
		-- puedes pagar es la mitad del motivo para hacer otro viaje. Ocultarlo
		-- dejaría el dinero sin destino visible, que es el problema que el taller
		-- viene a resolver.
		local alcanza = estado.dinero >= siguiente.coste
		local base = if alcanza then Color3.fromRGB(70, 90, 130) else Color3.fromRGB(58, 58, 64)
		comprarBoton.BackgroundColor3 = base
		comprarBoton.TextTransparency = if alcanza then 0 else 0.35
		if comprarTrazo then
			-- Cuando ya alcanza, el borde se enciende en oro: la señal de "puedes
			-- comprarlo" tiene que verse de reojo, sin comparar dos cifras.
			comprarTrazo.Color = if alcanza then Color3.fromRGB(238, 202, 122) else UiKit.oscurecer(base, 0.22)
			comprarTrazo.Thickness = if alcanza then 2.5 else 2
		end
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
	-- El aviso también. Medido: su franja (y 43-74) cruza las tres tarjetas de
	-- ruta (y 60-175), así que un aviso que llegara justo al abrir el selector se
	-- leería encima de la decisión. Y no hace falta: el selector sólo aparece en
	-- la salida, dentro de la zona segura, donde no hay nada que avisar.
	if activo and avisoLabel then
		avisoLabel.Text = ""
		avisoLabel.BackgroundTransparency = 1
	end
	if avisoLabel then
		avisoLabel.Visible = not activo
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
	avisoLabel.BackgroundTransparency = 0.25
	task.delay(3, function()
		-- Sólo se borra si nadie ha escrito otro aviso mientras tanto.
		if avisoId == id then
			avisoLabel.Text = ""
			avisoLabel.BackgroundTransparency = 1
		end
	end)
end

return Hud
