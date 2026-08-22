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

local Players = game:GetService("Players")

local PathfindingService = game:GetService("PathfindingService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Caches = require(game.ReplicatedStorage.Shared.Caches)
local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
local Goods = require(game.ReplicatedStorage.Shared.Goods)
local Bounds = require(game.ReplicatedStorage.Shared.Bounds)
local Grid = require(game.ReplicatedStorage.Shared.Grid)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Perimeter = require(game.ReplicatedStorage.Shared.Perimeter)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local Vision = require(game.ReplicatedStorage.Shared.Vision)

local SelfCheck = {}

type Resultado = { nombre: string, ok: boolean, detalle: string }

local resultados: { Resultado } = {}

-- A DONDE VA CADA RUTA, LEIDO DEL MUNDO Y NO DE `Config`.
--
-- Es la correccion mas importante de esta bateria, y viene de una tarde entera de
-- rojos sobre un mundo que estaba perfecto.
--
-- Desde que los destinos se sortean al arrancar (`Destinations.luau`), `ruta.destino`
-- es un dato de EJECUCION: lo escribe el servidor en su copia de `Config`. Y esta
-- bateria se lanza por el MCP con `execute_luau`, que corre en un SANDBOX con su
-- propia cache de `require` -- o sea que aqui `Config` es un modulo recien ejecutado
-- y sus destinos son los de DISENO, no los de la partida.
--
-- El resultado era un catalogo de fallos fantasma: "solo 4 de 7 migas al alcance",
-- "un alijo cae sobre una ruta"... midiendo un mundo correcto contra caminos que no
-- existen. La firma es reconocible -- las cosas del mundo estaban de acuerdo entre
-- si (las migas con su casa de entrega) y el unico que discrepaba era el dato.
--
-- La losa `Destino_<ruta>` la planta `CityBuilder` en el sitio de verdad, asi que
-- leerla es medir lo que se construyo, que es la unica regla que tiene una sonda.
local function destinoDeRuta(mundo: Instance?, rutaId: string, respaldo: Vector3): Vector3
	if mundo == nil then
		return respaldo
	end
	local losa = mundo:FindFirstChild("Destino_" .. rutaId)
	if losa and losa:IsA("BasePart") then
		return losa.Position
	end
	return respaldo
end

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
	-- LOS PERSONAJES FUERA. Sin esto, la sonda mide a quien esté de pie encima: la
	-- primera vez que se corrió con alguien parado sobre el almacén, el veredicto
	-- fue "lo que se pisa ahí es Handle" -- el sombrero del jugador. Una batería
	-- que falla según dónde se haya parado alguien no sirve para decidir nada.
	local fuera: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(fuera, p.Character)
		end
	end
	-- Y los ladrones, que son personajes también y andan por el mapa.
	local ladrones = workspace:FindFirstChild("Ladrones") or workspace:FindFirstChild("Patrullas")
	if ladrones then
		table.insert(fuera, ladrones)
	end
	params.FilterDescendantsInstances = fuera
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
-- DISTANCIA AL CAMINO, y el camino es una L por las calles.
--
-- Esto medía contra la RECTA del almacén al destino, que era el camino de verdad
-- mientras el mapa fue una explanada. Desde que la ciudad es una retícula, la recta es
-- la diagonal de la L: por ahí no pasa nadie. La sonda daba rojo a guaridas y refugios
-- que estaban exactamente donde tenían que estar -- sobre el corredor-- porque los
-- medía contra un camino que ya no existe.
--
-- Es el mismo fallo que tuvieron las migas de pan hoy mismo, y por el mismo motivo:
-- cuando cambia por dónde se va, hay que cambiar contra qué se mide.
local function alTrayecto(punto: Vector3, destino: Vector3): number
	local puntos = Grid.porCalles(Config.POLIGONO_SALIDA, destino)
	local p = Vector2.new(punto.X, punto.Z)
	local mejor = math.huge
	for i = 2, #puntos do
		local a = Vector2.new(puntos[i - 1].X, puntos[i - 1].Z)
		local b = Vector2.new(puntos[i].X, puntos[i].Z)
		local ab = b - a
		if ab:Dot(ab) > 0.01 then
			local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
			mejor = math.min(mejor, (p - (a + ab * t)).Magnitude)
		end
	end
	return mejor
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

	-- La salida ya no lleva baliza: el 19/08 se quitó todo lo vertical del mapa. Lo que
	-- se comprueba ahora es que la losa esté, que es lo que se pisa y lo que lleva el
	-- cartel.
	comprobar("la salida existe", m:FindFirstChild("Salida") ~= nil, "no hay losa de salida")
end

--------------------------------------------------------------------------------
-- 2. La vigilancia vigila. El fallo histórico del proyecto.
--------------------------------------------------------------------------------
local function vigilancia()
	local m = mundo()
	if m == nil then
		return
	end

	local postes: { BasePart } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and string.match(x.Name, "^Detector_") then
			table.insert(postes, x)
		end
	end

	-- LA VIGILANCIA ES DE LA CIUDAD, NO DE CADA RUTA. Hasta el 20/08 se sembraba sobre
	-- la recta de cada corredor y esta sonda contaba los de cada uno, y con ella se nos
	-- escapaba lo importante: fuera de los corredores el mapa estaba a oscuras, asi que
	-- lo mas rapido era ignorar el camino marcado. Ahora va una en cada cruce de la
	-- reticula y lo que hay que comprobar cambia -- no "cuantas tiene la roja" sino que
	-- NINGUNA RUTA SE PUEDA HACER LIMPIA.
	comprobar(
		"hay vigilancia plantada",
		#postes >= 1,
		"ninguna esquina fichada -- se puede cruzar la ciudad sin que nadie te vea"
	)
	if #postes == 0 then
		return
	end

	-- CON LOS PIES EN EL SUELO. Una esquina sobre un tejado no se dispara jamas: por
	-- debajo pasa la calle, a ochenta studs de su radio. La base se saca del CFrame y no
	-- de Size.Y, porque es un CILINDRO TUMBADO -- su Size.Y es el DIAMETRO, no la
	-- altura, y medirlo por Y daba "31 en el aire" con el mundo perfecto. Un falso rojo
	-- es la peor averia que puede tener una sonda: ensena a ignorarla.
	local enElAire = 0
	for _, poste in postes do
		local mitad = poste.CFrame:VectorToWorldSpace(poste.Size / 2)
		local base = poste.Position.Y - math.abs(mitad.Y)
		if bajoLosPies(poste.Position.X, base + 0.5, poste.Position.Z, 10) == nil then
			enElAire += 1
		end
	end
	comprobar("la vigilancia toca el suelo", enElAire == 0, string.format("%d en el aire", enElAire))

	-- CUANTAS ESQUINAS TE FICHAN DE VERDAD recorriendo una ruta.
	--
	-- Antes esto contaba las esquinas que quedaban a menos de DETECTOR_RADIO del
	-- trayecto, y esa cuenta dejo de valer el 20/08: desde que la esquina MIRA, estar
	-- cerca no basta -- hay que caer en su cono y sin pared de por medio. Contar por
	-- distancia diria que la ruta esta vigilada cuando quiza todas sus esquinas miran
	-- al otro lado, que es exactamente la clase de "existe y no hace nada" que esta
	-- bateria existe para cazar.
	--
	-- Asi que se anda el camino de verdad, muestra a muestra, aplicando las MISMAS dos
	-- condiciones que aplica HeatService.
	local function fichanDeVerdad(ruta: any): number
		local puntos = Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino)
		local vistas: { [BasePart]: boolean } = {}
		local cuenta = 0
		for i = 1, #puntos - 1 do
			local a, b = puntos[i], puntos[i + 1]
			local largo = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
			local pasos = math.max(1, math.floor(largo / 8))
			for k = 0, pasos do
				local donde = a:Lerp(b, k / pasos) + Vector3.new(0, 3, 0)
				for _, poste in postes do
					if vistas[poste] then
						continue
					end
					if (donde - poste.Position).Magnitude > Config.DETECTOR_RADIO then
						continue
					end
					local rumbo = poste:GetAttribute("rumbo")
					if typeof(rumbo) == "number" then
						local mirando = (CFrame.Angles(0, math.rad(rumbo), 0) * CFrame.new(0, 0, -1)).Position
						if
							not Vision.dentroDelCono(
								poste.Position,
								mirando,
								donde,
								Config.DETECTOR_VISION_ANGULO,
								Config.DETECTOR_RADIO
							)
						then
							continue
						end
						local params = RaycastParams.new()
						params.FilterType = Enum.RaycastFilterType.Exclude
						params.FilterDescendantsInstances = { poste }
						if workspace:Raycast(poste.Position, donde - poste.Position, params) ~= nil then
							continue
						end
					end
					vistas[poste] = true
					cuenta += 1
				end
			end
		end
		return cuenta
	end

	-- Y NINGUNA RUTA SE HACE LIMPIA. Es la comprobacion que de verdad importa:
	-- recorriendo el camino de cualquier ruta te tienen que fichar al menos una vez.
	-- Si una da CERO, su selector promete un peligro que no existe -- y eso ya paso,
	-- con la roja entera dando calor 0.
	local fichanPorRuta: { [string]: number } = {}
	for _, ruta in Routes.todas() do
		local fichan = fichanDeVerdad(ruta)
		fichanPorRuta[ruta.id] = fichan
		comprobar(
			string.format("la %s pasa por vigilancia que la MIRA", ruta.id),
			fichan >= 1,
			string.format("ninguna de las %d esquinas la ve: se hace limpia", #postes)
		)
	end

	-- Y QUE LA LARGA ESTE MAS VIGILADA QUE LA CORTA. Con el reparto por cruces esto sale
	-- solo --una ruta larga cruza mas cruces-- y por eso mismo hay que comprobarlo: lo
	-- que sale solo es lo que nadie mantiene, y el dia que alguien mueva un destino la
	-- progresion de dificultad puede darse la vuelta sin que nada avise.
	local function cuantasFichan(ruta: any): number
		return fichanPorRuta[ruta.id] or 0
	end
	local verde, roja = Routes.get("verde"), Routes.get("roja")
	if verde ~= nil and roja ~= nil then
		comprobar(
			"la roja esta mas vigilada que la verde",
			cuantasFichan(roja) > cuantasFichan(verde),
			string.format("verde %d, roja %d", cuantasFichan(verde), cuantasFichan(roja))
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
	-- SE COMPRUEBA LO QUE IMPORTA --que al destino se pueda llegar rodando-- y no
	-- cuántas carreteras hay. Un destino que YA cae sobre una calle de la ciudad no
	-- necesita acceso propio, y `acceso()` no lo construye: con el mundo encogido eso
	-- pasó en dos de las cuatro rutas, y contar grupos daba rojo por un mundo que
	-- estaba bien. Contar piezas es fácil; medir lo que el jugador necesita, no.
	local sinCalzada = {}
	for _, ruta in Routes.todas() do
		local losa = m:FindFirstChild("Destino_" .. ruta.id)
		if losa == nil or not losa:IsA("BasePart") then
			continue
		end
		local rueda = false
		for _, d in workspace:GetDescendants() do
			if not d:IsA("BasePart") or d == losa then
				continue
			end
			local dist = math.sqrt((d.Position.X - losa.Position.X) ^ 2 + (d.Position.Z - losa.Position.Z) ^ 2)
			if dist <= 70 and (d:GetAttribute("rodable") == true or Roads.esCalzada(d.Color)) then
				rueda = true
				break
			end
		end
		if not rueda then
			table.insert(sinCalzada, ruta.id)
		end
	end
	comprobar(
		"a cada destino se puede llegar rodando",
		#sinCalzada == 0,
		string.format("sin calzada a mano: %s", table.concat(sinCalzada, ", "))
	)

	for base, lista in grupos do
		table.sort(lista, function(a, b)
			return a.n < b.n
		end)
		-- LOS PUNTOS QUE SE RECORREN. Hasta el 19/08 esto iba de una pieza a la
		-- siguiente, porque una vía eran ocho tramos encadenados y lo único que podía
		-- fallar eran las juntas. Con suelo propio una vía es UNA losa recta, así que
		-- ese bucle no daba ni una vuelta y la sonda cantaba "0 de 0 puntos" -- un
		-- rojo que no era del mundo sino de una sonda que había dejado de saber qué
		-- estaba midiendo. Ahora, con una sola pieza, se recorre la pieza de punta a
		-- punta: es lo que la comprobación decía que hacía desde el principio.
		local puntos: { Vector3 } = {}
		if #lista == 1 then
			local via = lista[1].p
			local mitad = via.Size.Z / 2
			puntos = {
				via.CFrame:PointToWorldSpace(Vector3.new(0, 0, -mitad)),
				via.CFrame:PointToWorldSpace(Vector3.new(0, 0, mitad)),
			}
		else
			for _, e in lista do
				table.insert(puntos, e.p.Position)
			end
		end

		local malos, total = 0, 0
		for i = 1, #puntos - 1 do
			local a, b = puntos[i], puntos[i + 1]
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

	-- NI ESCALONES. Es el defecto que dejó el juego sin salida: *"el vehículo no
	-- sale de la zona inicial y se queda enganchado en el mapa"* (JJ). Las vías se
	-- montan por tramos que se solapan, y dos tramos seguidos con inclinaciones
	-- opuestas se cruzan dejando el canto de uno asomando sobre el otro. Se recorre
	-- la superficie de cada vía y se mira el salto entre pasos: cualquier cosa por
	-- encima de un bordillo es un muro contra el que se choca.
	local peorSalto, dondeSalto = 0, ""
	for base, lista in grupos do
		table.sort(lista, function(a, b)
			return a.n < b.n
		end)
		local anterior: number? = nil
		for i = 1, #lista - 1 do
			local a, b = lista[i].p.Position, lista[i + 1].p.Position
			-- Cada tres studs: un escalón mide dos o tres, y con pasos más largos se
			-- cuela entre dos muestras justo el sitio donde se traba el vehículo.
			local pasos = math.max(3, math.floor((a - b).Magnitude / 3))
			for k = 0, pasos do
				local punto = a:Lerp(b, k / pasos)
				local golpe = bajoLosPies(punto.X, punto.Y + 6, punto.Z, 20)
				if golpe == nil then
					anterior = nil
					continue
				end
				local y = golpe.Position.Y
				if anterior ~= nil and math.abs(y - anterior) > peorSalto then
					peorSalto = math.abs(y - anterior)
					dondeSalto = string.format("%s cerca de (%.0f, %.0f)", base, punto.X, punto.Z)
				end
				anterior = y
			end
		end
	end
	comprobar(
		"las vías no tienen escalones",
		peorSalto <= 2.5,
		string.format("salto de %.1f studs en %s -- ahí se traba el vehículo", peorSalto, dondeSalto)
	)

	-- Y NADA DE LA CIUDAD LES SALE POR MEDIO. Medido: cinco tramos de acceso
	-- atravesaban vallas -- las mismas con las que el pathfinding de los ladrones
	-- ya se atasca. Una vía con una valla dentro no es una vía; es una valla con
	-- asfalto debajo, y quien llegue conduciendo se queda parado sin saber por qué.
	local ciudad = workspace:FindFirstChild("Ciudad")
	if ciudad ~= nil then
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Include
		op.FilterDescendantsInstances = { ciudad }
		op.MaxParts = 40
		local atravesados, ejemplo = 0, ""
		for _, pieza in m:GetChildren() do
			if not pieza:IsA("BasePart") or not string.match(pieza.Name, "^Acceso") then
				continue
			end
			-- Sólo el volumen SOBRE el firme: una vía se apoya en el suelo y lo pisa
			-- por definición, así que medir hacia abajo sería contar el suelo.
			local dentro = workspace:GetPartBoundsInBox(
				pieza.CFrame * CFrame.new(0, 7, 0),
				Vector3.new(pieza.Size.X, 11, pieza.Size.Z),
				op
			)
			for _, c in dentro do
				local padre = c.Parent
				if padre ~= nil and padre.Name == "Tree" then
					continue
				end
				-- Lo enorme no cuenta: si un edificio entero roza la vía, el problema
				-- es el trazado y lo dice otra comprobación.
				if math.max(c.Size.X, c.Size.Y, c.Size.Z) > 200 then
					continue
				end
				atravesados += 1
				ejemplo = string.format("%s dentro de %s", c.Name, pieza.Name)
				break
			end
		end
		comprobar(
			"ninguna vía atraviesa nada de la ciudad",
			atravesados == 0,
			string.format("%d tramos con algo dentro (p. ej. %s)", atravesados, ejemplo)
		)
	end
end

---------------------------------------------------------------------------------
-- 3b. Las viviendas de entrega existen y no las pisa nadie.
---------------------------------------------------------------------------------
local function viviendas()
	local m = mundo()
	if m == nil then
		return
	end
	local sinCasa, invadidas, detalle = 0, 0, ""
	for _, ruta in Routes.todas() do
		local casa = m:FindFirstChild("Vivienda_" .. ruta.id) :: BasePart?
		if casa == nil then
			sinCasa += 1
			continue
		end
		-- QUE NO HAYA NADA METIDO DENTRO. Es la firma exacta del fallo que la estreno:
		-- la vivienda se planta en `mundo` y el buscador de parcela del taller solo
		-- mira dentro de `ciudad`, asi que para el era invisible -- y los talleres de
		-- la verde y la ambar salieron con el tejado, los escaparates y el rotulo
		-- DENTRO del bloque de pisos. No revienta nada: es una fachada que no se puede
		-- leer, que es lo contrario de para lo que existe.
		-- LA CAJA DE LA CASA, no la de una pared.
		--
		-- Desde que la vivienda es HUECA, `casa` ya no es un bloque macizo sino una de
		-- sus jambas: medir contra su Size daba una caja de 17x40x1,4 pegada a la
		-- fachada, y ahi dentro caben las OTRAS PAREDES de la propia casa. La sonda se
		-- puso roja con "verde(6)" sin que nada estuviera mal -- se estaba midiendo
		-- contra si misma, que es el falso rojo mas facil de creerse.
		--
		-- Se reconstruye la caja del edificio a partir de sus piezas, que es lo unico
		-- que sigue siendo verdad cuando cambia como esta hecho por dentro.
		local piezas = { casa }
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, #casa.Name) == casa.Name then
				table.insert(piezas, d)
			end
		end
		local min, max = casa.Position, casa.Position
		for _, d in piezas do
			local mitad = d.Size / 2
			min = Vector3.new(
				math.min(min.X, d.Position.X - mitad.X),
				math.min(min.Y, d.Position.Y - mitad.Y),
				math.min(min.Z, d.Position.Z - mitad.Z)
			)
			max = Vector3.new(
				math.max(max.X, d.Position.X + mitad.X),
				math.max(max.Y, d.Position.Y + mitad.Y),
				math.max(max.Z, d.Position.Z + mitad.Z)
			)
		end

		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = piezas
		params.MaxParts = 80
		local ajenas = 0
		for _, d in workspace:GetPartBoundsInBox(CFrame.new((min + max) / 2), (max - min) * 0.9, params) do
			-- El suelo y el asfalto no invaden: la casa se apoya en ellos. Ni los conos
			-- de las camaras, que son una mancha pintada sin volumen.
			-- LO QUE NO INVADE, aunque este dentro de la caja: el suelo y el asfalto
			-- (la casa se apoya en ellos), los conos de camara (una mancha pintada sin
			-- volumen) y los RECOGIBLES con sus piezas -- un rayo flotando junto a la
			-- fachada no estorba a nadie, no colisiona y encima es exactamente donde
			-- tiene que estar: la fila acaba en la puerta.
			--
			-- Los hijos hay que nombrarlos uno a uno porque `GetPartBoundsInBox`
			-- devuelve descendientes, no raices: sin `Rayo` y `Ala` la sonda contaba
			-- doce invasores donde habia dos recogibles.
			local suyo = d.Name
			if
				suyo ~= "Suelo"
				and suyo ~= "Asfalto"
				and suyo ~= "ConoDetector"
				and suyo ~= "Vista"
				and suyo ~= "VistaBorde"
				and suyo ~= "Rayo"
				and suyo ~= "Ala"
				and suyo ~= "Derrape"
				and string.match(suyo, "^Calle") == nil
				and string.match(suyo, "^Contacto_") == nil
			then
				ajenas += 1
			end
		end
		if ajenas > 0 then
			invadidas += 1
			detalle ..= string.format(" %s(%d)", ruta.id, ajenas)
		end
	end
	comprobar("cada ruta entrega en una vivienda", sinCasa == 0, string.format("%d rutas sin vivienda", sinCasa))
	comprobar("y nadie tiene medio taller dentro de casa", invadidas == 0, "invadidas:" .. detalle)
end

---------------------------------------------------------------------------------
-- 3c. Ningun recogible cae donde te fichan.
---------------------------------------------------------------------------------
local function recogiblesLimpios()
	local m = mundo()
	if m == nil then
		return
	end
	local camaras, piezas = {}, {}
	for _, d in m:GetChildren() do
		if not d:IsA("BasePart") then
			continue
		end
		if string.match(d.Name, "^Detector_") then
			table.insert(camaras, d)
		elseif string.match(d.Name, "^Contacto_") then
			table.insert(piezas, d)
		end
	end

	-- LA REGLA, dicha por JJ: *"no los pongamos en zonas con camara de vigilancia,
	-- que eso es tener mala leche"*. Un premio puesto donde te fichan no es una
	-- decision, es una trampa -- la fila dice "ven por aqui" y el sitio al que lleva
	-- te sube el calor. El juego se contradice y el jugador deja de fiarse de la
	-- unica guia que tiene.
	--
	-- Se mide con las MISMAS condiciones que HeatService. Dos verdades sobre donde
	-- te ven acaban discrepando, y la que discrepa siempre es la que nadie mira.
	local pillados, detalle = 0, ""
	for _, pieza in piezas do
		for _, poste in camaras do
			local rumbo = poste:GetAttribute("rumbo")
			if typeof(rumbo) ~= "number" then
				continue
			end
			if (pieza.Position - poste.Position).Magnitude > Config.DETECTOR_RADIO then
				continue
			end
			local mirando = (CFrame.Angles(0, math.rad(rumbo), 0) * CFrame.new(0, 0, -1)).Position
			if
				not Vision.dentroDelCono(
					poste.Position,
					mirando,
					pieza.Position,
					Config.DETECTOR_VISION_ANGULO,
					Config.DETECTOR_RADIO
				)
			then
				continue
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { poste, pieza }
			if workspace:Raycast(poste.Position, pieza.Position - poste.Position, params) == nil then
				pillados += 1
				if #detalle < 70 then
					detalle ..= " " .. pieza.Name
				end
				break
			end
		end
	end
	-- LA MAYORIA, no todos. La siembra intenta apartar del cono cada pieza que le
	-- toca en uno, pero si no encuentra hueco la planta igual: descartarla deja un
	-- vano en la fila, y un vano se lee como "te has salido de la ruta" -- mentira, y
	-- ademas rompe la cadena de velocidad. Medido con el descarte puesto: los
	-- recogibles pasaron de 33 a TRES.
	--
	-- Una vigilada suelta no es mala leche mientras el cono SE VEA, que se ve. Lo que
	-- esta sonda impide es que vuelvan a serlo casi todas.
	comprobar(
		"casi ningun recogible cae en el cono de una camara",
		pillados <= math.max(1, math.floor(#piezas * 0.2)),
		string.format("%d de %d vigilados:%s", pillados, #piezas, detalle)
	)

	-- Y QUE SIGAN SALIENDO LAS TRES CLASES. Apartar piezas de los conos puede
	-- comerse justo las de una --boost, salto o escudo-- y dejar una ruta sin ella:
	-- es la clase de sesgo que nadie ve porque el juego sigue funcionando, y que
	-- convierte "tres herramientas" en "una y media" sin que nadie lo decida.
	for _, ruta in Routes.todas() do
		local hay: { [string]: number } = {}
		for _, pieza in piezas do
			if pieza:GetAttribute("ruta") ~= ruta.id then
				continue
			end
			local t = tostring(pieza:GetAttribute("tipo"))
			hay[t] = (hay[t] or 0) + 1
		end
		local faltan = {}
		for _, clase in Config.RECOGIBLES do
			if (hay[clase] or 0) == 0 then
				table.insert(faltan, clase)
			end
		end
		comprobar(
			string.format("la %s reparte las tres clases de recogible", ruta.id),
			#faltan == 0,
			"falta: " .. table.concat(faltan, ", ")
		)
	end
end

--------------------------------------------------------------------------------
-- 4. La puerta del recinto cierra la boca entera.
--------------------------------------------------------------------------------
local function puerta()
	-- LA BOCA, que es el unico lado por el que se sale. Desde que la valla es un
	-- ANILLO hay que pedirla aparte: `Perimeter.postes` devuelve los cuatro lados, y
	-- medir juntas sobre la lista entera compara el panel de una esquina con el del
	-- lado siguiente -- que por supuesto no solapan en X, porque no estan en X. Esta
	-- sonda se puso roja el dia del anillo diciendo "junta abierta" con la puerta
	-- perfectamente cerrada: un falso rojo, que es la peor averia de una sonda.
	local postes = Perimeter.postesDeLaBoca(Config.RECINTO_PANELES)
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

	-- Y EL ANILLO ENTERO, que es lo que se pidio: *"que envuelva toda la zona"*. Se
	-- cuenta cuantos paneles caen en cada uno de los cuatro lados. Un lado a cero es
	-- una valla que solo cierra por delante, que es como estaba y no se leia.
	local centro, medida = Config.POLIGONO_CENTRO, Config.POLIGONO_TAMANO
	local porLado = { 0, 0, 0, 0 }
	local anillo = Perimeter.postes(Config.RECINTO_PANELES)
	for _, poste in anillo do
		if math.abs(poste.posicion.Z - (centro.Z - medida.Y / 2)) < 0.01 then
			porLado[1] += 1
		elseif math.abs(poste.posicion.Z - (centro.Z + medida.Y / 2)) < 0.01 then
			porLado[2] += 1
		elseif math.abs(poste.posicion.X - (centro.X - medida.X / 2)) < 0.01 then
			porLado[3] += 1
		elseif math.abs(poste.posicion.X - (centro.X + medida.X / 2)) < 0.01 then
			porLado[4] += 1
		end
	end
	local vacios = 0
	for _, n in porLado do
		if n < 2 then
			vacios += 1
		end
	end
	comprobar(
		"la valla envuelve el recinto entero",
		vacios == 0,
		string.format(
			"%d de los 4 lados sin vallar (%d/%d/%d/%d)",
			vacios,
			porLado[1],
			porLado[2],
			porLado[3],
			porLado[4]
		)
	)
end

--------------------------------------------------------------------------------
-- 5b. Las guaridas: existen, se pueden rodear, y ninguna cae en zona segura.
--------------------------------------------------------------------------------
local function guaridas()
	local m = mundo()
	if m == nil then
		return
	end

	local sitios: { BasePart } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and x:GetAttribute("guarida") == true then
			table.insert(sitios, x)
		end
	end
	-- CON LAS GUARIDAS APAGADAS, ESTA SONDA CALLA. Desde el 20/08
	-- `GUARIDAS_POR_RUTA` es 0 --se apagaron a peticion de JJ, ver el comentario en
	-- Config-- y exigir guaridas seria dar rojo por cumplir una decision. Lo que NO se
	-- hace es borrar las comprobaciones: el dia que se vuelvan a encender, tienen que
	-- estar esperandolas.
	if Config.GUARIDAS_POR_RUTA <= 0 then
		comprobar(
			"sin guaridas, no queda ninguna suelta en el mapa",
			#sitios == 0,
			string.format("%d plantadas con el sistema apagado", #sitios)
		)
		return
	end

	comprobar(
		"hay guaridas plantadas",
		#sitios >= 1,
		"ninguna -- los ladrones vuelven a salir de la nada, que es lo que esto venía a arreglar"
	)

	-- NINGUNA EN LA ZONA SEGURA. El almacén no es asaltable nunca, y una guarida
	-- pegada a casa contradiría esa promesa sin romperla del todo: el jugador
	-- vería salir ladrones del sitio donde se supone que está a salvo.
	local dentro = 0
	for _, g in sitios do
		local d = (Vector3.new(g.Position.X, 0, g.Position.Z) - Vector3.new(
			Config.ALMACEN_POS.X,
			0,
			Config.ALMACEN_POS.Z
		)).Magnitude
		if d <= Config.ZONA_SEGURA_RADIO then
			dentro += 1
		end
	end
	comprobar("ninguna guarida en la zona segura", dentro == 0, string.format("%d dentro del radio seguro", dentro))

	-- Y CADA RUTA TIENE LA SUYA CERCA DEL CAMINO: una guarida a trescientos studs
	-- del corredor no la rodea nadie porque nadie pasa por allí, y entonces la ruta
	-- se queda sin la amenaza que anuncia su selector.
	local alcance = Config.GUARIDA_DESVIO + 90
	for _, ruta in Routes.todas() do
		-- Salvo las que NO PIDEN NINGUNA, que hoy es el barrio: allí el peligro se
		-- enseña y no se aplica, así que exigirle una guarida es pedirle que
		-- incumpla su propio diseño. Mismo criterio que ya se aplicó a los refugios
		-- --una ruta sin ladrones no necesita dónde esconderse-- y por el mismo
		-- motivo: sin este guard, la sonda da un rojo permanente que enseña a
		-- ignorarla, que es la peor avería que puede tener una sonda.
		if (ruta.guaridas or Config.GUARIDAS_POR_RUTA) <= 0 then
			continue
		end
		local cerca = 0
		for _, g in sitios do
			if g:GetAttribute("ruta") == ruta.id and alTrayecto(g.Position, ruta.destino) <= alcance then
				cerca += 1
			end
		end
		comprobar(
			string.format("la %s tiene guarida sobre su camino", ruta.id),
			cerca >= 1,
			"ninguna de las suyas cae cerca del corredor"
		)
	end

	-- Se pisan: si una quedara flotando o enterrada, el ladrón saldría del aire.
	local malas = 0
	for _, g in sitios do
		local techo = g.Position.Y + g.Size.Y / 2
		local golpe = bajoLosPies(g.Position.X, techo, g.Position.Z, 8)
		if golpe == nil or golpe.Instance ~= g then
			malas += 1
		end
	end
	comprobar("las guaridas están apoyadas en el suelo", malas == 0, string.format("%d flotando o enterradas", malas))

	-- SIN FAROL QUE COMPROBAR. Aquí se medía que el farol de cada guarida asomara por
	-- encima del caserío, para que se pudiera ver y rodear. Las guaridas ya no llevan
	-- columna --se quitó todo lo vertical el 19/08-- así que la comprobación se va con
	-- ella. Lo que hace falta en su lugar es que al ladrón se le VEA venir, y eso se
	-- mide sobre el ladrón, no sobre su casa.
end

--------------------------------------------------------------------------------
-- 5. Los refugios: los hay, están separados, y cada ruta tiene uno a mano.
--------------------------------------------------------------------------------
local function refugios()
	local m = mundo()
	if m == nil then
		return
	end
	-- CON EL MAPA DESNUDO NO HAY REFUGIOS, y eso no es un fallo sino la prueba de
	-- que el interruptor funciona. Una sonda que se pone roja por algo que se
	-- apago a proposito ensena a ignorar los rojos, que es la peor averia que le
	-- puede pasar a una bateria de comprobaciones.
	if Config.MAPA_DESNUDO then
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

	-- NI UNO A LA SALIDA DEL ALMACÉN. Lo vio JJ jugando y la sonda no lo miraba: el
	-- de la ruta verde estaba a 230 studs de casa, con la puerta a 35 studs de donde
	-- acaba la zona segura. Pegado al almacén, un refugio no es una decisión --el
	-- almacén apaga el calor entero y encima es donde cobras-- y una opción que
	-- nunca puede ganar es una opción que no existe.
	-- El criterio es LA ZONA SEGURA y nada más: la puerta del refugio tiene que
	-- quedar fuera de ella. Antes sumaba medio REFUGIO_MARGEN_CASA encima, y al
	-- reescalar el mundo eso pedía un centro a 177 studs cuando `Shelter` sólo
	-- garantiza 85 -- dos números peleándose por decir lo mismo, y la sonda dando
	-- rojo por un refugio perfectamente colocado.
	local minimo = Config.ZONA_SEGURA_RADIO
	local pegados, elMasCerca = 0, math.huge
	for _, sitio in sitios do
		local d = (Vector3.new(sitio.X, 0, sitio.Z) - Vector3.new(Config.ALMACEN_POS.X, 0, Config.ALMACEN_POS.Z)).Magnitude
			- Config.REFUGIO_RADIO
		elMasCerca = math.min(elMasCerca, d)
		if d < minimo then
			pegados += 1
		end
	end
	comprobar(
		"ningún refugio a la salida del almacén",
		pegados == 0,
		string.format("%d pegados a casa -- el más cercano abre a %.0f studs", pegados, elMasCerca)
	)

	-- A MANO DE SU RUTA. Un refugio que existe pero cae a doscientos studs del
	-- camino es peor que ninguno: el jugador lo ve en el mapa, se desvía hacia él
	-- y pierde justo el tiempo que venía a ganar.
	local alcance = Config.REFUGIO_DESVIO + Config.REFUGIO_RADIO
	for _, ruta in Routes.todas() do
		-- Salvo las que NO PIDEN NINGUNO, que hoy es el barrio: allí no hay ladrones,
		-- así que no hay de qué refugiarse y el propio CityBuilder ni le busca sitio.
		-- Exigírselo aquí es reclamar que incumpla su diseño, y deja un rojo
		-- permanente en la sonda -- que es como se aprende a no mirarla.
		if (ruta.refugios or Config.REFUGIOS_POR_RUTA) <= 0 then
			continue
		end
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
-- 5c. Lo que plantamos encaja con el terreno de la ciudad.
--------------------------------------------------------------------------------
-- *"Cuidado con las guaridas, que las he visto no muy alineadas con el terreno"*
-- (JJ). Y no eran sólo las guaridas: todo este fichero medía el suelo con UN rayo
-- en el centro y dejaba encima una losa plana, así que en cuanto el sitio tenía
-- cuesta la pieza se hundía por un lado y volaba por el otro. Medido antes de
-- arreglarlo: la Guarida_1 volaba 20 studs y la tierra se la comía 32; el
-- Refugio_1, en la misma ladera, 37 de diferencia entre lados.
--
-- Es el defecto más barato de cometer y de los más caros que hay: no rompe nada,
-- pero un mapa donde las cosas están puestas ENCIMA en vez de EN él se lee como
-- descuidado en el primer minuto, que es justo donde se decide si alguien se queda.
local function encaje()
	local m = mundo()
	if m == nil then
		return
	end

	local ciudad = workspace:FindFirstChild("Ciudad")
	if ciudad == nil then
		comprobar("hay ciudad contra la que medir el encaje", false, "sin Ciudad no se puede comprobar el terreno")
		return
	end

	-- El terreno DE LA CIUDAD, sin contar nada nuestro: si sondeáramos el mundo
	-- entero, cada losa se mediría contra la de al lado.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ciudad }

	-- Los árboles NO son suelo: esta ciudad tiene 2.048 copas, y un rayo que se
	-- para en una hoja dice que hay terreno a cien studs de altura. La sonda mide
	-- lo mismo que mide el constructor o no sirve para comprobarlo.
	local function suelo(x: number, z: number): number?
		local desde = 500
		for _ = 1, 8 do
			local g = workspace:Raycast(Vector3.new(x, desde, z), Vector3.new(0, -(desde + 300), 0), params)
			if g == nil then
				return nil
			end
			local padre = g.Instance.Parent
			if padre == nil or padre.Name ~= "Tree" then
				return g.Position.Y
			end
			desde = g.Position.Y - 0.5
		end
		return nil
	end

	local peorEnterrada, peorHueco = "", ""
	local enterradas, huecos = 0, 0
	local maxEnterrada, maxHueco = 0, 0

	for _, pieza in m:GetChildren() do
		if not pieza:IsA("BasePart") then
			continue
		end
		-- Los zócalos NO: son precisamente lo que rellena el hueco, así que medirlos
		-- como si fueran losas cuenta dos veces el mismo desnivel y además siempre
		-- da "enterrado" -- que es su trabajo.
		local esLosa = (
			string.match(pieza.Name, "^Guarida_%d+$")
			or string.match(pieza.Name, "^Refugio_%d+$")
			or string.match(pieza.Name, "^Destino_")
			or string.match(pieza.Name, "^Taller_")
		) and not string.match(pieza.Name, "Zocalo$")
		if not esLosa then
			continue
		end
		-- Lo de dentro de casa se apoya en nuestra propia explanada, no en la
		-- ciudad: medirlo contra el terreno daría un falso positivo garantizado.
		if Perimeter.dentro(pieza.Position, 6) then
			continue
		end

		local base = pieza.Position.Y - pieza.Size.Y / 2
		local dx, dz = pieza.Size.X / 2 - 1, pieza.Size.Z / 2 - 1
		local alto, bajo = -math.huge, math.huge
		-- Rejilla de 5×5, la misma que usa el constructor: con nueve puntos, una
		-- franja de césped de 93 studs de ancho se cuela entre dos rayos.
		for i = -2, 2 do
			for k = -2, 2 do
				local y = suelo(pieza.Position.X + (i / 2) * dx, pieza.Position.Z + (k / 2) * dz)
				-- Lo que esté MUY por encima no es terreno, es un puente o un alero:
				-- estar debajo de algo no es lo mismo que estar enterrado en una loma,
				-- y meterlo en la misma cuenta daba "131 studs dentro del terreno".
				if y ~= nil and y <= base + 25 then
					alto = math.max(alto, y)
					bajo = math.min(bajo, y)
				end
			end
		end
		if alto == -math.huge then
			continue
		end

		-- ENTERRADA: el terreno sube por encima de su CARA, o sea que la losa no se ve
		-- y se pisa un hoyo al llegar.
		--
		-- Medía contra la BASE hasta el 19/08, y con razón mientras las losas se
		-- apoyaban encima del terreno: entonces base hundida = losa metida en una
		-- loma. Desde que el suelo es plano las losas van EMPOTRADAS a propósito --su
		-- cara al ras del asfalto, porque apoyadas encima hacían un muro de dos studs
		-- que cortaba el camino a pie de las cuatro rutas-- así que el criterio viejo
		-- daba ocho rojos por un mundo correcto. Lo que importa no es dónde acaba la
		-- pieza por abajo: es si su cara queda bajo el suelo que la rodea.
		local cara = pieza.Position.Y + pieza.Size.Y / 2
		local enterrada = alto - cara
		if enterrada > 1.5 then
			enterradas += 1
			if enterrada > maxEnterrada then
				maxEnterrada, peorEnterrada = enterrada, pieza.Name
			end
		end

		-- VOLANDO: el terreno cae por debajo de su base y no hay zócalo que lo tape.
		local zocalo = m:FindFirstChild(pieza.Name .. "Zocalo")
		local tapado = if zocalo and zocalo:IsA("BasePart") then zocalo.Position.Y - zocalo.Size.Y / 2 else base
		local hueco = tapado - bajo
		if hueco > 1.5 then
			huecos += 1
			if hueco > maxHueco then
				maxHueco, peorHueco = hueco, pieza.Name
			end
		end
	end

	comprobar(
		"ninguna losa enterrada en el terreno",
		enterradas == 0,
		string.format("%d enterradas, la peor %s con %.1f studs dentro", enterradas, peorEnterrada, maxEnterrada)
	)
	comprobar(
		"ninguna losa volando sobre el terreno",
		huecos == 0,
		string.format("%d con hueco debajo, la peor %s con %.1f studs al aire", huecos, peorHueco, maxHueco)
	)
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
			string.format("%s cuesta %d: %.1f viajes verdes llenos", primero.id, primero.coste, viajes)
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
-- LOS CONTACTOS. La comprobación que importa no es que estén plantados: es que
-- quien recorre la ruta LOS PISE.
--
-- Existe porque ya falló una vez y no dio la cara. Repartidos sobre la recta
-- casa-destino, medidos contra el camino real del pathfinder, caían en el camino
-- el 0 % de la ruta verde, el 8 % de la ámbar y el 5 % de la roja: treinta y ocho
-- piezas alumbradas, con sus atributos, y ninguna al alcance de nadie. Es la misma
-- firma que los quince detectores en las azoteas.
--
-- LA REGLA, que vale para cualquier sistema de este tipo: si el desvío típico
-- respecto al camino supera el radio de acción, el sistema no existe.
-- QUE LA SENAL DE LLEGADA SE VEA. Nace de una partida del 20/08: la diana estaba
-- enterrada DENTRO de la losa de su destino en las cuatro rutas, y ademas pintada
-- de su mismo color. O sea que "no se cuando he llegado al punto de delivery" no
-- era una impresion del jugador, era la descripcion exacta de lo que habia.
--
-- Es la firma de siempre en este proyecto: nada revienta, la pieza existe, se ve
-- perfectamente en el arbol de Studio, y no la ve nadie desde el juego. Por eso se
-- mide el TOPE de las dos piezas y no que la diana exista.
-- QUE DESDE CADA GUARIDA SE PUEDA LLEGAR AL JUGADOR.
--
-- Nace del fallo mas caro medido en este proyecto, el 20/08: los ladrones aparecian
-- sobre el TEJADO de la nave de su guarida --un rayo desde el cielo devuelve lo
-- primero que toca, y ahi lo primero son 18 studs de nave-- y se quedaban clavados
-- sin camino para bajar. Quieto cuarenta segundos en mitad de la ruta roja con la
-- carga encima y el calor al maximo, los tres perseguidores avanzaron DIEZ studs.
--
-- El calor, las guaridas, los refugios y la roja pagando x10 existian, se veian en el
-- mapa, costaban CPU y no hacian nada. El juego no tenia riesgo y nada lo decia.
--
-- Se mide lo unico que importa: que desde el pie de la guarida se pueda ANDAR hasta
-- el destino de la ruta. Un ladron sin camino no es un ladron.
-- QUE HAYA DONDE METERSE EN TODO EL CAMINO, no solo al principio.
--
-- El criterio no es un numero elegido a ojo: un refugio no puede estar MAS LEJOS que
-- el alcance de la guarida que te suelta al ladron (`GUARIDA_ALCANCE`). Si lo esta,
-- hay tramos donde te pueden perseguir y no tienes a donde correr, y eso no es
-- dificultad: es una ruta a la que le falta la mitad de sus reglas.
--
-- Nace de medirlo el 20/08: la ROJA tenia el 45 % de su recorrido a mas de 200 studs
-- del unico refugio del mapa, con un punto a 345 -- y es la ruta con mas ladrones,
-- mas detectores y la unica que paga x10. La causa era geometrica y callada: mide el
-- doble que la ambar y comparte con ella el primer tramo, asi que sus candidatos
-- chocaban y el que sobrevivia era siempre el del principio.
local function cobertura()
	local m = mundo()
	if m == nil then
		return
	end
	-- CON EL MAPA DESNUDO NO HAY REFUGIOS, y eso no es un fallo sino la prueba de
	-- que el interruptor funciona. Una sonda que se pone roja por algo que se
	-- apago a proposito ensena a ignorar los rojos, que es la peor averia que le
	-- puede pasar a una bateria de comprobaciones.
	if Config.MAPA_DESNUDO then
		return
	end

	local refugios: { Vector3 } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and x:GetAttribute("refugio") == true then
			table.insert(refugios, x.Position)
		end
	end
	if #refugios == 0 then
		return
	end

	local tope = Config.GUARIDA_ALCANCE
	local descubiertas = {}
	for _, ruta in Routes.todas() do
		-- Las rutas que renuncian al peligro no piden cobertura: sin ladrones no hay
		-- de que refugiarse, y exigirles un refugio seria plantar mobiliario.
		if (ruta.refugios or Config.REFUGIOS_POR_RUTA) <= 0 then
			continue
		end
		local puntos = Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino)
		local peor = 0
		for i = 2, #puntos do
			local a, b = puntos[i - 1], puntos[i]
			if (b - a).Magnitude > 1 then
				for t = 0, 1, 0.05 do
					local q = a:Lerp(b, t)
					local masCerca = math.huge
					for _, r in refugios do
						local dx, dz = r.X - q.X, r.Z - q.Z
						masCerca = math.min(masCerca, math.sqrt(dx * dx + dz * dz))
					end
					peor = math.max(peor, masCerca)
				end
			end
		end
		if peor > tope then
			table.insert(descubiertas, string.format("%s (%d studs)", ruta.id, math.floor(peor)))
		end
	end

	comprobar(
		"en todo el camino hay un refugio mas cerca que el alcance de una guarida",
		#descubiertas == 0,
		string.format("%s -- ahi te persiguen y no tienes donde meterte", table.concat(descubiertas, ", "))
	)
end

local function guaridasConSalida()
	local m = mundo()
	if m == nil then
		return
	end

	local sitios: { BasePart } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and x:GetAttribute("guarida") == true then
			table.insert(sitios, x)
		end
	end
	if #sitios == 0 then
		return
	end

	local encerradas, enElAire = 0, 0
	for _, g in sitios do
		-- El suelo pisable a su alrededor, saltandose la nave que tiene encima. Es la
		-- misma cuenta que hace PatrolService al plantar al ladron.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { workspace:FindFirstChild("Patrullas") }
		local salida: Vector3? = nil
		-- Los mismos radios que usa PatrolService, y por el mismo motivo: fuera de la
		-- losa, que esta 2,8 studs por encima del asfalto y el pathfinder sin saltos no
		-- la baja. Si esta sonda midiera desde el patio, daria rojo con el mundo bien.
		for _, radio in { 20, 24, 28 } do
			for k = 0, 7 do
				local a = (k / 8) * math.pi * 2
				local x = g.Position.X + math.cos(a) * radio
				local z = g.Position.Z + math.sin(a) * radio
				local altura = g.Position.Y + 60
				for _ = 1, 6 do
					local golpe = workspace:Raycast(Vector3.new(x, altura, z), Vector3.new(0, -500, 0), params)
					if golpe == nil then
						break
					end
					if golpe.Position.Y <= 30 then
						salida = golpe.Position
						break
					end
					altura = golpe.Position.Y - 1
				end
				if salida ~= nil then
					break
				end
			end
			if salida ~= nil then
				break
			end
		end

		if salida == nil then
			enElAire += 1
		else
			local camino = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
			local ok = pcall(function()
				camino:ComputeAsync(salida :: Vector3, Config.POLIGONO_SALIDA)
			end)
			if not ok or camino.Status ~= Enum.PathStatus.Success then
				encerradas += 1
			end
		end
	end

	comprobar(
		"todas las guaridas tienen suelo donde soltar a su ladron",
		enElAire == 0,
		string.format("%d sin sitio pisable alrededor -- el ladron nace en un tejado", enElAire)
	)
	comprobar(
		"y desde todas se puede andar hasta la ciudad",
		encerradas == 0,
		string.format("%d encerradas: sus ladrones no pueden llegar a nadie", encerradas)
	)
end

local function dianas()
	local m = mundo()
	if m == nil then
		return
	end

	-- YA NO HAY DIANAS. El disco de 58 studs del cruce se quito el 20/08 al mudarse
	-- el cobro dentro de la vivienda: senalaba un sitio donde ya no pasa nada.
	--
	-- Esta sonda no se borra, CAMBIA DE PREGUNTA. La de antes era "se ve la diana";
	-- la de ahora es la misma en el fondo -- *se sabe donde hay que entregar* -- pero
	-- contra lo que de verdad lo contesta hoy: un portal iluminado con su rotulo.
	--
	-- Borrarla habria dejado el hueco sin que nadie lo notara, que es como se pierden
	-- las comprobaciones: no se desactivan, se quedan sin objeto.
	local sinPortal, apagados = 0, 0
	for _, ruta in Routes.todas() do
		local casa = m:FindFirstChild("Vivienda_" .. ruta.id)
		local portal = casa and casa:FindFirstChild("Portal") :: BasePart?
		if portal == nil then
			sinPortal += 1
			continue
		end
		-- Y QUE SE VEA: neon y con luz. Un portal del color del ladrillo seria una
		-- puerta que hay que buscar, y buscarla no es la mecanica.
		if portal.Material ~= Enum.Material.Neon then
			apagados += 1
		end
	end
	comprobar("cada ruta tiene su portal de entrega", sinPortal == 0, string.format("%d rutas sin portal", sinPortal))
	comprobar("y el portal se ve encendido", apagados == 0, string.format("%d apagados", apagados))

	-- Y QUE NO QUEDE NINGUNA DIANA SUELTA. Si alguien vuelve a plantarlas sin quitar
	-- el portal, el cruce tendria dos senales diciendo cosas distintas sobre el mismo
	-- sitio -- y la que gana siempre es la mas grande, que es la equivocada.
	local sobran = 0
	for _, x in m:GetChildren() do
		if x.Name:match("^Diana_%a+$") then
			sobran += 1
		end
	end
	comprobar("no quedan dianas del cruce", sobran == 0, string.format("%d dianas plantadas", sobran))
end

local function contactos()
	local m = mundo()
	if m == nil then
		return
	end

	local piezas: { BasePart } = {}
	for _, x in m:GetChildren() do
		if x:IsA("BasePart") and x.Name:match("^Contacto_") then
			table.insert(piezas, x)
		end
	end

	comprobar("hay contactos plantados", #piezas >= 1, "ninguno -- el viaje vuelve a no dar nada")
	if #piezas == 0 then
		return
	end

	-- NINGUNO EN UN TEJADO. Se mide contra el suelo que tiene DEBAJO, no contra una
	-- cota fija: la ciudad tiene laderas y un contacto a 42 studs puede estar
	-- perfectamente apoyado.
	local flotando = 0
	for _, p in piezas do
		local golpe = bajoLosPies(p.Position.X, p.Position.Y, p.Position.Z, 300)
		if golpe == nil or (p.Position.Y - golpe.Position.Y) > 8 then
			flotando += 1
		end
	end
	comprobar(
		"ningún contacto flota",
		flotando == 0,
		string.format("%d en el aire o sobre un tejado -- ahí no los pisa nadie", flotando)
	)

	-- Y QUE SE PUEDA IR DE UNA A OTRA SIN CAERSE. Que cada miga esté apoyada no
	-- dice nada del TRAMO entre dos: la sonda de arriba las mira de una en una y da
	-- verde con un abismo de veinte studs en medio.
	--
	-- Esto es literalmente lo que hace el jugador -- *"sólo yendo recto a recoger el
	-- paquete me caigo y muero"* (JJ) -- así que se mide igual: se va de miga a miga
	-- en línea recta, sondeando el suelo cada 4 studs. Cuatro y no doce porque un
	-- personaje mide 2 de ancho y por una rendija de 12 se cuela; ya se pagó una vez.
	local rayos = RaycastParams.new()
	rayos.FilterType = Enum.RaycastFilterType.Exclude
	rayos.FilterDescendantsInstances = { m:FindFirstChild("Red") :: any }
	local vanos, tramos, primerVano = 0, 0, ""
	for _, ruta in Routes.todas() do
		local suyas: { BasePart } = {}
		for _, p in piezas do
			if p:GetAttribute("ruta") == ruta.id then
				table.insert(suyas, p)
			end
		end
		-- Por cercanía al origen, que es el orden en que se recogen.
		table.sort(suyas, function(a, b)
			return (a.Position - Config.POLIGONO_SALIDA).Magnitude < (b.Position - Config.POLIGONO_SALIDA).Magnitude
		end)
		for i = 2, #suyas do
			tramos += 1
			local desde, hasta = suyas[i - 1].Position, suyas[i].Position
			local largo = (hasta - desde).Magnitude
			local pasos = math.max(1, math.floor(largo / 4))
			for k = 0, pasos do
				local punto = desde:Lerp(hasta, k / pasos)
				local golpe = workspace:Raycast(punto + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), rayos)
				if golpe == nil or golpe.Position.Y < Bounds.fondo() then
					vanos += 1
					if primerVano == "" then
						primerVano = string.format(
							"%s entre sus migas %d y %d, en (%.0f, %.0f)",
							ruta.id,
							i - 1,
							i,
							punto.X,
							punto.Z
						)
					end
					break
				end
			end
		end
	end
	comprobar(
		"se va de miga a miga sin caerse",
		vanos == 0,
		string.format("%d tramos de %d con vacio, el primero: %s", vanos, tramos, primerVano)
	)

	-- Y EL CAMINO, ruta por ruta. Dos caminos distintos y los dos importan:
	--
	--   · el del PATHFINDER, para comprobar que al destino se llega andando y sin
	--     saltar -- si eso falla, las patrullas y los ladrones no pueden seguirte y el
	--     juego se rompe por dentro sin dar un error;
	--   · el de las CALLES, para medir si las migas de pan caen donde va el jugador.
	--
	-- Medirlas contra el del pathfinder daba siete rojos por un mundo correcto: el
	-- pathfinder es un bot omnisciente que corta en diagonal por dentro de las
	-- manzanas, y las migas se plantan por la calle a propósito, que es por donde
	-- puede seguirlas alguien que sólo mira. La sonda tiene que medir contra lo que ve
	-- el jugador, no contra lo que sabe el motor.
	-- NADA SE LEVANTA SOBRE EL CARRIL.
	--
	-- POR QUE HACE FALTA. El borde norte del recinto estuvo clavado en el EJE de la
	-- calle que pasa por delante en vez de en el borde del asfalto: trece studs de
	-- calzada tapados por su suelo gris, y los dos pilares del arco de entrada
	-- --cinco por cinco, veinte de alto-- plantados en mitad del carril. Y las tres
	-- casas de entrega tenian los pies en la carretera, mostrador incluido. Se veia
	-- desde dentro y no lo medía nadie: JJ mando dos capturas antes de que se cazara.
	--
	-- SE MIDE CONTRA LA BANDA DE LA RETICULA, no contra las piezas de calzada. Se
	-- probo lo segundo --parecia mas fiel a "lo que se construyo"-- y es peor: el
	-- asfalto se planta en parches de 160x160 que cubren el cruce ENTERO, aceras y
	-- esquinas de manzana incluidas, asi que media ciudad salia "sobre la calzada".
	-- La banda (`ANCHO_CALLE`) es el carril de verdad.
	--
	-- Y SE SALTA EL RECINTO: alli la reticula dice que hay calle, pero no se planta
	-- asfalto -- es nuestra parcela. Medir alli marcaba medio taller como intruso.
	do
		local medio = Grid.ANCHO_CALLE / 2
		local px0 = Config.POLIGONO_CENTRO.X - Config.POLIGONO_TAMANO.X / 2
		local px1 = Config.POLIGONO_CENTRO.X + Config.POLIGONO_TAMANO.X / 2
		local pz0 = Config.POLIGONO_CENTRO.Z - Config.POLIGONO_TAMANO.Y / 2
		local pz1 = Config.POLIGONO_CENTRO.Z + Config.POLIGONO_TAMANO.Y / 2

		-- Cuanto de un rectangulo cae dentro del carril mas cercano.
		local function sobreElCarril(d: BasePart): number
			local ax0, ax1 = d.Position.X - d.Size.X / 2, d.Position.X + d.Size.X / 2
			local az0, az1 = d.Position.Z - d.Size.Z / 2, d.Position.Z + d.Size.Z / 2
			local peor = 0
			for i = Grid.COL_MIN, Grid.COL_MAX do
				local eje = Grid.xDeCalle(i)
				local sx = math.min(ax1, eje + medio) - math.max(ax0, eje - medio)
				if sx > 0 then
					peor = math.max(peor, sx * (az1 - az0))
				end
			end
			for j = Grid.FILA_MIN, Grid.FILA_MAX do
				local eje = Grid.zDeCalle(j)
				local sz = math.min(az1, eje + medio) - math.max(az0, eje - medio)
				if sz > 0 then
					peor = math.max(peor, sz * (ax1 - ax0))
				end
			end
			return peor
		end

		local intrusos: { string } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Size.Y > 4 and d.Size.X < 60 and d.Size.Z < 60 then
				local x, z = d.Position.X, d.Position.Z
				local enRecinto = x > px0 and x < px1 and z > pz0 and z < pz1
				-- Ocho studs cuadrados de margen: una farola que roza el bordillo no
				-- molesta a nadie; un pilar de cinco por cinco son veinticinco, y ese si.
				if not enRecinto and sobreElCarril(d) > 8 then
					table.insert(intrusos, string.format("%s (%.0f studs2)", d.Name, sobreElCarril(d)))
				end
			end
		end
		comprobar(
			"no hay nada del juego plantado en el carril",
			#intrusos == 0,
			string.format("%d: %s", #intrusos, table.concat(intrusos, ", ", 1, math.min(#intrusos, 5)))
		)

		-- Y el suelo del recinto tampoco: es lo mas gordo que puede tapar una calle.
		local poli = m:FindFirstChild("Poligono")
		if poli and poli:IsA("BasePart") then
			comprobar(
				"el recinto no invade la calle que pasa por delante",
				poli.Position.Z - poli.Size.Z / 2 >= Grid.zDeCalle(Grid.FILA_MAX) + medio - 0.5,
				string.format(
					"su borde esta en z=%.0f y el carril acaba en z=%.0f",
					poli.Position.Z - poli.Size.Z / 2,
					Grid.zDeCalle(Grid.FILA_MAX) + medio
				)
			)
		end
	end

	-- LOS ALIJOS EXISTEN Y ESTAN DONDE TIENEN QUE ESTAR.
	--
	-- Lo que se comprueba no es que haya doce cajas: es que ninguna haya acabado
	-- pegada a un camino ni dentro de casa. Un alijo sobre la ruta no da error --
	-- se recoge igual-- y convierte en una miga mas lo unico del mapa que premia
	-- salirse, que es el sistema entero.
	do
		local cajas: { BasePart } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("alijo") == true then
				table.insert(cajas, d)
			end
		end
		comprobar(
			"hay alijos plantados por la ciudad",
			#cajas >= math.floor(Config.ALIJOS * 0.6),
			string.format("solo %d de %d", #cajas, Config.ALIJOS)
		)

		local caminos: { { Vector3 } } = {}
		for _, ruta in Routes.todas() do
			local puntos: { Vector3 } = { Config.ALMACEN_POS }
			for _, punto in Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino) do
				table.insert(puntos, punto)
			end
			table.insert(caminos, puntos)
		end

		local pegados, dentro, sinSuelo = 0, 0, 0
		for _, caja in cajas do
			-- LOS DE TEJADO NO ENTRAN EN ESTA CUENTA, y no es relajar la sonda: es que
			-- mide otra cosa de la que cree.
			--
			-- La regla dice "lejos del camino", pero lo que de verdad protege es que un
			-- alijo no se recoja SIN DESVIARSE -- si se cogiera al pasar no premiaria
			-- explorar, premiaria caminar, que es la frase con la que se escribio
			-- `Caches.LEJOS`. Para uno de suelo, desviarse es andar; para uno que esta a
			-- quince studs de altura, desviarse es tener con que subir, y eso no lo hace
			-- nadie de paso por muy encima de la ruta que este.
			--
			-- Y ESTAR SOBRE LA RUTA ES LO QUE SE QUIERE en ese caso: es donde se VE, y
			-- verlo desde la calle es lo unico que le ensena al jugador que el impulsor
			-- existe. Un premio inalcanzable que ademas no se ve no vende nada.
			if caja:GetAttribute("enTejado") then
				continue
			end
			for _, camino in caminos do
				-- Con el margen del sembrado: la caja se corre hasta 14 studs buscando
				-- calle, asi que exigir los 60 clavados seria pedirle a la sonda una
				-- precision que el mundo no puede dar.
				if Contacts.distanciaAlCamino(caja.Position, camino) < Caches.LEJOS - 15 then
					pegados += 1
					break
				end
			end
			if Perimeter.dentro(caja.Position, Config.ZONA_SEGURA_RADIO) then
				dentro += 1
			end
			-- Y CON SUELO DEBAJO. Un alijo flotando o enterrado se ve y no se coge, que
			-- es peor que no ponerlo.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { caja }
			local golpe = workspace:Raycast(caja.Position + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
			if golpe == nil then
				sinSuelo += 1
			end
		end
		comprobar("ningun alijo cae sobre una ruta", pegados == 0, string.format("%d pegados a un camino", pegados))
		comprobar("ningun alijo cae dentro de casa", dentro == 0, string.format("%d en la zona segura", dentro))
		comprobar("todos los alijos tienen suelo debajo", sinSuelo == 0, string.format("%d en el aire", sinSuelo))
	end

	for _, ruta in Routes.todas() do
		local camino = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function()
			camino:ComputeAsync(Config.POLIGONO_SALIDA, ruta.destino)
		end)
		if not ok or camino.Status ~= Enum.PathStatus.Success then
			comprobar("hay camino a pie hasta " .. ruta.id, false, tostring(camino.Status))
			continue
		end

		-- EL MISMO CAMINO QUE SE SEMBRO, con el almacen delante.
		--
		-- Esto medía contra `porCalles(salida, destino)` a secas mientras `CityBuilder`
		-- siembra sobre `{ALMACEN} ++ porCalles(...)`. Dos caminos parecidos y no
		-- iguales, que es la peor clase de sonda: mientras la verde fue una recta corta
		-- daba verde, y en cuanto un destino sorteado la alargo empezo a cantar migas
		-- "fuera del camino" que estaban exactamente donde tenian que estar.
		--
		-- Una sonda mide lo que se construyo. Si el camino sembrado cambia, este
		-- tiene que cambiar con el -- por eso comparte la misma forma linea a linea.
		local puntos: { Vector3 } = { Config.ALMACEN_POS }
		for _, punto in Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino) do
			table.insert(puntos, punto)
		end

		-- Tipo propio y no `Contacts.Contacto`: aquí hace falta además el ORDEN en que
		-- se plantaron, que el módulo puro no tiene por qué conocer.
		type Sembrado = { pos: Vector3, valor: number, tipo: string, orden: number }
		local sueltos: { Sembrado } = {}
		local racimos: { Sembrado } = {}
		for _, p in piezas do
			if p:GetAttribute("ruta") ~= ruta.id then
				continue
			end
			-- El ORDEN sale del nombre (`Contacto_verde_12`), que es donde CityBuilder
			-- lo dejó al sembrar. Hace falta para la comprobación de la fila: sin él,
			-- "la luz siguiente" sería la siguiente que devuelva GetDescendants, que
			-- no tiene nada que ver con el camino.
			local c = {
				pos = p.Position,
				valor = 1,
				tipo = tostring(p:GetAttribute("tipo")),
				orden = tonumber(string.match(p.Name, "(%d+)$")) or 0,
			}
			if c.tipo == "racimo" then
				table.insert(racimos, c)
			else
				table.insert(sueltos, c)
			end
		end

		if #sueltos > 0 then
			local pisados = Contacts.cercaDelCamino(sueltos, puntos, Config.CONTACTO_RADIO)
			-- El listón es el 70 %: por debajo, media ruta va sin nada que recoger y
			-- el ritmo que esto venía a dar no existe.
			comprobar(
				string.format("los contactos de la %s están en el camino", ruta.id),
				pisados >= math.ceil(#sueltos * 0.7),
				string.format("sólo %d de %d al alcance de quien va por el camino", pisados, #sueltos)
			)
		end

		-- Los racimos, al revés: tienen que estar FUERA del camino, o dejan de ser
		-- un rodeo y se convierten en un regalo.
		if #racimos > 0 then
			local enElCamino = Contacts.cercaDelCamino(racimos, puntos, Config.CONTACTO_RADIO)
			comprobar(
				string.format("los racimos de la %s piden desviarse", ruta.id),
				enElCamino == 0,
				string.format("%d de %d caen sobre el camino: se cogen sin decidir nada", enElCamino, #racimos)
			)
		end

		-- ¿Y SE PUEDE SEGUIR LA FILA? Que las píldoras estén cerca del camino no
		-- basta: lo que el rastro promete es "ve de una luz a la siguiente", y si
		-- entre dos hay una pared, el jugador que se fía se estampa.
		--
		-- Existe porque el rastro es la única guía que se le da a alguien que no
		-- conoce la ciudad, y una guía que miente es peor que ninguna -- con el mapa
		-- a oscuras al menos vas con cuidado. Se mide con un rayo de luz a luz
		-- contra la ciudad, saltándose lo nuestro (las propias píldoras, las losas,
		-- los postes) porque nada de eso frena a nadie.
		if #sueltos > 1 then
			-- En el orden en que se plantaron, que es el orden del camino: sus
			-- nombres llevan el índice.
			table.sort(sueltos, function(a, b)
				return a.orden < b.orden
			end)
			local ciudad = workspace:FindFirstChild("Ciudad")
			local cortes = 0
			local donde = ""
			if ciudad ~= nil then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { ciudad }
				for i = 2, #sueltos do
					local a, b = sueltos[i - 1].pos, sueltos[i].pos
					local golpe = workspace:Raycast(a, b - a, params)
					if golpe ~= nil then
						cortes += 1
						if donde == "" then
							donde = string.format("%s cerca de (%.0f, %.0f)", golpe.Instance.Name, a.X, a.Z)
						end
					end
				end
			end
			-- EL LISTÓN ES EL 90 % DE LOS TRAMOS, no todos, y la primera versión
			-- --exigiendo cero cortes-- falló en las cuatro rutas por el mismo sitio:
			-- `Dirt` en el borde del polígono. Es el desnivel del terreno donde acaba
			-- nuestra explanada y empieza la ciudad, y **un montículo no rompe un
			-- rastro**: subes la cuesta y la siguiente luz aparece.
			--
			-- Lo que esta comprobación tiene que cazar es una fila partida por un
			-- EDIFICIO -- un rastro que promete un camino que no existe. Eso no da uno
			-- ni dos cortes sueltos: parte la ruta y se lleva por delante un tramo
			-- entero. Con el 90 %, un relieve pasa y una pared no.
			local tramos = #sueltos - 1
			local limpios = tramos - cortes
			comprobar(
				string.format("la fila de la %s se puede seguir de luz en luz", ruta.id),
				limpios >= math.ceil(tramos * 0.9),
				string.format("%d de %d tramos con algo por medio -- el primero, %s", cortes, tramos, donde)
			)
		end
	end
end

-- LA RAMPA DE ENTRADA: el primer viaje que juega alguien que acaba de llegar.
--
-- No mira una ruta con nombre propio sino `Config.RUTA_PRIMERA`, y eso importa: el
-- 20/08 la rampa dejo de ser una ruta aparte --la que el selector llamaba LOCAL-- y
-- paso a ser la verde, mudada a ese mismo cruce. Con el id escrito a mano, esta
-- sonda habria muerto en silencio justo cuando mas falta hacia.
--
-- Y mide lo que de verdad importa, que no es que exista sino que se pueda ir
-- ANDANDO y que sea corto: la razon de ser de la rampa es que la primera recompensa
-- llegue en veinte segundos y no en cien.
local function rampaDeEntrada()
	local m = mundo()
	if m == nil then
		return
	end

	local ruta = Routes.get(Config.RUTA_PRIMERA)
	if ruta == nil then
		comprobar("existe la ruta con la que se empieza", false, Config.RUTA_PRIMERA .. " no está en Config.RUTAS")
		return
	end

	-- Apoyado en el suelo, medido contra lo que tiene DEBAJO y no contra una cota
	-- fija: la ciudad tiene laderas.
	local golpe = bajoLosPies(ruta.destino.X, ruta.destino.Y + 6, ruta.destino.Z, 300)
	comprobar(
		"el destino del primer viaje se apoya en el suelo",
		golpe ~= nil and math.abs(ruta.destino.Y - golpe.Position.Y) <= 10,
		if golpe == nil
			then "no hay suelo debajo"
			else string.format("%.0f studs de desnivel", math.abs(ruta.destino.Y - golpe.Position.Y))
	)
	comprobar(
		"y es pisable",
		esPisable(golpe),
		"el destino cae sobre algo que no es suelo: un tejado, una copa o el vacío"
	)

	-- Y SOBRE TODO: que se pueda ir andando, y que sea corto.
	local camino = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		camino:ComputeAsync(Config.POLIGONO_SALIDA, ruta.destino)
	end)
	if not ok or camino.Status ~= Enum.PathStatus.Success then
		comprobar("hay camino a pie hasta el primer destino", false, tostring(camino.Status))
		return
	end

	local largo = 0
	local puntos = camino:GetWaypoints()
	for i = 1, #puntos - 1 do
		local a, b = puntos[i].Position, puntos[i + 1].Position
		largo += math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
	end

	-- Por debajo de la zona segura la entrega cae dentro de casa y no enseña nada;
	-- por encima del tope deja de ser un bucle corto y no arregla lo que vino a
	-- arreglar.
	--
	-- La horquilla bajó de 200-350 a 90-220 el 19/08, con el resto de la escala: el
	-- mundo se encogió a la mitad y un umbral que no se reescala con él deja de
	-- decir lo que decía. 90 es la zona segura de hoy; 220 es lo que se anda en unos
	-- veinte segundos, que es lo que tiene que durar la rampa de entrada.
	comprobar(
		"el primer viaje está a la distancia de una rampa",
		largo >= 90 and largo <= 220,
		string.format("%d studs andando: fuera de la horquilla 90-220", math.floor(largo))
	)
end

-- 9. INFORME. Números medidos, sin aprobado ni suspenso.
--
-- No son comprobaciones porque no hay un valor "correcto": son las cifras con las
-- que se decide de diseño. La última --cuántos viajes cuesta comprarlo TODO-- es
-- la que dice cuánto dura el juego antes de quedarse sin objetivos, y ésa no se
-- puede estimar a ojo porque depende de tres cosas a la vez: qué sale del almacén,
-- cuánto cabe en cada vehículo y qué paga cada ruta.
--------------------------------------------------------------------------------
-- LOS LIMITES DEL MUNDO. Compañera del guardián de `Avatar.luau`: él caza al
-- jugador que se sale, y esto caza lo que PLANTAMOS nosotros fuera.
--
-- Mide el mundo, que es la regla de esta batería: no comprueba que la caja esté
-- bien calculada --de eso se encargan las pruebas puras de Bounds-- sino que cada
-- pieza que el juego construye cae dentro de ella. Si un día un destino, un
-- recogible o un refugio acaba en el vacío, esto lo dice; y si lo que acaba fuera
-- es el punto de aparición, entonces el guardián devolvería al jugador a un sitio
-- del que le volvería a sacar, que es la única forma que tiene una red de
-- seguridad de empeorar las cosas.
local function limites()
	local m = mundo()
	if m == nil then
		comprobar("los limites del mundo", false, "no hay workspace.Mundo")
		return
	end

	local fuera = 0
	local primero = ""
	for _, pieza in m:GetDescendants() do
		-- La red de seguridad NO cuenta: vive por debajo del fondo a propósito, que
		-- es justo lo que la hace útil. Se comprueba aparte, y comprobando lo que de
		-- verdad importa de ella, que es si CUBRE la caja.
		if pieza:IsA("BasePart") and pieza.Name ~= "Red" then
			local motivo = Bounds.fuera(pieza.Position)
			if motivo then
				fuera += 1
				if primero == "" then
					primero = string.format("%s (%s) en %s", pieza.Name, motivo, tostring(pieza.Position))
				end
			end
		end
	end
	comprobar(
		"nada del mundo cae fuera de los limites",
		fuera == 0,
		string.format("%d piezas fuera, p.ej. %s", fuera, primero)
	)

	-- LA RED TIENE QUE TAPAR LA CAJA ENTERA. Es la comprobación que faltaba cuando
	-- la red estaba centrada en el origen del mundo y el mapa no: medido entonces,
	-- 31 de 961 puntos del mapa no tenían red debajo -- el borde sur del recinto,
	-- que es donde empieza cada partida. Caerse ahí sí mataba.
	--
	-- SE MIDE LA UNION DE TODAS LAS BALDOSAS, no la primera que aparezca. La red se
	-- planto en una sola pieza durante meses y esta sonda cogia esa; desde que la caja
	-- paso de los 2.048 studs que Roblox admite por eje, son varias -- y con
	-- `FindFirstChild` la sonda medía media red y daba rojo teniendo el mundo tapado.
	-- Una sonda que mide algo PARECIDO a lo que se construyo es peor que no tener
	-- sonda, y esta ya lo fue durante una tarde.
	local red = nil
	local rx0, rx1, rz0, rz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, pieza in m:GetChildren() do
		if pieza:IsA("BasePart") and pieza.Name == "Red" then
			red = pieza
			rx0 = math.min(rx0, pieza.Position.X - pieza.Size.X / 2)
			rx1 = math.max(rx1, pieza.Position.X + pieza.Size.X / 2)
			rz0 = math.min(rz0, pieza.Position.Z - pieza.Size.Z / 2)
			rz1 = math.max(rz1, pieza.Position.Z + pieza.Size.Z / 2)
		end
	end
	if red then
		local x0, x1, z0, z1 = Bounds.caja()
		comprobar(
			"la red de seguridad tapa la caja entera",
			rx0 <= x0 and rx1 >= x1 and rz0 <= z0 and rz1 >= z1,
			string.format(
				"red X[%.0f..%.0f] Z[%.0f..%.0f] contra caja X[%.0f..%.0f] Z[%.0f..%.0f]",
				rx0,
				rx1,
				rz0,
				rz1,
				x0,
				x1,
				z0,
				z1
			)
		)
		comprobar(
			"y esta por debajo del fondo del guardian",
			red.Position.Y < Bounds.fondo(),
			string.format("red en %.0f, fondo en %.0f", red.Position.Y, Bounds.fondo())
		)
	else
		comprobar("hay red de seguridad bajo el mapa", false, "sin ella, caerse mata a -500")
	end

	-- Y QUE NO HAYA AGUJEROS EN EL SUELO. La sonda que faltaba, y que costó el fallo
	-- más caro de este mapa: el suelo base se paraba 78 studs antes que el recinto y
	-- alrededor del sitio donde empieza cada partida no había NADA. Caerse por ahí
	-- no mata --hay red-- y no da ningún error: te deja tumbado a -90, andando por
	-- debajo del mapa, y desde arriba parece que has desaparecido.
	--
	-- PASO DE 12 Y NO DE 20: un personaje mide 2 studs de ancho, así que las
	-- rejillas gruesas se saltan justo lo que hay que encontrar. La primera pasada
	-- de este fallo se hizo a 20 y dio verde. A 12 son ~2.600 rayos, que en una
	-- sonda que se lanza a mano sale barato.
	local rayos = RaycastParams.new()
	rayos.FilterType = Enum.RaycastFilterType.Exclude
	rayos.FilterDescendantsInstances = { m:FindFirstChild("Red") :: any }
	local mx0, mx1, mz0, mz1 = Bounds.mundo()
	local sinSuelo, puntos, dondeFalta = 0, 0, ""
	for x = mx0, mx1, 12 do
		for z = mz0, mz1, 12 do
			puntos += 1
			if workspace:Raycast(Vector3.new(x, Grid.Y + 60, z), Vector3.new(0, -200, 0), rayos) == nil then
				sinSuelo += 1
				if dondeFalta == "" then
					dondeFalta = string.format("(%.0f, %.0f)", x, z)
				end
			end
		end
	end
	comprobar(
		"no hay agujeros en el suelo del mundo",
		sinSuelo == 0,
		string.format("%d de %d puntos sin suelo, el primero en %s", sinSuelo, puntos, dondeFalta)
	)

	local aparicion = m:FindFirstChild("AparicionAlmacen")
	if aparicion and aparicion:IsA("BasePart") then
		comprobar(
			"el punto de aparicion esta dentro de los limites",
			Bounds.fuera(aparicion.Position) == nil,
			"aparecer fuera del mundo dejaria al guardian rescatando en bucle"
		)
	end

	-- Y que el fondo esté MUY por encima de donde Roblox destruye. Si alguien sube
	-- Bounds.CAIDA sin mirar, el guardián dejaría de llegar a tiempo: el personaje
	-- se destruiría antes de que el bucle de un segundo lo viera caer.
	comprobar(
		"el guardian salta antes de que Roblox destruya",
		Bounds.fondo() > workspace.FallenPartsDestroyHeight + 200,
		string.format("fondo %.0f contra destruccion en %.0f", Bounds.fondo(), workspace.FallenPartsDestroyHeight)
	)
end

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
		local nombre = vehiculoId
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
				string.format("  · %-8s %.2f monedas por hueco", Config.TAMANOS[nivel].id, suma / huecos)
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

-- LA RETÍCULA, medida sobre el mundo construido y no sobre Grid. Grid dice dónde
-- DEBERÍAN estar las calles; esto comprueba dónde están, que es lo único que pisa
-- el jugador. Las tres cosas que mira son las tres quejas que trajeron el mapa
-- nuevo: no sé a dónde ir, el sitio es confuso, y --la que nadie dice pero se
-- nota-- el suelo tiene cantos donde el plano promete llano.
local function reticula()
	local ciudad = workspace:FindFirstChild("Ciudad")
	if not ciudad then
		comprobar("hay ciudad", false, "no existe workspace.Ciudad")
		return
	end

	local calles = ciudad:FindFirstChild("Calles")

	-- HAY ASFALTO BAJO CADA CRUCE. Sustituye a un recuento de piezas ("¿hay nueve
	-- calles?"), que dejó de significar nada en cuanto la calzada pasó de ser nueve
	-- tiras a una alfombra segmentada. Contar piezas mide la implementación; esto mide
	-- lo que pisa el jugador, que es lo que la sonda tiene que mirar.
	local sinAsfalto = {}
	for i = Grid.COL_MIN, Grid.COL_MAX do
		for j = Grid.FILA_MIN, Grid.FILA_MAX do
			local cruce = Grid.cruce(i, j)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { ciudad }
			local r = workspace:Raycast(cruce + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
			if r == nil or math.abs(r.Position.Y - Grid.Y) > 0.2 then
				table.insert(sinAsfalto, string.format("(%d,%d)", i, j))
			end
		end
	end
	-- NINGUNA ESQUINA FICHADA FUERA DE LA CIUDAD. El reparto las aparta
	-- perpendicularmente al camino, y las de los tramos pegados al borde se salían al
	-- margen de césped -- donde no pasa nadie, así que no fichan a nadie. No rompía
	-- nada: la ruta tenía menos vigilancia de la que su selector promete.
	local fueraDelMapa = 0
	do
		local bx0, bx1, bz0, bz1 = Grid.limites()
		for _, d in mundo():GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("detectorId") ~= nil then
				if d.Position.X < bx0 or d.Position.X > bx1 or d.Position.Z < bz0 or d.Position.Z > bz1 then
					fueraDelMapa += 1
				end
			end
		end
	end
	comprobar(
		"todas las esquinas fichadas caen dentro de la ciudad",
		fueraDelMapa == 0,
		string.format("%d fuera del mapa, donde no pasa nadie", fueraDelMapa)
	)

	comprobar(
		"hay calzada bajo cada cruce de la reticula",
		#sinAsfalto == 0,
		"cruces sin asfalto a su cota: " .. table.concat(sinAsfalto, " ")
	)

	-- NADA PARPADEA. Dos superficies planas a la misma altura y con la misma huella
	-- hacen que la tarjeta gráfica no pueda decidir cuál está delante, y alterna
	-- fotograma a fotograma. Es un defecto que se VE al instante y que ninguna prueba
	-- podía cazar: el mundo se construye igual, la sonda daba verde, y JJ lo describió
	-- a los diez segundos de entrar como "parpadea el suelo".
	--
	-- Lo tenía la primera retícula: una tira por calle, cruzándose, y en cada uno de
	-- los veinte cruces dos piezas ocupando el mismo volumen con la cara superior a la
	-- misma cota.
	--
	-- ESTA SONDA DABA VERDE CON EL DEFECTO DELANTE, y por dos motivos a la vez. El
	-- 21/08 JJ vio *"parpadeos en el suelo del garaje donde estan los coches"*:
	--
	--   · MIRABA SOLO `Ciudad`. Las losas del juego --almacen, taller, salida,
	--     destinos-- viven en `Mundo`, que es otra carpeta. O sea que las piezas que
	--     mas parpadeaban eran justo las que no se miraban.
	--   · Y EL UMBRAL ERA 0,02. Las losas se apoyaban a 0,05 del suelo, asi que
	--     pasaban el filtro por tres centesimas -- y a la distancia a la que se juega
	--     0,05 studs pelean por el z-buffer igual que cero. El umbral tiene que medir
	--     lo que la TARJETA no distingue, no lo que es matematicamente distinto.
	--
	-- Se mira lo GRANDE de las dos carpetas: dos chinas de dos studs solapadas no las
	-- nota nadie, y el bucle es cuadratico.
	local piezas: { BasePart } = {}
	local function recoger(raiz: Instance?)
		if raiz == nil then
			return
		end
		for _, d in raiz:GetDescendants() do
			if d:IsA("BasePart") and d.Size.X >= 8 and d.Size.Z >= 8 and d.Transparency < 0.9 then
				table.insert(piezas, d)
			end
		end
	end
	recoger(ciudad)
	recoger(mundo())
	local parpadeos = 0
	local ejemplo = ""
	for i = 1, #piezas do
		for j = i + 1, #piezas do
			local a, b = piezas[i], piezas[j]
			local caraA = a.Position.Y + a.Size.Y / 2
			local caraB = b.Position.Y + b.Size.Y / 2
			-- QUINCE CENTESIMAS, no dos: es la separacion por debajo de la cual la
			-- tarjeta grafica no puede decidir cual esta delante. Ver arriba.
			if math.abs(caraA - caraB) < 0.15 then
				-- SOLAPE MINIMO DE UN STUD, no de medio. Con medio saltaban las molduras de
				-- ventanas de dos alas contiguas: sobresalen 0,3 de la fachada por cada lado,
				-- asi que dos alas que se tocan en la esquina se rozan 0,6 studs. Un roce de
				-- una decima no parpadea a la vista de nadie; lo que hay que cazar son dos
				-- superficies montadas una sobre otra.
				local solapaX = math.abs(a.Position.X - b.Position.X) < (a.Size.X + b.Size.X) / 2 - 1
				local solapaZ = math.abs(a.Position.Z - b.Position.Z) < (a.Size.Z + b.Size.Z) / 2 - 1
				if solapaX and solapaZ then
					parpadeos += 1
					if ejemplo == "" then
						ejemplo = string.format("%s y %s a cota %.2f", a.Name, b.Name, caraA)
					end
				end
			end
		end
	end
	comprobar(
		"ninguna superficie del mapa parpadea contra otra",
		parpadeos == 0,
		string.format("%d pares coplanares, p.ej. %s", parpadeos, ejemplo)
	)

	-- SE PUEDE LLEGAR A CASA DESDE CUALQUIER MANZANA POR LA QUE SE CORTA.
	--
	-- Vivia en `MapBuilder`, al final de `buildCiudad`, y desde ahi no podia funcionar:
	-- en ese momento el recinto y el almacen todavia no existen --los planta
	-- `CityBuilder` despues-- asi que el destino del camino era un punto en el aire y
	-- el pathfinder contestaba `NoPath` a todo. Nueve avisos rojos en cada arranque, y
	-- los nueve mentira. Aqui el mundo esta terminado, que es la unica forma de medir
	-- un camino.
	--
	-- QUE COMPRUEBA DE VERDAD: que una manzana atravesable no se haya quedado
	-- encerrada. Son las vias de escape del juego --se cortan por dentro mientras la
	-- patrulla, atada a las calles, tiene que rodear-- y una que no conecte no da
	-- ningun error: simplemente deja de ser una salida el dia que la necesitas.
	--
	-- SE MIRAN DOS, NO LAS NUEVE. Cada `ComputeAsync` cuesta cerca de un segundo y
	-- esto corre al arrancar cada partida; con la mas lejana y la mas cercana se caza
	-- un mapa partido en dos, que es el fallo que importa. Y se dice cuales, porque
	-- una sonda que recorta en silencio se lee como si lo hubiera mirado todo.
	do
		local Districts = require(game.ReplicatedStorage.Shared.Districts)
		local abiertas = {}
		for _, mz in Districts.manzanas() do
			if Districts.atravesable(mz.uso) then
				table.insert(abiertas, mz)
			end
		end
		local aProbar = {}
		if #abiertas > 0 then
			table.insert(aProbar, abiertas[1])
			if #abiertas > 1 then
				table.insert(aProbar, abiertas[#abiertas])
			end
		end

		local ok, pathfinding = pcall(function()
			return game:GetService("PathfindingService")
		end)
		for _, mz in aProbar do
			if not ok then
				break
			end
			local centro = Grid.centroManzana(mz.col, mz.fila)
			local origen = Vector3.new(centro.X, Grid.Y + 2, centro.Z)
			local bien, path = pcall(function()
				local ruta = pathfinding:CreatePath({
					AgentRadius = 2,
					AgentHeight = 5,
					AgentCanJump = true,
					WaypointSpacing = 4,
				})
				ruta:ComputeAsync(origen, Config.ALMACEN_POS)
				return ruta
			end)
			local estado = if bien then tostring((path :: any).Status) else "error: " .. tostring(path)
			comprobar(
				string.format("hay camino a casa desde la manzana %d,%d (%s)", mz.col, mz.fila, mz.uso),
				bien and (path :: any).Status == Enum.PathStatus.Success,
				estado
			)
		end
	end

	-- NINGUNA MOLDURA SIN EDIFICIO DEBAJO.
	--
	-- Un edificio se DERRIBA en dos sitios --`validarPuntosFijos` retira el que pisa un
	-- destino y `CityBuilder` el que estorba a una guarida o a un refugio-- y las dos
	-- veces con un `Destroy()` sobre la pieza del bloque. El dia que los adornos del
	-- edificio (zocalo, portal, marquesina, cornisa, azotea, bandas) se plantaron como
	-- HERMANOS suyos, derribar dejo 79 piezas colgadas del aire en una partida normal:
	-- puertas a metro y medio del suelo con su tejadillo, y laminas de cristal apiladas
	-- donde no habia edificio. Nada dio error; simplemente se veia mal.
	--
	-- La cura fue colgarlos DEL edificio, y esto es lo que comprueba que sigue siendo
	-- asi: una moldura cuyo padre no es una pieza es una moldura que sobrevivira al
	-- derribo de su bloque. Se mide aqui y no en la bateria del mundo porque el derribo
	-- solo ocurre con el juego montado -- `MapBuilder` a solas nunca retira nada.
	do
		local sueltas = 0
		local primera = ""
		for _, d in ciudad:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			local raiz = string.match(d.Name, "^.-_([ZPCMAV]%d*)$")
			if raiz ~= nil and not d.Parent:IsA("BasePart") then
				sueltas += 1
				if primera == "" then
					primera = d.Name
				end
			end
		end
		comprobar(
			"ninguna moldura de edificio se queda flotando",
			sueltas == 0,
			string.format("%d sueltas, la primera %s", sueltas, primera)
		)
	end

	-- LOS ALIJOS DE TEJADO, DONDE SE LLEGA SALTANDO.
	--
	-- La prueba pura fija la RELACIÓN entre el techo de siembra y el salto; esto mide
	-- los que de verdad se plantaron, que es otra cosa: la siembra lee los edificios
	-- del mundo, así que un cambio en el generador puede subirlos sin tocar ninguna
	-- constante. Y un premio que se ve y no se alcanza es el fallo que este proyecto
	-- ya pagó con los racimos.
	do
		local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
		local mejorSalto = 1
		for _, v in Config.VEHICULOS do
			mejorSalto = math.max(mejorSalto, Vehicles.saltoFactor(v.id))
		end
		local alcanza = Config.SALTO_ALTURA * math.max(mejorSalto, Config.SALTO_IMPULSO_FACTOR)
		local enTejado, lejos, masAlto = 0, 0, 0
		for _, d in mundo():GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("enTejado") then
				enTejado += 1
				local alto = d.Position.Y - Grid.Y
				masAlto = math.max(masAlto, alto)
				if alto > alcanza then
					lejos += 1
				end
			end
		end
		comprobar(
			"hay alijos en los tejados",
			enTejado == Config.ALIJOS_ALTOS,
			string.format("%d de %d", enTejado, Config.ALIJOS_ALTOS)
		)
		comprobar(
			"y se llega saltando a todos",
			lejos == 0,
			string.format("%d por encima de %.0f studs, el mas alto a %.0f", lejos, alcanza, masAlto)
		)
	end

	-- Y LAS MANZANAS SE LEVANTAN SOBRE EL ASFALTO, aunque sea por poco.
	--
	-- La pregunta ha cambiado el 21/08. Antes se exigia medio stud, para que la ciudad
	-- no fuera una explanada pintada; ahora el bordillo es de 0,2 a proposito --*"que
	-- solo se vean carreteras a nivel y desaparezcan desniveles raros"*-- porque un
	-- escalon de un stud es realista y, en un juego de correr, una piedra: te frena y
	-- te engancha en las esquinas.
	--
	-- Lo que sigue sin poder pasar es que queden AL RAS EXACTO o por debajo: al ras
	-- dos superficies coplanares parpadean, y por debajo cada manzana es un hoyo. Asi
	-- que el umbral baja pero no desaparece -- lo que se comprueba ya no es "hay
	-- bordillo" sino "no hay parpadeo ni hoyo", que es lo que de verdad importaba.
	local manzanas = ciudad:FindFirstChild("Manzanas")
	local esperadas = (Grid.COL_MAX - Grid.COL_MIN) * (Grid.FILA_MAX - Grid.FILA_MIN)
	comprobar(
		"hay una losa por manzana",
		manzanas ~= nil and #manzanas:GetChildren() == esperadas,
		string.format("hay %d, se esperaban %d", if manzanas then #manzanas:GetChildren() else 0, esperadas)
	)
	if manzanas then
		local bajas = 0
		for _, m in manzanas:GetChildren() do
			if m:IsA("BasePart") and m.Position.Y + m.Size.Y / 2 <= Grid.Y + 0.05 then
				bajas += 1
			end
		end
		comprobar("y todas se levantan sobre la calzada", bajas == 0, string.format("%d al ras o por debajo", bajas))
	end

	-- EL SUELO ES LLANO DONDE SE ANDA. Con retícula propia esto debería ser
	-- trivialmente cierto; si falla, hay un fallo de generación y no un terreno
	-- difícil. Es la comprobación que la ciudad prestada no permitía hacer.
	if calles then
		local alta, baja = -math.huge, math.huge
		for _, p in calles:GetChildren() do
			if p:IsA("BasePart") then
				local cara = p.Position.Y + p.Size.Y / 2
				alta = math.max(alta, cara)
				baja = math.min(baja, cara)
			end
		end
		comprobar(
			"todas las calles estan a la misma cota",
			alta - baja < 0.1,
			string.format("de %.2f a %.2f", baja, alta)
		)
		comprobar(
			"y a la cota que dice el plano",
			math.abs(alta - Grid.Y) < 0.1,
			string.format("las calles en %.2f, el plano dice %.2f", alta, Grid.Y)
		)
	end

	-- A UN GIRO O NINGUNO. Es "no sé a dónde tengo que ir" -- dicho tres partidas
	-- seguidas-- convertido en algo que falla solo. El listón se pone en dos y no en
	-- uno para dejar margen a que un edificio obligue a rodear una manzana.
	for _, ruta in Routes.todas() do
		local vueltas = Grid.giros(Config.POLIGONO_SALIDA, ruta.destino)
		comprobar(
			"al destino " .. ruta.id .. " se llega girando poco",
			vueltas <= 2,
			string.format("%d giros", vueltas)
		)
	end

	-- SIN HITOS QUE COMPROBAR. Aquí se verificaba que los tres se vieran desde la boca
	-- del recinto. Se quitaron del mapa el mismo día que se pusieron, con el resto de
	-- lo vertical, así que la comprobación se va con ellos: una sonda que busca algo
	-- que ya no existe sólo puede dar rojo o mentir.
end

function SelfCheck.run(): string
	resultados = {}

	-- LO PRIMERO DE TODO: traerse los destinos DEL MUNDO.
	--
	-- Sin esto, la bateria entera mide contra los destinos de diseno mientras el
	-- mundo esta construido sobre los sorteados, y canta fallos fantasma sobre un
	-- mapa correcto (ver `destinoDeRuta`). Se parchea aqui, una sola vez, en vez de
	-- en las quince sondas que leen `ruta.destino`: una regla en un sitio.
	--
	-- Y ESCRIBIR AQUI NO TOCA LA PARTIDA. Cuando esto corre por el MCP lo hace en un
	-- sandbox con su propia copia de los modulos, asi que este `Config` no es el del
	-- servidor; y si algun dia corriera dentro del servidor de verdad, lo que se
	-- escribe es EXACTAMENTE lo que ya habia --el destino que se leyo del mundo que
	-- ese servidor construyo-- asi que tampoco cambia nada.
	do
		local m = workspace:FindFirstChild("Mundo")
		for _, ruta in Config.RUTAS do
			ruta.destino = destinoDeRuta(m, ruta.id, ruta.destino)
		end
	end

	local pasos: { { nombre: string, fn: () -> () } } = {
		{ nombre = "retícula", fn = reticula },
		{ nombre = "limites del mundo", fn = limites },
		{ nombre = "piezas del juego", fn = piezasDelJuego },
		{ nombre = "vigilancia", fn = vigilancia },
		{ nombre = "accesos", fn = accesos },
		{ nombre = "viviendas de entrega", fn = viviendas },
		{ nombre = "recogibles limpios", fn = recogiblesLimpios },
		{ nombre = "puerta", fn = puerta },
		{ nombre = "refugios", fn = refugios },
		{ nombre = "guaridas", fn = guaridas },
		{ nombre = "contactos", fn = contactos },
		{ nombre = "dianas", fn = dianas },
		{ nombre = "salida de las guaridas", fn = guaridasConSalida },
		{ nombre = "cobertura de refugios", fn = cobertura },
		{ nombre = "rampa de entrada", fn = rampaDeEntrada },
		{ nombre = "encaje", fn = encaje },
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
