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

local Config = require(game.ReplicatedStorage.Shared.Config)
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
	-- EL IMPULSOR, A LA ESPALDA. Es el unico del catalogo que no va debajo ni se monta:
	-- se lleva puesto. El offset en +Z es la espalda -- el frente de Roblox es -Z.
	--
	-- Las dos toberas miran abajo y llevan neon: es lo que hace que desde la calle se
	-- entienda de un vistazo por que ese jugador esta subido a un tejado.
	impulsor = {
		{ tamano = Vector3.new(2.2, 2.6, 1.1), offset = Vector3.new(0, 0.3, 0.95), color = OSCURO },
		{ tamano = Vector3.new(0.8, 1.6, 0.8), offset = Vector3.new(-0.7, -1.1, 1), color = METAL },
		{ tamano = Vector3.new(0.8, 1.6, 0.8), offset = Vector3.new(0.7, -1.1, 1), color = METAL },
		{ tamano = Vector3.new(0.7, 0.25, 0.7), offset = Vector3.new(-0.7, -1.95, 1), color = NEON, neon = true },
		{ tamano = Vector3.new(0.7, 0.25, 0.7), offset = Vector3.new(0.7, -1.95, 1), color = NEON, neon = true },
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
	-- EL CARRO: caja abierta detras, dos ruedas y las varas de tiro. Va en +Z porque
	-- el frente de Roblox es -Z, o sea que esto queda a la espalda -- se tira, no se
	-- conduce, y desde la calle se tiene que leer de un vistazo cual de las dos cosas
	-- es. De ahi las varas: sin ellas es una caja flotando detras de alguien.
	carro = {
		{ tamano = Vector3.new(3.4, 0.35, 4.4), offset = Vector3.new(0, -2.5, 3.8), color = METAL },
		{ tamano = Vector3.new(3.4, 1.8, 0.3), offset = Vector3.new(0, -1.6, 5.9), color = OSCURO },
		{ tamano = Vector3.new(0.3, 1.8, 4.4), offset = Vector3.new(-1.7, -1.6, 3.8), color = OSCURO },
		{ tamano = Vector3.new(0.3, 1.8, 4.4), offset = Vector3.new(1.7, -1.6, 3.8), color = OSCURO },
		{ tamano = Vector3.new(0.35, 1.8, 1.8), offset = Vector3.new(-1.9, -2.5, 3.8), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.35, 1.8, 1.8), offset = Vector3.new(1.9, -2.5, 3.8), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.22, 0.22, 3.4), offset = Vector3.new(-0.9, -1.9, 1.7), color = METAL },
		{ tamano = Vector3.new(0.22, 0.22, 3.4), offset = Vector3.new(0.9, -1.9, 1.7), color = METAL },
	},
	-- EL REMOLQUE: lo mismo pero largo y con cuatro ruedas, que es como se distingue
	-- de lejos. Sube el suelo y baja los laterales -- una plataforma cargada se lee
	-- mejor que una caja cerrada, y ademas es lo que justifica que vaya por la calzada.
	remolque = {
		{ tamano = Vector3.new(4.4, 0.4, 7.2), offset = Vector3.new(0, -2.4, 5.2), color = METAL },
		{ tamano = Vector3.new(4.4, 1.2, 0.35), offset = Vector3.new(0, -1.7, 8.7), color = OSCURO },
		{ tamano = Vector3.new(0.35, 1.2, 7.2), offset = Vector3.new(-2.2, -1.7, 5.2), color = OSCURO },
		{ tamano = Vector3.new(0.35, 1.2, 7.2), offset = Vector3.new(2.2, -1.7, 5.2), color = OSCURO },
		{ tamano = Vector3.new(0.4, 2, 2), offset = Vector3.new(-2.4, -2.4, 3.6), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 2, 2), offset = Vector3.new(2.4, -2.4, 3.6), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 2, 2), offset = Vector3.new(-2.4, -2.4, 6.8), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.4, 2, 2), offset = Vector3.new(2.4, -2.4, 6.8), color = GOMA, rueda = true },
		{ tamano = Vector3.new(0.26, 0.26, 3.6), offset = Vector3.new(-1, -1.9, 1.6), color = METAL },
		{ tamano = Vector3.new(0.26, 0.26, 3.6), offset = Vector3.new(1, -1.9, 1.6), color = METAL },
	},
}

