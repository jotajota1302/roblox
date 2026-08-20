--!strict
--[[
	Gate.luau — la valla del recinto, dibujada.

	Las cuentas están en Shared.Perimeter (puro y probado); aquí sólo se pinta lo
	que aquéllas dicen.

	SE CONSTRUYE EN EL CLIENTE, y no es un atajo: la valla depende del estado de
	CADA jugador -- uno con carga y sin destino la tiene cerrada, el de al lado con
	su ruta ya elegida no. Una valla del servidor sería la misma para todos y
	frenaría precisamente a quien no debe. Como el personaje se simula en su propio
	cliente, una pieza local con CanCollide frena de verdad.

	Y no se destruye al bajarla: se aparta. Veinticuatro piezas creadas y
	destruidas cada vez que se recoge o se entrega es trabajo de sobra en un móvil
	de gama baja, para un decorado que va a volver dentro de treinta segundos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Perimeter = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Perimeter"))
local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

local Gate = {}
local carpeta: Folder? = nil
local levantada = false

-- Ámbar, el mismo color con el que el juego avisa de todo lo demás (el zurrón
-- lleno, el aviso de salir sin destino). Rojo sería "peligro" y aquí no hay
-- ninguno: es una puerta cerrada, no una amenaza.
local COLOR = Color3.fromRGB(232, 176, 64)

function Gate.build()
	local f = Instance.new("Folder")
	f.Name = "RecintoAlmacen"

	local postes = Perimeter.postes(Config.RECINTO_PANELES)
	-- CUANTOS CARTELES. Uno por lado, repartidos: con la valla en anillo, "uno de
	-- cada seis paneles" daba nueve carteles en fila por el lado largo y ninguno por
	-- el corto. Se reparten contando cuantos paneles hay y poniendo cuatro.
	local cadaCartel = math.max(1, math.floor(#postes / 4))

	for i, poste in postes do
		local panel = Instance.new("Part")
		panel.Name = "Valla" .. i
		panel.Size = Vector3.new(poste.ancho, Config.RECINTO_ALTO, 1.5)
		-- Hundida 3 studs: el suelo de la ciudad no es una mesa, y un panel apoyado
		-- justo en la cota del almacén dejaría por debajo una rendija a la altura
		-- de los tobillos en cuanto la calle baje un poco.
		panel.CFrame = CFrame.new(poste.posicion + Vector3.new(0, Config.RECINTO_ALTO / 2 - 3, 0))
			* CFrame.Angles(0, math.rad(poste.giro), 0)
		panel.Anchored = true
		panel.CanCollide = true
		panel.Color = COLOR
		-- ForceField: se ve que es una barrera y no un muro, y sobre todo DEJA VER
		-- lo que hay detrás. Un muro opaco de 26 studs alrededor del almacén
		-- taparía media ciudad y convertiría el recinto en un pozo.
		--
		-- MENOS TRANSPARENTE que antes (0,45 -> 0,25). Con el anillo hay barrera en
		-- los cuatro lados y por tanto el doble de razones para que no tape; pero una
		-- barrera que no se ve no informa de nada, y "que sea mucho mas evidente" es
		-- literalmente lo que se pidio. A 0,25 se lee desde el patio entero y sigue
		-- dejando ver la ciudad al otro lado.
		panel.Material = Enum.Material.ForceField
		panel.Transparency = 0.25
		panel.CastShadow = false
		panel.Parent = f

		-- EL REMATE DE ARRIBA, que es lo que de verdad la hace evidente. Un
		-- ForceField es un tinte sin bordes: se mira a traves de el y el ojo lo
		-- descarta como niebla. Una linea neon continua a lo alto del anillo le pone
		-- un CANTO, y un canto se lee como un limite -- es la diferencia entre un
		-- humo de color y una tapia.
		local remate = Instance.new("Part")
		remate.Name = "Remate" .. i
		remate.Size = Vector3.new(poste.ancho, 1.2, 2.6)
		remate.CFrame = CFrame.new(poste.posicion + Vector3.new(0, Config.RECINTO_ALTO - 3, 0))
			* CFrame.Angles(0, math.rad(poste.giro), 0)
		remate.Anchored = true
		remate.CanCollide = false
		remate.CastShadow = false
		remate.Color = COLOR
		remate.Material = Enum.Material.Neon
		remate.Parent = f

		-- Y UN ZOCALO abajo, por el mismo motivo del remate y por uno mas: marca
		-- EN EL SUELO por donde pasa la linea, que es lo que se mira cuando vas
		-- corriendo hacia ella.
		local zocalo = Instance.new("Part")
		zocalo.Name = "Zocalo" .. i
		zocalo.Size = Vector3.new(poste.ancho, 0.6, 3.4)
		zocalo.CFrame = CFrame.new(poste.posicion + Vector3.new(0, -2.4, 0)) * CFrame.Angles(0, math.rad(poste.giro), 0)
		zocalo.Anchored = true
		zocalo.CanCollide = false
		zocalo.CastShadow = false
		zocalo.Color = COLOR
		zocalo.Material = Enum.Material.Neon
		zocalo.Parent = f

		-- El motivo, escrito en la propia valla. CUATRO, uno por lado: mires hacia
		-- donde mires al chocar con ella, hay un cartel que dice por que.
		if i % cadaCartel == 1 or cadaCartel == 1 then
			local cartel = Instance.new("BillboardGui")
			cartel.Name = "Cartel"
			cartel.Size = UDim2.fromScale(22, 4)
			cartel.StudsOffsetWorldSpace = Vector3.new(0, Config.RECINTO_ALTO / 2 + 2, 0)
			cartel.AlwaysOnTop = false
			cartel.MaxDistance = 140
			cartel.Adornee = panel
			cartel.Parent = panel

			local texto = Instance.new("TextLabel")
			texto.Size = UDim2.fromScale(1, 1)
			texto.BackgroundTransparency = 1
			texto.TextColor3 = COLOR
			texto.TextStrokeTransparency = 0.25
			texto.TextScaled = true
			texto.Font = Enum.Font.GothamBold
			texto.Text = Strings.get("GATE_PICK_ROUTE")
			texto.Parent = cartel
		end
	end

	carpeta = f
end

-- Levantar o bajar. Devuelve true si acaba de cambiar, para que quien llama pueda
-- avisar UNA vez en vez de en cada vuelta del bucle.
function Gate.mostrar(activa: boolean): boolean
	if not carpeta or activa == levantada then
		return false
	end
	levantada = activa
	carpeta.Parent = if activa then workspace else nil
	return true
end

function Gate.estaLevantada(): boolean
	return levantada
end

return Gate
