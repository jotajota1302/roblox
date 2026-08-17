--!strict
--[[
	Remotes.luau — el puente entre cliente y servidor.

	CONCEPTO CLAVE DE ROBLOX. El cliente (el ordenador del jugador) y el servidor
	son dos máquinas distintas ejecutando código distinto. NO comparten variables.
	La única forma de hablar entre ellos es un objeto RemoteEvent.

	  cliente:  remote:FireServer(datos)        -> servidor: remote.OnServerEvent
	  servidor: remote:FireClient(jugador, ..)  -> cliente:  remote.OnClientEvent

	REGLA DE ORO DE SEGURIDAD: el cliente miente. Un jugador con un exploit puede
	llamar a FireServer con lo que le dé la gana ("dame 999999 monedas"). Por eso
	el servidor NUNCA se cree lo que le llega: valida todo. Ver ShopService.luau.

	Este módulo solo se encarga de que los RemoteEvent existan:
	  · en el servidor los crea si no están
	  · en el cliente espera a que aparezcan (llegan replicados desde el servidor)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Nombres de los remotes, en un sitio único para no escribirlos mal por ahí.
Remotes.BUY_UPGRADE = "BuyUpgrade" -- cliente -> servidor: "quiero comprar X"
Remotes.SYNC_STATE = "SyncState" -- servidor -> cliente: "este es tu estado real"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	-- WaitForChild bloquea hasta que el objeto existe. Imprescindible en el cliente,
	-- porque el código del jugador puede arrancar antes de que llegue la réplica.
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	local folder = getFolder()

	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
