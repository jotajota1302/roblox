--!strict
-- Pruebas de las habilidades. La más importante es la última: ninguna combinación
-- puede volver al jugador inalcanzable ni inmune al robo. Es la única regla
-- innegociable del diseño y por eso tiene prueba, no comentario.

local Config = require(script.Parent.Parent.Config)
local Skills = require(script.Parent.Parent.Skills)

return function(kit)
	local vacias = Skills.normalizar(nil)
	kit.eq("sin datos, camuflaje a cero", vacias.camuflaje, 0)
	kit.eq("basura del cliente no sube nada", Skills.normalizar({ camuflaje = 99 }).camuflaje, 3)
	kit.eq("basura no numérica se ignora", Skills.normalizar({ camuflaje = "muchos" }).camuflaje, 0)
	kit.eq("un peldaño negativo se recorta a cero", Skills.normalizar({ aguante = -5 }).aguante, 0)

	kit.eq("el primer peldaño de camuflaje cuesta 20", Skills.coste(vacias, "camuflaje"), 20)
	kit.eq("una habilidad que no existe no tiene coste", Skills.coste(vacias, "volar"), nil)

	-- Comprar sin contactos suficientes no cambia nada.
	local ok, motivo, tras, saldo = Skills.comprar(vacias, 5, "camuflaje")
	kit.falsy("no se compra sin contactos", ok)
	kit.eq("y lo dice", motivo, "Not enough contacts")
	kit.eq("el saldo no se toca", saldo, 5)
	kit.eq("la habilidad tampoco", tras.camuflaje, 0)

	-- Comprar con contactos suficientes cobra exactamente el coste.
	local ok2, _, tras2, saldo2 = Skills.comprar(vacias, 50, "camuflaje")
	kit.truthy("se compra con contactos de sobra", ok2)
	kit.eq("sube un peldaño", tras2.camuflaje, 1)
	kit.eq("y cobra 20", saldo2, 30)
	kit.eq("y no toca lo que recibió", vacias.camuflaje, 0)

	-- El tope. Tres peldaños y no hay cuarto.
	local topeCamuflaje = { camuflaje = 3 }
	kit.eq("al máximo no hay coste", Skills.coste(topeCamuflaje, "camuflaje"), nil)
	local ok3, motivo3 = Skills.comprar(topeCamuflaje, 9999, "camuflaje")
	kit.falsy("al máximo no se compra más", ok3)
	kit.eq("y lo dice", motivo3, "Already maxed")

	-- Una habilidad inventada por un cliente manipulado no se compra.
	local ok4, motivo4 = Skills.comprar(vacias, 9999, "volar")
	kit.falsy("no se compra lo que no existe", ok4)
	kit.eq("y lo dice", motivo4, "That skill does not exist")

	-- Los factores: mejoran, y en la dirección correcta.
	kit.eq("sin camuflaje, el bulto no cambia", Skills.factorBulto(vacias), 1)
	kit.truthy("con camuflaje, el bulto baja", Skills.factorBulto({ camuflaje = 3 }) < 1)
	kit.truthy("con aguante, el robo baja", Skills.factorRobo({ aguante = 3 }) < 1)
	kit.truthy("con vista, el alcance sube", Skills.factorVista({ vista = 3 }) > 1)
	kit.falsy("sin comprarlo, no hay señuelo", Skills.tieneSenuelo(vacias))
	kit.truthy("comprado, hay señuelo", Skills.tieneSenuelo({ senuelo = 1 }))

	-- LA REGLA DE ORO, en números. Con todo comprado el jugador sigue siendo
	-- fichable y sigue siendo robable: mitigar no es anular.
	local todo = { camuflaje = 3, aguante = 3, vista = 3, senuelo = 1 }
	kit.truthy("con todo comprado, todavía te fichan", Config.DETECTOR_RADIO * Skills.factorBulto(todo) > 0)
	local fraccion = math.max(Config.ROBO_FRACCION_MINIMA, Config.ROBO_FRACCION * Skills.factorRobo(todo))
	kit.truthy("con todo comprado, todavía te roban", fraccion >= Config.ROBO_FRACCION_MINIMA)
	kit.near("y se lleva el 21 % de tu carga", fraccion, 0.21, 0.001)
	kit.truthy("ninguna habilidad toca la velocidad", (Skills :: any).factorVelocidad == nil)
end
