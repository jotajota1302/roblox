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
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
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

function ContactService.registrar(nuevas: { BasePart })
	piezas = nuevas
end

local function encender(pieza: BasePart, encendida: boolean)
	pieza.Transparency = if encendida then 0 else 1
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
local function vigilarRuta(player: Player, estado: any)
	if ultimaRuta[player] ~= estado.ruta then
		ultimaRuta[player] = estado.ruta
		CargoService.reiniciarRacha(player)
	end
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

		-- CON MISIÓN, o no cuenta. Sin ruta no hay viaje, y sin carga no hay nada
		-- que arriesgar: recoger sería un premio sin apuesta.
		if not estado.ruta or #estado.cajas == 0 then
			return
		end

		local root = raiz(player)
		if not root then
			return
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

			local valor = tonumber(pieza:GetAttribute("valor")) or Config.CONTACTO_VALOR_SUELTO
			estado.contactos = (estado.contactos or 0) + valor
			estado.recogidos = (estado.recogidos or 0) + 1

			recargaHasta[pieza] = ahora + Config.CONTACTO_RECARGA
			encender(pieza, false)

			-- La velocidad se refresca AQUÍ y no en el bucle: la racha tiene que
			-- notarse en el paso siguiente, no dentro de un segundo.
			CargoService.aplicarVelocidad(player)
			PlayerState.sync(player)
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
		end
	end)

	-- Y las que ya cumplieron su recarga vuelven a encenderse.
	for pieza, hasta in recargaHasta do
		if hasta <= ahora then
			recargaHasta[pieza] = nil
			encender(pieza, true)
		end
	end
end

-- Cuándo puede volver a soltar cebo cada jugador. En memoria y no en el estado
-- guardado: una recarga que sobrevive a cerrar el juego sólo castiga a quien se
-- desconecta, y desconectarse no es una jugada.
local senueloLibre: { [Player]: number } = {}

local function avisar(player: Player, texto: string, bueno: boolean?)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, if bueno then Palette.AVISO_BUENO else Palette.AVISO_MALO)
end

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
	avisar(player, "Has aprendido: " .. id, true)
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
		avisar(player, "Todavia no tienes senuelo")
		return
	end

	local ahora = os.clock()
	local libre = senueloLibre[player] or 0
	if ahora < libre then
		avisar(player, string.format("Senuelo listo en %d s", math.ceil(libre - ahora)))
		return
	end

	local root = raiz(player)
	if not root then
		return
	end

	senueloLibre[player] = ahora + Config.SENUELO_RECARGA
	PatrolService.senuelo(player, root.Position, ahora + Config.SENUELO_DURACION)
	avisar(player, "Senuelo soltado", true)
	Remotes.event(Remotes.SONIDO):FireClient(player, "alerta")
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

	Remotes.event(Remotes.USAR_SENUELO).OnServerEvent:Connect(function(player)
		local ok, err = pcall(soltarSenuelo, player)
		if not ok then
			quejarse("el senuelo", err)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ultimaRuta[player] = nil
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
