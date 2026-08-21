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

-- SEIS Y NO CUATRO. Cuatro bastaban para que la figura no mintiera (el error de
-- alcance baja al 6 %), pero el sector se pinta ahora con un degradado por tajada y
-- con cuatro escalones el degradado se ve como cuatro franjas: el escalon se lee
-- antes que la forma. Con seis, el ojo lo lee como un foco.
--
-- Y ademas el cliente las usa de resolucion para el BARRIDO --la franja clara que
-- recorre el sector, ver `Alerta.luau`--: con cuatro pasos el barrido da saltos.
local TAJADAS = 6

-- CUANTO SE APAGA EL BORDE respecto al centro del haz. Un foco real no ilumina
-- igual el eje que el canto, y esa diferencia es la que hace que una mancha plana
-- pase a leerse como luz proyectada.
--
-- SE HACE CON COLOR Y NO CON TRANSPARENCIA, y no es un detalle de estilo: las
-- tajadas se solapan un 1 % para que no quede una rendija entre ellas (ver arriba),
-- y dos piezas translucidas superpuestas SUMAN brillo -- o sea una raya luminosa en
-- cada junta, que es exactamente el abanico de palos que este modulo vino a
-- sustituir. Opaco no suma.
local BORDE_APAGADO = 0.45

-- Dibuja el sector y devuelve sus piezas SIN PADRE ASIGNADO en el mundo: quien
-- llama decide donde cuelgan y como se pegan (el ladron las suelda a su raiz, la
-- esquina las deja quietas en la calle).
--
-- `base` es el CFrame del VERTICE del cono, con su frente en -Z, que es el frente
-- de Roblox. Asi se le puede pasar tal cual el CFrame de una raiz de personaje.
--
-- `anclado` NO TIENE VALOR POR DEFECTO, y es a proposito. Estas cunas nacian
-- ancladas siempre --lo correcto para una camara, que no se mueve-- y al reutilizar
-- el dibujo en el LADRON se llevaron el anclaje con ellas. Una pieza anclada soldada
-- a la raiz de un personaje ancla el ENSAMBLAJE ENTERO: el ladron se quedaba clavado
-- en el sitio, en estado `FallingDown` y con `FloorMaterial = Air`, y `MoveTo` no le
-- hacia nada.
--
-- No reventaba, no avisaba, y lo que se veia era un juego donde te fichan y no
-- aparece nadie -- que es una queja que este proyecto lleva arrastrando. Medido:
-- desanclando las ocho cunas en vivo, las patrullas pasaron a `Running`, tocaron
-- suelo y anduvieron 14 studs en cuatro segundos.
--
-- Por eso el parametro se pide siempre: quien dibuje un cono nuevo tiene que
-- contestar "esto se mueve o no", en vez de heredar en silencio la respuesta del
-- primero que lo uso.
function Cone.piezas(
	base: CFrame,
	mitad: number,
	largo: number,
	color: Color3,
	transparencia: number,
	anclado: boolean
): { BasePart }
	local salida: { BasePart } = {}
	local delta = mitad / TAJADAS
	local prof = largo * math.cos(math.rad(delta))
	local semi = largo * math.sin(math.rad(delta)) * 1.01

	for t = 0, TAJADAS - 1 do
		local centro = -mitad + delta * (2 * t + 1)
		-- El degradado: 0 en el eje del haz, 1 en el canto. `centro` es el angulo de
		-- ESTA tajada, asi que el tono sale de cuanto se aparta del frente.
		local fuera = math.abs(centro) / math.max(mitad, 0.001)
		local tono = color:Lerp(Color3.new(0, 0, 0), BORDE_APAGADO * fuera)
		for _, signo in { 1, -1 } do
			local cuna = Instance.new("WedgePart")
			cuna.Name = "Vista"
			-- El indice de la tajada viaja con la pieza: es lo que le permite al
			-- cliente encender una sola --la del barrido-- sin recalcular angulos.
			cuna:SetAttribute("tajada", t)
			cuna:SetAttribute("tajadas", TAJADAS)
			cuna.Size = Vector3.new(0.2, semi, prof)
			cuna.Color = tono
			-- RELLENO EN PLASTICO, NO EN NEON. El neon opaco satura: un naranja en neon
			-- se ve amarillo blanquecino y se come su propio borde, que es justo la
			-- linea que el jugador tiene que leer. El neon se reserva para los bordes,
			-- que es donde brillar significa algo.
			cuna.Material = Enum.Material.SmoothPlastic
			cuna.Transparency = transparencia
			cuna.Anchored = anclado
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

	-- AQUI HABIA DOS BORDES, dos barras neon finas a lo largo de los limites del
	-- sector. La idea era buena: el relleno dice "por aqui te ven" y el borde dice
	-- DONDE DEJA DE VERTE, que es la linea que hay que calcular para pasar por detras.
	--
	-- Y en pantalla salio al reves. Son 45 camaras, o sea NOVENTA barras amarillas
	-- tiradas por las calles, y a la distancia a la que se juega una barra fina y
	-- brillante no se lee como el canto de una mancha: se lee como un objeto suelto.
	-- JJ, mirando el suelo: *"sigue teniendo rectangulos amarillos que no se para que
	-- estan"*.
	--
	-- El sector relleno ya tiene bordes -- los suyos. Y quien lo mira tiene la camara
	-- justo en el vertice diciendo de quien es. No hacia falta subrayarlo.

	return salida
end

return Cone
