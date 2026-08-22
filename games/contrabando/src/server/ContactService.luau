--!strict
--[[
	ContactService.luau — quién recoge un contacto, cuándo cuenta, y en qué se
	gasta. Los contactos y las habilidades son un solo sistema: uno paga al otro,
	y separarlos en dos servicios sería partir por la mitad una misma regla.

	POR QUÉ EXISTE. Medido antes de esto: toda la experiencia del juego se otorgaba
	en una sola línea de CargoService, al entregar. Los 54-100 segundos de viaje no
	daban nada y sólo podían quitar -- el viaje era un impuesto entre dos momentos
	buenos. Aquí está la mitad buena del camino.

	EL SERVIDOR DETECTA, y no hay ningún remote de "he recogido esto", por la misma
	razón que no lo hay de "he tocado a este": un mensaje del cliente diciendo que
	ha cogido algo es una moneda gratis para cualquiera que sepa abrir un ejecutor.
	El bucle recorre a los jugadores y mide distancias, exactamente igual que
	InterceptService.

	SÓLO CUENTAN CON MISIÓN ACTIVA (carga encima y ruta elegida). Las piezas están
	siempre plantadas -- son fijas y aprendibles, como los detectores -- pero pasar
	por encima sin llevar nada no da nada. Es lo que impide que dar vueltas por la
	ciudad recolectando sea una forma de progresar sin jugar al juego.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Caches = require(game.ReplicatedStorage.Shared.Caches)
local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
local Strings = require(game.ReplicatedStorage.Shared.Strings)
local CargoService = require(script.Parent.CargoService)
local PatrolService = require(script.Parent.PatrolService)
local PlayerState = require(script.Parent.PlayerState)

local ContactService = {}

local piezas: { BasePart } = {}
-- Cuándo vuelve a estar disponible cada pieza. Se apagan al recogerlas en vez de
-- destruirse: son parte del trazado, y una ciudad que se vacía de contactos
-- después del primer viaje deja de tener camino que aprender.
local recargaHasta: { [BasePart]: number } = {}

-- El aviso sale UNA VEZ por sesión y por sitio. Un pcall pelado alrededor de algo
-- que corre cinco veces por segundo es un agujero negro: el fallo de la brújula
-- costó dos horas porque no se distinguía de "no hay nada que apuntar".
local avisados: { [string]: boolean } = {}
local function quejarse(donde: string, err: any)
	if avisados[donde] then
		return
	end
	avisados[donde] = true
	warn("[Contrabando] contactos, fallo en " .. donde .. ": " .. tostring(err))
end

-- Sube AQUI --antes que el bucle de recogida-- desde que las casillas avisan al
-- guardar y al llenarse: en Luau una funcion local no existe hasta la linea en que
-- se declara, y usarla antes no es un error de sintaxis, es una variable global
-- vacia. Lo caza el paso de analisis estatico en un segundo; en tiempo de ejecucion
-- seria un "attempt to call a nil value" dentro del pcall del ciclo, o sea la
-- recogida entera muerta en silencio.
local function avisar(player: Player, clave: string, args: { [string]: any }?, bueno: boolean?)
	Remotes.event(Remotes.AVISO)
		:FireClient(player, clave, args, if bueno then Palette.AVISO_BUENO else Palette.AVISO_MALO)
end

function ContactService.registrar(nuevas: { BasePart })
	piezas = nuevas
end

-- LOS ALIJOS. Van por su cuenta y no mezclados con las migas porque su regla es la
-- CONTRARIA: una miga solo cuenta con mision activa --si no, dar vueltas por la
-- ciudad seria una forma de progresar sin jugar-- y un alijo cuenta SIEMPRE, porque
-- lo que premia es justamente salirse. Ver la cabecera de `Caches.luau`.
local alijos: { BasePart } = {}
local alijoHasta: { [BasePart]: number } = {}

function ContactService.registrarAlijos(nuevos: { BasePart })
	alijos = nuevos
end

-- Abrir uno se ve: la caja se hunde y el halo se cierra. Se apaga en vez de
-- destruirse, igual que las migas, porque el sitio es parte de lo que se aprende --
-- un mapa que se queda pelado deja de tener escondites que recordar.
local function encenderAlijo(caja: BasePart, encendido: boolean)
	caja.Transparency = if encendido then 0 else 1
	for _, hijo in caja:GetChildren() do
		if hijo:IsA("BasePart") then
			hijo.Transparency = if encendido then (if hijo.Name == "Halo" then 0.62 else 0) else 1
		end
	end
end

-- APAGAR Y ENCENDER SE MARCA, NO SE PINTA.
--
-- El servidor no puede decidir la transparencia de una pieza del mundo, porque esa
-- decisión es DISTINTA PARA CADA JUGADOR: el rastro de la roja no le sirve de nada
-- a quien va por la verde. Antes se pintaba desde aquí y el resultado lo describió
-- JJ jugando: *"los cuadraditos que salen, aunque suene el sonido al cogerlos, no
-- desaparecen"*. Y no era que no desaparecieran -- desaparecía la que cogía, y
-- seguían a la vista las otras **139 de las tres rutas que no había elegido**.
--
-- Así que aquí sólo se deja la marca (`apagada`) y la pinta cada cliente con su
-- propio estado: ver `Rastro.luau`. El servidor mantiene la pieza visible para que,
-- si el cliente fallara, el fallo sea ver de más y no quedarse sin rastro.
local function encender(pieza: BasePart, encendida: boolean)
	pieza:SetAttribute("apagada", if encendida then nil else true)
	local luz = pieza:FindFirstChildOfClass("PointLight")
	if luz then
		luz.Enabled = encendida
	end
end

-- La última ruta que se le vio a cada jugador. Sirve para una sola cosa: darse
-- cuenta de que ha empezado un viaje nuevo.
local ultimaRuta: { [Player]: string? } = {}

-- Quien pierde la racha llama a CargoService.reiniciarRacha, que vive allí porque
-- allí está la escritura de la velocidad.
--
-- Y el reinicio POR CAMBIO DE RUTA se vigila aquí, en vez de llamarse desde
-- RouteService, porque CargoService ya requiere a RouteService: pedirle algo de
-- vuelta monta un ciclo de require que mata los dos módulos. Vigilarlo tiene
-- además la ventaja de cubrir CUALQUIER vía por la que cambie la ruta -- elegirla
-- en la valla, heredarla de una víctima al robar, o la que venga mañana.
--
-- Y CUÁNDO RECOGIÓ CADA UNO su última pieza, que es lo que mide la cadena. En
-- memoria y no en el estado guardado, por lo mismo que la recarga del señuelo: un
-- reloj que sobrevive a cerrar el juego sólo castiga a quien se desconecta, y
-- desconectarse no es una jugada.
local ultimoContacto: { [Player]: number } = {}

local function vigilarRuta(player: Player, estado: any)
	if ultimaRuta[player] ~= estado.ruta then
		ultimaRuta[player] = estado.ruta
		ultimoContacto[player] = nil
		-- EL VIAJE ENTERO, no sólo la racha: el salto y el escudo también son del
		-- viaje y también caducan aquí. Antes se llamaba a `reiniciarRacha` y esos
		-- dos se quedaban puestos, así que un escudo cogido junto a la casa de
		-- entrega salía del almacén contigo en el porte siguiente. La lista de qué
		-- caduca está en `Contacts.terminarViaje` y no aquí, para que sea UNA.
		CargoService.terminarViaje(player)

		-- Y EL RASTRO DE LA RUTA NUEVA SE ENCIENDE ENTERO.
		--
		-- La recarga son 240 segundos y un viaje al barrio dura 18. Sin esto haces el
		-- primer reparto con camino y los DOCE siguientes a ciegas -- y desde que no
		-- hay ningun indicador vertical, estas migas son la unica senal que dice hacia
		-- donde tirar. Medido jugando el 20/08: entregar en el barrio dejaba sus cinco
		-- migas apagadas cuatro minutos, o sea que el bucle que el juego pide repetir
		-- se repetia sin senalizacion. Es la queja de las tres partidas perdidas --*no
		-- se hacia donde tirar*-- reaparecida por culpa de un numero.
		--
		-- La recarga no se toca y sigue haciendo su trabajo: impide recoger dos veces
		-- la misma miga DENTRO de un viaje, que es donde el farmeo tendria gracia. Lo
		-- que no puede es sobrevivir al viaje.
		if estado.ruta ~= nil then
			for _, pieza in piezas do
				if pieza:GetAttribute("ruta") == estado.ruta then
					recargaHasta[pieza] = nil
					encender(pieza, true)
				end
			end
		end
	end
end

-- LA CADENA: quien deja de recoger pierde la racha, despacio y con gracia.
--
-- Corre aquí, en el mismo bucle que la recogida, porque son la misma regla vista
-- por sus dos caras -- y tenerlas separadas garantizaría que un día una se toque
-- y la otra no. Devuelve si hubo cambio, para no sincronizar de balde cinco veces
-- por segundo a todo el servidor.
local function decaer(player: Player, estado: any, ahora: number): boolean
	local recogidos = estado.recogidos or 0
	if recogidos <= 0 then
		return false
	end
	local ultimo = ultimoContacto[player]
	if not ultimo then
		-- Sin reloj no se descuenta: es la primera vuelta del bucle desde que
		-- empezó el viaje, y arrancar la cuenta atrás antes de la primera píldora
		-- castigaría por el tramo de casa a la calle, donde no hay rastro.
		ultimoContacto[player] = ahora
		return false
	end

	local quedan = Contacts.rachaTrasEspera(recogidos, ahora - ultimo)
	if quedan >= recogidos then
		return false
	end

	estado.recogidos = quedan
	-- El reloj se adelanta hasta el filo de la gracia en vez de ponerse a `ahora`:
	-- así el siguiente descuento cae un segundo después y no otra gracia entera.
	-- Con `ahora` a secas, la racha tardaría cinco segundos en perder cada punto
	-- en vez de uno, y la cadena no pediría nada.
	ultimoContacto[player] = ahora - Config.RACHA_GRACIA
	CargoService.aplicarVelocidad(player)
	return true
end

-- LAS CHISPAS DEL IMPULSO: el golpe visible, en el mundo y para todos.
--
-- El tiron de camara (`Boost.luau`) solo lo ve quien coge el rayo, y eso esta bien
-- para lo que es -- una sensacion. Pero la velocidad del otro es INFORMACION en
-- este juego: ver a alguien salir disparado dice "ese acaba de coger la fila" y
-- decide si te merece la pena perseguirle. Por eso esto va en el servidor, igual
-- que la carga visible y la estela de racha.
--
-- El emisor se crea UNA vez por personaje y despues solo se le pide que dispare.
-- Crear y destruir uno por recogida es la fuga lenta que este fichero ya vio en
-- RoadService: 1.658 emisores colgando de un jugador tras diez minutos de partida,
-- sin error y sin sintoma hasta que el movil va a tirones.
--
-- La textura es `rbxasset://` --de las que trae el propio cliente-- y no
-- `rbxassetid://`: las segundas hay que publicarlas y no se ven hasta entonces.
local function chispas(root: BasePart)
	local ancla = root:FindFirstChild("AnclaImpulso") :: Attachment?
	local emisor = ancla and ancla:FindFirstChild("Chispas") :: ParticleEmitter?
	if emisor == nil then
		local sitio = ancla or Instance.new("Attachment")
		sitio.Name = "AnclaImpulso"
		sitio.Position = Vector3.new(0, -1.6, 0)
		sitio.Parent = root

		emisor = Instance.new("ParticleEmitter")
		local e = emisor :: ParticleEmitter
		e.Name = "Chispas"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140))
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(0.25, 0.5)
		e.Speed = NumberRange.new(9, 18)
		e.SpreadAngle = Vector2.new(180, 180)
		e.LightEmission = 1
		e.Rate = 0 -- solo dispara cuando se le pide
		e.Parent = sitio
	end
	(emisor :: ParticleEmitter):Emit(26)
