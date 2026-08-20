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
local puntos: { [string]: Frame } = {}
local estado: any = nil
local origenMapa = Vector2.new(0, 0)
local tamanoMapa = Vector2.new(1, 1)

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
	-- EL PLANO INCLUYE EL RECINTO, no sólo la ciudad.
	--
	-- La primera versión dibujaba únicamente la retícula, y el almacén está FUERA de
	-- ella: el recinto ocupa de Z 755 a 1005 y el mapa acaba en 767. O sea que el
	-- jugador, que empieza y termina cada viaje en casa, aparecía fuera del plano --
	-- y como el lienzo se centra en él, el mapa se iba a una esquina del panel. Es
	-- exactamente lo que se veía en la captura: un recuadro claro descolgado arriba a
	-- la derecha y el punto blanco en ninguna parte.
	local cx, cz, tx, tz =
		Config.POLIGONO_CENTRO.X, Config.POLIGONO_CENTRO.Z, Config.POLIGONO_TAMANO.X, Config.POLIGONO_TAMANO.Y
	local rx0, rx1 = cx - tx / 2, cx + tx / 2
	local rz0, rz1 = cz - tz / 2, cz + tz / 2

	local gx0, gx1, gz0, gz1 = Grid.limites()
	local xMin, xMax = math.min(gx0, rx0), math.max(gx1, rx1)
	local zMin, zMax = math.min(gz0, rz0), math.max(gz1, rz1)

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
	rect("Asfalto", gx0, gx1, gz0, gz1, Color3.fromRGB(196, 198, 204), 1)

	for col = 0, Grid.COLUMNAS - 1 do
		for fila = 0, Grid.FILAS - 1 do
			local x0, x1, z0, z1 = Grid.manzana(col, fila)
			rect(string.format("Manzana_%d_%d", col, fila), x0, x1, z0, z1, Color3.fromRGB(58, 62, 74), 2)
		end
	end

	-- Y el recinto, en su propio tono: es tuyo, no es ciudad, y saber dónde queda casa
	-- es la mitad de orientarse.
	rect("Recinto", rx0, rx1, rz0, rz1, Color3.fromRGB(120, 104, 66), 1)

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
	local yo = punto("Yo", Color3.fromRGB(255, 255, 255), 9, 8)
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
local peligrosPintados = false

-- CADA PELIGRO CON SU RUTA Y SU PAPEL, para poder darles pesos distintos.
--
-- El plano ensenaba los 29 detectores de las tres rutas con su disco de radio 35
-- entero, y eso es lo que JJ describio mirandolo: *"en el minimapa estan saliendo
-- muchas cosas que no se lo que son"*. Tenia razon -- veintinueve discos de 35 studs
-- sobre un mapa de 610 no dicen por donde no pasar, dicen que la ciudad es naranja.
--
-- LA PRIMERA VERSION DE ESTE ARREGLO ESCONDIA LOS DE LAS OTRAS RUTAS, y estaba mal.
-- Se vio yendo a mirar el servidor en vez de suponerlo: `HeatService` recorre TODOS
-- los detectores sin filtrar por ruta, asi que una esquina ambar te ficha igual
-- aunque vayas a la verde. Ocultarla habria hecho un plano legible y MENTIROSO, que
-- es peor que uno recargado: el jugador confia en el, cruza por donde el mapa dice
-- que no hay nada, y le sube el calor sin explicacion.
--
-- Asi que se ensenan todos y lo que cambia es el PESO: de tu ruta, el disco entero
-- --por donde no pasar-- y de las demas solo el nucleo, un punto de 7 studs que dice
-- "aqui hay ojos" sin tapar el plano. La informacion esta toda; la que estorba, no.
local peligros: { { marco: Frame, ruta: string?, disco: boolean } } = {}

