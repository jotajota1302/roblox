--!strict
--[[
	CargoService.luau — recoger cajas, notar el peso y entregar.

	Todo lo que decide se calcula aquí, en el servidor. El cliente pide "quiero
	entregar" y el servidor comprueba que de verdad está donde dice estar: esa
	comprobación es lo que impide teletransportarse al destino y cobrar.
]]

local Players = game:GetService("Players")

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Contacts = require(game.ReplicatedStorage.Shared.Contacts)
local Goals = require(game.ReplicatedStorage.Shared.Goals)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Goods = require(game.ReplicatedStorage.Shared.Goods)
local GoodsLook = require(game.ReplicatedStorage.Shared.GoodsLook)
local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Rarity = require(game.ReplicatedStorage.Shared.Rarity)
local Roads = require(game.ReplicatedStorage.Shared.Roads)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local Warehouse = require(game.ReplicatedStorage.Shared.Warehouse)
local Strings = require(game.ReplicatedStorage.Shared.Strings)
local PlayerState = require(script.Parent.PlayerState)
local Nameplates = require(script.Parent.Nameplates)
local Ride = require(script.Parent.Ride)
local RouteService = require(script.Parent.RouteService)
local Telemetry = require(script.Parent.Telemetry)

local DISTANCIA_ENTREGA = 30 -- studs de margen alrededor del destino
-- Margen para entregar la carga de VUELTA en el almacén. Más generoso que el de
-- los destinos porque el almacén es un edificio con nave, patio y muelle: exigir
-- pisar su centro exacto obligaría a meterse dentro para cobrar algo que ya has
-- traído.
local DISTANCIA_ALMACEN_ENTREGA = 55

-- Marcador para "el destino es el almacén". destinoParaCobrar tiene que devolver
-- una pieza y el almacén no está en la lista de destinos; esta pieza vacía evita
-- tener que cambiar la firma y que todos los que la llaman se enteren.
local almacenComoDestino: BasePart = Instance.new("Part")
almacenComoDestino.Name = "AlmacenComoDestino"

-- ARRIBA DEL TODO, antes que cualquiera que la use. Estaba declarada a mitad de
-- fichero y en cuanto recoger() paso a necesitarla se habria resuelto como un
-- global nil: reventaria justo al intentar avisar de que no te cabe algo, es
-- decir en el unico caso en que hace falta. Este proyecto ya ha pagado ese mismo
-- error cuatro veces (tieneLegendaria, suelo del decorado, perseguidos, rng).
local function avisar(player: Player, clave: string, args: { [string]: any }?, color: Color3?)
	Remotes.event(Remotes.AVISO):FireClient(player, clave, args, color)
end

local CargoService = {}
local destinos: { BasePart } = {}

local function aplicarVelocidad(player: Player)
	local estado = PlayerState.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- El vehículo que CUENTA, que no siempre es el que has comprado: con la moto
		-- aparcada al otro lado del parque vas a pie (ver Roads/RoadService). Sin
		-- esto, recoger una caja te devolvería la velocidad de la moto estando a pie
		-- -- dos sitios escribiendo la misma propiedad con reglas distintas, que es
		-- la receta de un fallo imposible de reproducir.
		local cuenta = Roads.vehiculoQueCuenta(estado.vehiculo, estado.montado ~= false)
		-- Y LA RACHA ENCIMA: cada contacto recogido en este viaje acelera. Va aquí y
		-- no dentro de Cargo.velocidad a propósito -- la carga y el viaje son cosas
		-- distintas, y mezclarlas obligaría a que todo el que pregunta por el peso
		-- supiera de contactos. Contacts recorta la suma por debajo del antitrampas.
		humanoid.WalkSpeed = Contacts.velocidadConRacha(Cargo.velocidad(estado.cajas, cuenta), estado.recogidos or 0)
	end
end

-- Declarada aquí (antes de recoger/vaciar, que la usan) en vez de junto a
-- marcarLegendaria más abajo: en Lua un nombre usado antes de declararse como
-- local se resuelve como global nil, y reventaría al recoger la primera caja.
local function tieneLegendaria(cajas: { Economy.Caja }): boolean
	for _, caja in cajas do
		if caja.rareza == "legendaria" then
			return true
		end
	end
	return false
end

-- Cuándo se le dijo por última vez a cada uno que eso no le cabe, para no
-- repetírselo en bucle (ver dentro de recoger).
local quejaTamano: { [Player]: number } = {}
local SILENCIO_QUEJA = 6

