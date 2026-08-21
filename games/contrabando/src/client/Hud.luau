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
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Contacts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Contacts"))
local Goals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Goals"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))
local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

local TOUCH_MIN = 48

local Hud = {}
local dineroLabel: TextLabel
local cargaLabel: TextLabel
local almacenLabel: TextLabel
local calorLabel: TextLabel
local calorFila: Frame
-- EL ALTO DE CADA LÍNEA DEL PANEL, y por qué no es una constante.
--
-- El panel tiene tres líneas fijas (dinero, carga, nave) y hasta cuatro
-- condicionales (peligro, meta, contactos, objetivo): siete en el peor caso. Con
-- un alto fijo de 26 px eso son 210 px de panel, y ahí está el problema — medido
-- contra el Galaxy A06 que ya cita el minimapa (705×338 apaisado), **210 px son el
-- 62 % del alto de la pantalla**. El panel de estado tapando dos tercios del juego.
--
-- La solución no es recortarlo con un máximo: eso es lo que había antes y es lo que
-- hacía que las filas se salieran unas sobre otras. Es que la línea mida según la
-- pantalla que la va a enseñar. Con el 5 %: en ese móvil son 17 px (43 % con las
-- siete, aceptable para un pico) y en un monitor 28 (18 %).
--
-- El mínimo de 17 no es negociable hacia abajo: por debajo, el texto de la fila
-- --que va con TextScaled, o sea atado a este alto-- deja de leerse de un vistazo,
-- y un HUD que hay que mirar fijamente mientras te persiguen no sirve de nada.
local ALTO_FILA_MIN, ALTO_FILA_MAX = 17, 28

-- El halo rojo del borde de la pantalla. Ver `Hud.build` y el bloque del calor en
-- `Hud.update`.
local calorHalo: Frame?
local calorLatido = 0
local metaLabel: TextLabel
local metaFila: Frame
local contactosLabel: TextLabel
local contactosFila: Frame
local objetivoLabel: TextLabel
local objetivoFila: Frame
local dineroObjetivo = 0
local dineroMostrado: number? = nil
local avisoLabel: TextLabel
local misionLabel: TextLabel
local accionesPanel: Frame

-- LAS CASILLAS. Una por clase guardable, con lo que llevas y lo que queda de lo que
-- has activado. Ver `Config.OBJETOS_TOPE` para el porque de que se guarden.
type Casilla = {
	marco: Frame,
	cuantos: TextLabel,
	tecla: TextLabel,
	barra: Frame,
	icono: Frame,
}
local casillas: { [string]: Casilla } = {}
local casillasPanel: Frame?
-- Lo que quedaba de cada efecto en el ultimo sync, y cuando llego. Entre sync y
-- sync se descuenta aqui: el servidor manda "te quedan 6,2 s" y el reloj sigue
-- corriendo aunque no llegue nada nuevo. Sin esto la barra daria saltos de medio
-- segundo, que en una cuenta atras de ocho se lee como que va rota.
local restante: { [string]: number } = {}
local medidoEn = 0
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

-- El contador del dinero. Persigue al objetivo con un paso proporcional a lo que
-- falta, así que un salto pequeño se resuelve enseguida y uno grande no tarda una
-- eternidad: contar de 0 a 15.000 moneda a moneda sería peor que no contar.
--
-- En Heartbeat y no en RenderStepped: esto es información, y con la ventana sin
-- foco RenderStepped da CERO llamadas por segundo -- el contador se quedaría
-- congelado a mitad de cuenta sin ningún error.
local function arrancarContador()
	RunService.Heartbeat:Connect(function(dt)
		if not dineroLabel or dineroMostrado == nil then
			return
		end
		local actual = dineroMostrado :: number
		if actual == dineroObjetivo then
			return
		end
		local paso = (dineroObjetivo - actual) * math.min(1, dt * 6)
		-- Sin este mínimo, el último tramo se acerca infinitamente sin llegar y el
		-- HUD se queda un euro por debajo para siempre.
		if math.abs(dineroObjetivo - actual) < 1 or math.abs(paso) < 1 then
			dineroMostrado = dineroObjetivo
		else
			dineroMostrado = actual + paso
		end
		dineroLabel.Text = UiKit.millares(math.floor(dineroMostrado :: number))
	end)
