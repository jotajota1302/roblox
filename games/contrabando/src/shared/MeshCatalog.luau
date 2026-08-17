--!strict
--[[
	MeshCatalog.luau — los modelos 3D generados con Cube 3D, por su id de asset.

	Por qué existe el fichero: los meshes se generan UNA vez desde Studio y luego
	viven en la nube de Roblox por su id. Sin este catálogo, esos ids sólo
	existirían dentro del `.rbxl` -- que es un artefacto desechable que se
	reconstruye desde `src/` en cada compilación -- y se perderían al primer
	`rojo build`. Aquí están en git, revisables en un diff, igual que el resto.

	DECORACIÓN, NO GEOMETRÍA DE JUEGO. Ninguna distancia, colisión ni regla depende
	de estos modelos: el mundo jugable siguen siendo las losas de WorldBuilder. Si
	un id deja de cargar, el juego queda feo y sigue funcionando igual -- que es
	justo la garantía que hace seguro añadir arte a un prototipo cuyo propósito es
	medir el bucle.
]]

export type Modelo = {
	mesh: string,
	textura: string,
	-- Tamaño con el que se planta en el mundo. El generador devuelve el suyo
	-- propio manteniendo proporciones, así que este es el que manda.
	tamano: Vector3,
}

local MeshCatalog = {}

MeshCatalog.ALMACEN = {
	mesh = "rbxassetid://86350586534714",
	textura = "rbxassetid://108531948020878",
	tamano = Vector3.new(52, 34, 40),
} :: Modelo

MeshCatalog.TALLER = {
	mesh = "rbxassetid://135952229092945",
	textura = "rbxassetid://104409087804710",
	tamano = Vector3.new(34, 22, 34),
} :: Modelo

MeshCatalog.FURGONETA = {
	mesh = "rbxassetid://85055487487148",
	textura = "rbxassetid://71208068029418",
	tamano = Vector3.new(9, 7, 16),
} :: Modelo

MeshCatalog.CAJA = {
	mesh = "rbxassetid://72663440882404",
	textura = "rbxassetid://99381330613789",
	tamano = Vector3.new(5, 4, 4),
} :: Modelo

return MeshCatalog
