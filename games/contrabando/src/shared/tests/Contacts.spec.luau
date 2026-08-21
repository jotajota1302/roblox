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

	-- LA PRUEBA DE LA ELE, que es la que habría cazado el fallo original: un camino
	-- que dobla en ángulo recto. El rastro tiene que seguir la ele, no la diagonal,
	-- o repite exactamente el error de repartir sobre la recta -- y aquí importa
	-- todavía más que con los sueltos, porque un rastro que corta por la diagonal
	-- no es un premio mal puesto: es una ruta MAL SEÑALIZADA, y manda al jugador
	-- contra una pared.
	local ele = { Vector3.new(0, 0, 0), Vector3.new(0, 0, 500), Vector3.new(500, 0, 500) }
	local porLaEle = Contacts.rastro(ele)
	kit.truthy("en un camino en ele siembra rastro", #porLaEle > 10)
	kit.eq("y TODO cae sobre la ele", Contacts.cercaDelCamino(porLaEle, ele, Config.CONTACTO_RADIO), #porLaEle)
	kit.truthy(
		"que no es lo mismo que la recta entre los extremos",
		Contacts.cercaDelCamino(porLaEle, { ele[1], ele[3] }, Config.CONTACTO_RADIO) < #porLaEle
	)
	-- Y hay rastro en los DOS brazos: si el reparto se quedara en el primero,
	-- media ruta iría a oscuras.
	local primerBrazo, segundoBrazo = 0, 0
	for _, c in porLaEle do
		if c.pos.X < 10 then
			primerBrazo += 1
		else
			segundoBrazo += 1
		end
	end
	kit.truthy("hay rastro en el primer brazo", primerBrazo > 0)
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

	-- ─────────────────────────────────────────────────────────────────────────
	-- EL RASTRO. Lo que se comprueba no es que salga: es que sea una FILA -- sin
	-- huecos por los que el jugador pueda perder el camino, que es su único
	-- trabajo. Un rastro con un vano de sesenta studs no marca una ruta.
	local rastro = Contacts.rastro(recta)
	kit.truthy("el rastro llena el camino, no lo salpica", #rastro > 10)
	kit.eq("una pieza de rastro no paga contacto", rastro[1].valor, Config.CONTACTO_VALOR_RASTRO)
	kit.eq("la primera es de velocidad", rastro[1].tipo, Config.RECOGIBLE_VELOCIDAD)
	kit.eq("la segunda de salto", rastro[2].tipo, Config.RECOGIBLE_SALTO)
	kit.eq("y la tercera de escudo", rastro[3].tipo, Config.RECOGIBLE_ESCUDO)

	-- SE TURNAN SIN FALLAR NI UNA. Es la regla que hace el rastro aprendible: si el
	-- reparto se torciera a mitad de ruta, la fila dejaria de poder planearse y
	-- volveria a ser una loteria.
	local mal = 0
	for i, c in rastro do
		local toca = Config.RECOGIBLES[((i - 1) % #Config.RECOGIBLES) + 1]
		if c.tipo ~= toca then
			mal += 1
		end
		if not Contacts.esDelRastro(c.tipo) then
			mal += 1
		end
	end
	kit.eq("las tres clases se turnan de principio a fin", mal, 0)
	kit.eq("todo el rastro cae sobre el camino", Contacts.cercaDelCamino(rastro, recta, Config.CONTACTO_RADIO), #rastro)

	-- SIN HUECOS: entre dos píldoras seguidas no puede haber más de un paso.
	local mayorHueco = 0
	for i = 2, #rastro do
		local d = (rastro[i].pos - rastro[i - 1].pos).Magnitude
		if d > mayorHueco then
			mayorHueco = d
		end
	end
	kit.truthy("no hay ningún vano mayor que el paso", mayorHueco <= Config.RASTRO_PASO + 0.5)

	-- Ninguna dentro de la zona segura, igual que los sueltos.
	local rastroDentro = 0
	for _, c in rastro do
		if (c.pos - origen).Magnitude <= Config.ZONA_SEGURA_RADIO then
			rastroDentro += 1
		end
	end
	kit.eq("ninguna pieza del rastro cae dentro de la zona segura", rastroDentro, 0)

	-- Y LLEGA HASTA EL FINAL. Es la diferencia con los sueltos, que paraban a 60
	-- studs del destino: quien sigue el rastro tiene que acabar en la entrega, no
	-- quedarse a oscuras en el último tramo, que es donde más caro sale perderse.
	local finalRastro = rastro[#rastro].pos
	kit.truthy(
		"el rastro llega hasta cerca del destino",
		(finalRastro - destino).Magnitude <= Config.RASTRO_HASTA + Config.RASTRO_PASO
	)

	-- El rastro escala con el largo del camino, que es su razón de ser: un número
	-- fijo dejaba la ruta larga --la que más ganas de abandonar da-- con la misma
	-- media docena de piezas que la corta.
	local largo = Contacts.rastro({ origen, Vector3.new(0, 0, 1200) })
	kit.truthy("un camino el doble de largo lleva bastante más rastro", #largo > #rastro * 1.5)
	kit.eq("camino demasiado corto, sin rastro", #Contacts.rastro({ origen, Vector3.new(0, 0, 120) }), 0)
	kit.eq("un camino de un solo punto no revienta", #Contacts.rastro({ origen }), 0)

	-- LAS DORADAS: cuántas del rastro pagan. Lo que importa es que el jugador
	-- cobre lo mismo aunque la ciudad se coma piezas al plantar.
	local dorados = Contacts.indicesDorados(20, 6)
	local cuantasDoradas = 0
	for _ in dorados do
		cuantasDoradas += 1
	end
	kit.eq("dora exactamente las que se le piden", cuantasDoradas, 6)

	-- Repartidas, no amontonadas al principio: si se agruparan, la segunda mitad
	-- del viaje dejaría de pagar justo cuando más cuesta seguir.
	local primeraMitad, segundaMitad = 0, 0
	for i in dorados do
		if i <= 10 then
			primeraMitad += 1
		else
			segundaMitad += 1
		end
	end
	kit.truthy("hay doradas en la primera mitad", primeraMitad > 0)
	kit.truthy("y en la segunda", segundaMitad > 0)

	local todas = Contacts.indicesDorados(4, 10)
	local cuantasTodas = 0
	for _ in todas do
		cuantasTodas += 1
	end
	kit.eq("si se piden más doradas que piezas, se doran todas y no revienta", cuantasTodas, 4)
	local ninguna = 0
	for _ in Contacts.indicesDorados(0, 6) do
		ninguna += 1
	end
	kit.eq("sin piezas plantadas no hay doradas", ninguna, 0)

	-- La ruta entera, por su id.
	kit.truthy("la verde reparte rastro y su racimo", #Contacts.deRuta("verde", recta, peligros) > 10)
	kit.eq("una ruta desconocida no revienta, devuelve vacío", #Contacts.deRuta("gris", recta, peligros), 0)

	-- LA RACHA. Acelera, tiene tope, y NUNCA deja al jugador fuera de alcance.
	kit.eq("sin recoger nada, no hay racha", Contacts.racha(0), 0)
	kit.near("cada pieza vale lo que dice Config", Contacts.racha(3), 3 * Config.RACHA_POR_CONTACTO)
	kit.eq("la racha tiene tope", Contacts.racha(999), Config.RACHA_MAXIMA)
	kit.near("la racha se suma a la velocidad", Contacts.velocidadConRacha(16, 3), 16 + 3 * Config.RACHA_POR_CONTACTO)

	-- UNA SOLA PIEZA TIENE QUE NOTARSE, y esto no es una preferencia: es la regla
	-- que el sistema incumplia. Con 0,4 studs/s sobre 16, coger un rayo movia la
	-- velocidad un 2,5 % -- por debajo de lo que un ojo distingue, asi que el premio
	-- existia en el HUD y en ningun otro sitio. El diez por ciento es el suelo por
	-- debajo del cual esto vuelve a ser una estadistica.
	kit.truthy(
		"un solo rayo mueve la velocidad a pie mas de un diez por ciento",
		Config.RACHA_POR_CONTACTO / Config.VELOCIDAD_BASE > 0.1
	)
	-- Y LA CADENA TIENE QUE PODER GANAR A QUIEN TE PERSIGUE, o el rayo no sirve
	-- para huir --que es para lo que se pidio-- sino solo para llegar antes. La
	-- patrulla va a la velocidad del perseguido SIN racha mas 3 (PatrolService), asi
	-- que el tope tiene que sacarle mas de esos 3 studs/s de ventaja.
	kit.truthy("la racha al tope adelanta a la patrulla", Config.RACHA_MAXIMA > 3)

	-- LA CADENA. Es lo que convierte el rastro en un juego en vez de en un pasillo
	-- decorado: si recoger seis al principio rindiera igual que seguir la fila
	-- entera, el rastro no pediría nada y no engancharía.
	kit.eq("recogiendo sin parar no se pierde nada", Contacts.rachaTrasEspera(10, 0), 10)
	kit.eq("dentro de la gracia tampoco", Contacts.rachaTrasEspera(10, Config.RACHA_GRACIA), 10)
	kit.eq(
		"pasada la gracia se cae una pieza por segundo",
		Contacts.rachaTrasEspera(10, Config.RACHA_GRACIA + 3),
		10 - 3 * Config.RACHA_DECAE
	)
	kit.eq("y se cae a cero, sin suelo", Contacts.rachaTrasEspera(10, Config.RACHA_GRACIA + 999), 0)
	kit.eq("nunca baja de cero", Contacts.rachaTrasEspera(0, 999), 0)

	-- LA GRACIA TIENE QUE CUBRIR EL PASO DEL RASTRO, o quien va por la fila la
	-- pierde sin haberse salido -- que es el fallo que convertiría la cadena en un
	-- impuesto. A pie cargado (lo más lento que se juega) se pisa una píldora cada
	-- RASTRO_PASO / velocidad segundos.
	local segundosEntrePildoras = Config.RASTRO_PASO / Config.VELOCIDAD_BASE
	kit.truthy("quien sigue el rastro a pie no pierde nunca la cadena", segundosEntrePildoras < Config.RACHA_GRACIA)
	kit.truthy(
		"ni el vehículo más rápido con la racha al tope pasa el antitrampas",
		Contacts.velocidadConRacha(34, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)
	kit.truthy(
		"una velocidad base absurda se recorta igual",
		Contacts.velocidadConRacha(999, 999) < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
	)

	-- LO QUE CADUCA AL ACABAR EL VIAJE. La regla es "lo que se recoge por el camino
	-- se queda en el camino", y hasta hoy sólo la cumplía la racha: el salto y el
	-- escudo sobrevivían a la entrega, que además te devuelve al muelle al instante.
	local viaje = {
		recogidos = 5,
		saltoHasta = 1000,
		escudoHasta = 1000,
		contactos = 7,
		marcadoHasta = 1234,
		dinero = 900,
	}
	kit.truthy("terminar el viaje avisa de que había algo que apagar", Contacts.terminarViaje(viaje))
	kit.eq("la racha se cae entera", viaje.recogidos, 0)
	kit.eq("el salto no viaja al porte siguiente", viaje.saltoHasta, nil)
	kit.eq("y el escudo tampoco", viaje.escudoHasta, nil)
	-- Y LA OTRA MITAD DE LA REGLA, que es la que evita convertir un arreglo en un
	-- robo: lo ganado para siempre no se toca, y el castigo del que acaba de robar
	-- tampoco -- si se limpiara, entregar sería la forma de esquivarlo.
	kit.eq("los contactos ganados no se pierden", viaje.contactos, 7)
	kit.eq("el dinero tampoco", viaje.dinero, 900)
	kit.eq("y la marca del ladrón sigue corriendo", viaje.marcadoHasta, 1234)

	-- Sin nada que apagar, dice que no: quien lo llama cinco veces por segundo se
	-- ahorra sincronizar el estado entero a todo el servidor de balde.
	kit.falsy("un viaje ya limpio no cambia nada", Contacts.terminarViaje(viaje))
	kit.falsy("y un estado recién nacido tampoco", Contacts.terminarViaje({ recogidos = 0 }))
end
