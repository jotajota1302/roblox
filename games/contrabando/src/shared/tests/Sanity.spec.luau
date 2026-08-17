--!strict
-- Suite de cordura: comprueba que el propio ciclo de pruebas funciona.

return function(kit)
	kit.eq("el runner encuentra la suite", 1, 1)
	kit.near("near tolera decimales", 0.1 + 0.2, 0.3)
	kit.truthy("truthy acepta valores", "algo")
	kit.falsy("falsy acepta nil", nil)
	kit.errors("errors detecta un fallo", function()
		error("a propósito")
	end)
end
