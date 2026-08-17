--!strict
--[[
	HeatService.luau — el calor de cada jugador, en el servidor.

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
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

-- 5 Hz, igual que la intercepción. Con detectores de 35 studs de radio y un
-- jugador a 16 studs/s como mucho, entre muestra y muestra se recorren 3,2 studs:
-- imposible atravesar un detector sin que lo vea.
local HZ = 5

local HeatService = {}
local calor: { [Player]: Heat.Estado } = {}
local detectores: { BasePart } = {}

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

local function avisar(player: Player, texto: string, color: Color3)
	Remotes.event(Remotes.AVISO):FireClient(player, texto, color)
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
			avisar(player, "A salvo en el almacén: te han perdido la pista", Palette.AVISO_BUENO)
			publicar(player)
			return true
		end
		return false
	end

	local estado = antes
	local vigilado = false

	for _, poste in detectores do
		if poste.Parent == nil then
			continue
		end
		if (root.Position - poste.Position).Magnitude > Config.DETECTOR_RADIO then
			continue
		end
		vigilado = true
		local id = poste:GetAttribute("detectorId")
		if typeof(id) ~= "string" then
			continue
		end
		local siguiente, subio = Heat.detectar(estado, id, ahora)
		estado = siguiente
		if subio then
			avisar(
				player,
				string.format("Te han detectado  ·  calor %d/%d", estado.nivel, Config.CALOR_MAXIMO),
				Palette.AVISO_MALO
			)
			Telemetry.evento(player, "calor_sube", { nivel = estado.nivel, detector = id })
		end
	end

	-- `vigilado` incluye a propósito sólo los detectores: las patrullas se lo dicen
	-- por su cuenta con marcarPerseguido, que es quien sabe si de verdad te ven.
	estado = Heat.enfriar(estado, ahora, vigilado or perseguidos[player] == true)
	calor[player] = estado

	if estado.nivel ~= nivelAntes then
		if estado.nivel < nivelAntes and estado.nivel == 0 then
			avisar(player, "Los has perdido", Palette.AVISO_BUENO)
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
		avisar(
			ladron,
			string.format("Te llevas su carga y su calor  ·  %d/%d", heredado, Config.CALOR_MAXIMO),
			Palette.AVISO_AGRESIVO
		)
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
