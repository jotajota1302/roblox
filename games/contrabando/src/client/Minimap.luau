--!strict
--[[
	Minimap.luau — la ciudad vista desde arriba, con el plano de verdad.

	La primera versión eran puntos de colores flotando en un cuadro negro, y JJ dio
	con el problema exacto: "que se vea el plano de la ciudad, si no no sirve para
	mucho". Tenía razón, y el motivo es de diseño, no estético. Un punto azul a
	ochenta metros no dice si puedes llegar: la respuesta cambia por completo según
	haya una calle o una manzana de edificios en medio, y **esa es justo la decisión
	que el mapa tiene que ayudar a tomar** cuando te persiguen. La dirección ya la
	da la brújula; lo que aporta un mapa es el obstáculo.

	CÓMO SE DIBUJA UN PLANO SIN NINGÚN ASSET. Una textura del mapa sería un asset
	subido, y un asset no carga con el place sin publicar -- la trampa que ya nos
	dejó sin avatar y sin decorado. Así que el plano se construye con Frames leyendo
	la ciudad directamente (está replicada al cliente), UNA sola vez al arrancar.

	Y el truco que lo hace barato: los cientos de rectángulos se pintan en un LIENZO
	grande que no se toca nunca más; lo que se mueve en cada refresco es el lienzo
	entero, un único Frame, dentro de un marco recortado. Mover 500 hijos sesenta
	veces por segundo mataría un móvil de gama baja; mover a su padre no cuesta nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Grid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Grid"))
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))
local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

-- Píxeles por stud. Con un marco de 150 px se ven unos 680 studs de lado: la
-- manzana en la que estás y las dos de al lado. Más alcance convierte cada
-- edificio en un punto de dos píxeles y el plano deja de leerse; menos, y ya no
-- ves a dónde vas.
-- Subió de 0,22 a 0,45 con el mapa nuevo. La escala vieja era para una ciudad de
-- 1.600 studs; con 610, el plano entero ocupaba un tercio del panel y el resto era
-- negro -- que es lo que se veía en la captura de JJ: un recuadro claro en una esquina
-- y él, el punto blanco, fuera de él.
-- Ya no hay escala fija: el plano se dibuja en fracción del panel y por eso cabe
-- entero en cualquier pantalla. La constante desapareció con el lienzo móvil.

-- Sólo se pintan las piezas que aportan silueta. Un plano con las 7161 partes de
-- la ciudad sería una mancha gris, además de tardar en construirse.
local MINIMO_LADO = 14

local Minimap = {}
local marco: Frame? = nil
local lienzo: Frame? = nil
local puntos: { [string]: any } = {}
local estado: any = nil
local origenMapa = Vector2.new(0, 0)
local tamanoMapa = Vector2.new(1, 1)

-- DONDE SE ENTREGA DE VERDAD. El plano marcaba el CRUCE, y desde que se entrega
-- dentro de la vivienda eso son cincuenta y cinco studs de diferencia -- lo justo
-- para plantarte donde dice el mapa y no ver ninguna puerta.
--
-- Se lee del mundo, que ya esta replicado al cliente. Si no hubiera casa se cae al
-- cruce, que es lo que habia.
local function dondeSeEntrega(rutaId: string, porDefecto: Vector3): Vector3
	local mundo = workspace:FindFirstChild("Mundo")
	local casa = mundo and mundo:FindFirstChild("Vivienda_" .. rutaId)
	local mostrador = casa and casa:FindFirstChild("Mostrador") :: BasePart?
	return if mostrador then mostrador.Position else porDefecto
end

-- DEL MUNDO AL PANEL, en fracción y no en píxeles.
--
-- Antes el plano se dibujaba a una escala fija y era el LIENZO el que se movía para
-- centrarse en el jugador -- lo correcto cuando el mapa era mucho mayor que el panel.
-- Con una ciudad de 630 studs cabe entera, y verla entera vale más que verla de
-- cerca: se sabe dónde está uno, a dónde va y qué hay en medio de un vistazo, que es
-- justo lo que se le pide a un plano y lo que JJ echaba en falta.
--
-- En fracción, además, el plano encaja solo en cualquier pantalla sin recalcular nada.
local function aEscala(x: number, z: number): UDim2
	return UDim2.fromScale((x - origenMapa.X) / tamanoMapa.X, (z - origenMapa.Y) / tamanoMapa.Y)