end

-- LAS CASILLAS, abajo y al centro.
--
-- No a los lados: la columna izquierda es informacion que se lee (dinero, mision,
-- controles) y la derecha es el menu. Y NUNCA en las esquinas de abajo, que son del
-- joystick y del boton de salto de Roblox -- regla del proyecto, ya pagada una vez.
-- El centro inferior es el unico hueco que queda libre en movil, y ademas es donde
-- el pulgar llega sin soltar la direccion.
--
-- El icono se DIBUJA con marcos, no con una imagen: un asset hay que subirlo y no
-- se ve hasta publicar el place (la trampa de los meshes). Una flecha son dos
-- rectangulos y un cuadrado girado; un escudo, un rombo con borde.
local function construirCasilla(padre: Instance, tipo: string, orden: number, color: Color3): Casilla
	local marco = Instance.new("Frame")
	marco.Name = "Casilla_" .. tipo
	marco.LayoutOrder = orden
	marco.Size = UDim2.fromOffset(62, 62)
	marco.BackgroundColor3 = UiKit.TINTA
	marco.BackgroundTransparency = 0.15
	marco.BorderSizePixel = 0
	marco.Parent = padre
	UiKit.redondear(marco, 10)
	UiKit.borde(marco, color, 2, 0.25)

	local icono = Instance.new("Frame")
	icono.Name = "Icono"
	icono.AnchorPoint = Vector2.new(0.5, 0.5)
	icono.Position = UDim2.fromScale(0.5, 0.44)
	icono.Size = UDim2.fromOffset(26, 26)
	icono.BackgroundTransparency = 1
	icono.Parent = marco

	if tipo == "salto" then
		-- Flecha: el asta y la punta.
		local asta = Instance.new("Frame")
		asta.AnchorPoint = Vector2.new(0.5, 1)
		asta.Position = UDim2.fromScale(0.5, 1)
		asta.Size = UDim2.fromOffset(8, 14)
		asta.BackgroundColor3 = color
		asta.BorderSizePixel = 0
		asta.Parent = icono
		local punta = Instance.new("Frame")
		punta.AnchorPoint = Vector2.new(0.5, 0)
		punta.Position = UDim2.fromScale(0.5, 0.06)
		punta.Size = UDim2.fromOffset(15, 15)
		punta.Rotation = 45
		punta.BackgroundColor3 = color
		punta.BorderSizePixel = 0
		punta.Parent = icono
	else
		-- Escudo: un rombo con el centro hueco, que a este tamano se lee mejor que
		-- una silueta de escudo -- que a 26 pixeles es una mancha.
		local rombo = Instance.new("Frame")
		rombo.AnchorPoint = Vector2.new(0.5, 0.5)
		rombo.Position = UDim2.fromScale(0.5, 0.5)
		rombo.Size = UDim2.fromOffset(20, 20)
		rombo.Rotation = 45
		rombo.BackgroundTransparency = 1
		rombo.Parent = icono
		UiKit.borde(rombo, color, 3, 0)
		UiKit.redondear(rombo, 4)
	end

	-- CUANTOS LLEVAS. Abajo, grande y en el color de la casilla: es el dato por el
	-- que se mira aqui mientras conduces.
	local cuantos = Instance.new("TextLabel")
	cuantos.Name = "Cuantos"
	cuantos.AnchorPoint = Vector2.new(0.5, 1)
	cuantos.Position = UDim2.fromScale(0.5, 0.99)
	cuantos.Size = UDim2.new(1, -6, 0, 16)
	cuantos.BackgroundTransparency = 1
	cuantos.TextColor3 = color
	cuantos.TextScaled = true
	cuantos.Font = Enum.Font.GothamBold
	cuantos.Text = ""
	cuantos.Parent = marco

	-- Y CON QUE SE USA. Cambia con el aparato: la misma etiqueta que la lista de
	-- controles, para que digan lo mismo (ver `etiqueta` en Main.client).
	local tecla = Instance.new("TextLabel")
	tecla.Name = "Tecla"
	tecla.AnchorPoint = Vector2.new(0, 0)
	tecla.Position = UDim2.fromOffset(4, 2)
	tecla.Size = UDim2.fromOffset(24, 13)
	tecla.BackgroundTransparency = 1
	tecla.TextColor3 = UiKit.APAGADO
	tecla.TextScaled = true
	tecla.Font = Enum.Font.GothamBold
	tecla.TextXAlignment = Enum.TextXAlignment.Left
	tecla.Text = ""
	tecla.Parent = marco

	-- LA CUENTA ATRAS del efecto puesto, como una barra que se vacia por debajo.
	-- Un numero haria falta leerlo; una barra se ve de reojo, que es como se mira
	-- el HUD cuando te persiguen.
	local barra = Instance.new("Frame")
	barra.Name = "Barra"
	barra.AnchorPoint = Vector2.new(0, 1)
	barra.Position = UDim2.fromScale(0, 1)
	barra.Size = UDim2.fromScale(0, 0.06)
	barra.BackgroundColor3 = color
	barra.BorderSizePixel = 0
	barra.Visible = false
	barra.Parent = marco

	return { marco = marco, cuantos = cuantos, tecla = tecla, barra = barra, icono = icono }
