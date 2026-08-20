--!strict
--[[
	Senales.luau — decide QUÉ VES TÚ del viaje: las píldoras y las luces.

	POR QUÉ EXISTE, y las dos veces lo dijo JJ jugando:

	  · *"los cuadraditos que salen, aunque suene el sonido al cogerlos, no
	    desaparecen, y no deberían salir hasta que haya cargado algo"*;
	  · *"me sobran las luces esas hasta el cielo, no sé dónde tengo que ir, y los
	    enemigos aparecen de repente y no los veo a distancia"*.

	Son el mismo fallo contado dos veces, y medirlo lo dejó claro: el mundo encendía
	a la vez **140 píldoras de las cuatro rutas y 14 columnas de luz**, todas
	visibles desde la puerta de casa. Cuatro balizas de destino de 300 studs, seis
	faroles de guarida, dos faros de refugio.

	El problema no era que faltara señalización: es que sobraba y **competía consigo
	misma**. Cuatro balizas encendidas no dicen a dónde ir, dicen que hay cuatro
	sitios. Y con catorce columnas en pantalla, el pilar del ladrón --70 studs, la
	señal que de verdad hay que ver-- no destacaba: de ahí "aparecen de repente".

	LA REGLA ES UNA: **se enciende lo que te sirve AHORA, y lo demás se apaga.** Y
	tiene que decidirse en el cliente porque depende de TU estado -- dos personas en
	rutas distintas miran al mismo sitio y tienen que ver cosas distintas.

	Lo que queda encendido durante un viaje: tu rastro, la baliza de tu destino, y
	los peligros de tu ruta. De catorce columnas a tres o cuatro.
]]

local Senales = {}

local piezas: { BasePart } = {}
local zonas: { BasePart } = {}
local lineas: { BasePart } = {}

-- Cada farol de guarida con la ruta de SU guarida. El farol no lleva el atributo
-- (es una pieza aparte), pero comparte índice con ella: `GuaridaFarol_3` alumbra
-- `Guarida_3`. Se resuelve una vez al reunir y no en cada vuelta del bucle.

local mundoVisto: Instance? = nil

-- Se recogen del mundo una vez y se recuerdan. Volver a recorrer el workspace
-- cuatro veces por segundo para encontrar piezas que no se mueven sería tirar el
-- rendimiento del cliente por nada.
local function reunir()
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo == nil or mundo == mundoVisto then
		return
	end
	mundoVisto = mundo
	piezas, zonas, lineas = {}, {}, {}

	for _, d in mundo:GetDescendants() do
		local indice = string.match(d.Name, "^Guarida_(%d+)$")
		if indice ~= nil then
			local r = d:GetAttribute("ruta")
			if typeof(r) == "string" then
				rutaDeGuarida[indice] = r
			end
		end
	end

	for _, d in mundo:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		if string.find(d.Name, "^Contacto_") then
			table.insert(piezas, d)
		elseif d:GetAttribute("zonaFichada") == true then
			table.insert(zonas, d)
		elseif d:GetAttribute("lineaDeRuta") == true then
			table.insert(lineas, d)
		end
		-- Balizas, faroles y faros ya no existen: el 19/08 se quitó del mapa todo lo
		-- vertical, a petición de JJ y con el argumento que lo cierra -- los puntos
		-- importantes ya salen en el mapa pequeño, así que una columna en pantalla no
		-- añadía información, sólo tapaba el camino.
		--
		-- Lo único que este módulo enciende y apaga son las MIGAS DE PAN, que es lo
		-- que marca la ruta.
	end
end

-- Encender y apagar es mover la transparencia, y sólo si cambia: escribirla en
-- ciento y pico piezas cuatro veces por segundo cuesta, y no cambiar nada no.
local function pintar(pieza: BasePart, visible: boolean, opacidad: number)
	local quiero = if visible then opacidad else 1
	if pieza.Transparency ~= quiero then
		pieza.Transparency = quiero
	end
end

function Senales.actualizar(estado: any)
	reunir()

	local ruta = estado and estado.ruta
	local llevaAlgo = estado ~= nil and estado.cajas ~= nil and #estado.cajas > 0
	-- HAY VIAJE cuando tienes destino y algo que llevar. Es la misma condición con
	-- la que el servidor cobra los contactos, así que encender fuera de ella sería
	-- enseñar premios que no cuentan.
	local hayViaje = ruta ~= nil and llevaAlgo

	-- LAS PÍLDORAS: sólo las de tu ruta, y sólo las que no estén gastadas. Es lo
	-- que convierte 140 luces sueltas en un camino.
	for _, pieza in piezas do
		local mia = hayViaje and pieza:GetAttribute("ruta") == ruta
		pintar(pieza, mia and pieza:GetAttribute("apagada") ~= true, 0)
	end

	-- LA LÍNEA DE TU RUTA, y sólo la tuya. Cuatro líneas pintadas a la vez serían
	-- cuatro caminos y ninguno: es la misma razón por la que sólo se encienden tus
	-- migas.
	for _, linea in lineas do
		pintar(linea, hayViaje and linea:GetAttribute("ruta") == ruta, 0)
	end

	-- LAS ZONAS FICHADAS, sólo mientras llevas algo. Sin carga no te fichan --el
	-- detector no dispara-- así que pintarlas sería enseñar un peligro que no existe,
	-- y el jugador aprendería a ignorarlas justo antes de que empiecen a importar.
	--
	-- TODAS y no sólo las de tu ruta, al contrario que las migas: una esquina fichada
	-- te ve pasar lleves el destino que lleves, y esconder las de las otras rutas sería
	-- mentir sobre el mapa. Es la diferencia entre una señal que te guía --que sí es
	-- tuya-- y un peligro, que es de la ciudad.
	for _, zona in zonas do
		-- Cada una recuerda su propia opacidad: el área es un tinte (0,9) y el foco del
		-- centro va marcado (0,45). Pintarlas todas igual borraba la diferencia entre
		-- "por aquí te ven" y "aquí está el ojo".
		local suya = zona:GetAttribute("opacidad")
		pintar(zona, llevaAlgo, if typeof(suya) == "number" then suya else 0.9)
	end
end

return Senales
