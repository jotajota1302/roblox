
local cache: any = {}
local nodo
function nodo(prefijo: string, padre: any, nombre: string): any
	local self: any
	self = setmetatable({}, {
		__index = function(_, k)
			if k == "Parent" then
				return padre
			end
			if k == "Name" then
				return nombre
			end
			local clave = if prefijo == "" then k else prefijo .. "/" .. k
			local fuente = FUENTES[clave]
			if fuente then
				if cache[clave] == nil then
					cache[clave] = fuente(nodo(prefijo, self, k))
				end
				return cache[clave]
			end
			return nodo(clave, self, k)
		end,
	})
	return self
end

local shared = nodo("", nil, "Shared")
local servidor = nodo("server", nil, "Server")
local ReplicatedStorage: any = setmetatable({}, {
	__index = function(_, k)
		if k == "Shared" then
			return shared
		end
		return nil
	end,
})
game = setmetatable({}, {
	__index = function(_, k)
		if k == "ReplicatedStorage" then
			return ReplicatedStorage
		end
		if k == "ServerScriptService" then
			return setmetatable({}, {
				__index = function(_, s)
					if s == "Server" then
						return servidor
					end
					return nil
				end,
			})
		end
		if k == "GetService" then
			return function()
				error("sin servicios")
			end
		end
		return nil
	end,
})

local Grid = shared.Grid
local Districts = shared.Districts
local MapBuilder = servidor.MapBuilder

local raiz = Instance.new("Folder")
local reloj = os.clock()
local ciudad = MapBuilder.buildCiudad(raiz)
local tardo = os.clock() - reloj

-- ── Cuantas piezas, y donde ─────────────────────────────────────────────────────
local total = 0
for _, carpeta in ciudad:GetChildren() do
	local n = #carpeta:GetDescendants()
	total += n
	print(string.format("  %-12s %6d", carpeta.Name, n))
end
print(string.format("TOTAL %d piezas en %.2f s", total, tardo))

-- ── SONDA 1: nada del mapa invade el carril ─────────────────────────────────────
local medio = Grid.ANCHO_CALLE / 2
-- La banda util de la calzada, sin contar el bordillo pintado.
local BANDA = medio - 2
local enCarril = {}
for _, p in TODAS do
	if p.ClassName ~= "Part" or p._muerta then
		continue
	end
	-- Solo lo que TAPA: la pintura y las losas rasantes no estorban a nadie.
	if p.Size.Y < 1.2 then
		continue
	end
	local x0, x1 = p.Position.X - p.Size.X / 2, p.Position.X + p.Size.X / 2
	local z0, z1 = p.Position.Z - p.Size.Z / 2, p.Position.Z + p.Size.Z / 2
	local dentro = false
	for i = Grid.COL_MIN, Grid.COL_MAX do
		local eje = Grid.xDeCalle(i)
		if x1 > eje - BANDA and x0 < eje + BANDA then
			dentro = true
		end
	end
	local dentroZ = false
	for j = Grid.FILA_MIN, Grid.FILA_MAX do
		local eje = Grid.zDeCalle(j)
		if z1 > eje - BANDA and z0 < eje + BANDA then
			dentroZ = true
		end
	end
	if dentro and dentroZ then
		table.insert(enCarril, p)
	end
