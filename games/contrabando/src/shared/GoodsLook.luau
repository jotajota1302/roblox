--!strict
--[[
	GoodsLook.luau — cómo se DIBUJA cada cosa que se transporta.

	"¿Es normal que los paquetes sigan siendo cuadrados?" (JJ, jugando). En parte
	sí y en parte no, y la parte que no era arreglable es ésta.

	La parte inevitable: los modelos 3D de verdad (mallas) NO CARGAN mientras el
	place no esté publicado -- ni los generados con Cube 3D ni los de la biblioteca
	de Roblox. Es la misma trampa que dejó al avatar invisible. Así que todo lo que
	se ve hoy está hecho con Part, y lo seguirá estando hasta que el place se
	publique.

	La parte que sí era nuestra: con Part también se puede dejar de parecer un
	cubo. Un barril son tres aros, un sofá es un respaldo y dos brazos, un piano es
	una tapa negra y tres patas. Son dos o tres piezas por objeto y cambian por
	completo lo que el jugador cree estar cargando.

	VIVE EN SHARED porque hay DOS sitios que dibujan mercancía --el muelle del
	almacén (cliente) y el bulto a la espalda (servidor)-- y tenían dos códigos
	distintos: un objeto podía llevar flejes en el suelo y ser un cubo pelado en
	cuanto lo cogías. Con una sola función, lo que ves en el suelo es lo que
	llevas.
]]

local Goods = require(script.Parent.Goods)

local GoodsLook = {}

-- Los tonos de los detalles. Aquí y no repartidos por los `if`, para que cambiar
-- el aspecto de la mercancía sea tocar cuatro líneas y no buscarlas.
local MADERA = Color3.fromRGB(96, 72, 44)
local METAL = Color3.fromRGB(58, 62, 70)
local DORADO = Color3.fromRGB(212, 172, 82)
local NEGRO = Color3.fromRGB(26, 26, 30)
local VERDE = Color3.fromRGB(74, 132, 72)
local PAPEL = Color3.fromRGB(226, 220, 202)

function GoodsLook.forma(objetoId: string?): string
	if objetoId == nil then
		return "cajon"
	end
	local ok, def = pcall(Goods.get, objetoId)
	if not ok or def == nil then
		return "cajon"
	end
	return (def :: any).forma or "cajon"
end

