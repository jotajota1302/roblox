--!strict
--[[
	StreetProps.luau — el mobiliario urbano: farolas, árboles y el jardín.

	POR QUÉ EXISTE. *"Me gustaría tener un mapa más trabajado, con edificios, calles,
	aceras, farolas, árboles, si hay algún jardín, etc."* (JJ). Las calles y las
	aceras ya están; esto es lo que va ENCIMA de la acera, y lo que convierte una
	retícula correcta en un sitio.

	Y no es sólo decorar. Un mapa de cajas grises no da referencias: todas las
	esquinas son la misma esquina, y sin referencias el jugador no construye un mapa
	mental -- de ahí *"no sé hacia dónde tirar"* y *"el sitio es feo y confuso"*, dos
	de los tres veredictos negativos que hicieron abandonar el mapa del Creator Store.
	Un árbol en una esquina y un jardín en el centro son puntos de los que acordarse.

	TRES REGLAS QUE NO SE SALTAN, y las tres se han pagado en este proyecto:

	  · TODO VA SIN `CanQuery`. `CityBuilder` siembra el mundo lanzando rayos hacia
	    abajo, y un rayo que se para en la copa de un árbol devuelve "el suelo está a
	    28 studs de altura" -- así se descartó media ciudad prestada por imposible. Un
	    decorado invisible para los rayos no puede romper nada de lo que se siembra
	    después.
	  · Y SIN COLISIÓN. El pathfinding de las patrullas ya se encalla con las vallas
	    de la ciudad (tres tramos sin avanzar y hay que reubicarlas); plantar
	    doscientos postes con cuerpo es multiplicar ese problema por doscientos. Un
	    farol atravesable es un defecto que nadie nota; una patrulla clavada detrás de
	    un árbol apaga el sistema de persecución en silencio.
	  · NADA COPLANAR. Cada pieza apoyada sobre otra sube al menos 0,03 studs sobre
	    ella: la sonda del mundo salta a 0,02 y tiene razón -- dos caras a la misma
	    cota parpadean.

	Nada de meshes. Con el place sin publicar no cargan (`PlaceId == 0`), así que un
	árbol de malla sería un árbol invisible. Todo son `Part`.
]]

local Grid = require(game.ReplicatedStorage.Shared.Grid)

local StreetProps = {}

-- Cada cuántos studs se planta algo a lo largo de una acera. 34 es el resultado de
-- una cuenta y no un gusto: la manzana mide 120, así que caben tres por lado con
-- márgenes -- suficiente para que la calle tenga ritmo, y lo bastante espaciado para
-- que no se conviertan en una valla visual que tape a los ladrones.
local PASO_MOBILIARIO = 34
-- Y cuánto se separan del bordillo, hacia dentro de la manzana. El bordillo ocupa
-- los dos primeros studs; 4 deja el poste justo detrás, como en una acera de verdad.
local RETRANQUEO = 4

local COLOR_POSTE = Color3.fromRGB(58, 60, 66)
local COLOR_LUZ = Color3.fromRGB(255, 226, 150)
local COLOR_TRONCO = Color3.fromRGB(86, 66, 50)
local COLOR_COPA_A = Color3.fromRGB(62, 108, 58)
local COLOR_COPA_B = Color3.fromRGB(78, 126, 66)
local COLOR_CESPED = Color3.fromRGB(96, 134, 76)
local COLOR_CAMINO = Color3.fromRGB(168, 158, 140)
local COLOR_BANCO = Color3.fromRGB(120, 92, 64)
local COLOR_AGUA = Color3.fromRGB(96, 148, 176)

local contador = 0

local function pieza(nombre: string, tamano: Vector3, centro: Vector3, color: Color3, padre: Instance): Part
	contador += 1
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tamano
	p.Position = centro
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	-- Las tres reglas de la cabecera, en tres líneas. Van aquí y no en cada llamada
	-- justo para que no se puedan olvidar en una pieza nueva.
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = padre
	return p
end

