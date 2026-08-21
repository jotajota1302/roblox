
-- ── El arbol de modulos, sobre las fuentes embebidas ────────────────────────────
local cache: any = {}
local nodo

-- Un nodo del arbol: la carpeta `Shared`, la carpeta `tests`, o el `script` de un
-- modulo (cuyo `.Parent` es su carpeta).
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
			-- No es un modulo: sera una carpeta (tests).
			return nodo(clave, self, k)
		end,
	})
	return self
end

local shared = nodo("", nil, "Shared")

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
				__index = function(_, sub)
					if sub == "Server" then
						return nodo("server", nil, "Server")
					end
					return nil
				end,
			})
		end
		return function()
			return nil
		end
	end,
})

-- ── Correr las suites ───────────────────────────────────────────────────────────
local TestKit = shared.TestKit
local aCorrer: any = { ... }
if #aCorrer == 0 then
	aCorrer = {}
	for clave in FUENTES do
		local nombre = string.match(clave, "^tests/(.+)%.spec$")
		if nombre then
			table.insert(aCorrer, nombre)
		end
	end
	table.sort(aCorrer)
end

local total, fallos = 0, 0
for _, nombreSuite in aCorrer do
	local suite = shared.tests[nombreSuite .. ".spec"]
	local kit = TestKit.new(nombreSuite)
	local ok, err = pcall(suite, kit)
	if not ok then
		fallos += 1
		total += 1
		print(string.format("[X] %s :: la suite revento: %s", nombreSuite, tostring(err)))
		continue
	end
	for _, caso in kit.cases do
		total += 1
		if not caso.ok then
			fallos += 1
			print(string.format("[X] %s :: %s -- %s", nombreSuite, caso.name, caso.detail))
		end
	end
end
local resumen = string.format("%s (%d pruebas, %d fallos)", if fallos == 0 then "OK" else "FALLOS", total, fallos)
if fallos > 0 then
	-- CON `error` Y NO SOLO IMPRIMIENDO: el CLI de Luau devuelve 0 mientras el script
	-- no reviente, asi que un resumen en rojo por pantalla dejaria a `verificar.ps1`
	-- dando "TODO OK" con la bateria en fallo -- que es exactamente la clase de sonda
	-- que este proyecto ya ha pagado dos veces.
	error(resumen, 0)
end
print(resumen)