end

local function punto(nombre: string, color: Color3, tamano: number, orden: number): Frame
	local p = puntos[nombre]
	if p and p.Parent then
		return p
	end
	local f = Instance.new("Frame")
	f.Name = nombre
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(tamano, tamano)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = orden
	f.Visible = false
	f.Parent = marco
	UiKit.redondear(f, tamano)
	puntos[nombre] = f
	return f
end

-- EL PLANO SE DIBUJA DESDE EL PLANO, no adivinándolo del mundo.
--
-- La versión anterior recorría la ciudad buscando `Model` hoja y pintaba su contorno.
-- Era lo único que se podía hacer contra un mapa del Creator Store: allí no había
-- ninguna descripción de la ciudad, sólo siete mil piezas, y había que deducir qué era
-- un edificio por su tamaño. Contra la retícula propia esa heurística no encuentra
-- NADA --nuestra ciudad son carpetas con piezas sueltas, sin un solo Model-- así que
-- el minimapa salía vacío salvo por los puntos de colores, descentrado, y JJ lo
-- resumió en cuatro palabras: "ese mapa no se entiende nada".
--
-- Ahora se dibuja lo que Grid dice que hay: asfalto claro de borde a borde y las doce
-- manzanas oscuras encima. Lo claro es por donde se pasa, que es la convención de
-- cualquier plano y no necesita leyenda. Trece rectángulos en vez de setecientos.
local function pintarPlano(_ciudad: Instance?, capa: Frame): Vector2
	-- SOLO LA CIUDAD. Nada de recinto.
	--
	-- Durante un tiempo el plano abarcaba tambien el poligono de casa, con un argumento
	-- razonable: el almacen esta FUERA de la reticula --el recinto va de Z 755 a 1005 y
	-- la ciudad acaba en 767-- asi que el jugador, que empieza y termina cada viaje en
	-- casa, quedaba fuera del dibujo.
	--
	-- Y salia caro, medido: el recinto son 250 studs de alto y 360 de ancho, asi que el
	-- plano pasaba a 631x702 y LA CIUDAD SE QUEDABA EN EL 66 % DEL ALTO. Ademas
	-- sobresale 21 studs por la izquierda, que es la banda oscura sin nada que JJ vio en
	-- su captura. Todo eso por dibujar un solar donde no hay nada que decidir.
	--
	-- Lo zanjo el mismo JJ: *"el mapa tiene que ser de la ciudad solo... claramente la
	-- ciudad, el objetivo y los enemigos, ya esta"*. Lo de quedarse fuera del plano no es
	-- un problema: `aPantalla` pega al borde lo que se sale, asi que mientras estas en
	-- casa tu punto se apoya arriba y en cuanto pisas la ciudad se mueve. Y volver a
	-- casa no necesita navegacion -- se entrega y el juego te lleva.
	local gx0, gx1, gz0, gz1 = Grid.limites()
	local xMin, xMax = gx0, gx1
	local zMin, zMax = gz0, gz1

	origenMapa = Vector2.new(xMin, zMin)
	tamanoMapa = Vector2.new(xMax - xMin, zMax - zMin)
	capa.Position = UDim2.fromScale(0, 0)
	capa.Size = UDim2.fromScale(1, 1)

	local function rect(nombre: string, x0: number, x1: number, z0: number, z1: number, color: Color3, orden: number)
		local r = Instance.new("Frame")
		r.Name = nombre
		r.Position = aEscala(x0, z0)
		r.Size = UDim2.fromScale((x1 - x0) / tamanoMapa.X, (z1 - z0) / tamanoMapa.Y)
		r.BorderSizePixel = 0
		r.BackgroundColor3 = color
		r.ZIndex = orden
		r.Parent = capa
	end

	-- El asfalto de la ciudad. Lo que no tape una manzana es calle: es la convención
	-- de cualquier plano --lo claro es por donde se pasa-- y no necesita leyenda.
	-- MAS CLARO QUE ANTES. En la captura del 20/08 el plano era una rejilla de
	-- cuadrados que apenas se distinguian del fondo del panel: *"no se ve nada"*. Lo
	-- que separa un plano legible de una mancha es el CONTRASTE entre lo que se pisa
	-- y lo que no, y 196 sobre un fondo de 22 no llegaba porque las manzanas (58) se
	-- comian el hueco. Asfalto casi blanco y manzanas casi negras.
	rect("Asfalto", gx0, gx1, gz0, gz1, Color3.fromRGB(224, 226, 232), 1)

	for col = 0, Grid.COLUMNAS - 1 do
		for fila = 0, Grid.FILAS - 1 do
			local x0, x1, z0, z1 = Grid.manzana(col, fila)
			rect(string.format("Manzana_%d_%d", col, fila), x0, x1, z0, z1, Color3.fromRGB(34, 36, 44), 2)
		end
	end

	return Vector2.new(xMin, zMin)