end

function Hud.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContrabandoHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- EL HALO DE PELIGRO: el borde de la pantalla se tiñe y late cuando aprietan.
	--
	-- POR QUÉ, y está escrito en `V1.md` §7: *"el paso de peligro 1 a 3 no cambia la
	-- pantalla lo suficiente; la tensión está en los números, no en los ojos"*. Hoy
	-- el calor sólo se ve en una línea del panel de arriba a la izquierda, y lo que
	-- estás mirando cuando te persiguen es el centro de la pantalla.
	--
	-- Va PRIMERO en el árbol y con ZIndex bajo para quedar DEBAJO de todo lo demás:
	-- es ambiente, no información que haya que leer. Y `Active = false` para que no
	-- se coma un solo toque en móvil, donde toda la pantalla es un botón.
	-- SE MONTA CON CUATRO FRANJAS Y UN DEGRADADO, no con una textura.
	--
	-- El primer intento usaba una imagen del cliente (`inspect_gradient.png`)
	-- estirada a pantalla completa, y la captura lo desmintió: es un degradado
	-- LINEAL, así que salía una banda naranja cruzando el centro en vez de un
	-- viñeteado. Cuatro franjas --una por borde-- con su `UIGradient` de opaco a
	-- transparente hacia dentro dan la forma correcta, no dependen de ningún asset
	-- y dejan el centro de la pantalla completamente limpio, que es donde el
	-- jugador está mirando cuando le persiguen.
	local halo = Instance.new("Frame")
	halo.Name = "HaloPeligro"
	halo.BackgroundTransparency = 1
	halo.Active = false
	halo.ZIndex = 0
	halo.Size = UDim2.fromScale(1, 1)
	halo.Visible = false
	halo.Parent = gui
	calorHalo = halo

	-- Cada franja: de dónde nace, cómo de gruesa, y hacia dónde se desvanece.
	local bordes = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.new(1, 0, 0.17, 0), anchor = Vector2.new(0, 0), rot = 90 },
		{ pos = UDim2.fromScale(0, 1), size = UDim2.new(1, 0, 0.17, 0), anchor = Vector2.new(0, 1), rot = 270 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.new(0.11, 0, 1, 0), anchor = Vector2.new(0, 0), rot = 0 },
		{ pos = UDim2.fromScale(1, 0), size = UDim2.new(0.11, 0, 1, 0), anchor = Vector2.new(1, 0), rot = 180 },
	}
	for i, borde in bordes do
		local franja = Instance.new("Frame")
		franja.Name = "Franja" .. i
		franja.AnchorPoint = borde.anchor
		franja.Position = borde.pos
		franja.Size = borde.size
		franja.BackgroundColor3 = Color3.fromRGB(190, 30, 25)
		franja.BorderSizePixel = 0
		franja.ZIndex = 0
		franja.Parent = halo

		local grad = Instance.new("UIGradient")
		-- Opaca pegada al borde y transparente del todo hacia el centro. La rotación
		-- es lo que orienta cada franja hacia dentro de la pantalla.
		grad.Rotation = borde.rot
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = franja
	end

	-- LA COLUMNA DE LA IZQUIERDA: estado, mision y controles, EN ESTE ORDEN y sin
	-- que ninguno sepa donde acaba el anterior.
	--
	-- Antes cada uno llevaba su Y escrita a mano (0,03 / 0,235 / 0,295) y el panel de
	-- estado, que crece con las filas que tengas encendidas, se los comia. Ya paso
	-- una vez DENTRO del panel --"Skateboard 150", "Goal" y "0 of 1 deliveries"
	-- pisandose-- y se arreglo alli poniendole AutomaticSize... con lo que el mismo
	-- fallo se mudo a la puerta de al lado: el panel crecio y se trago la mision.
	-- Se vio en una captura de JJ el 20/08, con "Warehouse 3/10" cortada por arriba y
	-- "Deliver in GREEN" encima de "Goal".
	--
	-- Un UIListLayout no se puede desordenar: el hueco de cada cosa lo decide lo que
	-- ocupa la de arriba, que es exactamente el dato que un numero fijo no tiene.
	local columna = Instance.new("Frame")
	columna.Name = "Columna"
	columna.AnchorPoint = Vector2.new(0, 0)
	columna.Position = UDim2.fromScale(0.02, 0.03)
	columna.Size = UDim2.new(0.34, 0, 0, 0)
	columna.AutomaticSize = Enum.AutomaticSize.Y
	columna.BackgroundTransparency = 1
	columna.Parent = gui

	local columnaLayout = Instance.new("UIListLayout")
	columnaLayout.FillDirection = Enum.FillDirection.Vertical
	columnaLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnaLayout.Padding = UDim.new(0, 6)
	columnaLayout.Parent = columna

	local columnaSize = Instance.new("UISizeConstraint")
	-- Solo el ANCHO: el alto lo decide el contenido, y un maximo aqui volveria a
	-- recortar lo de abajo, que es el fallo del que se viene.
	columnaSize.MinSize = Vector2.new(150, 0)
	columnaSize.MaxSize = Vector2.new(300, math.huge)
	columnaSize.Parent = columna

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.LayoutOrder = 1
	-- EL ALTO LO PONE EL CONTENIDO, no una fracción de la pantalla.
	--
	-- Antes era `fromScale(0.3, 0.19)` con cada fila al 33 % del panel, y eso sólo
	-- cuadra con TRES filas. El panel tiene tres fijas (dinero, carga, nave) y hasta
	-- cuatro condicionales (peligro, meta, contactos, objetivo): con cinco visibles
	-- las filas sumaban el 165 % del panel y se salían por abajo, encima del mundo y
	-- unas sobre otras. Se vio en una captura -- "Skateboard 150", "Goal" y "0 of 1
	-- deliveries" pisándose. Un HUD que se desordena según lo que te pasa en la
	-- partida es de las cosas que más barato se arreglan y peor se ven.
	--
	-- Con AutomaticSize.Y el panel mide exactamente lo que ocupan sus filas, así que
	-- añadir o quitar líneas condicionales no puede volver a romperlo.
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.BackgroundColor3 = UiKit.TINTA
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.Parent = columna
	UiKit.redondear(panel, 10)
	UiKit.borde(panel, Color3.fromRGB(90, 88, 96), 1.5, 0.35)
	UiKit.margen(panel, 8)

	-- El ancho lo limita la columna, que es quien lo tiene que decidir para las tres.

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
		-- Alto en PÍXELES y no en fracción del panel: es lo que permite que el panel
		-- crezca contando filas en vez de repartirse entre ellas. Lo pone
		-- `ajustarFilas` según el alto de la pantalla, y aquí sólo se deja un valor
		-- de arranque para que la fila exista con tamaño desde el primer fotograma.
		fila.Size = UDim2.new(1, 0, 0, ALTO_FILA_MAX)
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

	dineroLabel = linea("Dinero", 1, Strings.get("HUD_MONEY"))
	cargaLabel = linea("Carga", 2, Strings.get("HUD_CARGO"))
	almacenLabel = linea("Almacen", 3, Strings.get("HUD_WAREHOUSE"))
	-- La cuarta línea es CONDICIONAL: sólo se enseña con calor encima. Por eso el
	-- panel sigue dimensionado para tres y se estira con el layout en vez de
	-- reservar sitio para una línea que casi siempre estaría a cero.
	calorLabel = linea("Calor", 4, Strings.get("HUD_HEAT"))
	calorFila = calorLabel.Parent :: Frame
	calorFila.Visible = false

	-- La meta: lo próximo que puedes comprar y su precio. También condicional --
	-- desaparece cuando ya no queda nada que comprar, en vez de quedarse ocupando
	-- sitio con una línea vacía.
	metaLabel = linea("Meta", 5, Strings.get("HUD_NEXT"))
	metaFila = metaLabel.Parent :: Frame
	metaFila.Visible = false

	-- LOS CONTACTOS, y la racha entre paréntesis. También condicional: hasta que se
	-- recoge el primero no hay nada que contar, y un cero fijo en un panel de tres
	-- líneas es sitio caro tirado en un móvil.
	--
	-- Van juntos porque son la misma cosa vista de dos maneras: lo que has
	-- recogido en este viaje es lo que estás corriendo de más.
	contactosLabel = linea("Contactos", 6, Strings.get("HUD_CONTACTS"))
	contactosFila = contactosLabel.Parent :: Frame
	contactosFila.Visible = false
	contactosLabel.TextColor3 = Color3.fromRGB(255, 214, 130)

	-- EL OBJETIVO. Es la línea que responde "¿y esto para qué?", que es distinta de
	-- la misión de abajo -- ésa dice qué hacer AHORA (ve a la salida, entrega
	-- aquí) y ésta a qué aspiras. Sin ella, la licencia por nivel sólo se descubría
	-- chocando: pulsabas la ámbar y te decía que no.
	--
	-- Condicional como las otras dos: cuando no queda ningún hito, desaparece en
	-- vez de quedarse diciendo algo vacío.
	objetivoLabel = linea("Objetivo", 7, Strings.get("HUD_GOAL"))
	objetivoFila = objetivoLabel.Parent :: Frame
	objetivoFila.Visible = false
	objetivoLabel.TextColor3 = Color3.fromRGB(150, 205, 235)
	-- El dinero es el número que más se mira: se le da el color del oro para que
	-- destaque entre los otros dos sin necesidad de leer la etiqueta.
	dineroLabel.TextColor3 = Color3.fromRGB(238, 202, 122)

	-- Y AHORA LAS FILAS SE MIDEN CONTRA LA PANTALLA QUE LES HA TOCADO.
	--
	-- Se recalcula al cambiar `AbsoluteSize` y no una sola vez al construir, por dos
	-- motivos que pasan de verdad: al arrancar, el ScreenGui todavía no tiene su
	-- tamaño final (sale 0 y luego se ajusta), y girar el móvil cambia el alto de
	-- pantalla a la mitad sin recargar nada.
	--
	-- Se mide contra `gui.AbsoluteSize` y NO contra `Camera.ViewportSize`: con los
	-- insets de dispositivo puestos no coinciden, y ésa es una confusión que este
	-- proyecto ya pagó midiendo interfaces.
	local function ajustarFilas()
		local area = gui.AbsoluteSize
		if area.Y <= 0 then
			return
		end
		local alto = math.clamp(math.floor(area.Y * 0.05), ALTO_FILA_MIN, ALTO_FILA_MAX)
		for _, hijo in panel:GetChildren() do
			if hijo:IsA("Frame") then
				hijo.Size = UDim2.new(1, 0, 0, alto)
			end
		end
	end
	ajustarFilas()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(ajustarFilas)

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
	misionLabel.LayoutOrder = 2
	-- ALTO EN PIXELES y no en fraccion de pantalla: la mision es una linea de texto,
	-- y una linea mide lo que mide la letra, no un 5,5 % de lo alta que sea la
	-- ventana. En un movil apaisado, esa fraccion daba una tira de doce pixeles.
	misionLabel.Size = UDim2.new(1, 0, 0, 34)
	misionLabel.BackgroundColor3 = UiKit.TINTA
	misionLabel.BackgroundTransparency = 0.22
	misionLabel.TextColor3 = UiKit.PAPEL
	misionLabel.TextScaled = true
	misionLabel.Font = Enum.Font.GothamBold
	misionLabel.TextXAlignment = Enum.TextXAlignment.Left
	misionLabel.TextStrokeTransparency = 0.6
	misionLabel.Text = ""
	misionLabel.Visible = false
	misionLabel.Parent = columna
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
	accionesPanel.LayoutOrder = 3
	-- ALTO PARA LAS CUATRO FILAS, en pixeles. Tenia 4,5 % de la pantalla con cuatro
	-- filas de 26 px dentro: con dos acciones a la vez, la segunda salia del marco.
	-- Como el marco es transparente eso no se veia como "se sale", se veia como
	-- "esta encima de otra cosa".
	--
	-- Y NO `AutomaticSize`, que fue el primer intento y salio peor: medido en
	-- pantalla, un hijo con ancho en escala dentro de un padre que tambien crece
	-- solo se quedaba en 102 px de los 300 de la columna, y el texto de las acciones
	-- ("pick up, buy and use") se cortaba. El hueco que sobra cuando hay menos de
	-- cuatro acciones es transparente y esta al final de la columna, asi que no
	-- estorba a nadie.
	accionesPanel.Size = UDim2.new(1, 0, 0, 4 * 26 + 3 * 4)
	accionesPanel.BackgroundTransparency = 1
	accionesPanel.Visible = false
	accionesPanel.Parent = columna

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

	-- EL PANEL DE CASILLAS. Se monta al final porque cuelga del ScreenGui y no de la
	-- columna: es lo unico del HUD que no se lee, se PULSA.
	local panel = Instance.new("Frame")
	panel.Name = "Casillas"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 0.985)
	panel.Size = UDim2.fromOffset(62 * 2 + 10, 62)
	panel.BackgroundTransparency = 1
	panel.Parent = gui
	casillasPanel = panel

	local fila = Instance.new("UIListLayout")
	fila.FillDirection = Enum.FillDirection.Horizontal
	fila.HorizontalAlignment = Enum.HorizontalAlignment.Center
	fila.Padding = UDim.new(0, 10)
	fila.Parent = panel

	-- Los ids NO se traducen y de ellos se deriva todo lo demas: el nombre sale de
	-- `SLOT_<id>` en Strings, igual que las rutas.
	casillas.salto = construirCasilla(panel, "salto", 1, Color3.fromRGB(96, 226, 236))
	casillas.escudo = construirCasilla(panel, "escudo", 2, Color3.fromRGB(150, 240, 150))

	-- LA CUENTA ATRAS, EN SU PROPIO BUCLE. El HUD se repinta cuando llega estado del
	-- servidor --que puede ser cada varios segundos si no pasa nada-- y una barra que
	-- solo se mueve con el trafico de red no es una cuenta atras, es un escalon.
	RunService.Heartbeat:Connect(function()
		local ahora = os.clock()
		for tipo, casilla in casillas do
			local queda = (restante[tipo] or 0) - (ahora - medidoEn)
			local tope = if tipo == "salto" then Config.SALTO_IMPULSO_SEGUNDOS else Config.ESCUDO_SEGUNDOS
			casilla.barra.Visible = queda > 0
			if queda > 0 then
				casilla.barra.Size = UDim2.fromScale(math.clamp(queda / tope, 0, 1), 0.06)
			end
		end
	end)

	arrancarContador()
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

