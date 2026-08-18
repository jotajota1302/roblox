--!strict
--[[
	Goods.luau — QUÉ transportas. Módulo PURO.

	Existe porque "todo eran cajas" (JJ) y eso vaciaba dos cosas a la vez: el
	transporte no significaba nada --daba igual llevar un cubo marrón que otro-- y
	la progresión de vehículos se quedaba en un número de capacidad sin motivo.

	La pieza que lo arregla es la regla que puso JJ: **no puedes llevar algo grande
	sin un vehículo para ello**. Con ella, el catálogo deja de ser decoración y pasa
	a ser el motor del juego: ves un piano que paga x50 en tu almacén, no te cabe en
	el monopatín, y ya sabes exactamente para qué es el dinero. El vehículo deja de
	ser "una caja más" y se convierte en UNA LLAVE.

	Cada objeto lleva su tamaño Y su valor juntos y a mano, no sorteados por
	separado: así el jugador puede APRENDER el catálogo --"el joyero es pequeño y
	paga mucho, el sofá ocupa medio camión por calderilla"-- y esa memoria es
	justamente la habilidad que hace que la segunda partida se juegue mejor que la
	primera. Con tamaño y valor independientes saldrían combinaciones absurdas
	(un piano que no vale nada, un sobre que vale una fortuna) y no habría nada que
	aprender.
]]

local Config = require(script.Parent.Config)

export type Objeto = {
	id: string,
	nombre: string,
	-- Referencia a Config.RAREZAS: de ahí salen el multiplicador y el color.
	rareza: string,
	-- Referencia a Config.TAMANOS: de ahí salen los huecos y el vehículo mínimo.
	tamano: string,
	-- Peso relativo en la tirada. No es una probabilidad: se normaliza contra el
	-- total, así que añadir un objeto nuevo no obliga a recalcular los demás.
	frecuencia: number,
	-- Cómo se dibuja. Lo interpretan CargoService (a la espalda) y Stock (en el
	-- muelle); aquí sólo se nombra, para que las dos mitades no discrepen.
	forma: string,
}

-- El catálogo. Ordenado de pequeño a enorme para que se lea como una escalera.
--
-- Lo COMÚN es lo pequeño y lo que más sale: el jugador nuevo tiene que poder
-- trabajar desde el primer minuto sin vehículo. Lo enorme paga mucho y sale poco,
-- y encima exige coche o furgoneta -- es el escaparate de por qué seguir jugando.
local CATALOGO: { Objeto } = {
	-- Pequeños: caben andando. El pan de cada día.
	{
		id = "sobre",
		nombre = "Sobre lacrado",
		rareza = "marcada",
		tamano = "pequeno",
		frecuencia = 10,
		forma = "sobre",
	},
	{ id = "joyero", nombre = "Joyero", rareza = "sellada", tamano = "pequeno", frecuencia = 3, forma = "joyero" },
	{ id = "frasco", nombre = "Frasco", rareza = "comun", tamano = "pequeno", frecuencia = 22, forma = "frasco" },
	{ id = "libro", nombre = "Libro antiguo", rareza = "comun", tamano = "pequeno", frecuencia = 18, forma = "libro" },

	-- Medianos: a partir del monopatín.
	{ id = "maletin", nombre = "Maletín", rareza = "marcada", tamano = "mediano", frecuencia = 9, forma = "maletin" },
	{
		id = "cajon",
		nombre = "Cajón de fruta",
		rareza = "comun",
		tamano = "mediano",
		frecuencia = 16,
		forma = "cajon",
	},
	{ id = "maceta", nombre = "Maceta", rareza = "comun", tamano = "mediano", frecuencia = 10, forma = "maceta" },
	{ id = "urna", nombre = "Urna", rareza = "sellada", tamano = "mediano", frecuencia = 4, forma = "urna" },

	-- Grandes: bicicleta o moto.
	{
		id = "television",
		nombre = "Televisor",
		rareza = "marcada",
		tamano = "grande",
		frecuencia = 6,
		forma = "television",
	},
	{ id = "baul", nombre = "Baúl", rareza = "sellada", tamano = "grande", frecuencia = 4, forma = "baul" },
	{ id = "barril", nombre = "Barril", rareza = "comun", tamano = "grande", frecuencia = 7, forma = "barril" },

	-- Enormes: coche o furgoneta, y sólo por eso ya son un objetivo a medio plazo.
	{ id = "nevera", nombre = "Nevera", rareza = "marcada", tamano = "enorme", frecuencia = 3, forma = "nevera" },
	{ id = "sofa", nombre = "Sofá", rareza = "comun", tamano = "enorme", frecuencia = 4, forma = "sofa" },
	{ id = "piano", nombre = "Piano", rareza = "sellada", tamano = "enorme", frecuencia = 2, forma = "piano" },
	{ id = "estatua", nombre = "Estatua", rareza = "legendaria", tamano = "enorme", frecuencia = 1, forma = "estatua" },
}

