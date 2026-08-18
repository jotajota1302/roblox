--!strict
--[[
	Garage.luau — tus vehículos, aparcados en el taller.

	MISMO PATRÓN QUE EL MUELLE DEL ALMACÉN (Stock.luau) y por el mismo motivo: lo
	que hay en las plazas es de CADA jugador, así que un garaje construido en el
	servidor le enseñaría a todo el mundo la moto de uno solo. El servidor publica
	dónde están las plazas (atributos de la losa) y el cliente dibuja lo suyo.

	POR QUÉ EXISTE. Hasta ahora comprar SUSTITUÍA: te quedabas siempre con el
	último y el anterior desaparecía. Eso tenía sentido cuando un vehículo era sólo
	"más capacidad" -- el nuevo era mejor en todo. Con la regla de la calzada dejó
	de serlo: la furgoneta lleva un piano pero no puede salirse del asfalto, y el
	patinete entra en cualquier callejón. Ya no hay un mejor, hay un mejor PARA
	ESTE VIAJE, y para que eso sea una decisión hay que poder verlos y elegir.

	Se dibujan con el mismo respaldo de piezas que usa Ride cuando la malla no
	carga: aquí no se pide la malla al servidor de assets porque son hasta cuatro
	modelos y esto se redibuja cada vez que compras algo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Roads = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Roads"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))

local Garage = {}
local carpeta: Folder? = nil
local dibujado = ""

local function plazas(taller: BasePart): { Vector3 }
	local total = taller:GetAttribute("plazas")
	if typeof(total) ~= "number" then
		return {}
	end
	local lista: { Vector3 } = {}
	for i = 1, total do
		local p = taller:GetAttribute("plaza" .. i)
		if typeof(p) == "Vector3" then
			table.insert(lista, p)
		end
	end
	return lista
end

-- El taller más cercano, que es el único que hace falta dibujar: los otros están
-- a media ciudad y sus plazas no se ven.
local function tallerCercano(mundo: Instance?): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not mundo then
		return nil
	end
	local mejor, mejorDistancia = nil, 260
	for _, pieza in mundo:GetChildren() do
		-- POR EL ATRIBUTO, no por el nombre: el edificio del concesionario está
		-- hecho de piezas que también empiezan por "Taller" (TallerTecho,
		-- TallerLuz...), y filtrando por nombre se elegía una pared -- que no tiene
		-- plazas, así que el garaje no se dibujaba nunca.
		if pieza:IsA("BasePart") and pieza:GetAttribute("plazas") ~= nil then
			local d = (root.Position - pieza.Position).Magnitude
			if d < mejorDistancia then
				mejor, mejorDistancia = pieza, d
			end
		end
	end
	return mejor
end

function Garage.actualizar(mundo: Instance?, estado: any)
	local taller = tallerCercano(mundo)
	local garaje = (estado and estado.garaje) or {}
	local activo = (estado and estado.vehiculo) or Vehicles.A_PIE

	-- La huella incluye el taller: al cambiar de taller hay que redibujar en el
	-- nuevo aunque tengas los mismos vehículos.
	local huella = tostring(taller) .. "|" .. activo
	for _, id in garaje do
		huella ..= "," .. id
	end
	if huella == dibujado then
		return
	end
	dibujado = huella

	if carpeta then
		carpeta:Destroy()
		carpeta = nil
	end
	if not taller or #garaje == 0 then
		return
	end

	local f = Instance.new("Folder")
	f.Name = "MiGaraje"
	f.Parent = workspace
	carpeta = f

	local sitios = plazas(taller)
	for i = 1, math.min(#garaje, #sitios) do
		local id = garaje[i]
		local ok, def = pcall(Vehicles.get, id)
		if ok and def then
			local esActivo = id == activo

			local plaza = Instance.new("Part")
			plaza.Name = "Plaza" .. i
			plaza.Size = Vector3.new(9, 0.3, 9)
			plaza.Position = sitios[i]
			plaza.Anchored = true
			plaza.CanCollide = false
			plaza.Material = Enum.Material.SmoothPlastic
			-- La plaza del que llevas puesto se enciende. Es la única forma de saber
			-- cuál está fuera sin leer nada.
			plaza.Color = if esActivo then Palette.TALLER else Color3.fromRGB(70, 70, 76)
			plaza.Parent = f

			-- Un bulto con la forma aproximada del vehículo. No se pide la malla:
			-- esto se redibuja cada vez que compras, y cuatro peticiones al servidor
			-- de assets por redibujado es tiempo de carga por gusto.
			local bulto = Instance.new("Part")
			bulto.Name = "Bulto" .. i
			-- El tamaño sale de la capacidad: se ve de un vistazo cuál lleva más.
			local largo = 3 + math.min(def.capacidad, 26) * 0.28
			bulto.Size = Vector3.new(2.4, 2 + def.capacidad * 0.06, largo)
			bulto.Position = sitios[i] + Vector3.new(0, bulto.Size.Y / 2 + 0.3, 0)
			bulto.Anchored = true
			bulto.CanCollide = false
			bulto.Material = Enum.Material.Metal
			bulto.Color = if Roads.exigeCalzada(id) then Color3.fromRGB(96, 116, 150) else Color3.fromRGB(120, 150, 110)
			bulto.Parent = f

			-- La ficha: nombre, huecos y --lo que de verdad decide-- si puede salirse
			-- del asfalto. Sin ese dato, elegir entre la furgoneta y el patinete es
			-- elegir por el precio, que es justo lo que el garaje viene a cambiar.
			local cartel = Instance.new("BillboardGui")
			cartel.Name = "Ficha"
			cartel.Size = UDim2.fromScale(9, 3)
			cartel.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
			cartel.AlwaysOnTop = false
			cartel.MaxDistance = 90
			cartel.Adornee = bulto
			cartel.Parent = bulto

			local texto = Instance.new("TextLabel")
			texto.Size = UDim2.fromScale(1, 1)
			texto.BackgroundTransparency = 1
			texto.TextColor3 = if esActivo then Color3.fromRGB(255, 240, 200) else Color3.fromRGB(190, 192, 200)
			texto.TextStrokeTransparency = 0.35
			texto.TextScaled = true
			texto.Font = Enum.Font.GothamBold
			texto.Text = string.format(
				"%s%s\n%d huecos  ·  %s",
				def.nombre,
				if esActivo then "  (fuera)" else "",
				def.capacidad,
				if Roads.exigeCalzada(id) then "sólo calle" else "por todas partes"
			)
			texto.Parent = cartel

			local aviso = Instance.new("ProximityPrompt")
			aviso.Name = "PromptGaraje"
			aviso.ActionText = if esActivo then "Guardar" else "Sacar"
			aviso.ObjectText = def.nombre
			aviso.MaxActivationDistance = 10
			aviso.HoldDuration = 0
			aviso.RequiresLineOfSight = false
			-- El id viaja con la pieza: es lo que se manda al servidor. El cliente no
			-- decide nada, sólo devuelve lo que le dieron.
			aviso:SetAttribute("vehiculo", id)
			aviso.Parent = bulto
		end
	end
end

return Garage