end

function Minimap.build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Minimapa"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Parent = gui

	-- ABAJO A LA DERECHA cuando se puede, que es donde lo pidió JJ y donde mejor
	-- está: fuera del camino de la vista y donde la mano ya descansa.
	--
	-- Pero en un dispositivo TÁCTIL esa esquina es el botón de salto de Roblox, que
	-- no podemos mover y que el jugador pulsa sin mirar. Medido en un Galaxy A06
	-- (705x338), un mapa ahí se come el salto y el botón de Recoger. Así que la
	-- posición depende de si hay controles táctiles en pantalla: en el móvil se va
	-- arriba, al único hueco que queda entre la brújula y la columna de acciones.
	-- Dar la razón al que pide y romperle el juego en su dispositivo no es darle la
	-- razón.
	if UserInputService.TouchEnabled then
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.fromScale(0.71, 0.03)
		panel.Size = UDim2.fromScale(0.16, 0.16)
	else
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.fromScale(0.98, 0.97)
		panel.Size = UDim2.fromScale(0.19, 0.26)
	end

	UiKit.redondear(panel, 8)
	UiKit.borde(panel, Color3.fromRGB(96, 94, 102), 1.5, 0.25)

	local tamano = Instance.new("UISizeConstraint")
	tamano.MinSize = Vector2.new(80, 80)
	tamano.MaxSize = Vector2.new(190, 190)
	tamano.Parent = panel

	local proporcion = Instance.new("UIAspectRatioConstraint")
	proporcion.AspectRatio = 1
	proporcion.Parent = panel

	local capa = Instance.new("Frame")
	capa.Name = "Plano"
	capa.AnchorPoint = Vector2.new(0, 0)
	capa.BackgroundTransparency = 1
	capa.Parent = panel
	lienzo = capa

	marco = panel

	-- Ya no espera a que exista la ciudad: el plano sale de Grid, que está en el
	-- cliente desde el primer fotograma. Antes, si el mapa tardaba en replicarse, el
	-- minimapa se quedaba vacío para siempre.
	origenMapa = pintarPlano(nil, capa)

	-- El jugador se mueve por el plano, y no al revés. Con el mapa entero a la vista,
	-- clavarlo en el centro obligaba a mover la ciudad debajo y eso escondía la mitad
	-- de lo que hace falta ver -- dónde está uno RESPECTO al destino, que es la única
	-- pregunta que se le hace a un plano mientras se corre.
	-- TU, COMO UNA FLECHA QUE MIRA. Eras un punto blanco de nueve pixeles, y un punto
	-- dice donde estas pero no hacia donde vas -- que es la mitad de la pregunta
	-- cuando lo que quieres saber es si estas yendo bien. En un GPS de coche el
	-- cursor SIEMPRE es una flecha, y no por gusto.
	--
	-- Es un triangulo hecho con un ImageLabel del propio cliente (`rbxasset://`, de
	-- los que no hay que publicar) y girado con la camara. Mas grande que antes: 16
	-- pixeles, porque el cursor es lo primero que hay que encontrar en el plano.
	local yo = puntos["Yo"]
	if yo == nil or yo.Parent == nil then
		local f = Instance.new("ImageLabel")
		f.Name = "Yo"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(18, 18)
		f.BackgroundTransparency = 1
		f.Image = "rbxasset://textures/ui/Controls/DirectionalIndicator.png"
		f.ImageColor3 = Color3.fromRGB(255, 255, 255)
		f.ZIndex = 9
		f.Parent = marco
		puntos["Yo"] = f :: any
		yo = f :: any
	end
	yo.Visible = true

	-- A 12 Hz, no en cada fotograma: los puntos se desplazan menos de un píxel
	-- entre fotogramas y esto tiene que ir en un móvil de gama baja.
	local reloj = 0
	RunService.Heartbeat:Connect(function(dt)
		reloj += dt
		if reloj < 1 / 12 then
			return
		end
		reloj = 0
		pcall(Minimap.refrescar)
	end)
