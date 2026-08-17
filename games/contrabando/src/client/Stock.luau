--!strict
--[[
	Stock.luau — las cajas del muelle SON el contador del almacén.

	Antes eran decoración fija: siempre las mismas tres, produjera lo que produjera
	el almacén. El HUD decía "6/10" y en el suelo no había nada que correspondiera a
	ese 6, así que el número no significaba nada -- y el almacén es EL MOTIVO PARA
	VOLVER. Ver la mercancía acumulándose es lo que hace que volver tenga sentido;
	una cifra en una esquina de la pantalla no lo consigue.

	SE DIBUJAN EN EL CLIENTE, y esa es la decisión de fondo: el contador del almacén
	es de cada jugador (así lo exige "el almacén no es asaltable"), de modo que una
	pila construida en el servidor sería la misma para todos y le mentiría a todo el
	mundo menos a uno. Aquí cada jugador ve exactamente lo que tiene.

	Las posiciones las publica el servidor como atributos de la losa (CityBuilder):
	con dos copias de las coordenadas, el día que alguien mueva el muelle las cajas
	se quedarían flotando donde estaba antes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Goods"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

-- Los tonos de los detalles. Van aquí y no repartidos por los `if` para que
-- cambiar el aspecto de la mercancía sea tocar cuatro líneas y no buscarlas.
local MADERA_OSCURA = Color3.fromRGB(96, 72, 44)
local METAL_OSCURO = Color3.fromRGB(58, 62, 70)
local DORADO = Color3.fromRGB(212, 172, 82)

local Stock = {}
local carpeta: Folder? = nil
local dibujadas = ""

local function sitios(almacen: BasePart): { Vector3 }
	local total = almacen:GetAttribute("muelleSitios")
	if typeof(total) ~= "number" then
		return {}
	end
	local lista: { Vector3 } = {}
	for i = 1, total do
		local p = almacen:GetAttribute("muelle" .. i)
		if typeof(p) == "Vector3" then
			table.insert(lista, p)
		end
	end
	return lista
end

-- `piezas` es lo que hay guardado, cada una con su rareza ya decidida por el
-- servidor. Se redibuja sólo cuando cambia la lista: reconstruir diez modelos
-- cinco veces por segundo es tirar rendimiento en un juego que tiene que ir en un
-- móvil de gama baja.
function Stock.actualizar(almacen: BasePart?, piezas: { { rareza: string, objeto: string? } }?)
	if not almacen then
		return
	end
	local lote = piezas or {}
	-- La huella de la lista, no sólo su tamaño: cambiar una urna por un cajón sin
	-- cambiar la cuenta tiene que repintarse igual, o el jugador estaría eligiendo
	-- sobre un dibujo viejo.
	local huella = ""
	for _, p in lote do
		huella ..= p.rareza .. ":" .. tostring(p.objeto) .. ","
	end
	if huella == dibujadas then
		return
	end
	dibujadas = huella

	if carpeta then
		carpeta:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "CajasDelMuelle"
	f.Parent = workspace
	carpeta = f

	local lista = sitios(almacen)
	for i = 1, math.min(#lote, #lista) do
		local rareza = lote[i].rareza
		local objeto = lote[i].objeto
		local aspecto = Rarity.aspecto(rareza)

		local caja = Instance.new("Part")
		caja.Name = "CajaAlmacen" .. i
		-- 3 studs de base: poco menos de la mitad de un personaje. A 4,4 eran
		-- "excesivamente grandes" (JJ, jugando) -- diez de ésas llenan la nave y
		-- tapan al propio jugador, así que la pila deja de leerse como un contador.
		-- Cada rareza deforma esa base con su escala: la urna sale alta y estrecha,
		-- el maletín plano y ancho. Se distinguen de lejos, antes de leer nada.
		-- La medida real del OBJETO, no una escala de la rareza: un sofá es ancho y
		-- bajo, una estatua alta y estrecha, y una nevera no cabe donde cabe un
		-- sobre. Que se vea que no cabe es el argumento de venta del vehículo.
		-- A escala 1,6: un personaje mide 5 studs, así que a tamaño 1 un sobre de 0,4
		-- era una mota en el suelo que no se veía ni de cerca. Con esto lo pequeño
		-- sigue siendo pequeño y lo enorme ocupa media nave -- que es justo lo que
		-- tiene que transmitir: que eso no lo mueves sin un vehículo.
		caja.Size = Goods.medida(objeto, 1.6)
		caja.Position = lista[i]
		caja.Color = Rarity.color(rareza)
		caja.Material = Goods.aspecto(objeto).material
		caja.Anchored = true
		-- Atravesables: están en el muelle, que es justo por donde se anda. Una pila
		-- sólida creciendo dentro de la nave acabaría encerrando al jugador en su
		-- propio almacén.
		caja.CanCollide = false
		caja.CFrame = CFrame.new(lista[i]) * CFrame.Angles(0, math.rad(i * 23), 0)
		-- El índice viaja con la pieza: es lo que se manda al servidor para pedir
		-- ÉSTA y no otra.
		caja:SetAttribute("indice", i)
		caja.Parent = f

		-- Y su aviso de recogida, en la pieza. Sustituye al botón fijo de la
		-- esquina, que no decía cuál de las diez ibas a coger.
		local aviso = Instance.new("ProximityPrompt")
		aviso.Name = "PromptCaja"
		aviso.ActionText = "Cargar"
		aviso.ObjectText = Goods.etiqueta(objeto, rareza)
		aviso.MaxActivationDistance = 9
		aviso.HoldDuration = 0
		aviso.RequiresLineOfSight = false
		aviso.Parent = caja

		-- Los detalles que separan un objeto de un cubo. Son dos piezas por objeto y
		-- cambian por completo lo que parece: "el tema objetos que se llevan, que
		-- son todo cajas" (JJ). Van sin colisión y ancladas a la pieza madre.
		local function adorno(nombre: string, tamano: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
			local d = Instance.new("Part")
			d.Name = nombre
			d.Size = tamano
			d.Color = color
			d.Material = material
			d.Anchored = true
			d.CanCollide = false
			d.CFrame = caja.CFrame * CFrame.new(offset)
			d.Parent = caja
			return d
		end

		local lado = caja.Size
		local forma = (objeto and Goods.get(objeto) and (Goods.get(objeto) :: any).forma) or "cajon"
		if forma == "cajon" or forma == "baul" then
			-- Flejes cruzados: dos listones y el cubo pasa a ser un cajón.
			adorno(
				"Fleje1",
				Vector3.new(lado.X + 0.1, 0.45, lado.Z + 0.1),
				Vector3.new(0, lado.Y * 0.22, 0),
				MADERA_OSCURA,
				Enum.Material.Wood
			)
			adorno(
				"Fleje2",
				Vector3.new(lado.X + 0.1, 0.45, lado.Z + 0.1),
				Vector3.new(0, -lado.Y * 0.22, 0),
				MADERA_OSCURA,
				Enum.Material.Wood
			)
		elseif forma == "maletin" or forma == "joyero" then
			-- Asa arriba y cierre delante: se lee como maletín al instante.
			adorno(
				"Asa",
				Vector3.new(lado.X * 0.4, 0.5, 0.5),
				Vector3.new(0, lado.Y * 0.6, 0),
				METAL_OSCURO,
				Enum.Material.Metal
			)
			adorno(
				"Cierre",
				Vector3.new(lado.X * 0.9, 0.35, 0.2),
				Vector3.new(0, 0, lado.Z * 0.5),
				METAL_OSCURO,
				Enum.Material.Metal
			)
		elseif forma == "nevera" or forma == "television" then
			-- Refuerzos en las esquinas: la silueta de algo blindado.
			for k, e in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
				adorno(
					"Refuerzo" .. k,
					Vector3.new(0.6, lado.Y + 0.1, 0.6),
					Vector3.new(e[1] * lado.X * 0.45, 0, e[2] * lado.Z * 0.45),
					METAL_OSCURO,
					Enum.Material.Metal
				)
			end
		elseif forma == "urna" or forma == "estatua" then
			-- Base y tapa: una urna es lo único que no debería parecer una caja.
			adorno(
				"Base",
				Vector3.new(lado.X * 1.25, 0.5, lado.Z * 1.25),
				Vector3.new(0, -lado.Y * 0.5, 0),
				DORADO,
				Enum.Material.Metal
			)
			adorno(
				"Tapa",
				Vector3.new(lado.X * 0.7, lado.Y * 0.25, lado.Z * 0.7),
				Vector3.new(0, lado.Y * 0.6, 0),
				DORADO,
				Enum.Material.Metal
			)
		end

		-- Qué es y cuánto multiplica, escrito encima. Es el dato de la decisión: sin
		-- él, elegir entre la urna y tres cajones sería elegir por la forma, a
		-- ciegas, y volvería a no haber nada que decidir.
		local cartel = Instance.new("BillboardGui")
		cartel.Name = "Etiqueta"
		cartel.Size = UDim2.fromScale(8, 1.3)
		cartel.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
		cartel.AlwaysOnTop = true
		cartel.MaxDistance = 70
		cartel.Adornee = caja
		cartel.Parent = caja

		local texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.TextColor3 = Rarity.color(rareza)
		texto.TextStrokeTransparency = 0.3
		texto.TextScaled = true
		texto.Font = Enum.Font.GothamBold
		texto.Text = Goods.etiqueta(objeto, rareza)
		texto.Parent = cartel
	end
end

return Stock
