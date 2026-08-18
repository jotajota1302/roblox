--!strict
--[[
	Roads.luau — la calle manda. Módulo PURO.

	LA REGLA, decidida por JJ: los vehículos de motor sólo ruedan por el asfalto.
	Si te sales, te bajas y el vehículo se queda aparcado donde lo dejaste.

	POR QUÉ ES LA MEJOR PIEZA QUE SE LE HA AÑADIDO AL JUEGO: hasta ahora comprar un
	vehículo era una mejora pasiva -- más capacidad, un poco más de velocidad, cero
	decisiones. Con esto, cada trayecto pasa a tener dos versiones:

	  · por la calle, deprisa, pero por donde va todo el mundo y donde están las
	    esquinas fichadas;
	  · a pie, cortando por parques y solares, lento pero por donde no te siguen.

	Y como el vehículo se queda donde lo dejas, meterse por un atajo tiene precio:
	hay que volver a por él. Eso es una decisión de verdad, tomada varias veces por
	viaje, que es exactamente lo que le faltaba al minuto y medio del medio.

	LA REGLA DE ORO SIGUE EN PIE -- "ningún vehículo te hace inatrapable"-- pero
	ahora se sostiene por otro sitio: no porque los vehículos sean lentos, sino
	porque van atados a la calzada. Quien te persigue puede cortar por donde tú no
	puedes.

	Qué queda dentro y qué fuera lo dice Config (`soloCalzada`): los baratos --
	patines, monopatín, patinete-- van por todas partes, y ésa es su gracia frente
	a los caros.
]]

local Config = require(script.Parent.Config)

local Roads = {}

-- ¿Es asfalto lo que estoy pisando?
--
-- POR COLOR, y no por nombre ni por material. La ciudad es un modelo ajeno: sus
-- piezas se llaman "Grass", "Part" o "Stone" con total independencia de lo que
-- representan, y el mismo nombre sirve para una acera y para un tejado. El color
-- sí es fiable, porque una calzada es gris y el gris es lo único que no tiene
-- color: sus tres componentes son casi iguales.
--
-- El techo de luminosidad deja fuera el blanco y los grises muy claros, que en
-- esta ciudad son las fachadas y las líneas pintadas.
local MAXIMA_LUMINOSIDAD = 190
local MAXIMA_DIFERENCIA = 14

function Roads.esCalzada(color: Color3): boolean
	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	if r > MAXIMA_LUMINOSIDAD then
		return false
	end
	return math.abs(r - g) <= MAXIMA_DIFERENCIA and math.abs(g - b) <= MAXIMA_DIFERENCIA
end

-- ¿Este vehículo necesita asfalto?
function Roads.exigeCalzada(vehiculoId: string?): boolean
	if vehiculoId == nil then
		return false
	end
	for _, v in Config.VEHICULOS do
		if v.id == vehiculoId then
			return v.soloCalzada == true
		end
	end
	return false
end

-- ¿Puede rodar aquí y ahora?
function Roads.puedeRodar(vehiculoId: string?, enCalzada: boolean): boolean
	if vehiculoId == nil or vehiculoId == Config.VEHICULO_INICIAL then
		return false
	end
	if not Roads.exigeCalzada(vehiculoId) then
		return true
	end
	return enCalzada
end

-- Qué vehículo cuenta para la VELOCIDAD ahora mismo. Devuelve el id del vehículo
-- si va montado, o el de ir a pie si lo ha dejado aparcado.
--
-- La CAPACIDAD no se toca: la sigue dando el vehículo comprado aunque lo tengas
-- aparcado, porque la carga ya está cargada y quitártela al bajarte sería
-- castigar por una decisión que el juego te invita a tomar.
function Roads.vehiculoQueCuenta(vehiculoId: string?, montado: boolean): string?
	if montado then
		return vehiculoId
	end
	return Config.VEHICULO_INICIAL
end

return Roads
