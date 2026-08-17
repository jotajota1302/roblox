--!strict
--[[
	Sfx.luau — efectos de sonido en el cliente.

	Los efectos NO son decoración, son información: la alerta de persecución es lo
	que convierte la intercepción en una persecución en lugar de una emboscada.

	El servidor manda una CLAVE, no un id: así cambiar un sonido es tocar Config y
	nada más, y un cliente manipulado no puede hacer sonar cosas que no existen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Sfx = {}
local cache: { [string]: Sound } = {}

function Sfx.reproducir(clave: string)
	local id = Config.SONIDOS[clave]
	if not id or id == "" then
		return -- sin id no suena nada, y no pasa nada
	end

	local sonido = cache[clave]
	if not sonido then
		sonido = Instance.new("Sound")
		sonido.Name = "Sfx_" .. clave
		sonido.SoundId = id
		sonido.Volume = 0.5
		sonido.Parent = SoundService
		cache[clave] = sonido
	end

	sonido:Play()
end

return Sfx