function CargoService.recoger(player: Player, caja: Economy.Caja): boolean
	local estado = PlayerState.get(player)
	-- La capacidad sale del vehículo, no de la constante de ir a pie: leer
	-- Config.CAPACIDAD_A_PIE aquí dejaba el zurrón clavado en 3 aunque el jugador
	-- hubiera pagado por una furgoneta de 10, y sin dar ningún error.
	local puede, motivo = Cargo.cabe(estado.cajas, caja, Cargo.capacidad(estado.vehiculo), estado.vehiculo)
	if not puede then
		-- Se dice POR QUÉ, porque los dos motivos llevan a decisiones opuestas: uno
		-- dice vacía el zurrón y el otro dice ve a comprarte un vehículo. Desde
		-- dentro se ven igual --la pieza no se recoge-- y sin explicación el jugador
		-- concluye que está roto.
		if motivo == "vehiculo_insuficiente" and caja.objeto then
			-- UNA VEZ CADA TANTO, NO EN CADA INTENTO. El cliente recoge solo lo que
			-- tiene a diez studs, así que quedarse de pie junto a una pieza que no te
			-- cabe dispara el intento una y otra vez: medido, cuarenta avisos
			-- idénticos seguidos. Un mensaje que se repite sin parar deja de leerse y
			-- encima tapa los que sí importan.
			local ultimo = quejaTamano[player] or 0
			if os.clock() - ultimo >= SILENCIO_QUEJA then
				quejaTamano[player] = os.clock()
				avisar(
					player,
					"CARGO_NEED_BIGGER",
					{ tamano = Strings.ref(Goods.claveTamano(caja.objeto)) },
					Palette.AVISO_MALO
				)
			end
		end
		return false
	end
	table.insert(estado.cajas, caja)
	aplicarVelocidad(player)

	-- SIN RUTA AUTOMÁTICA. Aquí se le ponía el barrio al jugador nuevo para que no se
	-- encontrara una pantalla de decisión antes de su primera recompensa.
	--
	-- Era el arreglo correcto mientras la decisión llegaba tarde y en otro sitio: se
	-- cogía la carga, se andaba hasta la losa de salida, y ALLÍ preguntaba. Tres
	-- gestos separados para una sola intención. Y encima dejaba muerta la única losa
	-- con luz del recinto: JJ la pisó y no pasó nada -- "la plataforma amarilla no
	-- sirve para nada"-- porque el destino ya venía puesto de casa.
	--
	-- Ahora la pregunta sale al coger el paquete (ver debeElegir en Main.client), que
	-- es el momento en que el jugador ha dicho "me voy". Elegir es lo que hace
	-- aparecer las migas, así que la decisión y su consecuencia se ven juntas.

	PlayerState.sync(player)
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
	CargoService.mostrarCarga(player)
	return true
end

-- `sincronizar = false` para quien vaya a seguir tocando el estado y prefiera
-- mandar UNA foto ya coherente. Entregar es justo ese caso: vaciando con sync, el
-- cliente recibía un estado con el zurrón ya vacío y el dinero todavía sin cobrar
-- -- medio segundo en el que el HUD dice que has perdido la carga a cambio de
-- nada. Por defecto sí sincroniza, que es lo que espera todo lo demás.
function CargoService.vaciar(player: Player, sincronizar: boolean?): { Economy.Caja }
	local estado = PlayerState.get(player)
	local cajas = estado.cajas
	estado.cajas = {}
	aplicarVelocidad(player)
	if sincronizar ~= false then
		PlayerState.sync(player)
	end
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
	CargoService.mostrarCarga(player)
	return cajas
end

-- LA RACHA SE PIERDE ENTERA, y lo llaman tres sitios: al elegir ruta (empieza un
-- viaje nuevo), al entregar (se acabó) y al ser alcanzado (el paso en falso).
--
-- Vive aquí y no en ContactService para no montar un ciclo de require: quien la
-- pierde ya está llamando a este módulo para reescribir la velocidad, y meter el
-- camino de vuelta convertiría dos módulos en uno mal cortado.
function CargoService.reiniciarRacha(player: Player)
	local estado = PlayerState.peek(player)
	if not estado or (estado.recogidos or 0) == 0 then
		return
	end
	estado.recogidos = 0
	CargoService.aplicarVelocidad(player)
	PlayerState.sync(player)
end

function CargoService.aplicarVelocidad(player: Player)
	aplicarVelocidad(player)
end

