--!nocheck
-- Arnes desechable para correr las pruebas PURAS sin Studio, con tools/luau.exe.
-- Vive en el directorio temporal del trabajo, no en el repo: es una muleta para
-- verificar mientras Studio esta cerrado, no una segunda bateria que mantener.


-- ── Tipos de Roblox, lo minimo que piden los modulos puros ──────────────────────
local Vector3 = {}
Vector3.__index = Vector3
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3)
end
function Vector3.new(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
Vector3.zero = v3(0, 0, 0)
function Vector3.__add(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function Vector3.__sub(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function Vector3.__mul(a, b)
	if type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function Vector3.__div(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end
function Vector3.__unm(a)
	return v3(-a.X, -a.Y, -a.Z)
end
function Vector3.__eq(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
function Vector3.__tostring(a)
	return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z)
end
function Vector3.__index(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	return rawget(Vector3, k)
end
function Vector3:Dot(o)
	return self.X * o.X + self.Y * o.Y + self.Z * o.Z
end
function Vector3:Cross(o)
	return v3(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X)
end
function Vector3:Lerp(o, t)
	return v3(self.X + (o.X - self.X) * t, self.Y + (o.Y - self.Y) * t, self.Z + (o.Z - self.Z) * t)
end

local Vector2 = { new = function(x, y)
	return { X = x, Y = y }
end }

local Color3 = {}
Color3.__index = Color3
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, Color3)
end
function Color3.new(r, g, b)
	return c3(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	return c3(r / 255, g / 255, b / 255)
end
function Color3.fromHSV(h, s, v)
	return c3(h, s, v)
end
function Color3:Lerp(o, t)
	return c3(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t)
end
function Color3.__eq(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.__tostring(a)
	return string.format("rgb(%d,%d,%d)", a.R * 255, a.G * 255, a.B * 255)
end

-- Random determinista propio: el `Random` de Roblox no esta aqui, y lo unico que
-- las pruebas le piden es que la misma semilla de la misma secuencia.
local Random = {}
Random.__index = Random
function Random.new(semilla)
	return setmetatable({ estado = (semilla or 0) % 2147483647 }, Random)
end
function Random:_next()
	self.estado = (self.estado * 1103515245 + 12345) % 2147483648
	return self.estado / 2147483648
end
function Random:NextNumber(a, b)
	local u = self:_next()
	if a == nil then
		return u
	end
	return a + u * (b - a)
end
function Random:NextInteger(a, b)
	return a + math.floor(self:_next() * (b - a + 1))
end

local function stubEnum()
	return setmetatable({}, {
		__index = function()
			return stubEnum()
		end,
		__tostring = function()
			return "Enum"
		end,
	})
end
local Enum = stubEnum()

-- CFrame minimo: rotacion 3x3 por filas y posicion. Solo lo que piden los modulos
-- puros -- girar sobre un eje, componer y preguntar por los vectores del marco.
local CFrame = {}
CFrame.__index = CFrame
local function cf(r, p)
	return setmetatable({ r = r, p = p }, CFrame)
end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return cf(IDENT, x)
	end
	return cf(IDENT, Vector3.new(x or 0, y or 0, z or 0))
end
CFrame.identity = cf(IDENT, Vector3.new(0, 0, 0))
local function mulR(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 1, 3 do
			o[i * 3 + j] = a[i * 3 + 1] * b[j] + a[i * 3 + 2] * b[3 + j] + a[i * 3 + 3] * b[6 + j]
		end
	end
	return o
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(mulR(mulR(X, Y), Z), Vector3.new(0, 0, 0))
end
function CFrame.fromAxisAngle(eje, ang)
	local u = eje.Unit
	local c, s, t = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
	local x, y, z = u.X, u.Y, u.Z
	return cf({
		t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c,
	}, Vector3.new(0, 0, 0))
end
local function aplicar(r, v)
	return Vector3.new(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
function CFrame.__mul(a, b)
	if getmetatable(b) == Vector3 then
		return a.p + aplicar(a.r, b)
	end
	return cf(mulR(a.r, b.r), a.p + aplicar(a.r, b.p))
end
function CFrame.__add(a, v)
	return cf(a.r, a.p + v)
end
function CFrame.__index(t, k)
	if k == "Position" or k == "p" then
		return rawget(t, "p")
	elseif k == "RightVector" then
		return Vector3.new(t.r[1], t.r[4], t.r[7])
	elseif k == "UpVector" then
		return Vector3.new(t.r[2], t.r[5], t.r[8])
	elseif k == "LookVector" then
		return Vector3.new(-t.r[3], -t.r[6], -t.r[9])
	elseif k == "Rotation" then
		return cf(t.r, Vector3.new(0, 0, 0))
	end
	return rawget(CFrame, k)
end
function CFrame:VectorToObjectSpace(v)
	return Vector3.new(
		self.r[1] * v.X + self.r[4] * v.Y + self.r[7] * v.Z,
		self.r[2] * v.X + self.r[5] * v.Y + self.r[8] * v.Z,
		self.r[3] * v.X + self.r[6] * v.Y + self.r[9] * v.Z
	)
end
function CFrame:Inverse()
	local r = { self.r[1], self.r[4], self.r[7], self.r[2], self.r[5], self.r[8], self.r[3], self.r[6], self.r[9] }
	return cf(r, -aplicar(r, self.p))
end
function CFrame:Lerp(o, t)
	return cf(self.r, self.p:Lerp(o.p, t))
end

-- `require` sombreado con un LOCAL: las fuentes de abajo lo capturan como upvalue,
-- asi que dentro de cada modulo `require(script.Parent.X)` recibe el modulo ya
-- construido y solo tiene que devolverlo.
local function require(m: any): any
	return m
end
-- Igual con `game`: local aqui, relleno en el epilogo cuando el arbol existe.
local game: any
