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
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Rarity = require(game.ReplicatedStorage.Shared.Rarity)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Routes = require(game.ReplicatedStorage.Shared.Routes)
local PlayerState = require(script.Parent.PlayerState)
local RouteService = require(script.Parent.RouteService)
local Telemetry = require(script.Parent.Telemetry)

local DISTANCIA_ENTREGA = 30 -- studs de margen alrededor del destino

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
	if not Cargo.cabe(estado.cajas, caja, Cargo.capacidad(estado.vehiculo)) then
		return false
	end
	table.insert(estado.cajas, caja)
	aplicarVelocidad(player)
	PlayerState.sync(player)
	CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
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
	return cajas
end

function CargoService.aplicarVelocidad(player: Player)
	aplicarVelocidad(player)
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

function CargoService.nuevaCaja(): Economy.Caja
	return { rareza = Rarity.tirada(rng) }
end

-- Punto de entrega. El multiplicador es el de la ruta elegida en la salida, y
-- entregaValida exige que la ruta elegida coincida con la ruta del destino:
-- sin eso, elegir la roja y entregar en el destino verde cobraría el premio
-- grande por el viaje corto.
-- Va como función pública (no local) para poder probarla desde el servidor sin
-- pasar por el remote.
function CargoService.entregar(player: Player)
	local estado = PlayerState.get(player)
	if #estado.cajas == 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, destino in destinos do
		local rutaDelDestino = destino:GetAttribute("ruta")
		if
			(root.Position - destino.Position).Magnitude <= DISTANCIA_ENTREGA
			and Routes.entregaValida(estado.ruta, rutaDelDestino)
		then
			local multiplicador = Routes.get(rutaDelDestino).multiplicador
			-- Un solo sync al final, con el estado ya completo: zurrón vacío, dinero
			-- cobrado y ruta liberada llegan juntos.
			local cajas = CargoService.vaciar(player, false)
			local cobrado = Economy.valorEntrega(cajas, multiplicador)
			estado.dinero += cobrado
			RouteService.limpiar(player)
			PlayerState.sync(player)
			Telemetry.evento(player, "entrega", {
				ruta = rutaDelDestino,
				cajas = #cajas,
				valor = cobrado,
			})
			Remotes.event(Remotes.SONIDO):FireClient(player, "cobro")
			return
		end
	end
	-- Si no está cerca de ningún destino, no pasa nada: no se cobra y no se avisa.
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
				:FireClient(player, "Al reaparecer pierdes la carga que llevabas encima", Palette.AVISO_MALO)
		end

		-- I1, parte 1: el haz de la legendaria no se reaplicaba aquí, sólo la
		-- velocidad. Se reimpone siempre, en paralelo a la velocidad, para que el
		-- estado visible del personaje nuevo (con o sin haz) coincida con lo que
		-- de verdad lleva encima — hoy siempre "sin haz" porque la carga se acaba
		-- de vaciar arriba, pero queda correcto aunque esa regla cambie el día de
		-- mañana.
		CargoService.marcarLegendaria(player, tieneLegendaria(estado.cajas))
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
