--!strict
--[[
	Contacts.luau — los contactos que se recogen por el camino. Módulo PURO.

	POR QUÉ EXISTE. Medido: toda la experiencia del juego se otorgaba en una sola
	línea de CargoService, al entregar. Los 54-100 segundos de viaje no daban nada
	y sólo podían quitar. Esto pone algo bueno dentro del viaje sin tocar la
	economía de monedas, que ya está equilibrada.

	DOS POBLACIONES, CON TRABAJOS DISTINTOS:

	  · el RASTRO es una fila continua sobre la calzada, una píldora cada
	    RASTRO_PASO studs. Marca POR DÓNDE se va y acelera al seguirlo. No paga:
	    unas cuantas de sus piezas se doran al plantarlas y ésas sí;
	  · los RACIMOS se apartan hacia un peligro y dan la DECISIÓN. Su desvío es
	    menor que el de una guarida (55 frente a 70) para que el rodeo sea un
	    rodeo y no una expedición.

	EL RASTRO SUSTITUYÓ A LOS SUELTOS el 19/08, y el motivo lo dio JJ jugando: "es
	muy largo, nada atractivo". Los sueltos eran SEIS en la ruta verde -- uno cada
	128 studs, uno cada ocho segundos-- y un número fijo repartía igual de pocos en
	400 studs que en 1.800. Eso ni marcaba camino ni se sentía como premio
	continuo. El reparto por paso fijo hace las dos cosas, y de paso arregla algo
	que no era de premio sino de orientación: la brújula dice hacia dónde, pero no
	por dónde. La fila de luces sí.

	FIJOS Y APRENDIBLES, como los detectores y las guaridas: el reparto sale del
	trazado, no de un dado. El jugador que repite la ruta sabe dónde están.

	Y SE REPARTEN SOBRE EL CAMINO REAL, no sobre la recta entre casa y destino.
	Esto no es un detalle: la primera versión los repartía sobre la recta y, medido
	contra el camino que calcula el pathfinder, **caían en el camino el 0 % de la
	ruta verde, el 8 % de la ámbar y el 5 % de la roja**. Treinta y ocho piezas
	plantadas, alumbradas y con sus atributos, y ninguna al alcance de nadie. Es la
	misma firma que los quince detectores en las azoteas: nada revienta y el
	sistema simplemente no existe.

	Por eso la entrada de este módulo es una POLILÍNEA y no un par origen-destino.
	Un par de puntos sigue valiendo (es una polilínea de dos), pero quien tenga el
	camino de verdad debe pasarlo.
]]

local Config = require(script.Parent.Config)

export type Contacto = { pos: Vector3, valor: number, tipo: string }

local Contacts = {}

-- Longitud de cada tramo de la polilínea, MEDIDA EN EL PLANO. Las cuestas de la
-- ciudad no cuentan como distancia recorrida para esto: lo que importa es dónde
-- pisa el jugador, no cuánto sube.
local function tramos(camino: { Vector3 }): ({ number }, number)
	local largos: { number } = {}
	local total = 0
	for i = 1, #camino - 1 do
		local a, b = camino[i], camino[i + 1]
		local d = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		largos[i] = d
		total += d
	end
	return largos, total
end