end

-- LO FIJO SE PINTA EN EL LIENZO, UNA VEZ. Las esquinas fichadas y las guaridas no
-- se mueven jamás, así que dibujarlas en cada refresco sería pagar doce veces por
-- segundo por algo que no cambia. Van en la misma capa que el plano de la ciudad y
-- se mueven con él gratis.
--
-- POR QUÉ ESTÁN AQUÍ, que es lo importante: lo pidió JJ jugando y señalaba el
-- agujero exacto entre lo que el diseño prometía y lo que había. El rediseño de la
-- ciudad decía que la habilidad del juego sería reconocer el cruce malo y
-- rodearlo; con los peligros invisibles, eso sólo se podía aprender perdiendo la
-- carga. Un peligro que no se puede anticipar no es tensión, es un impuesto.
-- AQUI SE DIBUJABAN LAS ESQUINAS VIGILADAS Y LAS GUARIDAS: veintinueve nucleos, sus
-- discos de radio de 35 studs y los nucleos de las guaridas, todo a la vez sobre un
-- panel de 190x190 pixeles. Se fue con ellas la tabla que las guardaba.
--
-- Estaba bien pensado --el disco dice por donde NO pasar, que es lo que sirve para
-- trazar un camino-- y aun asi el resultado era ilegible, porque el plano acabo
-- teniendo siete familias de simbolo a la vez. *"Estan saliendo muchas cosas que no se
-- lo que son"*, y luego, cerrandolo: *"claramente la ciudad, el objetivo y los
-- enemigos, ya esta"*.
--
-- El peligro no se ha quedado sin representar: las esquinas vigiladas se pintan en el
-- SUELO, con su radio real y a tamano real, que es donde se decide si las rodeas.

-- EL CAMINO, DIBUJADO. Es lo que JJ pidio mirando el plano: *"con el mapa tan
-- sencillo el camino deberia mostrarlo el minimapa"*.
--
-- Y encaja con lo que el mapa ES desde que es nuestro: una reticula donde todo
-- destino esta a un giro o a ninguno. El camino en L de `Grid.porCalles` es EL mismo
-- que marcan las migas de pan en el suelo, asi que el plano y el mundo cuentan la
-- misma historia -- que es justo lo que fallaba antes, cuando el rastro dibujaba una
-- L y quien tiraba hacia el destino tomaba la otra.
--
-- Los tramos son horizontales o verticales SIEMPRE (van por calles), asi que se
-- dibujan como rectangulos y no hay que rotar nada.
local caminos: { Frame } = {}
local caminoDe: string? = nil
-- En STUDS, que luego se convierten a fraccion del panel. Con 12 salian tres pixeles
-- de linea sobre un panel de 190, que en un movil es no verse. 22 dan seis o siete y
-- se lee de un vistazo sin tapar la reticula de debajo.
local CAMINO_GRUESO = 22

-- LA RUTA VIVA, recalculada desde DONDE ESTAS.
--
-- Lo pidio JJ y describio exactamente lo que faltaba: *"el mapa de abajo deberia
-- ensenar el punto de entrega y la ruta dinamica hasta el, segun por donde decida
-- ir, asi no me pierdo, como si fuera un GPS del coche"*.
--
-- Lo que habia era una L fija de la puerta de casa al destino, calculada UNA vez.
-- Servia mientras no te desviaras, y en cuanto lo hacias no volvia a decir nada: la
-- linea seguia donde estaba y tu no. Un plano que solo acierta si vas por donde el
-- creia es una ilustracion, no una guia.
--
-- Se repinta cuando te has movido lo suficiente (`PASO_REPINTADO`) y no en cada
-- vuelta: son cuatro Frames destruidos y creados, y hacerlo doce veces por segundo
-- en un movil de gama baja se nota. Quince studs es menos de un carril, asi que la
-- linea nunca se queda visiblemente atras.
local PASO_REPINTADO = 15
local ultimoTrazado: Vector3? = nil

