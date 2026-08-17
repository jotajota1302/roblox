--!strict
-- Suite de cordura: comprueba que el propio ciclo de pruebas funciona.
-- El caso "esto debe fallar" se corrige en el paso siguiente; existe para
-- ver un rojo antes de fiarnos de un verde.

return function(kit)
	kit.eq("el runner encuentra la suite", 1, 1)
	kit.eq("esto debe fallar", 1, 2)
end