-- LA CARGA SE VE. No es adorno: es la mitad de la información del juego.
--
-- Sin esto, un jugador con el zurrón lleno y otro vacío son idénticos, y el diseño
-- entero se apoya en lo contrario -- "por el camino ves a otros con carga" es lo
-- que hace que haya algo que cazar, y sin ello el PvP es adivinar. Y en solitario
-- pasa lo que dijo JJ probándolo: recoges tres cajas y no cambia nada en pantalla,
-- así que ni siquiera sabes si has recogido.
--
-- Se monta en el SERVIDOR, no en el cliente de cada uno, precisamente porque tiene
-- que verlo todo el mundo: es lo que convierte a un transportista en un objetivo.
function CargoService.mostrarCarga(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local vieja = character:FindFirstChild("CargaVisible")
	if vieja then
		vieja:Destroy()
	end

	local estado = PlayerState.get(player)
	if #estado.cajas == 0 then
		return
	end

	local bulto = Instance.new("Folder")
	bulto.Name = "CargaVisible"
	bulto.Parent = character

	-- LA MOCHILA, y no es adorno: es lo que convierte seis cubos flotando en una
	-- persona que carga algo.
	--
	-- Lo dijo JJ mirándolo: *"si podemos llevar una mochila con los paquetes y no
	-- los paquetes flotando"*. Tenía razón y el defecto era literal -- las cajas
	-- iban soldadas al aire treinta centímetros detrás de la espalda, sin nada que
	-- las sujetara. De lejos no se leía "va cargado", se leía "a ése le persiguen
	-- unas cajas".
	--
	-- Y ADEMÁS ABULTA CON LO QUE LLEVAS. Ésa es la parte que hace trabajo de juego
	-- y no de decorado: el diseño entero se apoya en que ver a alguien por la calle
	-- diga si merece la pena perseguirle, y una mochila reventada se lee a distancia
	-- mucho antes que contar cajitas. Crece con los HUECOS ocupados, no con el
	-- número de piezas, porque es el bulto lo que se ve: un piano abulta lo que
	-- ocho sobres.
	local torso = character:FindFirstChild("Torso") :: BasePart? or root
	local gordura = math.clamp(Cargo.pesoTotal(estado.cajas) / 12, 0, 1)

	local mochila = Instance.new("Part")
	mochila.Name = "Mochila"
	mochila.Size = Vector3.new(1.5 + gordura * 0.7, 1.5 + gordura * 0.9, 0.6 + gordura * 0.55)
	mochila.Color = Color3.fromRGB(78, 68, 56)
	mochila.Material = Enum.Material.Fabric
	mochila.Anchored = false
	mochila.CanCollide = false
	-- Sin masa, por lo mismo que las cajas: el coste de cargar se cobra en la
	-- velocidad, que es una regla del juego. Cobrarlo otra vez en la física sería
	-- un impuesto que nadie decidió.
	mochila.Massless = true
	mochila.CFrame = torso.CFrame * CFrame.new(0, 0.15, 0.55 + mochila.Size.Z / 2)
	mochila.Parent = bulto

	local anclaMochila = Instance.new("WeldConstraint")
	anclaMochila.Part0 = torso
	anclaMochila.Part1 = mochila
	anclaMochila.Parent = mochila

	-- Las dos correas por encima del hombro. Son lo que hace que se lea como
	-- mochila y no como una caja pegada a la espalda, y salen baratas: dos tiras.
	for _, lado in { -0.55, 0.55 } do
		local correa = Instance.new("Part")
		correa.Name = "Correa"
		correa.Size = Vector3.new(0.22, 1.9, 0.18)
		correa.Color = Color3.fromRGB(56, 48, 40)
		correa.Material = Enum.Material.Fabric
		correa.CanCollide = false
		correa.Massless = true
		correa.CFrame = torso.CFrame * CFrame.new(lado, 0.35, 0.42) * CFrame.Angles(math.rad(-14), 0, 0)
		correa.Parent = bulto
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = correa
		w.Parent = correa
	end

	-- Y LO QUE LLEVAS ASOMA POR LA BOCA DE LA MOCHILA, en vez de flotar detrás.
	--
	-- Cuatro a la vista y no seis: ahora el volumen lo cuenta la mochila, así que
	-- las piezas ya no tienen que hacer ese trabajo -- sólo decir QUÉ es lo que
	-- llevas, que es la decisión que le importa a quien te mira. Con menos encima,
	-- además, dejan de taparle la cámara al propio jugador. El número exacto
	-- sigue estando en el HUD.
	local altoMochila = mochila.Size.Y
	local visibles = math.min(#estado.cajas, 4)
	for i = 1, visibles do
		local caja = estado.cajas[i]
		local fila = math.floor((i - 1) / 2)
		local columna = (i - 1) % 2
		local aspecto = Goods.aspecto(caja.objeto)

		local p = Instance.new("Part")
		p.Name = "Caja" .. i
		-- Cada rareza con su forma y su material: un cajón, un maletín, un estuche
		-- blindado, una urna. Antes eran seis cubos de madera idénticos y una
		-- legendaria de x135 no se distinguía de una común salvo por el tono.
		p.Size = Goods.medida(caja.objeto, 0.55)
		-- Del color de su rareza: una legendaria a la espalda se ve de lejos, que es
		-- justo lo que el diseño quiere -- llevarla vale una fortuna Y te señala.
		p.Color = Rarity.color(caja.rareza)
		p.Material = aspecto.material
		p.Anchored = false
		p.CanCollide = false
		-- Sin masa: seis cajas con peso real cambian la física del personaje y lo
		-- vuelven torpe. El coste de llevar carga ya se cobra en la VELOCIDAD, que
		-- es una regla del juego; cobrarlo otra vez por la puerta de atrás en la
		-- física sería un impuesto que nadie decidió.
		p.Massless = true
		-- Metidas EN la mochila: sobre su boca y un poco hundidas, para que se lea
		-- que salen de dentro en vez de ir pegadas por fuera. Se colocan respecto a
		-- la mochila y no al torso, así que cuando ella abulta más, lo que asoma
		-- sube con ella sin tener que repetir la cuenta en dos sitios.
		p.CFrame = mochila.CFrame * CFrame.new(-0.42 + columna * 0.84, altoMochila / 2 - 0.15 + fila * 0.62, 0)
		p.Parent = bulto

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = mochila
		weld.Part1 = p
		weld.Parent = p

		-- Y sus detalles, los mismos que tenía en el suelo del muelle: soldados,
		-- porque a la espalda del jugador todo se mueve.
		GoodsLook.adornar(p, caja.objeto, true)
	end

	-- QUÉ llevas, escrito encima. Una sola etiqueta para todo el bulto, con la
	-- pieza más valiosa: seis carteles apilados serían ilegibles, y el dato que
	-- decide --si merece la pena arriesgarse con esto por la roja-- es el del
	-- objeto que más multiplica. Lo ven los DEMÁS jugadores también, que es lo que
	-- convierte a alguien que pasa en un objetivo que merece la pena perseguir.
	local mejor = estado.cajas[1]
	for _, caja in estado.cajas do
		local a, defA = pcall(Rarity.def, caja.rareza)
		local b, defB = pcall(Rarity.def, mejor.rareza)
		if a and b and defA.multiplicador > defB.multiplicador then
			mejor = caja
		end
	end

	local cartel = Instance.new("BillboardGui")
	cartel.Name = "EtiquetaCarga"
	cartel.Size = UDim2.fromOffset(200, 38)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	cartel.AlwaysOnTop = false -- tapado por edificios: esconderse tiene que servir
	cartel.MaxDistance = 140
	cartel.Adornee = root
	-- Tampoco a su dueño, por lo mismo que la placa del nombre: esto existe para que
	-- QUIEN TE VE PASAR decida si le merece la pena perseguirte. Tú ya sabes lo que
	-- llevas --lo dice el HUD, con el número exacto-- y desde tu cámara el cartel te
	-- queda flotando delante de la cara.
	cartel.PlayerToHideFrom = player
	cartel.Parent = bulto

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Rarity.color(mejor.rareza)
	texto.TextStrokeTransparency = 0.25
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	local etiquetaMejor = Goods.etiqueta(mejor.objeto, mejor.rareza)
	texto.Text = if #estado.cajas > 1
		then Strings.get("BACKPACK_MORE", { pieza = etiquetaMejor, cuantas = #estado.cajas - 1 })
		else etiquetaMejor
	texto.Parent = cartel
end

-- El haz de luz no es decoración: es la mitad de la mecánica. Llevar una legendaria
-- vale 13.500 por la roja Y hace que todo el servidor sepa dónde estás y qué llevas.
-- Sin el haz, la decisión difícil desaparece y sólo queda dinero gratis.
function CargoService.marcarLegendaria(player: Player, activa: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local haz = root:FindFirstChild("HazLegendaria") :: Beam?
	if not activa then
		if haz then
			haz:Destroy()
		end
		local a0 = root:FindFirstChild("HazA0")
		local a1 = root:FindFirstChild("HazA1")
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
		return
	end

	if haz then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "HazA0"
	a0.Position = Vector3.new(0, 0, 0)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "HazA1"
	a1.Position = Vector3.new(0, 300, 0)
	a1.Parent = root

	local beam = Instance.new("Beam")
	beam.Name = "HazLegendaria"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 4
	beam.Width1 = 10
	beam.Color = ColorSequence.new(Rarity.color("legendaria"))
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = root
end

-- Genera una caja con rareza aleatoria. La Tarea 9 la llamará desde el almacén;
-- de momento sirve para probar la mecánica de punta a punta.
local rng = Random.new(os.clock() * 1000)

-- `nivelMaximo` limita lo que puede salir a lo que el jugador PUEDE mover. Sin
-- ese tope, alguien a pie llenaría su almacén de sofás intocables y se quedaría
-- sin juego -- lo contrario de lo buscado: lo grande tiene que asomar de vez en
-- cuando como promesa, no ser todo lo que hay. Se deja un peldaño por encima de
-- su vehículo, que es justo la promesa.
function CargoService.nuevaCaja(nivelMaximo: number?): Economy.Caja
	local objeto = Goods.tirada(rng, nivelMaximo)
	return { rareza = objeto.rareza, objeto = objeto.id }
end

-- Punto de entrega. El multiplicador es el de la ruta elegida en la salida, y
-- entregaValida exige que la ruta elegida coincida con la ruta del destino:
-- sin eso, elegir la roja y entregar en el destino verde cobraría el premio
-- grande por el viaje corto.
--
-- CADA SALIDA DE ESTA FUNCIÓN AVISA. Antes sólo cobraba o callaba, y el
-- comentario final decía "no se cobra y no se avisa" como si fuera una decisión.
-- No lo era: en la primera partida de verdad, el jugador pulsó Entregar al llegar
-- al destino verde, no pasó absolutamente nada, y lo que leyó fue "el juego está
-- roto". Hay CUATRO motivos distintos por los que una entrega no cobra —no llevas
-- nada, no has llegado, has llegado al destino de otra ruta, o saliste sin elegir
-- ruta— y desde dentro los cuatro se ven exactamente igual: un botón muerto. Un
-- botón que no responde cuesta la partida entera; una línea de texto la salva.
--
-- Va como función pública (no local) para poder probarla desde el servidor sin
-- pasar por el remote.
-- ¿Puede cobrar aquí y ahora? Devuelve el destino bueno, o nil y el motivo.
--
-- Separado del cobro para que la entrega AUTOMÁTICA y la manual compartan
-- exactamente las mismas reglas. Con la lógica duplicada acabarían divergiendo, y
-- el día que divergieran habría un sitio donde el juego cobra solo y otro donde
-- hay que insistir a mano, sin que nada lo explicara.
local function destinoParaCobrar(estado, root: BasePart): (BasePart?, string)
	if #estado.cajas == 0 then
		return nil, "sin_carga"
	end

	-- Primero se busca el destino que tiene delante, y sólo después se juzga si le
	-- vale. Al revés es imposible distinguir "aún no has llegado" de "has llegado
	-- al sitio equivocado", que son dos consejos opuestos: uno dice sigue andando y
	-- el otro dice date la vuelta.
	-- LA VUELTA TAMBIÉN ES UNA ENTREGA. Con carga de retorno encima, el destino es
	-- el almacén y no hace falta elegir ruta: ya la elegiste a la ida.
	if estado.retornoZona ~= nil then
		if (root.Position - Config.ALMACEN_POS).Magnitude <= DISTANCIA_ALMACEN_ENTREGA then
			return almacenComoDestino, "ok"
		end
		-- Y TAMBIÉN VALE CUALQUIER OTRO DESTINO, que es lo que quita la vuelta
		-- obligatoria a casa.
		--
		-- Medido antes de esto: el ciclo del reparto más corto eran 87 segundos y
		-- **37 de ellos era el camino de vuelta** -- casi la mitad del viaje andando
		-- por donde ya habías andado, con la única gracia de que la carga de retorno
		-- también se puede perder. JJ lo resumió jugando: "tardamos mucho en
		-- completar algo".
		--
		-- Ahora entregar te deja EN OTRO SITIO desde el que seguir: coges lo que te
		-- dan y decides el siguiente destino, en vez de deshacer el camino. Volver a
		-- la nave sigue existiendo --es donde está la mercancía que de verdad paga--
		-- pero pasa a ser una decisión y no un peaje.
		--
		-- No vale el mismo del que salió: entregar donde acabas de recoger sería
		-- cobrar por dar dos pasos.
		for _, destino in destinos do
			if (root.Position - destino.Position).Magnitude > DISTANCIA_ENTREGA then
				continue
			end
			if destino:GetAttribute("ruta") ~= estado.retornoZona then
				return destino, "ok"
			end
		end
		return nil, "no_has_llegado_al_almacen"
	end

	local cerca: BasePart? = nil
	for _, destino in destinos do
		if (root.Position - destino.Position).Magnitude <= DISTANCIA_ENTREGA then
			cerca = destino
			break
		end
	end
	if not cerca then
		return nil, if estado.ruta == nil then "sin_ruta_lejos" else "no_has_llegado"
	end

	local rutaDelDestino = cerca:GetAttribute("ruta") :: string
	if not Routes.entregaValida(estado.ruta, rutaDelDestino) then
		return nil, if estado.ruta == nil then "sin_ruta" else "destino_equivocado"
	end
	return cerca, "ok"
end

-- OJO AL SITIO: esta función tiene que estar declarada ANTES de cobrar(), que es
-- quien la llama. En Luau un `local function` no existe todavía en las líneas de
-- arriba, así que teniéndola debajo valía `nil` y cobrar() reventaba justo después de
-- pagar -- el dinero entraba, y ni el aviso de cobro ni la vuelta a casa llegaban
-- nunca. Nada avisó: el jugador cobraba y se quedaba plantado en el destino.
--
-- Es la tercera vez que este proyecto paga un local usado antes de declararse.
-- EL REGRESO INSTANTÁNEO. Se mueve el modelo entero con PivotTo, no el CFrame de la
-- raíz: el personaje es propiedad de red del cliente y escribirle la posición pieza a
-- pieza desde el servidor se revierte en cuanto el cliente manda su siguiente
-- actualización. Un pivote sobre el modelo sí se replica.
--
-- Se busca el punto de aparición real en vez de calcular una posición junto al
-- almacén: la losa tiene la nave ocupándole el fondo, y aparecer dentro de un objeto
-- es de las primeras cosas que ve un jugador -- ya pasó una vez, encima de la
-- furgoneta. Si por lo que sea no está, se cae al lado del almacén y se avisa.
local function volverACasa(player: Player)
	local char = player.Character
	if char == nil then
		return
	end
	local mundo = workspace:FindFirstChild("Mundo")
	local punto = mundo and mundo:FindFirstChild("AparicionAlmacen")
	local sitio = if punto and punto:IsA("BasePart")
		then punto.Position + Vector3.new(0, 4, 0)
		else Config.ALMACEN_POS + Vector3.new(0, 6, 40)
	if punto == nil then
		warn("[Contrabando] sin punto de aparición: se vuelve junto al almacén")
	end
	char:PivotTo(CFrame.new(sitio))
end

-- El cobro en sí. No comprueba nada: quien llama ya lo ha hecho.
local function cobrar(player: Player, destino: BasePart)
	local estado = PlayerState.get(player)
	local esRetorno = estado.retornoZona ~= nil
	-- QUÉ RUTA PAGA. Manda el sitio DONDE ENTREGAS, no de dónde salió la carga: si
	-- llevas el retorno del barrio hasta la roja te has cruzado media ciudad con
	-- ella encima y tiene que notarse. El almacén no tiene atributo de ruta, así que
	-- ahí se cae a la de origen -- que es lo que hacía siempre antes de que el
	-- retorno pudiera entregarse en otro destino.
	local rutaEntregada = destino:GetAttribute("ruta")
	local rutaDelDestino = if typeof(rutaEntregada) == "string" then rutaEntregada else estado.retornoZona :: string
	-- El retorno paga una fracción: si rindiera igual que la ida, la ruta elegida
	-- daría lo mismo y la decisión de destino --que es el corazón del juego-- se
	-- quedaría sin peso.
	local multiplicador = Routes.get(rutaDelDestino).multiplicador * (if esRetorno then Config.RETORNO_FRACCION else 1)
	-- Un solo sync al final, con el estado ya completo: zurrón vacío, dinero
	-- cobrado y ruta liberada llegan juntos.
	local cajas = CargoService.vaciar(player, false)
	local cobrado = Economy.valorEntrega(cajas, multiplicador)
	estado.dinero += cobrado
	-- Y se acabó el viaje: la racha no viaja de una entrega a la siguiente.
	estado.recogidos = 0

	-- ENTREGAR TRAE GÉNERO NUEVO, y esto es lo que hace que el bucle se pueda
	-- repetir. Medido jugando el 20/08: un viaje al barrio dura 20 s y gasta tres
	-- cajas, y el almacén reponía UNA CADA TREINTA SEGUNDOS. O sea que de las diez
	-- de partida salían tres viajes seguidos --poco más de un minuto de juego-- y a
	-- partir de ahí tocaba un viaje cada minuto y medio: **veinte segundos jugando y
	-- setenta esperando, el 77 % del tiempo parado**.
	--
	-- Y esperando ENCERRADO, porque desde que la valla no deja salir sin paquete
	-- --que es lo correcto-- esos setenta segundos se pasan dentro del propio
	-- almacén sin nada que hacer. Dos decisiones razonables por separado que juntas
	-- cerraban el juego en el minuto uno, justo contra el criterio del proyecto:
	-- sesiones de más de ocho minutos.
	--
	-- Reponer lo entregado tiene además sentido de negocio: le dejas la mercancía a
	-- un contacto y el contacto te surte para el siguiente porte. El freno del juego
	-- pasa a ser el RIESGO --el calor, los ladrones, la ruta que elegiste-- y no un
	-- reloj, que es donde tiene que estar.
	--
	-- El goteo por tiempo NO se toca y sigue detrás como suelo: es lo que rellena la
	-- nave de quien vuelve mañana, y lo que salva a quien se queda a cero porque le
	-- han robado. Lo que ya no hace es ser la única fuente.
	--
	-- Sólo la IDA repone. El retorno es carga que recoges en el destino y traes a
	-- casa: contarlo también sería pagar dos veces el mismo viaje.
	if not esRetorno then
		local tope = Warehouse.mejora(estado.naveNivel).tope
		local antes = estado.almacenCajas or 0
		estado.almacenCajas = math.min(tope, antes + #cajas)
	end

	-- LOS HITOS SE COBRAN AQUÍ, y no en un servicio aparte: éste es el único sitio
	-- del juego donde una entrega ocurre de verdad, y separarlo obligaría a que dos
	-- módulos se pusieran de acuerdo sobre cuándo cuenta una.
	--
	-- Se cobran TODOS los que se cumplan de golpe: quien entrega ocho de una
	-- sentada se ha ganado los tres peldaños de entregas, y pagarle sólo el último
	-- sería quedarse con su dinero.
	estado.entregas = (estado.entregas or 0) + 1
	estado.hitos = estado.hitos or {}
	local nivelAhora = Levels.nivelDe(estado.xp or 0)
	for _, hito in Goals.cumplidos(estado.entregas, nivelAhora, estado.vehiculo, estado.hitos) do
		estado.hitos[hito.id] = true
		if hito.monedas then
			estado.dinero += hito.monedas
		end
		if hito.monedas then
			avisar(player, "GOAL_DONE_REWARD", { hito = Goals.ref(hito), monedas = hito.monedas }, Palette.AVISO_BUENO)
		else
			avisar(player, "GOAL_" .. hito.id, nil, Palette.AVISO_BUENO)
		end
	end

	-- Y experiencia, que es lo único que no se puede gastar. El dinero se va en
	-- vehículos; el nivel se queda, y por eso es lo que sirve para saber quién
	-- tienes delante cuando os cruzáis en una calle.
	local nivelAntes = Levels.nivelDe(estado.xp or 0)
	-- CON EL MULTIPLICADOR DE LA RUTA, que es de donde sale ahora la mayor parte de la
	-- experiencia. Se pasa el mismo que se uso para pagar --incluida la fraccion del
	-- retorno-- para que media entrega valga medio viaje tambien en nivel.
	estado.xp = (estado.xp or 0) + Levels.xpPorEntrega(cobrado, multiplicador)
	local nivelAhora = Levels.nivelDe(estado.xp)

	RouteService.limpiar(player)

	-- DE VUELTA A CASA, AL INSTANTE.
	--
	-- Aquí se cargaba el encargo de retorno, que era el arreglo anterior al mismo
	-- problema: la vuelta al almacén eran noventa segundos de andar de vacío, la mitad
	-- del ciclo sin una sola decisión. Darle carga a esa vuelta la hacía menos muerta,
	-- pero seguía siendo un trayecto que ya te sabías, por un camino que acababas de
	-- hacer, y JJ lo dijo de la forma más clara posible: "que sea ágil".
	--
	-- No se arregla haciendo la vuelta más entretenida: se arregla quitándola. El
	-- ciclo pasa a ser cargar, ir, entregar y estar otra vez en el muelle -- y todo lo
	-- que se gana en el viaje se conserva, que es lo que hace que valga la pena.
	estado.retornoZona = nil
	estado.retorno = {}
	volverACasa(player)

	-- La velocidad, con el zurrón ya en su sitio y la racha a cero. Va aquí y no
	-- antes porque `vaciar` la escribió cuando la racha todavía contaba: sin este
	-- repintado, entregar y quedarte quieto te dejaba corriendo lo que corrías
	-- cuando llegaste.
	aplicarVelocidad(player)
	PlayerState.sync(player)
	-- La carga de vuelta se acaba de subir al zurrón DESPUÉS de vaciarlo, así que
	-- el cuerpo sigue pintado vacío: sin este repintado, el jugador vería el mismo
	-- personaje de manos libres mientras el HUD le dice que lleva tres bultos.
	CargoService.mostrarCarga(player)
	Telemetry.evento(player, "entrega", {
		ruta = rutaDelDestino,
		cajas = #cajas,
		valor = cobrado,
	})
	Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
	-- Y se dice que ya estás en casa. Sin esto, el jugador cobra y aparece en otro
	-- sitio de golpe sin que nada le explique por qué: un teletransporte que no se
	-- anuncia se lee como un fallo, no como una comodidad.
	task.delay(0.6, function()
		avisar(player, "CARGO_WARPED_HOME", nil, Palette.AVISO_BUENO)
	end)
	-- El cobro también se dice con palabras, no sólo cambiando una cifra en una
	-- esquina. Es el único momento en que el juego te da algo, y una cifra que
	-- salta de 0 a 300 sin más se pierde entre lo demás.
	avisar(player, "CARGO_PAID", {
		monedas = cobrado,
		items = #cajas,
		-- La ruta POR REFERENCIA. Antes se pegaba `rutaDelDestino` tal cual, que es
		-- el ID: el aviso decia "+250 for 3 items on verde" en vez de "on GREEN".
		ruta = Strings.ref("ROUTE_" .. tostring(rutaDelDestino)),
	}, Palette.AVISO_BUENO)

	-- Subir de nivel se dice aparte y DESPUÉS del cobro: son dos buenas noticias y
	-- juntas en una línea se pisan. La segunda es la que se recuerda.
	if nivelAhora > nivelAntes then
		task.delay(1.6, function()
			avisar(player, "CARGO_LEVEL_UP", { nivel = nivelAhora }, Palette.AVISO_BUENO)
			Nameplates.refrescar(player)
		end)
	end
end

-- ENTREGA AUTOMÁTICA: llegas y cobras.
--
-- Lo pidió JJ y no le veo contra: NO EXISTE ninguna razón para llegar al destino
-- correcto, con la carga correcta, y no querer entregar. Cuando una acción sólo
-- tiene una respuesta posible, pedirla es un paso muerto -- y este paso muerto
-- caía justo en el único momento del bucle en que el juego te da algo.
--
-- Sólo dispara cuando de verdad va a cobrar. Los motivos por los que NO se puede
-- entregar se los guarda: aquí no se avisa de nada, porque el jugador no ha
-- pedido nada. Explicar los fallos sigue siendo trabajo de la entrega manual.
function CargoService.arrancarEntregaAutomatica()
	task.spawn(function()
		while true do
			task.wait(0.4)
			PlayerState.forEach(function(player)
				local ok, err = pcall(function()
					local estado = PlayerState.get(player)
					-- Se corta pronto en el caso normal (sin carga o sin ruta) para
					-- no medir distancias a tres destinos por cada jugador dos veces
					-- por segundo cuando la mayoría van de vuelta y de vacío.
					-- Con carga de RETORNO no hay ruta elegida --el destino es el
					-- almacén-- así que exigir `ruta` aquí dejaría la vuelta sin
					-- cobrar sola, que es justo el tramo que veníamos a arreglar.
					if #estado.cajas == 0 or (estado.ruta == nil and estado.retornoZona == nil) then
						return
					end
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not root then
						return
					end
					local destino = destinoParaCobrar(estado, root)
					if destino then
						cobrar(player, destino)
					end
				end)
				if not ok then
					warn("[Contrabando] fallo en la entrega automatica: " .. tostring(err))
				end
			end)
		end
	end)
end

-- La entrega MANUAL (tecla E). Se queda como red de seguridad y, sobre todo,
-- como la única que EXPLICA por qué no puedes cobrar: hay cuatro motivos
-- distintos y desde dentro se ven igual. Cuando el jugador pulsa, ha preguntado
-- algo y merece respuesta.
--
-- Va como función pública para poder probarla desde el servidor sin pasar por el
-- remote.
function CargoService.entregar(player: Player)
	local estado = PlayerState.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local destino, motivo = destinoParaCobrar(estado, root)
	if destino then
		cobrar(player, destino)
		return
	end

	if motivo == "sin_carga" then
		avisar(player, "CARGO_EMPTY", nil, Palette.AVISO_MALO)
	elseif motivo == "sin_ruta_lejos" then
		avisar(player, "CARGO_NO_ROUTE_FAR", nil, Palette.AVISO_MALO)
	elseif motivo == "no_has_llegado" then
		avisar(
			player,
			"CARGO_NOT_THERE_YET",
			{ ruta = Strings.ref("ROUTE_" .. tostring(estado.ruta)) },
			Palette.AVISO_MALO
		)
	elseif motivo == "sin_ruta" then
		avisar(player, "CARGO_NO_ROUTE", nil, Palette.AVISO_MALO)
	elseif motivo == "destino_equivocado" then
		local rutaDelDestino = "?"
		for _, d in destinos do
			if (root.Position - d.Position).Magnitude <= DISTANCIA_ENTREGA then
				rutaDelDestino = tostring(d:GetAttribute("ruta"))
			end
		end
		avisar(player, "CARGO_WRONG_DROP", {
			aqui = Strings.ref("ROUTE_" .. rutaDelDestino),
			tuya = Strings.ref("ROUTE_" .. tostring(estado.ruta)),
		}, Palette.AVISO_MALO)
	end
end

function CargoService.registrarDestino(destino: BasePart)
	table.insert(destinos, destino)
end

function CargoService.start()
	-- Envuelto en una función anónima que descarta los argumentos del cliente,
	-- igual que los otros tres remotes del proyecto. Conectar el método
	-- directamente (como estaba) expone su firma completa: hoy entregar() sólo
	-- declara `player` y es inocuo, pero el día que alguien le añada un segundo
	-- parámetro, ese parámetro pasaría a estar controlado por el cliente desde el
	-- primer minuto sin que nada lo señale.
	Remotes.event(Remotes.ENTREGAR).OnServerEvent:Connect(function(player)
		CargoService.entregar(player)
	end)

	-- Y se limpia el reloj de la queja al irse: una tabla indexada por Player que
	-- nadie vacía es una fuga lenta, de las que no se notan hasta la hora de
	-- partida.
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		quejaTamano[player] = nil
	end)

	CargoService.arrancarEntregaAutomatica()

	-- Al reaparecer, la velocidad vuelve al valor por defecto de Roblox:
	-- hay que reimponer la que corresponde a lo que lleva encima.
	local function alAparecer(player: Player)
		task.wait(0.2)
		aplicarVelocidad(player)

		-- I1, parte 2: qué pasa con la carga al morir o pulsar Reset. El haz de la
		-- legendaria se monta sobre el HumanoidRootPart, así que se destruye solo
		-- con el personaje — pero la carga en sí sobrevivía intacta, y con el
		-- botón estándar de Reset (sin ningún exploit) el jugador se quedaba con
		-- una caja de x135 y sin el haz que lo hacía peligroso: vaciaba la
		-- mecánica central del juego. Persistence.guardar ya razona la regla
		-- gemela para la desconexión ("guardar la carga convertiría desconectarse
		-- en un escudo perfecto contra el robo"): reaparecer es el mismo riesgo
		-- por otra puerta, así que cuesta la carga igual. Se avisa por
		-- Remotes.AVISO para que no sea una desaparición inexplicable.
		local estado = PlayerState.get(player)
		if #estado.cajas > 0 then
			CargoService.vaciar(player)
			Remotes.event(Remotes.AVISO):FireClient(player, "CARGO_LOST_ON_RESPAWN", nil, Palette.AVISO_MALO)
		end

		-- I1, parte 1: el haz de la legendaria no se reaplicaba aquí, sólo la
		-- velocidad. Se reimpone siempre, en paralelo a la velocidad, para que el
		-- estado visible del personaje nuevo (con o sin haz) coincida con lo que
		-- de verdad lleva encima — hoy siempre "sin haz" porque la carga se acaba
		-- de vaciar arriba, pero queda correcto aunque esa regla cambie el día de
		-- mañana.
		CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
		-- El personaje es NUEVO: las cajas soldadas al anterior se fueron con él.
		-- Hoy siempre repinta un cuerpo vacío porque la carga se acaba de perder
		-- arriba, pero queda correcto el día que esa regla cambie.
		CargoService.mostrarCarga(player)
		-- Y el vehículo también se fue con el cuerpo viejo. Éste SÍ se recupera
		-- entero: reaparecer cuesta la carga, no lo que has comprado -- perder una
		-- furgoneta de 15.000 por morir sería un castigo que nadie ha decidido.
		Ride.montar(player.Character, estado.vehiculo)
	end

	local function conectar(player: Player)
		player.CharacterAdded:Connect(function()
			alAparecer(player)
		end)
	end

	-- Players.PlayerAdded NUNCA dispara para quien ya estuviera en Players antes de
	-- esta línea (la misma carrera clásica de Roblox que Main.server.luau ya evita
	-- para LoadCharacter, con el mismo barrido de GetPlayers() después de conectar).
	-- Sin este barrido, cualquier jugador presente en el arranque del servidor se
	-- queda SIN este manejador para siempre -- ni velocidad, ni haz, ni pérdida de
	-- carga en ningún respawn futuro suyo -- porque el PlayerAdded que lo habría
	-- conectado ya pasó. Detectado verificando I1 en Studio: la sonda que fuerza
	-- LoadCharacter() sobre el jugador de la sesión de Play (ya presente cuando el
	-- servidor arranca) no perdía la carga hasta añadir este barrido.
	Players.PlayerAdded:Connect(conectar)
	for _, player in Players:GetPlayers() do
		conectar(player)
	end
end

return CargoService