end

-- CADA CLASE, SU EFECTO. *"Cada elemento que tenga su efecto diferencial"*, y es
-- mas que variedad: si los tres se cogen igual, el jugador tiene que MIRAR el icono
-- para saber que acaba de recoger -- y a la velocidad a la que se juega no mira.
-- Notarlo en el cuerpo es la unica forma de aprender los tres sin leer nada.
--
--   · BOOST  chispas doradas a los pies y tiron de camara (ya estaban);
--   · SALTO  un anillo que se abre bajo los pies, como un impulso hacia arriba;
--   · ESCUDO la burbuja, que la enciende RoadService, y un destello al cerrarse.
--
-- Las piezas se crean y se destruyen aqui --al reves que los emisores, que se
-- reutilizan-- porque son UNA por recogida y viven medio segundo: mantener un
-- anillo por jugador para usarlo cada veinte segundos es peor negocio que crearlo.
local function anilloDeSalto(root: BasePart)
	local aro = Instance.new("Part")
	aro.Name = "AnilloSalto"
	aro.Shape = Enum.PartType.Cylinder
	aro.Size = Vector3.new(0.4, 5, 5)
	aro.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	aro.Anchored = true
	aro.CanCollide = false
	aro.CanQuery = false
	aro.CanTouch = false
	aro.CastShadow = false
	aro.Color = Color3.fromRGB(96, 226, 236)
	aro.Material = Enum.Material.Neon
	aro.Parent = workspace
	game:GetService("Debris"):AddItem(aro, 1)

	-- Se abre y se desvanece. Un anillo que solo aparece y desaparece se lee como un
	-- parpadeo; lo que dice "impulso" es que CREZCA.
	game:GetService("TweenService")
		:Create(
			aro,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.4, 22, 22), Transparency = 1 }
		)
		:Play()
