--!strict
--[[
	Menu.luau — los paneles 2D: habilidades, nave y taller.

	POR QUÉ EXISTE. Hasta ahora todo se compraba yendo al edificio, y eso funciona
	para lo que forma parte del viaje --el almacén, la salida-- pero convierte cada
	compra en un paseo. Lo dijo JJ comparando con un juego grande de la plataforma:
	"las tiendas y el taller mejor en menú 2D como hacen ellos, menos follón". Y es
	el estándar que cualquiera que juegue en móvil ya sabe usar.

	LOS EDIFICIOS SE QUEDAN. El menú es una segunda puerta, no una demolición: la
	oficina de la nave y los talleres siguen ahí y siguen funcionando. Si se
	quitaran, el polígono dejaría de ser un sitio y pasaría a ser un decorado.

	Y HAY UNA EXCEPCIÓN, que es de diseño y no de comodidad: **comprar** un vehículo
	se puede desde aquí, pero **sacarlo** del garaje sigue pidiendo estar en un
	taller. Poder cambiar de vehículo a mitad de la ciudad evaporaría la decisión
	"cuál me llevo a ESTE viaje", que es justo lo que el garaje y la regla de la
	calzada existen para crear.

	DÓNDE VA, que aquí no es un detalle: en el borde derecho, franja media. Las
	cuatro esquinas están ocupadas -- panel de estado arriba a la izquierda,
	brújula arriba en el centro, minimapa arriba a la derecha en móvil y abajo a la
	derecha en escritorio, y abajo los controles táctiles de Roblox, que no podemos
	mover y que el jugador pulsa sin mirar.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
local UiKit = require(game.ReplicatedStorage.Shared.UiKit)
local Strings = require(game.ReplicatedStorage.Shared.Strings)

local Menu = {}

local gui: ScreenGui? = nil
local modal: Frame? = nil
local cuerpo: ScrollingFrame? = nil
local titulo: TextLabel? = nil
local botonSenuelo: TextButton? = nil
local abierto: string? = nil
local ultimoEstado: any = nil
local senueloListoEn = 0

local ORO = Color3.fromRGB(238, 202, 122)

-- 48 px es el minimo tactil del proyecto: por debajo, en un movil se falla el
-- boton y el jugador cree que el juego no responde.
local TOUCH_MIN = 48

local function boton(padre: Instance, texto: string, orden: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = texto
	b.LayoutOrder = orden
	b.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.TextColor3 = UiKit.PAPEL
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.Text = texto
	b.AutoButtonColor = true
	b.Parent = padre
	UiKit.redondear(b, 8)
	UiKit.borde(b, UiKit.oscurecer(color, 0.4), 1.5, 0.3)
	UiKit.margen(b, 6)
	return b
end

-- Una ficha del panel: nombre, lo que hace, y el botón de comprar con su precio.
-- El precio va DENTRO del botón a propósito: leer la fila y decidir tiene que ser
-- un solo movimiento de ojos.
local function ficha(nombre: string, detalle: string, precio: string?, alPulsar: (() -> ())?, orden: number)
	local fila = Instance.new("Frame")
	fila.LayoutOrder = orden
	fila.Size = UDim2.new(1, 0, 0, 66)
	fila.BackgroundColor3 = UiKit.TINTA
	fila.BackgroundTransparency = 0.35
	fila.BorderSizePixel = 0
	fila.Parent = cuerpo
	UiKit.redondear(fila, 8)
	UiKit.margen(fila, 8)

	local titulo2 = Instance.new("TextLabel")
	titulo2.Size = UDim2.new(0.62, 0, 0.45, 0)
	titulo2.BackgroundTransparency = 1
	titulo2.TextColor3 = UiKit.PAPEL
	titulo2.TextScaled = true
	titulo2.Font = Enum.Font.GothamBold
	titulo2.TextXAlignment = Enum.TextXAlignment.Left
	titulo2.Text = nombre
	titulo2.Parent = fila

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.5)
	sub.Size = UDim2.new(0.62, 0, 0.45, 0)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = UiKit.APAGADO
	sub.TextScaled = true
	sub.Font = Enum.Font.Gotham
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = detalle
	sub.Parent = fila

	if not precio then
		return
	end

	local comprar = Instance.new("TextButton")
	comprar.AnchorPoint = Vector2.new(1, 0.5)
	comprar.Position = UDim2.fromScale(1, 0.5)
	comprar.Size = UDim2.new(0.34, 0, 0, TOUCH_MIN)
	comprar.BackgroundColor3 = if alPulsar then ORO else Color3.fromRGB(70, 70, 78)
	comprar.BorderSizePixel = 0
	comprar.TextColor3 = if alPulsar then UiKit.TINTA else UiKit.APAGADO
	comprar.TextScaled = true
	comprar.Font = Enum.Font.GothamBold
	comprar.Text = precio
	comprar.AutoButtonColor = alPulsar ~= nil
	comprar.Parent = fila
	UiKit.redondear(comprar, 6)
	UiKit.margen(comprar, 4)

	if alPulsar then
		comprar.Activated:Connect(alPulsar)
	end
end

local function limpiar()
	if not cuerpo then
		return
	end
	for _, hijo in cuerpo:GetChildren() do
		if not hijo:IsA("UIListLayout") then
			hijo:Destroy()
		end
	end
end

local function pintarHabilidades()
	local estado = ultimoEstado or {}
	local habilidades = Skills.normalizar(estado.habilidades)
	local contactos = estado.contactos or 0
	if titulo then
		titulo.Text = Strings.get("MENU_SKILLS_TITLE", { contactos = contactos })
	end

	for i, d in Skills.CATALOGO do
		local peldano = habilidades[d.id] or 0
		local coste = Skills.coste(habilidades, d.id)
		local descripcion = Strings.ref("SKILL_" .. d.id .. "_DESC")
		local detalle = if coste
			then Strings.get("MENU_SKILL_LEVEL", { descripcion = descripcion, peldano = peldano, total = #d.costes })
			else Strings.get("MENU_SKILL_MAXED", { descripcion = descripcion })

		-- El precio va a secas, sin simbolo: los emojis y los signos raros salen como
		-- cuadrados en un TextLabel de Roblox. Lo que dice que son contactos y no
		-- monedas es la cabecera, que lleva el saldo al lado del titulo.
		local precio = if coste then tostring(coste) else Strings.get("MENU_DONE")
		-- El botón sólo responde si de verdad se puede pagar. Un botón que acepta y
		-- luego el servidor rechaza es la forma más rápida de que el jugador crea
		-- que el juego está roto.
		local puede = coste ~= nil and contactos >= coste
		ficha(
			Strings.get("SKILL_" .. d.id),
			detalle,
			precio,
			if puede
				then function()
					Remotes.event(Remotes.COMPRAR_HABILIDAD):FireServer(d.id)
				end
				else nil,
			i
		)
	end
end

local function pintarNave()
	local estado = ultimoEstado or {}
	local nave = estado.nave
	local siguiente = estado.naveSiguiente

	ficha(
		Strings.get("MENU_WAREHOUSE_TITLE", { nivel = estado.naveNivel or 1 }),
		if nave
			then Strings.get("MENU_WAREHOUSE_SUB", { tope = nave.tope, ritmo = nave.ritmo })
			else Strings.get("MENU_WAREHOUSE_PLAIN"),
		nil,
		nil,
		1
	)

	if not siguiente then
		ficha(Strings.get("MENU_MAXED"), Strings.get("MENU_MAXED_SUB"), nil, nil, 2)
		return
	end

	local puede = (estado.dinero or 0) >= siguiente.coste
	ficha(
		Strings.get("MENU_LEVEL", { nivel = (estado.naveNivel or 1) + 1 }),
		Strings.get("MENU_WAREHOUSE_SUB", { tope = siguiente.tope, ritmo = siguiente.ritmo }),
		UiKit.millares(siguiente.coste),
		if puede
			then function()
				Remotes.event(Remotes.MEJORAR_NAVE):FireServer()
			end
			else nil,
		2
	)
end

local function pintarTaller()
	local estado = ultimoEstado or {}
	local mejoras = estado.mejoras or {}

	if #mejoras == 0 then
		ficha(Strings.get("MENU_NOTHING_TO_BUY"), Strings.get("MENU_NOTHING_TO_BUY_SUB"), nil, nil, 1)
	end

	for i, v in mejoras do
		local detalle = Strings.get("MENU_RIDE_DETAIL", { capacidad = v.capacidad, velocidad = v.velocidadBase })
		if v.bloqueado then
			ficha(
				Strings.get("RIDE_" .. v.id),
				Strings.get("MENU_RIDE_LOCKED", { detalle = detalle, nivel = v.nivel }),
				Strings.get("MENU_LOCKED"),
				nil,
				i
			)
		else
			local puede = (estado.dinero or 0) >= v.coste
			ficha(
				Strings.get("RIDE_" .. v.id),
				detalle,
				UiKit.millares(v.coste),
				if puede
					then function()
						Remotes.event(Remotes.COMPRAR):FireServer(v.id)
					end
					else nil,
				i
			)
		end
	end

	-- Y SE DICE POR QUÉ no se puede sacar desde aquí. Sin esta línea, el jugador
	-- que compra una moto y no la ve puesta cree que el juego se ha comido su
	-- dinero.
	ficha(Strings.get("MENU_GARAGE_TITLE"), Strings.get("MENU_GARAGE_SUB"), nil, nil, 99)
end

-- EL ID NO ES LA ETIQUETA, y esto es lo que había antes: el panel se abría
-- comparando `abierto == "Skills"`, la misma cadena que se pintaba en el botón.
-- Traducir esa cadena habría dejado el menú muerto -- se leería "Fähigkeiten" y
-- la comparación fallaría para siempre. Es el fallo clásico de una localización
-- hecha con prisa, y aquí ya estaba plantado.
local TITULO: { [string]: string } = {
	skills = "MENU_SKILLS",
	warehouse = "MENU_WAREHOUSE",
	workshop = "MENU_WORKSHOP",
}

local function abrir(cual: string)
	if not modal or not titulo then
		return
	end
	abierto = cual
	modal.Visible = true
	titulo.Text = Strings.get(TITULO[cual] or "MENU_WORKSHOP")
	limpiar()

	if cual == "skills" then
		pintarHabilidades()
	elseif cual == "warehouse" then
		pintarNave()
	else
		pintarTaller()
	end
end

local function cerrar()
	abierto = nil
	if modal then
		modal.Visible = false
	end
end

function Menu.build()
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "ContrabandoMenu"
	pantalla.ResetOnSpawn = false
	pantalla.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	pantalla.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = pantalla

	-- LA COLUMNA, en el borde derecho y a media altura: es el único hueco que no
	-- pelea con nada (ver la cabecera). En móvil sube un poco porque ahí el
	-- minimapa está arriba y el salto abajo.
	local columna = Instance.new("Frame")
	columna.Name = "Columna"
	columna.AnchorPoint = Vector2.new(1, 0.5)
	columna.Position = UDim2.fromScale(0.985, if UserInputService.TouchEnabled then 0.46 else 0.42)
	columna.Size = UDim2.fromScale(0.15, 0.3)
	columna.BackgroundTransparency = 1
	columna.Parent = pantalla

	local tamano = Instance.new("UISizeConstraint")
	tamano.MinSize = Vector2.new(104, 4 * TOUCH_MIN + 3 * 6)
	tamano.MaxSize = Vector2.new(170, 4 * TOUCH_MIN + 3 * 6)
	tamano.Parent = columna

	local lista = Instance.new("UIListLayout")
	lista.Padding = UDim.new(0, 6)
	lista.Parent = columna

	boton(columna, Strings.get("MENU_SKILLS"), 2, Color3.fromRGB(58, 62, 82)).Activated:Connect(function()
		if abierto == "skills" then
			cerrar()
		else
			abrir("skills")
		end
	end)
	boton(columna, Strings.get("MENU_WAREHOUSE"), 3, Color3.fromRGB(52, 66, 60)).Activated:Connect(function()
		if abierto == "warehouse" then
			cerrar()
		else
			abrir("warehouse")
		end
	end)
	boton(columna, Strings.get("MENU_WORKSHOP"), 4, Color3.fromRGB(70, 58, 52)).Activated:Connect(function()
		if abierto == "workshop" then
			cerrar()
		else
			abrir("workshop")
		end
	end)

	-- EL SEÑUELO va arriba del todo y en rojo, porque no es una tienda: es la única
	-- cosa que se pulsa MIENTRAS corres, y buscarla entre tres botones iguales con
	-- un ladrón detrás sería perderla.
	local cebo = boton(columna, Strings.get("MENU_DECOY"), 1, Color3.fromRGB(120, 54, 54))
	cebo.Visible = false
	cebo.Activated:Connect(function()
		Remotes.event(Remotes.USAR_SENUELO):FireServer()
		senueloListoEn = os.clock() + Config.SENUELO_RECARGA
	end)
	botonSenuelo = cebo

	-- EL PANEL, centrado y con scroll: en un móvil apaisado no caben cuatro fichas
	-- sin poder deslizar.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.44, 0.5)
	panel.Size = UDim2.fromScale(0.5, 0.66)
	panel.BackgroundColor3 = UiKit.TINTA
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = pantalla
	UiKit.redondear(panel, 12)
	UiKit.borde(panel, Color3.fromRGB(96, 94, 102), 1.5, 0.25)
	UiKit.margen(panel, 10)
	modal = panel

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(260, 200)
	panelSize.MaxSize = Vector2.new(520, 420)
	panelSize.Parent = panel

	local cabecera = Instance.new("TextLabel")
	cabecera.Size = UDim2.new(1, -(TOUCH_MIN + 8), 0, 34)
	cabecera.BackgroundTransparency = 1
	cabecera.TextColor3 = ORO
	cabecera.TextScaled = true
	cabecera.Font = Enum.Font.GothamBold
	cabecera.TextXAlignment = Enum.TextXAlignment.Left
	cabecera.Text = ""
	cabecera.Parent = panel
	titulo = cabecera

	local cerrarBoton = Instance.new("TextButton")
	cerrarBoton.AnchorPoint = Vector2.new(1, 0)
	cerrarBoton.Position = UDim2.fromScale(1, 0)
	cerrarBoton.Size = UDim2.fromOffset(TOUCH_MIN, TOUCH_MIN)
	cerrarBoton.BackgroundColor3 = Color3.fromRGB(70, 70, 78)
	cerrarBoton.BorderSizePixel = 0
	cerrarBoton.TextColor3 = UiKit.PAPEL
	cerrarBoton.TextScaled = true
	cerrarBoton.Font = Enum.Font.GothamBold
	cerrarBoton.Text = Strings.get("MENU_CLOSE")
	cerrarBoton.Parent = panel
	UiKit.redondear(cerrarBoton, 6)
	UiKit.margen(cerrarBoton, 6)
	cerrarBoton.Activated:Connect(cerrar)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(0, TOUCH_MIN + 6)
	scroll.Size = UDim2.new(1, 0, 1, -(TOUCH_MIN + 6))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	cuerpo = scroll

	local listaCuerpo = Instance.new("UIListLayout")
	listaCuerpo.Padding = UDim.new(0, 6)
	listaCuerpo.Parent = scroll
end

function Menu.actualizar(estado: any)
	ultimoEstado = estado

	if botonSenuelo then
		botonSenuelo.Visible = Skills.tieneSenuelo(Skills.normalizar(estado.habilidades))
	end

	-- Repintar lo que esté abierto: si el jugador acaba de comprar, la ficha tiene
	-- que enseñar el peldaño nuevo sin cerrar y volver a abrir.
	if abierto then
		abrir(abierto)
	end
end

-- La recarga, a la vista. Se llama desde el bucle del cliente (en Heartbeat, no
-- en RenderStepped: con la ventana sin foco RenderStepped da cero llamadas por
-- segundo y el botón se quedaría eternamente en cuenta atrás).
function Menu.tick()
	if not botonSenuelo or not botonSenuelo.Visible then
		return
	end
	local queda = senueloListoEn - os.clock()
	if queda > 0 then
		botonSenuelo.Text = Strings.get("MENU_DECOY_COOLDOWN", { segundos = math.ceil(queda) })
		botonSenuelo.BackgroundColor3 = Color3.fromRGB(70, 60, 60)
		botonSenuelo.AutoButtonColor = false
	else
		botonSenuelo.Text = Strings.get("MENU_DECOY")
		botonSenuelo.BackgroundColor3 = Color3.fromRGB(120, 54, 54)
		botonSenuelo.AutoButtonColor = true
	end
end

function Menu.cerrar()
	cerrar()
end

-- Con el selector de ruta abierto, el menú se aparta entero. Su velo ocupa la
-- pantalla completa, así que sin esto la columna quedaría encima de un modal y se
-- podría pulsar a través de él -- que es la clase de cosa que no se ve en una
-- captura y se sufre jugando.
function Menu.setModal(activo: boolean)
	if not gui then
		return
	end
	local columna = gui:FindFirstChild("Columna")
	if columna and columna:IsA("GuiObject") then
		columna.Visible = not activo
	end
	if activo then
		cerrar()
	end
end

return Menu
