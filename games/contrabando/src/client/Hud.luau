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
local Contacts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Contacts"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

local TOUCH_MIN = 48

local Hud = {}
local dineroLabel: TextLabel
local cargaLabel: TextLabel
local almacenLabel: TextLabel
local calorLabel: TextLabel
local calorFila: Frame
local metaLabel: TextLabel
local metaFila: Frame
local contactosLabel: TextLabel
local contactosFila: Frame
local avisoLabel: TextLabel
local misionLabel: TextLabel
local accionesPanel: Frame
type FilaAccion = { marco: Frame, tecla: TextLabel, accion: TextLabel }
local filasAccion: { FilaAccion } = {}
local modal = false

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
	-- La cuarta línea es CONDICIONAL: sólo se enseña con calor encima. Por eso el
	-- panel sigue dimensionado para tres y se estira con el layout en vez de
	-- reservar sitio para una línea que casi siempre estaría a cero.
	calorLabel = linea("Calor", 4, "Peligro")
	calorFila = calorLabel.Parent :: Frame
	calorFila.Visible = false

	-- La meta: lo próximo que puedes comprar y su precio. También condicional --
	-- desaparece cuando ya no queda nada que comprar, en vez de quedarse ocupando
	-- sitio con una línea vacía.
	metaLabel = linea("Meta", 5, "Meta")
	metaFila = metaLabel.Parent :: Frame
	metaFila.Visible = false

	-- LOS CONTACTOS, y la racha entre paréntesis. También condicional: hasta que se
	-- recoge el primero no hay nada que contar, y un cero fijo en un panel de tres
	-- líneas es sitio caro tirado en un móvil.
	--
	-- Van juntos porque son la misma cosa vista de dos maneras: lo que has
	-- recogido en este viaje es lo que estás corriendo de más.
	contactosLabel = linea("Contactos", 6, "Contactos")
	contactosFila = contactosLabel.Parent :: Frame
	contactosFila.Visible = false
	contactosLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	-- El dinero es el número que más se mira: se le da el color del oro para que
	-- destaque entre los otros dos sin necesidad de leer la etiqueta.
	dineroLabel.TextColor3 = Color3.fromRGB(238, 202, 122)

	-- SIN BOTONES DE ACCIÓN. Los tenía --Recoger, Entregar, Comprar-- y los tres
	-- se han ido al mundo como ProximityPrompt, que es la pieza nativa de Roblox
	-- para esto y la que cualquier jugador de la plataforma ya sabe usar.
	--
	-- El motivo lo dio JJ jugando: "lo de entregar y recoger que sean botones es un
	-- poco extraño". Lo es, y el problema de fondo es que un botón fijo en una
	-- esquina no dice ni DÓNDE ni CUÁNDO sirve: está igual de encendido en mitad de
	-- la nada que encima del destino, y con diez cajas en el muelle tampoco decía
	-- cuál de ellas ibas a coger. El aviso pegado a la cosa responde las tres
	-- preguntas sin una palabra de explicación.
	--
	-- Lo que queda en pantalla es sólo INFORMACIÓN: el panel de estado, la brújula
	-- y el minimapa. Y de paso desaparece el problema que ya costó una ronda -- la
	-- columna de botones peleándose por el sitio con el botón de salto de Roblox en
	-- la esquina inferior derecha del móvil.

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

	-- LA MISIÓN: qué toca hacer AHORA, siempre en pantalla.
	--
	-- JJ, jugando: "si le das a 'ahora no' no sé dónde tengo que ir para volver".
	-- El juego ya lo decía en dos sitios, y ninguno servía para eso: el aviso dura
	-- tres segundos y la brújula dice a DÓNDE apunta, no QUÉ hay que hacer. Entre
	-- una y otra quedaba el hueco donde vive el jugador nuevo -- el que ha cerrado
	-- una pantalla y ya no sabe cómo volver a abrirla.
	--
	-- Va pegado bajo el panel de estado, en la misma columna: es información del
	-- mismo tipo y leerla es un solo movimiento de ojos.
	misionLabel = Instance.new("TextLabel")
	misionLabel.Name = "Mision"
	misionLabel.AnchorPoint = Vector2.new(0, 0)
	misionLabel.Position = UDim2.fromScale(0.02, 0.235)
	misionLabel.Size = UDim2.fromScale(0.34, 0.055)
	misionLabel.BackgroundColor3 = UiKit.TINTA
	misionLabel.BackgroundTransparency = 0.22
	misionLabel.TextColor3 = UiKit.PAPEL
	misionLabel.TextScaled = true
	misionLabel.Font = Enum.Font.GothamBold
	misionLabel.TextXAlignment = Enum.TextXAlignment.Left
	misionLabel.TextStrokeTransparency = 0.6
	misionLabel.Text = ""
	misionLabel.Visible = false
	misionLabel.Parent = gui
	UiKit.redondear(misionLabel, 8)
	UiKit.margen(misionLabel, 8)
	UiKit.borde(misionLabel, Color3.fromRGB(90, 88, 96), 1.5, 0.35)

	-- LO QUE PUEDES HACER AHORA MISMO, debajo de la misión.
	--
	-- La primera versión de esta ayuda era un letrero en la pared del taller, y JJ
	-- la mandó aquí: "que salga no un letrero en el taller sino como una leyenda a
	-- la izquierda donde pone lo de 'elige destino'". Tiene razón -- un cartel sólo
	-- se lee si estás delante, y la pregunta "¿cómo me bajo?" se te ocurre
	-- conduciendo, a media ciudad de allí.
	--
	-- Va en gris y más pequeña que la misión: la misión dice QUÉ hacer, esto sólo
	-- recuerda CON QUÉ. Si compitieran por la atención, la misión perdería.
	-- EL PANEL DE CONTROLES, a la izquierda y debajo de la misión: es donde JJ pidió
	-- que estuvieran todos ("a la izquierda, donde ya poníamos lo de subir o
	-- bajarte, que salgan todas las acciones ahí").
	accionesPanel = Instance.new("Frame")
	accionesPanel.Name = "Acciones"
	accionesPanel.AnchorPoint = Vector2.new(0, 0)
	accionesPanel.Position = UDim2.fromScale(0.02, 0.295)
	accionesPanel.Size = UDim2.fromScale(0.34, 0.045)
	accionesPanel.BackgroundTransparency = 1
	accionesPanel.Visible = false
	accionesPanel.Parent = gui

	local lista = Instance.new("UIListLayout")
	lista.FillDirection = Enum.FillDirection.Vertical
	lista.SortOrder = Enum.SortOrder.LayoutOrder
	lista.Padding = UDim.new(0, 4)
	lista.Parent = accionesPanel

	-- CUATRO FILAS FIJAS, creadas una vez y encendidas o apagadas según haga falta.
	-- Cuatro porque nunca hay más acciones a la vez y una lista que crece empuja al
	-- resto de la interfaz; si algún día hay una quinta, se ve enseguida que falta.
	for i = 1, 4 do
		local marco = Instance.new("Frame")
		marco.Name = "Accion" .. i
		marco.Size = UDim2.new(1, 0, 0, 26)
		marco.BackgroundColor3 = UiKit.TINTA
		marco.BackgroundTransparency = 0.35
		marco.LayoutOrder = i
		marco.Visible = false
		marco.Parent = accionesPanel
		UiKit.redondear(marco, 6)

		local limite = Instance.new("UISizeConstraint")
		limite.MinSize = Vector2.new(150, 22)
		limite.MaxSize = Vector2.new(300, 30)
		limite.Parent = marco

		-- La tecla, en su propia cajita clara: es lo que el ojo busca primero, y con
		-- el mismo tamaño que el texto se pierde dentro de la frase.
		local tecla = Instance.new("TextLabel")
		tecla.Name = "Tecla"
		tecla.AnchorPoint = Vector2.new(0, 0.5)
		tecla.Position = UDim2.new(0, 5, 0.5, 0)
		tecla.Size = UDim2.new(0, 34, 0.74, 0)
		tecla.BackgroundColor3 = UiKit.PAPEL
		tecla.BackgroundTransparency = 0.12
		tecla.TextColor3 = UiKit.TINTA
		tecla.TextScaled = true
		tecla.Font = Enum.Font.GothamBold
		tecla.Text = ""
		tecla.Parent = marco
		UiKit.redondear(tecla, 5)

		local accion = Instance.new("TextLabel")
		accion.Name = "Que"
		accion.AnchorPoint = Vector2.new(0, 0.5)
		accion.Position = UDim2.new(0, 45, 0.5, 0)
		accion.Size = UDim2.new(1, -50, 0.8, 0)
		accion.BackgroundTransparency = 1
		accion.TextColor3 = UiKit.PAPEL
		accion.TextScaled = true
		accion.Font = Enum.Font.GothamMedium
		accion.TextXAlignment = Enum.TextXAlignment.Left
		accion.TextStrokeTransparency = 0.7
		accion.Text = ""
		accion.Parent = marco

		table.insert(filasAccion, { marco = marco, tecla = tecla, accion = accion })
	end

	local misionSize = Instance.new("UISizeConstraint")
	misionSize.MinSize = Vector2.new(150, 26)
	misionSize.MaxSize = Vector2.new(300, 38)
	misionSize.Parent = misionLabel
end

-- LOS CONTROLES QUE SIRVEN AHORA MISMO, uno por fila y con su botón dibujado.
--
-- Antes era una línea de texto ("V  bajarte  ·  E  entregar") y sólo hablaba de
-- teclado: *"con el mando no se puede jugar, los botones que hay que pulsar son
-- los del teclado; que salgan siempre los controles en pantalla de manera visual"*
-- (JJ). Con un mando enchufado, esa línea era instrucciones para un aparato que no
-- tienes en la mano.
--
-- Ahora cada acción llega con la etiqueta de SU mando --"V" con teclado, "Y" con
-- mando, el botón táctil en el móvil-- y quien decide cuál es Main.client, que es
-- el que sabe con qué se está jugando. Aquí sólo se dibuja.
--
-- Recibe una lista de { tecla, accion }. Vacía = no hay ninguna, y entonces el
-- panel desaparece en vez de quedarse ocupando sitio.
export type Accion = { tecla: string, accion: string }

function Hud.acciones(lista: { Accion })
	if not accionesPanel then
		return
	end
	local cuantas = #lista
	accionesPanel.Visible = cuantas > 0 and not modal
	if cuantas == 0 then
		return
	end

	-- Las filas se reutilizan en vez de recrearse: esto se llama en cada refresco
	-- del selector --varias veces por segundo-- y crear instancias a ese ritmo es
	-- basura para el recolector y parpadeo en pantalla.
	for i, fila in filasAccion do
		local dato = lista[i]
		fila.marco.Visible = dato ~= nil
		if dato ~= nil then
			fila.tecla.Text = dato.tecla
			fila.accion.Text = dato.accion
		end
	end
	accionesPanel.Size = UDim2.fromScale(0.34, 0.045 * math.min(cuantas, #filasAccion))
end

-- Lo que hay que hacer ahora, en una línea. La escribe Main.client, que es quien
-- sabe en qué punto del bucle estás.
function Hud.mision(texto: string, color: Color3?)
	if not misionLabel then
		return
	end
	misionLabel.Text = texto
	misionLabel.TextColor3 = color or UiKit.PAPEL
	-- Con el selector abierto no se enseña: la pregunta que hay delante ya es la
	-- misión, y repetirla debajo sería ruido sobre la decisión.
	misionLabel.Visible = texto ~= "" and not modal
end

export type EstadoHud = {
	dinero: number,
	cajas: { any },
	almacenCajas: number?,
	calor: number?,
	capacidad: number?,
	vehiculoNombre: string?,
	mejoras: { { id: string, nombre: string, coste: number, capacidad: number } }?,
	cajasEnVehiculo: { any }?,
	contactos: number?,
	recogidos: number?,
}

function Hud.update(estado: EstadoHud)
	if not dineroLabel then
		return
	end
	dineroLabel.Text = UiKit.millares(estado.dinero)
	-- Carga sobre capacidad, no un número suelto: "2 cajas" no dice si te queda
	-- sitio, y de ese hueco depende toda la decisión de qué te llevas.
	local capacidad = estado.capacidad or Config.CAPACIDAD_A_PIE
	-- Y lo que espera en el vehículo aparcado, entre paréntesis. Sin esto, dejar
	-- la moto con cuatro bultos dentro y ver "3/3" en el panel hace pensar que se
	-- han perdido.
	local enElVehiculo = #(estado.cajasEnVehiculo or {})
	cargaLabel.Text = if enElVehiculo > 0
		then string.format("%d/%d  (+%d)", #estado.cajas, capacidad, enElVehiculo)
		else string.format("%d/%d", #estado.cajas, capacidad)
	-- La etiqueta de esa línea es el vehículo, no la palabra "Carga": ya se
	-- entiende que "2/10" es carga, y así el jugador ve en qué va sin gastar una
	-- cuarta línea en un panel que tiene tres.
	local etiquetaCarga = cargaLabel.Parent and cargaLabel.Parent:FindFirstChild("Etiqueta") :: TextLabel?
	if etiquetaCarga then
		etiquetaCarga.Text = estado.vehiculoNombre or "Carga"
	end
	-- El tope que se enseña es el de TU nave, no el de partida: si no, quien la
	-- mejora ve "12/10" y no entiende nada.
	local topeNave = (estado.nave and estado.nave.tope) or Config.ALMACEN_TOPE
	almacenLabel.Text = string.format("%d/%d", estado.almacenCajas or 0, topeNave)

	-- El calor. La línea sólo aparece cuando hay algo que decir: en frío ocuparía
	-- un cuarto de un panel de tres líneas para poner un cero, y en un móvil ese
	-- sitio es caro. En cuanto sube, es lo primero que hay que mirar.
	local nivel = estado.calor or 0
	if calorFila then
		calorFila.Visible = nivel > 0
	end
	if calorLabel and nivel > 0 then
		calorLabel.Text = string.format("%d/%d", nivel, Config.CALOR_MAXIMO)
		-- Del ámbar al rojo según aprieta: el color dice cuánto sin leer la cifra,
		-- que es lo que hace falta cuando estás corriendo y mirando al frente.
		calorLabel.TextColor3 = if nivel >= Config.CALOR_MAXIMO
			then Color3.fromRGB(235, 75, 70)
			elseif nivel == 2 then Color3.fromRGB(235, 140, 60)
			else Color3.fromRGB(230, 190, 80)
	end

	-- Los contactos, con la racha al lado cuando la hay. "12  (+2,0)" dice a la vez
	-- lo que llevas ahorrado y lo que estás corriendo de más por haberlo recogido.
	local contactos = estado.contactos or 0
	local recogidos = estado.recogidos or 0
	if contactosFila then
		contactosFila.Visible = contactos > 0 or recogidos > 0
	end
	if contactosLabel then
		local racha = Contacts.racha(recogidos)
		contactosLabel.Text = if racha > 0 then string.format("%d  (+%.1f)", contactos, racha) else tostring(contactos)
	end

	-- El zurrón lleno se pinta en ámbar: es la señal de "ya no te cabe más, vete",
	-- y es lo que separa un viaje aprovechado de otro a medias.
	cargaLabel.TextColor3 = if #estado.cajas >= capacidad then Color3.fromRGB(230, 180, 70) else UiKit.PAPEL
	-- Y el almacén al tope, también: a partir de ahí deja de producir y cada
	-- minuto fuera es tiempo tirado.
	almacenLabel.TextColor3 = if (estado.almacenCajas or 0) >= topeNave
		then Color3.fromRGB(230, 180, 70)
		else UiKit.PAPEL

	-- El PRECIO de lo próximo que puedes comprar, en el propio panel. Antes vivía
	-- en el botón de compra, y ese botón se ha ido al taller como aviso de mundo --
	-- pero el precio NO puede irse con él: ver lo que aún no puedes pagar es la
	-- mitad del motivo para hacer otro viaje, y el taller está en la otra punta del
	-- mapa. Sin esta línea, el dinero se queda sin destino visible, que es
	-- exactamente el problema que el taller venía a resolver.
	local mejoras = estado.mejoras
	local siguiente = mejoras and mejoras[1]
	if metaFila then
		metaFila.Visible = siguiente ~= nil
	end
	if metaLabel and siguiente then
		metaLabel.Text = UiKit.millares(siguiente.coste)
		local etiqueta = metaLabel.Parent and metaLabel.Parent:FindFirstChild("Etiqueta") :: TextLabel?
		if etiqueta then
			etiqueta.Text = siguiente.nombre
		end
		-- En oro cuando ya alcanza: la señal de "puedes comprarlo" tiene que verse de
		-- reojo, sin comparar dos cifras.
		metaLabel.TextColor3 = if estado.dinero >= siguiente.coste then Color3.fromRGB(238, 202, 122) else UiKit.APAGADO
	end
end

-- Llamada por Main.client cuando aparece o desaparece el selector de ruta. Ya no
-- tiene botones que esconder --se fueron al mundo como avisos de proximidad-- así
-- que sólo le queda apartar el aviso de texto.
function Hud.setModal(activo: boolean)
	modal = activo
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
	-- Y la línea de misión con él: el selector ES la misión mientras está abierto.
	if misionLabel then
		misionLabel.Visible = not activo and misionLabel.Text ~= ""
	end
	if accionesPanel then
		-- Se mira si hay alguna fila encendida: el panel sin filas es una caja vacía.
		local hayAlguna = false
		for _, fila in filasAccion do
			hayAlguna = hayAlguna or fila.marco.Visible
		end
		accionesPanel.Visible = not activo and hayAlguna
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
