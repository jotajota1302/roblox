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

local MeshCatalog = require(game.ReplicatedStorage.Shared.MeshCatalog)

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
		local ok = pcall(function()
			return game:GetService("AssetService"):CreateMeshPartAsync(MeshCatalog.ALMACEN.mesh)
		end)
		puedeDescargar = ok
		print("[Contrabando] descarga de mallas: " .. (ok and "disponible" or "no disponible, avatar de bloques"))
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

function Avatar.start()
	-- Queda apagado a propósito y para siempre: esta es la única puerta por la que
	-- se crea un personaje en este juego.
	Players.CharacterAutoLoads = false

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
