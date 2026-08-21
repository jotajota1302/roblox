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
-- cliente -> servidor: "gasto lo que llevo en esta casilla" (salto o escudo). Manda
-- solo la CLASE, nunca el efecto: el servidor mira si de verdad lo tiene, lo
-- descuenta y decide cuanto dura. Un cliente que pudiera decir "activame el escudo"
-- seria un escudo permanente para cualquiera con un ejecutor.
Remotes.USAR_OBJETO = "UsarObjeto"
-- servidor -> cliente: (clave de Strings, argumentos, color). NO viaja el texto
-- ya montado: el idioma es del jugador, y en una partida con dos personas de
-- paises distintos el servidor no tiene un idioma correcto que elegir.
Remotes.AVISO = "Aviso"
Remotes.SONIDO = "Sonido" -- servidor -> cliente: reproducir un efecto por su clave
-- Servidor -> cliente: "acabas de entregar, y esto has cobrado". Va aparte del
-- AVISO normal porque no es una linea mas de texto: es el unico momento en que el
-- juego te da algo, y se merece la pantalla entera un segundo. Ver `Hud.entregado`.
Remotes.ENTREGADO = "Entregado"

-- Servidor -> cliente: "esa camara te esta viendo AHORA MISMO", con su posicion y
-- el nivel de calor. Va por su cuenta y no como un aviso de texto porque no es una
-- frase: es lo unico que conecta el numerito del calor con un sitio concreto de la
-- calle. Hasta ahora te fichaban y lo unico que pasaba era una linea de texto, de
-- ahi la queja historica --*"me detectan y no hay nadie"*-- que ni siquiera era de
-- las patrullas: era de no ver QUIEN te ficha.
--
-- Se manda mientras te ve, no una sola vez, y el cliente deja morir el efecto solo
-- si dejan de llegar: asi el laser se apaga cuando sales del cono, sin que el
-- servidor tenga que mandar un segundo mensaje de "ya no".
Remotes.VIGILADO = "Vigilado"

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