-- Lo que se dibuja en cada casilla. Se llama con cada estado que llega.
function Hud.objetos(estado: any)
	if casillasPanel == nil then
		return
	end
	local objetos = (estado and estado.objetos) or {}
	restante.salto = if estado then estado.saltoRestante or 0 else 0
	restante.escudo = if estado then estado.escudoRestante or 0 else 0
	medidoEn = os.clock()

	for tipo, casilla in casillas do
		local cuantos = objetos[tipo] or 0
		casilla.cuantos.Text = if cuantos > 0 then "x" .. cuantos else Strings.get("SLOT_EMPTY")
		-- VACIA SE APAGA, no se esconde: una casilla que desaparece cuando no llevas
		-- nada no ensena que existe, y lo que hay que aprender aqui es justamente que
		-- esas piezas del suelo se guardan.
		casilla.marco.BackgroundTransparency = if cuantos > 0 then 0.15 else 0.55
		casilla.icono.Visible = true
		for _, hijo in casilla.icono:GetChildren() do
			if hijo:IsA("Frame") then
				hijo.BackgroundTransparency = if cuantos > 0 then 0 else 0.6
			end
		end
	end
	casillasPanel.Visible = not modal
end

-- Con que se pulsa cada casilla. Lo decide Main.client, que es quien sabe si hay un
-- mando en la mano; aqui solo se pinta.
function Hud.teclasDeObjetos(salto: string, escudo: string)
	if casillas.salto then
		casillas.salto.tecla.Text = salto
	end
	if casillas.escudo then
		casillas.escudo.tecla.Text = escudo
	end
