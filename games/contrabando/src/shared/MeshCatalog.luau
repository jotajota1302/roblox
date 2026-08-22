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

-- Regenerada: el primer intento se subió mal y su id devolvía siempre "Failed to
-- load mesh asset" mientras los otros tres del mismo lote cargaban. Que un asset
-- del catálogo pueda estar roto sin previo aviso es justo el motivo de que cada
-- elemento del decorado tenga su respaldo de piezas por separado.
MeshCatalog.FURGONETA = {
	mesh = "rbxassetid://137254300257491",
	textura = "rbxassetid://85512227994280",
	tamano = Vector3.new(9, 7, 16),
} :: Modelo

-- LA CARROCERIA DEL COCHE, y es la primera pieza del catalogo que NO es decorado:
-- va encima de algo que se conduce. Sigue sin sostener ninguna regla --lo que choca
-- es el chasis, lo que rueda son los cilindros-- asi que la garantia de arriba se
-- mantiene entera: si el id deja de cargar, el coche vuelve a ser una caja roja y se
-- conduce exactamente igual.
--
-- SALIO FURGONETA PIDIENDO UN COCHE, y se queda: un juego de contrabando con una
-- furgoneta de reparto se lee solo, y ademas casa con lo que el jugador lleva
-- haciendo cien entregas.
--
-- ES LA SEGUNDA GENERACION, Y LA PRIMERA NO SE TIRO POR FEA SINO POR SUS
-- PROPORCIONES. Salio 4,70 x 3,60 x 7,49 --una furgoneta CORTA-- y al llevarla a los
-- 12 studs del chasis quedaba tan estrecha que las ruedas parecian de monster truck
-- asomando por fuera. Se vio en una captura, no discutiendo: `screen_capture`
-- responde en `Edit`, y montar las dos versiones juntas y mirarlas cuesta un minuto.
--
-- Y EL TAMANO NO ES LA ESCALA UNIFORME DEL GENERADOR, a proposito. Cube 3D devuelve
-- la caja casi cuadrada de seccion (4,35 de ancho por 4,40 de alto) y un coche de
-- verdad es MAS ANCHO QUE ALTO: ensancharlo y aplanarlo no es deformar el modelo, es
-- corregir una proporcion que ya venia mal. Lo que decide el ancho final es que la
-- carroceria tape las ruedas -- 7,6 contra una via que acaba en 7,5.
MeshCatalog.COCHE = {
	mesh = "rbxassetid://120095376977599",
	textura = "rbxassetid://113548294711188",
	tamano = Vector3.new(7.6, 5, 13),
} :: Modelo

MeshCatalog.CAJA = {
	mesh = "rbxassetid://72663440882404",
	textura = "rbxassetid://99381330613789",
	tamano = Vector3.new(5, 4, 4),
} :: Modelo

return MeshCatalog
