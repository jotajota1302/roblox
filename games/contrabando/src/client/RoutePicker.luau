--!strict
--[[
	RoutePicker.luau — los tres destinos con su precio, al salir del almacén.

	Es la pantalla donde se toma la decisión central del juego, así que enseña el
	multiplicador y la distancia SIN adornos: la elección tiene que poder hacerse
	de un vistazo, no leyendo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))
local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

-- Cuántas guaridas hay PLANTADAS de verdad en esa ruta. Se cuentan del mundo y no
-- se da por bueno el número del diseño: una guarida se omite si no encuentra suelo
-- transitable donde caer, y un selector que promete dos cuando hay una está
-- mintiendo justo en el dato por el que se elige.
local function guaridasDe(rutaId: string): number
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo == nil then
		return (select(2, Routes.amenazas(rutaId)))
	end
	local n = 0
	for _, pieza in mundo:GetChildren() do
		if pieza:IsA("BasePart") and pieza:GetAttribute("guarida") == true and pieza:GetAttribute("ruta") == rutaId then
			n += 1
		end
	end
	return n
end

local RoutePicker = {}
local gui: ScreenGui? = nil
local tarjetas: { [string]: TextButton } = {}

function RoutePicker.build(alElegir: (string) -> (), alCerrar: () -> ())
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "SelectorRuta"
	pantalla.ResetOnSpawn = false
	pantalla.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	pantalla.Enabled = false
	pantalla.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Velo, para que las tarjetas se lean sobre cualquier fondo. A 0,45 dejaba la
	-- pantalla casi negra y el jugador no veía ni su propio personaje: parecía que
	-- había desaparecido. A 0,72 se sigue viendo el mundo -- y sobre todo se ve
	-- DÓNDE estás, que es parte de lo que se decide aquí.
	local velo = Instance.new("Frame")
	velo.Name = "Velo"
	velo.Size = UDim2.fromScale(1, 1)
	velo.Position = UDim2.fromScale(0, 0)
	velo.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	velo.BackgroundTransparency = 0.72
	velo.BorderSizePixel = 0
	velo.ZIndex = 0
	velo.Parent = pantalla

	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	-- A 0,24 y no más abajo: el panel de estado sigue visible bajo el velo (a
	-- propósito, porque el dinero y la carga son justo lo que se mira para
	-- decidir) y ocupa la esquina superior izquierda hasta el 26 % de la altura.
	-- Un título más bajo o más ancho se le monta encima.
	titulo.AnchorPoint = Vector2.new(0.5, 1)
	titulo.Position = UDim2.fromScale(0.6, 0.24)
	titulo.Size = UDim2.fromScale(0.52, 0.11)
	titulo.BackgroundTransparency = 1
	titulo.TextColor3 = UiKit.PAPEL
	titulo.TextScaled = true
	titulo.Font = Enum.Font.GothamBold
	titulo.TextStrokeTransparency = 0.5
	titulo.Text = Strings.get("PICKER_TITLE")
	titulo.ZIndex = 2
	titulo.Parent = pantalla

	local tituloSize = Instance.new("UISizeConstraint")
	tituloSize.MaxSize = Vector2.new(380, 46)
	tituloSize.Parent = titulo

	local fila = Instance.new("Frame")
	fila.AnchorPoint = Vector2.new(0.5, 0.5)
	fila.Position = UDim2.fromScale(0.5, 0.52)
	fila.Size = UDim2.fromScale(0.9, 0.34)
	fila.BackgroundTransparency = 1
	fila.ZIndex = 2
	fila.Parent = pantalla

	-- Declaradas ANTES del layout que las usa: en Lua un nombre usado antes de
	-- existir como local se resuelve como global nil, y `UDim.new(nil, 0)` revienta.
	-- Este proyecto ya pagó ese error dos veces (en CargoService y en el cierre a
	-- mano del selector), así que aquí va dicho.
	local cuantas = #Routes.todas()
	local separacion = 0.02

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(separacion, 0)
	-- Por LayoutOrder, no por nombre. Con el orden por defecto los botones salían
	-- alfabéticos -- AMBAR, ROJA, VERDE -- y el gradiente de riesgo, que es lo
	-- único que esta pantalla tiene que comunicar de un vistazo, quedaba
	-- desordenado: el x10 en el centro y el seguro a la derecha.
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = fila

	-- EL ANCHO SE REPARTE, no se cablea. Con tres rutas cabían tres tarjetas de
	-- 0,3 y una separación de 0,02 (0,94 en total); al entrar el barrio pasaron a
	-- ser cuatro y la suma se fue a 1,26 -- y un UIListLayout horizontal NO encoge
	-- a sus hijos, los deja salirse. El día que se añada una quinta ruta, esto
	-- sigue funcionando solo.
	local anchoTarjeta = (1 - separacion * math.max(cuantas - 1, 0)) / math.max(cuantas, 1)

	for orden, ruta in Routes.todas() do
		local boton = Instance.new("TextButton")
		boton.Name = ruta.id
		boton.LayoutOrder = orden
		boton.ZIndex = 2
		boton.Size = UDim2.fromScale(anchoTarjeta, 1)
		boton.BackgroundColor3 = Palette.ruta(ruta.id)
		boton.AutoButtonColor = true
		-- El texto va en tres etiquetas hijas, no en una cadena con saltos de
		-- línea. Con TextScaled sobre tres líneas, Roblox reduce todo al tamaño
		-- que le cabe a la más larga y las tres acaban pesando lo mismo -- pero el
		-- multiplicador es la cifra por la que se elige, y tiene que dominar la
		-- tarjeta. Separarlas es la única forma de darle su propio tamaño.
		boton.Text = ""
		boton.Parent = fila
		tarjetas[ruta.id] = boton
		UiKit.redondear(boton, 14)
		-- Borde grueso en vez de sombra: estas tarjetas viven dentro de un
		-- UIListLayout, que reparte el espacio entre todos sus hijos, y una sombra
		-- sería un hijo más (ver UiKit.sombra, que por eso se niega a crearla
		-- aquí). El borde da la misma separación del fondo sin tocar el reparto.
		UiKit.borde(boton, UiKit.oscurecer(Palette.ruta(ruta.id), 0.3), 4)
		UiKit.volumen(boton, 0.22)
		UiKit.margen(boton, 8)

		local pila = Instance.new("UIListLayout")
		pila.FillDirection = Enum.FillDirection.Vertical
		pila.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pila.VerticalAlignment = Enum.VerticalAlignment.Center
		pila.SortOrder = Enum.SortOrder.LayoutOrder
		pila.Parent = boton

		local function texto(
			nombre: string,
			orden: number,
			alto: number,
			contenido: string,
			fuente: Enum.Font,
			opacidad: number
		)
			local t = Instance.new("TextLabel")
			t.Name = nombre
			t.LayoutOrder = orden
			t.Size = UDim2.fromScale(1, alto)
			t.BackgroundTransparency = 1
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.TextTransparency = opacidad
			t.TextScaled = true
			t.Font = fuente
			t.TextStrokeTransparency = 0.55
			t.Text = contenido
			t.ZIndex = 2
			t.Parent = boton
			return t
		end

		texto("Nombre", 1, 0.24, Routes.nombre(ruta.id), Enum.Font.GothamMedium, 0.15)
		texto("Multiplicador", 2, 0.5, Routes.paga(ruta.id), Enum.Font.GothamBlack, 0)
		-- Distancia Y vigilancia. La distancia sola bastaba cuando las tres rutas
		-- eran la misma recta: elegir era decidir cuánto andabas. Con zonas de
		-- verdad, lo que separa la roja de la verde es CUÁNTA POLICÍA hay, y sin
		-- ese dato aquí la decisión se toma a ciegas y el jugador aprende a base
		-- de perder cargas. En palabras y no en símbolos: los caracteres decorados
		-- salen como cuadrados en TextLabel.
		-- QUÉ HAY POR EL CAMINO, en números. Antes decía la distancia y una palabra
		-- ("peligrosa"), y con eso elegir ruta seguía siendo elegir un
		-- multiplicador a ciegas: nadie sabe qué significa "peligrosa" hasta que le
		-- cuesta una carga. Las esquinas fichadas y las guaridas son lo que de
		-- verdad se compra al elegir, y ahora además se ven en el mapa -- así que
		-- el número de aquí y los círculos de allí dicen lo mismo.
		local fichadas = (Routes.amenazas(ruta.id))
		local madrigueras = guaridasDe(ruta.id)
		texto(
			"Detalle",
			3,
			0.2,
			-- math.floor y no %d a secas: en Luau, formatear un float con %d revienta
			-- ("number has no integer representation") y la cadena sale con los
			-- catorce decimales -- "212.4923553466797m", que es lo que se vio en
			-- pantalla. La distancia es una magnitud, así que casi nunca es entera.
			string.format(
				"%dm  ·  %d hotspots  ·  %d dens",
				math.floor(Routes.distancia(ruta.id) + 0.5),
				fichadas,
				madrigueras
			),
			Enum.Font.GothamMedium,
			0.35
		)

		local size = Instance.new("UISizeConstraint")
		size.MinSize = Vector2.new(90, 96)
		-- Y un techo: sin él, en un portátil de 1365x768 cada botón salía de
		-- 368x261 px, con el texto a un tamaño de cartel. No es sólo feo — un
		-- elemento que ocupa un tercio de la pantalla tapa el mundo justo cuando
		-- el jugador quiere mirar hacia dónde va a salir.
		size.MaxSize = Vector2.new(260, 190)
		size.Parent = boton

		boton.Activated:Connect(function()
			alElegir(ruta.id)
			RoutePicker.ocultar()
		end)
	end

	-- Se puede cerrar sin elegir. Parece un detalle y no lo es: hasta ahora esta
	-- pantalla no tenía salida, así que llegar a la salida con carga te obligaba a
	-- irte de viaje aunque hubieras venido a otra cosa -- a mirar el mapa, a
	-- pensártelo, o a volver al taller. Una decisión que no se puede posponer deja
	-- de ser una decisión.
	local cerrar = Instance.new("TextButton")
	cerrar.Name = "Cerrar"
	cerrar.AnchorPoint = Vector2.new(0.5, 0)
	cerrar.Position = UDim2.fromScale(0.5, 0.76)
	cerrar.Size = UDim2.fromScale(0.24, 0.13)
	cerrar.BackgroundColor3 = Color3.fromRGB(52, 52, 58)
	cerrar.TextColor3 = UiKit.APAGADO
	cerrar.TextScaled = true
	cerrar.Font = Enum.Font.GothamMedium
	cerrar.Text = Strings.get("PICKER_NOT_NOW")
	cerrar.AutoButtonColor = true
	cerrar.ZIndex = 2
	cerrar.Parent = pantalla
	UiKit.redondear(cerrar, 8)
	UiKit.borde(cerrar, Color3.fromRGB(86, 86, 94), 2)
	UiKit.margen(cerrar, 6)

	local cerrarSize = Instance.new("UISizeConstraint")
	cerrarSize.MinSize = Vector2.new(120, 44)
	cerrarSize.MaxSize = Vector2.new(200, 56)
	cerrarSize.Parent = cerrar

	cerrar.Activated:Connect(function()
		RoutePicker.ocultar()
		alCerrar()
	end)

	gui = pantalla
