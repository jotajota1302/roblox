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
local dibujadas = -1

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

-- `cuantas` es lo que hay en el almacén ahora mismo. Se redibuja sólo cuando el
-- número cambia: reconstruir diez piezas cinco veces por segundo es tirar
-- rendimiento en un juego que tiene que ir en un móvil de gama baja.
function Stock.actualizar(almacen: BasePart?, cuantas: number)
	if not almacen then
		return
	end
	if cuantas == dibujadas then
		return
	end
	dibujadas = cuantas

	if carpeta then
		carpeta:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "CajasDelMuelle"
	f.Parent = workspace
	carpeta = f

	local lista = sitios(almacen)
	for i = 1, math.min(cuantas, #lista) do
		local caja = Instance.new("Part")
		caja.Name = "CajaAlmacen" .. i
		-- 3 studs: poco menos de la mitad de la altura de un personaje. A 4,4 eran
		-- "excesivamente grandes" (JJ, jugando) -- diez de ésas llenan la nave y
		-- tapan al propio jugador, así que la pila deja de leerse como un contador.
		caja.Size = Vector3.new(3, 3, 3)
		caja.Position = lista[i]
		-- Todas del color de la común: la rareza de lo que hay guardado NO se sabe
		-- hasta recogerlo (la tirada la hace el servidor al reclamar), y pintarlas
		-- de colores aquí prometería un botín que nadie ha decidido todavía.
		caja.Color = Rarity.color("comun")
		caja.Material = Enum.Material.WoodPlanks
		caja.Anchored = true
		-- Atravesables: están en el muelle, que es justo por donde se anda para
		-- llegar al botón de recoger. Una pila sólida creciendo delante de la puerta
		-- acabaría encerrando al jugador en su propio almacén.
		caja.CanCollide = false
		caja.CFrame = CFrame.new(lista[i]) * CFrame.Angles(0, math.rad(i * 23), 0)
		caja.Parent = f
	end
end

return Stock
