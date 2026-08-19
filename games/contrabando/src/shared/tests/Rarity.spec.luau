--!strict
local Config = require(script.Parent.Parent.Config)
local Rarity = require(script.Parent.Parent.Rarity)

return function(kit)
	-- Las probabilidades tienen que sumar 1: si suman menos, la cola se pierde y
	-- la rareza más valiosa no sale nunca; si suman más, sale de más.
	local suma = 0
	for _, def in Config.RAREZAS do
		suma += def.probabilidad
	end
	kit.near("las probabilidades suman uno", suma, 1, 0.0001)

	-- Con semilla fija la tirada es determinista, así que se puede probar de verdad.
	local rng = Random.new(1302)
	local conteo = { comun = 0, marcada = 0, sellada = 0, legendaria = 0 }
	for _ = 1, 10000 do
		local id = Rarity.tirada(rng)
		conteo[id] = (conteo[id] or 0) + 1
	end

	kit.eq(
		"todas las tiradas dan una rareza valida",
		conteo.comun + conteo.marcada + conteo.sellada + conteo.legendaria,
		10000
	)
	kit.truthy("la comun domina", conteo.comun > conteo.marcada)
	kit.truthy("la marcada supera a la sellada", conteo.marcada > conteo.sellada)
	kit.truthy("la legendaria es la mas rara", conteo.legendaria < conteo.sellada)
	-- Con 2% esperado en 10.000 tiradas, salirse de 100-350 sería un fallo del reparto.
	kit.truthy("la legendaria sale, pero poco", conteo.legendaria > 100 and conteo.legendaria < 350)

	kit.eq("una rareza tiene su multiplicador", Rarity.def("legendaria").multiplicador, 135)
	kit.falsy("la comun no llama la atencion", Rarity.esLlamativa("comun"))
	kit.truthy("la legendaria si", Rarity.esLlamativa("legendaria"))

	kit.errors("una rareza inventada revienta", function()
		Rarity.def("diamante")
	end)

	-- QUÉ es cada cosa, no sólo de qué color. Antes todo era la misma caja marrón y
	-- una legendaria de x135 se veía igual que una común de x1: llevar algo dejaba
	-- de significar nada, que es de donde vive la tensión de la ruta roja.
	local vistas: { [string]: boolean } = {}
	for _, id in { "comun", "marcada", "sellada", "legendaria" } do
		local a = Rarity.aspecto(id)
		-- El nombre ya no vive en el aspecto: sale de Strings ("RARITY_" .. id).
		-- Lo que se comprueba es que la etiqueta que se lee salga entera.
		kit.truthy("la rareza " .. id .. " tiene etiqueta", string.find(Rarity.etiqueta(id), "x") ~= nil)
		kit.falsy("y no se repite con otra", vistas[a.forma] == true)
		vistas[a.forma] = true
	end

	-- Y no todas miden igual: la silueta es lo que las distingue de lejos, antes de
	-- que se pueda leer la etiqueta.
	kit.truthy(
		"la urna es mas alta que ancha",
		Rarity.aspecto("legendaria").escala.Y > Rarity.aspecto("legendaria").escala.X
	)
	kit.truthy("y el maletin al reves", Rarity.aspecto("marcada").escala.Y < Rarity.aspecto("marcada").escala.X)

	-- La etiqueta lleva el multiplicador, que es el número con el que se decide si
	-- compensa cargar con ello.
	kit.truthy("la etiqueta dice cuanto multiplica", string.find(Rarity.etiqueta("legendaria"), "x135") ~= nil)

	-- Y NO revienta con un id desconocido, aunque Rarity.def sí lo haga: esto lo
	-- llama el dibujado de una pieza, y una etiqueta mal formada no puede llevarse
	-- por delante el bucle que dibuja las demás.
	kit.truthy("una rareza inventada no tumba la etiqueta", type(Rarity.etiqueta("diamante")) == "string")
end