-- En cuáles vas SENTADO. En los otros vas de pie encima (monopatín,
-- patinete), que es como se va de verdad y además no necesita postura ninguna.
local SENTADO: { [string]: boolean } = {
	bicicleta = true,
	moto = true,
	-- El carro y el remolque NO estan: se tiran a pie. Ir sentado encima de algo que
	-- arrastras seria la contradiccion que se acaba de quitar de en medio.
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
-- ¿A ESTE PERSONAJE SE LE PUEDEN MOVER LOS HUESOS A MANO?
--
-- No es una pregunta retorica y la respuesta cambia de jugador a jugador. En este
-- servidor conviven tres clases de esqueleto: el R6 de respaldo que monta
-- `Avatar.luau` (Motor6D clasicos), el R15 de siempre (Motor6D con otros nombres) y
-- el avatar nuevo de Roblox, cuyas articulaciones son `AnimationConstraint` y NO
-- Motor6D -- medido el 22/08 en el avatar real de JJ: quince ataduras y cero
-- Motor6D.
--
-- Los dos primeros se posan (`client/Riders.luau` sabe escribir en los dos: `C0` en
-- uno, `Transform` en el otro). Si algun dia aparece un rig que no tenga ni una cosa
-- ni la otra, esto devuelve false y el personaje se queda ANDANDO encima del
-- monopatin en vez de rigido -- moverse de mas es mucho mejor que no moverse.
local function tieneHuesos(character: Model): boolean
	for _, d in character:GetDescendants() do
		local cadera = d.Name == "Right Hip" or d.Name == "RightHip"
		if cadera and (d:IsA("Motor6D") or d.ClassName == "AnimationConstraint") then
			return true
		end
	end
	return false
end

local function postura(character: Model, montado: boolean, sentado: boolean)
	-- APAGAR `Animate` SOLO SI ALGUIEN VA A PONER UNA POSE EN SU LUGAR.
	--
	-- Esto decia `animate.Disabled = montado` a secas, y ahi esta el fallo que dejaba
	-- al monopatin como una estatua: apagar el script que mueve las extremidades es la
	-- MITAD del trabajo, y la otra mitad --la pose-- no siempre se puede hacer.
	--
	--   · SENTADO: la pose viene de una animacion oficial de Roblox, que funciona en
	--     cualquier rig. Se apaga.
	--   · DE PIE CON HUESOS: la pone `client/Riders.luau` moviendo los Motor6D. Se
	--     apaga.
	--   · DE PIE SIN HUESOS (el avatar nuevo): no hay nada que ponga una pose, asi
	--     que apagarlo deja a un muneco rigido deslizandose por la calle. Se DEJA
	--     ANDANDO -- moverse de mas es infinitamente mejor que no moverse nada, y
	--     encima en un monopatin se lee casi como que va empujando.
	--
	-- Sin esto, el arreglo del monopatin funcionaria en Studio (donde el avatar de
	-- respaldo es R6) y no funcionaria en el juego publicado, que es justo donde se
	-- juega. La clase de fallo que se descubre tarde y mal.
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LuaSourceContainer") then
		animate.Disabled = montado and (sentado or tieneHuesos(character))
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

	-- AQUI SI SE PIDE EL `Torso` DE R6 A PROPOSITO, y no `Rigs.torso`.
	--
	-- Lo cambie a `Rigs.torso` al arreglar la mochila y fue un error: lo de abajo son
	-- los Motor6D "Right Hip"/"Left Hip", que SOLO existen en el R6 clasico. En R15
	-- las caderas cuelgan del `LowerTorso` y se llaman de otra forma, asi que
	-- devolver el `UpperTorso` aqui no arregla nada -- solo quita el `return` que
	-- protegia al R15 de entrar en un camino que no es el suyo.
	--
	-- El comentario de abajo ya lo decia. La leccion es que "buscar el torso" no es
	-- una sola pregunta: la mochila quiere el torso QUE SE ANIMA y esto quiere el
	-- hueso del R6. Mismo nombre, dos cosas.
	local torso = character:FindFirstChild("Torso") :: BasePart?
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
-- LA MALLA DE UN VEHÍCULO, ya escalada y orientada, sin colocar.
--
-- Vive aquí y no en quien la pide porque la cuenta de la escala es delicada y ya
-- se torció una vez: cada autor modela mirando a donde le parece --coche y
-- furgoneta vienen de lado, la bicicleta con el eje Z hacia arriba-- y los
-- ángulos no se deducen de las proporciones, se miden y se guardan en el
-- catálogo. Tener esa cuenta en dos sitios es cómo el escaparate acabaría
-- enseñando una furgoneta aplastada mientras el jugador conduce una normal.
--
-- Devuelve la pieza ANCLADA y su alto real en el mundo (que no es `Size.Y`: en
-- una malla volteada, Size.Y es el ancho). Quien la pida decide dónde ponerla.
function Ride.malla(vehiculoId: string?): (BasePart?, number)
	local modelo = RideCatalog.get(vehiculoId)
	if modelo == nil then
		return nil, 0
	end

	local ok, malla = pcall(function()
		local m = AssetService:CreateMeshPartAsync(modelo.mesh)
		m.Name = "Modelo"
		if modelo.textura then
			m.TextureID = modelo.textura
		end
		if modelo.color then
			m.Color = modelo.color
		end

		-- EL ORDEN IMPORTA: primero el volteo sobre X, después el giro sobre Y. Al
		-- revés, el eje largo del vehículo acaba apuntando al cielo (medido con las
		-- cuatro combinaciones).
		local giro = CFrame.Angles(0, math.rad(modelo.giroY), 0) * CFrame.Angles(math.rad(modelo.giroX or 0), 0, 0)
		local nativo = m.Size
		-- LA ESCALA, limitada por el LARGO Y POR EL ALTO a la vez. Escalar sólo por
		-- el lado mayor infla lo pequeño: una malla casi cúbica estirada hasta medir
		-- 2,6 de largo queda también de 2,6 de alto, por la rodilla de un personaje
		-- que mide cinco. Y el alto se mide DESPUÉS de girar: en una malla volteada
		-- la altura no está en su eje Y.
		local altoNativo = math.abs(giro.RightVector.Y) * nativo.X
			+ math.abs(giro.UpVector.Y) * nativo.Y
			+ math.abs(giro.LookVector.Y) * nativo.Z
		local largoNativo = math.abs(giro.RightVector.Z) * nativo.X
			+ math.abs(giro.UpVector.Z) * nativo.Y
			+ math.abs(giro.LookVector.Z) * nativo.Z
		local porLargo = math.max(modelo.tamano.X, modelo.tamano.Z) / math.max(largoNativo, 0.01)
		local porAlto = modelo.tamano.Y / math.max(altoNativo, 0.01)
		m.Size = nativo * math.min(porLargo, porAlto)

		m.Anchored = true
		m.CanCollide = false
		m.CFrame = giro
		return m
	end)

	if not ok or malla == nil then
		return nil, 0
	end

	local m = malla :: BasePart
	local cf, s3 = m.CFrame, m.Size
	local alto = math.abs(cf.RightVector.Y) * s3.X + math.abs(cf.UpVector.Y) * s3.Y + math.abs(cf.LookVector.Y) * s3.Z
	return m, alto
end

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
	-- Y el ruido, que NO vive en esa carpeta sino en el HumanoidRootPart (tiene que
	-- ser espacial, para que lo oigan los demás). Sin esto, bajarse de la moto
	-- dejaría el motor sonando para siempre, y montar otra añadiría un segundo
	-- motor encima del primero.
	local ruidoViejo = root:FindFirstChild("RuidoVehiculo")
	if ruidoViejo then
		ruidoViejo:Destroy()
	end

	-- A QUÉ ALTURA PISA ESTE PERSONAJE. No es una constante: depende del rig, y en
	-- este juego conviven los dos -- los jugadores van en R15 desde que el place
	-- está publicado, y los ladrones son R6 (hechos de Part, para que se vean
	-- siempre).
	--
	-- LA PRIMERA VERSIÓN USABA HipHeight Y SÓLO VALÍA PARA R15. En R6 esa
	-- propiedad es CERO por diseño --el rig clásico no la usa-- así que la cuenta
	-- daba un metro de más y el vehículo se le quedaba a la altura del pecho a todo
	-- ladrón que llevara uno. Con jugadores R15 no se veía: el fallo estaba
	-- escondido en los PNJ.
	--
	-- Así que no se pregunta por el rig: se mide. El punto más bajo de todas las
	-- piezas del personaje es donde pisa, tenga los huesos que tenga.
	local function cotaDeLosPies(character: Model, root: BasePart): number
		local masBaja = nil
		for _, parte in character:GetDescendants() do
			if parte:IsA("BasePart") and parte.Name ~= "HumanoidRootPart" then
				local base = parte.Position.Y - parte.Size.Y / 2
				if masBaja == nil or base < masBaja then
					masBaja = base
				end
			end
		end
		if masBaja ~= nil then
			return masBaja
		end
		-- Sin piezas que medir (un personaje a medio montar): se cae a la cuenta de
		-- siempre, que al menos no deja el vehículo en el aire.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local altura = if humanoid and humanoid.HipHeight > 0 then humanoid.HipHeight else 2
		return root.Position.Y - (altura + root.Size.Y / 2)
	end

	local forma = if vehiculoId ~= nil then FORMAS[vehiculoId] else nil
	if not forma then
		-- A pie: se devuelve la postura normal antes de salir. Si no, quien se baja
		-- de la moto sigue con las piernas al frente el resto de la partida.
		postura(character, false, false)
		character:SetAttribute("vehiculoDePie", nil)
		return
	end

	local sentado = SENTADO[vehiculoId :: string] == true
	postura(character, true, sentado)

	-- LA BANDERA QUE LEE EL CLIENTE (`Riders.luau`): "este va DE PIE encima de algo".
	--
	-- Aqui abajo solo se apaga el `Animate` y se posa a los que van sentados, asi que
	-- los de pie salian rigidos -- *"va encima de el sin moverse como una estatua"*
	-- (JJ). Animarlos desde aqui serian cinco articulaciones por sesenta fotogramas
	-- de trafico de red que no cambia nada del juego, asi que lo unico que cruza es
	-- este booleano y el dibujo lo hace cada maquina.
	--
	-- Un atributo y no una carpeta con nombre: se replica solo, se lee sin esperar a
	-- que exista, y borrarlo es una linea. La carpeta `VehiculoVisible` sigue siendo
	-- lo que ES el vehiculo; esto es lo que se HACE con el.
	character:SetAttribute("vehiculoDePie", not sentado)

	local carpeta = Instance.new("Folder")
	carpeta.Name = "VehiculoVisible"
	carpeta.Parent = character

	-- EL RUIDO, en el HumanoidRootPart y por tanto ESPACIAL: lo oyen los demás
	-- jugadores, y eso es información de juego -- oír llegar una furgoneta por la
	-- calle de al lado es lo que convierte un encuentro en una decisión.
	--
	-- Va en el servidor, como el modelo y la carga, por el mismo motivo: un ruido
	-- que sólo oye su dueño no avisa a nadie.
	local def = Config.SONIDOS_VEHICULO[vehiculoId :: string]
	if def and root then
		local sonido = Instance.new("Sound")
		sonido.Name = "RuidoVehiculo"
		sonido.SoundId = def.sonido
		sonido.Looped = true
		-- Arranca CALLADO si no tiene motor: RoadService le pone el volumen en la
		-- vuelta siguiente según te muevas o no. Sin esto, subirse a un monopatín
		-- suelta un siseo antes de dar un paso.
		sonido.Volume = if def.motor then def.volumen * 0.3 else 0
		-- El tono ES la escala del juego hecha sonido: cuanto más grave, más
		-- grande. Un mismo motor a 0,72 y a 1,15 son dos vehículos distintos.
		sonido.PlaybackSpeed = def.tono
		-- Se oye a media manzana, no a un barrio entero: con 200 studs de alcance,
		-- diez jugadores en la ciudad serían diez motores sonando siempre.
		sonido.RollOffMaxDistance = 90
		sonido.RollOffMode = Enum.RollOffMode.InverseTapered
		sonido.Parent = root
		sonido:Play()
	end

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
			-- LA ESCALA, limitada por el LARGO Y POR EL ALTO a la vez.
			--
			-- Escalar sólo por el lado mayor infla lo pequeño: los patines (ya
			-- retirados) venían casi cúbicos, y estirarlos hasta medir 2,6 de largo
			-- los dejaba también de 2,6 de ALTO, por la rodilla de un personaje que
			-- mide cinco. El siguiente modelo cúbico que entre tendrá el mismo vicio.
			--
			-- Y el alto se mide DESPUÉS de girar: en una malla volteada (la bicicleta)
			-- la altura no está en su eje Y.
			local giro = CFrame.Angles(0, math.rad(modelo.giroY), 0) * CFrame.Angles(math.rad(modelo.giroX or 0), 0, 0)
			local altoNativo = math.abs(giro.RightVector.Y) * nativo.X
				+ math.abs(giro.UpVector.Y) * nativo.Y
				+ math.abs(giro.LookVector.Y) * nativo.Z
			local largoNativo = math.abs(giro.RightVector.Z) * nativo.X
				+ math.abs(giro.UpVector.Z) * nativo.Y
				+ math.abs(giro.LookVector.Z) * nativo.Z
			local porLargo = math.max(modelo.tamano.X, modelo.tamano.Z) / math.max(largoNativo, 0.01)
			local porAlto = modelo.tamano.Y / math.max(altoNativo, 0.01)
			-- El menor de los dos: así el vehículo nunca sale más alto de lo que dice el
			-- catálogo, que es la medida que se comparó con el personaje.
			local escala = math.min(porLargo, porAlto)
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
