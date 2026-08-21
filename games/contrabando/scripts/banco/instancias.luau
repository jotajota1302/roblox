--!nocheck
--[[
	instancias.luau — un `Instance` de mentira, para construir la ciudad en memoria.

	POR QUE. `MapBuilder` es el fichero que mas ha roto este juego, y hasta hoy solo
	se podia mirar dentro de Studio: abrirlo, cargar el place, jugar y medir. Con esto
	se construye la ciudad entera en centesimas de segundo desde la linea de ordenes y
	se le pasan las sondas -- cuantas piezas, si algo pisa el carril, si hay caras
	coplanares.

	LO QUE NO ES. No sustituye a `SelfCheck`: aqui no hay raycasts, ni suelo, ni
	pathfinding, ni las piezas que planta `CityBuilder` encima. Esto comprueba lo que
	el mapa DICE que planta; SelfCheck comprueba el mundo que sale de verdad.

	Solo implementa lo que MapBuilder y StreetProps usan. Si un dia hace falta algo
	mas, revienta con "attempt to call a nil value" y se anade -- que es infinitamente
	mejor que devolver un valor falso y dar verde.
]]

-- ── Instance de mentira: lo justo para que MapBuilder construya en memoria ───────
local TODAS = {}
local Instance = {}
local Inst = {}
Inst.__index = function(t, k)
	if k == "Position" then
		return rawget(t, "_pos")
	elseif k == "CFrame" then
		return rawget(t, "_cf") or CFrame.new(rawget(t, "_pos"))
	end
	return rawget(Inst, k) or rawget(t, "_p")[k]
end
Inst.__newindex = function(t, k, v)
	if k == "Position" then
		rawset(t, "_pos", v)
		rawset(t, "_cf", CFrame.new(v))
	elseif k == "CFrame" then
		rawset(t, "_cf", v)
		rawset(t, "_pos", v.Position)
	elseif k == "Parent" then
		rawset(t, "_padre", v)
		if v ~= nil then
			table.insert(v._hijos, t)
		end
	else
		rawget(t, "_p")[k] = v
	end
end
function Inst:SetAttribute(k, v)
	self._attr[k] = v
end
function Inst:GetAttribute(k)
	return self._attr[k]
end
function Inst:GetChildren()
	return self._hijos
end
function Inst:GetDescendants()
	local out = {}
	local function baja(n)
		for _, h in n._hijos do
			table.insert(out, h)
			baja(h)
		end
	end
	baja(self)
	return out
end
function Inst:FindFirstChild(n)
	for _, h in self._hijos do
		if h.Name == n then
			return h
		end
	end
	return nil
end
function Inst:IsA(clase)
	return clase == self.ClassName or (clase == "BasePart" and self.ClassName == "Part")
end
function Inst:Destroy()
	rawset(self, "_muerta", true)
	local padre = rawget(self, "_padre")
	if padre then
		for i, h in padre._hijos do
			if h == self then
				table.remove(padre._hijos, i)
				break
			end
		end
	end
	rawset(self, "_padre", nil)
end
function Instance.new(clase)
	local t = setmetatable({}, Inst)
	rawset(t, "_p", { ClassName = clase, Name = clase, Size = Vector3.new(1, 1, 1), Transparency = 0 })
	rawset(t, "_pos", Vector3.new(0, 0, 0))
	rawset(t, "_hijos", {})
	rawset(t, "_attr", {})
	rawset(t, "_padre", nil)
	table.insert(TODAS, t)
	return t
end