end

local function destelloEscudo(root: BasePart)
	local golpe = Instance.new("Part")
	golpe.Name = "DestelloEscudo"
	golpe.Shape = Enum.PartType.Ball
	golpe.Size = Vector3.new(3, 3, 3)
	golpe.CFrame = root.CFrame
	golpe.Anchored = true
	golpe.CanCollide = false
	golpe.CanQuery = false
	golpe.CanTouch = false
	golpe.CastShadow = false
	golpe.Color = Color3.fromRGB(150, 240, 150)
	golpe.Material = Enum.Material.ForceField
	golpe.Parent = workspace
	game:GetService("Debris"):AddItem(golpe, 1)

	-- Al reves que el anillo: la burbuja se CIERRA sobre ti. Crecer es empujar,
	-- encogerse es envolver, y son las dos cosas distintas que hacen estos dos.
	game:GetService("TweenService")
		:Create(
			golpe,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(9, 9, 9), Transparency = 0.9 }
		)
		:Play()
	golpe.Size = Vector3.new(16, 16, 16)
	golpe.Transparency = 0.4
end

local function raiz(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function ContactService.tick(ahora: number)
	if #piezas == 0 then
		return
	end

	PlayerState.forEach(function(player, estado)
		vigilarRuta(player, estado)

		local root = raiz(player)
		if not root then
			return
		end

		-- LOS ALIJOS SE MIRAN ANTES DEL FILTRO DE MISION, y ahi esta todo el diseno:
		-- las migas piden llevar carga porque son el premio del VIAJE, y un alijo es
		-- el premio de EXPLORAR -- exigirle carga lo dejaria donde ya esta todo lo
		-- demas, sobre la linea de casa al destino.
		for _, caja in alijos do
			if (alijoHasta[caja] or 0) > ahora then
				continue
			end
			local dx = caja.Position.X - root.Position.X
			local dz = caja.Position.Z - root.Position.Z
			if dx * dx + dz * dz > Config.ALIJO_RADIO * Config.ALIJO_RADIO then
				continue
			end
			-- Y LA ALTURA, que hasta el 22/08 no se miraba. Con seis alijos en los
			-- tejados, un radio medido solo en planta los regalaba a quien pasara por la
			-- calle de abajo: dieciseis studs de altura caben de sobra en dieciocho de
			-- radio. Ver `Config.ALIJO_ALTURA`.
			if math.abs(caja.Position.Y - root.Position.Y) > Config.ALIJO_ALTURA then
				continue
			end
			alijoHasta[caja] = ahora + Config.ALIJO_RECARGA
			encenderAlijo(caja, false)

			local xp, objeto = Caches.premio(math.random())
			estado.xp = (estado.xp or 0) + xp
			if objeto ~= nil then
				local cupo = Contacts.guardar(estado, objeto)
				if cupo then
					avisar(player, "STASH_ITEM", { xp = xp, objeto = Strings.ref("SLOT_" .. objeto) }, true)
				else
					-- Con la casilla llena se dice, y se paga solo la experiencia: es la
					-- misma regla que las migas, y callarlo seria hacerle creer al jugador
					-- que lleva algo que no lleva.
					avisar(player, "STASH_FULL", { xp = xp, objeto = Strings.ref("SLOT_" .. objeto) }, true)
				end
			else
				avisar(player, "STASH_FOUND", { xp = xp }, true)
			end
			PlayerState.sync(player)
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
			local ok, err = pcall(chispas, root)
			if not ok then
				quejarse("el efecto del alijo", err)
			end
		end

		-- CON MISIÓN, o las migas no cuentan. Sin ruta no hay viaje, y sin carga no
		-- hay nada que arriesgar: recogerlas sería un premio sin apuesta.
		if not estado.ruta or #estado.cajas == 0 then
			return
		end

		-- Antes de mirar qué pisa: qué ha dejado de pisar.
		if decaer(player, estado, ahora) then
			PlayerState.sync(player)
		end

		for _, pieza in piezas do
			if pieza:GetAttribute("ruta") ~= estado.ruta then
				continue
			end
			if (recargaHasta[pieza] or 0) > ahora then
				continue
			end

			-- EN EL PLANO. Medir en 3D fue lo que convirtió una vez 83 studs de
			-- altura en "83 studs de desviación", y aquí haría que un contacto al
			-- pie de una cuesta no se pudiera coger nunca.
			local dx = pieza.Position.X - root.Position.X
			local dz = pieza.Position.Z - root.Position.Z
			if dx * dx + dz * dz > Config.CONTACTO_RADIO * Config.CONTACTO_RADIO then
				continue
			end

			-- El valor sale de la pieza y puede ser CERO: las del rastro aceleran
			-- pero no pagan. `or` no vale aquí -- 0 es un valor legítimo, y un
			-- `or Config.CONTACTO_VALOR_SUELTO` convertiría todo el rastro en
			-- moneda y multiplicaría por cinco la economía de habilidades.
			local valor = tonumber(pieza:GetAttribute("valor"))
			if valor == nil then
				valor = Config.CONTACTO_VALOR_SUELTO
			end
			estado.contactos = (estado.contactos or 0) + valor

			-- QUE HACE ESTA PIEZA. El tipo viaja con ella desde que la planto
			-- CityBuilder, asi que aqui no se repite ningun reparto: se lee.
			local tipo = pieza:GetAttribute("tipo")
			if tipo == Config.RECOGIBLE_ESCUDO or tipo == Config.RECOGIBLE_SALTO then
				-- A LA CASILLA, no al cuerpo. Antes los dos se disparaban aqui mismo, y
				-- eso significaba que se gastaban SIEMPRE donde estaba la pieza: el
				-- jugador no elegia, solo pasaba por encima. Ahora son municion -- ver
				-- `Contacts.guardar` y `Config.OBJETOS_TOPE`.
				local cupo, cuantos = Contacts.guardar(estado, tipo)
				if cupo then
					avisar(player, "ITEM_STORED", { objeto = Strings.ref("SLOT_" .. tipo), cuantos = cuantos }, true)
				else
					-- Y SE DICE CUANDO NO CABE. Recoger algo que se tira sin avisar es de
					-- las cosas que hacen que un jugador deje de fiarse de lo que ve.
					avisar(player, "ITEM_FULL", { objeto = Strings.ref("SLOT_" .. tipo) })
				end
			else
				-- La velocidad SI se aplica en el acto: es la racha de siempre, el pulso
				-- del rastro. Su freno es que se cae sola si dejas de recoger.
				estado.recogidos = (estado.recogidos or 0) + 1
			end
			ultimoContacto[player] = ahora

			recargaHasta[pieza] = ahora + Config.CONTACTO_RECARGA
			encender(pieza, false)

			-- La velocidad se refresca AQUÍ y no en el bucle: la racha tiene que
			-- notarse en el paso siguiente, no dentro de un segundo.
			CargoService.aplicarVelocidad(player)
			PlayerState.sync(player)
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")

			-- Y EL EMPUJON SE VE. Las dos mitades del mismo instante: las chispas en
			-- el mundo (las ve todo el mundo) y el tiron de camara (lo sientes tu).
			-- Un pcall alrededor porque son adorno: que falle el efecto no puede
			-- costar la recogida, que es lo unico que cuenta de verdad aqui.
			local ok, err = pcall(function()
				-- LAS CHISPAS SON DE RECOGER, SIEMPRE. El anillo y la burbuja se han
				-- mudado al momento de USAR el objeto (`usarObjeto`), que es donde ahora
				-- pasa algo: dibujar un impulso al guardarlo en la casilla diria que ya
				-- esta puesto, y es justo lo contrario de lo que ha ocurrido.
				chispas(root)
			end)
			if not ok then
				quejarse("efecto de recogida", err)
			end
			-- EL TIRON DE CAMARA SOLO CON EL BOOST. Es lo que significa "acabas de
			-- acelerar", y ponerlo en los tres lo convertiria en "acabas de recoger
			-- algo" -- o sea, en nada.
			if tipo ~= Config.RECOGIBLE_SALTO and tipo ~= Config.RECOGIBLE_ESCUDO then
				Remotes.event(Remotes.IMPULSO):FireClient(player)
			end
		end
	end)

	-- Y las que ya cumplieron su recarga vuelven a encenderse.
	for pieza, hasta in recargaHasta do
		if hasta <= ahora then
			recargaHasta[pieza] = nil
			encender(pieza, true)
		end
	end
	for caja, hasta in alijoHasta do
		if hasta <= ahora then
			alijoHasta[caja] = nil
			encenderAlijo(caja, true)
		end
	end
end

-- Cuándo puede volver a soltar cebo cada jugador. En memoria y no en el estado
-- guardado: una recarga que sobrevive a cerrar el juego sólo castiga a quien se
-- desconecta, y desconectarse no es una jugada.
local senueloLibre: { [Player]: number } = {}

-- LA COMPRA LA DECIDE EL SERVIDOR. El cliente pinta el precio, pero un remote
-- manipulado manda el id que quiera: sin esta comprobación, las habilidades
-- serían gratis para cualquiera que sepa abrir un ejecutor.
local function comprar(player: Player, id: any)
	if typeof(id) ~= "string" then
		return
	end
	local estado = PlayerState.peek(player)
	if not estado then
		return
	end

	local ok, motivo, habilidades, contactos = Skills.comprar(estado.habilidades, estado.contactos or 0, id)
	if not ok then
		avisar(player, motivo)
		return
	end

	estado.habilidades = habilidades
	estado.contactos = contactos
	-- El camuflaje cambia desde cuán lejos te fichan y el aguante lo que pierdes:
	-- los dos los leen sus servicios en el momento, así que no hay nada que
	-- refrescar salvo lo que ve el jugador.
	PlayerState.sync(player)
	-- El NOMBRE, no el id: "Learned: camuflaje" enseña la clave interna, que es
	-- justo lo que el jugador no tiene por qué ver nunca. Va por referencia para
	-- que se traduzca en el cliente, no aquí.
	avisar(player, "CONTACT_LEARNED", { habilidad = Strings.ref("SKILL_" .. id) }, true)
	Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
end

-- EL CEBO SE SUELTA DONDE ESTÁ EL JUGADOR, y la posición la toma el servidor del
-- personaje: si viniera en el mensaje, soltar el señuelo sería teletransportar
-- ladrones a donde uno quisiera.
local function soltarSenuelo(player: Player)
	local estado = PlayerState.peek(player)
	if not estado then
		return
	end
	if not Skills.tieneSenuelo(estado.habilidades) then
		avisar(player, "DECOY_NOT_OWNED")
		return
	end

	local ahora = os.clock()
	local libre = senueloLibre[player] or 0
	if ahora < libre then
		avisar(player, "DECOY_COOLDOWN", { segundos = math.ceil(libre - ahora) })
		return
	end

	local root = raiz(player)
	if not root then
		return
	end

	senueloLibre[player] = ahora + Config.SENUELO_RECARGA
	PatrolService.senuelo(player, root.Position, ahora + Config.SENUELO_DURACION)
	avisar(player, "DECOY_DROPPED", nil, true)
	Remotes.event(Remotes.SONIDO):FireClient(player, "alerta")
end

-- GASTAR LO QUE LLEVAS EN LA CASILLA.
--
-- El cliente manda la CLASE y nada mas. Todo lo demas --si de verdad lo tiene, si
-- ya lo tiene puesto, cuanto dura-- lo decide aqui, por la regla de siempre: un
-- remote que aceptara "activame el escudo" seria un escudo permanente para
-- cualquiera con un ejecutor.
local function usarObjeto(player: Player, tipo: any)
	if typeof(tipo) ~= "string" then
		return
	end
	local estado = PlayerState.peek(player)
	if not estado then
		return
	end
	local ahora = os.clock()

	-- YA PUESTO NO SE GASTA. Sin esto, dos pulsaciones seguidas --que en un mando
	-- pasan solas-- tiran el segundo objeto para alargar el primero medio segundo.
	-- Y se dice por que no ha pasado nada: un boton que no responde y no explica es
	-- indistinguible de uno roto.
	local activo = if tipo == Config.RECOGIBLE_SALTO then estado.saltoHasta else estado.escudoHasta
	if (activo or 0) > ahora then
		avisar(player, "ITEM_ALREADY_ON", { objeto = Strings.ref("SLOT_" .. tipo) })
		return
	end

	if not Contacts.gastar(estado, tipo) then
		avisar(player, "ITEM_NONE", { objeto = Strings.ref("SLOT_" .. tipo) })
		return
	end

	local root = raiz(player)
	if tipo == Config.RECOGIBLE_SALTO then
		estado.saltoHasta = ahora + Config.SALTO_IMPULSO_SEGUNDOS
		if root then
			pcall(anilloDeSalto, root)
		end
	elseif tipo == Config.RECOGIBLE_ESCUDO then
		estado.escudoHasta = ahora + Config.ESCUDO_SEGUNDOS
		if root then
			pcall(destelloEscudo, root)
		end
	else
		-- Una clase que no se guarda (la velocidad, o algo inventado por un
		-- ejecutor): se ha descontado de una casilla que no existe, o sea nada.
		return
	end

	PlayerState.sync(player)
	Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
end

function ContactService.start()
	-- Los dos remotes, creados AL ARRANCAR como todos: uno que el servidor sólo
	-- envía no existe hasta el primer envío, y el cliente que hace WaitForChild
	-- sobre él se cuelga para siempre.
	Remotes.event(Remotes.COMPRAR_HABILIDAD).OnServerEvent:Connect(function(player, id)
		local ok, err = pcall(comprar, player, id)
		if not ok then
			quejarse("la compra", err)
		end
	end)

	Remotes.event(Remotes.USAR_OBJETO).OnServerEvent:Connect(function(player, tipo)
		local ok, err = pcall(usarObjeto, player, tipo)
		if not ok then
			quejarse("el uso de un objeto", err)
		end
	end)

	Remotes.event(Remotes.USAR_SENUELO).OnServerEvent:Connect(function(player)
		local ok, err = pcall(soltarSenuelo, player)
		if not ok then
			quejarse("el senuelo", err)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ultimaRuta[player] = nil
		ultimoContacto[player] = nil
		senueloLibre[player] = nil
		local estado = PlayerState.peek(player)
		if estado then
			estado.recogidos = 0
		end
	end)

	local acumulado = 0
	local intervalo = 1 / Config.INTERCEPT_HZ

	RunService.Heartbeat:Connect(function(delta)
		acumulado += delta
		if acumulado < intervalo then
			return
		end
		acumulado = 0

		local ok, err = pcall(function()
			ContactService.tick(os.clock())
		end)
		if not ok then
			quejarse("el ciclo", err)
		end
	end)
end

return ContactService
