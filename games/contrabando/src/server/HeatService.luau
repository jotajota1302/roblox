--!strict
--[[
	HeatService.luau — el PELIGRO de cada jugador, en el servidor.

	El nombre interno sigue siendo "calor" en todo el codigo: renombrar cien
	referencias para que coincidan con el texto de pantalla es mucho riesgo a
	cambio de nada, y el concepto es el mismo -- cuanta atencion has llamado. Lo
	que ve el jugador si esta en el idioma del juego nuevo.

	Toda la aritmética vive en Heat.luau (puro y probado). Aquí sólo está lo que
	necesita tocar el mundo: quién está cerca de qué poste, cuándo avisar y cuándo
	replicar. La línea es la de siempre en este proyecto — los defectos críticos
	aparecen en el lado impuro, así que cuanto menos haya de este lado, mejor.

	El calor NO SE PERSISTE a propósito. Reconectar empieza en frío: guardarlo
	convertiría desconectarse en un castigo, y —peor— haría que la forma óptima de
	jugar fuera cerrar el juego cada vez que se calienta la cosa. Es el mismo
	razonamiento por el que la carga no sobrevive a la desconexión (ver
	Persistence.guardar), sólo que al revés.
]]

local Players = game:GetService("Players")

local Config = require(game.ReplicatedStorage.Shared.Config)
local Heat = require(game.ReplicatedStorage.Shared.Heat)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Skills = require(game.ReplicatedStorage.Shared.Skills)
local Vision = require(game.ReplicatedStorage.Shared.Vision)
local Vehicles = require(game.ReplicatedStorage.Shared.Vehicles)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Shelter = require(game.ReplicatedStorage.Shared.Shelter)
local Strings = require(game.ReplicatedStorage.Shared.Strings)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

-- 5 Hz, igual que la intercepción. Con detectores de 35 studs de radio y un
-- jugador a 16 studs/s como mucho, entre muestra y muestra se recorren 3,2 studs:
-- imposible atravesar un detector sin que lo vea.
local HZ = 5

local HeatService = {}

-- El gancho que rellena PatrolService al arrancar: "a este jugador lo acaba de
-- fichar una cámara, y estaba aquí". Ver dónde se llama, más abajo.
HeatService.alDelatar = nil :: ((Player, Vector3) -> ())?
local calor: { [Player]: Heat.Estado } = {}
local detectores: { BasePart } = {}
local refugios: { Vector3 } = {}

-- "Una patrulla te está viendo ahora mismo". Lo escribe PatrolService y lo lee el
-- enfriamiento. DECLARADA AQUÍ ARRIBA, con todas las demás, y no junto a la
-- función que la escribe: en Lua un nombre usado antes de existir como local se
-- resuelve como global nil, y este proyecto ya ha pagado ese error dos veces
-- --`tieneLegendaria` en CargoService y `suelo` en el respaldo del decorado--. Aquí
-- habría salido especialmente caro, porque el síntoma sería sólo que el calor baja
-- mientras te persiguen: nada revienta, el juego simplemente se vuelve más fácil
-- de lo que dice ser.
local perseguidos: { [Player]: boolean } = {}

function HeatService.registrarDetector(poste: BasePart)
	table.insert(detectores, poste)
end

function HeatService.registrarRefugios(sitios: { Vector3 })
	refugios = sitios
end

-- Lo consultan también las patrullas y el robo: la regla "dentro de un refugio no
-- te alcanzan" tiene que salir de UN sitio, o el día que cambie el radio habrá
-- servicios protegiendo un área y otros no.
function HeatService.enRefugio(posicion: Vector3): boolean
	return Shelter.dentro(posicion, refugios) ~= nil
end

local function estadoDe(player: Player): Heat.Estado
	local e = calor[player]
	if not e then
		e = Heat.nuevo(os.time())
		calor[player] = e
	end
	return e
end

function HeatService.nivel(player: Player): number
	return estadoDe(player).nivel
end

-- El nivel viaja al cliente dentro del estado normal, no por un remote propio: el
-- HUD ya se redibuja entero con cada sync, y un segundo canal para un solo número
-- sólo añade una forma más de que las dos cifras se contradigan en pantalla.
local function publicar(player: Player)
	local estado = PlayerState.peek(player)
	if estado then
		estado.calor = estadoDe(player).nivel
	end
end

local function avisar(player: Player, clave: string, args: { [string]: any }?, color: Color3?)
	Remotes.event(Remotes.AVISO):FireClient(player, clave, args, color)
end

