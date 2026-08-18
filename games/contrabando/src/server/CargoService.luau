--!strict
--[[
	CargoService.luau — recoger cajas, notar el peso y entregar.

	Todo lo que decide se calcula aquí, en el servidor. El cliente pide "quiero
	entregar" y el servidor comprueba que de verdad está donde dice estar: esa
	comprobación es lo que impide teletransportarse al destino y cobrar.
]]

local Players = game:GetService("Players")

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Economy = require(game.ReplicatedStorage.Shared.Economy)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Goods = require(game.ReplicatedStorage.Shared.Goods)
local GoodsLook = require(game.ReplicatedStorage.Shared.GoodsLook)
local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Rarity = require(game.ReplicatedStorage.Shared.Rarity)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
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
local function avisar(player: Player, texto: string, color: Color3)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, color)
end

local CargoService = {}
local destinos: { BasePart } = {}

local function aplicarVelocidad(player: Player)
	local estado = PlayerState.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Cargo.velocidad(estado.cajas, estado.vehiculo)
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
			avisar(
				player,
				string.format("Necesitas un vehículo mayor: eso es %s", Goods.nombreTamano(caja.objeto)),
				Palette.AVISO_MALO
			)
		end
		return false
	end
	table.insert(estado.cajas, caja)
	aplicarVelocidad(player)
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

	-- Apiladas a la espalda, en dos columnas. Se limita a 6 a la vista aunque la
	-- furgoneta lleve 10: más allá de eso la torre tapa la cámara del propio
	-- jugador, y lo que se quiere transmitir --"éste va cargado"-- ya se transmite
	-- con seis. El número exacto lo da el HUD.
	local visibles = math.min(#estado.cajas, 6)
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
		p.CFrame = root.CFrame * CFrame.new(-0.6 + columna * 1.2, 0.2 + fila * 1.15, 1.1)
		p.Parent = bulto

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
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
	cartel.Size = UDim2.fromScale(9, 1.4)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	cartel.AlwaysOnTop = false -- tapado por edificios: esconderse tiene que servir
	cartel.MaxDistance = 140
	cartel.Adornee = root
	cartel.Parent = bulto

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Rarity.color(mejor.rareza)
	texto.TextStrokeTransparency = 0.25
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = if #estado.cajas > 1
		then string.format("%s  +%d", Goods.etiqueta(mejor.objeto, mejor.rareza), #estado.cajas - 1)
		else Goods.etiqueta(mejor.objeto, mejor.rareza)
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

-- El cobro en sí. No comprueba nada: quien llama ya lo ha hecho.
local function cobrar(player: Player, destino: BasePart)
	local estado = PlayerState.get(player)
	local esRetorno = estado.retornoZona ~= nil
	local rutaDelDestino = if esRetorno then estado.retornoZona :: string else destino:GetAttribute("ruta") :: string
	-- El retorno paga una fracción: si rindiera igual que la ida, la ruta elegida
	-- daría lo mismo y la decisión de destino --que es el corazón del juego-- se
	-- quedaría sin peso.
	local multiplicador = Routes.get(rutaDelDestino).multiplicador * (if esRetorno then Config.RETORNO_FRACCION else 1)
	-- Un solo sync al final, con el estado ya completo: zurrón vacío, dinero
	-- cobrado y ruta liberada llegan juntos.
	local cajas = CargoService.vaciar(player, false)
	local cobrado = Economy.valorEntrega(cajas, multiplicador)
	estado.dinero += cobrado

	-- Y experiencia, que es lo único que no se puede gastar. El dinero se va en
	-- vehículos; el nivel se queda, y por eso es lo que sirve para saber quién
	-- tienes delante cuando os cruzáis en una calle.
	local nivelAntes = Levels.nivelDe(estado.xp or 0)
	estado.xp = (estado.xp or 0) + Levels.xpPorEntrega(cobrado)
	local nivelAhora = Levels.nivelDe(estado.xp)

	RouteService.limpiar(player)

	if esRetorno then
		-- Se cierra el ciclo: ya no llevas nada de vuelta y el almacén vuelve a ser
		-- el punto de partida.
		estado.retornoZona = nil
		estado.retorno = {}
	else
		-- Y aquí se abre el siguiente: el destino te ofrece carga para el camino de
		-- vuelta. Es lo que convierte los 90 segundos de volver de vacío en otro
		-- viaje con algo que perder.
		--
		-- SIEMPRE pequeñas (nivel 1): si hiciera falta vehículo para moverlas, el
		-- jugador nuevo volvería de vacío igual y no habríamos arreglado nada.
		--
		-- Y SE SUBEN SOLAS al zurrón, igual que la entrega se cobra sola. La primera
		-- versión las dejaba en el suelo esperando a que las recogieras, y eso
		-- producía justo lo que contó JJ jugando: "en la vuelta al almacén la
		-- brújula sigue apuntando al primer destino". No era un fallo de la brújula
		-- -- apuntaba a la carga que se había dejado atrás-- pero da igual: si el
		-- juego tiene que explicar por qué su flecha señala el sitio del que acabas
		-- de salir, la flecha está mal. Nadie entrega y decide NO llevarse el
		-- encargo de vuelta.
		estado.retorno = {}
		local capacidad = Cargo.capacidad(estado.vehiculo)
		local subidas = 0
		for _ = 1, Config.RETORNO_PIEZAS do
			local pieza = CargoService.nuevaCaja(1)
			if Cargo.cabe(estado.cajas, pieza, capacidad, estado.vehiculo) then
				table.insert(estado.cajas, pieza)
				subidas += 1
			else
				-- Lo que no cabe se queda en el muelle del destino, con su aviso: es
				-- el caso raro (zurrón lleno de carga robada) y ahí sí toca elegir.
				table.insert(estado.retorno, pieza)
			end
		end
		estado.retornoZona = rutaDelDestino
		if subidas > 0 then
			task.delay(0.8, function()
				avisar(player, string.format("Cargas %d bultos de vuelta al almacén", subidas), Palette.AVISO_BUENO)
			end)
		end
	end

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
	-- El cobro también se dice con palabras, no sólo cambiando una cifra en una
	-- esquina. Es el único momento en que el juego te da algo, y una cifra que
	-- salta de 0 a 300 sin más se pierde entre lo demás.
	avisar(player, string.format("+%d por %d cosas en la %s", cobrado, #cajas, rutaDelDestino), Palette.AVISO_BUENO)

	-- Subir de nivel se dice aparte y DESPUÉS del cobro: son dos buenas noticias y
	-- juntas en una línea se pisan. La segunda es la que se recuerda.
	if nivelAhora > nivelAntes then
		task.delay(1.6, function()
			avisar(player, string.format("¡Nivel %d!", nivelAhora), Palette.AVISO_BUENO)
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
		avisar(player, "No llevas nada que entregar", Palette.AVISO_MALO)
	elseif motivo == "sin_ruta_lejos" then
		avisar(player, "Saliste sin destino elegido: vuelve a la salida del almacén", Palette.AVISO_MALO)
	elseif motivo == "no_has_llegado" then
		avisar(player, "Todavía no has llegado: sigue la baliza " .. tostring(estado.ruta), Palette.AVISO_MALO)
	elseif motivo == "sin_ruta" then
		avisar(player, "Saliste sin destino elegido, así que esta carga no vale aquí", Palette.AVISO_MALO)
	elseif motivo == "destino_equivocado" then
		local rutaDelDestino = "?"
		for _, d in destinos do
			if (root.Position - d.Position).Magnitude <= DISTANCIA_ENTREGA then
				rutaDelDestino = tostring(d:GetAttribute("ruta"))
			end
		end
		avisar(
			player,
			string.format("Este es el destino %s y tu destino es la %s", rutaDelDestino, tostring(estado.ruta)),
			Palette.AVISO_MALO
		)
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
			Remotes.event(Remotes.AVISO)
				:FireClient(player, "Al reaparecer pierdes lo que llevabas encima", Palette.AVISO_MALO)
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
