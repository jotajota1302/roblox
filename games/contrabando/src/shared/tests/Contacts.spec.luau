--!strict
-- Pruebas del reparto de contactos. Lo que se comprueba aquí no es "que salgan":
-- es que quien recorre la ruta LOS ENCUENTRE.
--
-- Esa distinción no es teórica: la primera versión repartía sobre la recta entre
-- casa y destino y, medida contra el camino real del pathfinder, ponía en el
-- camino el 0 % de la ruta verde. Treinta y ocho piezas plantadas y ninguna al
-- alcance de nadie -- la misma firma que los quince detectores en las azoteas.
-- De ahí que el reparto trabaje sobre una POLILÍNEA y que la prueba de la ele
-- exista.

local Config = require(script.Parent.Parent.Config)
local Contacts = require(script.Parent.Parent.Contacts)

return function(kit)
	local origen = Vector3.new(0, 0, 0)
	local destino = Vector3.new(0, 0, 600)
	local recta = { origen, destino }

	local sueltos = Contacts.sueltos(recta, 6)
	kit.eq("siembra los sueltos que se le piden", #sueltos, 6)
	kit.eq("un suelto vale 1", sueltos[1].valor, Config.CONTACTO_VALOR_SUELTO)
	kit.eq("un suelto es de tipo suelto", sueltos[1].tipo, "suelto")

	-- SOBRE el camino: el que lo recorre los pisa todos.
	kit.eq(
		"quien recorre el camino pisa todos los sueltos",
		Contacts.cercaDelCamino(sueltos, recta, Config.CONTACTO_RADIO),
		6
	)

	-- Ninguno dentro de la zona segura: un contacto a la puerta de casa es gratis.
	local dentro = 0
	for _, c in sueltos do
		if (c.pos - origen).Magnitude <= Config.ZONA_SEGURA_RADIO then
			dentro += 1
		end
	end
	kit.eq("ningún suelto cae dentro de la zona segura", dentro, 0)

	-- LA PRUEBA DE LA ELE, que es la que habría cazado el fallo: un camino que
	-- dobla en ángulo recto. Los contactos tienen que seguir la ele, no la
	-- diagonal, o repiten exactamente el error de repartir sobre la recta.
	local ele = { Vector3.new(0, 0, 0), Vector3.new(0, 0, 500), Vector3.new(500, 0, 500) }
	local porLaEle = Contacts.sueltos(ele, 8)
	kit.eq("en un camino en ele siembra los que se le piden", #porLaEle, 8)
	kit.eq("y TODOS caen sobre la ele", Contacts.cercaDelCamino(porLaEle, ele, Config.CONTACTO_RADIO), 8)
	kit.truthy(
		"que no es lo mismo que la recta entre los extremos",
		Contacts.cercaDelCamino(porLaEle, { ele[1], ele[3] }, Config.CONTACTO_RADIO) < 8
	)
	-- Y hay contactos en los DOS brazos: si el reparto se quedara en el primero,
	-- media ruta iría sin nada.
	local primerBrazo, segundoBrazo = 0, 0
	for _, c in porLaEle do
		if c.pos.X < 10 then
			primerBrazo += 1
		else
			segundoBrazo += 1
		end
	end
	kit.truthy("hay contactos en el primer brazo", primerBrazo > 0)
	kit.truthy("y en el segundo", segundoBrazo > 0)

	-- Los racimos se apartan, y por eso NO se pisan yendo por el camino: son un
	-- rodeo.
	local peligros = { Vector3.new(80, 0, 200), Vector3.new(-80, 0, 400) }
	local racimos = Contacts.racimos(recta, peligros, 2)
	kit.eq("siembra los racimos que se le piden", #racimos, 2)
	kit.eq("un racimo vale 5", racimos[1].valor, Config.CONTACTO_VALOR_RACIMO)
	kit.eq(
		"un racimo no se pisa yendo por el camino",
		Contacts.cercaDelCamino(racimos, recta, Config.CONTACTO_RADIO),
		0
	)

	-- Y cae ENTRE el camino y su peligro, no al otro lado: ir a por él tiene que
	-- ser acercarse al riesgo, que es toda su gracia.
	for i, c in racimos do
		local haciaPeligro = Vector3.new(peligros[i].X, 0, peligros[i].Z)
		local haciaRacimo = Vector3.new(c.pos.X, 0, c.pos.Z)
		kit.truthy("el racimo " .. i .. " está del lado de su peligro", haciaRacimo.X * haciaPeligro.X > 0)
		kit.truthy("y no más lejos que él", math.abs(haciaRacimo.X) <= math.abs(haciaPeligro.X) + 1)
	end

	-- Sin peligros que usar de ancla, no inventa racimos sueltos por ahí.
	kit.eq("sin peligros no hay racimos", #Contacts.racimos(recta, {}, 3), 0)

	-- La ruta entera, por su id.
	kit.eq("la verde reparte 6 sueltos y 1 racimo", #Contacts.deRuta("verde", recta, peligros), 7)
	kit.eq("una ruta desconocida no revienta, devuelve vacío", #Contacts.deRuta("gris", recta, peligros), 0)

	-- Un camino tan corto que no cabe nada fuera de la zona segura: mejor ninguno
	-- que uno mal puesto (misma regla que Lairs).
	kit.eq("camino demasiado corto, sin contactos", #Contacts.sueltos({ origen, Vector3.new(0, 0, 120) }, 6), 0)
	kit.eq("un camino de un solo punto no revienta", #Contacts.sueltos({ origen }, 6), 0)

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
