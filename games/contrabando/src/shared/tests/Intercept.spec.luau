--!strict
local Config = require(script.Parent.Parent.Config)
local Intercept = require(script.Parent.Parent.Intercept)

return function(kit)
	local AHORA = 1000
	local comun = { rareza = "comun" }

	local function perfil(ruta, cajas, marcadoHasta, velocidad)
		return {
			cajas = cajas or {},
			ruta = ruta,
			marcadoHasta = marcadoHasta or 0,
			velocidad = velocidad or 16,
		}
	end

	-- Ruta verde: aquí no roba nadie. Es la promesa que hace jugable el juego en
	-- solitario, y romperla es romper el diseño entero.
	local ok, motivo = Intercept.puedeRobar(perfil("verde", { comun }), perfil("verde", { comun }), 3, AHORA)
	kit.falsy("en la verde no se roba", ok)
	kit.eq("y se dice por que", motivo, "ruta_sin_pvp")

	-- Ruta ámbar: sólo roba quien también arriesga algo.
	kit.truthy(
		"en la ambar roba quien lleva carga",
		Intercept.puedeRobar(perfil("ambar", { comun }), perfil("ambar", { comun }), 3, AHORA)
	)
	local okVacio, motivoVacio = Intercept.puedeRobar(perfil("ambar", {}), perfil("ambar", { comun }), 3, AHORA)
	kit.falsy("en la ambar no se caza de vacio", okVacio)
	kit.eq("y se dice por que", motivoVacio, "cazador_sin_carga")

	-- Ruta roja: cualquiera, incluso saliendo del almacén sin nada, sólo a por ti.
	kit.truthy(
		"en la roja caza cualquiera",
		Intercept.puedeRobar(perfil("roja", {}), perfil("roja", { comun }), 3, AHORA)
	)

	-- La víctima tiene que llevar algo.
	local okSinBotin = Intercept.puedeRobar(perfil("roja", { comun }), perfil("roja", {}), 3, AHORA)
	kit.falsy("no se roba a quien va vacio", okSinBotin)

	-- Distancia.
	kit.falsy("de lejos no se alcanza", Intercept.puedeRobar(perfil("roja", {}), perfil("roja", { comun }), 30, AHORA))

	-- Marcado: 60 s sin poder volver a robar. Sin esto, el ladrón encadena robos.
	local okMarcado, motivoMarcado =
		Intercept.puedeRobar(perfil("roja", {}, AHORA + 30), perfil("roja", { comun }), 3, AHORA)
	kit.falsy("un ladron marcado no roba", okMarcado)
	kit.eq("y se dice por que", motivoMarcado, "marcado")
	kit.truthy(
		"pero al expirar la marca vuelve a poder",
		Intercept.puedeRobar(perfil("roja", {}, AHORA - 1), perfil("roja", { comun }), 3, AHORA)
	)

	-- Velocidad imposible: se invalida el robo en vez de expulsar. Más suave con el
	-- lag y con las caídas, y quita el beneficio igual.
	local okVeloz, motivoVeloz = Intercept.puedeRobar(
		perfil("roja", {}, 0, Config.VELOCIDAD_MAXIMA_PLAUSIBLE + 20),
		perfil("roja", { comun }),
		3,
		AHORA
	)
	kit.falsy("velocidad imposible invalida el robo", okVeloz)
	kit.eq("y se dice por que", motivoVeloz, "velocidad_imposible")

	-- La víctima tiene que estar en ruta: nadie roba dentro del almacén.
	kit.falsy(
		"a quien no esta en ruta no se le roba",
		Intercept.puedeRobar(perfil("roja", { comun }), perfil(nil, { comun }), 3, AHORA)
	)

	-- Reparto: 30% redondeando hacia arriba, para que robar una sola caja sirva
	-- de algo. Y nunca se lleva todo: quedarse a cero es lo que hace abandonar.
	local robadas, restantes = Intercept.reparto({ comun, comun, comun, comun }, 0.30)
	kit.eq("de cuatro se lleva dos", #robadas, 2)
	kit.eq("y deja dos", #restantes, 2)

	local unaRobada, unaRestante = Intercept.reparto({ comun }, 0.30)
	kit.eq("de una se lleva una", #unaRobada, 1)
	kit.eq("y no queda nada", #unaRestante, 0)

	local ningunaRobada = Intercept.reparto({}, 0.30)
	kit.eq("de nada no se lleva nada", #ningunaRobada, 0)

	-- Alerta de proximidad. Usa EXACTAMENTE las mismas reglas que el robo: si alguien
	-- no puede robarte, avisar de que se acerca sería asustar por nada.
	kit.truthy(
		"en la roja se avisa de quien se acerca",
		Intercept.esAmenaza(perfil("roja", {}), perfil("roja", { comun }), 40, AHORA)
	)
	kit.falsy(
		"en la verde no se avisa: alli nadie roba",
		Intercept.esAmenaza(perfil("verde", { comun }), perfil("verde", { comun }), 40, AHORA)
	)
	kit.falsy(
		"en la ambar no asusta un cazador vacio",
		Intercept.esAmenaza(perfil("ambar", {}), perfil("ambar", { comun }), 40, AHORA)
	)
	kit.falsy(
		"desde muy lejos no se avisa",
		Intercept.esAmenaza(perfil("roja", {}), perfil("roja", { comun }), 500, AHORA)
	)
end
