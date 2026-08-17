--!strict
--[[
	Ride.luau — el vehículo que llevas debajo, y que ven los demás.

	EXISTE PARA QUE LA PROGRESIÓN SE VEA. Sin esto, comprar una moto cambia dos
	números en un panel y nada más: el jugador paga 4.500 y sigue siendo el mismo
	muñeco andando. Y para los DEMÁS es todavía peor -- no hay forma de saber si el
	que viene por la calle va a pie o en coche, y eso es exactamente lo que hay que
	poder juzgar en un juego donde alguien puede robarte o perseguirte.

	Se monta en el SERVIDOR, como la carga a la espalda y por el mismo motivo: tiene
	que verlo todo el mundo. Un vehículo dibujado en el cliente de cada uno sería
	una mejora invisible para el resto, que es la mitad de para lo que sirve.

	NO SE CONDUCE. Son piezas soldadas al personaje y sin masa: te mueves igual que
	siempre, sólo que más rápido y con más capacidad. Es una decisión de alcance --
	`DISENO.md` deja los vehículos conducibles fuera-- y también de riesgo: la
	física de Roblox convierte cualquier vehículo real en volcadas, atascos y
	atropellos, y ninguno de esos problemas aporta nada al bucle que estamos
	midiendo.
]]

local Ride = {}

-- Tonos compartidos. Un vehículo se reconoce por su SILUETA, no por su color, así
-- que la paleta es corta a propósito: metal, goma y un acento vivo para lo que
-- tiene motor.
local METAL = Color3.fromRGB(168, 172, 180)
local OSCURO = Color3.fromRGB(48, 50, 58)
local GOMA = Color3.fromRGB(28, 28, 32)
local ACENTO = Color3.fromRGB(220, 96, 60)
local NEON = Color3.fromRGB(120, 220, 255)

type Pieza = {
	tamano: Vector3,
	offset: Vector3,
	color: Color3,
	rueda: boolean?,
	neon: boolean?,
}

-- Cada vehículo, en piezas relativas al HumanoidRootPart. El origen del personaje
-- está a unos 3 studs del suelo en un rig R6, así que todo lo que va "en el suelo"
-- cae sobre -2,6.
local FORMAS: { [string]: { Pieza } } = {
	patines = {
		{ tamano = Vector3.new(1.1, 0.35, 2.2), offset = Vector3.new(-0.65, -2.7, 0), color = METAL },
		{ tamano = Vector3.new(1.1, 0.35, 2.2), offset = Vector3.new(0.65, -2.7, 0), color = METAL },
		{ tamano = Vector3.new(0.35, 0.7, 0.7), offset = Vector3.new(-0.65, -2.95, -0.7), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 0.7, 0.7), offset = Vector3.new(-0.65, -2.95, 0.7), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 0.7, 0.7), offset = Vector3.new(0.65, -2.95, -0.7), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 0.7, 0.7), offset = Vector3.new(0.65, -2.95, 0.7), color = GOMA, rueda = true },
	},
	monopatin = {
		{ tamano = Vector3.new(1.8, 0.3, 4.4), offset = Vector3.new(0, -2.8, 0), color = ACENTO },
		{ tamano = Vector3.new(0.4, 0.8, 0.8), offset = Vector3.new(-0.8, -3.1, -1.5), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 0.8, 0.8), offset = Vector3.new(0.8, -3.1, -1.5), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 0.8, 0.8), offset = Vector3.new(-0.8, -3.1, 1.5), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 0.8, 0.8), offset = Vector3.new(0.8, -3.1, 1.5), color = GOMA, rueda = true },
	},
	patinete = {
		{ tamano = Vector3.new(1.4, 0.3, 4.6), offset = Vector3.new(0, -2.8, 0), color = METAL },
		{ tamano = Vector3.new(0.3, 3.4, 0.3), offset = Vector3.new(0, -1.2, 2.2), color = METAL },
		{ tamano = Vector3.new(2.4, 0.3, 0.3), offset = Vector3.new(0, 0.4, 2.2), color = OSCURO },
		{ tamano = Vector3.new(0.4, 1.1, 1.1), offset = Vector3.new(0, -3, 2.2), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 1.1, 1.1), offset = Vector3.new(0, -3, -2), color = GOMA, rueda = true },
	},
	patinete_electrico = {
		{ tamano = Vector3.new(1.6, 0.4, 5), offset = Vector3.new(0, -2.8, 0), color = OSCURO },
		{ tamano = Vector3.new(1.3, 0.12, 4), offset = Vector3.new(0, -2.58, 0), color = NEON, neon = true },
		{ tamano = Vector3.new(0.35, 3.6, 0.35), offset = Vector3.new(0, -1.1, 2.4), color = OSCURO },
		{ tamano = Vector3.new(2.6, 0.35, 0.35), offset = Vector3.new(0, 0.6, 2.4), color = OSCURO },
		{ tamano = Vector3.new(0.45, 1.3, 1.3), offset = Vector3.new(0, -2.95, 2.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.45, 1.3, 1.3), offset = Vector3.new(0, -2.95, -2.2), color = GOMA, rueda = true },
	},
	bicicleta = {
		{ tamano = Vector3.new(0.3, 0.3, 5), offset = Vector3.new(0, -1.9, 0), color = ACENTO },
		{ tamano = Vector3.new(0.3, 2, 0.3), offset = Vector3.new(0, -2.4, -1.6), color = ACENTO },
		{ tamano = Vector3.new(0.3, 2.6, 0.3), offset = Vector3.new(0, -1.4, 2.2), color = ACENTO },
		{ tamano = Vector3.new(2.4, 0.3, 0.3), offset = Vector3.new(0, 0, 2.2), color = OSCURO },
		{ tamano = Vector3.new(0.35, 2.8, 2.8), offset = Vector3.new(0, -2, 2.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 2.8, 2.8), offset = Vector3.new(0, -2, -2.4), color = GOMA, rueda = true },
	},
	moto = {
		{ tamano = Vector3.new(1.6, 1.4, 5.4), offset = Vector3.new(0, -1.8, 0), color = OSCURO },
		{ tamano = Vector3.new(1.4, 0.8, 1.8), offset = Vector3.new(0, -0.9, -1), color = ACENTO },
		{ tamano = Vector3.new(2.4, 0.35, 0.35), offset = Vector3.new(0, -0.2, 2.2), color = METAL },
		{ tamano = Vector3.new(0.7, 0.7, 0.7), offset = Vector3.new(0, -0.6, 2.7), color = NEON, neon = true },
		{ tamano = Vector3.new(0.9, 3, 3), offset = Vector3.new(0, -1.9, 2.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.9, 3, 3), offset = Vector3.new(0, -1.9, -2.4), color = GOMA, rueda = true },
	},
	coche = {
		{ tamano = Vector3.new(5, 1.6, 9), offset = Vector3.new(0, -2, 0), color = ACENTO },
		{ tamano = Vector3.new(4.4, 1.8, 4.4), offset = Vector3.new(0, -0.4, -0.6), color = ACENTO },
		{ tamano = Vector3.new(4.2, 1.2, 0.3), offset = Vector3.new(0, -0.4, 1.6), color = Color3.fromRGB(60, 74, 92) },
		{ tamano = Vector3.new(1.2, 2.2, 2.2), offset = Vector3.new(-2.4, -2.6, 3), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.2, 2.2, 2.2), offset = Vector3.new(2.4, -2.6, 3), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.2, 2.2, 2.2), offset = Vector3.new(-2.4, -2.6, -3), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.2, 2.2, 2.2), offset = Vector3.new(2.4, -2.6, -3), color = GOMA, rueda = true },
	},
	furgoneta = {
		{ tamano = Vector3.new(5.6, 1.6, 11), offset = Vector3.new(0, -2, 0), color = METAL },
		{ tamano = Vector3.new(5.6, 4.6, 7), offset = Vector3.new(0, 0.6, -2), color = METAL },
		{ tamano = Vector3.new(5.2, 2.6, 3), offset = Vector3.new(0, -0.4, 2.6), color = Color3.fromRGB(96, 116, 156) },
		{ tamano = Vector3.new(4.6, 1.6, 0.3), offset = Vector3.new(0, -0.2, 4.1), color = Color3.fromRGB(60, 74, 92) },
		{ tamano = Vector3.new(1.3, 2.4, 2.4), offset = Vector3.new(-2.7, -2.6, 3.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.3, 2.4, 2.4), offset = Vector3.new(2.7, -2.6, 3.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.3, 2.4, 2.4), offset = Vector3.new(-2.7, -2.6, -3.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(1.3, 2.4, 2.4), offset = Vector3.new(2.7, -2.6, -3.4), color = GOMA, rueda = true },
	},
}