end

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
	vehiculoClave: string?,
	mejoras: { { id: string, nombre: string, coste: number, capacidad: number } }?,
	cajasEnVehiculo: { any }?,
	contactos: number?,
	recogidos: number?,
	entregas: number?,
	nivel: number?,
	hito: any?,
}

function Hud.update(estado: EstadoHud)
	if not dineroLabel then
		return
	end
	-- EL DINERO NO SE ESCRIBE: SE PERSIGUE. Un número que salta de 300 a 540 se
	-- entera el HUD; uno que sube se entera el jugador, y es la misma cifra. El
	-- contador vive en su propio Heartbeat (abajo) porque el refresco general va a
	-- cuatro veces por segundo y a esa cadencia contar se ve a trompicones.
	dineroObjetivo = estado.dinero
	if dineroMostrado == nil then
		-- La primera vez se pone entero: entrar con 7.777 guardadas no es haber
		-- ganado 7.777, y verlas contar desde cero sería mentir.
		dineroMostrado = estado.dinero
		dineroLabel.Text = UiKit.millares(estado.dinero)
	end
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
		-- El nombre del vehículo llega como CLAVE y se monta aquí: el servidor no
		-- sabe en qué idioma lee este jugador.
		etiquetaCarga.Text = if estado.vehiculoClave
			then Strings.get(estado.vehiculoClave)
			else Strings.get("HUD_CARGO")
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

	-- Y EL BORDE DE LA PANTALLA CON ÉL. A partir del nivel 2 y no del 1: con uno
	-- sólo te han visto pasar, y teñir la pantalla por eso la dejaría teñida medio
	-- viaje -- un aviso que está siempre encendido deja de ser un aviso. Dos es
	-- cuando ya hay alguien detrás.
	--
	-- El latido va con el nivel: a 2 respira, a 3 va deprisa. Es información sin
	-- números, que es lo que sirve cuando estás corriendo y mirando al frente.
	if calorHalo then
		local halo = calorHalo :: Frame
		if nivel >= 2 then
			halo.Visible = true
			-- El latido sale del RELOJ, no de un contador que suba una pizca en cada
			-- llamada: `Hud.update` lo llama el bucle del cliente (cada 0,25 s) pero
			-- también cada estado que llega del servidor, así que acumular ataría la
			-- velocidad del latido al tráfico de red -- iría más deprisa cuanto más
			-- pasara en la partida, que es exactamente lo que no se quiere.
			local ritmo = if nivel >= Config.CALOR_MAXIMO then 5.2 else 2.6
			local fuerza = if nivel >= Config.CALOR_MAXIMO then 0.16 else 0.09
			calorLatido = os.clock() * ritmo
			-- Entre el 80 % y el 100 % de la fuerza: nunca se apaga del todo entre
			-- latidos, o parpadearía en vez de respirar.
			local onda = 0.9 + 0.1 * math.sin(calorLatido)
			-- La transparencia va en las franjas, no en el contenedor: el Frame de
			-- fuera no pinta nada, sólo las agrupa para poder encenderlas de una vez.
			for _, franja in halo:GetChildren() do
				if franja:IsA("Frame") then
					franja.BackgroundTransparency = 1 - fuerza * onda
				end
			end
		else
			halo.Visible = false
		end
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

	-- El objetivo, con su progreso. El hito viaja YA RESUELTO desde el servidor
	-- (PlayerState.sync): el cliente lo dibuja y no aplica ninguna regla, que es lo
	-- que impide que su idea de qué toca hacer discrepe de la del servidor.
	local hito = estado.hito
	if objetivoFila then
		objetivoFila.Visible = hito ~= nil
	end
	if objetivoLabel and hito then
		objetivoLabel.Text = Goals.progreso(hito, estado.entregas or 0, estado.nivel or 1)
		local etiqueta = objetivoLabel.Parent and objetivoLabel.Parent:FindFirstChild("Etiqueta") :: TextLabel?
		if etiqueta then
			etiqueta.Text = Strings.get("HUD_GOAL")
		end
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
			etiqueta.Text = Strings.get("RIDE_" .. siguiente.id)
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

