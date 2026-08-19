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
local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
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

	-- SE VEN POR ENCIMA DEL BARRIO. Su trabajo entero es que las rodees, y una
	-- guarida que no se distingue desde lejos no se rodea: se descubre cuando ya te
	-- ha soltado un ladrón encima, que es exactamente lo que venía a arreglar. El
	-- farol medía 46 studs cuando los tejados de alrededor pasan de 80, así que la
	-- guarida sólo existía en el minimapa -- *"no los veo a lo lejos"* (JJ).
	--
	-- Se compara contra los EDIFICIOS DE SU MANZANA, no contra una constante: lo que
	-- importa no es la altura del farol sino si asoma por encima de lo que tiene al
	-- lado, y eso depende de dónde haya caído.
	--
	-- Y contra el percentil 80 de los tejados de alrededor, no contra el más alto:
	-- una torre suelta puede taparlo desde UN ángulo y eso no es un defecto --es la
	-- ciudad haciendo de ciudad--. Lo que sí lo es, y es lo que se mide, es que el
	-- farol quede por debajo del caserío normal y no se vea desde ninguna parte.
	local ciudad = workspace:FindFirstChild("Ciudad")
	local altos: { BasePart } = {}
	if ciudad then
		for _, p in ciudad:GetDescendants() do
			if p:IsA("BasePart") and p.Size.Y > 20 then
				table.insert(altos, p)
			end
		end
	end

	local tapadas, peor = 0, 0
	for _, g in sitios do
		local farol = m:FindFirstChild("GuaridaFarol_" .. string.match(g.Name, "%d+"))
		if farol == nil or not farol:IsA("BasePart") then
			continue
		end
		local cima = farol.Position.Y + farol.Size.Y / 2

		local cimas: { number } = {}
		for _, p in altos do
			local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(g.Position.X, 0, g.Position.Z)).Magnitude
			if d <= 150 then
				table.insert(cimas, p.Position.Y + p.Size.Y / 2)
			end
		end
		table.sort(cimas)
		local barrio = if #cimas > 0 then cimas[math.max(1, math.ceil(#cimas * 0.8))] else g.Position.Y

		if cima < barrio then
			tapadas += 1
			peor = math.max(peor, barrio - cima)
		end
	end
	comprobar(
		"las guaridas asoman sobre su manzana",
		tapadas == 0,
		string.format("%d tapadas por los edificios de al lado (hasta %.0f studs por debajo)", tapadas, peor)
	)
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

	-- NI UNO A LA SALIDA DEL ALMACÉN. Lo vio JJ jugando y la sonda no lo miraba: el
	-- de la ruta verde estaba a 230 studs de casa, con la puerta a 35 studs de donde
	-- acaba la zona segura. Pegado al almacén, un refugio no es una decisión --el
	-- almacén apaga el calor entero y encima es donde cobras-- y una opción que
	-- nunca puede ganar es una opción que no existe.
	local minimo = Config.ZONA_SEGURA_RADIO + Config.REFUGIO_MARGEN_CASA / 2
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

		-- ENTERRADA: el terreno sube por encima de su base, o sea que un trozo de la
		-- pieza está dentro de la loma.
		local enterrada = alto - base
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

	-- Y EL CAMINO REAL, ruta por ruta.
	for _, ruta in Routes.todas() do
		local camino = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function()
			camino:ComputeAsync(Config.POLIGONO_SALIDA, ruta.destino)
		end)
		if not ok or camino.Status ~= Enum.PathStatus.Success then
			comprobar("hay camino a pie hasta " .. ruta.id, false, tostring(camino.Status))
			continue
		end

		local puntos: { Vector3 } = {}
		for _, w in camino:GetWaypoints() do
			table.insert(puntos, w.Position)
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

-- EL BARRIO: la rampa de entrada. Su destino es el ÚNICO del juego que se puso
-- estimado y no medido -- sale de interpolar entre el enganche del polígono y el
-- destino verde --, así que esta sonda es la que dice si la estimación valía.
--
-- Y mide lo que importa de verdad, que no es que exista sino que se pueda ir
-- ANDANDO y que sea corto: la razón de ser del barrio es que la primera
-- recompensa llegue en ~45 s en vez de ~100.
local function barrio()
	local m = mundo()
	if m == nil then
		return
	end

	local ruta = Routes.get("barrio")
	if ruta == nil then
		comprobar("existe la ruta del barrio", false, "no está en Config.RUTAS")
		return
	end

	-- Apoyado en el suelo, medido contra lo que tiene DEBAJO y no contra una cota
	-- fija: la ciudad tiene laderas.
	local golpe = bajoLosPies(ruta.destino.X, ruta.destino.Y + 6, ruta.destino.Z, 300)
	comprobar(
		"el destino del barrio se apoya en el suelo",
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
		comprobar("hay camino a pie hasta el barrio", false, tostring(camino.Status))
		return
	end

	local largo = 0
	local puntos = camino:GetWaypoints()
	for i = 1, #puntos - 1 do
		local a, b = puntos[i].Position, puntos[i + 1].Position
		largo += math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
	end

	-- Por debajo de 200 la entrega cae dentro de la zona segura y no enseña nada;
	-- por encima de 350 deja de ser un bucle corto y no arregla lo que vino a
	-- arreglar.
	comprobar(
		"el barrio está a la distancia de una rampa",
		largo >= 200 and largo <= 350,
		string.format("%d studs andando: fuera de la horquilla 200-350", math.floor(largo))
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

function SelfCheck.run(): string
	resultados = {}

	local pasos: { { nombre: string, fn: () -> () } } = {
		{ nombre = "piezas del juego", fn = piezasDelJuego },
		{ nombre = "vigilancia", fn = vigilancia },
		{ nombre = "accesos", fn = accesos },
		{ nombre = "puerta", fn = puerta },
		{ nombre = "refugios", fn = refugios },
		{ nombre = "guaridas", fn = guaridas },
		{ nombre = "contactos", fn = contactos },
		{ nombre = "barrio", fn = barrio },
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