-- Cómo se dibuja cada forma: proporciones y material. El COLOR no está aquí --
-- sale de la rareza, para que el valor se siga leyendo de un vistazo. Así una
-- nevera marcada y un televisor marcado comparten tono pero no silueta: sabes lo
-- que vale por el color y lo que es por la forma.
--
-- `alto` es lo que mide sobre el suelo en studs; ancho y fondo salen de él por
-- proporción. Los objetos enormes son de verdad enormes: ver un piano en el
-- muelle y no poder ni acercarlo a los patines es el argumento de venta de la
-- furgoneta, y para eso tiene que verse que no cabe.
export type Aspecto = {
	alto: number,
	proporcion: Vector3,
	material: Enum.Material,
}

local ASPECTOS: { [string]: Aspecto } = {
	sobre = { alto = 0.4, proporcion = Vector3.new(1.6, 1, 2.2), material = Enum.Material.SmoothPlastic },
	joyero = { alto = 1.1, proporcion = Vector3.new(1.4, 1, 1.1), material = Enum.Material.Metal },
	frasco = { alto = 1.6, proporcion = Vector3.new(0.6, 1, 0.6), material = Enum.Material.Glass },
	libro = { alto = 0.5, proporcion = Vector3.new(1.5, 1, 2), material = Enum.Material.Fabric },

	maletin = { alto = 1.4, proporcion = Vector3.new(2.1, 1, 0.7), material = Enum.Material.Metal },
	cajon = { alto = 2.2, proporcion = Vector3.new(1.2, 1, 1.2), material = Enum.Material.WoodPlanks },
	maceta = { alto = 2, proporcion = Vector3.new(0.9, 1, 0.9), material = Enum.Material.Slate },
	urna = { alto = 2.6, proporcion = Vector3.new(0.7, 1, 0.7), material = Enum.Material.Foil },

	television = { alto = 2.6, proporcion = Vector3.new(1.7, 1, 0.4), material = Enum.Material.SmoothPlastic },
	baul = { alto = 2.4, proporcion = Vector3.new(1.9, 1, 1.2), material = Enum.Material.WoodPlanks },
	barril = { alto = 3, proporcion = Vector3.new(0.8, 1, 0.8), material = Enum.Material.Wood },

	nevera = { alto = 6, proporcion = Vector3.new(0.55, 1, 0.5), material = Enum.Material.SmoothPlastic },
	sofa = { alto = 2.6, proporcion = Vector3.new(3, 1, 1.2), material = Enum.Material.Fabric },
	piano = { alto = 3.4, proporcion = Vector3.new(2.1, 1, 1.6), material = Enum.Material.Wood },
	estatua = { alto = 6.5, proporcion = Vector3.new(0.45, 1, 0.45), material = Enum.Material.Marble },
}

local Goods = {}

-- El aspecto de un objeto por su id. Devuelve el del cajón si no se conoce: una
-- pieza con forma rara es mucho mejor que una pieza que no se dibuja.
function Goods.aspecto(objetoId: string?): Aspecto
	if objetoId == nil then
		return ASPECTOS.cajon
	end
	local o = Goods.get(objetoId)
	if not o then
		return ASPECTOS.cajon
	end
	return ASPECTOS[o.forma] or ASPECTOS.cajon