-- Añade los detalles a una pieza ya creada y colocada.
--
-- `soldar` es lo que separa los dos usos: en el muelle las piezas están ancladas
-- y basta con ponerlas en su sitio; a la espalda del jugador tienen que ir
-- soldadas y sin masa, o se quedan flotando donde las dejaste.
function GoodsLook.adornar(base: BasePart, objetoId: string?, soldar: boolean?)
	local lado = base.Size
	local forma = GoodsLook.forma(objetoId)

	local function adorno(nombre: string, tamano: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
		local d = Instance.new("Part")
		d.Name = nombre
		-- Nunca por debajo de un décimo de stud: con los objetos pequeños dibujados
		-- a escala reducida (el bulto de la espalda va a 0,55) una proporción del
		-- 4 % da piezas de medio milímetro que Roblox redondea a cero y desaparecen.
		d.Size = Vector3.new(math.max(tamano.X, 0.1), math.max(tamano.Y, 0.1), math.max(tamano.Z, 0.1))
		d.Color = color
		d.Material = material
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.Massless = true
		d.CFrame = base.CFrame * CFrame.new(offset)
		d.Anchored = base.Anchored
		d.Parent = base
		if soldar then
			local w = Instance.new("WeldConstraint")
			w.Part0 = base
			w.Part1 = d
			w.Parent = d
		end
		return d
	end

	if forma == "cajon" or forma == "baul" then
		-- Flejes cruzados: dos listones y el cubo pasa a ser un cajón.
		adorno(
			"Fleje1",
			Vector3.new(lado.X * 1.02, lado.Y * 0.12, lado.Z * 1.02),
			Vector3.new(0, lado.Y * 0.22, 0),
			MADERA,
			Enum.Material.Wood
		)
		adorno(
			"Fleje2",
			Vector3.new(lado.X * 1.02, lado.Y * 0.12, lado.Z * 1.02),
			Vector3.new(0, -lado.Y * 0.22, 0),
			MADERA,
			Enum.Material.Wood
		)
	elseif forma == "maletin" or forma == "joyero" then
		-- Asa arriba y cierre delante: se lee como maletín al instante.
		adorno(
			"Asa",
			Vector3.new(lado.X * 0.4, lado.Y * 0.22, lado.Z * 0.25),
			Vector3.new(0, lado.Y * 0.6, 0),
			METAL,
			Enum.Material.Metal
		)
		adorno(
			"Cierre",
			Vector3.new(lado.X * 0.9, lado.Y * 0.14, lado.Z * 0.12),
			Vector3.new(0, 0, lado.Z * 0.5),
			METAL,
			Enum.Material.Metal
		)
	elseif forma == "nevera" or forma == "television" then
		-- Refuerzos en las esquinas: la silueta de algo blindado.
		for k, e in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			adorno(
				"Refuerzo" .. k,
				Vector3.new(lado.X * 0.12, lado.Y * 1.02, lado.Z * 0.12),
				Vector3.new(e[1] * lado.X * 0.45, 0, e[2] * lado.Z * 0.45),
				METAL,
				Enum.Material.Metal
			)
		end
	elseif forma == "urna" or forma == "estatua" then
		-- Base y remate dorados: una urna es lo único que no debería parecer una caja.
		adorno(
			"Base",
			Vector3.new(lado.X * 1.25, lado.Y * 0.12, lado.Z * 1.25),
			Vector3.new(0, -lado.Y * 0.5, 0),
			DORADO,
			Enum.Material.Metal
		)
		adorno(
			"Tapa",
			Vector3.new(lado.X * 0.7, lado.Y * 0.18, lado.Z * 0.7),
			Vector3.new(0, lado.Y * 0.6, 0),
			DORADO,
			Enum.Material.Metal
		)
	elseif forma == "barril" then
		-- Tres aros: es todo lo que hace falta para que un cilindro sea un barril.
		for k, altura in { -0.3, 0, 0.3 } do
			adorno(
				"Aro" .. k,
				Vector3.new(lado.X * 1.06, lado.Y * 0.09, lado.Z * 1.06),
				Vector3.new(0, lado.Y * altura, 0),
				METAL,
				Enum.Material.Metal
			)
		end
	elseif forma == "sofa" then
		-- Respaldo y dos brazos. Un sofá visto de lejos es exactamente esa silueta.
		adorno(
			"Respaldo",
			Vector3.new(lado.X, lado.Y * 0.9, lado.Z * 0.25),
			Vector3.new(0, lado.Y * 0.45, -lado.Z * 0.38),
			base.Color,
			base.Material
		)
		adorno(
			"BrazoIzq",
			Vector3.new(lado.X * 0.16, lado.Y * 0.6, lado.Z * 0.9),
			Vector3.new(-lado.X * 0.42, lado.Y * 0.3, 0),
			base.Color,
			base.Material
		)
		adorno(
			"BrazoDer",
			Vector3.new(lado.X * 0.16, lado.Y * 0.6, lado.Z * 0.9),
			Vector3.new(lado.X * 0.42, lado.Y * 0.3, 0),
			base.Color,
			base.Material
		)
	elseif forma == "piano" then
		-- Tapa levantada y patas: nada más se parece a esto.
		adorno(
			"Tapa",
			Vector3.new(lado.X * 0.95, lado.Y * 0.12, lado.Z * 0.8),
			Vector3.new(0, lado.Y * 0.55, 0),
			NEGRO,
			Enum.Material.Wood
		)
		adorno(
			"Teclado",
			Vector3.new(lado.X * 0.85, lado.Y * 0.1, lado.Z * 0.22),
			Vector3.new(0, lado.Y * 0.2, lado.Z * 0.42),
			PAPEL,
			Enum.Material.SmoothPlastic
		)
		for k, e in { -1, 1 } do
			adorno(
				"Pata" .. k,
				Vector3.new(lado.X * 0.1, lado.Y * 0.5, lado.Z * 0.1),
				Vector3.new(e * lado.X * 0.38, -lado.Y * 0.5, lado.Z * 0.3),
				NEGRO,
				Enum.Material.Wood
			)
		end
	elseif forma == "maceta" then
		-- La planta: es lo que la distingue de un cubo marrón.
		adorno(
			"Planta",
			Vector3.new(lado.X * 0.8, lado.Y * 0.7, lado.Z * 0.8),
			Vector3.new(0, lado.Y * 0.6, 0),
			VERDE,
			Enum.Material.Grass
		)
		adorno(
			"Borde",
			Vector3.new(lado.X * 1.12, lado.Y * 0.14, lado.Z * 1.12),
			Vector3.new(0, lado.Y * 0.42, 0),
			MADERA,
			Enum.Material.Slate
		)
	elseif forma == "libro" then
		-- Lomo y cantos: un libro cerrado es un bloque con una cara distinta.
		adorno(
			"Lomo",
			Vector3.new(lado.X * 0.14, lado.Y * 1.02, lado.Z * 1.02),
			Vector3.new(-lado.X * 0.44, 0, 0),
			MADERA,
			Enum.Material.Fabric
		)
		adorno(
			"Hojas",
			Vector3.new(lado.X * 0.8, lado.Y * 0.86, lado.Z * 0.9),
			Vector3.new(lado.X * 0.12, 0, 0),
			PAPEL,
			Enum.Material.SmoothPlastic
		)
	elseif forma == "frasco" then
		-- Tapón y etiqueta.
		adorno(
			"Tapon",
			Vector3.new(lado.X * 0.45, lado.Y * 0.2, lado.Z * 0.45),
			Vector3.new(0, lado.Y * 0.58, 0),
			MADERA,
			Enum.Material.Wood
		)
		adorno(
			"Etiqueta",
			Vector3.new(lado.X * 0.9, lado.Y * 0.35, lado.Z * 0.06),
			Vector3.new(0, 0, lado.Z * 0.5),
			PAPEL,
			Enum.Material.SmoothPlastic
		)
	elseif forma == "sobre" then
		-- La solapa y el lacre: un sobre es plano, y lo que lo cuenta es el sello.
		adorno(
			"Solapa",
			Vector3.new(lado.X * 0.9, lado.Y * 0.5, lado.Z * 0.06),
			Vector3.new(0, lado.Y * 0.2, lado.Z * 0.5),
			PAPEL,
			Enum.Material.SmoothPlastic
		)
		adorno(
			"Lacre",
			Vector3.new(lado.X * 0.22, lado.Y * 0.22, lado.Z * 0.08),
			Vector3.new(0, 0, lado.Z * 0.52),
			Color3.fromRGB(160, 44, 44),
			Enum.Material.Neon
		)
	end
end

return GoodsLook
