--!strict
--[[
	Telemetry.luau — medición propia desde el primer día.

	Roblox sólo da analítica a partir de 100 jugadores diarios; por debajo vamos a
	ciegas. Y el dato más valioso no es cuánta gente entra, sino DÓNDE ABANDONA:
	si todos se van durante el primer viaje, el problema es el viaje, y ninguna
	cantidad de contenido nuevo lo arregla.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Telemetry = {}
local entradas: { [Player]: number } = {}

-- Roblox sólo acepta tres campos personalizados por evento, y con estas claves
-- exactas. Se toman los tres primeros por orden alfabético para que el mismo
-- evento mande siempre los mismos campos: sin orden fijo, la tabla de Lua los
-- entregaría en un orden distinto cada vez y las columnas del panel saldrían
-- mezcladas entre sí.
local CLAVES_ROBLOX = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

function Telemetry.evento(player: Player, nombre: string, datos: { [string]: any }?)
	local partes = { string.format("t=%d jugador=%d evento=%s", os.time(), player.UserId, nombre) }
	local claves: { string } = {}
	if datos then
		for clave in datos do
			table.insert(claves, clave)
		end
		table.sort(claves)
		for _, clave in claves do
			table.insert(partes, string.format("%s=%s", clave, tostring(datos[clave])))
		end
	end

	-- A la consola: es lo único que se ve en Studio y durante las pruebas.
	print("[TELEMETRIA] " .. table.concat(partes, " "))

	-- Y al servicio de Roblox, que es lo único que sobrevive a un servidor
	-- publicado: los print de un servidor en producción no los lee nadie, así que
	-- toda la medición que justifica este módulo se perdía justo cuando empezaba a
	-- importar. Va dentro de pcall y sólo fuera de Studio -- sin place publicado
	-- el servicio lanza, y ninguna medición vale un servidor caído.
	if RunService:IsStudio() then
		return
	end
	pcall(function()
		local campos: { [string]: any } = {}
		if datos then
			for i, clave in claves do
				if i > #CLAVES_ROBLOX then
					break
				end
				-- "clave:valor", no el valor a secas: el panel de Roblox sólo
				-- enseña "customField01", así que un "roja" suelto no dice si es
				-- la ruta o cualquier otra cosa.
				campos[CLAVES_ROBLOX[i]] = clave .. ":" .. tostring(datos[clave])
			end
		end
		AnalyticsService:LogCustomEvent(player, nombre, 1, campos)
	end)
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
