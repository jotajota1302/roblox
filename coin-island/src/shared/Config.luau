--!strict
--[[
	Config.luau — TODOS los números del juego en un solo sitio.

	Está en ReplicatedStorage, que es la carpeta que ven TANTO el servidor COMO el cliente.
	Regla mental de Roblox:
	  · ServerScriptService  -> solo el servidor. El jugador no puede leerlo. Aquí van los secretos.
	  · ReplicatedStorage    -> lo ven los dos. Aquí van datos compartidos y los "Remotes".
	  · StarterPlayerScripts -> se copia al jugador al entrar. Aquí va el código del cliente.

	Un fichero .luau (sin sufijo) se convierte en un ModuleScript: código que otros
	scripts cargan con require(). Devuelve una tabla al final.
]]

export type Upgrade = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number,
	maxLevel: number,
	perLevel: number,
}

local Config = {
	-- ── Mundo ──────────────────────────────────────────────────────────────
	ARENA_SIZE = 140, -- lado del suelo cuadrado, en studs (1 stud ≈ 28 cm)

	-- ── Monedas ────────────────────────────────────────────────────────────
	COIN_COUNT = 30, -- cuántas monedas hay a la vez en el mapa
	COIN_VALUE = 1, -- cuánto suma cada moneda
	COIN_RESPAWN_SECONDS = 3, -- cuánto tarda en reaparecer una moneda recogida

	-- ── Personaje ──────────────────────────────────────────────────────────
	BASE_WALK_SPEED = 16, -- valor por defecto de Roblox
	BASE_JUMP_POWER = 50, -- valor por defecto de Roblox

	-- ── Mejoras de la tienda ───────────────────────────────────────────────
	-- El coste de subir al nivel N es: baseCost * (N + 1)
	UPGRADES = {
		{
			id = "speed",
			displayName = "Botas ligeras",
			description = "+2 de velocidad por nivel",
			baseCost = 10,
			maxLevel = 5,
			perLevel = 2,
		},
		{
			id = "jump",
			displayName = "Muelles de sal",
			description = "+8 de salto por nivel",
			baseCost = 15,
			maxLevel = 5,
			perLevel = 8,
		},
		{
			id = "magnet",
			displayName = "Imán de bolsillo",
			description = "Atrae monedas a 6 studs por nivel",
			baseCost = 25,
			maxLevel = 4,
			perLevel = 6,
		},
	} :: { Upgrade },

	-- ── Monetización ───────────────────────────────────────────────────────
	-- Ambos son 0 = desactivados. Para activarlos hay que PUBLICAR el juego y
	-- crear el pase/producto en la web de Roblox. Ver README, sección 6.
	GAME_PASS_ID = 0, -- pase "x2 monedas" (compra única, permanente)
	PRODUCT_ID = 0, -- producto "+100 monedas" (compra repetible)

	GAME_PASS_MULTIPLIER = 2,
	PRODUCT_COIN_REWARD = 100,

	-- ── Persistencia ───────────────────────────────────────────────────────
	DATASTORE_NAME = "CoinIsland_PlayerData_v1", -- si cambias el esquema, sube el v1 a v2
	AUTOSAVE_SECONDS = 120,
}

--[[
	Ayuda: busca una mejora por su id. Devuelve nil si no existe.
	El servidor la usa para NO fiarse del id que manda el cliente.
]]
function Config.findUpgrade(id: string): Upgrade?
	for _, upgrade in Config.UPGRADES do
		if upgrade.id == id then
			return upgrade
		end
	end
	return nil
end

--[[ Coste de pasar de `currentLevel` al siguiente. ]]
function Config.upgradeCost(upgrade: Upgrade, currentLevel: number): number
	return upgrade.baseCost * (currentLevel + 1)
end

return Config