local function pintarCamino(capa: Frame, rutaId: string?, desde: Vector3, hasta: Vector3?)
	local mismaRuta = caminoDe == rutaId
	local cerca = ultimoTrazado ~= nil and (desde - (ultimoTrazado :: Vector3)).Magnitude < PASO_REPINTADO
	if mismaRuta and cerca and #caminos > 0 then
		return
	end
	caminoDe = rutaId
	ultimoTrazado = desde
	for _, f in caminos do
		f:Destroy()
	end
	caminos = {}
	if rutaId == nil or hasta == nil then
		return
	end

	local tramos = Grid.rutaGps(desde, hasta)
	local color = Palette.ruta(rutaId)
	for i = 2, #tramos do
		local a, b = tramos[i - 1], tramos[i]
		local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
		local z0, z1 = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
		if (x1 - x0) < 1 and (z1 - z0) < 1 then
			continue
		end
		local anchoX = math.max(x1 - x0, CAMINO_GRUESO)
		local anchoZ = math.max(z1 - z0, CAMINO_GRUESO)
		local f = Instance.new("Frame")
		f.Name = string.format("Camino_%s_%d", rutaId, i)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = aEscala((x0 + x1) / 2, (z0 + z1) / 2)
		f.Size = UDim2.fromScale(anchoX / tamanoMapa.X, anchoZ / tamanoMapa.Y)
		f.BackgroundColor3 = color
		-- OPACA Y POR ENCIMA DEL PLANO: esta linea ya no acompana a ninguna guia, ES
		-- la guia, y una guia no puede ser lo mas tenue del panel.
		f.BackgroundTransparency = 0
		f.BorderSizePixel = 0
		f.ZIndex = 3
		f.Parent = capa
		table.insert(caminos, f)
	end
end

function Minimap.actualizar(nuevo: any)
	estado = nuevo
end

-- Del mundo al marco, con el jugador en el centro. Devuelve además si el sitio
-- cae DENTRO del trozo visible: lo que se sale no se borra, se pega al borde
-- apuntando hacia dónde queda -- que es lo que hace un radar y lo que un plano
-- recortado, por sí solo, no haría.
-- Dónde cae un sitio del mundo dentro del panel. `centro` y `lado` ya no se usan --se
-- conservan en la firma porque los llamadores los pasan-- desde que el plano es fijo:
-- la posición de algo en el mapa no depende de dónde esté mirando el jugador.
local function aPantalla(_centro: Vector3, sitio: Vector3, _lado: number): (UDim2, boolean)
	local fx = (sitio.X - origenMapa.X) / tamanoMapa.X
	local fz = (sitio.Z - origenMapa.Y) / tamanoMapa.Y
	local dentro = fx >= 0 and fx <= 1 and fz >= 0 and fz <= 1
	-- Lo que se sale del plano se pega al borde en vez de desaparecer: un ladrón
	-- fuera del mapa sigue siendo información, y saber por qué lado viene basta.
	return UDim2.fromScale(math.clamp(fx, 0.02, 0.98), math.clamp(fz, 0.02, 0.98)), dentro
end

