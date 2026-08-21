--!strict
--[[
	Avatar.luau — quién es el muñeco que controla el jugador.

	EXISTE POR UN FALLO QUE PARECÍA IMPOSIBLE: al dar a Play, el personaje NO SE
	VEÍA. Existía en el servidor y en el cliente, con sus 16 partes, todas con
	Transparency 0, a trece studs de la cámara, en el centro exacto de la pantalla
	según WorldToViewportPoint, sin nada por delante. Andaba y chocaba. Pero no se
	dibujaba. Una marca de color puesta en su posición exacta SÍ se veía.

	La causa: un avatar R15 moderno está hecho de MeshPart, y cada MeshPart baja su
	malla de assetdelivery.roblox.com. Con el place SIN PUBLICAR (PlaceId = 0)
	Roblox no resuelve NINGÚN mesh -- ya lo habíamos medido con los modelos del
	decorado y hasta con uno público de la biblioteca. Así que el personaje se
	quedaba sin nada con lo que dibujarse: un fantasma que camina.

	La solución es el rig R6 clásico: está hecho de Part (bloques), no descarga
	nada, y se ve siempre. Además encaja con el prototipo, que es de cubos a
	propósito, y tiene una ventaja que no es estética: en un juego de persecuciones,
	que todos midan lo mismo hace el PvP comparable. Un avatar con paquetes
	enormes cambia el volumen que hay que alcanzar.

	Cuando el place se publique, los meshes cargan y cada uno vuelve a llevar su
	propio avatar sin tocar una línea.
]]

local Players = game:GetService("Players")

local Bounds = require(game.ReplicatedStorage.Shared.Bounds)
local Config = require(game.ReplicatedStorage.Shared.Config)
local MeshCatalog = require(game.ReplicatedStorage.Shared.MeshCatalog)
local Palette = require(game.ReplicatedStorage.Shared.Palette)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local RESPAWN_SEGUNDOS = 4

local Avatar = {}
local aparicion: BasePart? = nil

function Avatar.registrarAparicion(part: BasePart)
	aparicion = part
end

-- ¿Puede esta sesión descargar mallas? Se PRUEBA, no se deduce.
--
-- La primera versión miraba `game.PlaceId ~= 0`, dando por hecho que sin publicar
-- nunca se descarga nada. Falso: medido, un place local acabó bajando tres de los
-- cuatro modelos del catálogo sin estar publicado. Deducir la capacidad de una
-- condición indirecta dejaba al jugador con avatar de bloques en una sesión que
-- podía darle el suyo.
--
-- Se prueba una vez y se recuerda: la respuesta no cambia dentro de una misma
-- sesión de servidor, y es una llamada que espera al servidor de assets.
local puedeDescargar: boolean? = nil

local function sePuedeDescargarElAvatar(): boolean
	if puedeDescargar == nil then
		-- DOS CONDICIONES, Y LA PRIMERA ES LA QUE FALTABA.
		--
		-- `PlaceId == 0` significa place sin publicar, y sin publicar los MeshPart no
		-- se descargan: un avatar R15 son quince mallas, asi que el jugador sale
		-- INVISIBLE -- existe, anda y colisiona, y no tiene con que dibujarse. Es la
		-- trampa que este fichero entero existe para esquivar, y estaba documentada
		-- en el CLAUDE.md del proyecto desde hace dias.
		--
		-- La comprobacion de abajo sola no basta y por eso fallaba: `CreateMeshPartAsync`
		-- llega a funcionar dentro de Studio con la malla en cache, asi que decia "se
		-- puede" y despues el avatar del jugador no se dibujaba. Medido el 21/08 en una
		-- partida real: rig R15 y *"he desaparecido y estoy flotando"*.
		--
		-- Que la que sobraba no se quite: hace falta para el caso contrario -- place
		-- publicado pero sin conexion al servidor de assets.
		local publicado = game.PlaceId ~= 0
		local ok = publicado
			and pcall(function()
				return game:GetService("AssetService"):CreateMeshPartAsync(MeshCatalog.ALMACEN.mesh)
			end)
		puedeDescargar = ok
		print(
			string.format(
				"[Contrabando] avatar: %s (PlaceId=%d)",
				if ok then "el del jugador" else "de bloques R6, que es el que se ve sin publicar",
				game.PlaceId
			)
		)
	end
	return puedeDescargar :: boolean
