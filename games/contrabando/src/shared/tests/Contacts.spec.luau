--!strict
-- Pruebas del reparto de contactos. Lo que se comprueba aquí no es "que salgan":
-- es que quien recorre la ruta LOS ENCUENTRE. La lección de los detectores (quince
-- acabaron en azoteas y medio sistema de vigilancia era decorado sin que nada
-- reventara) vale igual aquí: si el desvío típico supera el radio de recogida, el
-- sistema no existe aunque el código esté escrito.

local Config = require(script.Parent.Parent.Config)
local Contacts = require(script.Parent.Parent.Contacts)

return function(kit)
	local origen = Vector3.new(0, 0, 0)
	local destino = Vector3.new(0, 0, 600)

	local sueltos = Contacts.sueltos(origen, destino, 6)
	kit.eq("siembra los sueltos que se le piden", #sueltos, 6)
	kit.eq("un suelto vale 1", sueltos[1].valor, Config.CONTACTO_VALOR_SUELTO)
	kit.eq("un suelto es de tipo suelto", sueltos[1].tipo, "suelto")

	-- SOBRE el camino: el que va en línea recta los pisa todos.
	local pisados = Contacts.recogidosEnLineaRecta(sueltos, origen, destino, Config.CONTACTO_RADIO)
	kit.eq("quien va en línea recta pisa todos los sueltos", pisados, 6)

	-- Ninguno dentro de la zona segura: un contacto a la puerta de casa es gratis.
	local dentro = 0
	for _, c in sueltos do
		if (c.pos - origen).Magnitude <= Config.ZONA_SEGURA_RADIO then
			dentro += 1
		end
	end
	kit.eq("ningún suelto cae dentro de la zona segura", dentro, 0)

	-- Los racimos se apartan, y por eso NO se pisan yendo recto: son un rodeo.
	local peligros = { Vector3.new(0, 0, 200), Vector3.new(0, 0, 400) }
	local racimos = Contacts.racimos(origen, destino, peligros, 2)
	kit.eq("siembra los racimos que se le piden", #racimos, 2)
	kit.eq("un racimo vale 5", racimos[1].valor, Config.CONTACTO_VALOR_RACIMO)
	kit.eq(
		"un racimo no se pisa yendo recto",
		Contacts.recogidosEnLineaRecta(racimos, origen, destino, Config.CONTACTO_RADIO),
		0
	)

	-- Pero tampoco tan lejos que ir a por él sea una expedición.
	for i, c in racimos do
		local d = (Vector3.new(c.pos.X, 0, c.pos.Z) - Vector3.new(peligros[i].X, 0, peligros[i].Z)).Magnitude
		kit.truthy("el racimo " .. i .. " está junto a su peligro (<= 60)", d <= 60)
	end

	-- Sin peligros que usar de ancla, no inventa racimos sueltos por ahí.
	kit.eq("sin peligros no hay racimos", #Contacts.racimos(origen, destino, {}, 3), 0)

	-- La ruta entera, por su id.
	local ruta = Contacts.deRuta("verde", origen, destino, peligros)
	kit.eq("la verde reparte 6 sueltos y 1 racimo", #ruta, 7)
	kit.eq("una ruta desconocida no revienta, devuelve vacío", #Contacts.deRuta("gris", origen, destino, peligros), 0)

	-- Una ruta tan corta que no cabe nada fuera de la zona segura: mejor ninguno
	-- que uno mal puesto (misma regla que Lairs).
	kit.eq("ruta demasiado corta, sin contactos", #Contacts.sueltos(origen, Vector3.new(0, 0, 120), 6), 0)

	-- LA RACHA. Acelera, tiene tope, y NUNCA deja al jugador fuera de alcance.
	kit.eq("sin recoger nada, no hay racha", Contacts.racha(0), 0)
	kit.near("cuatro contactos dan 2 studs/s", Contacts.racha(4), 2)
	kit.eq("la racha tiene tope", Contacts.racha(999), Config.RACHA_MAXIMA)
	kit.near("la racha se suma a la velocidad", Contacts.velocidadConRacha(16, 4), 18)
	kit.truthy(
		"ni el vehículo más rápido con la racha al tope pasa el antitrampas",
		Contacts.velocidadConRacha(34, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)
	kit.truthy(
		"una velocidad base absurda se recorta igual",
		Contacts.velocidadConRacha(999, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)
end