-- UNA FAROLA, y lo importante es que NO se parezca a una cámara.
--
-- El mapa ya tiene 43 cámaras de vigilancia hechas de mástil, cabeza y lente, y
-- añadir doscientos postes parecidos convertiría la única señal de peligro del juego
-- en ruido de fondo. Así que la farola es alta y de brazo largo, con la luz cálida
-- COLGANDO sobre la calzada, mientras que la cámara es baja, tiene visor y un piloto
-- rojo. Se distinguen por la silueta, que es como se distinguen las cosas a la
-- distancia a la que se juega.
local function farola(centro: Vector3, haciaLaCalle: Vector3, padre: Instance)
	local ALTO = 9
	local base =
		pieza("FarolaPoste", Vector3.new(0.7, ALTO, 0.7), centro + Vector3.new(0, ALTO / 2, 0), COLOR_POSTE, padre)
	base.Material = Enum.Material.Metal

	-- El brazo sale HACIA LA CALZADA: una farola que alumbra la fachada no alumbra
	-- nada. Y de paso da la dirección de un vistazo, que en un mapa de retícula
	-- ayuda a saber por dónde va la calle.
	local largoBrazo = 3.2
	local brazo = pieza(
		"FarolaBrazo",
		Vector3.new(0.45, 0.45, largoBrazo),
		centro + Vector3.new(0, ALTO - 0.4, 0) + haciaLaCalle * (largoBrazo / 2),
		COLOR_POSTE,
		padre
	)
	brazo.Material = Enum.Material.Metal
	brazo.CFrame = CFrame.lookAt(brazo.Position, brazo.Position + haciaLaCalle)

	local lampara = pieza(
		"FarolaLuz",
		Vector3.new(1.3, 0.5, 1.8),
		centro + Vector3.new(0, ALTO - 0.85, 0) + haciaLaCalle * largoBrazo,
		COLOR_LUZ,
		padre
	)
	-- NEON Y NO UNA LUZ DE VERDAD. Un `PointLight` por farola serían doscientas luces
	-- dinámicas, y Roblox ni las dibuja todas ni le sale gratis intentarlo. El neón se
	-- ve encendido desde lejos, cuesta lo que una pieza normal, y a la distancia a la
	-- que se juega no se distingue de una lámpara iluminando.
	lampara.Material = Enum.Material.Neon
	lampara.CFrame = CFrame.lookAt(lampara.Position, lampara.Position + haciaLaCalle)
end

-- UN ÁRBOL de tronco y tres copas escalonadas.
--
-- Tres y no una: una sola caja verde encima de un palo se lee como una seta. Lo que
-- convierte tres cajas en un árbol es que sean de tamaños distintos, con un giro
-- entre ellas y dos verdes que no son el mismo -- la irregularidad es la señal, no el
-- detalle.
local function arbol(centro: Vector3, semilla: number, padre: Instance)
	local rng = Random.new(semilla)
	local altoTronco = rng:NextNumber(4.5, 6.5)
	local tronco = pieza(
		"ArbolTronco",
		Vector3.new(1.1, altoTronco, 1.1),
		centro + Vector3.new(0, altoTronco / 2, 0),
		COLOR_TRONCO,
		padre
	)
	tronco.Material = Enum.Material.Wood

	local anchoBase = rng:NextNumber(5, 6.5)
	local capas = {
		{ anchoBase, 2.6, COLOR_COPA_A },
		{ anchoBase * 0.8, 2.2, COLOR_COPA_B },
		{ anchoBase * 0.55, 1.8, COLOR_COPA_A },
	}
	local y = altoTronco
	for i, capa in capas do
		local ancho, alto, color = capa[1] :: number, capa[2] :: number, capa[3] :: Color3
		local hoja =
			pieza("ArbolCopa", Vector3.new(ancho, alto, ancho), centro + Vector3.new(0, y + alto / 2, 0), color, padre)
		hoja.Material = Enum.Material.Grass
		-- Giradas entre sí: dos cajas alineadas se leen como una sola caja alta.
		hoja.CFrame = CFrame.new(hoja.Position) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90) + i * 18), 0)
		y += alto * 0.72
	end
end