-- EL CARTELON DE ENTREGA. *"Que el traslado al inicio sea con un efecto y salga
-- 'delivered'"* (JJ), y el diagnostico de fondo es acertado: entregar era el momento
-- mas importante del bucle y se anunciaba con la misma linea de texto de tres
-- segundos que usa "no llevas nada". El unico instante en que el juego te DA algo se
-- perdia entre los avisos de trafico.
--
-- Se construye al vuelo y se destruye al acabar. Es lo unico de este HUD que no vive
-- permanentemente en la pantalla, y a proposito: aparece una vez cada viaje, dura
-- segundo y medio, y no puede quedarse ocupando sitio ni pintarse en la primera
-- carga como todo lo demas.
function Hud.entregado(monedas: number)
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then
		return
	end

	local capa = Instance.new("ScreenGui")
	capa.Name = "Entregado"
	capa.ResetOnSpawn = false
	-- Por encima de todo lo demas: es el unico momento en que tapar el HUD es lo
	-- correcto.
	capa.DisplayOrder = 50
	capa.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	capa.Parent = gui

	local marco = Instance.new("Frame")
	marco.AnchorPoint = Vector2.new(0.5, 0.5)
	marco.Position = UDim2.fromScale(0.5, 0.42)
	marco.Size = UDim2.fromScale(0.6, 0.2)
	marco.BackgroundTransparency = 1
	marco.Parent = capa

	local titulo = Instance.new("TextLabel")
	titulo.Size = UDim2.fromScale(1, 0.58)
	titulo.BackgroundTransparency = 1
	titulo.Text = Strings.get("DELIVERED_BANNER")
	titulo.TextColor3 = Color3.fromRGB(150, 235, 165)
	titulo.TextStrokeTransparency = 0.35
	titulo.TextScaled = true
	titulo.Font = Enum.Font.GothamBlack
	titulo.Parent = marco

	local cifra = Instance.new("TextLabel")
	cifra.Position = UDim2.fromScale(0, 0.58)
	cifra.Size = UDim2.fromScale(1, 0.42)
	cifra.BackgroundTransparency = 1
	cifra.Text = Strings.get("DELIVERED_AMOUNT", { monedas = monedas })
	cifra.TextColor3 = Color3.fromRGB(238, 205, 120)
	cifra.TextStrokeTransparency = 0.4
	cifra.TextScaled = true
	cifra.Font = Enum.Font.GothamBold
	cifra.Parent = marco

	-- ENTRA GRANDE Y SE VA HACIA ARRIBA. El golpe de entrada es lo que hace que se
	-- lea sin buscarlo; la subida al desvanecerse es lo que hace que no moleste --
	-- sale del centro justo cuando el jugador vuelve a necesitar ver el mundo.
	marco.Size = UDim2.fromScale(0.3, 0.1)
	TweenService:Create(marco, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.62, 0.21),
	}):Play()
	task.delay(0.9, function()
		local salida = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(marco, salida, { Position = UDim2.fromScale(0.5, 0.3) }):Play()
		TweenService:Create(titulo, salida, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(cifra, salida, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.6, function()
			capa:Destroy()
		end)
	end)
end

return Hud