local function pintarPeligros(capa: Frame)
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo == nil or peligrosPintados then
		return
	end

	local function mancha(
		nombre: string,
		centro: Vector3,
		radio: number,
		color: Color3,
		opacidad: number,
		orden: number
	)
		local f = Instance.new("Frame")
		f.Name = nombre
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = aEscala(centro.X, centro.Z)
		f.Size = UDim2.fromScale(radio * 2 / tamanoMapa.X, radio * 2 / tamanoMapa.Y)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = opacidad
		f.BorderSizePixel = 0
		f.ZIndex = orden
		f.Parent = capa
		local redondo = Instance.new("UICorner")
		redondo.CornerRadius = UDim.new(1, 0)
		redondo.Parent = f
		return f
	end

	local fichadas, madrigueras = 0, 0
	for _, pieza in mundo:GetChildren() do
		if not pieza:IsA("BasePart") then
			continue
		end
		if pieza:GetAttribute("detectorId") ~= nil then
			-- SU RADIO DE VERDAD, no un punto. Un punto dice dónde está; el círculo
			-- dice por dónde NO pasar, que es lo único que sirve para trazar un
			-- camino. Es el mismo número que usa el servidor para dispararlas.
			-- MUY TENUE, y con un núcleo encima. El disco a 0,72 tapaba media retícula:
			-- son 35 studs de radio sobre un mapa de 630, o sea un 11 % del ancho cada
			-- uno, y hay treinta. Con el mapa entero a la vista eso deja de informar y
			-- pasa a ser una mancha naranja donde estaba la ciudad.
			--
			-- El disco sigue diciendo por dónde NO pasar --que es lo que sirve para
			-- trazar un camino-- y el núcleo dice dónde está exactamente.
			local disco = mancha(
				"Fichada_" .. pieza.Name,
				pieza.Position,
				Config.DETECTOR_RADIO,
				Color3.fromRGB(255, 170, 60),
				0.88,
				2
			)
			local nucleo =
				mancha("FichadaNucleo_" .. pieza.Name, pieza.Position, 7, Color3.fromRGB(255, 170, 60), 0.15, 3)
			local suya = pieza:GetAttribute("ruta")
			local deQuien = if typeof(suya) == "string" then suya else nil
			table.insert(peligros, { marco = disco, ruta = deQuien, disco = true })
			table.insert(peligros, { marco = nucleo, ruta = deQuien, disco = false })
			fichadas += 1
		elseif pieza:GetAttribute("guarida") == true then
			-- SU ALCANCE VA COMO ANILLO, NO COMO MANCHA. Es la distancia a la que esa
			-- guarida puede soltarte un ladrón encima (Config.GUARIDA_ALCANCE), y son
			-- 260 studs: seis discos de ese tamaño pintarían el mapa entero de rojo y
			-- no se distinguiría nada, que es justo lo contrario de lo que se le pide
			-- a un plano. El anillo dice lo mismo y deja ver lo que hay debajo.
			-- SIN ANILLO DE ALCANCE. Dibujaba los 250 studs a los que esa guarida puede
			-- soltarte un ladrón, y en la ciudad prestada --de 1.600 studs-- eso era un
			-- arco fino que informaba. En un mapa de 610 son casi el mapa entero: seis
			-- guaridas pintaban la maraña de arcos marrones que JJ vio y resumió con
			-- "ese mapa no se entiende nada". Queda el núcleo, que es lo que hay que
			-- rodear.
			-- Y el núcleo, que es lo que se ve de lejos y lo que hay que rodear.
			-- La guarida no lleva ruta: es un sitio de la ciudad y de ahi sale un ladron
			-- vayas a donde vayas. Se ensena siempre.
			mancha("GuaridaNucleo_" .. pieza.Name, pieza.Position, 20, Color3.fromRGB(220, 70, 60), 0.25, 3)
			madrigueras += 1
		end
	end

	-- Sólo se da por pintado cuando había algo que pintar: si el mundo todavía no
	-- ha replicado al cliente, hay que volver a intentarlo en el siguiente refresco
	-- en vez de quedarse con un mapa sin peligros para toda la partida.
	if fichadas > 0 or madrigueras > 0 then
		peligrosPintados = true
	end
end

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