-- EL JARDÍN, en la manzana que ya estaba vacía.
--
-- No se inventa un hueco: la plaza de la zona verde existe desde que se hizo la
-- retícula, como atajo peatonal, y hasta ahora era una losa gris pelada. Ponerle
-- césped, dos caminos en cruz y una fuente le da lo que le faltaba -- ser un SITIO,
-- el único punto del mapa del que uno se acuerda al describirlo por teléfono.
--
-- Los caminos van en cruz y no en diagonal porque el atajo tiene que seguir siendo
-- legible: se entra por el centro de un lado y se sale por el del contrario.
function StreetProps.jardin(col: number, fila: number, cotaSuperior: number, padre: Instance)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local ancho, largo = x1 - x0, z1 - z0

	-- El césped, apoyado sobre la losa de la manzana y por encima de ella: la sonda
	-- de parpadeo salta a 0,02 y dos caras a la misma cota se pelean.
	local cesped = pieza(
		"JardinCesped",
		Vector3.new(ancho - 4, 0.2, largo - 4),
		Vector3.new(cx, cotaSuperior + 0.14, cz),
		COLOR_CESPED,
		padre
	)
	cesped.Material = Enum.Material.Grass

	-- Los dos caminos, por encima del césped por el mismo motivo.
	local ANCHO_CAMINO = 8
	local y = cotaSuperior + 0.32
	local ca =
		pieza("JardinCamino", Vector3.new(ANCHO_CAMINO, 0.2, largo - 4), Vector3.new(cx, y, cz), COLOR_CAMINO, padre)
	ca.Material = Enum.Material.Concrete
	-- El segundo, PARTIDO en dos para no cruzarse con el primero a la misma cota.
	local trozo = (ancho - 4 - ANCHO_CAMINO) / 2
	for _, lado in { -1, 1 } do
		local cb = pieza(
			"JardinCamino",
			Vector3.new(trozo, 0.2, ANCHO_CAMINO),
			Vector3.new(cx + lado * (ANCHO_CAMINO / 2 + trozo / 2), y, cz),
			COLOR_CAMINO,
			padre
		)
		cb.Material = Enum.Material.Concrete
	end

	-- La fuente: pila, agua y chorro. Es el punto de referencia del mapa entero.
	local pila = pieza("FuenteBase", Vector3.new(1.2, 11, 11), Vector3.new(cx, y + 0.7, cz), COLOR_CAMINO, padre)
	pila.Material = Enum.Material.Concrete
	pila.Shape = Enum.PartType.Cylinder
	pila.CFrame = CFrame.new(pila.Position) * CFrame.Angles(0, 0, math.rad(90))
	local agua = pieza("FuenteAgua", Vector3.new(0.4, 9, 9), Vector3.new(cx, y + 1.35, cz), COLOR_AGUA, padre)
	agua.Material = Enum.Material.Glass
	agua.Shape = Enum.PartType.Cylinder
	agua.CFrame = CFrame.new(agua.Position) * CFrame.Angles(0, 0, math.rad(90))
	-- El chorro, MAS ALTO QUE EL AGUA. Con 3,6 su tapa caia a la misma cota que la
	-- del cilindro del agua y la sonda de parpadeo lo canto -- ella mide sin tener en
	-- cuenta el giro del cilindro, asi que es un falso positivo, pero da igual: dos
	-- caras a la misma cota son un riesgo real de todas formas, y separarlas cuesta
	-- una decima.
	local chorro = pieza("FuenteChorro", Vector3.new(1.4, 5.2, 1.4), Vector3.new(cx, y + 4.1, cz), COLOR_AGUA, padre)
	chorro.Material = Enum.Material.Glass

	-- Cuatro árboles hacia las esquinas del césped y cuatro bancos mirando adentro.
	local margen = 16
	local esquinas = {
		Vector3.new(x0 + margen, cotaSuperior, z0 + margen),
		Vector3.new(x1 - margen, cotaSuperior, z0 + margen),
		Vector3.new(x0 + margen, cotaSuperior, z1 - margen),
		Vector3.new(x1 - margen, cotaSuperior, z1 - margen),
	}
	for i, sitio in esquinas do
		arbol(sitio, col * 977 + fila * 131 + i * 17, padre)
		local banco = pieza(
			"Banco",
			Vector3.new(if i % 2 == 1 then 6 else 1.2, 1.1, if i % 2 == 1 then 1.2 else 6),
			Vector3.new(cx + (sitio.X - cx) * 0.42, y + 0.65, cz + (sitio.Z - cz) * 0.42),
			COLOR_BANCO,
			padre
		)
		banco.Material = Enum.Material.Wood
	end
end

-- Reparte farolas y árboles por las aceras de una manzana, alternando: farola,
-- árbol, farola... Alternar es lo que hace que la calle tenga ritmo en vez de ser una
-- hilera de lo mismo, y de paso reparte el coste -- un árbol son cuatro piezas y una
-- farola tres.
function StreetProps.acerasDe(col: number, fila: number, cotaSuperior: number, padre: Instance)
	local x0, x1, z0, z1 = Grid.manzana(col, fila)
	local n = 0

	local function repartir(desde: Vector3, hasta: Vector3, haciaLaCalle: Vector3)
		local largo = (hasta - desde).Magnitude
		local cuantos = math.max(1, math.floor(largo / PASO_MOBILIARIO))
		for k = 1, cuantos do
			local t = (k - 0.5) / cuantos
			local sitio = desde:Lerp(hasta, t)
			n += 1
			if n % 2 == 1 then
				farola(sitio, haciaLaCalle, padre)
			else
				arbol(sitio, col * 613 + fila * 271 + n * 43, padre)
			end
		end
	end

	-- Los cuatro lados, cada uno mirando a SU calle. Los laterales arrancan más
	-- adentro para no chocar con los de arriba y abajo en las esquinas.
	repartir(
		Vector3.new(x0 + RETRANQUEO, cotaSuperior, z0 + RETRANQUEO),
		Vector3.new(x1 - RETRANQUEO, cotaSuperior, z0 + RETRANQUEO),
		Vector3.new(0, 0, -1)
	)
	repartir(
		Vector3.new(x0 + RETRANQUEO, cotaSuperior, z1 - RETRANQUEO),
		Vector3.new(x1 - RETRANQUEO, cotaSuperior, z1 - RETRANQUEO),
		Vector3.new(0, 0, 1)
	)
	repartir(
		Vector3.new(x0 + RETRANQUEO, cotaSuperior, z0 + RETRANQUEO * 4),
		Vector3.new(x0 + RETRANQUEO, cotaSuperior, z1 - RETRANQUEO * 4),
		Vector3.new(-1, 0, 0)
	)
	repartir(
		Vector3.new(x1 - RETRANQUEO, cotaSuperior, z0 + RETRANQUEO * 4),
		Vector3.new(x1 - RETRANQUEO, cotaSuperior, z1 - RETRANQUEO * 4),
		Vector3.new(1, 0, 0)
	)
end

function StreetProps.cuantasPiezas(): number
	return contador
end

return StreetProps
