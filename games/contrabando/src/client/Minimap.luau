--!strict
--[[
	Minimap.luau — la ciudad vista desde arriba, con lo que importa encima.

	Es el compañero de Compass: la brújula dice hacia dónde, y esto dice qué hay
	alrededor. En una ciudad de 1.500 studs eso no es comodidad -- es lo que separa
	decidir de deambular. La brújula sola te lleva en línea recta contra un
	edificio; el mapa te enseña que hay que rodear, y quién viene.

	DÓNDE VA. JJ lo pidió abajo a la derecha, y ahí no puede ir: en móvil esa
	esquina es el botón de salto de Roblox, que no podemos mover y que el jugador
	pulsa sin mirar. Este proyecto ya pagó ese error una vez -- el botón de comprar
	pisaba el de salto por seis píxeles y en pantalla no se veía. Va arriba a la
	derecha, que es el otro hueco libre, por encima de la columna de acciones.

	SE DIBUJA CON FRAMES, no con una cámara ni una imagen. Una textura de mapa sería
	un asset, y un asset no carga con el place sin publicar: la misma trampa que nos
	dejó sin avatar y sin decorado. Unos cuantos rectángulos se dibujan siempre.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

-- Cuánto mundo cabe en el mapa, medido desde el jugador. No es todo el mapa a la
-- vez a propósito: una ciudad entera en 130 píxeles convierte cada cosa en un
-- punto de un píxel que no se puede leer. A 700 se ve el barrio y se distingue
-- quién está cerca, que es la pregunta que se hace mientras corres.
local ALCANCE = 700

local Minimap = {}
local marco: Frame? = nil
local capa: Frame? = nil
local puntos: { [string]: Frame } = {}
local estado: any = nil

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
	f.Parent = capa
	UiKit.redondear(f, tamano)
	puntos[nombre] = f
	return f
end

function Minimap.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Minimapa"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	-- Entre la brújula y la columna de botones, no pegado al borde derecho.
	--
	-- Pegado al borde SÍ cabía en un portátil y NO en un móvil: medido en un Galaxy
	-- A06 apaisado (705x338), un mapa de 96 px en la esquina se comía el botón de
	-- Recoger. Es el mismo error que ya costó el botón de comprar contra el de
	-- salto, y la lección también: en la pantalla grande no se ve, hay que calcular
	-- las cajas con las reglas reales (Scale más UISizeConstraint) y compararlas
	-- todas contra todas.
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.71, 0.03)
	panel.Size = UDim2.fromScale(0.16, 0.16)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true -- lo que cae fuera del alcance no se pinta encima del HUD
	panel.Parent = gui
	UiKit.redondear(panel, 8)
	UiKit.borde(panel, Color3.fromRGB(90, 88, 96), 1.5, 0.3)

	local tamano = Instance.new("UISizeConstraint")
	tamano.MinSize = Vector2.new(80, 80)
	tamano.MaxSize = Vector2.new(150, 150)
	tamano.Parent = panel

	-- Cuadrado: el mapa se lee mal si se estira. Se fija por la altura, que es la
	-- dimensión escasa en un móvil apaisado.
	local proporcion = Instance.new("UIAspectRatioConstraint")
	proporcion.AspectRatio = 1
	proporcion.Parent = panel

	local lienzo = Instance.new("Frame")
	lienzo.Name = "Lienzo"
	lienzo.Size = UDim2.fromScale(1, 1)
	lienzo.BackgroundTransparency = 1
	lienzo.Parent = panel
	capa = lienzo

	marco = panel

	-- El jugador siempre en el centro: es el mapa el que se mueve. Así no hay que
	-- buscarse a uno mismo cada vez que se mira.
	local yo = punto("Yo", Color3.fromRGB(255, 255, 255), 8, 6)
	yo.Position = UDim2.fromScale(0.5, 0.5)
	yo.Visible = true

	-- A 12 Hz, no en cada fotograma. Refrescar el mapa 60 veces por segundo significa
	-- recorrer todos los jugadores y todas las patrullas 60 veces por segundo para
	-- mover unos puntos que se desplazan menos de un píxel entre fotogramas: no se
	-- ve, y este juego tiene que ir en un móvil de gama baja. A 12 el movimiento
	-- sigue leyéndose fluido y el trabajo se divide por cinco.
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

-- Del mundo al mapa. El jugador va al centro y el norte del mundo (-Z) arriba: es
-- un mapa de mesa, no una vista de cámara. Gira menos la cabeza que uno que rote
-- con la mirada, y para "¿dónde está el almacén?" es más rápido.
local function aPantalla(centro: Vector3, sitio: Vector3): (UDim2, boolean)
	local dx = (sitio.X - centro.X) / ALCANCE
	local dz = (sitio.Z - centro.Z) / ALCANCE
	local dentro = math.abs(dx) <= 0.5 and math.abs(dz) <= 0.5
	-- Recortado al borde cuando se sale: un objetivo fuera de alcance sigue
	-- diciendo por dónde cae, que es más útil que desaparecer.
	local m = math.max(math.abs(dx), math.abs(dz))
	if m > 0.5 then
		dx, dz = dx / (m * 2), dz / (m * 2)
	end
	return UDim2.fromScale(0.5 + dx, 0.5 + dz), dentro
end

function Minimap.refrescar()
	local panel = marco
	if not panel then
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

	-- El almacén: es a donde se vuelve, y por eso está siempre.
	local casa = punto("Almacen", Palette.ALMACEN, 9, 3)
	local pos, _ = aPantalla(centro, Config.ALMACEN_POS)
	casa.Position = pos
	casa.Visible = true

	-- Los tres destinos, cada uno de su color. El de tu ruta, más grande: es el que
	-- estás persiguiendo y tiene que distinguirse de un vistazo entre los tres.
	local rutaActiva = estado and estado.ruta
	for _, ruta in Routes.todas() do
		local p = punto("Destino_" .. ruta.id, Palette.ruta(ruta.id), 9, 4)
		local donde, _ = aPantalla(centro, ruta.destino)
		p.Position = donde
		p.Size = if rutaActiva == ruta.id then UDim2.fromOffset(13, 13) else UDim2.fromOffset(8, 8)
		p.Visible = true
	end

	-- Los refugios. Es lo que se busca en el mapa cuando la cosa se pone fea, así
	-- que van SIEMPRE visibles y no sólo con calor: hay que haberlos visto antes de
	-- necesitarlos, o cuando los necesites será tarde para aprenderte dónde están.
	-- Se leen del mundo en vez de recibirlos por el estado -- son geometría fija y
	-- no cambian por jugador.
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo then
		for _, pieza in mundo:GetChildren() do
			if pieza:IsA("BasePart") and pieza:GetAttribute("refugio") == true then
				local p = punto("Refugio_" .. pieza.Name, Color3.fromRGB(120, 180, 255), 10, 3)
				local donde = aPantalla(centro, pieza.Position)
				p.Position = donde
				p.Visible = true
			end
		end
	end

	-- La gente. Se dibuja a TODO EL MUNDO, con carga o sin ella: saber que hay
	-- alguien cerca es media decisión en la ruta roja, y ocultar a los que van
	-- vacíos escondería justamente a los cazadores.
	local vistos: { [string]: boolean } = {}
	for _, otro in Players:GetPlayers() do
		if otro ~= Players.LocalPlayer then
			local suyo = otro.Character and otro.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if suyo then
				local clave = "Jugador_" .. otro.UserId
				local p = punto(clave, Color3.fromRGB(240, 220, 120), 8, 5)
				local donde, dentro = aPantalla(centro, suyo.Position)
				p.Position = donde
				p.Visible = dentro
				vistos[clave] = true
			end
		end
	end

	-- Y la policía que te busca. Es el dato por el que se mira el mapa cuando la
	-- cosa se pone fea: no "dónde voy" sino "por dónde vienen".
	local patrullas = workspace:FindFirstChild("Patrullas")
	if patrullas then
		for i, agente in patrullas:GetChildren() do
			local clave = "Patrulla_" .. i
			local p = punto(clave, Color3.fromRGB(110, 170, 255), 8, 5)
			local donde, dentro = aPantalla(centro, agente:GetPivot().Position)
			p.Position = donde
			p.Visible = dentro
			vistos[clave] = true
		end
	end

	-- Los que ya no están se apagan, no se destruyen: crear y borrar Frames varias
	-- veces por segundo es la forma más fácil de que un minimapa cueste más que el
	-- juego.
	for clave, p in puntos do
		if (string.sub(clave, 1, 8) == "Jugador_" or string.sub(clave, 1, 9) == "Patrulla_") and not vistos[clave] then
			p.Visible = false
		end
	end
end

return Minimap