end
print(string.format("%s piezas del mapa sobre el carril: %d", if #enCarril == 0 then "OK  " else "[X] ", #enCarril))
for i = 1, math.min(6, #enCarril) do
	local p = enCarril[i]
	print(string.format("      %s en (%.0f, %.0f) de %.0f x %.0f", p.Name, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z))
end

-- ── SONDA 2: cada manzana tiene su losa y su contenido ──────────────────────────
local manzanas = ciudad:FindFirstChild("Manzanas")
local esperadas = #Districts.manzanas()
print(
	string.format(
		"%s una losa por manzana: %d de %d",
		if manzanas and #manzanas:GetChildren() == esperadas then "OK  " else "[X] ",
		if manzanas then #manzanas:GetChildren() else 0,
		esperadas
	)
)

-- ── SONDA 3: ninguna manzana se queda sin nada dentro ───────────────────────────
-- Es la que caza un uso mal plantado: la manzana existe, la losa esta, y dentro no
-- hay ni un edificio ni un adorno. No da error y se ve como un descampado.
local porManzana: any = {}
for _, p in TODAS do
	if p.ClassName ~= "Part" or p._muerta then
		continue
	end
	for _, mz in Districts.manzanas() do
		local x0, x1, z0, z1 = Grid.manzana(mz.col, mz.fila)
		if p.Position.X > x0 and p.Position.X < x1 and p.Position.Z > z0 and p.Position.Z < z1 then
			local clave = mz.col .. "," .. mz.fila
			porManzana[clave] = (porManzana[clave] or 0) + 1
		end
	end
end
local vacias = {}
for _, mz in Districts.manzanas() do
	local clave = mz.col .. "," .. mz.fila
	if (porManzana[clave] or 0) < 6 then
		table.insert(vacias, string.format("%s (%s, %d piezas)", clave, mz.uso, porManzana[clave] or 0))
	end
end
print(string.format("%s todas las manzanas tienen contenido: %d flojas", if #vacias == 0 then "OK  " else "[X] ", #vacias))
for _, v in vacias do
	print("      " .. v)
end

-- ── SONDA 4: reparto de piezas por uso, para ver si algo se desmadra ────────────
local recuento: any = {}
for _, mz in Districts.manzanas() do
	local clave = mz.col .. "," .. mz.fila
	recuento[mz.uso] = (recuento[mz.uso] or 0) + (porManzana[clave] or 0)
end
local usos = {}
for u in recuento do
	table.insert(usos, u)
end
table.sort(usos)
print("piezas por uso:")
for _, u in usos do
	print(string.format("  %-14s %5d", u, recuento[u]))
end

-- ── SONDA 5: caras coplanares (el parpadeo) ─────────────────────────────────────
-- Dos superficies horizontales a la misma cota que se solapan en planta pelean por el
-- z-buffer, y la tarjeta va enseñando trozos de una y de otra. Es el defecto que este
-- mapa lleva pagando desde que existe: los cruces de calle, el suelo base, los
-- bordillos, las bandas de ventanas y la losa de salida. Se mide aquí porque una vez
-- construido es una cuenta, no una opinión.
local grandes = {}
for _, p in TODAS do
	if p.ClassName ~= "Part" or p._muerta then
		continue
	end
	-- Sólo lo que se ve de lejos: dos chinas de 2 studs solapadas no las nota nadie.
	if p.Size.X < 8 or p.Size.Z < 8 then
		continue
	end
	table.insert(grandes, p)
end
local pares = 0
local ejemplos = {}
for i = 1, #grandes do
	local a = grandes[i]
	local ay = a.Position.Y + a.Size.Y / 2
	for j = i + 1, #grandes do
		local b = grandes[j]
		local by = b.Position.Y + b.Size.Y / 2
		if math.abs(ay - by) > 0.02 then
			continue
		end
		local solapaX = math.abs(a.Position.X - b.Position.X) < (a.Size.X + b.Size.X) / 2 - 0.5
		local solapaZ = math.abs(a.Position.Z - b.Position.Z) < (a.Size.Z + b.Size.Z) / 2 - 0.5
		if solapaX and solapaZ then
			pares += 1
			if #ejemplos < 6 then
				table.insert(ejemplos, string.format("%s / %s a y=%.3f", a.Name, b.Name, ay))
			end
		end
	end
end
print(string.format("%s caras coplanares grandes: %d pares", if pares == 0 then "OK  " else "[X] ", pares))
for _, e in ejemplos do
	print("      " .. e)
end
