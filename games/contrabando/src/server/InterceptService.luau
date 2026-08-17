--!strict
--[[
	InterceptService.luau — detección de robos, EN EL SERVIDOR.

	EL RIESGO TÉCNICO CENTRAL DEL JUEGO. En Roblox el personaje pertenece al cliente
	por diseño: un exploit puede teletransportarse, y el núcleo de este juego es una
	persecución. No se elimina; se le quita el incentivo.

	Por eso el servidor recorre él mismo a los jugadores cinco veces por segundo y
	NO EXISTE ningún remote de "he tocado a este". Esa llamada sería el primer
	exploit del juego: cualquiera podría robar a cualquiera desde el otro extremo
	del mapa sin moverse.

	Robar no es cobrar: te llevas la carga, pero ahora eres TÚ quien tiene que
	llegar cargado, lento y marcado 60 segundos. Interceptar no puede ser mejor que
	transportar, que es como degeneran estos sistemas.
]]

local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Intercept = require(game.ReplicatedStorage.Shared.Intercept)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local CargoService = require(script.Parent.CargoService)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local ROJO = Color3.fromRGB(220, 80, 80)
local AMBAR = Color3.fromRGB(230, 180, 70)

local InterceptService = {}

local function raiz(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function perfil(player: Player): Intercept.Perfil?
	local estado = PlayerState.get(player)
	local root = raiz(player)
	if not root then
		return nil
	end
	return {
		cajas = estado.cajas,
		ruta = estado.ruta,
		marcadoHasta = estado.marcadoHasta,
		velocidad = root.AssemblyLinearVelocity.Magnitude,
		-- El almacén se construye en el origen (WorldBuilder), así que la distancia
		-- al (0,0,0) del mundo es la distancia a la zona segura (I4). Se calcula
		-- para todos los jugadores por igual; Intercept.puedeRobar sólo la mira en
		-- el perfil de la víctima.
		distanciaOrigen = root.Position.Magnitude,
	}
end

local function avisar(player: Player, texto: string, color: Color3)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, color)
end

local function sonar(player: Player, clave: string)
	Remotes.event(Remotes.SONIDO):FireClient(player, clave)
end

-- Última vez que se alertó a cada jugador, para no repetir el aviso cinco veces por
-- segundo mientras dura la persecución: una alerta constante deja de ser información
-- y pasa a ser ruido que se ignora.
local ultimaAlerta: { [Player]: number } = {}
local ALERTA_CADA = 4

function InterceptService.tick(ahora: number)
	local jugadores = {}
	PlayerState.forEach(function(player)
		table.insert(jugadores, player)
	end)

	for _, atacante in jugadores do
		local rootAtacante = raiz(atacante)
		local perfilAtacante = perfil(atacante)
		if not rootAtacante or not perfilAtacante then
			continue
		end

		for _, victima in jugadores do
			if victima == atacante then
				continue
			end
			local rootVictima = raiz(victima)
			local perfilVictima = perfil(victima)
			if not rootVictima or not perfilVictima then
				continue
			end

			local distancia = (rootAtacante.Position - rootVictima.Position).Magnitude

			-- Aviso de persecución antes del alcance. Sin esto la carga desaparece de
			-- golpe y sin explicación, que es la diferencia exacta entre tensión y rabia.
			if Intercept.esAmenaza(perfilAtacante, perfilVictima, distancia, ahora) then
				if ahora - (ultimaAlerta[victima] or 0) >= ALERTA_CADA then
					ultimaAlerta[victima] = ahora
					avisar(victima, "Te vienen detras", ROJO)
					sonar(victima, "alerta")
				end
			end

			local puede = Intercept.puedeRobar(perfilAtacante, perfilVictima, distancia, ahora)
			if not puede then
				continue
			end

			local estadoVictima = PlayerState.get(victima)
			local estadoAtacante = PlayerState.get(atacante)

			-- Solo se roba lo que quepa en el ladrón: lo que no cabe se queda con
			-- la víctima. Robar transfiere carga, nunca la destruye.
			local robadas, restantes = Intercept.repartoConCapacidad(
				estadoVictima.cajas,
				Config.ROBO_FRACCION,
				estadoAtacante.cajas,
				Config.CAPACIDAD_A_PIE
			)

			-- Un ladrón que ya va lleno no roba nada: no hay suceso que marcar,
			-- avisar ni sonar, y sigue disponible para probar con otra víctima
			-- este mismo ciclo.
			if #robadas == 0 then
				continue
			end

			estadoVictima.cajas = restantes
			for _, caja in robadas do
				table.insert(estadoAtacante.cajas, caja)
			end

			estadoAtacante.marcadoHasta = ahora + Config.MARCADO_SEGUNDOS

			CargoService.aplicarVelocidad(atacante)
			CargoService.aplicarVelocidad(victima)
			PlayerState.sync(atacante)
			PlayerState.sync(victima)

			-- La víctima sabe quién fue: sin eso el robo es una desaparición
			-- inexplicable, y eso es rabia, no tensión. Los dos avisos usan el
			-- MISMO número: el de cajas realmente transferidas.
			avisar(victima, string.format("%s te ha robado %d cajas", atacante.DisplayName, #robadas), ROJO)
			avisar(atacante, string.format("Has robado %d cajas. Estas marcado 60 s", #robadas), AMBAR)
			sonar(victima, "robo")
			sonar(atacante, "robo")
			Telemetry.evento(atacante, "robo", { robadas = #robadas, ruta = perfilVictima.ruta })
			Telemetry.evento(victima, "robado", { perdidas = #robadas, ruta = perfilVictima.ruta })

			break -- un robo por atacante y por ciclo
		end
	end
end

function InterceptService.start()
	-- Los remotes que solo se ENVIAN hay que crearlos al arrancar: el cliente hace
	-- WaitForChild sobre ellos nada mas cargar y, si no existen, espera para siempre.
	Remotes.event(Remotes.AVISO)
	Remotes.event(Remotes.SONIDO)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		ultimaAlerta[player] = nil
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
			InterceptService.tick(os.time())
		end)
		if not ok then
			warn("[Contrabando] fallo en el ciclo de intercepcion: " .. tostring(err))
		end
	end)
end

return InterceptService
