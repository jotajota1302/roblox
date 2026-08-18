--!strict
--[[
	Main.client.luau — arranque del cliente.

	El cliente NO tiene lógica de juego: pide su estado, lo dibuja y manda
	intenciones. Es el servidor quien decide si esas intenciones valen.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local Routes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routes"))
local Perimeter = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Perimeter"))
local Compass = require(script.Parent:WaitForChild("Compass"))
local Garage = require(script.Parent:WaitForChild("Garage"))
local Gate = require(script.Parent:WaitForChild("Gate"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Menu = require(script.Parent:WaitForChild("Menu"))
local Minimap = require(script.Parent:WaitForChild("Minimap"))
local RoutePicker = require(script.Parent:WaitForChild("RoutePicker"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Stock = require(script.Parent:WaitForChild("Stock"))

-- La carpeta del mundo la crea el servidor al arrancar, así que puede no existir
-- todavía cuando este script empieza. Se espera con un tope: sin ella el juego
-- sigue funcionando (sólo que el selector no aparecería), y colgarse para siempre
-- esperando algo que quizá no llega es peor que seguir sin ello.
local mundo = workspace:WaitForChild("Mundo", 20) :: Instance?

-- Cada pantalla se construye por su cuenta y protegida, igual que los servicios
-- del servidor. LA RAZÓN, pagada: una excepción a mitad de Hud.build() (un
-- Color3 fuera de rango en un degradado) se llevó por delante el resto del
-- script -- HUD a medias, selector de ruta que nunca llegó a existir, y ni un
-- error visible en la pantalla del jugador. Un fallo en el adorno de un botón no
-- puede costar el selector de ruta, que es donde se juega la partida.
local function construir(nombre: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Contrabando] no se pudo construir " .. nombre .. ": " .. tostring(err))
	end
	return ok
end

-- Estado del selector de ruta. Se recalcula tanto cuando llega estado nuevo del
-- servidor como cuando el jugador se mueve, porque depende de las dos cosas.
--
-- Declaradas ANTES de construir el selector, que es quien captura `cerradoAMano`
-- en su callback: en Lua un nombre usado antes de existir como local se resuelve
-- como global, así que el botón "Ahora no" escribiría en una variable distinta de
-- la que lee refrescarSelector y no cerraría nada. Este proyecto ya pagó ese
-- mismo error una vez, en CargoService.
local ultimoEstado: any = nil
local cerradoAMano = false

construir("Hud", Hud.build)
construir("Gate", Gate.build)
construir("Compass", Compass.build)
construir("Minimap", Minimap.build)
construir("Menu", Menu.build)

construir("RoutePicker", function()
	RoutePicker.build(function(rutaId)
		Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
	end, function()
		cerradoAMano = true
	end)
end)

-- Dónde está el jugador. Se pide una vez por vuelta y se pasa a quien lo
-- necesite: la valla, el selector y el aviso miran todos la misma posición, y
-- consultarla tres veces sería tres respuestas distintas dentro de la misma
-- decisión.
local function raizDelJugador(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- LA VALLA DEL RECINTO. Las reglas están en Shared.Perimeter; aquí sólo se
-- levanta o se baja, y se avisa UNA vez cuando cambia.
--
-- Es la respuesta a lo que pedía JJ: "no deberías poder salir de la zona del
-- almacén a la ciudad si has cargado paquete y no eliges ruta". El aviso de
-- texto que había no bastaba -- llegaba cuando ya habías cruzado, duraba tres
-- segundos y no decía cómo arreglarlo.
local function refrescarValla(root: BasePart?): boolean
	if root == nil then
		Gate.mostrar(false)
		return false
	end
	local cerrada = Perimeter.debeCerrar(ultimoEstado, root.Position)
	if Gate.mostrar(cerrada) and cerrada then
		Hud.aviso("Con carga no se sale sin destino elegido", Color3.fromRGB(232, 176, 64))
	end
	return cerrada
end

-- CUÁNDO aparece el selector. La primera versión sólo miraba "llevas carga y no
-- has elegido ruta", y eso lo abría NADA MÁS RECOGER, dentro del almacén. Dos
-- consecuencias, las dos malas:
--
--   · Ahí el servidor RECHAZABA la elección, así que era una pantalla cuyos tres
--     botones no hacían nada.
--   · Y al ser modal, tapaba el mundo entero -- incluido tu propio personaje --
--     y escondía los botones. Recogías cajas y te quedabas encerrado en una
--     pantalla oscura sin salida.
--
-- Ahora aparece en dos sitios, y el segundo es el que cierra el agujero que
-- encontró JJ ("si le das a 'ahora no' no sé dónde tengo que ir para volver"):
--
--   · en la salida, que es donde uno va a decidir;
--   · y al llegar a la valla, porque plantarse delante de ella ES decir "quiero
--     salir". Responder a ese gesto con la pregunta vale más que cualquier
--     cartel: la pantalla que cerraste vuelve sola cuando la necesitas.
local function debeElegir(root: BasePart?, vallaCerrada: boolean): boolean
	if ultimoEstado == nil or #ultimoEstado.cajas == 0 or ultimoEstado.ruta ~= nil then
		return false
	end
	if root == nil then
		return false
	end
	local salida = mundo and mundo:FindFirstChild("Salida") :: BasePart?
	if salida and (root.Position - salida.Position).Magnitude <= Config.DISTANCIA_SALIDA then
		return true
	end
	return vallaCerrada and Perimeter.tocando(root.Position)
end

-- Aviso al cruzar la salida con carga y sin ruta. Sin esto, salir sin elegir es
-- un error MUDO que sólo se descubre dos minutos después, al llegar al destino y
-- ver que no cobras: has hecho el viaje entero para nada y el juego no te ha
-- dicho ni una palabra. Se avisa aquí, en el cliente, porque es puramente
-- informativo — el servidor sigue siendo quien decide si una entrega vale.
local dentroDeLaSalida = false

local function vigilarSalidaSinRuta(eligiendo: boolean)
	if eligiendo then
		dentroDeLaSalida = true
		return
	end
	if not dentroDeLaSalida then
		return
	end
	dentroDeLaSalida = false
	-- Sólo cuenta como "salir" si de verdad llevas algo: cruzar la salida de
	-- vacío es lo que se hace al volver a por más, y avisar ahí sería ruido.
	if ultimoEstado and #ultimoEstado.cajas > 0 and ultimoEstado.ruta == nil then
		Hud.aviso("Sales sin destino elegido: no podrás cobrar", Color3.fromRGB(230, 180, 70))
	end
end

-- QUÉ TOCA HACER AHORA, en una línea. Es el hilo que ata el bucle entero: el
-- jugador que acaba de cobrar a dos mil studs de casa, o el que cerró el
-- selector con "Ahora no", tienen que poder mirar a un sitio y saber qué sigue.
--
-- Sale del estado y sólo del estado, así que dice lo mismo que la brújula por
-- construcción: dos fuentes distintas acabarían contradiciéndose el día que una
-- cambie.
local function misionActual(estado: any): (string, Color3)
	if estado == nil then
		return "", Palette.ALMACEN
	end
	if estado.retornoZona ~= nil then
		if #estado.cajas > 0 then
			return "Lleva la carga al almacén", Palette.ALMACEN
		end
		return "Recoge la carga de vuelta", Palette.ruta(estado.retornoZona)
	end
	if estado.ruta ~= nil then
		return "Entrega en " .. string.upper(estado.ruta), Palette.ruta(estado.ruta)
	end
	if #estado.cajas > 0 then
		return "Elige destino en la salida", Palette.SALIDA
	end
	-- Con el zurrón vacío pero carga esperando en el vehículo, lo que toca es ir a
	-- por él: si no, el jugador se vuelve al almacén creyendo que lo ha perdido.
	if #(estado.cajasEnVehiculo or {}) > 0 then
		return "Vuelve a por tu vehículo cargado", Palette.TALLER
	end
	-- Con dinero suficiente, lo primero es gastarlo. "No sé dónde se compran los
	-- vehículos" (JJ) tenía dos mitades: el taller no se veía --ya es un
	-- concesionario con rótulo y escaparate-- y nadie te decía nunca que ya podías
	-- permitirte algo. El HUD enseña el precio; esto dice qué hacer con él.
	local siguiente = estado.mejoras and estado.mejoras[1]
	if siguiente and estado.dinero >= siguiente.coste then
		return "Compra " .. siguiente.nombre .. " en el taller", Palette.TALLER
	end
	if (estado.almacenCajas or 0) > 0 then
		-- "En el almacén", no "en el muelle". Muelle es como lo llamamos NOSOTROS
		-- en el código (la losa donde se apilan las piezas); el jugador lo que ve es
		-- un almacén, y el letrero de la nave dice ALMACÉN. Un juego que llama a la
		-- misma cosa de dos maneras hace dudar de si son dos sitios.
		return "Carga mercancía en el almacén", Palette.ALMACEN
	end
	-- Y el hueco que no tenía respuesta: almacén vacío y zurrón vacío. Sin esta
	-- línea, el jugador se queda mirando un muelle pelado sin saber si el juego se
	-- ha roto o hay que esperar.
	return "El almacén está produciendo: espera", Palette.ALMACEN
end

-- EL RUIDO DE LO QUE ESTÁS HACIENDO. "Aunque vayas en vehículo suenan los pasos
-- del personaje" (JJ), y tiene razón: el sonido dice lo que haces, y si dice que
-- vas andando, vas andando por mucha moto que se vea debajo.
--
-- VA EN EL CLIENTE, y ése fue el primer intento fallido: se hizo en el servidor y
-- allí esos sonidos NO EXISTEN. Los crea RbxCharacterSounds, que es un script
-- local de Roblox, dentro del HumanoidRootPart de cada personaje y en la máquina
-- de cada jugador. Medido: desde el servidor, buscar "Running" devuelve nil
-- siempre.
--
-- Se silencian por VOLUMEN y guardando el valor original, no destruyéndolos: al
-- bajarse del vehículo tienen que volver exactamente como estaban.
local PASOS = { "Running", "Climbing", "FreeFalling", "Landing", "Jumping" }

local function ajustarSonidoDePasos(estado: any)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or estado == nil then
		return
	end
	local montado = estado.montado ~= false and estado.vehiculo ~= nil and estado.vehiculo ~= "a_pie"
	for _, nombre in PASOS do
		local sonido = root:FindFirstChild(nombre)
		if sonido and sonido:IsA("Sound") then
			if sonido:GetAttribute("volumenOriginal") == nil then
				sonido:SetAttribute("volumenOriginal", sonido.Volume)
			end
			local original = sonido:GetAttribute("volumenOriginal") :: number?
			sonido.Volume = if montado then 0 else (original or 0.65)
		end
	end
end

-- SUBIRSE Y BAJARSE DEL VEHÍCULO. Faltaba entero: sólo te bajabas saliéndote del
-- asfalto, así que con un coche no había manera de ir a pie a ningún sitio --
-- "¿cómo te bajas del coche? porque no puedo" (JJ).
--
-- Con `createTouchButton` en true, ContextActionService da LAS DOS COSAS de una
-- vez: la tecla para quien juega en ordenador y un botón de verdad en el móvil.
-- Escribir el botón a mano habría sido otra pieza de interfaz que colocar, medir
-- en tres pantallas y mantener; ésta la coloca y la dimensiona Roblox, y sale
-- donde el jugador de móvil ya espera encontrarla.
--
-- Se enlaza y se desenlaza según tengas vehículo o no: un botón que no hace nada
-- es peor que ningún botón, porque el jugador lo prueba, no pasa nada, y aprende
-- a no mirarlo.
-- CON QUÉ SE ESTÁ JUGANDO AHORA MISMO. No es una pregunta de una vez al arrancar:
-- se puede enchufar un mando a mitad de partida, o soltarlo y seguir con el
-- teclado, y la pantalla tiene que decir el botón que hay en la mano.
--
-- Lo pidió JJ con un mando de Xbox delante: *"con el mando no se puede jugar, los
-- botones que hay que pulsar son los del teclado"*. Y no era sólo la etiqueta --no
-- había NINGÚN botón de mando enlazado--: las acciones del juego que no tienen
-- aviso de proximidad (subirse al vehículo, entregar) sólo existían en el teclado.
local UserInputService = game:GetService("UserInputService")

local function conMando(): boolean
	local ultimo = UserInputService:GetLastInputType()
	return ultimo == Enum.UserInputType.Gamepad1
		or ultimo == Enum.UserInputType.Gamepad2
		or ultimo == Enum.UserInputType.Gamepad3
		or ultimo == Enum.UserInputType.Gamepad4
end

-- La etiqueta de cada acción según el aparato. En táctil se deja la del teclado a
-- propósito: ContextActionService dibuja su botón con ese mismo texto, así que la
-- lista y el botón dicen lo mismo.
local function etiqueta(tecla: string, boton: string): string
	return if conMando() then boton else tecla
end

local mandoPuesto = false

local function mandoDeVehiculo(estado: any)
	local tiene = estado ~= nil and estado.vehiculo ~= nil and estado.vehiculo ~= "a_pie"
	if tiene == mandoPuesto then
		return
	end
	mandoPuesto = tiene
	if not tiene then
		ContextActionService:UnbindAction("Vehiculo")
		return
	end
	ContextActionService:BindAction("Vehiculo", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Remotes.event(Remotes.MONTAR):FireServer()
		end
		return Enum.ContextActionResult.Pass
		-- ButtonY, y no ButtonX: la X la usa Roblox para los avisos de proximidad
		-- (comprar, sacar del garaje, dejar carga), así que compartirla haría que
		-- bajarse del coche y comprar un vehículo fueran el mismo botón dentro del
		-- taller -- que es justo donde se hacen las dos cosas.
	end, true, Enum.KeyCode.V, Enum.KeyCode.ButtonY)
	-- El título dice la tecla, no la acción: la acción cambia (subir/bajar) y el
	-- botón es el mismo, así que poner "Bajar" lo dejaría mintiendo la mitad del
	-- tiempo.
	ContextActionService:SetTitle("Vehiculo", "V")
	-- A media altura por la derecha: las dos esquinas de abajo son del joystick y
	-- del salto de Roblox, y ésa es una regla del proyecto que ya costó una ronda.
	ContextActionService:SetPosition("Vehiculo", UDim2.fromScale(0.86, 0.42))
end

-- QUÉ TECLAS SIRVEN AHORA. Se calcula del estado, igual que la misión, y sólo
-- aparece lo que de verdad hace algo en este momento: una lista fija de teclas se
-- convierte en decorado que el jugador deja de leer al segundo minuto.
local function accionesActuales(estado: any): { Hud.Accion }
	local lista: { Hud.Accion } = {}
	if estado == nil then
		return lista
	end
	if estado.vehiculo ~= nil and estado.vehiculo ~= "a_pie" then
		table.insert(lista, {
			tecla = etiqueta("V", "Y"),
			accion = if estado.montado == false then "subirte al vehículo" else "bajarte del vehículo",
		})
	end
	if #estado.cajas > 0 and (estado.ruta ~= nil or estado.retornoZona ~= nil) then
		table.insert(lista, { tecla = etiqueta("E", "RB"), accion = "entregar la carga" })
	end
	-- LO QUE SIEMPRE SE PUEDE, y que hasta ahora no se decía en ningún sitio: el
	-- aviso de proximidad lo dibuja Roblox con el botón correcto de cada aparato,
	-- pero sólo aparece cuando ya estás encima. Nombrarlo aquí es lo que hace que
	-- alguien que acaba de entrar sepa que hay algo que pulsar.
	table.insert(lista, { tecla = etiqueta("E", "X"), accion = "recoger, comprar y usar" })
	return lista
end

local function refrescarSelector()
	local root = raizDelJugador()
	local vallaCerrada = refrescarValla(root)
	local eligiendo = debeElegir(root, vallaCerrada)
	vigilarSalidaSinRuta(eligiendo)
	if not eligiendo then
		-- Al salir de la zona se olvida el cierre manual: volver a la salida --o
		-- llegar a la valla-- es justamente decir "ahora sí quiero elegir".
		cerradoAMano = false
	end
	local mostrar = eligiendo and not cerradoAMano
	-- setModal ANTES de update y de mision: las dos miran si hay algo delante para
	-- decidir si se dibujan.
	Hud.setModal(mostrar)
	pcall(Menu.setModal, mostrar)
	if ultimoEstado then
		Hud.update(ultimoEstado)
		pcall(Menu.actualizar, ultimoEstado)
	end
	Hud.mision(misionActual(ultimoEstado))
	mandoDeVehiculo(ultimoEstado)
	Hud.acciones(accionesActuales(ultimoEstado))
	-- El garaje se refresca aquí y no sólo al sincronizar porque depende de a qué
	-- taller te acercas, y eso cambia andando.
	pcall(Garage.actualizar, mundo, ultimoEstado)
	-- Aquí y no sólo al sincronizar: los sonidos los crea Roblox cuando le parece
	-- (al reaparecer, al cambiar de estado), así que hay que volver a callarlos.
	ajustarSonidoDePasos(ultimoEstado)
	if mostrar then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
	end
end

-- Y CUANDO CAMBIA EL APARATO, se reescribe la lista. Enchufar el mando a mitad de
-- partida no debería dejar la pantalla diciendo "V" mientras tienes un pad en la
-- mano; y al revés igual.
UserInputService.LastInputTypeChanged:Connect(function()
	Hud.acciones(accionesActuales(ultimoEstado))
end)

-- A qué apunta la brújula, que cambia con lo que estés haciendo:
--
--   · con ruta elegida, al destino de esa ruta -- es el viaje;
--   · con carga y sin ruta, a la salida -- porque salir sin elegir es perder el
--     viaje entero, y es el error más caro que puede cometer un jugador nuevo;
--   · de vacío, al almacén, porque volver a por más es la otra mitad del bucle y
--     también hay que saber por dónde se vuelve.
--
-- Sin este último caso la brújula se apagaría justo después de cobrar, que es el
-- momento en que estás más lejos de casa y menos sabes dónde estás.
local function apuntarBrujula(estado: any)
	if estado == nil then
		return
	end
	-- Con carga de vuelta, la brújula apunta a casa: es el destino de verdad y
	-- olvidarlo dejaría al jugador con la flecha señalando el sitio del que acaba
	-- de salir.
	if estado.retornoZona ~= nil and #estado.cajas > 0 then
		Compass.apuntar(Config.ALMACEN_POS, "De vuelta al almacén", Palette.ALMACEN)
		return
	end
	if estado.retornoZona ~= nil then
		local ok, ruta = pcall(Routes.get, estado.retornoZona)
		if ok and ruta then
			Compass.apuntar(ruta.destino, "Carga de vuelta ahí", Palette.ruta(ruta.id))
			return
		end
	end

	if estado.ruta ~= nil then
		local ok, ruta = pcall(Routes.get, estado.ruta)
		if ok and ruta then
			Compass.apuntar(ruta.destino, "Destino " .. string.upper(ruta.id), Palette.ruta(ruta.id))
			return
		end
	end
	local salida = mundo and mundo:FindFirstChild("Salida") :: BasePart?
	if #estado.cajas > 0 and salida then
		Compass.apuntar(salida.Position, "Elige destino en la salida", Palette.SALIDA)
		return
	end
	Compass.apuntar(Config.ALMACEN_POS, "Tu almacén", Palette.ALMACEN)
end

-- Como `construir`, pero para lo que corre en cada actualización de estado: cada
-- pieza protegida por su cuenta y, sobre todo, QUE SE OIGA cuando falla.
--
-- El pcall pelado que había aquí costó una tarde: la brújula dejó de apuntar a
-- nada y no había ni un mensaje en la consola, así que el fallo no se distinguía
-- de "no hay objetivo". Un error tragado es peor que un error a la vista.
local avisados: { [string]: boolean } = {}

local function intentar(nombre: string, fn: (any) -> (), estado: any)
	local ok, err = pcall(fn, estado)
	if not ok and not avisados[nombre] then
		-- Una vez por sesión y por sitio: esto corre en cada sync, y un fallo
		-- permanente llenaría la consola hasta tapar todo lo demás.
		avisados[nombre] = true
		warn("[Contrabando] fallo en " .. nombre .. ": " .. tostring(err))
	end
end

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	ultimoEstado = estado
	-- LO QUE CUESTA LA SIGUIENTE MEJORA, escrito en el propio aviso de la oficina.
	-- Se pone desde el cliente y no al construir el mundo porque el precio depende
	-- del nivel de CADA jugador, y esa pieza es la misma para todos. Tocar un
	-- ProximityPrompt desde el cliente sólo se ve en su pantalla, que es justo lo
	-- que hace falta.
	intentar("precioDeLaNave", function(e)
		local oficina = mundo and mundo:FindFirstChild("OficinaNave")
		local aviso = oficina and oficina:FindFirstChild("PromptMejorar") :: ProximityPrompt?
		if aviso == nil then
			return
		end
		local siguiente = e and e.naveSiguiente
		if siguiente then
			aviso.ActionText = string.format("Mejorar nave  ·  %d", siguiente.coste)
			aviso.ObjectText = string.format("Guarda %d  ·  cada %d s", siguiente.tope, siguiente.ritmo)
			aviso.Enabled = true
		else
			aviso.ActionText = "Nave al maximo"
			aviso.ObjectText = "Oficina"
		end
	end, estado)
	-- El candado de las rutas, antes de decidir si se enseña el selector: si se
	-- pintara después, la primera vez que se abre saldría un instante con todas
	-- las tarjetas encendidas.
	intentar("RoutePicker.actualizar", RoutePicker.actualizar, estado)
	refrescarSelector()
	intentar("apuntarBrujula", apuntarBrujula, estado)
	intentar("Minimap.actualizar", Minimap.actualizar, estado)
	-- La pila del muelle, que ES el contador del almacén. Protegida por su cuenta:
	-- un fallo dibujando cajas no puede costar el HUD ni el selector de ruta.
	pcall(function()
		local almacen = mundo and mundo:FindFirstChild("Almacen") :: BasePart?
		Stock.actualizar(almacen, estado.almacen)
		-- Y la carga de vuelta, en el destino donde se acaba de entregar.
		local centro = nil
		if estado.retornoZona then
			local ok, ruta = pcall(Routes.get, estado.retornoZona)
			if ok and ruta then
				centro = ruta.destino
			end
		end
		Stock.actualizarRetorno(estado.retorno, centro)
	end)
end)

-- Recoger ACERCÁNDOSE a las cajas, no sólo con el botón.
--
-- El diseño lo decía desde el principio ("recoges las cajas tocándolas") y no
-- estaba implementado, y el resultado fue lo que contó JJ jugando: "hay un paquete
-- que no se puede recoger". Claro que no se podía -- las cajas son el dibujo del
-- contador y lo que recoge es un botón en la esquina, así que el jugador que se
-- planta encima de una caja y no pasa nada concluye, con toda la razón, que está
-- rota. El botón se queda (es lo que funciona con el zurrón lleno y sin mirar al
-- suelo); esto es lo que hace que el gesto natural también valga.
local ultimaRecogida = 0

local function recogerSiEstasEncima()
	if ultimoEstado == nil or (ultimoEstado.almacenCajas or 0) <= 0 then
		return
	end
	-- Con el zurrón lleno no se pide nada: el servidor lo rechazaría igual, y
	-- mandarle una petición cinco veces por segundo para que diga que no es
	-- gastar red por gusto.
	if #ultimoEstado.cajas >= (ultimoEstado.capacidad or 3) then
		return
	end
	local ahora = os.clock()
	-- Cada 0,4 s y no cada segundo: cargar cinco cosas tardaba CINCO SEGUNDOS de
	-- pie encima del montón, y eso es lo que se siente como que "no va fino" (JJ).
	-- Sigue habiendo freno --sin él, plantarse en el muelle vacía el almacén en un
	-- suspiro y deja de haber elección-- pero al ritmo de una persona cargando.
	if ahora - ultimaRecogida < 0.4 then
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pila = workspace:FindFirstChild("CajasDelMuelle")
	if not root or not pila then
		return
	end

	-- LA MÁS CERCANA, no la primera que se encuentre. Es lo que convierte el
	-- almacén en una decisión: te plantas delante de la urna y te llevas la urna,
	-- no lo que el bucle mirase antes. Con diez piezas juntas, "la primera del
	-- montón" habría hecho imposible elegir.
	local elegida, masCerca = nil, math.huge
	for _, caja in pila:GetChildren() do
		if caja:IsA("BasePart") then
			local d = (root.Position - caja.Position).Magnitude
			-- 10 studs y no 7: el radio viejo obligaba a plantarse casi encima de la
			-- pieza, y con la mercancía grande (un sofá mide 6) el centro de la caja
			-- quedaba fuera de alcance aunque la estuvieras tocando.
			if d <= 10 and d < masCerca then
				elegida, masCerca = caja, d
			end
		end
	end

	if elegida then
		ultimaRecogida = ahora
		Remotes.event(Remotes.RECLAMAR):FireServer(elegida:GetAttribute("indice"))
	end
end

-- Y también al moverse: el estado no cambia por caminar, pero la respuesta a
-- "¿estoy en la salida?" sí. Cuatro veces por segundo basta y de sobra para algo
-- que el jugador alcanza andando a 10-16 studs/s.
task.spawn(function()
	while true do
		task.wait(0.25)
		pcall(refrescarSelector)
		pcall(recogerSiEstasEncima)
		-- La cuenta atrás del señuelo va aquí y no en RenderStepped: es
		-- información, y con la ventana sin foco RenderStepped da cero llamadas por
		-- segundo -- el botón se quedaría congelado en su cuenta atrás.
		pcall(Menu.tick)
	end
end)

Remotes.event(Remotes.AVISO).OnClientEvent:Connect(function(texto, color)
	Hud.aviso(texto, color)
end)

Remotes.event(Remotes.SONIDO).OnClientEvent:Connect(function(clave)
	Sfx.reproducir(clave)
end)

-- Los avisos del mundo (ProximityPrompt) son ahora la forma de entregar y de
-- comprar. Sustituyen a los botones fijos de la pantalla, que "eran un poco
-- extraños" (JJ) y con razón: un botón permanente en una esquina no dice ni dónde
-- ni cuándo sirve, así que está igual de encendido en mitad de la nada que encima
-- del destino.
--
-- Se escuchan TODOS de una vez con PromptTriggered en vez de conectarse uno a uno:
-- los destinos se crean al arrancar el mundo, pero las cajas del muelle aparecen y
-- desaparecen constantemente, y una conexión por pieza sería una fuga de memoria
-- lenta que nadie notaría hasta media hora de partida.
ProximityPromptService.PromptTriggered:Connect(function(aviso, jugador)
	if jugador ~= Players.LocalPlayer then
		return
	end
	if aviso.Name == "PromptEntregar" then
		Remotes.event(Remotes.ENTREGAR):FireServer()
	elseif aviso.Name == "PromptTaller" then
		-- El id del vehículo lo decide el servidor (mejorasPara) y el cliente sólo
		-- devuelve lo que le dieron: aquí se manda el primero que quede por comprar.
		local mejoras = ultimoEstado and ultimoEstado.mejoras
		local siguiente = mejoras and mejoras[1]
		if siguiente then
			Remotes.event(Remotes.COMPRAR):FireServer(siguiente.id)
		end
	elseif aviso.Name == "PromptDevolver" then
		Remotes.event(Remotes.DEVOLVER):FireServer()
	elseif aviso.Name == "PromptComprar" then
		-- El id lo pone el mundo (lo escribió el servidor al construir el
		-- escaparate) y el cliente sólo lo devuelve: aquí no se decide nada.
		Remotes.event(Remotes.COMPRAR):FireServer(aviso:GetAttribute("vehiculo"))
	elseif aviso.Name == "PromptGaraje" then
		-- Sacar el vehículo de esa plaza. Si ya lo llevas puesto, el mismo aviso
		-- dice "Guardar" y lo que se manda es "a pie": una sola pieza para las dos
		-- caras de la misma acción, como el botón de subir/bajar.
		local id = aviso:GetAttribute("vehiculo")
		local puesto = ultimoEstado and ultimoEstado.vehiculo
		Remotes.event(Remotes.SACAR):FireServer(if id == puesto then "a_pie" else id)
	elseif aviso.Name == "PromptMejorar" then
		Remotes.event(Remotes.MEJORAR_NAVE):FireServer()
	elseif aviso.Name == "PromptCaja" then
		Remotes.event(Remotes.RECLAMAR):FireServer(aviso.Parent and aviso.Parent:GetAttribute("indice"))
	end
end)

-- La tecla E se mantiene como atajo de entrega para quien juegue en ordenador y
-- prefiera no acercarse al centro exacto de la losa. No estorba: el servidor
-- rechaza la entrega si no estás donde hay que estar, y ahora además lo dice.
ContextActionService:BindAction("Entregar", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.event(Remotes.ENTREGAR):FireServer()
	end
	return Enum.ContextActionResult.Pass
	-- Y en el mando, el gatillo derecho de arriba: entregar no tiene aviso de
	-- proximidad --se puede hacer desde cualquier punto de la losa-- así que sin
	-- esto era la única acción del bucle que un jugador de mando no podía hacer.
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)

-- Se pide el estado DESPUÉS de construir la interfaz: al revés llegaría a un
-- cliente que todavía no sabe dibujarlo.
Remotes.event(Remotes.PEDIR_ESTADO):FireServer()
