--!strict
--[[
	Riders.luau — que quien va en tabla CONDUZCA, en vez de posar encima.

	POR QUE EXISTE, con las palabras exactas: *"la fisica de conducir el monopatin es
	lamentable, va encima de el sin moverse como una estatua"* (JJ). Y "estatua" no es
	una exageracion: es el diagnostico literal.

	LA CAUSA, en `Ride.postura`: al montar CUALQUIER vehiculo se desactiva el script
	`Animate` --el que Roblox mete en cada personaje para mover las extremidades-- y
	despues se coloca una pose a mano SOLO para los vehiculos en los que se va
	sentado (moto, bici, coche, furgoneta). Los de pie --monopatin, patinete-- se
	quedaron en tierra de nadie: sin el script que los animaba y sin pose que lo
	sustituyera. O sea rigidos en posicion de reposo, deslizandose por la calle.

	Es el mismo fallo que tenian las patrullas y por el mismo motivo: apagar algo es
	la mitad del trabajo. El comentario de `Ride` decia *"en los otros vas de pie
	encima, que es como se va de verdad y ademas no necesita postura ninguna"*, y ahi
	esta el error de razonamiento -- ir de pie no necesita una pose DISTINTA, pero
	sigue necesitando UNA.

	QUE SE DIBUJA AQUI, por orden de lo que aporta:

	  · LA POSTURA. Un pie delante y otro detras, el cuerpo abierto hacia el lado.
	    Es lo que hace que la silueta diga "va en tabla" hasta en una captura fija.
	  · LA PATADA. Cada segundo y pico la pierna de atras empuja contra el suelo. Es
	    el gesto que nadie confunde con otro, y lo unico que convierte deslizarse en
	    avanzar por tu propio pie.
	  · EL BALANCEO EN CURVA. El cuerpo se inclina hacia dentro segun lo que esta
	    girando. Es lo que se siente como "fisica" sin que haya fisica ninguna
	    debajo: el ojo lee inercia donde solo hay una interpolacion.

	VA EN EL CLIENTE, igual que `Patrullas` y por lo mismo: mover cinco
	articulaciones a sesenta por segundo desde el servidor serian cientos de
	actualizaciones de red que no cambian NADA del juego. Es dibujo, y el dibujo es
	de cada maquina -- y como cada cliente anima a todos los que ve, los demas
	jugadores tambien te ven patinar.

	Y SIN ANIMACIONES OFICIALES. Serian dos lineas y no cargan mientras el place no
	este publicado: la trampa de los meshes y el DataStore, ya pagada tres veces
	aqui. Los Motor6D son piezas, y las piezas siempre funcionan.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Pose = require(game.ReplicatedStorage.Shared.Pose)

local Riders = {}

-- Los ejes y la traduccion de marcos viven en `shared/Pose.luau`, con su prueba.
--
-- POR QUE NO SE ESCRIBEN AQUI. En un R6 las caderas traen el C0 girado un cuarto de
-- vuelta en Y --asi que "doblar hacia delante" es girar sobre su Z local-- y el lado
-- izquierdo viene ademas espejado, de modo que el mismo numero significa lo contrario
-- en cada pierna. Eso costo una tarde en `Patrullas` (los signos alternados, que es
-- lo logico sobre el papel, daban las dos piernas a la vez) y estuvo a punto de
-- costar otra aqui: la primera version de este fichero tenia `ADELANTE = -1` escrito
-- a ojo, y con ese signo el patinador habria patinado de espaldas.
--
-- Lo canto la cuenta, no Studio: con el eje pedido en el marco del torso, un angulo
-- de +30 grados desplaza el pie -0,75 en Z, y en Roblox -Z es el frente. Ahora esa
-- medicion es una prueba pura que corre en cada `verificar.ps1`.
local DERECHA = Pose.DERECHA
local ARRIBA = Pose.ARRIBA
local FRENTE = Pose.FRENTE
local ADELANTE = Pose.ADELANTE

-- LA POSTURA, en grados, y los numeros salen de MEDIR sobre el avatar de verdad --
-- no de lo que parece razonable escribiendo.
--
-- LO QUE HACE QUE SE LEA COMO UN MONOPATIN ES IR DE LADO. La primera version separaba
-- los pies doblando las caderas adelante y atras, y medido dio 0,41 studs sobre una
-- tabla de 4,4 de largo: el jugador se veia de pie con los pies juntos, o sea igual
-- que andando. Subir el angulo no arreglaba gran cosa (34 grados daban 1,18 y ya se
-- veia forzado).
--
-- Un skater no doble las caderas: gira el CUERPO ENTERO. Girando la raiz 55 grados y
-- abriendo las piernas de lado, los pies quedan a 1,67 studs A LO LARGO de la tabla y
-- a 0,39 a lo ancho -- o sea en linea sobre ella, que es exactamente como se va. Y
-- sale mas barato: un giro grande dice mas que cuatro pequenos.
--
-- El torso CONTRAGIRA la mitad: de lado del todo el jugador iria mirando a la acera,
-- y hay que mirar hacia donde se va.
local CUERPO_ABIERTO = 55
local TORSO_CONTRA = 0.45
local CUERPO_AGACHADO = 8
-- Y las piernas, abiertas de lado sobre la tabla. Poco adelante y atras: con el
-- cuerpo ya girado, la separacion sale sola.
local PIE_DELANTERO = 14
local PIE_TRASERO = -14
local PIERNA_ABIERTA = 16
-- Los brazos, abiertos para equilibrar. Poco: un patinador con los brazos en cruz
-- parece que se cae, no que va.
local BRAZO_ABIERTO = 26
local BRAZO_ADELANTE = 14

-- LA PATADA: cada cuanto empuja y cuanto dura el gesto.
--
-- Espaciado y no un pataleo. A 1,25 s se lee como impulso --das un pie, ruedas,
-- vuelves a dar-- y por debajo de 0,8 parece que corre encima de la tabla, que es
-- justo el defecto que esto viene a arreglar.
local PATADA_CADA = 1.25
local PATADA_DURA = 0.42
-- Lo que baja la pierna al empujar, sumado a su angulo de reposo.
local PATADA_ARCO = 42

-- EL BALANCEO EN CURVA: cuanto se inclina como maximo, y a que velocidad de giro
-- llega a ese maximo. Los 2,2 rad/s son un viraje decidido; girar despacio inclina
-- poco, que es lo que hace que la inclinacion signifique algo.
local BALANCEO_MAX = 16
local GIRO_LLENO = 2.2

-- A partir de que velocidad se considera que rueda. Parado no se patea ni se
-- inclina: un patinador quieto que sigue empujando es lo mismo que un ladron
-- balanceandose sin avanzar -- se lee como roto.
local RODANDO = 3

-- Hasta donde se anima. Mas lejos no se distingue una pierna de otra.
local CERCA = 400

-- UNA ARTICULACION, SEA DEL RIG QUE SEA. En este servidor conviven dos formas de
-- tener esqueleto y no se parecen en nada:
--
--   · Motor6D (R6 y R15 clasico): la pose se escribe en `C0`, SOBRE el C0 de
--     fabrica, que hay que guardar para no acumular giros.
--   · AnimationConstraint (el avatar moderno de Roblox): no hay C0 que valga; se
--     escribe `Transform`, que YA es la desviacion respecto al reposo del rig. La
--     base, por tanto, es la identidad.
--
-- Medido el 22/08 en el avatar real de JJ: quince `AnimationConstraint` y CERO
-- Motor6D. O sea que sin esta rama, el arreglo del monopatin funcionaba en Studio
-- --donde el avatar de respaldo es R6-- y no funcionaba en el juego publicado, que
-- es donde se juega. La clase de fallo que se descubre tarde y mal.
type Junta = {
	motor: Motor6D?,
	atadura: any?,
	base: CFrame,
}

type Patinador = {
	personaje: Model,
	raiz: BasePart,
	caderaD: Junta?,
	caderaI: Junta?,
	hombroD: Junta?,
	hombroI: Junta?,
	tronco: Junta?,
	-- El reloj de la patada, SUYO: dos patinadores en la misma calle empujando a la
	-- vez se leen como una animacion en bucle, no como dos personas.
	fase: number,
	-- El rumbo de la vuelta anterior, para saber cuanto esta girando. Se guarda el
	-- vector y no el angulo: restar angulos cerca de 180 grados da un salto de una
	-- vuelta entera, y el patinador se tira al suelo de golpe.
	rumbo: Vector3,
	balanceo: number,
	-- Cuando toca volver a mirar si hay animaciones sonando. Ver `callarAnimaciones`.
	revision: number,
}

local patinadores: { [Model]: Patinador } = {}

-- La articulacion, se llame como se llame. Los dos rigs conviven en este juego --el
-- avatar de respaldo es R6 y un jugador con el place publicado viene en R15-- y los
-- nombres cambian: "Right Hip" con espacio en el clasico, "RightHip" pegado en el
-- moderno, y el tronco es "RootJoint" en uno y "Root" en el otro.
local function junta(personaje: Model, nombres: { string }): Junta?
	local function llamada(inst: Instance): boolean
		for _, nombre in nombres do
			if inst.Name == nombre then
				return true
			end
		end
		return false
	end
	for _, hijo in personaje:GetDescendants() do
		if hijo:IsA("Motor6D") and llamada(hijo) then
			-- EL C0 DE FABRICA, guardado antes de tocar nada. La pose se aplica siempre
			-- sobre el, nunca sobre el ultimo valor: acumular sobre lo ya girado es como
			-- una pierna acaba dando la vuelta entera en diez segundos.
			return { motor = hijo, atadura = nil, base = hijo.C0 }
		end
		if hijo.ClassName == "AnimationConstraint" and llamada(hijo) then
			-- Aqui la base es la IDENTIDAD: `Transform` no es la postura absoluta de la
			-- junta sino lo que se desvia del reposo del rig, asi que escribir la
			-- rotacion a secas es exactamente lo que se quiere.
			return { motor = nil, atadura = hijo, base = CFrame.identity }
		end
	end
	return nil
end

local function adoptar(personaje: Model): Patinador?
	local raiz = personaje:FindFirstChild("HumanoidRootPart")
	if raiz == nil or not raiz:IsA("BasePart") then
		return nil
	end

	local p: Patinador = {
		personaje = personaje,
		raiz = raiz,
		caderaD = junta(personaje, { "Right Hip", "RightHip" }),
		caderaI = junta(personaje, { "Left Hip", "LeftHip" }),
		hombroD = junta(personaje, { "Right Shoulder", "RightShoulder" }),
		hombroI = junta(personaje, { "Left Shoulder", "LeftShoulder" }),
		tronco = junta(personaje, { "RootJoint", "Root" }),
		-- El torso alto: `Waist` en R15, y en R6 no existe -- ahi el contragiro se
		-- hace con el cuello, que es lo unico que hay por encima de la cintura.
		torso = junta(personaje, { "Waist", "Neck" }),
		fase = 0,
		rumbo = raiz.CFrame.LookVector,
		balanceo = 0,
		revision = 0,
	}

	-- Sin una sola articulacion no hay nada que animar: un rig con articulaciones
	-- por restriccion (el avatar nuevo de Roblox) no se posa asi, y forzarlo seria
	-- escribir en propiedades que no hacen nada.
	if p.caderaD == nil and p.caderaI == nil and p.tronco == nil then
		return nil
	end

	return p
end

-- Lo que hay escrito ahora mismo en la junta, y como se escribe. Es lo unico que
-- cambia entre los dos rigs; la pose de arriba no se entera de cual es cual.
local function leer(j: Junta): CFrame
	if j.motor then
		return j.motor.C0
	end
	return j.atadura.Transform
end

local function escribir(j: Junta, cf: CFrame)
	if j.motor then
		j.motor.C0 = cf
	else
		j.atadura.Transform = cf
	end
end

-- Lleva una junta a su pose, persiguiendola en vez de saltando: el `Lerp` es lo que
-- convierte un cambio de postura en un gesto.
local function posar(j: Junta?, giro: (CFrame) -> CFrame, suave: number)
	if j == nil then
		return
	end
	escribir(j, leer(j):Lerp(j.base * giro(j.base), suave))
end

-- CALLAR LAS ANIMACIONES QUE PISAN LA POSE, y esto es lo que separaba "el codigo
-- corre" de "se ve".
--
-- `Ride.postura` apaga el script `Animate` y para las pistas... EN EL SERVIDOR. Y el
-- `Animator` de un jugador vive en SU cliente: las pistas que estaban sonando ahi
-- siguen sonando, escribiendo en las mismas articulaciones cada fotograma. El
-- resultado es una pelea que se pierde -- nosotros escribimos, el animador
-- sobrescribe, y el cuerpo no se mueve.
--
-- Medido el 22/08 con el monopatin puesto: dos pistas de prioridad `Core` sonando y
-- los pies a 0,14 studs uno de otro (o sea juntos, como andando). Parandolas a mano,
-- 0,82 al instante -- con la MISMA pose, que ya se estaba escribiendo.
--
-- Se revisa cada poco en vez de una sola vez al montar: el personaje puede recibir
-- una pista nueva --al aterrizar de un salto, por ejemplo-- y una sola pasada al
-- principio dejaria la pose muerta a partir de ahi.
local REVISAR_CADA = 0.4

local function callarAnimaciones(p: Patinador)
	local humanoid = p.personaje:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	for _, pista in animator:GetPlayingAnimationTracks() do
		pista:Stop(0)
	end
end

local function soltar(p: Patinador)
	for _, j in { p.caderaD, p.caderaI, p.hombroD, p.hombroI, p.tronco, p.torso } do
		if j and (if j.motor then j.motor.Parent ~= nil else j.atadura.Parent ~= nil) then
			escribir(j, j.base)
		end
	end
end

local function animar(p: Patinador, delta: number, dondeEstoy: Vector3?)
	if p.personaje.Parent == nil then
		patinadores[p.personaje] = nil
		return
	end
	-- EL ATRIBUTO SE MIRA CADA VUELTA y no se escucha su cambio: bajarse del
	-- monopatin tiene que devolver el cuerpo a su sitio, y un
	-- `GetAttributeChangedSignal` por personaje son conexiones que hay que acordarse
	-- de soltar cuando el personaje muere -- y aqui muere a menudo.
	--
	-- Y `nil` NO ES LO MISMO QUE `false`, que es un fallo que estuvo escrito:
	--
	--   · nil   -> va A PIE. Hay que devolver las articulaciones a su sitio, o se
	--              queda andando por la calle en postura de tabla.
	--   · false -> se ha subido a algo en lo que se va SENTADO. Ahi la pose la pone
	--              `Ride.postura` en el servidor --piernas al frente-- y restaurar
	--              seria pisarsela: bajarse del monopatin para subirse a la moto
	--              dejaba al jugador con las piernas rectas sobre el asiento, que es
	--              exactamente la queja que abrio todo esto ("aunque voy en moto voy
	--              andando, es muy raro"). El cliente solo deshace lo que hizo el
	--              cliente.
	local bandera = p.personaje:GetAttribute("vehiculoDePie")
	if bandera ~= true then
		if bandera == nil then
			soltar(p)
		end
		patinadores[p.personaje] = nil
		return
	end
	-- Y si la raiz se ha ido --el personaje muriendo a mitad de fotograma-- se suelta
	-- sin tocarla: leerle la posicion lanzaria, y el pcall de arriba se llevaria por
	-- delante la animacion de todos los demas ese fotograma.
	if p.raiz.Parent == nil then
		patinadores[p.personaje] = nil
		return
	end
	if dondeEstoy and (p.raiz.Position - dondeEstoy).Magnitude > CERCA then
		return
	end

	local cf = p.raiz.CFrame
	local velocidad = Vector3.new(p.raiz.AssemblyLinearVelocity.X, 0, p.raiz.AssemblyLinearVelocity.Z).Magnitude
	local rodando = velocidad > RODANDO

	-- CUANTO ESTA GIRANDO, en radianes por segundo. Sale del rumbo de la vuelta
	-- anterior contra el de ahora, con el signo del producto vectorial vertical:
	-- positivo girando hacia su derecha.
	local ahora = cf.LookVector
	local giro = 0
	if delta > 0.0001 then
		local seno = p.rumbo.X * ahora.Z - p.rumbo.Z * ahora.X
		local coseno = math.clamp(p.rumbo:Dot(ahora), -1, 1)
		giro = math.atan2(seno, coseno) / delta
	end
	p.rumbo = ahora

	-- El balanceo PERSIGUE al giro en vez de copiarlo. Copiarlo lo dejaria pegado al
	-- volantazo --el personaje gira en un fotograma-- y se veria un tiron lateral;
	-- persiguiendolo, entra y sale como entraria un cuerpo con inercia.
	local objetivo = if rodando then math.clamp(giro / GIRO_LLENO, -1, 1) * BALANCEO_MAX else 0
	p.balanceo += (objetivo - p.balanceo) * math.min(1, delta * 6)

	-- LA PATADA, solo mientras rueda. El reloj sigue corriendo parado a proposito:
	-- asi al arrancar no empieza siempre por el mismo punto del gesto.
	p.fase += delta
	local empuje = 0
	if rodando then
		local t = p.fase % PATADA_CADA
		if t < PATADA_DURA then
			-- Ida y vuelta en un solo seno: baja al empujar y se recoge, sin el salto
			-- que dejaria una rampa lineal al reiniciarse.
			empuje = math.sin((t / PATADA_DURA) * math.pi)
		end
	end

	p.revision -= delta
	if p.revision <= 0 then
		p.revision = REVISAR_CADA
		callarAnimaciones(p)
	end

	local suave = math.min(1, delta * 12)

	-- LA RAIZ: el cuerpo entero girado sobre la tabla. Es la pieza que hace que esto
	-- se lea como un monopatin y no como alguien de pie; el resto son matices.
	--
	-- El balanceo de las curvas va aqui tambien: inclinar el cuerpo entero hacia
	-- dentro es lo que se siente como inercia. Y NO mueve la camara -- la camara
	-- sigue al HumanoidRootPart, que no gira con esto.
	posar(p.tronco, function(base)
		return Pose.enTorso(base, ARRIBA, CUERPO_ABIERTO) * Pose.enTorso(base, FRENTE, p.balanceo)
	end, suave)

	-- EL TORSO ALTO CONTRAGIRA y se agacha con el empuje: de lado del todo se iria
	-- mirando a la acera, y hay que mirar hacia donde se va.
	local agacha = (CUERPO_AGACHADO + empuje * 5) * ADELANTE
	posar(p.torso, function(base)
		return Pose.enTorso(base, ARRIBA, -CUERPO_ABIERTO * TORSO_CONTRA) * Pose.enTorso(base, DERECHA, agacha)
	end, suave)

	-- LAS PIERNAS: abiertas de lado sobre la tabla, y la de atras es la que empuja.
	posar(p.caderaD, function(base)
		return Pose.enTorso(base, DERECHA, PIE_DELANTERO * ADELANTE) * Pose.enTorso(base, FRENTE, -PIERNA_ABIERTA)
	end, suave)
	local trasera = (PIE_TRASERO - empuje * PATADA_ARCO) * ADELANTE
	posar(p.caderaI, function(base)
		return Pose.enTorso(base, DERECHA, trasera) * Pose.enTorso(base, FRENTE, PIERNA_ABIERTA)
	end, suave)

	-- LOS BRAZOS, abiertos y contrapesando el balanceo: el de fuera de la curva sube
	-- y el de dentro baja. Es como se equilibra cualquiera, y en pantalla es lo que
	-- remata la sensacion de peso.
	local contrapeso = p.balanceo * 0.5
	posar(p.hombroD, function(base)
		return Pose.enTorso(base, FRENTE, -BRAZO_ABIERTO - contrapeso)
			* Pose.enTorso(base, DERECHA, BRAZO_ADELANTE * ADELANTE)
	end, suave)
	posar(p.hombroI, function(base)
		return Pose.enTorso(base, FRENTE, BRAZO_ABIERTO - contrapeso)
			* Pose.enTorso(base, DERECHA, BRAZO_ADELANTE * ADELANTE)
	end, suave)
end

local arrancado = false
local avisado = false

function Riders.build()
	if arrancado then
		return
	end
	arrancado = true

	local jugador = Players.LocalPlayer

	-- En Heartbeat y no en RenderStepped: esto no va sincronizado con la camara, y
	-- ademas RenderStepped se para en seco cuando la ventana pierde el foco -- con lo
	-- que la animacion no se puede medir desde fuera. Ver la misma nota en `Alerta`.
	RunService.Heartbeat:Connect(function(delta)
		local ok, err = pcall(function()
			local raiz = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dondeEstoy = if raiz then raiz.Position else nil

			-- A QUIEN SE MIRA: a los jugadores y a las patrullas. Recorrer el Workspace
			-- entero por fotograma para encontrar cinco personajes seria pagar el mapa
			-- de siete mil piezas sesenta veces por segundo.
			local candidatos: { Model } = {}
			for _, otro in Players:GetPlayers() do
				if otro.Character then
					table.insert(candidatos, otro.Character)
				end
			end
			local carpeta = workspace:FindFirstChild("Patrullas")
			if carpeta then
				for _, hijo in carpeta:GetChildren() do
					if hijo:IsA("Model") then
						table.insert(candidatos, hijo)
					end
				end
			end

			for _, personaje in candidatos do
				if patinadores[personaje] == nil and personaje:GetAttribute("vehiculoDePie") == true then
					local p = adoptar(personaje)
					if p then
						-- Desfasado al montar, para que dos patinadores no empujen a la vez.
						local donde = p.raiz.Position
						p.fase = (math.abs(donde.X) + math.abs(donde.Z)) % PATADA_CADA
						callarAnimaciones(p)
						patinadores[personaje] = p
					end
				end
			end

			for _, p in patinadores do
				animar(p, delta, dondeEstoy)
			end
		end)
		if not ok and not avisado then
			avisado = true
			warn("[Contrabando] fallo animando a los patinadores: " .. tostring(err))
		end
	end)
end

return Riders