end

-- Pinta el candado. La regla NO se decide aquí: se pregunta a Routes, que es el
-- mismo módulo que aplica el servidor. Dos copias de "¿puedo salir por aquí?"
-- acaban discrepando, y el día que discrepen el jugador verá una tarjeta
-- encendida que al pulsarla no hace nada -- que es exactamente lo que este
-- selector vino a quitar.
--
-- Y LA TARJETA BLOQUEADA SIGUE PULSÁNDOSE. Es deliberado: el servidor contesta
-- con lo que falta ("Te falta nivel: Nivel 8 y vehículo de motor"), y esa frase
-- vale más que un botón muerto. Además así hay una sola fuente de la verdad.
function RoutePicker.actualizar(estado: any)
	if estado == nil then
		return
	end
	local nivel = estado.nivel or 1
	for id, boton in tarjetas do
		-- Con los hitos: la verde está cerrada hasta la primera entrega, y el
		-- selector tiene que decirlo. Pinta, no decide -- el servidor vuelve a
		-- comprobarlo cuando se pulsa.
		local puede = Routes.disponible(id, nivel, estado.vehiculo, estado.hitos)
		local color = Palette.ruta(id)
		boton.BackgroundColor3 = if puede then color else UiKit.oscurecer(color, 0.62)
		local detalle = boton:FindFirstChild("Detalle") :: TextLabel?
		local multiplicador = boton:FindFirstChild("Multiplicador") :: TextLabel?
		if detalle then
			local fichadas = (Routes.amenazas(id))
			local madrigueras = guaridasDe(id)
			detalle.Text = if puede
				then Strings.get(
					"PICKER_DETAIL",
					{ metros = Routes.distancia(id), fichadas = fichadas, guaridas = madrigueras }
				)
				-- Lo que falta DE VERDAD, sabiendo lo que ya tiene: una vez hecho el
				-- hito, lo que falta vuelve a ser el nivel. Sin esto, la verde diría
				-- "entrega tu primer paquete" para siempre.
				else Routes.requisitoPara(id, estado.hitos)
			detalle.TextTransparency = if puede then 0.35 else 0
		end
		if multiplicador then
			-- El ×10 apagado es la promesa: se ve lo que hay detrás del candado.
			multiplicador.TextTransparency = if puede then 0 else 0.45
		end
	end
end

function RoutePicker.mostrar()
	if gui then
		gui.Enabled = true
	end
end

function RoutePicker.ocultar()
	if gui then
		gui.Enabled = false
	end
end

return RoutePicker
