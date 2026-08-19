--!strict
--[[
	Rastro.luau — decide QUÉ PÍLDORAS VES TÚ.

	POR QUÉ EXISTE, y lo dijo JJ en cuanto lo jugó: *"los cuadraditos que salen,
	aunque suene el sonido al cogerlos, no desaparecen, y no deberían salir hasta
	que haya cargado algo para entregar"*.

	Las dos mitades de esa frase son el mismo fallo. El servidor plantaba las 140
	piezas de las CUATRO rutas y las dejaba encendidas para todo el mundo, así que:

	  · al recoger una, desaparecía esa y seguían a la vista las otras 139 -- de ahí
	    la sensación de que no desaparecen;
	  · y se veía el rastro de la roja yendo por la verde, que no es que sobre: es
	    que **estorba**. La fila de luces sólo dice "por aquí" si hay UNA fila.

	La visibilidad de un recogible es información de JUGADOR, no del mundo, y por eso
	se decide aquí y no en el servidor: dos personas en rutas distintas tienen que
	ver cosas distintas mirando al mismo sitio. El servidor sólo marca cuáles están
	gastadas (atributo `apagada`) y de qué ruta es cada una.

	SE VEN CUANDO HAY ALGO QUE ENTREGAR. Sin carga no hay viaje, y sin viaje el
	rastro no guía a ninguna parte -- encenderlo sería decorar la ciudad con premios
	que no cuentan (`ContactService` ya sólo los cobra con misión activa, así que
	además engañaría).
]]

local Rastro = {}

local piezas: { BasePart } = {}
local mundoVisto: Instance? = nil

-- Se recogen del mundo una vez y se recuerdan. Volver a recorrer el workspace
-- cuatro veces por segundo para encontrar 140 piezas fijas sería tirar el
-- rendimiento del cliente por algo que no cambia.
local function reunir()
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo == nil or mundo == mundoVisto then
		return
	end
	mundoVisto = mundo
	piezas = {}
	for _, d in mundo:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "^Contacto_") then
			table.insert(piezas, d)
		end
	end
end

function Rastro.actualizar(estado: any)
	reunir()
	if #piezas == 0 then
		return
	end

	local ruta = estado and estado.ruta
	local llevaAlgo = estado ~= nil and estado.cajas ~= nil and #estado.cajas > 0
	local hayViaje = ruta ~= nil and llevaAlgo

	for _, pieza in piezas do
		-- Y sólo LAS DE TU RUTA. Es lo que convierte 140 luces sueltas en un camino.
		local mia = hayViaje and pieza:GetAttribute("ruta") == ruta
		local gastada = pieza:GetAttribute("apagada") == true
		local visible = mia and not gastada
		local quiero = if visible then 0 else 1
		-- Sólo se escribe si cambia: asignar Transparency a 140 piezas cuatro veces
		-- por segundo cuesta, y no cambiar nada cuesta cero.
		if pieza.Transparency ~= quiero then
			pieza.Transparency = quiero
		end
	end
end

return Rastro
