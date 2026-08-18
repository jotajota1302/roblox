--!strict
--[[
	SelfCheck.luau — la batería de escenario: comprueba EL MUNDO YA CONSTRUIDO.

	Se lanza con el juego corriendo (datamodel Server, en Play):

		return require(game.ServerScriptService.Server.SelfCheck).run()

	POR QUÉ EXISTE, y por qué no basta con las pruebas de shared/tests. Aquéllas
	comprueban las REGLAS y son puras: dado un estado, ¿qué manda el juego? Se
	ejecutan en un milisegundo y no necesitan mundo. Pero ni una sola de ellas
	podía cazar los fallos que de verdad nos han costado sesiones enteras, porque
	todos eran del MUNDO y no de las reglas:

	  · la mitad de los detectores plantada en las azoteas -- reglas perfectas,
	    vigilancia que no vigilaba nada, y la ruta roja entera dando calor 0;
	  · el almacén encima de una pista de baloncesto, con la canasta asomando por
	    el tejado;
	  · una carretera de acceso enterrada bajo el césped media longitud;
	  · un taller plantado sesenta studs por debajo de la ciudad, sin una calle a
	    doscientos studs a la redonda;
	  · la "calle más cercana" de una ruta, que era una azotea veinte studs por
	    encima del destino.

	Todos comparten la misma firma: NADA REVIENTA. El juego arranca, se puede
	jugar, y simplemente es más fácil o más raro de lo que dice ser. Ésa es la
	clase de fallo que una persona no encuentra jugando y que una sonda encuentra
	en cinco segundos.

	La regla de esta batería: **cada comprobación mide el mundo, no repite una
	cuenta del código**. Comprobar que `Config.RUTAS[1].detectores == 3` no vale
	nada; contar los postes plantados sí.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Goods = require(game.ReplicatedStorage.Shared.Goods)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)

local SelfCheck = {}

type Resultado = { nombre: string, ok: boolean, detalle: string }

local resultados: { Resultado } = {}

local function comprobar(nombre: string, ok: boolean, detalle: string?)
	table.insert(resultados, { nombre = nombre, ok = ok, detalle = detalle or "" })
end

local function mundo(): Instance?
	return workspace:FindFirstChild("Mundo")
end

-- Lo que hay bajo un punto, mirando desde la altura de la cabeza y no desde el
-- cielo. Es la diferencia entre medir el suelo y medir el primer tejado, que es
-- el error que se repite en este proyecto desde el primer día.
local function bajoLosPies(x: number, y: number, z: number, alcance: number?): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	return workspace:Raycast(Vector3.new(x, y + 6, z), Vector3.new(0, -(alcance or 14), 0), params)
end

local function esPisable(golpe: RaycastResult?): boolean
	if golpe == nil then
		return false
	end
	return golpe.Instance:GetAttribute("rodable") == true or Roads.esCalzada(golpe.Instance.Color)
end

-- Distancia de un punto al trayecto almacén→destino, medida en el plano. Es la
-- cuenta que decide si un poste vigila algo o es un adorno.
local function alTrayecto(punto: Vector3, destino: Vector3): number
	local a = Vector2.new(Config.ALMACEN_POS.X, Config.ALMACEN_POS.Z)
	local b = Vector2.new(destino.X, destino.Z)
	local p = Vector2.new(punto.X, punto.Z)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

--------------------------------------------------------------------------------
-- 1. Las piezas del juego están, y están donde el jugador las va a buscar.
--------------------------------------------------------------------------------
local function piezasDelJuego()
	local m = mundo()
	comprobar("el mundo del juego existe", m ~= nil, "no hay workspace.Mundo")
	if m == nil then
		return
	end

	local losas = { "Almacen", "Salida", "Taller" }
	for _, ruta in Routes.todas() do
		table.insert(losas, "Destino_" .. ruta.id)
	end

	for _, nombre in losas do
		local pieza = m:FindFirstChild(nombre)
		comprobar("está " .. nombre, pieza ~= nil, "falta la pieza")
		if pieza == nil or not pieza:IsA("BasePart") then
			continue
		end

		-- TODA losa del juego es rodable. Si una se queda sin el atributo, la regla
		-- de la calzada echa al jugador del vehículo al entrar en su propio muelle,
		-- y eso se lee como un juego roto, no como una regla.
		comprobar(nombre .. " es rodable", pieza:GetAttribute("rodable") == true, "sin atributo rodable")

		-- Y NINGUNA ENTERRADA. Una losa por debajo del suelo que la rodea no se ve,
		-- no se pisa y su aviso de "pulsa aquí" no llega: el jugador da vueltas
		-- encima de su destino sin encontrarlo.
		local techo = pieza.Position.Y + pieza.Size.Y / 2
		local golpe = bajoLosPies(pieza.Position.X, techo, pieza.Position.Z, 8)
		comprobar(
			nombre .. " se pisa por arriba",
			golpe ~= nil and golpe.Instance == pieza,
			string.format("lo que se pisa ahí es %s", if golpe then golpe.Instance.Name else "nada")
		)
	end

	comprobar("la salida tiene baliza", m:FindFirstChild("Baliza_Salida") ~= nil, "no se ve desde dentro del recinto")
end

--------------------------------------------------------------------------------
-- 2. La vigilancia vigila. El fallo histórico del proyecto.
--------------------------------------------------------------------------------
local function vigilancia()
	local m = mundo()
	if m == nil then
		return
	end

	for _, ruta in Routes.todas() do
		local postes: { BasePart } = {}
		for _, x in m:GetChildren() do
			if x:IsA("BasePart") and x:GetAttribute("ruta") == ruta.id and string.match(x.Name, "^Detector_") then
				table.insert(postes, x)
			end
		end
		comprobar(
			string.format("la %s tiene sus %d detectores", ruta.id, ruta.detectores),
			#postes == ruta.detectores,
			string.format("hay %d", #postes)
		)

		-- CON LOS PIES EN EL SUELO. Un poste sobre un tejado no se dispara jamás:
		-- por debajo pasa la calle, a ochenta studs de su radio de treinta y cinco.
		local enElAire = 0
		for _, poste in postes do
			local base = poste.Position.Y - poste.Size.Y / 2
			if bajoLosPies(poste.Position.X, base, poste.Position.Z, 10) == nil then
				enElAire += 1
			end
		end
		comprobar(
			string.format("los detectores de la %s tocan suelo", ruta.id),
			enElAire == 0,
			string.format("%d en el aire", enElAire)
		)

		-- Y ALCANZAN EL CAMINO. Es la cuenta que este proyecto se saltó dos veces:
		-- si el desvío respecto al trayecto es mayor que el radio, la vigilancia no
		-- vigila nada aunque los postes existan y se vean perfectamente.
		local alcanzan = 0
		for _, poste in postes do
			if alTrayecto(poste.Position, ruta.destino) <= Config.DETECTOR_RADIO then
				alcanzan += 1
			end
		end
		comprobar(
			string.format("la %s tiene vigilancia sobre el camino", ruta.id),
			alcanzan >= 1,
			string.format("ninguno de los %d postes llega al trayecto", #postes)
		)
	end
end

--------------------------------------------------------------------------------
-- 3. Se puede llegar rodando: los accesos, pisados a ras de suelo.
--------------------------------------------------------------------------------
local function accesos()
	local m = mundo()
	if m == nil then
		return
	end

	local grupos: { [string]: { { n: number, p: BasePart } } } = {}
	for _, x in m:GetChildren() do
		local base, num = string.match(x.Name, "^(Acceso[%a_]*)_(%d+)$")
		if base and x:IsA("BasePart") then
			grupos[base] = grupos[base] or {}
			table.insert(grupos[base], { n = tonumber(num) :: number, p = x })
		end
	end

	-- UNO POR DESTINO Y UNO POR TALLER DE ZONA, más el de casa. Que falte un acceso
	-- no rompe nada visible: simplemente la mercancía grande, que EXIGE vehículo,
	-- llega a un sitio donde el vehículo no entra.
	local cuantos = 0
	for _ in grupos do
		cuantos += 1
	end
	comprobar(
		"cada destino y el polígono tienen carretera",
		cuantos >= 1 + #Routes.todas(),
		string.format("hay %d grupos de acceso, se esperaban al menos %d", cuantos, 1 + #Routes.todas())
	)

	for base, lista in grupos do
		table.sort(lista, function(a, b)
			return a.n < b.n
		end)
		local malos, total = 0, 0
		for i = 1, #lista - 1 do
			local a, b = lista[i].p.Position, lista[i + 1].p.Position
			for k = 0, 6 do
				local p = a:Lerp(b, k / 6)
				total += 1
				if not esPisable(bajoLosPies(p.X, p.Y, p.Z, 12)) then
					malos += 1
				end
			end
		end
		-- El 95 % y no el 100 %: algún tramo pasa bajo el voladizo del taller y el
		-- rayo se come el techo. Un agujero de verdad hunde el porcentaje entero.
		local bien = if total > 0 then (total - malos) / total else 0
		comprobar(
			base .. " se pisa de punta a punta",
			bien >= 0.95,
			string.format("%d de %d puntos sin asfalto debajo", malos, total)
		)
	end

	-- Y LA SALIDA DE CASA, el trozo que más veces se ha roto: la vía nacía
	-- enterrada bajo la losa de la salida y reaparecía dos studs y medio más abajo
	-- justo donde la losa se acaba.
	local malos, total = 0, 0
	local desde, hasta = Config.POLIGONO_SALIDA, Config.POLIGONO_ENGANCHE
	for i = 0, 60 do
		local p = Vector3.new(desde.X, 0, desde.Z):Lerp(Vector3.new(hasta.X, 0, hasta.Z), i / 60)
		total += 1
		if not esPisable(bajoLosPies(p.X, Config.POLIGONO_CENTRO.Y, p.Z, 30)) then
			malos += 1
		end
	end
	comprobar(
		"de casa a la ciudad se va rodando",
		malos == 0,
		string.format("%d de %d puntos del camino sin asfalto", malos, total)
	)
end

--------------------------------------------------------------------------------
-- 4. La puerta del recinto cierra la boca entera.
--------------------------------------------------------------------------------
local function puerta()
	local postes = Perimeter.postes(Config.RECINTO_PANELES)
	local izquierda, derecha = math.huge, -math.huge
	for _, poste in postes do
		izquierda = math.min(izquierda, poste.posicion.X - poste.ancho / 2)
		derecha = math.max(derecha, poste.posicion.X + poste.ancho / 2)
	end
	comprobar(
		"la puerta tapa la boca del polígono",
		derecha - izquierda >= Config.POLIGONO_TAMANO.X,
		string.format("la valla mide %.0f y la boca %.0f", derecha - izquierda, Config.POLIGONO_TAMANO.X)
	)

	-- Y SIN JUNTAS: dos paneles que se tocan justo en la punta dejan pasar por la
	-- juntura en cuanto el suelo no es perfectamente plano.
	local abierta = false
	for i = 1, #postes - 1 do
		local finA = postes[i].posicion.X + postes[i].ancho / 2
		local iniB = postes[i + 1].posicion.X - postes[i + 1].ancho / 2
		if iniB > finA then
			abierta = true
		end
	end
	comprobar("los paneles de la puerta solapan", not abierta, "hay una junta abierta entre dos paneles")
end

--------------------------------------------------------------------------------
-- 5. Los refugios: los hay, están separados, y cada ruta tiene uno a mano.
--------------------------------------------------------------------------------
local function refugios()
	local m = mundo()
	if m == nil then
		return
	end

	local sitios: { Vector3 } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and string.match(x.Name, "^Refugio_%d+$") then
			table.insert(sitios, x.Position)
		end
	end
	comprobar("hay refugios plantados", #sitios >= 1, "ninguno -- el calor no se puede bajar en ninguna ruta")

	local juntos = 0
	for i = 1, #sitios do
		for j = i + 1, #sitios do
			local d = (Vector3.new(sitios[i].X, 0, sitios[i].Z) - Vector3.new(sitios[j].X, 0, sitios[j].Z)).Magnitude
			if d < Config.REFUGIO_SEPARACION * 0.8 then
				juntos += 1
			end
		end
	end
	comprobar(
		"los refugios están espaciados",
		juntos == 0,
		string.format("%d parejas más cerca de %d studs", juntos, math.floor(Config.REFUGIO_SEPARACION * 0.8))
	)

	-- A MANO DE SU RUTA. Un refugio que existe pero cae a doscientos studs del
	-- camino es peor que ninguno: el jugador lo ve en el mapa, se desvía hacia él
	-- y pierde justo el tiempo que venía a ganar.
	local alcance = Config.REFUGIO_DESVIO + Config.REFUGIO_RADIO
	for _, ruta in Routes.todas() do
		local cerca = 0
		for _, sitio in sitios do
			if alTrayecto(sitio, ruta.destino) <= alcance then
				cerca += 1
			end
		end
		comprobar(
			string.format("la %s tiene refugio a mano", ruta.id),
			cerca >= 1,
			string.format("el más cercano se sale de los %d studs de desvío", alcance)
		)
	end
end

--------------------------------------------------------------------------------
-- 6. La economía conserva su jerarquía: más riesgo, más dinero por minuto.
--------------------------------------------------------------------------------
local function economia()
	-- Un viaje de libro: el zurrón lleno de cajas comunes. Lo que se comprueba no
	-- es el número --eso ya lo hace Economy.spec-- sino que el ORDEN se mantiene
	-- con los valores que hay hoy. El día que alguien toque una capacidad o un
	-- multiplicador, esto es lo que avisa de que la roja ha dejado de compensar.
	local porMinuto: { [string]: number } = {}
	for _, ruta in Routes.todas() do
		local cajas = {}
		for _ = 1, Config.CAPACIDAD_A_PIE do
			table.insert(cajas, { rareza = "comun" })
		end
		local valor = Economy.valorEntrega(cajas :: any, ruta.multiplicador)
		-- Minutos estimados: ida y vuelta en línea recta, a la velocidad cargada.
		-- Es una cota optimista igual para las tres, y eso es lo que hace
		-- comparables los tres números.
		local distancia = (Config.ALMACEN_POS - ruta.destino).Magnitude * 2
		local velocidad = Config.VELOCIDAD_BASE - Config.PENALIZACION_POR_CAJA * Config.CAPACIDAD_A_PIE
		porMinuto[ruta.id] = valor / (distancia / velocidad / 60)
	end
	comprobar(
		"la ámbar paga más por minuto que la verde",
		porMinuto.ambar > porMinuto.verde,
		string.format("verde %.0f/min, ámbar %.0f/min", porMinuto.verde, porMinuto.ambar)
	)
	comprobar(
		"la roja paga más por minuto que la ámbar",
		porMinuto.roja > porMinuto.ambar,
		string.format("ámbar %.0f/min, roja %.0f/min", porMinuto.ambar, porMinuto.roja)
	)

	-- Y EL PRIMER PELDAÑO SE ALCANZA PRONTO. Si el primer vehículo cuesta más de
	-- unos pocos viajes, el dinero no significa nada en la primera sesión -- y la
	-- primera sesión es la única que casi todo el mundo llega a jugar.
	local primero = nil
	for _, v in Config.VEHICULOS do
		if v.coste > 0 and (primero == nil or v.coste < primero.coste) then
			primero = v
		end
	end
	if primero then
		local viajes = primero.coste / (Config.CAJA_VALOR_BASE * Config.CAPACIDAD_A_PIE)
		comprobar(
			"el primer vehículo cae en pocos viajes",
			viajes <= 8,
			string.format("%s cuesta %d: %.1f viajes verdes llenos", primero.nombre, primero.coste, viajes)
		)
	end
end

--------------------------------------------------------------------------------
-- 7. El puente cliente/servidor está entero.
--------------------------------------------------------------------------------
local function puente()
	local carpeta = game.ReplicatedStorage:FindFirstChild("Remotes")
	local faltan: { string } = {}
	for clave, valor in Remotes :: any do
		if type(valor) == "string" and type(clave) == "string" then
			if carpeta == nil or carpeta:FindFirstChild(valor) == nil then
				table.insert(faltan, valor)
			end
		end
	end
	-- Un remote que no existe al arrancar no da error: el cliente hace WaitForChild
	-- y espera para siempre. Interbloqueo perfecto, pantalla en blanco.
	comprobar("todos los remotes existen al arrancar", #faltan == 0, "faltan: " .. table.concat(faltan, ", "))
end

--------------------------------------------------------------------------------
-- 8. Coste del mundo: esto tiene que ir en un móvil.
--------------------------------------------------------------------------------
local function coste()
	local piezas = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			piezas += 1
		end
	end
	-- No es un límite del motor: es el listón que nos ponemos por el "móvil
	-- primero" de CLAUDE.md.
	comprobar("el mundo cabe en un móvil", piezas <= 20000, string.format("%d piezas en workspace", piezas))

	local ciudades = 0
	for _, x in workspace:GetChildren() do
		if x.Name == "Ciudad" then
			ciudades += 1
		end
	end
	comprobar(
		"hay UNA ciudad, no dos",
		ciudades <= 1,
		string.format("%d modelos llamados Ciudad -- dos mapas superpuestos", ciudades)
	)
end

--------------------------------------------------------------------------------
-- 9. INFORME. Números medidos, sin aprobado ni suspenso.
--
-- No son comprobaciones porque no hay un valor "correcto": son las cifras con las
-- que se decide de diseño. La última --cuántos viajes cuesta comprarlo TODO-- es
-- la que dice cuánto dura el juego antes de quedarse sin objetivos, y ésa no se
-- puede estimar a ojo porque depende de tres cosas a la vez: qué sale del almacén,
-- cuánto cabe en cada vehículo y qué paga cada ruta.
--------------------------------------------------------------------------------
local function informe(): { string }
	local lineas: { string } = {}
	local rng = Random.new(20260818)

	-- LO QUE VALE Y LO QUE OCUPA CADA PIEZA. A ojo no sale: la rareza NO se sortea
	-- con las probabilidades de Config.RAREZAS --eso es sólo la tabla de
	-- multiplicadores-- sino con la frecuencia de cada objeto del catálogo, y
	-- encima filtrada por lo que el jugador puede mover.
	local function valorDe(objeto): number
		return Economy.valorCaja({ rareza = objeto.rareza, objeto = objeto.id }, 1)
	end

	-- UN VIAJE COMO LO HARÍA ALGUIEN QUE PIENSA: el almacén te ofrece hasta
	-- ALMACEN_TOPE piezas y tú te llevas las que más pagan por hueco ocupado. Es
	-- importante modelarlo así y no "el zurrón lleno de lo más grande": lo segundo
	-- da un número bonito y falso.
	local function porViaje(vehiculoId: string, multiplicador: number): number
		local def = Vehicles.get(vehiculoId)
		local nivel = def.tamanoMaximo or 1
		local suma, N = 0, 300
		for _ = 1, N do
			local oferta = {}
			for _ = 1, Config.ALMACEN_TOPE do
				local objeto = Goods.tirada(rng, nivel)
				table.insert(oferta, {
					valor = valorDe(objeto),
					huecos = Goods.huecos(objeto.id),
					cabe = Goods.nivelExigido(objeto.id) <= nivel,
				})
			end
			table.sort(oferta, function(a, b)
				return a.valor / a.huecos > b.valor / b.huecos
			end)
			local libre, cobrado = def.capacidad, 0
			for _, pieza in oferta do
				if pieza.cabe and pieza.huecos <= libre then
					libre -= pieza.huecos
					cobrado += pieza.valor
				end
			end
			suma += cobrado
		end
		return suma / N * multiplicador
	end

	table.insert(lineas, "monedas por viaje (almacén lleno, cargando lo que más paga):")
	for _, vehiculoId in { Config.VEHICULO_INICIAL, "bicicleta", "furgoneta" } do
		local nombre = Vehicles.get(vehiculoId).nombre
		table.insert(
			lineas,
			string.format(
				"  · %-12s verde %6.0f   ámbar %6.0f   roja %7.0f",
				nombre,
				porViaje(vehiculoId, 1),
				porViaje(vehiculoId, 3),
				porViaje(vehiculoId, 10)
			)
		)
	end

	-- LO QUE PAGA CADA TAMAÑO POR HUECO OCUPADO. Si un tamaño paga menos por hueco
	-- que el anterior, llevarlo es una pérdida y el objeto grande deja de ser una
	-- meta para convertirse en una trampa -- por muy vistoso que sea.
	table.insert(lineas, "lo que paga cada tamaño por hueco:")
	for nivel = 1, 4 do
		local suma, huecos = 0, 0
		for _, objeto in Goods.todos() do
			if Goods.nivelExigido(objeto.id) == nivel then
				suma += valorDe(objeto) * objeto.frecuencia
				huecos += Goods.huecos(objeto.id) * objeto.frecuencia
			end
		end
		if huecos > 0 then
			table.insert(
				lineas,
				string.format("  · %-8s %.2f monedas por hueco", Config.TAMANOS[nivel].nombre, suma / huecos)
			)
		end
	end

	-- CUÁNTO PESA UN ALMACÉN LLENO. Es el techo real de la capacidad: comprar un
	-- vehículo que quepa más que esto no cambia nada, porque no hay más que llevar.
	local pesoTotal, N = 0, 300
	for _ = 1, N do
		for _ = 1, Config.ALMACEN_TOPE do
			pesoTotal += Goods.huecos(Goods.tirada(rng, 4).id)
		end
	end
	table.insert(
		lineas,
		string.format(
			"un almacén lleno pesa %.0f huecos: por encima de eso, la capacidad no sirve de nada",
			pesoTotal / N
		)
	)

	-- CUÁNTO DURA EL JUEGO. El garaje es hoy el único sumidero de dinero que existe,
	-- así que comprarlo entero es literalmente quedarse sin objetivos.
	local total = 0
	for _, v in Config.VEHICULOS do
		total += v.coste
	end
	table.insert(
		lineas,
		string.format(
			"el garaje entero cuesta %d monedas: %.0f viajes verdes a pie, o %.0f rojos en furgoneta",
			total,
			total / math.max(porViaje(Config.VEHICULO_INICIAL, 1), 1),
			total / math.max(porViaje("furgoneta", 10), 1)
		)
	)

	local ida = (Config.ALMACEN_POS - Routes.get("verde").destino).Magnitude
	local velocidad = Config.VELOCIDAD_BASE - Config.PENALIZACION_POR_CAJA * Config.CAPACIDAD_A_PIE
	table.insert(
		lineas,
		string.format(
			"ida y vuelta a la verde a pie: %.0f s en recta (andando de verdad, bastante más)",
			ida * 2 / velocidad
		)
	)

	return lineas
end

--------------------------------------------------------------------------------

function SelfCheck.run(): string
	resultados = {}

	local pasos: { { nombre: string, fn: () -> () } } = {
		{ nombre = "piezas del juego", fn = piezasDelJuego },
		{ nombre = "vigilancia", fn = vigilancia },
		{ nombre = "accesos", fn = accesos },
		{ nombre = "puerta", fn = puerta },
		{ nombre = "refugios", fn = refugios },
		{ nombre = "economía", fn = economia },
		{ nombre = "puente", fn = puente },
		{ nombre = "coste", fn = coste },
	}
	-- Cada sonda va en su pcall: interesa ver TODOS los rojos de una pasada, no
	-- pararse en el primero.
	for _, paso in pasos do
		local ok, err = pcall(paso.fn)
		if not ok then
			comprobar("la sonda de " .. paso.nombre .. " no revienta", false, tostring(err))
		end
	end

	local lineas: { string } = {}
	local fallos = 0
	for _, r in resultados do
		if r.ok then
			table.insert(lineas, "[ok] " .. r.nombre)
		else
			fallos += 1
			table.insert(lineas, string.format("[X] %s -- %s", r.nombre, r.detalle))
		end
	end

	local veredicto = if fallos == 0
		then string.format("MUNDO OK (%d comprobaciones)", #resultados)
		else string.format("FALLOS: %d de %d comprobaciones", fallos, #resultados)
	local ok, medidas = pcall(informe)
	local cola = if ok then "\n\n-- INFORME --\n" .. table.concat(medidas :: { string }, "\n") else ""
	return veredicto .. "\n" .. table.concat(lineas, "\n") .. cola
end

return SelfCheck