-- El punto del camino que está a `distancia` studs del principio.
local function puntoA(camino: { Vector3 }, largos: { number }, distancia: number): Vector3
	local recorrido = 0
	for i = 1, #largos do
		if recorrido + largos[i] >= distancia then
			local t = if largos[i] > 0 then (distancia - recorrido) / largos[i] else 0
			return camino[i]:Lerp(camino[i + 1], t)
		end
		recorrido += largos[i]
	end
	return camino[#camino]
end

-- La dirección del camino en ese punto, en el plano. La usan los racimos para
-- saber hacia qué lado apartarse; con la dirección global (casa -> destino) un
-- racimo de una curva se apartaba hacia dentro de la manzana.
local function direccionEn(camino: { Vector3 }, largos: { number }, distancia: number): Vector3
	local recorrido = 0
	for i = 1, #largos do
		if recorrido + largos[i] >= distancia or i == #largos then
			local a, b = camino[i], camino[i + 1]
			local plano = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if plano.Magnitude > 0.01 then
				return plano.Unit
			end
		end
		recorrido += largos[i]
	end
	return Vector3.new(0, 0, 1)
end

-- Un racimo por peligro, apartado del camino a la altura de ese peligro. Sin
-- peligros no hay racimos: su razón de ser es estar junto a uno, así que uno
-- suelto en mitad de ninguna parte sería un premio sin apuesta.
function Contacts.racimos(camino: { Vector3 }, peligros: { Vector3 }, cuantos: number): { Contacto }
	local salida: { Contacto } = {}
	if cuantos <= 0 or #peligros == 0 or #camino < 2 then
		return salida
	end

	local largos, total = tramos(camino)

	for i = 1, math.min(cuantos, #peligros) do
		local ancla = peligros[i]
		-- ¿A qué altura del camino queda este peligro? De ahí sale hacia dónde
		-- apartarse, para que el racimo caiga ENTRE el camino y la guarida.
		local mejor, mejorD = 0, math.huge
		local recorrido = 0
		for j = 1, #largos do
			local a, b = camino[j], camino[j + 1]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if ab.Magnitude > 0.01 then
				local ap = Vector3.new(ancla.X - a.X, 0, ancla.Z - a.Z)
				local t = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
				local d = (ap - ab.Unit * t).Magnitude
				if d < mejorD then
					mejorD = d
					mejor = recorrido + t
				end
			end
			recorrido += largos[j]
		end

		local enElCamino = puntoA(camino, largos, math.clamp(mejor, 0, total))
		local hacia = ancla - enElCamino
		local plano = Vector3.new(hacia.X, 0, hacia.Z)
		-- Si la guarida está justo encima del camino, se aparta perpendicular: un
		-- racimo en mitad de la calzada no sería un rodeo.
		local desvio = if plano.Magnitude > 1
			then plano.Unit
			else Vector3.new(direccionEn(camino, largos, mejor).Z, 0, -direccionEn(camino, largos, mejor).X)

		table.insert(salida, {
			pos = enElCamino + desvio * Config.CONTACTO_RACIMO_DESVIO,
			valor = Config.CONTACTO_VALOR_RACIMO,
			tipo = "racimo",
		})
	end

	return salida
end

-- EL RASTRO: la fila continua de píldoras que dibuja el camino.
--
-- Su número NO se pide: sale del largo del camino y del paso. Con paso fijo, cada
-- ruta lleva las que le caben, y el jugador aprende una sola regla en vez de
-- cuatro: si hay hueco entre luces, te has salido del camino.
function Contacts.rastro(camino: { Vector3 }): { Contacto }
	local salida: { Contacto } = {}
	if #camino < 2 then
		return salida
	end

	local largos, total = tramos(camino)
	local desde = Config.ZONA_SEGURA_RADIO + Config.RASTRO_DESDE
	local hasta = total - Config.RASTRO_HASTA
	if hasta <= desde then
		return salida
	end

	-- CUANTOS CABEN, y despues se reparten a partes iguales por el corredor. Antes
	-- se avanzaba de RASTRO_PASO en RASTRO_PASO hasta que no cupiera otro, y esa
	-- diferencia --que parece de estilo-- resolvia mal las rutas cortas.
	--
	-- MEDIDO EL 20/08, y es la clase de averia que este proyecto ya conoce: nada
	-- reventaba, la sonda daba verde y la ruta VERDE tenia UN SOLO rayo. El corredor
	-- util son 89 studs (224 de camino menos los 110 de zona segura y los 25 del
	-- final), asi que con paso fijo entraban uno o dos -- y su economia reparte
	-- CUATRO doradas. Es decir: la primera ruta del juego, la que aprende todo el
	-- mundo, no ensenaba el sistema, y ademas pagaba la mitad de lo que su tabla
	-- decia, porque las doradas se reparten sobre las que existen.
	--
	-- La causa es que la ruta se acorto de 558 a 147 studs el 19/08 y el paso del
	-- rastro se quedo donde estaba. Un numero absoluto no sobrevive a que cambie
	-- aquello que mide.
	local disponible = hasta - desde
	-- `ceil` y no `floor`, que es la diferencia entre "caben N" y "no queda ningun
	-- vano mayor que el paso". Con `floor` la separacion real sale POR ENCIMA de
	-- RASTRO_PASO al repartir el sobrante (42 studs con el paso en 40), y el paso
	-- deja de ser lo que promete: un techo. Lo cazo la prueba que lo vigila.
	local cuantas = math.max(Config.RASTRO_MINIMO, math.ceil(disponible / Config.RASTRO_PASO) + 1)
	-- El ultimo cae EXACTAMENTE en `hasta`, o sea a las puertas del destino: quien
	-- sigue la fila tiene que acabar en la entrega, no quedarse a medio tramo.
	local paso = disponible / (cuantas - 1)

	for k = 0, cuantas - 1 do
		table.insert(salida, {
			pos = puntoA(camino, largos, desde + k * paso),
			valor = Config.CONTACTO_VALOR_RASTRO,
			-- SE ALTERNAN velocidad y salto. Empieza por velocidad porque es la que
			-- ya conoce quien viene de antes, y porque el salto sin haber cogido
			-- carrerilla no lleva a ninguna parte.
			--
			-- Alternar por INDICE y no por sorteo es la regla de este mapa: el reparto
			-- sale del trazado, asi que la segunda vez que haces una ruta sabes cual
			-- viene -- y poder planear es lo que separa una decision de una loteria.
			tipo = if k % 2 == 0 then Config.RECOGIBLE_VELOCIDAD else Config.RECOGIBLE_SALTO,
		})
	end

	return salida
end

-- ¿Es del rastro? Antes bastaba comparar con "rastro"; desde que hay dos clases,
-- la pregunta "esto es una pieza de la fila" hay que hacerla en un solo sitio o el
-- dia que entre una tercera clase habra media docena de comparaciones que actualizar
-- y una que se quedara atras.
function Contacts.esDelRastro(tipo: string): boolean
	return tipo == Config.RECOGIBLE_VELOCIDAD or tipo == Config.RECOGIBLE_SALTO
end

-- CUÁLES DEL RASTRO SON DORADAS, o sea cuáles además pagan un contacto.
--
-- Devuelve índices y no piezas, y esa forma tiene un motivo práctico: al plantar,
-- unas cuantas píldoras se caen del reparto porque no hay calle donde tocaban
-- (`sembrarContactos` las descarta). Si el dorado se decidiera aquí sobre la
-- lista teórica, cada píldora perdida se llevaría por delante una moneda y la
-- economía de habilidades saldría distinta en cada ruta sin que nadie lo supiera.
--
-- Repartiendo sobre las que SE PLANTARON de verdad, el jugador cobra siempre lo
-- mismo aunque la ciudad se coma piezas.
function Contacts.indicesDorados(plantadas: number, cuantas: number): { [number]: boolean }
	local marca: { [number]: boolean } = {}
	if plantadas <= 0 or cuantas <= 0 then
		return marca
	end
	if cuantas >= plantadas then
		for i = 1, plantadas do
			marca[i] = true
		end
		return marca
	end
	-- Repartidas, no las primeras: si se agruparan al principio, la segunda mitad
	-- del viaje dejaría de pagar justo cuando más cuesta seguir.
	for i = 1, cuantas do
		marca[math.floor((i - 0.5) * plantadas / cuantas) + 1] = true
	end
	return marca
end

-- CUÁNTA RACHA QUEDA tras un rato sin recoger nada. La cadena, en una función
-- pura para que se pueda comprobar sin mundo.
--
-- La gracia es lo que la hace justa: un semáforo, una curva o esquivar un ladrón
-- no pueden costarte el viaje. Pasada, se cae despacio -- y se cae a cero, no a
-- un mínimo, porque un suelo convertiría "abandonar el rastro" en una opción
-- barata y el rastro dejaría de pedir nada.
function Contacts.rachaTrasEspera(recogidos: number, segundosSinRecoger: number): number
	if recogidos <= 0 then
		return 0
	end
	local sobra = segundosSinRecoger - Config.RACHA_GRACIA
	if sobra <= 0 then
		return recogidos
	end
	return math.max(0, recogidos - math.floor(sobra * Config.RACHA_DECAE))
end

function Contacts.deRuta(rutaId: string, camino: { Vector3 }, peligros: { Vector3 }): { Contacto }
	local cuantos = Config.CONTACTOS_POR_RUTA[rutaId]
	if not cuantos then
		return {}
	end

	-- El rastro va SIN dorar: quién paga se decide al plantar, sobre las que de
	-- verdad encontraron calle (ver indicesDorados).
	local salida = Contacts.rastro(camino)
	-- SIN RACIMOS. Eran grupos de piezas apartados del camino, junto a un peligro:
	-- pagaban más a cambio de desviarte. La idea era buena y el resultado, jugado, fue
	-- "salen paquetes fuera de la ruta y no se pueden coger" -- porque desde el camino
	-- se VEN, y lo que se ve y no se alcanza no se lee como una decisión sino como un
	-- fallo.
	--
	-- Vuelven cuando el desvío se pueda entender de un vistazo. Hoy la fila de la
	-- calle es todo lo que hay, y es lo que hace falta que funcione.
	return salida
end

-- LA MEDIDA QUE IMPORTA: cuántos recoge de verdad quien recorre el camino.
--
-- Es la misma comprobación que Detectors.disparadosEnLineaRecta y existe por lo
-- mismo, sólo que aquí ya cazó su fallo: con el reparto sobre la recta, esto daba
-- 0 de 7 en la ruta verde. Un contacto que el jugador no pisa es decorado.
function Contacts.cercaDelCamino(contactos: { Contacto }, camino: { Vector3 }, radio: number): number
	if #camino < 2 then
		return 0
	end

	local cuenta = 0
	for _, c in contactos do
		local mejor = math.huge
		for i = 1, #camino - 1 do
			local a, b = camino[i], camino[i + 1]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			if ab.Magnitude < 0.01 then
				continue
			end
			-- EN EL PLANO. Medir en 3D convirtió una vez 83 studs de altura en "83
			-- studs de desviación".
			local ap = Vector3.new(c.pos.X - a.X, 0, c.pos.Z - a.Z)
			local t = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
			local d = (ap - ab.Unit * t).Magnitude
			if d < mejor then
				mejor = d
			end
		end
		if mejor <= radio then
			cuenta += 1
		end
	end
	return cuenta
end

-- LA RACHA: lo que has acelerado por lo que llevas recogido EN ESTE VIAJE.
--
-- La velocidad permanente está descartada (Levels.luau lo dice en su cabecera):
-- chocaría con la regla de que nadie puede volverse inalcanzable, y sin alcance no
-- hay PvP. Ésta es la salida que usa el juego que lo inspiró: la velocidad es del
-- intento, no tuya -- corres, aceleras, y un paso en falso te devuelve al
-- principio. Quien la aplique la borra al entregar y al ser alcanzado.
function Contacts.racha(recogidos: number): number
	if recogidos <= 0 then
		return 0
	end
	return math.min(recogidos * Config.RACHA_POR_CONTACTO, Config.RACHA_MAXIMA)
end

-- EL RECORTE NO ES DECORATIVO: es la regla de oro escrita en un número. El
-- antitrampas expulsa a quien pase de Config.VELOCIDAD_MAXIMA_PLAUSIBLE, así que
-- la suma se queda por debajo con margen -- y de paso, una velocidad base absurda
-- (un fallo en otro sitio) no puede colarse por aquí.
function Contacts.velocidadConRacha(base: number, recogidos: number): number
	return math.min(base + Contacts.racha(recogidos), Config.VELOCIDAD_MAXIMA_PLAUSIBLE - 2)
end

return Contacts
