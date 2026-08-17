--!strict
--[[
	Telemetry.luau — medición propia desde el primer día.

	Roblox sólo da analítica a partir de 100 jugadores diarios; por debajo vamos a
	ciegas. Y el dato más valioso no es cuánta gente entra, sino DÓNDE ABANDONA:
	si todos se van durante el primer viaje, el problema es el viaje, y ninguna
	cantidad de contenido nuevo lo arregla.
]]

local Players = game:GetService("Players")

local Telemetry = {}
local entradas: { [Player]: number } = {}

function Telemetry.evento(player: Player, nombre: string, datos: { [string]: any }?)
	local partes = { string.format("t=%d jugador=%d evento=%s", os.time(), player.UserId, nombre) }
	if datos then
		for clave, valor in datos do
			table.insert(partes, string.format("%s=%s", clave, tostring(valor)))
		end
	end
	-- De momento a la consola del servidor. Cuando haya tráfico real, este print se
	-- sustituye por un envío a un endpoint; el resto del código no se entera.
	print("[TELEMETRIA] " .. table.concat(partes, " "))
end

function Telemetry.start()
	Players.PlayerAdded:Connect(function(player)
		entradas[player] = os.time()
		Telemetry.evento(player, "entrada")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local inicio = entradas[player]
		entradas[player] = nil
		Telemetry.evento(player, "salida", {
			segundos = if inicio then os.time() - inicio else 0,
		})
	end)
end

return Telemetry