local function raiz(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Lo que le pasa a un jugador en una muestra. Devuelve si hay que sincronizar.
local function muestra(player: Player, ahora: number): boolean
	local root = raiz(player)
	if not root then
		return false
	end

	local antes = estadoDe(player)
	local nivelAntes = antes.nivel

	-- Zona segura: el calor se apaga entero. Es la promesa que hace jugable el
	-- juego en solitario -- siempre hay un sitio donde se acaba lo que te esté
	-- pasando-- y sin ella el jugador que se calienta no tiene a dónde ir.
	if (root.Position - Config.ALMACEN_POS).Magnitude <= Config.ZONA_SEGURA_RADIO then
		if nivelAntes > 0 then
			calor[player] = Heat.aSalvo(antes)
			avisar(player, "HEAT_SAFE", nil, Palette.AVISO_BUENO)
			publicar(player)
			return true
		end
		return false
	end

	local estado = antes
	local vigilado = false

	-- EN QUÉ VA, para saber desde cuán lejos le fichan. Se pregunta al estado del
	-- JUGADOR y no al del calor -- que es una tabla distinta y no sabe de vehículos.
	-- Y cuenta lo que lleva PUESTO: con la moto aparcada al otro lado del parque
	-- vas a pie, y te tienen que fichar como a alguien que va a pie.
	local suyo = PlayerState.peek(player)
	local montado = suyo ~= nil and suyo.montado ~= false
	-- Y EL CAMUFLAJE ENCIMA, que es la habilidad que compra justo esto. Multiplica
	-- el mismo número en vez de restar studs: así lo que ya estaba equilibrado
	-- --que la furgoneta se vea venir más que un monopatín-- se mueve entero en vez
	-- de aplanarse. Baja, nunca a cero: un repartidor invisible no existe.
	local radio = Config.DETECTOR_RADIO
		* (if montado and suyo then Vehicles.bulto(suyo.vehiculo) else 1)
		* (if suyo then Skills.factorBulto(suyo.habilidades) else 1)

	for _, poste in detectores do
		if poste.Parent == nil then
			continue
		end
		-- EL RADIO DEPENDE DE LO QUE CONDUCES. Una furgoneta se ve venir desde más
		-- lejos que un monopatín, y es lo que impide que el vehículo grande sea
		-- sólo mejor: aguanta más golpes (Vehicles.expone) pero recibe más.
		if (root.Position - poste.Position).Magnitude > radio then
			continue
		end

		-- Y AHORA HAY QUE ESTAR DELANTE DE ELLA, no sólo cerca.
		--
		-- Esto era un sensor de proximidad puro y se notaba desde dentro sin poder
		-- explicárselo: *"me detectan y no hay nadie"*, y más tarde *"no acabo de ver
		-- el tema de la detección de las esquinas; que te detecten sólo enemigos si
		-- miran"*. Medido a propósito: de pie al otro lado de `Edificio_0_0_1`, a 30
		-- studs de la esquina, el calor subía igual. Y la caja negra lo remató --un
		-- viaje entero de la ruta verde con el aviso de detección saltando y CERO
		-- enemigos que te vieran.
		--
		-- Las dos condiciones son las mismas que las del ladrón, y a propósito: un
		-- jugador no debería tener que aprender dos reglas de visión.
		local rumbo = poste:GetAttribute("rumbo")
		if typeof(rumbo) == "number" then
			local mirando = (CFrame.Angles(0, math.rad(rumbo), 0) * CFrame.new(0, 0, -1)).Position
			if
				not Vision.dentroDelCono(poste.Position, mirando, root.Position, Config.DETECTOR_VISION_ANGULO, radio)
			then
				continue
			end
			-- Y SIN PARED DE POR MEDIO. Sin esto el cono atravesaría una manzana
			-- entera, que es exactamente el fallo que se viene a arreglar -- sólo que
			-- con forma de tarta en vez de con forma de círculo.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { poste, root.Parent :: Instance }
			if workspace:Raycast(poste.Position, root.Position - poste.Position, params) ~= nil then
				continue
			end
		end

		vigilado = true
		local id = poste:GetAttribute("detectorId")
		if typeof(id) ~= "string" then
			continue
		end
		local siguiente, subio = Heat.detectar(estado, id, ahora)
		estado = siguiente
		if subio then
			avisar(player, "HEAT_SPOTTED", { nivel = estado.nivel, maximo = Config.CALOR_MAXIMO }, Palette.AVISO_MALO)
			Telemetry.evento(player, "calor_sube", { nivel = estado.nivel, detector = id })
		end

		-- Y LA CAMARA DA EL AVISO. Esto va FUERA del `if subio` a proposito: el calor
		-- sube una vez por camara y por recarga, pero el chivatazo tiene que darse
		-- cada vez que te ve -- si no, la segunda pasada por la misma esquina seria
		-- gratis, que es justo la ruta que un jugador acaba aprendiendo.
		--
		-- Una camara no te roba: te delata. Ver `PatrolService.delatar`.
		--
		-- SE LLAMA POR UN GANCHO Y NO CON UN `require`, y no es manía: PatrolService
		-- ya requiere a HeatService (le pregunta el nivel y le avisa de las capturas),
		-- así que pedirle algo de vuelta monta un ciclo de require -- y un ciclo aquí
		-- no da un error legible, mata los dos módulos y con ellos el calor y las
		-- patrullas enteras. Es la misma razón por la que ContactService vigila el
		-- cambio de ruta en vez de preguntárselo a RouteService.
		--
		-- Quien puede requerir sin ciclo es PatrolService, así que es él quien se
		-- engancha aquí al arrancar.
		if HeatService.alDelatar then
			HeatService.alDelatar(player, root.Position)
		end
	end

	-- Dentro de un refugio se enfría MUCHO más rápido y no cuenta que te vean: es
	-- el sitio al que corres cuando la cosa se pone fea. Pero no es instantáneo
	-- como el almacén -- sigue costando tiempo parado sin cobrar, que es lo único
	-- que escasea de verdad en una sesión (ver la cabecera de Shelter).
	local aCubierto = Shelter.dentro(root.Position, refugios) ~= nil
	local periodo = Shelter.periodoDeEnfriado(aCubierto)

	-- `vigilado` incluye a propósito sólo los detectores: las patrullas se lo dicen
	-- por su cuenta con marcarPerseguido, que es quien sabe si de verdad te ven.
	local encima = (vigilado or perseguidos[player] == true) and not aCubierto
	estado = Heat.enfriar(estado, ahora, encima, periodo)
	calor[player] = estado

	if estado.nivel ~= nivelAntes then
		if estado.nivel < nivelAntes and estado.nivel == 0 then
			avisar(player, "HEAT_CLEAR", nil, Palette.AVISO_BUENO)
		end
		publicar(player)
		return true
	end
	return false
end

-- Lo pone PatrolService: "una patrulla te está viendo ahora mismo". La tabla vive
-- aquí y no allí porque es el enfriamiento quien la necesita, y tenerla del otro
-- lado obligaría a que HeatService preguntara a PatrolService en cada muestra.
function HeatService.marcarPerseguido(player: Player, activo: boolean)
	perseguidos[player] = activo or nil
end

-- Te ha alcanzado una patrulla: el calor se apaga. Ya te ha costado media carga, y
-- arrastrar además las estrellas que te la costaron es cobrar dos veces por lo
-- mismo, justo en el momento en que el jugador decide si sigue jugando.
function HeatService.capturado(player: Player)
	calor[player] = Heat.capturado(estadoDe(player))
	publicar(player)
	PlayerState.sync(player)
end

-- EL ROBO TE TRAE EL PROBLEMA DEL OTRO. Es la pieza que convierte el PvP de
-- impuesto en decisión: hoy robar sale gratis y por eso no tiene freno; heredando
-- el calor, quien roba a alguien con tres estrellas se lleva la carga Y a toda la
-- policía que iba detrás. Va en paralelo a la herencia de ruta que ya existe
-- (Intercept.rutaTrasRobo): quien roba, hereda el viaje entero, lo bueno y lo malo.
function HeatService.transferir(victima: Player, ladron: Player)
	local heredado = estadoDe(victima).nivel
	if heredado <= 0 then
		return
	end

	local estadoLadron = estadoDe(ladron)
	if heredado > estadoLadron.nivel then
		-- Se queda con el MAYOR de los dos, no con la suma: sumar convertiría robar
		-- a dos jugadores calientes en un salto instantáneo al máximo y el ladrón no
		-- tendría ninguna forma de calcular en qué se está metiendo.
		calor[ladron] = { nivel = heredado, ultimoDescenso = os.time(), disparos = {} }
		avisar(ladron, "HEAT_INHERITED", { nivel = heredado, maximo = Config.CALOR_MAXIMO }, Palette.AVISO_AGRESIVO)
		publicar(ladron)
		PlayerState.sync(ladron)
	end

	calor[victima] = Heat.capturado(estadoDe(victima))
	publicar(victima)
	PlayerState.sync(victima)
	Telemetry.evento(ladron, "calor_heredado", { nivel = heredado })
end

function HeatService.start()
	Players.PlayerRemoving:Connect(function(player)
		calor[player] = nil
		perseguidos[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1 / HZ)
			local ahora = os.time()
			PlayerState.forEach(function(player)
				local ok, err = pcall(function()
					if muestra(player, ahora) then
						PlayerState.sync(player)
					end
				end)
				if not ok then
					warn("[Contrabando] fallo midiendo el calor: " .. tostring(err))
				end
			end)
		end
	end)
end

return HeatService
