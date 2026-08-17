--!strict
--[[
	RideCatalog.luau — los modelos 3D de los vehículos, por id.

	VIVEN COMO IDS EN EL CÓDIGO, no como un fichero binario. Es la diferencia con
	el mapa, y no es casual: el mapa tuvo que entrar como `.rbxm` porque
	`InsertService:LoadAsset` no carga assets de otra cuenta, pero
	`AssetService:CreateMeshPartAsync` SÍ funciona con mallas ajenas -- probado en
	este mismo juego. Así que aquí basta con anotar el id y todo queda en git,
	legible en un diff y sin pasos manuales.

	CÓMO SE ELIGIERON, que es lo que importa de verdad:

	Sólo entran mallas (`MeshPart`), nunca modelos con scripts. Un `MeshPart` es
	geometría y no puede llevar código; un `Model` del Toolbox sí, y ahí está el
	problema. El primer pack de vehículos que se probó traía un script llamado
	`CoreSkyboxSystem` que se presentaba como cargador de texturas y hacía tres
	cosas: autodestruirse si detectaba Studio (`game.JobId == ""`, o sea no correr
	nunca mientras el desarrollador mira), guardarse un asset id escondido en una
	propiedad, y hacer `require()` de él -- descargar y ejecutar código remoto en el
	servidor. Es el patrón exacto con el que se roban juegos en Roblox.

	LA REGLA, sin excepciones: **ningún modelo del Toolbox entra con un solo script
	dentro**. Un vehículo no necesita código.

	Y como toda malla, necesitan respaldo: sin el place publicado no se descarga
	ninguna, así que `Ride` monta sus piezas cuando esto falla. El juego tiene que
	quedar reconocible sin ellas.
]]

export type Modelo = {
	mesh: string,
	textura: string?,
	-- Medida en studs. Los originales vienen a escalas absurdas -- el coche medía
	-- 50 studs de largo y la moto 3 -- así que la medida de juego se fija aquí y no
	-- se hereda del autor.
	tamano: Vector3,
	-- Desplazamiento respecto al centro del personaje y giro en grados. Cada autor
	-- modela mirando hacia donde le parece, y sin esto la mitad van de lado.
	offset: Vector3,
	giroY: number,
	-- Color de respaldo para las mallas sin textura (el coche viene en gris).
	color: Color3?,
}

local RideCatalog = {}

RideCatalog.MODELOS = {
	-- Los cuatro pequeños están GENERADOS con Cube 3D, no sacados del Toolbox, y
	-- ésa es la diferencia que importa: los genera Roblox, así que no pueden traer
	-- código, pasan la moderación solos y son de la cuenta de JJ. Es la vía que
	-- este proyecto debería preferir siempre que el resultado valga -- y aquí
	-- valió, porque no había mallas limpias decentes de patines ni de patinete.
	patines = {
		mesh = "rbxassetid://85333403995294",
		textura = "rbxassetid://121874462881181",
		tamano = Vector3.new(2.4, 1.6, 2.6),
		offset = Vector3.new(0, -2.6, 0),
		giroY = 0,
	},
	monopatin = {
		mesh = "rbxassetid://136682752722782",
		textura = "rbxassetid://85379852016686",
		tamano = Vector3.new(1.8, 0.9, 4.4),
		offset = Vector3.new(0, -2.9, 0),
		giroY = 0,
	},
	patinete = {
		mesh = "rbxassetid://119645081769748",
		textura = "rbxassetid://71699102265311",
		tamano = Vector3.new(1.6, 3.8, 4.6),
		-- Bajo y algo retrasado: colocado al centro, el manillar le quedaba al
		-- conductor a la altura del pecho y la plataforma por delante de los pies.
		offset = Vector3.new(0, -2, -0.7),
		giroY = 0,
	},
	patinete_electrico = {
		mesh = "rbxassetid://118747264146015",
		textura = "rbxassetid://116829806666752",
		tamano = Vector3.new(1.8, 4, 5),
		offset = Vector3.new(0, -1.9, -0.7),
		giroY = 0,
	},
	bicicleta = {
		mesh = "rbxassetid://475108790",
		textura = "rbxassetid://475108895",
		tamano = Vector3.new(2, 4, 6),
		offset = Vector3.new(0, -1.4, 0),
		giroY = 0,
	},
	moto = {
		mesh = "rbxassetid://7951986269",
		textura = "rbxassetid://7951986376",
		tamano = Vector3.new(2.2, 3, 6.5),
		offset = Vector3.new(0, -1.9, 0),
		giroY = 0,
	},
	coche = {
		mesh = "rbxassetid://3906462734",
		tamano = Vector3.new(5.5, 4.5, 11),
		offset = Vector3.new(0, -1.2, 0),
		giroY = 0,
		color = Color3.fromRGB(196, 84, 62),
	},
	furgoneta = {
		mesh = "rbxassetid://18341462777",
		tamano = Vector3.new(6, 6, 12),
		offset = Vector3.new(0, -0.6, 0),
		giroY = 0,
		color = Color3.fromRGB(214, 216, 220),
	},
} :: { [string]: Modelo }

function RideCatalog.get(vehiculoId: string?): Modelo?
	if vehiculoId == nil then
		return nil
	end
	return RideCatalog.MODELOS[vehiculoId]
end

return RideCatalog
