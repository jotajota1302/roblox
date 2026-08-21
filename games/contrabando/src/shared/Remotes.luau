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
Remotes.MEJORAR_NAVE = "MejorarNave" -- cliente -> servidor: "pago la siguiente mejora de la nave"
Remotes.COMPRAR_HABILIDAD = "ComprarHabilidad" -- cliente -> servidor: "compro este peldaño"
Remotes.USAR_SENUELO = "UsarSenuelo" -- cliente -> servidor: "suelto el cebo aquí"
-- servidor -> cliente: (clave de Strings, argumentos, color). NO viaja el texto
-- ya montado: el idioma es del jugador, y en una partida con dos personas de
-- paises distintos el servidor no tiene un idioma correcto que elegir.
Remotes.AVISO = "Aviso"
Remotes.SONIDO = "Sonido" -- servidor -> cliente: reproducir un efecto por su clave
-- Servidor -> cliente: "acabas de entregar, y esto has cobrado". Va aparte del
-- AVISO normal porque no es una linea mas de texto: es el unico momento en que el
-- juego te da algo, y se merece la pantalla entera un segundo. Ver `Hud.entregado`.
Remotes.ENTREGADO = "Entregado"

-- servidor -> cliente: "acabas de coger un rayo". Va SIN datos: el estado ya
-- viaja por SYNC_STATE y lo unico que hace falta aqui es el instante exacto, que
-- es lo que no se puede deducir de un numero que cambia.
--
-- Y va aparte de SONIDO en vez de colarse como una clave mas, porque no es un
-- sonido: es un golpe de camara. Meterlo ahi obligaria al cliente a mirar la
-- clave para decidir si ademas hace otra cosa, y esa clase de "casi es lo mismo"
-- es como se acaba con un remote que significa dos cosas.
Remotes.IMPULSO = "Impulso"

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