end

local function colocar(modelo: Model)
	local punto = aparicion
	if punto then
		-- Un pelo por encima del punto de aparición para que caiga y se asiente,
		-- en vez de nacer atravesándolo.
		modelo:PivotTo(CFrame.new(punto.Position + Vector3.new(0, 4, 0)))
	end
end

local conectados: { [Player]: boolean } = {}

function Avatar.cargar(player: Player)
	if not player.Parent then
		return
	end

	if sePuedeDescargarElAvatar() then
		-- Place publicado: cada uno con su avatar, como espera un jugador de Roblox.
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if ok then
			return
		end
		warn("[Contrabando] no se pudo cargar el avatar del jugador: " .. tostring(err))
		-- y se sigue al respaldo de abajo
	end

	local ok, err = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		local modelo = Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R6)
		modelo.Name = player.Name
		colocar(modelo)
		modelo.Parent = workspace
		-- Asignar Character dispara CharacterAdded, así que todo lo que ya escucha
		-- ese evento (velocidad según la carga, haz de la legendaria, pérdida de
		-- carga al reaparecer) sigue funcionando igual.
		player.Character = modelo
	end)

	if not ok then
		warn("[Contrabando] no se pudo construir el avatar de bloques: " .. tostring(err))
		-- Último recurso: mejor un avatar invisible que un jugador sin personaje,
		-- que no puede ni moverse.
		pcall(function()
			player:LoadCharacter()
		end)
	end
end

local function vigilarMuerte(player: Player)
	if conectados[player] then
		return
	end
	conectados[player] = true

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end

		-- MAS AGIL, que es la otra mitad de "mas rapido" (Config.SALTO_ALTURA).
		-- Con los 7,2 de serie un bordillo o el escalon de una losa te frenan, y en
		-- un juego que consiste en desplazarse eso se siente como torpeza propia.
		--
		-- Se escribe AQUI y una sola vez, al nacer el personaje, y no en el bucle de
		-- la calzada como la velocidad: la velocidad depende de lo que llevas encima
		-- y cambia cada tercio de segundo; el salto no depende de nada.
		--
		-- `UseJumpPower` a false primero: un humanoide trae por defecto la medida
		-- vieja (JumpPower) y escribir JumpHeight con ella activa no hace nada. Es
		-- de los fallos que no avisan -- la propiedad acepta el numero, se queda
		-- guardado, y el personaje sigue saltando lo de siempre.
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = Config.SALTO_ALTURA

		humanoid.Died:Connect(function()
			-- Reaparecer lo hacemos NOSOTROS porque CharacterAutoLoads está
			-- apagado: con él encendido, Roblox cargaría el avatar R15 de siempre
			-- y volvería el personaje invisible.
			task.delay(RESPAWN_SEGUNDOS, function()
				Avatar.cargar(player)
			end)
		end)
	end)
end

-- EL GUARDIÁN DE LOS LÍMITES. Ver la cabecera de `Bounds.luau`: hay un fallo sin
-- reproducir que saca al jugador del mundo (*"cuando llego al medio desaparezco"*,
-- con la brújula marcando 255 km EN HORIZONTAL). No se ha encontrado la causa
-- leyendo el código, así que mientras tanto se le pone una red.
--
-- NO CURA EL FALLO Y NO PRETENDE HACERLO. Lo que hace son dos cosas que sí valen:
-- que dejes de perder la partida cuando pasa, y --la importante-- DEJAR CONSTANCIA.
-- Hoy el fallo es invisible: `get_console_output` se cuelga, el personaje se
-- destruye a -500 y no queda ni rastro de por dónde iba. Cuando vuelva a pasar,
-- esta línea de consola dirá desde dónde salió, a qué velocidad y con qué encima,
-- que es exactamente lo que falta para cerrar el diagnóstico.
--
-- SE VUELVE AL ÚLTIMO SITIO BUENO, no al almacén. Devolver a casa castigaría al
-- jugador por un fallo nuestro: perdería el viaje entero. El último sitio bueno es
-- de hace un segundo como mucho, así que se pierde un paso.
local ultimoBueno: { [Player]: Vector3 } = {}
local avisadoDelFallo = false