local function pintarCamino(capa: Frame, rutaId: string?)
	if caminoDe == rutaId and #caminos > 0 then
		return
	end
	caminoDe = rutaId
	for _, f in caminos do
		f:Destroy()
	end
	caminos = {}
	if rutaId == nil then
		return
	end
	local ok, ruta = pcall(Routes.get, rutaId)
	if not ok or ruta == nil then
		return
	end

	local tramos = Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino)
	local color = Palette.ruta(rutaId)
	for i = 2, #tramos do
		local a, b = tramos[i - 1], tramos[i]
		local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
		local z0, z1 = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
		-- LOS TRAMOS DE LONGITUD CERO NO SE DIBUJAN. El camino en L de una ruta RECTA
		-- --la verde va derecha al sur-- tiene el segundo tramo vacio, porque la esquina
		-- coincide con el destino. Pintarlo dejaba un cuadradito de tres pixeles clavado
		-- encima de la diana: no informa de nada y parece suciedad. Medido jugando.
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
		-- Por debajo de los peligros y de los puntos: es el fondo sobre el que se lee
		-- todo lo demas, no algo que competir con ellos.
		f.BackgroundTransparency = 0.45
		f.BorderSizePixel = 0
		f.ZIndex = 1
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
		yo.Position = aEscala(centro.X, centro.Z)
		yo.Visible = true
	end

	-- Los peligros fijos, en cuanto el mundo haya llegado al cliente. Se protege
	-- sola: en cuanto pinta algo, no vuelve a hacer nada.
	pintarPeligros(capa)

	local rutaEnCurso = estado and estado.ruta
	-- SIN VIAJE NO SE ENSENA NINGUNO: los detectores no disparan sin carga --lo
	-- comprueba el servidor antes de mirar distancias-- asi que pintarlos seria
	-- ensenar un peligro que no existe, y el jugador aprenderia a ignorarlos justo
	-- antes de que empiecen a importar. Es la misma regla que `Senales` aplica en 3D.
	--
	-- Con viaje: el disco entero solo el de tu ruta; de las demas, el nucleo.
	for _, p in peligros do
		if rutaEnCurso == nil then
			p.marco.Visible = false
		elseif p.disco then
			p.marco.Visible = p.ruta == nil or p.ruta == rutaEnCurso
		else
			p.marco.Visible = true
		end
	end

	-- El camino que estas haciendo, por debajo de todo lo demas.
	pintarCamino(capa, rutaEnCurso)

	local casa = punto("Almacen", Palette.ALMACEN, 10, 4)
	casa.Position = (aPantalla(centro, Config.ALMACEN_POS, lado))
	casa.Visible = true

	local rutaActiva = estado and estado.ruta
	for _, ruta in Routes.todas() do
		local p = punto("Destino_" .. ruta.id, Palette.ruta(ruta.id), 9, 5)
		p.Position = (aPantalla(centro, ruta.destino, lado))
		-- El de tu ruta, más grande: es el que persigues y tiene que distinguirse
		-- de un vistazo entre los tres.
		p.Size = if rutaActiva == ruta.id then UDim2.fromOffset(14, 14) else UDim2.fromOffset(8, 8)
		p.Visible = true
	end

	local vistos: { [string]: boolean } = {}

	-- Los refugios, SIEMPRE visibles y pegados al borde si se salen. Es lo que se
	-- busca cuando la cosa se pone fea, y hay que haberlos visto antes de
	-- necesitarlos: cuando los necesitas, ya es tarde para aprendértelos.
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo then
		for _, pieza in mundo:GetChildren() do
			if pieza:IsA("BasePart") and pieza:GetAttribute("refugio") == true then
				local clave = "Refugio_" .. pieza.Name
				local p = punto(clave, Color3.fromRGB(120, 180, 255), 11, 6)
				local donde, dentro = aPantalla(centro, pieza.Position, lado)
				p.Position = donde
				-- Los de fuera de alcance, más pequeños y translúcidos: siguen
				-- diciendo por dónde caen sin competir con los que sí puedes
				-- alcanzar ahora mismo.
				p.Size = if dentro then UDim2.fromOffset(11, 11) else UDim2.fromOffset(7, 7)
				p.BackgroundTransparency = if dentro then 0 else 0.35
				p.Visible = true
				vistos[clave] = true
			end
		end
	end

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
