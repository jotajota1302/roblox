--!strict
--[[
	Cone.luau — el sector de vision dibujado en el suelo.

	POR QUE EXISTE COMO MODULO. Lo estrena el ladron y lo hereda la esquina
	vigilada, y las dos tienen que dibujar EXACTAMENTE la misma figura: si el ojo
	tuviera que aprender dos simbolos para "aqui te ven", el segundo no lo aprende
	nadie. Un cono es un cono venga de quien venga.

	COMO SE CONSTRUYE, medido y no supuesto. Una `WedgePart` sin girar ocupa el
	triangulo con el angulo recto en (Y=-alto/2, Z=+fondo/2) -- se sondeo con rayos
	horizontales, porque deducirlo del nombre de los ejes ya salio mal una vez. De
	ahi que su vertice agudo sirva de vertice del cono con solo tumbarla 90 grados
	sobre su eje Z.

	El sector se parte en TAJADAS y cada tajada son dos cunas espejadas. Con un solo
	par el borde recto se iria muy por fuera del alcance real --a 60 grados, la
	esquina del triangulo queda al doble de distancia que el centro-- y el dibujo
	mentiria sobre donde te ven. Con cuatro tajadas el error baja al 6 %.

	EL SOLAPE DEL 1 % NO ES ADORNO: sin el, entre dos tajadas queda una rendija de
	grosor cero por redondeo, y una sonda de rayos la encontro justo a 0 grados --
	delante de las narices del vigilante, el peor sitio posible para un agujero.

	Y VA OPACO, que es lo que costo la primera version. Con las tajadas
	semitransparentes, el 1 % de solape SUMA brillo y dibuja una raya luminosa en
	cada junta: el resultado en pantalla eran cuatro palos naranjas saliendo del
	vigilante -- exactamente el abanico de varillas que este modulo vino a sustituir.
	JJ mando la captura preguntando *"eso que es?"*, que es la respuesta correcta a
	un simbolo que no se parece a nada.

	Este fichero no descubrio nada: `CityBuilder` ya lo tenia escrito de otra vez --
	*"Roblox no ordena bien las piezas semitransparentes que se solapan y el orden
	cambia de un fotograma a otro"*. Opaco no suma, y las tajadas van ESCALONADAS un
	par de centesimas de stud para que la parte solapada tampoco pelee por la
	profundidad, que es la otra cara del mismo problema.
]]

local Cone = {}

local TAJADAS = 4

-- Dibuja el sector y devuelve sus piezas SIN PADRE ASIGNADO en el mundo: quien
-- llama decide donde cuelgan y como se pegan (el ladron las suelda a su raiz, la
-- esquina las deja quietas en la calle).
--
-- `base` es el CFrame del VERTICE del cono, con su frente en -Z, que es el frente
-- de Roblox. Asi se le puede pasar tal cual el CFrame de una raiz de personaje.
function Cone.piezas(base: CFrame, mitad: number, largo: number, color: Color3, transparencia: number): { BasePart }
	local salida: { BasePart } = {}
	local delta = mitad / TAJADAS
	local prof = largo * math.cos(math.rad(delta))
	local semi = largo * math.sin(math.rad(delta)) * 1.01

	for t = 0, TAJADAS - 1 do
		local centro = -mitad + delta * (2 * t + 1)
		for _, signo in { 1, -1 } do
			local cuna = Instance.new("WedgePart")
			cuna.Name = "Vista"
			cuna.Size = Vector3.new(0.2, semi, prof)
			cuna.Color = color
			-- RELLENO EN PLASTICO, NO EN NEON. El neon opaco satura: un naranja en neon
			-- se ve amarillo blanquecino y se come su propio borde, que es justo la
			-- linea que el jugador tiene que leer. El neon se reserva para los bordes,
			-- que es donde brillar significa algo.
			cuna.Material = Enum.Material.SmoothPlastic
			cuna.Transparency = transparencia
			cuna.Anchored = true
			cuna.CanCollide = false
			cuna.CanQuery = false
			cuna.CanTouch = false
			cuna.CastShadow = false
			cuna.Massless = true
			-- Escalonada: cada tajada un pelin mas alta que la anterior, para que la
			-- franja donde se solapan no pelee por la profundidad.
			cuna.CFrame = base
				* CFrame.new(0, t * 0.02, 0)
				* CFrame.Angles(0, math.pi + math.rad(centro), 0)
				* CFrame.Angles(0, 0, math.rad(90) * signo)
				* CFrame.new(0, semi / 2, prof / 2)
			table.insert(salida, cuna)
		end
	end

	-- LOS DOS BORDES, finos y mas claros. El relleno dice "por aqui te ven" y el
	-- borde dice DONDE DEJA DE VERTE, que es la linea que el jugador tiene que
	-- calcular para pasar por detras. Sin ella el limite se difumina justo donde
	-- importa que sea nitido.
	for _, signo in { 1, -1 } do
		local borde = Instance.new("Part")
		borde.Name = "VistaBorde"
		borde.Size = Vector3.new(0.5, 0.1, largo)
		-- ACLARADO POCO. Con +0,35 el neon lo empujaba fuera de rango y los dos bordes
		-- salian BLANCOS: dejaban de pertenecer al cono y parecian dos barras sueltas,
		-- que es de donde se viene. Con +0,12 sigue siendo el mismo naranja, mas vivo.
		borde.Color = Color3.new(math.min(1, color.R + 0.12), math.min(1, color.G + 0.12), math.min(1, color.B + 0.12))
		borde.Material = Enum.Material.Neon
		borde.Transparency = math.max(0, transparencia - 0.45)
		borde.Anchored = true
		borde.CanCollide = false
		borde.CanQuery = false
		borde.CanTouch = false
		borde.CastShadow = false
		borde.Massless = true
		borde.CFrame = base * CFrame.Angles(0, math.rad(mitad * signo), 0) * CFrame.new(0, 0.15, -largo / 2)
		table.insert(salida, borde)
	end

	return salida
end

return Cone
