--!strict
--[[
	TestKit.luau — micro-framework de pruebas.

	Luau no corre fuera de Roblox, así que las pruebas se ejecutan DENTRO de Studio
	(por MCP) contra los módulos puros de esta carpeta. No hace falta nada más
	sofisticado: sin dependencias, sin instalación y el informe cabe en una pantalla.

	Uso desde una suite:

		return function(kit)
			kit.eq("dos mas dos", 2 + 2, 4)
		end
]]

export type Case = { name: string, ok: boolean, detail: string }

export type Kit = {
	suite: string,
	cases: { Case },
	eq: (name: string, actual: any, expected: any) -> (),
	near: (name: string, actual: number, expected: number, tolerance: number?) -> (),
	truthy: (name: string, value: any) -> (),
	falsy: (name: string, value: any) -> (),
	errors: (name: string, fn: () -> ()) -> (),
}

local TestKit = {}

function TestKit.new(suite: string): Kit
	local cases: { Case } = {}

	local function record(name: string, ok: boolean, detail: string)
		table.insert(cases, { name = name, ok = ok, detail = detail })
	end

	local kit: Kit
	kit = {
		suite = suite,
		cases = cases,

		eq = function(name, actual, expected)
			record(
				name,
				actual == expected,
				string.format("esperado <%s>, obtenido <%s>", tostring(expected), tostring(actual))
			)
		end,

		-- Para números con decimales: comparar con == es pedir un falso negativo.
		near = function(name, actual, expected, tolerance)
			local tol = tolerance or 0.001
			record(
				name,
				math.abs(actual - expected) <= tol,
				string.format("esperado %.4f +-%.4f, obtenido %.4f", expected, tol, actual)
			)
		end,

		truthy = function(name, value)
			record(name, value ~= nil and value ~= false, "esperado verdadero, obtenido " .. tostring(value))
		end,

		falsy = function(name, value)
			record(name, value == nil or value == false, "esperado falso, obtenido " .. tostring(value))
		end,

		-- Comprobar que algo REVIENTA es una prueba de primera: así se verifica
		-- que el servidor rechaza la basura que le manda un exploit.
		errors = function(name, fn)
			local ok = pcall(fn)
			record(name, not ok, "se esperaba un error y no lo hubo")
		end,
	}

	return kit
end

return TestKit