end

-- El tamaño real de la pieza, ya en studs. `escalaBase` permite dibujar lo mismo
-- pequeño a la espalda del jugador y a tamaño natural en el muelle, sin que las
-- dos mitades tengan cada una su propia idea de las proporciones.
function Goods.medida(objetoId: string?, escalaBase: number): Vector3
	local a = Goods.aspecto(objetoId)
	local alto = a.alto * escalaBase
	return Vector3.new(alto * a.proporcion.X, alto, alto * a.proporcion.Z)
end

function Goods.todos(): { Objeto }
	local copia: { Objeto } = {}
	for _, o in CATALOGO do
		table.insert(copia, table.clone(o))
	end
	return copia
end

function Goods.get(id: string): Objeto?
	for _, o in CATALOGO do
		if o.id == id then
			return o
		end
	end
	return nil
end

local function tamanoDe(id: string)
	for _, t in Config.TAMANOS do
		if t.id == id then
			return t
		end
	end
	return Config.TAMANOS[1]
end

-- Cuánto ocupa de la capacidad del vehículo.
function Goods.huecos(objetoId: string): number
	local o = Goods.get(objetoId)
	if not o then
		return 1
	end
	return tamanoDe(o.tamano).huecos
end

-- Qué listón de vehículo exige. Es LA regla nueva: un piano no entra en unos
-- patines por mucho hueco libre que quede.
function Goods.nivelExigido(objetoId: string): number
	local o = Goods.get(objetoId)
	if not o then
		return 1
	end
	return tamanoDe(o.tamano).nivel
end

-- Lo que se lee encima de la pieza: qué es y cuánto multiplica. Con respaldo a la
-- rareza para las cargas guardadas antes de que existiera el catálogo, que no
-- tienen objeto y aun así tienen que poder dibujarse con su etiqueta.
function Goods.etiqueta(objetoId: string?, rareza: string): string
	local multiplicador = 1
	local ok, def = pcall(function()
		return Config.RAREZAS
	end)
	if ok and def then
		for _, r in def do
			if r.id == rareza then
				multiplicador = r.multiplicador
			end
		end
	end
	local o = if objetoId ~= nil then Goods.get(objetoId) else nil
	local nombre = if o then o.nombre else "Bulto"
	return string.format("%s  x%d", nombre, multiplicador)
end

function Goods.nombreTamano(objetoId: string): string
	local o = Goods.get(objetoId)
	if not o then
		return ""
	end
	return tamanoDe(o.tamano).nombre
end

-- La tirada. Recibe el Random en vez de crearlo dentro para que con semilla fija
-- sea determinista y se pueda comprobar el reparto de verdad, igual que Rarity.
--
-- `nivelMaximo` filtra por lo que el jugador PUEDE mover. Sin él, un jugador a pie
-- llenaría el almacén de sofás que no puede tocar y se quedaría sin juego -- que
-- es exactamente lo contrario del efecto buscado: lo grande tiene que verse de vez
-- en cuando como promesa, no ser todo lo que hay.
function Goods.tirada(rng: Random, nivelMaximo: number?): Objeto
	local tope = nivelMaximo or 4
	local candidatos: { Objeto } = {}
	local total = 0
	for _, o in CATALOGO do
		if tamanoDe(o.tamano).nivel <= tope then
			table.insert(candidatos, o)
			total += o.frecuencia
		end
	end
	if #candidatos == 0 then
		return CATALOGO[1]
	end

	local tirada = rng:NextNumber() * total
	local acumulado = 0
	for _, o in candidatos do
		acumulado += o.frecuencia
		if tirada <= acumulado then
			return o
		end
	end
	-- Red de seguridad por redondeo: devolver el último es infinitamente mejor
	-- que devolver nil.
	return candidatos[#candidatos]
end

return Goods