-- ¿Hay SUELO FIRME bajo este punto? Devuelve dónde está, o nil.
--
-- Es la pregunta que le faltaba a la primera versión del guardián y la que lo
-- convirtió en un bucle. Guardaba como "último sitio bueno" cualquier punto que
-- `Bounds.fuera` diera por dentro -- y la caja de Bounds lleva 600 studs de margen
-- a propósito, así que un punto EN EL AIRE, fuera del mapa y sin nada debajo,
-- contaba como bueno. Resultado: te caías, el guardián te devolvía exactamente a
-- donde te habías caído, y vuelta a empezar. JJ lo vio en pantalla -- el aviso de
-- rescate puesto, y el personaje cayendo contra el cielo.
--
-- Estar dentro de los límites y estar en un sitio donde se puede jugar no son la
-- misma pregunta, y confundirlas es lo que hace que una red de seguridad se
-- convierta en una trampa.
local function sueloBajo(punto: Vector3, ignorar: Instance?): Vector3?
	local rayos = RaycastParams.new()
	rayos.FilterType = Enum.RaycastFilterType.Exclude
	rayos.FilterDescendantsInstances = if ignorar then { ignorar } else {}
	local golpe = workspace:Raycast(punto + Vector3.new(0, 6, 0), Vector3.new(0, -200, 0), rayos)
	if golpe == nil then
		return nil
	end
	-- La red de seguridad NO es suelo: está para que Roblox no destruya a nadie,
	-- no para jugar encima. Devolver a alguien ahí sería dejarlo donde estaba.
	if golpe.Position.Y < Bounds.fondo() then
		return nil
	end
	return golpe.Position
end

