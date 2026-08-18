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

local AssetService = game:GetService("AssetService")

local RideCatalog = require(game.ReplicatedStorage.Shared.RideCatalog)

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
		{ tamano = Vector3.new(0.3, 0.3, 5), offset = Vector3.new(0, -2.3, 0), color = ACENTO },
		{ tamano = Vector3.new(0.3, 2, 0.3), offset = Vector3.new(0, -2.4, -1.6), color = ACENTO },
		{ tamano = Vector3.new(0.3, 2.6, 0.3), offset = Vector3.new(0, -1.4, 2.2), color = ACENTO },
		{ tamano = Vector3.new(2.4, 0.3, 0.3), offset = Vector3.new(0, 0, 2.2), color = OSCURO },
		{ tamano = Vector3.new(0.35, 2.8, 2.8), offset = Vector3.new(0, -2, 2.4), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 2.8, 2.8), offset = Vector3.new(0, -2, -2.4), color = GOMA, rueda = true },
	},
	moto = {
		{ tamano = Vector3.new(1.6, 1.4, 5.4), offset = Vector3.new(0, -2.3, 0), color = OSCURO },
		{ tamano = Vector3.new(1.4, 0.8, 1.8), offset = Vector3.new(0, -1.5, -1), color = ACENTO },
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

-- En cuáles vas SENTADO. En los otros vas de pie encima (patines, monopatín,
-- patinete), que es como se va de verdad y además no necesita postura ninguna.
local SENTADO: { [string]: boolean } = {
	bicicleta = true,
	moto = true,
	coche = true,
	furgoneta = true,
}

-- La postura. Sin esto el personaje va MOVIENDO LAS PIERNAS encima de la moto,
-- que fue lo primero que saltó al verlo: "aunque voy en moto voy andando, es muy
-- raro". Y lo es -- rompe la ilusión más que no tener vehículo, porque el ojo
-- perdona un dibujo simple pero no una contradicción.
--
-- Se resuelve por las dos puntas: se apaga el script `Animate` (el que mueve las
-- extremidades al caminar, y que Roblox mete en cada personaje) y se coloca la
-- pose a mano moviendo los Motor6D de las caderas. Sin apagar Animate, la
-- animación pisaría la pose cuatro veces por segundo y las piernas temblarían.
--
-- No se usa un `Seat` de Roblox, que sería lo idiomático, por lo mismo que el
-- vehículo no tiene colisión: sentarse de verdad entrega el control del personaje
-- a la física, y ahí empiezan las volcadas, los atascos y el "me he quedado
-- pegado al asiento". Aquí el jugador sigue moviéndose exactamente igual que
-- siempre; lo único que cambia es cómo se le ve.
local function postura(character: Model, montado: boolean, sentado: boolean)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LuaSourceContainer") then
		animate.Disabled = montado
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and montado then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			-- Las que ya estuvieran sonando no se paran solas al desactivar el
			-- script: seguirían hasta el final del ciclo, con las piernas a medio
			-- paso congeladas en cuanto termine.
			for _, pista in animator:GetPlayingAnimationTracks() do
				pista:Stop(0)
			end
		end
	end

	-- LA POSE DE SENTADO, por animación y no por huesos.
	--
	-- Posar los Motor6D a mano fue el primer intento y NO FUNCIONA de forma fiable:
	-- depende del rig. Medido en este mismo juego -- un jugador con avatar moderno
	-- viene en R15 y sus articulaciones no son Motor6D sino AnimationConstraint
	-- (cero Motor6D en todo el personaje), mientras que el avatar de respaldo que
	-- monta Avatar.luau cuando no hay mallas sí es R6 clásico. Dos rigs distintos en
	-- el mismo servidor, y el código que posa huesos sólo vale para uno.
	--
	-- Las animaciones oficiales de Roblox valen para los dos y son lo que la
	-- plataforma espera. Si el asset no carga --puede pasar sin publicar el place--
	-- se queda simplemente rígido, que ya es infinitamente mejor que ir moviendo
	-- las piernas encima de una moto.
	if humanoid and montado and sentado then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			pcall(function()
				local anim = Instance.new("Animation")
				anim.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R6
					then "rbxassetid://178130996"
					else "rbxassetid://2506281703"
				local pista = animator:LoadAnimation(anim)
				pista.Looped = true
				pista.Priority = Enum.AnimationPriority.Action4
				pista:Play(0.15)
			end)
		end
	end

	local torso = character:FindFirstChild("Torso")
	if not torso then
		-- R15 u otro rig: la pose ya la ha puesto la animación de arriba. Los
		-- Motor6D de abajo son el camino del R6 clásico, que no tiene "Torso".
		return
	end

	for _, lado in { "Right", "Left" } do
		local cadera = torso:FindFirstChild(lado .. " Hip")
		if cadera and cadera:IsA("Motor6D") then
			-- Se posa con C0, NO con CurrentAngle. CurrentAngle viene de los `Motor`
			-- clásicos y en un Motor6D no hace absolutamente nada: la primera versión
			-- lo usaba, la prueba dijo "cadera a 0 grados" y el personaje seguía
			-- sentado en el aire con las piernas rectas.
			--
			-- El C0 de fábrica se guarda la primera vez en un atributo de la propia
			-- articulación: sin él, montar y desmontar dos veces iría acumulando
			-- rotaciones hasta dejar al jugador hecho un nudo.
			local base = cadera:GetAttribute("c0Original")
			if typeof(base) ~= "CFrame" then
				base = cadera.C0
				cadera:SetAttribute("c0Original", base)
			end

			if montado and sentado then
				-- Piernas al frente. El giro va sobre el eje Y local porque el C0 de la
				-- cadera en R6 ya viene rotado 90° en Y, así que lo que aquí parece
				-- "girar de lado" es en realidad doblar hacia delante.
				local signo = if lado == "Right" then -1 else 1
				cadera.C0 = (base :: CFrame) * CFrame.Angles(0, 0, math.rad(70) * signo)
			else
				cadera.C0 = base :: CFrame
			end
		end
	end
end

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

	-- A QUÉ ALTURA PISA ESTE PERSONAJE. No es una constante: depende del rig, y el
	-- juego ha vivido con los dos -- R6 mientras el place no estaba publicado (los
	-- avatares R15 son mallas y no se descargaban) y R15 en cuanto se publicó.
	--
	-- Los offsets del catálogo se calibraron a ojo sobre R6 y el resultado se vio en
	-- cuanto hubo avatar de verdad: "parece que la moto no va por encima del terreno"
	-- (JJ). Medido: entre 0,40 y 0,60 studs ENTERRADOS, los cinco vehículos probados.
	--
	-- Así que la altura deja de ser un número escrito a mano y pasa a ser una cuenta:
	-- la base del vehículo se apoya donde pisa el personaje, sea cual sea su rig.
	local function cotaDeLosPies(character: Model, root: BasePart): number
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local altura = if humanoid then humanoid.HipHeight else 2
		return root.Position.Y - (altura + root.Size.Y / 2)
	end

	local forma = if vehiculoId ~= nil then FORMAS[vehiculoId] else nil
	if not forma then
		-- A pie: se devuelve la postura normal antes de salir. Si no, quien se baja
		-- de la moto sigue con las piernas al frente el resto de la partida.
		postura(character, false, false)
		return
	end

	postura(character, true, SENTADO[vehiculoId :: string] == true)

	local carpeta = Instance.new("Folder")
	carpeta.Name = "VehiculoVisible"
	carpeta.Parent = character

	-- PRIMERO EL MODELO 3D, si hay uno para este vehículo y la sesión puede
	-- descargarlo. Las piezas de abajo son el respaldo, no la primera opción: una
	-- moto de verdad se lee mejor que seis bloques por muy bien colocados que
	-- estén.
	--
	-- Y si falla, no pasa nada y no se avisa a nadie: se montan las piezas y el
	-- juego sigue siendo el mismo. Sin el place publicado NINGUNA malla se
	-- descarga, así que este camino se cae entero de forma rutinaria -- por eso el
	-- respaldo no es una red de seguridad teórica sino el modo normal en Studio.
	local modelo = RideCatalog.get(vehiculoId)
	if modelo then
		local ok, malla = pcall(function()
			local m = AssetService:CreateMeshPartAsync(modelo.mesh)
			m.Name = "Modelo"
			if modelo.textura then
				m.TextureID = modelo.textura
			end
			if modelo.color then
				m.Color = modelo.color
			end
			-- CÓMO SE ORIENTA Y SE ESCALA UNA MALLA AJENA, que es donde se torció
			-- todo. Cada autor modela mirando a donde le parece y con el eje que le
			-- parece: medido sobre el catálogo, coche y furgoneta vienen de lado y
			-- con el morro al revés, y la bicicleta además viene con el eje Z hacia
			-- arriba. Con un único `giroY = 0` para todas, el resultado fue el que
			-- vio JJ: "la bicicleta sale tumbada" y "el personaje mira hacia delante
			-- y el coche hacia atrás".
			--
			-- Los ángulos NO se deducen: se miden una vez por modelo y se guardan en
			-- el catálogo. Se intentó deducirlos de las proporciones y no funciona --
			-- un coche es más ancho que alto y una bici al revés, así que no hay
			-- regla que distinga "de lado" de "tumbado" sin mirarlo.
			--
			-- EL ORDEN IMPORTA: primero el volteo sobre X, después el giro sobre Y.
			-- Al revés, el eje largo del vehículo acaba apuntando al cielo (medido
			-- con las cuatro combinaciones).
			--
			-- La ESCALA sí se calcula: proporcional al lado mayor, para que el
			-- vehículo mida de largo lo que pide el catálogo sin deformarse. Forzar
			-- los tres ejes a la vez es lo que aplastaba la furgoneta.
			local nativo = m.Size
			local escala = math.max(modelo.tamano.X, modelo.tamano.Z) / math.max(nativo.X, nativo.Y, nativo.Z, 0.01)
			m.Size = nativo * escala
			m.Anchored = false
			m.CanCollide = false
			m.Massless = true
			m.CFrame = root.CFrame
				* CFrame.new(modelo.offset.X, modelo.offset.Y, -modelo.offset.Z)
				* CFrame.Angles(0, math.rad(modelo.giroY), 0)
				* CFrame.Angles(math.rad(modelo.giroX or 0), 0, 0)
			-- Y APOYADO: se corrige la altura para que la base del vehículo caiga
			-- justo donde pisa el personaje. El offset del catálogo sigue mandando
			-- en X y en Z --dónde queda respecto al cuerpo es una decisión de
			-- diseño-- pero la altura es una consecuencia del rig, no una opinión.
			-- El alto REAL en el mundo, no `Size.Y`: en una malla volteada, Size.Y es
			-- el ancho. Se proyectan los tres ejes de la pieza sobre la vertical.
			local cf, s3 = m.CFrame, m.Size
			local alto = math.abs(cf.RightVector.Y) * s3.X
				+ math.abs(cf.UpVector.Y) * s3.Y
				+ math.abs(cf.LookVector.Y) * s3.Z
			local base = m.Position.Y - alto / 2
			m.CFrame = m.CFrame + Vector3.new(0, cotaDeLosPies(character, root) - base, 0)
			m.Parent = carpeta

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = m
			weld.Parent = m
			return m
		end)
		if ok and malla then
			return -- con el modelo puesto, las piezas sobran
		end
	end

	local montadas: { BasePart } = {}
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
		table.insert(montadas, p)
	end

	-- Y el conjunto, apoyado en el suelo igual que la malla. Se hace DESPUÉS de
	-- colocarlas todas y ANTES de soldarlas: un WeldConstraint congela la posición
	-- relativa en el instante en que se crea, así que mover una pieza ya soldada no
	-- movería nada.
	local masBaja = math.huge
	for _, p in montadas do
		masBaja = math.min(masBaja, p.Position.Y - p.Size.Y / 2)
	end
	local ajuste = if masBaja < math.huge then cotaDeLosPies(character, root) - masBaja else 0
	for _, p in montadas do
		p.CFrame = p.CFrame + Vector3.new(0, ajuste, 0)
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
