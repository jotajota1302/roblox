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

local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

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
function Stock.actualizar(almacen: BasePart?, piezas: { { rareza: string } }?)
	if not almacen then
		return
	end
	local lote = piezas or {}
	-- La huella de la lista, no sólo su tamaño: cambiar una urna por un cajón sin
	-- cambiar la cuenta tiene que repintarse igual, o el jugador estaría eligiendo
	-- sobre un dibujo viejo.
	local huella = ""
	for _, p in lote do
		huella ..= p.rareza .. ","
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
		local aspecto = Rarity.aspecto(rareza)

		local caja = Instance.new("Part")
		caja.Name = "CajaAlmacen" .. i
		-- 3 studs de base: poco menos de la mitad de un personaje. A 4,4 eran
		-- "excesivamente grandes" (JJ, jugando) -- diez de ésas llenan la nave y
		-- tapan al propio jugador, así que la pila deja de leerse como un contador.
		-- Cada rareza deforma esa base con su escala: la urna sale alta y estrecha,
		-- el maletín plano y ancho. Se distinguen de lejos, antes de leer nada.
		caja.Size = Vector3.new(3, 3, 3) * aspecto.escala
		caja.Position = lista[i]
		caja.Color = Rarity.color(rareza)
		caja.Material = aspecto.material
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
		texto.Text = Rarity.etiqueta(rareza)
		texto.Parent = cartel
	end
end

return Stock
