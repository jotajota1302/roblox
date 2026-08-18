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
	for i, poste in postes do
		local panel = Instance.new("Part")
		panel.Name = "Valla" .. i
		panel.Size = Vector3.new(poste.ancho, Config.RECINTO_ALTO, 1.5)
		-- Hundida 6 studs: el suelo de la ciudad no es una mesa, y un panel apoyado
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
		panel.Material = Enum.Material.ForceField
		panel.Transparency = 0.45
		panel.CastShadow = false
		panel.Parent = f

		-- El motivo, escrito en la propia valla y sólo en una de cada seis: es lo
		-- que convierte un obstáculo en una instrucción. Repetirlo en las
		-- veinticuatro sería un anillo de carteles ilegible.
		if i % 2 == 1 then
			local cartel = Instance.new("BillboardGui")
			cartel.Name = "Cartel"
			cartel.Size = UDim2.fromScale(22, 4)
			cartel.StudsOffsetWorldSpace = Vector3.new(0, Config.RECINTO_ALTO / 2 + 2, 0)
			cartel.AlwaysOnTop = false
			cartel.MaxDistance = 260
			cartel.Adornee = panel
			cartel.Parent = panel

			local texto = Instance.new("TextLabel")
			texto.Size = UDim2.fromScale(1, 1)
			texto.BackgroundTransparency = 1
			texto.TextColor3 = COLOR
			texto.TextStrokeTransparency = 0.25
			texto.TextScaled = true
			texto.Font = Enum.Font.GothamBold
			texto.Text = "PICK A ROUTE TO LEAVE"
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
