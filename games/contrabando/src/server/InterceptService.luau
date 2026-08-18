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

local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Intercept = require(game.ReplicatedStorage.Shared.Intercept)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local CargoService = require(script.Parent.CargoService)
local HeatService = require(script.Parent.HeatService)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local ROJO = Palette.AVISO_MALO
local AMBAR = Palette.AVISO_AGRESIVO

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
		-- Distancia al ALMACÉN, que es donde está la zona segura (I4).
		--
		-- Antes era `root.Position.Magnitude`, es decir la distancia al (0,0,0) del
		-- mundo, y era correcto sólo porque el almacén se construía justo ahí. Al
		-- plantar el juego dentro de la ciudad el almacén se va a (-600, 540) y ese
		-- atajo se convierte en un fallo grave y silencioso: la zona segura se
		-- quedaría en mitad del centro —protegiendo a quien pasa por una plaza
		-- cualquiera— y el almacén, que es el único sitio donde el diseño PROMETE
		-- que no te pueden robar, quedaría a 800 studs de su propia protección.
		-- Nada habría fallado, nada habría avisado: simplemente la promesa central
		-- del juego dejaría de cumplirse. Se calcula para todos por igual;
		-- Intercept.puedeRobar sólo la mira en el perfil de la víctima.
		distanciaOrigen = (root.Position - Config.ALMACEN_POS).Magnitude,
		-- La otra garantía espacial: dentro de un refugio no se roba. Se pregunta a
		-- HeatService y no a Shelter directamente para que la respuesta salga de un
		-- único sitio -- el día que cambie el radio, no puede haber un servicio
		-- protegiendo un área y otro protegiendo otra distinta.
		enRefugio = HeatService.enRefugio(root.Position),
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
	-- Los perfiles se arman UNA vez por jugador y por ciclo, no dentro del bucle
	-- interno. Antes el de cada víctima se recalculaba una vez por atacante: con
	-- 30 jugadores son 900 perfiles cinco veces por segundo, y este bucle es lo
	-- único del juego que corre siempre. Además así todas las comparaciones de un
	-- ciclo usan la misma foto del mundo: con el perfil recalculado a mitad de
	-- ronda, un robo podía decidirse contra un estado que otro robo del mismo
	-- ciclo ya había cambiado.
	local jugadores = {}
	local roots: { [Player]: BasePart } = {}
	local perfiles: { [Player]: Intercept.Perfil } = {}

	PlayerState.forEach(function(player)
		local root = raiz(player)
		local p = perfil(player)
		if root and p then
			table.insert(jugadores, player)
			roots[player] = root
			perfiles[player] = p
		end
	end)

	for _, atacante in jugadores do
		local rootAtacante = roots[atacante]
		local perfilAtacante = perfiles[atacante]

		for _, victima in jugadores do
			if victima == atacante then
				continue
			end
			local rootVictima = roots[victima]
			local perfilVictima = perfiles[victima]

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
			-- Y AQUÍ TAMBIÉN CUENTA EN QUÉ VA LA VÍCTIMA. Sin esto, el eje de
			-- exposición valdría contra los ladrones de mentira y no contra los de
			-- verdad, que es justo al revés de lo que importa.
			local robadas, restantes = Intercept.repartoConCapacidad(
				estadoVictima.cajas,
				Config.ROBO_FRACCION * Vehicles.expone(estadoVictima.vehiculo),
				estadoAtacante.cajas,
				Cargo.capacidad(estadoAtacante.vehiculo)
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

			-- La víctima pierde también la racha: mismo golpe, las dos cosas. El
			-- atacante NO la gana -- la racha se recoge del suelo, no se roba, o
			-- robar sería además la forma más rápida de acelerar.
			CargoService.reiniciarRacha(victima)

			estadoAtacante.marcadoHasta = ahora + Config.MARCADO_SEGUNDOS

			-- El ladrón hereda el encargo de la víctima si no traía el suyo. Sin
			-- esto, el cazador que sale del almacén vacío por la roja -- que es
			-- justo la jugada que la roja permite -- robaba y luego no tenía
			-- ningún destino que le aceptase la entrega: su premio era caminar
			-- 2.000 studs de vuelta. Ver Intercept.rutaTrasRobo.
			estadoAtacante.ruta = Intercept.rutaTrasRobo(estadoAtacante.ruta, estadoVictima.ruta)

			-- Los perfiles de este ciclo acaban de quedarse obsoletos, y la víctima
			-- sigue en juego: el atacante ya no vuelve (rompe abajo), pero a ella
			-- puede evaluarla OTRO atacante en este mismo ciclo, y su perfil
			-- cacheado todavía apunta a la tabla de cajas anterior al robo. Sin
			-- refrescarlo, el segundo ladrón se llevaría cajas que ella ya no
			-- tiene: carga duplicada de la nada.
			perfiles[victima] = perfil(victima) or perfilVictima
			perfiles[atacante] = perfil(atacante) or perfilAtacante

			CargoService.aplicarVelocidad(atacante)
			CargoService.aplicarVelocidad(victima)
			-- La carga cambió de dueño, así que las cajas visibles también: sin esto
			-- la víctima seguiría pareciendo un objetivo cargado y el ladrón seguiría
			-- pareciendo inofensivo, que es exactamente al revés de la verdad.
			CargoService.mostrarCarga(atacante)
			CargoService.mostrarCarga(victima)
			-- Y HEREDA EL CALOR con la carga. Es la pieza que convierte el PvP de
			-- impuesto en decisión: robar deja de ser gratis porque te traes encima a
			-- toda la policía que iba detrás del otro. Va en paralelo a la herencia de
			-- ruta de arriba -- quien roba, hereda el viaje entero, lo bueno y lo malo.
			HeatService.transferir(victima, atacante)
			PlayerState.sync(atacante)
			PlayerState.sync(victima)

			-- La víctima sabe quién fue: sin eso el robo es una desaparición
			-- inexplicable, y eso es rabia, no tensión. Los dos avisos usan el
			-- MISMO número: el de cajas realmente transferidas.
			avisar(victima, string.format("%s te ha robado %d cosas", atacante.DisplayName, #robadas), ROJO)
			-- Si acaba de heredar la ruta hay que DECÍRSELO: es la diferencia entre
			-- saber adónde llevar el botín y volver andando al almacén a preguntar.
			local heredada = perfilAtacante.ruta == nil and estadoAtacante.ruta ~= nil
			avisar(
				atacante,
				if heredada
					then string.format(
						"Has robado %d cosas y su ruta (%s). Estas marcado 60 s",
						#robadas,
						tostring(estadoAtacante.ruta)
					)
					else string.format("Has robado %d cosas. Estas marcado 60 s", #robadas),
				AMBAR
			)
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