local function rescatar(player: Player, root: BasePart, motivo: string)
	local char = player.Character
	if char == nil then
		return
	end

	local donde = root.Position
	local vuelta = ultimoBueno[player]
	-- Y SI NO HAY SITIO BUENO, A CASA. Antes se caía al almacén "más cuarenta studs",
	-- que es una posición inventada a mano; el punto de aparición es el sitio del que
	-- sabemos con certeza que se puede salir andando, porque es por donde empieza
	-- todo el mundo.
	--
	-- Y SE COMPRUEBA OTRA VEZ AQUI, aunque al guardarlo ya tuviera suelo: entre que
	-- se guardo y ahora pueden haber pasado varios segundos, y devolver a alguien a
	-- un sitio que ya no existe es como se monta un bucle -- cae, se le devuelve
	-- donde cayo, vuelve a caer. Es exactamente lo que JJ vio en pantalla: el aviso
	-- de rescate puesto y el personaje cayendo contra el cielo.
	local sitio = nil
	if vuelta ~= nil then
		local ok, firme = pcall(sueloBajo, vuelta, char)
		if ok and firme ~= nil then
			sitio = (firme :: Vector3) + Vector3.new(0, 4, 0)
		end
	end
	if sitio == nil then
		-- Sin sitio bueno fiable, AL PUNTO DE APARICION. Se pierde el viaje, y es
		-- preferible: del punto de aparicion sabemos con certeza que se puede salir
		-- andando, porque es por donde empieza todo el mundo.
		local punto = aparicion
		sitio = if punto then punto.Position + Vector3.new(0, 4, 0) else Config.ALMACEN_POS + Vector3.new(0, 6, 40)
	end

	-- Una sola vez por sesión, pero que se oiga: si esto sale por consola es que el
	-- fallo existe de verdad y hay por dónde tirar. El detalle va todo junto porque
	-- la segunda vez no se imprime.
	if not avisadoDelFallo then
		avisadoDelFallo = true
		warn(
			string.format(
				"[Contrabando] jugador FUERA DEL MUNDO (%s): %s estaba en %s, velocidad %.1f, devuelto a %s",
				motivo,
				player.Name,
				tostring(donde),
				root.AssemblyLinearVelocity.Magnitude,
				tostring(sitio)
			)
		)
	end

	-- El modelo entero con PivotTo, y NO el CFrame de la raíz: el personaje es
	-- propiedad de red del cliente y escribirle la posición pieza a pieza se
	-- revierte en cuanto el cliente manda su siguiente actualización. Es la misma
	-- lección que ya pagó el regreso al almacén de CargoService.
	char:PivotTo(CFrame.new(sitio :: Vector3))
	-- Y se le para en seco: si lo que le sacó del mapa fue la física, devolverlo
	-- con la velocidad puesta lo saca otra vez al instante siguiente.
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
	end)

	-- CON LAS COORDENADAS PUESTAS, y no es ruido de depuración: este fallo sólo le
	-- pasa a quien juega, la consola de Studio no la lee nadie durante una partida
	-- (`get_console_output` se cuelga) y sin saber DÓNDE se cae no hay diagnóstico
	-- posible. Poniéndolo en el aviso, una captura de pantalla del jugador vale por
	-- una sesión entera de sondas.
	pcall(function()
		Remotes.event(Remotes.AVISO):FireClient(player, "RESCUE_BACK", {
			-- EL MOTIVO Y LA VELOCIDAD son la mitad del diagnóstico y por eso van en
			-- pantalla: "abajo" es un agujero en el suelo, "lejos" es que algo te ha
			-- empujado, y "nan" es un CFrame roto. Tres causas distintas que se
			-- arreglan en tres sitios distintos, y sin el dato hay que adivinar.
			motivo = motivo,
			x = math.floor(donde.X),
			y = math.floor(donde.Y),
			z = math.floor(donde.Z),
			velocidad = math.floor(root.AssemblyLinearVelocity.Magnitude),
		}, Palette.AVISO_MALO)
	end)
end

local function vigilarLimites()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local motivo = Bounds.fuera(root.Position)
					if motivo then
						-- Cada rescate va en su propio pcall: que uno falle no puede
						-- dejar sin vigilancia a los demás jugadores ni matar el bucle.
						-- Un guardián que se muere en silencio es peor que no tenerlo.
						pcall(rescatar, player, root, motivo)
					else
						-- SÓLO SI HAY SUELO DEBAJO. Estar dentro de la caja no basta:
						-- ver `sueloBajo`. Y si no lo hay, no se toca lo que ya había
						-- guardado -- el sitio bueno de hace tres segundos sigue siendo
						-- bueno, y quien va por el aire (saltando, cayendo, en la rampa)
						-- no debe borrarlo.
						local ok, suelo = pcall(sueloBajo, root.Position, char)
						if ok and suelo ~= nil then
							ultimoBueno[player] = (suelo :: Vector3) + Vector3.new(0, 3, 0)
						end
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ultimoBueno[player] = nil
	end)
end

function Avatar.start()
	-- Queda apagado a propósito y para siempre: esta es la única puerta por la que
	-- se crea un personaje en este juego.
	Players.CharacterAutoLoads = false

	vigilarLimites()

	Players.PlayerAdded:Connect(function(player)
		vigilarMuerte(player)
		Avatar.cargar(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		conectados[player] = nil
	end)

	-- Y los que ya estuvieran dentro cuando arranca el servidor -- que en Studio es
	-- SIEMPRE el caso, porque el jugador de la sesión de Play existe antes de que
	-- este código corra. Sin este barrido, dar a Play deja al jugador sin personaje.
	for _, player in Players:GetPlayers() do
		vigilarMuerte(player)
		task.spawn(Avatar.cargar, player)
	end
end

return Avatar
