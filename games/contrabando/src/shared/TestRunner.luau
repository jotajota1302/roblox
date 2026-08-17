--!strict
--[[
	TestRunner.luau — recorre shared/tests, ejecuta cada suite y devuelve un informe.

	Se lanza por MCP con:
		return require(game.ReplicatedStorage.Shared.TestRunner).run()

	Una suite que revienta al cargarse cuenta como fallo en vez de tumbar la tanda:
	interesa ver TODOS los rojos de una pasada, no el primero.
]]

local TestKit = require(script.Parent.TestKit)

local TestRunner = {}

function TestRunner.run(): string
	local folder = script.Parent:FindFirstChild("tests")
	if not folder then
		return "FALLOS: 1 (no existe la carpeta shared/tests)"
	end

	local lines: { string } = {}
	local total, failed = 0, 0

	local modules = folder:GetChildren()
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)

	for _, module in modules do
		if not module:IsA("ModuleScript") then
			continue
		end

		local kit = TestKit.new(module.Name)
		local ok, err = pcall(function()
			local suite = require(module) :: (TestKit.Kit) -> ()
			suite(kit)
		end)

		if not ok then
			total += 1
			failed += 1
			table.insert(lines, string.format("[X] %s :: la suite reventó: %s", module.Name, tostring(err)))
			continue
		end

		for _, case in kit.cases do
			total += 1
			if case.ok then
				table.insert(lines, string.format("[ok] %s :: %s", module.Name, case.name))
			else
				failed += 1
				table.insert(lines, string.format("[X] %s :: %s -- %s", module.Name, case.name, case.detail))
			end
		end
	end

	local resumen = if failed == 0
		then string.format("OK (%d pruebas)", total)
		else string.format("FALLOS: %d de %d", failed, total)

	table.insert(lines, "")
	table.insert(lines, resumen)
	return table.concat(lines, "\n")
end

return TestRunner
