--!strict
--[[
	Remotes.luau — el puente cliente/servidor.

	El cliente y el servidor son dos máquinas distintas: no comparten variables.
	La única forma de hablar es un RemoteEvent.

	REGLA DE ORO: el cliente miente. Un exploit llama a FireServer con lo que le dé
	la gana. El servidor no se cree NADA de lo que le llega, sólo la intención.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.SYNC_STATE = "SyncState" -- servidor -> cliente: "este es tu estado real"
Remotes.PEDIR_ESTADO = "PedirEstado" -- cliente -> servidor: "acabo de entrar, ponme al día"
Remotes.ENTREGAR = "Entregar" -- cliente -> servidor: "quiero entregar aquí"
Remotes.ELEGIR_RUTA = "ElegirRuta" -- cliente -> servidor: "salgo por esta ruta"
Remotes.RECLAMAR = "Reclamar" -- cliente -> servidor: "cojo lo que ha producido el almacén"
Remotes.DEVOLVER = "Devolver" -- cliente -> servidor: "dejo esto en el almacén"
Remotes.COMPRAR = "Comprar" -- cliente -> servidor: "compro este vehículo"
Remotes.SACAR = "Sacar" -- cliente -> servidor: "saco este vehículo del garaje"
Remotes.MONTAR = "Montar" -- cliente -> servidor: "me subo o me bajo del vehículo"
Remotes.AVISO = "Aviso" -- servidor -> cliente: mensaje corto en pantalla
Remotes.SONIDO = "Sonido" -- servidor -> cliente: reproducir un efecto por su clave

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
