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
local Compass = require(script.Parent:WaitForChild("Compass"))
local Hud = require(script.Parent:WaitForChild("Hud"))
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
construir("Compass", Compass.build)
construir("Minimap", Minimap.build)

construir("RoutePicker", function()
	RoutePicker.build(function(rutaId)
		Remotes.event(Remotes.ELEGIR_RUTA):FireServer(rutaId)
	end, function()
		cerradoAMano = true
	end)
end)

-- CUÁNDO aparece el selector. La versión anterior sólo miraba "llevas carga y no
-- has elegido ruta", y eso lo abría NADA MÁS RECOGER, dentro del almacén. Dos
-- consecuencias, las dos malas:
--
--   · Ahí el servidor RECHAZA la elección (exige estar en la salida), así que
--     era una pantalla cuyos tres botones no hacían nada.
--   · Y al ser modal, tapaba el mundo entero -- incluido tu propio personaje --
--     y escondía los botones, incluido el de comprar la furgoneta. Recogías
--     cajas y te quedabas encerrado en una pantalla oscura sin salida.
--
-- Ahora aparece donde sirve: en la salida, con carga y sin ruta elegida. Y se
-- puede cerrar; al alejarse y volver, vuelve a ofrecerse.
local function debeElegir(): boolean
	if ultimoEstado == nil or #ultimoEstado.cajas == 0 or ultimoEstado.ruta ~= nil then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local salida = mundo and mundo:FindFirstChild("Salida") :: BasePart?
	if not root or not salida then
		return false
	end
	return (root.Position - salida.Position).Magnitude <= Config.DISTANCIA_SALIDA
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

local function refrescarSelector()
	local eligiendo = debeElegir()
	vigilarSalidaSinRuta(eligiendo)
	if not eligiendo then
		-- Al salir de la zona se olvida el cierre manual: volver a la salida es
		-- justamente decir "ahora sí quiero elegir".
		cerradoAMano = false
	end
	local mostrar = eligiendo and not cerradoAMano
	-- setModal ANTES de update: update decide si el botón de comprar se enciende,
	-- y necesita saber ya si hay algo delante.
	Hud.setModal(mostrar)
	if ultimoEstado then
		Hud.update(ultimoEstado)
	end
	if mostrar then
		RoutePicker.mostrar()
	else
		RoutePicker.ocultar()
	end
end

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

Remotes.event(Remotes.SYNC_STATE).OnClientEvent:Connect(function(estado)
	ultimoEstado = estado
	refrescarSelector()
	pcall(apuntarBrujula, estado)
	pcall(Minimap.actualizar, estado)
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
	if ahora - ultimaRecogida < 1 then
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
			if d <= 7 and d < masCerca then
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
end, false, Enum.KeyCode.E)

-- Se pide el estado DESPUÉS de construir la interfaz: al revés llegaría a un
-- cliente que todavía no sabe dibujarlo.
Remotes.event(Remotes.PEDIR_ESTADO):FireServer()