function Minimap.refrescar()
	local panel = marco
	local capa = lienzo
	if not panel or not capa then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		panel.Visible = false
		return
	end
	panel.Visible = true

	local centro = root.Position
	local lado = panel.AbsoluteSize.X

	-- El lienzo ya no se mueve: el mapa entero está siempre a la vista y lo que se
	-- mueve son los puntos. Un mapa de 630 studs cabe en el panel, así que centrarlo
	-- en el jugador sólo servía para esconderle la mitad de lo que necesita ver.

	-- Y el jugador, en su sitio del plano.
	local yo = puntos["Yo"]
	if yo then
		-- GIRADA HACIA DONDE MIRA LA CAMARA, y AQUI y no en `build`: build corre una
		-- sola vez, asi que la flecha se quedaba clavada en la orientacion que tuviera
		-- al arrancar la partida. Medido girando la camara a los cuatro puntos
		-- cardinales: cero grados en los cuatro. Una flecha que no gira es un punto
		-- gordo, y para eso ya estaba el punto.
		--
		-- La camara y no el personaje: lo que el jugador entiende por "hacia delante"
		-- es lo que tiene en pantalla.
		local cam = workspace.CurrentCamera
		if cam and yo:IsA("ImageLabel") then
			local mira = cam.CFrame.LookVector
			-- El plano tiene el norte arriba, o sea -Z hacia arriba: el angulo sale de
			-- atan2 con la Z invertida, o la flecha giraria al reves.
			yo.Rotation = math.deg(math.atan2(mira.X, -mira.Z))
		end
		-- CON `aPantalla` Y NO CON `aEscala`, que es la diferencia entre verse y no
		-- verse. El plano es SOLO la ciudad, y el almacen esta fuera de la reticula
		-- --250 studs mas al sur-- asi que estando en casa tu punto caia en Y=1,09,
		-- fuera del panel, y el panel recorta a sus hijos: desaparecias.
		--
		-- O sea que no te veias a ti mismo en el sitio donde EMPIEZA Y TERMINA CADA
		-- VIAJE. La cabecera de `pintarPlano` ya describia el comportamiento correcto
		-- --*"tu punto se apoya arriba y en cuanto pisas la ciudad se mueve"*-- y lo
		-- atribuia a `aPantalla`; lo que faltaba era usarla aqui.
		yo.Position = (aPantalla(centro, centro, lado))
		yo.Visible = true
	end

	local rutaEnCurso = estado and estado.ruta

	-- El camino que estas haciendo, por debajo de todo lo demas.
	local metaDeRuta = if rutaEnCurso ~= nil
		then (function(): Vector3?
			local ok, suya = pcall(Routes.get, rutaEnCurso)
			return if ok and suya then dondeSeEntrega(rutaEnCurso, suya.destino) else nil
		end)()
		else nil
	pintarCamino(capa, rutaEnCurso, centro, metaDeRuta)

	-- SIN EL PUNTO DE CASA. Estaba fuera del plano desde que el plano es solo la
	-- ciudad, asi que lo unico que hacia era pegarse al borde de arriba y competir con
	-- lo que si hay que mirar. Y no se navega hacia casa: se entrega y el juego te lleva.

	local rutaActiva = estado and estado.ruta

	-- LA ZONA DE ENTREGA, CON HALO. Lo pidio JJ jugando: *"lo que si marcaria mejor es
	-- la zona de entrega, donde esta en el mapa, porque puedes ir por otro camino y te
	-- pierdes"*. Y es exactamente el caso que el resto del sistema no cubre: el rastro
	-- del suelo y la linea del plano dibujan UN camino, y en cuanto te sales de el --por
	-- un atajo, por rodear a un ladron, porque te has despistado-- lo unico que queda es
	-- un punto de nueve pixeles entre otros dos iguales.
	--
	-- El halo va DEBAJO del punto y es cuatro veces mas ancho: se ve desde el otro lado
	-- del plano y no tapa nada, porque lo que hay debajo es la retícula. Solo el de tu
	-- ruta, claro -- tres halos serian tres sitios y ninguno.
	local halo = punto("HaloDestino", Color3.fromRGB(255, 255, 255), 34, 4)
	if rutaActiva ~= nil then
		local ok, suya = pcall(Routes.get, rutaActiva)
		if ok and suya ~= nil then
			halo.BackgroundColor3 = Palette.ruta(rutaActiva)
			halo.BackgroundTransparency = 0.55
			halo.Position = (aPantalla(centro, dondeSeEntrega(rutaActiva, suya.destino), lado))
			halo.Visible = true
		else
			halo.Visible = false
		end
	else
		halo.Visible = false
	end

	for _, ruta in Routes.todas() do
		local p = punto("Destino_" .. ruta.id, Palette.ruta(ruta.id), 9, 5)
		p.Position = (aPantalla(centro, dondeSeEntrega(ruta.id, ruta.destino), lado))
		-- CON VIAJE, SOLO EL TUYO. Los tres a la vez estaban bien mientras el plano
		-- servia para elegir --saber donde cae cada zona es la decision de la valla--
		-- pero en cuanto sales ya has decidido, y entonces los otros dos solo compiten
		-- con el unico que importa. *"La ciudad, el objetivo y los enemigos"*: el
		-- objetivo, en singular.
		--
		-- Sin ruta se ensenan los tres, que es cuando de verdad hay algo que comparar.
		local mio = rutaActiva == ruta.id
		p.Size = if mio then UDim2.fromOffset(14, 14) else UDim2.fromOffset(8, 8)
		p.Visible = rutaActiva == nil or mio
	end

	local vistos: { [string]: boolean } = {}

	-- LOS REFUGIOS YA NO SE PINTAN AQUI, y con ellos se fueron las esquinas vigiladas.
	-- El plano llego a tener a la vez: la reticula, el recinto, tres destinos, tres
	-- refugios, veintinueve nucleos de esquina vigilada, sus discos de radio y el
	-- jugador. JJ lo miro y dijo lo que se ve: *"estan saliendo muchas cosas que no se
	-- lo que son"* -- y no era falta de leyenda, era exceso de dibujo. Un plano de
	-- 190x190 pixeles no admite siete familias de simbolo.
	--
	-- Se queda con lo que contesta a las tres preguntas del viaje: donde estoy, a donde
	-- voy y quien viene a por mi. *"Claramente la ciudad, el objetivo y los enemigos, ya
	-- esta"*.

	-- La gente: TODOS, con carga o sin ella. Saber que hay alguien cerca es media
	-- decisión en la ruta roja, y esconder a los que van vacíos escondería
	-- justamente a los cazadores.
	for _, otro in Players:GetPlayers() do
		if otro ~= Players.LocalPlayer then
			local suyo = otro.Character and otro.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if suyo then
				local clave = "Jugador_" .. otro.UserId
				local p = punto(clave, Color3.fromRGB(240, 220, 120), 9, 7)
				local donde, dentro = aPantalla(centro, suyo.Position, lado)
				p.Position = donde
				p.Visible = dentro
				vistos[clave] = true
			end
		end
	end

	-- Y quien te persigue, que es el dato por el que se mira el mapa cuando aprieta:
	-- no "dónde voy" sino "por dónde vienen".
	local patrullas = workspace:FindFirstChild("Patrullas")
	if patrullas then
		for i, agente in patrullas:GetChildren() do
			local sitio = agente:GetPivot().Position
			local donde, dentro = aPantalla(centro, sitio, lado)

			-- SU ZONA DE INFLUENCIA, no sólo el punto. Es la mitad de lo que se
			-- pide a un mapa cuando aprieta: no "dónde está" sino "hasta dónde
			-- llega". El radio es la distancia a la que el juego ya te avisa de que
			-- lo tienes detrás, así que el círculo dibuja exactamente el momento en
			-- que dejas de poder ignorarlo.
			local aura = punto("Aura_" .. i, Color3.fromRGB(255, 110, 100), 1, 6)
			local lo = Config.ALERTA_DISTANCIA * 2 / tamanoMapa.X
			aura.Size = UDim2.fromOffset(lo, lo)
			aura.BackgroundTransparency = 0.82
			aura.Position = donde
			aura.Visible = dentro
			-- Redonda del todo. punto() ya le puso una esquina, pero con el radio del
			-- tamaño con el que nació (un píxel), y aquí el tamaño se recalcula en cada
			-- refresco: si el radio no es relativo, el aura sale cuadrada -- y un
			-- cuadrado no se lee como un alcance.
			local redondo = aura:FindFirstChildOfClass("UICorner")
			if redondo then
				redondo.CornerRadius = UDim.new(1, 0)
			end
			vistos["Aura_" .. i] = true

			local clave = "Patrulla_" .. i
			local p = punto(clave, Color3.fromRGB(255, 110, 100), 9, 7)
			p.Position = donde
			-- LOS DE FUERA DEL MARCO SE PEGAN AL BORDE en vez de desaparecer. Un
			-- ladrón que no se ve porque queda a cincuenta metros del recuadro es
			-- justo el que te va a alcanzar: esconderlo es esconder el dato por el
			-- que se mira el mapa.
			p.Size = if dentro then UDim2.fromOffset(9, 9) else UDim2.fromOffset(6, 6)
			p.BackgroundTransparency = if dentro then 0 else 0.3
			p.Visible = true
			vistos[clave] = true
		end
	end

	-- Los que ya no están se apagan, no se destruyen: crear y borrar Frames doce
	-- veces por segundo es la forma más fácil de que un minimapa cueste más que el
	-- juego que representa.
	for clave, p in puntos do
		local esVolatil = string.sub(clave, 1, 8) == "Jugador_"
			or string.sub(clave, 1, 9) == "Patrulla_"
			or string.sub(clave, 1, 5) == "Aura_"
			or string.sub(clave, 1, 8) == "Refugio_"
		if esVolatil and not vistos[clave] then
			p.Visible = false
		end
	end
end

return Minimap
