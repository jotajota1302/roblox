--!strict
--[[
	Minimap.luau — la ciudad vista desde arriba, con el plano de verdad.

	La primera versión eran puntos de colores flotando en un cuadro negro, y JJ dio
	con el problema exacto: "que se vea el plano de la ciudad, si no no sirve para
	mucho". Tenía razón, y el motivo es de diseño, no estético. Un punto azul a
	ochenta metros no dice si puedes llegar: la respuesta cambia por completo según
	haya una calle o una manzana de edificios en medio, y **esa es justo la decisión
	que el mapa tiene que ayudar a tomar** cuando te persiguen. La dirección ya la
	da la brújula; lo que aporta un mapa es el obstáculo.

	CÓMO SE DIBUJA UN PLANO SIN NINGÚN ASSET. Una textura del mapa sería un asset
	subido, y un asset no carga con el place sin publicar -- la trampa que ya nos
	dejó sin avatar y sin decorado. Así que el plano se construye con Frames leyendo
	la ciudad directamente (está replicada al cliente), UNA sola vez al arrancar.

	Y el truco que lo hace barato: los cientos de rectángulos se pintan en un LIENZO
	grande que no se toca nunca más; lo que se mueve en cada refresco es el lienzo
	entero, un único Frame, dentro de un marco recortado. Mover 500 hijos sesenta
	veces por segundo mataría un móvil de gama baja; mover a su padre no cuesta nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

-- Píxeles por stud. Con un marco de 150 px se ven unos 680 studs de lado: la
-- manzana en la que estás y las dos de al lado. Más alcance convierte cada
-- edificio en un punto de dos píxeles y el plano deja de leerse; menos, y ya no
-- ves a dónde vas.
local ESCALA = 0.22

-- Sólo se pintan las piezas que aportan silueta. Un plano con las 7161 partes de
-- la ciudad sería una mancha gris, además de tardar en construirse.
local MINIMO_LADO = 14

local Minimap = {}
local marco: Frame? = nil
local lienzo: Frame? = nil
local puntos: { [string]: Frame } = {}
local estado: any = nil
local origenMapa = Vector2.new(0, 0)

local function punto(nombre: string, color: Color3, tamano: number, orden: number): Frame
	local p = puntos[nombre]
	if p and p.Parent then
		return p
	end
	local f = Instance.new("Frame")
	f.Name = nombre
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(tamano, tamano)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = orden
	f.Visible = false
	f.Parent = marco
	UiKit.redondear(f, tamano)
	puntos[nombre] = f
	return f
end

-- Pinta el plano una vez. Distingue suelo de edificio por la altura de la pieza,
-- que es lo único que hace falta: la silueta de las manzanas contra las calles.
local function pintarPlano(ciudad: Instance, capa: Frame): Vector2
	local cf, size = ciudad:GetBoundingBox()
	local minX = cf.Position.X - size.X / 2
	local minZ = cf.Position.Z - size.Z / 2

	capa.Size = UDim2.fromOffset(size.X * ESCALA, size.Z * ESCALA)

	local pintadas = 0

	local function rectangulo(centroX: number, centroZ: number, anchoX: number, anchoZ: number, esEdificio: boolean)
		local r = Instance.new("Frame")
		r.Name = "P" .. pintadas
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromOffset((centroX - minX) * ESCALA, (centroZ - minZ) * ESCALA)
		r.Size = UDim2.fromOffset(math.max(2, anchoX * ESCALA), math.max(2, anchoZ * ESCALA))
		r.BorderSizePixel = 0
		-- Edificios claros sobre calle oscura: es la convención de cualquier plano y
		-- se lee sin explicación. El color real de la pieza no sirve -- media ciudad
		-- es del mismo gris y el plano saldría plano.
		-- El suelo se pinta MUY apagado y los edificios opacos. Con los dos a media
		-- tinta el plano salía gris uniforme y las manzanas no se despegaban del
		-- fondo: un plano en el que no se distingue lo que bloquea de lo que se
		-- puede cruzar no responde a la única pregunta que se le hace.
		r.BackgroundColor3 = if esEdificio then Color3.fromRGB(168, 172, 182) else Color3.fromRGB(38, 42, 50)
		r.BackgroundTransparency = if esEdificio then 0 else 0.55
		r.ZIndex = if esEdificio then 2 else 1
		r.Parent = capa
		pintadas += 1
	end

	-- UN EDIFICIO ES UN RECTÁNGULO, no cien.
	--
	-- La primera versión pintaba pieza a pieza y salían 1716 rectángulos para los
	-- edificios: cada pared, cada ventana y cada alero por su cuenta. El resultado
	-- era una masa gris uniforme en la que no se distinguía una manzana de otra --
	-- justo lo contrario de para lo que sirve un plano. Aquí se pinta el contorno
	-- de cada MODELO (que es como viene agrupada la ciudad: una casa, un bloque),
	-- así que salen decenas de formas limpias en vez de miles de manchas.
	--
	-- Sólo las hojas: un modelo que contiene otros modelos es una agrupación
	-- ("House/Tower" son 1250 piezas), y pintar su contorno taparía el barrio entero
	-- con un solo rectángulo.
	for _, m in ciudad:GetDescendants() do
		if pintadas > 700 then
			break
		end
		if not m:IsA("Model") then
			continue
		end
		local tieneHijosModelo = false
		for _, h in m:GetChildren() do
			if h:IsA("Model") then
				tieneHijosModelo = true
				break
			end
		end
		if tieneHijosModelo then
			continue
		end

		local ok, cf, size = pcall(function()
			return m:GetBoundingBox()
		end)
		if not ok or not cf then
			continue
		end
		if size.Y <= 8 or size.X < MINIMO_LADO or size.Z < MINIMO_LADO then
			continue
		end
		rectangulo(cf.Position.X, cf.Position.Z, size.X, size.Z, true)
	end

	-- Y el suelo: las losas planas y grandes (calles, césped, plazas). Van sueltas,
	-- no agrupadas en modelos, así que éstas sí se leen pieza a pieza.
	for _, p in ciudad:GetDescendants() do
		if pintadas > 1100 then
			break
		end
		if not p:IsA("BasePart") or p.Size.Y > 8 then
			continue
		end
		if p.Size.X < 40 or p.Size.Z < 40 then
			continue
		end
		rectangulo(p.Position.X, p.Position.Z, p.Size.X, p.Size.Z, false)
	end

	return Vector2.new(minX, minZ)
end

function Minimap.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Minimapa"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Parent = gui

	-- ABAJO A LA DERECHA cuando se puede, que es donde lo pidió JJ y donde mejor
	-- está: fuera del camino de la vista y donde la mano ya descansa.
	--
	-- Pero en un dispositivo TÁCTIL esa esquina es el botón de salto de Roblox, que
	-- no podemos mover y que el jugador pulsa sin mirar. Medido en un Galaxy A06
	-- (705x338), un mapa ahí se come el salto y el botón de Recoger. Así que la
	-- posición depende de si hay controles táctiles en pantalla: en el móvil se va
	-- arriba, al único hueco que queda entre la brújula y la columna de acciones.
	-- Dar la razón al que pide y romperle el juego en su dispositivo no es darle la
	-- razón.
	if UserInputService.TouchEnabled then
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.fromScale(0.71, 0.03)
		panel.Size = UDim2.fromScale(0.16, 0.16)
	else
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.fromScale(0.98, 0.97)
		panel.Size = UDim2.fromScale(0.19, 0.26)
	end

	UiKit.redondear(panel, 8)
	UiKit.borde(panel, Color3.fromRGB(96, 94, 102), 1.5, 0.25)

	local tamano = Instance.new("UISizeConstraint")
	tamano.MinSize = Vector2.new(80, 80)
	tamano.MaxSize = Vector2.new(190, 190)
	tamano.Parent = panel

	local proporcion = Instance.new("UIAspectRatioConstraint")
	proporcion.AspectRatio = 1
	proporcion.Parent = panel

	local capa = Instance.new("Frame")
	capa.Name = "Plano"
	capa.AnchorPoint = Vector2.new(0, 0)
	capa.BackgroundTransparency = 1
	capa.Parent = panel
	lienzo = capa

	marco = panel

	local ciudad = workspace:FindFirstChild("Ciudad")
	if ciudad then
		origenMapa = pintarPlano(ciudad, capa)
	end

	-- El jugador SIEMPRE en el centro: es el mapa el que se mueve. Así no hay que
	-- buscarse a uno mismo cada vez que se mira, que es lo último que quieres hacer
	-- mientras corres.
	local yo = punto("Yo", Color3.fromRGB(255, 255, 255), 9, 8)
	yo.Position = UDim2.fromScale(0.5, 0.5)
	yo.Visible = true

	-- A 12 Hz, no en cada fotograma: los puntos se desplazan menos de un píxel
	-- entre fotogramas y esto tiene que ir en un móvil de gama baja.
	local reloj = 0
	RunService.Heartbeat:Connect(function(dt)
		reloj += dt
		if reloj < 1 / 12 then
			return
		end
		reloj = 0
		pcall(Minimap.refrescar)
	end)
end

function Minimap.actualizar(nuevo: any)
	estado = nuevo
end

-- Del mundo al marco, con el jugador en el centro. Devuelve además si el sitio
-- cae DENTRO del trozo visible: lo que se sale no se borra, se pega al borde
-- apuntando hacia dónde queda -- que es lo que hace un radar y lo que un plano
-- recortado, por sí solo, no haría.
local function aPantalla(centro: Vector3, sitio: Vector3, lado: number): (UDim2, boolean)
	local dx = (sitio.X - centro.X) * ESCALA
	local dz = (sitio.Z - centro.Z) * ESCALA
	local limite = lado / 2 - 6
	local dentro = math.abs(dx) <= limite and math.abs(dz) <= limite
	if not dentro then
		local m = math.max(math.abs(dx), math.abs(dz))
		dx, dz = dx / m * limite, dz / m * limite
	end
	return UDim2.new(0.5, dx, 0.5, dz), dentro
end

function Minimap.refrescar()
	local panel = marco
	local capa = lienzo
	if not panel or not capa then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		panel.Visible = false
		return
	end
	panel.Visible = true

	local centro = root.Position
	local lado = panel.AbsoluteSize.X

	-- Se mueve el LIENZO, no sus cientos de hijos: es lo que hace que un plano de
	-- verdad quepa en el presupuesto de un móvil.
	capa.Position = UDim2.new(0.5, -(centro.X - origenMapa.X) * ESCALA, 0.5, -(centro.Z - origenMapa.Y) * ESCALA)

	local casa = punto("Almacen", Palette.ALMACEN, 10, 4)
	casa.Position = (aPantalla(centro, Config.ALMACEN_POS, lado))
	casa.Visible = true

	local rutaActiva = estado and estado.ruta
	for _, ruta in Routes.todas() do
		local p = punto("Destino_" .. ruta.id, Palette.ruta(ruta.id), 9, 5)
		p.Position = (aPantalla(centro, ruta.destino, lado))
		-- El de tu ruta, más grande: es el que persigues y tiene que distinguirse
		-- de un vistazo entre los tres.
		p.Size = if rutaActiva == ruta.id then UDim2.fromOffset(14, 14) else UDim2.fromOffset(8, 8)
		p.Visible = true
	end

	local vistos: { [string]: boolean } = {}

	-- Los refugios, SIEMPRE visibles y pegados al borde si se salen. Es lo que se
	-- busca cuando la cosa se pone fea, y hay que haberlos visto antes de
	-- necesitarlos: cuando los necesitas, ya es tarde para aprendértelos.
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo then
		for _, pieza in mundo:GetChildren() do
			if pieza:IsA("BasePart") and pieza:GetAttribute("refugio") == true then
				local clave = "Refugio_" .. pieza.Name
				local p = punto(clave, Color3.fromRGB(120, 180, 255), 11, 6)
				local donde, dentro = aPantalla(centro, pieza.Position, lado)
				p.Position = donde
				-- Los de fuera de alcance, más pequeños y translúcidos: siguen
				-- diciendo por dónde caen sin competir con los que sí puedes
				-- alcanzar ahora mismo.
				p.Size = if dentro then UDim2.fromOffset(11, 11) else UDim2.fromOffset(7, 7)
				p.BackgroundTransparency = if dentro then 0 else 0.35
				p.Visible = true
				vistos[clave] = true
			end
		end
	end

	-- La gente: TODOS, con carga o sin ella. Saber que hay alguien cerca es media
	-- decisión en la ruta roja, y esconder a los que van vacíos escondería
	-- justamente a los cazadores.
	for _, otro in Players:GetPlayers() do
		if otro ~= Players.LocalPlayer then
			local suyo = otro.Character and otro.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if suyo then
				local clave = "Jugador_" .. otro.UserId
				local p = punto(clave, Color3.fromRGB(240, 220, 120), 9, 7)
				local donde, dentro = aPantalla(centro, suyo.Position, lado)
				p.Position = donde
				p.Visible = dentro
				vistos[clave] = true
			end
		end
	end

	-- Y quien te persigue, que es el dato por el que se mira el mapa cuando aprieta:
	-- no "dónde voy" sino "por dónde vienen".
	local patrullas = workspace:FindFirstChild("Patrullas")
	if patrullas then
		for i, agente in patrullas:GetChildren() do
			local clave = "Patrulla_" .. i
			local p = punto(clave, Color3.fromRGB(255, 110, 100), 9, 7)
			local donde, dentro = aPantalla(centro, agente:GetPivot().Position, lado)
			p.Position = donde
			p.Visible = dentro
			vistos[clave] = true
		end
	end

	-- Los que ya no están se apagan, no se destruyen: crear y borrar Frames doce
	-- veces por segundo es la forma más fácil de que un minimapa cueste más que el
	-- juego que representa.
	for clave, p in puntos do
		local esVolatil = string.sub(clave, 1, 8) == "Jugador_"
			or string.sub(clave, 1, 9) == "Patrulla_"
			or string.sub(clave, 1, 8) == "Refugio_"
		if esVolatil and not vistos[clave] then
			p.Visible = false
		end
	end
end

return Minimap