-- Monta (o desmonta) el vehículo de un personaje. `vehiculoId` nil o "a_pie"
-- deja al personaje limpio.
function Ride.montar(character: Model?, vehiculoId: string?)
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local viejo = character:FindFirstChild("VehiculoVisible")
	if viejo then
		viejo:Destroy()
	end

	local forma = if vehiculoId ~= nil then FORMAS[vehiculoId] else nil
	if not forma then
		return
	end

	local carpeta = Instance.new("Folder")
	carpeta.Name = "VehiculoVisible"
	carpeta.Parent = character

	for i, pieza in forma do
		local p = Instance.new("Part")
		p.Name = "Pieza" .. i
		p.Size = pieza.tamano
		p.Color = pieza.color
		p.Material = if pieza.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Anchored = false
		-- Sin colisión: el vehículo es un dibujo, no un cuerpo. Con colisión, un
		-- coche de 9 studs empotraría al jugador en cada esquina de la ciudad y
		-- convertiría la mejora que acaba de pagar en un castigo.
		p.CanCollide = false
		-- Y sin masa, por lo mismo que la carga: el coste de llevar cosas se cobra
		-- en la VELOCIDAD, que es una regla del juego, no por la puerta de atrás en
		-- la física.
		p.Massless = true
		if pieza.rueda then
			-- SIN rotar. El eje de un Part cilíndrico ya va a lo largo de su X local,
			-- que es justo el eje sobre el que gira una rueda en un vehículo que mira
			-- hacia adelante. Girarla 90° la dejaría tumbada como un plato -- error
			-- que este proyecto ya cometió con la furgoneta del escaparate.
			p.Shape = Enum.PartType.Cylinder
		end
		-- Z NEGADO al aplicarlo. En las tablas de arriba, Z positivo significa
		-- "hacia delante" porque es como se piensa un vehículo; en Roblox el frente
		-- de un CFrame es -Z. Sin esta traducción, el manillar y el faro salen
		-- montados a la espalda del conductor -- que es exactamente como salió la
		-- primera versión de la moto.
		p.CFrame = root.CFrame * CFrame.new(pieza.offset.X, pieza.offset.Y, -pieza.offset.Z)
		p.Parent = carpeta

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end
end

-- ¿Hay dibujo para este vehículo? Lo usa PatrolService para no intentar montar
-- algo que no existe.
function Ride.existe(vehiculoId: string?): boolean
	return vehiculoId ~= nil and FORMAS[vehiculoId] ~= nil
end

return Ride
