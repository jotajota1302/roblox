--!strict
--[[
	Persistence.luau — guardado en la nube.

	LA TRAMPA QUE COSTÓ TRES RONDAS DE DEPURACIÓN EN EL PILOTO:
	DataStoreService:GetDataStore() LANZA UNA EXCEPCIÓN si el place no está
	publicado. Llamarlo al cargar el módulo hace que el require reviente y mate el
	script entero: juego sin mapa, sin personaje y sin ninguna pista del motivo.

	Por eso el store se resuelve PEREZOSAMENTE y dentro de pcall. Sin place
	publicado el juego funciona igual, sólo que no guarda.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerState = require(script.Parent.PlayerState)

local NOMBRE_STORE = "ContrabandoV1"

local store: DataStore? = nil
local resuelto = false

local Persistence = {}

local function getStore(): DataStore?
	if resuelto then
		return store
	end
	resuelto = true

	local ok, resultado = pcall(function()
		return DataStoreService:GetDataStore(NOMBRE_STORE)
	end)

	if ok then
		store = resultado
	else
		warn("[Contrabando] se juega sin guardar en la nube: " .. tostring(resultado))
	end
	return store
end

function Persistence.cargar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	local ok, datos = pcall(function()
		return ds:GetAsync("jugador_" .. player.UserId)
	end)
	if not ok or type(datos) ~= "table" then
		return
	end

	local estado = PlayerState.get(player)
	estado.dinero = tonumber(datos.dinero) or estado.dinero
	estado.almacenCajas = tonumber(datos.almacenCajas) or estado.almacenCajas
	estado.almacenUltimaVisita = tonumber(datos.almacenUltimaVisita) or estado.almacenUltimaVisita
	PlayerState.sync(player)
end

function Persistence.guardar(player: Player)
	local ds = getStore()
	if not ds then
		return
	end

	local estado = PlayerState.get(player)
	-- La carga que lleva encima NO se guarda a propósito: si la partida se corta a
	-- mitad de viaje, el riesgo asumido se resuelve como una pérdida. Guardarla
	-- convertiría desconectarse en un escudo perfecto contra el robo.
	local datos = {
		dinero = estado.dinero,
		almacenCajas = estado.almacenCajas,
		almacenUltimaVisita = os.time(),
	}

	local ok, err = pcall(function()
		ds:SetAsync("jugador_" .. player.UserId, datos)
	end)
	if not ok then
		warn("[Contrabando] no se pudo guardar: " .. tostring(err))
	end
end

function Persistence.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(Persistence.cargar, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Persistence.guardar(player)
	end)

	-- Guardado periódico: si el servidor cae, PlayerRemoving no llega.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				task.spawn(Persistence.guardar, player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			Persistence.guardar(player)
		end
		task.wait(2)
	end)
end

return Persistence
