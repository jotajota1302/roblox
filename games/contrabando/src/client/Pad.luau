--!strict
--[[
	Pad.luau — jugar SIN RATÓN, en un solo sitio: el mando y el teclado.

	POR QUÉ EXISTE. *"No funciona el controlador de Xbox para manejar el juego"*
	(JJ). Hay dos mitades en esa frase y sólo una es nuestra:

	  · MOVER al personaje no es cosa del juego -- lo hace el control por defecto
	    de Roblox, y funciona salvo que Roblox no vea el mando (medido con
	    `UserInputService.GamepadEnabled`, que salió `false` con cero mandos
	    conectados: el mando estaba dormido, no había nada que arreglar en el
	    código);
	  · PULSAR los botones de la pantalla SÍ es cosa nuestra, y no funcionaba en
	    absoluto. Con un mando no hay puntero: la única forma de llegar a un botón
	    es la navegación por selección, y ésa no se enciende sola -- hace falta que
	    alguien ponga `GuiService.SelectedObject`. Nadie lo hacía. O sea que elegir
	    ruta, comprar una habilidad, mejorar la nave o sacar el coche del garaje
	    eran cosas que un jugador de mando NO PODÍA HACER, y son el juego entero.

	POR QUÉ UNA PILA Y NO UNA VARIABLE. Los paneles se montan unos encima de otros
	--el selector de ruta puede abrirse con el menú abierto-- y al cerrar el de
	arriba el foco tiene que volver al de abajo, no evaporarse. Con una variable
	suelta, cerrar un panel deja al jugador sin selección y sin manera de recuperar
	el mando salvo tocar la pantalla, que es justo lo que no tiene.

	Y DESDE EL 22/08 TAMBIÉN EL TECLADO. *"La eleccion del objetivo deberia poder
	hacerse con el mando o las flechas y el enter o algun boton, no solo con el
	raton"* (JJ). Es la misma carencia por otro lado: la navegación por selección de
	Roblox la mueve el mando y NADA MÁS -- con teclado, poner una selección dibuja el
	recuadro y ahí se queda. Las flechas, el Enter y el salto de un botón a otro se
	hacen a mano aquí abajo, en el bloque del teclado.

	Y SÓLO CON MANDO A LA VISTA. Poner `SelectedObject` con teclado y ratón dibuja
	un recuadro de selección alrededor del botón que nadie ha pedido, y encima
	secuestra el stick: la navegación de la interfaz se come el movimiento. Por eso
	todo lo de aquí se pregunta antes si hay un mando conectado, y por eso hay un
	enganche a `GamepadConnected` -- se puede enchufar el mando con un panel ya
	abierto, y entonces hay que darle el foco sin que el jugador tenga que cerrar y
	volver a abrir.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Nav = require(game.ReplicatedStorage.Shared.Nav)

local Pad = {}

type Capa = {
	nombre: string,
	primero: GuiObject,
	alCerrar: (() -> ())?,
}

local pila: { Capa } = {}

-- ¿Hay un mando enchufado? No es lo mismo que "se está usando el mando"
-- (`conMando`): para decidir si la interfaz se puede navegar vale con que exista.
function Pad.hayMando(): boolean
	return UserInputService.GamepadEnabled and #UserInputService:GetConnectedGamepads() > 0
end

-- ¿Lo último que tocó el jugador fue el mando? Es lo que decide qué botón se
-- DIBUJA en la lista de acciones ("E" o "RB"), y por eso mira el último input y no
-- la conexión: se puede tener un mando enchufado y estar jugando con el teclado.
function Pad.conMando(): boolean
	local ultimo = UserInputService:GetLastInputType()
	return ultimo == Enum.UserInputType.Gamepad1
		or ultimo == Enum.UserInputType.Gamepad2
		or ultimo == Enum.UserInputType.Gamepad3
		or ultimo == Enum.UserInputType.Gamepad4
end

-- NO SE ROBA EL FOCO A QUIEN YA ESTA NAVEGANDO. `Menu.actualizar` repinta el panel
-- abierto cada vez que llega el estado --varias veces por segundo-- y volver a
-- poner la seleccion en el primer boton en cada repintado le arrastraria el cursor
-- al jugador mientras baja por la lista. Asi que si lo que hay seleccionado sigue
-- vivo y sigue dentro de la misma pantalla, se deja donde esta.
--
-- Lo de "sigue vivo" no es paranoia: repintar DESTRUYE las fichas y las vuelve a
-- crear, y un SelectedObject que apunta a un boton borrado no da error -- deja el
-- mando muerto, que es peor.
local function pintarFoco(forzar: boolean?)
	if not Pad.hayMando() then
		return
	end
	local arriba = pila[#pila]
	if arriba == nil then
		GuiService.SelectedObject = nil
		return
	end
	local actual = GuiService.SelectedObject
	local pantalla = arriba.primero:FindFirstAncestorWhichIsA("ScreenGui")
	if
		not forzar
		and actual ~= nil
		and actual:IsDescendantOf(game)
		and pantalla ~= nil
		and actual:IsDescendantOf(pantalla)
	then
		return
	end
	GuiService.SelectedObject = arriba.primero
end

-- ATRÁS ES B, y se enlaza sólo mientras hay algo abierto: dejarlo puesto siempre
-- haría que la B no sirviera para nada el 90 % del tiempo, y ContextActionService
-- pinta un botón táctil por cada acción enlazada.
local ATRAS = "PadAtras"

local function vigilarAtras()
	if #pila == 0 then
		ContextActionService:UnbindAction(ATRAS)
		return
	end
	ContextActionService:BindAction(ATRAS, function(_, estado)
		if estado == Enum.UserInputState.Begin then
			local arriba = pila[#pila]
			if arriba and arriba.alCerrar then
				arriba.alCerrar()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonB)
end

-- Declarada aquí porque `abrir` y `cerrar` la llaman y se define más abajo, con el
-- resto del teclado: en Luau una `local` no existe hasta la línea en la que se
-- escribe, así que sin esto las dos verían `nil` y el teclado no se enlazaría nunca.
local vigilarTeclado: () -> ()

-- Abre una capa: a partir de aquí el mando navega ESTE panel, y la B lo cierra.
-- `primero` es dónde aterriza la selección -- el botón que el jugador querría
-- pulsar el 90 % de las veces, no el primero que se creó.
function Pad.abrir(nombre: string, primero: GuiObject?, alCerrar: (() -> ())?)
	if primero == nil then
		return
	end
	-- Reabrir la misma capa no la duplica: `Menu.actualizar` repinta el panel
	-- abierto en cada sync --cinco veces por segundo con el estado cambiando-- y
	-- sin esto la pila crecería sin parar.
	Pad.cerrar(nombre)
	table.insert(pila, { nombre = nombre, primero = primero, alCerrar = alCerrar })
	pintarFoco()
	vigilarAtras()
	vigilarTeclado()
end

-- Cierra una capa POR NOMBRE, no la de arriba: quien cierra un panel casi nunca
-- sabe si encima suyo se ha abierto otro, y "cierra la de arriba" dejaría abierta
-- la de abajo con el foco de la que ya no está.
function Pad.cerrar(nombre: string)
	for i = #pila, 1, -1 do
		if pila[i].nombre == nombre then
			table.remove(pila, i)
		end
	end
	-- FORZANDO. La capa que se cierra puede compartir pantalla con la de debajo --el
	-- panel del menu y su columna estan en el mismo ScreenGui-- y sin forzar el foco
	-- se quedaria sobre un boton que acaba de ocultarse: el mando, muerto.
	pintarFoco(true)
	vigilarAtras()
	vigilarTeclado()
end

function Pad.hayPanel(): boolean
	return #pila > 0
end

-- ¿Está abierta esta capa? Lo pregunta quien tiene un botón que ALTERNA (abrir con
-- el mismo botón que cierra), y así el estado vive en un solo sitio en vez de en
-- una variable paralela que un día dirá lo contrario que la pila.
function Pad.enCapa(nombre: string): boolean
	for _, capa in pila do
		if capa.nombre == nombre then
			return true
		end
	end
	return false
end

-- ── EL TECLADO, que es la otra mitad de "sin ratón" ──────────────────────────────
--
-- *"La eleccion del objetivo deberia poder hacerse con el mando o las flechas y el
-- enter o algun boton, no solo con el raton"* (JJ, 22/08).
--
-- El mando ya estaba resuelto arriba; el teclado no lo estaba EN ABSOLUTO, y no por
-- descuido: la navegación por selección de Roblox (`GuiService.SelectedObject`) la
-- mueve el mando y nada más. Con teclado, poner una selección dibuja el recuadro y
-- ahí se queda -- las flechas no la mueven solas y el Enter no pulsa nada.
--
-- ASÍ QUE LA NAVEGACIÓN SE HACE AQUÍ, y son tres piezas:
--
--   · MOVERSE es geometría, no una lista. Se mira dónde está cada botón en pantalla
--     y se salta al más cercano en la dirección pulsada. Una lista ordenada obligaría
--     a que cada panel declarase su orden --y a mantenerlo cuando se añade un botón--
--     mientras que la posición ya está ahí y nunca miente: si en pantalla está a la
--     derecha, la flecha derecha lleva a él.
--   · PULSAR no se puede simular. `GuiButton.Activated` no se dispara a mano desde
--     un script, así que los paneles registran su acción con `Pad.accion(boton, fn)`
--     en vez de con `Activated:Connect(fn)`. Es una línea por botón y hace que el
--     Enter, el clic y la A del mando acaben los tres en la misma función.
--   · Y EL FOCO SÓLO APARECE CUANDO SE PIDE. Encenderlo siempre pintaría un recuadro
--     de selección que nadie ha pedido alrededor de un botón cualquiera -- que es
--     exactamente el motivo por el que todo esto estaba limitado al mando. Se
--     enciende al pulsar la primera flecha y se apaga en cuanto se mueve el ratón.
local tecladoActivo = false

-- La acción de cada botón, para poder ejecutarla con Enter. La tabla tiene CLAVES
-- DÉBILES: los paneles se repintan destruyendo sus fichas y creándolas de nuevo
-- (`Menu.actualizar` lo hace varias veces por segundo), así que una tabla normal
-- iría acumulando botones muertos durante toda la partida.
local acciones: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

-- Conecta la acción de un botón Y la deja registrada. Devuelve el botón para poder
-- encadenar, que es como se usaba `Activated:Connect` en los paneles.
function Pad.accion<T>(boton: T & GuiButton, fn: () -> ()): T
	acciones[boton :: any] = fn;
	(boton :: any).Activated:Connect(fn)
	return boton
end

-- Los botones a los que se puede saltar ahora mismo: los de la pantalla de la capa
-- de arriba, visibles y con sitio en pantalla.
--
-- SE MIRA `Visible` DE TODOS LOS PADRES, no sólo el del botón. Un panel se oculta
-- ocultando su marco, y sus botones siguen diciendo `Visible = true` -- navegar a un
-- botón de un panel cerrado deja el foco en un sitio que no se ve, que es la forma
-- más rápida de que el jugador crea que el teclado no funciona.
local function seVe(objeto: GuiObject, pantalla: Instance): boolean
	local nodo: Instance? = objeto
	while nodo ~= nil and nodo ~= pantalla do
		if nodo:IsA("GuiObject") and not nodo.Visible then
			return false
		end
		nodo = nodo.Parent
	end
	return true
end

local function navegables(): ({ GuiButton }, Instance?)
	local arriba = pila[#pila]
	if arriba == nil then
		return {}, nil
	end
	local pantalla = arriba.primero:FindFirstAncestorWhichIsA("ScreenGui")
	if pantalla == nil then
		return {}, nil
	end
	local lista: { GuiButton } = {}
	for _, d in pantalla:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 0 and seVe(d, pantalla) then
			table.insert(lista, d)
		end
	end
	return lista, pantalla
end

local function centro(b: GuiObject): Vector2
	return b.AbsolutePosition + b.AbsoluteSize / 2
end

-- El salto de una flecha. LA DECISION NO ESTA AQUI: vive en `shared/Nav.luau`, que es
-- puro y esta probado en la bateria. Aqui solo se traduce el mundo de Roblox --que
-- botones hay y donde caen en pantalla-- a la pregunta que `Nav` sabe contestar.
--
-- Estan separados porque las teclas NO SE PUEDEN PROBAR desde fuera: medido el 22/08,
-- `user_keyboard_input` del MCP no entrega ninguna con Studio en segundo plano (ni un
-- espia de ContextActionService a prioridad 9000 ni un `InputBegan` crudo recibieron
-- nada). Con la aritmetica metida en este fichero, el unico sitio donde se sabria si
-- la flecha de abajo va abajo seria jugando.
local function mover(dx: number, dy: number)
	local lista, pantalla = navegables()
	if #lista == 0 then
		return
	end
	local actual = GuiService.SelectedObject
	if actual == nil or not actual:IsDescendantOf(pantalla :: Instance) then
		GuiService.SelectedObject = pila[#pila].primero
		return
	end
	local candidatos: { Nav.Candidato } = {}
	for _, b in lista do
		if b ~= actual then
			table.insert(candidatos, { id = b, centro = centro(b) })
		end
	end
	local mejor = Nav.siguiente(candidatos, centro(actual :: GuiObject), dx, dy)
	if mejor then
		GuiService.SelectedObject = mejor
	end
end

local function pulsar()
	local actual = GuiService.SelectedObject
	if actual == nil then
		return
	end
	local fn = acciones[actual :: any]
	if fn then
		fn()
	end
end

-- LAS TECLAS SE ENLAZAN SÓLO CON UN PANEL ABIERTO, y se TRAGAN (`Sink`). Las dos
-- cosas importan: sin panel, las flechas mueven al personaje y tienen que seguir
-- haciéndolo; con panel, dejarlas pasar movería al jugador por debajo del menú.
local NAVEGAR = "PadNavegar"

function vigilarTeclado()
	if #pila == 0 then
		ContextActionService:UnbindAction(NAVEGAR)
		tecladoActivo = false
		return
	end
	ContextActionService:BindAction(
		NAVEGAR,
		function(_, estado, input)
			if estado ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			local tecla = input.KeyCode
			if tecla == Enum.KeyCode.Return or tecla == Enum.KeyCode.KeypadEnter or tecla == Enum.KeyCode.Space then
				pulsar()
				return Enum.ContextActionResult.Sink
			end
			if tecla == Enum.KeyCode.Escape or tecla == Enum.KeyCode.Backspace then
				local arriba = pila[#pila]
				if arriba and arriba.alCerrar then
					arriba.alCerrar()
				end
				return Enum.ContextActionResult.Sink
			end
			-- La primera flecha ENCIENDE el foco en vez de mover: si moviera, el jugador
			-- que pulsa una vez para ver qué pasa se encontraría la selección ya saltada
			-- de sitio sin haber visto nunca dónde estaba.
			if not tecladoActivo then
				tecladoActivo = true
				GuiService.SelectedObject = pila[#pila].primero
				return Enum.ContextActionResult.Sink
			end
			if tecla == Enum.KeyCode.Up then
				mover(0, -1)
			elseif tecla == Enum.KeyCode.Down then
				mover(0, 1)
			elseif tecla == Enum.KeyCode.Left then
				mover(-1, 0)
			elseif tecla == Enum.KeyCode.Right then
				mover(1, 0)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Return,
		Enum.KeyCode.KeypadEnter,
		Enum.KeyCode.Space,
		Enum.KeyCode.Escape,
		Enum.KeyCode.Backspace
	)
end

-- Y EN CUANTO SE TOCA EL RATÓN, el recuadro se va. Un foco de teclado olvidado sobre
-- un botón mientras el jugador apunta con el ratón a otro es la interfaz diciendo dos
-- cosas a la vez.
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and tecladoActivo and not Pad.hayMando() then
		tecladoActivo = false
		GuiService.SelectedObject = nil
	end
end)

-- Enchufar el mando con un panel ya abierto tiene que darle el foco solo. Y al
-- desenchufarlo se suelta: un `SelectedObject` vivo sin mando deja el recuadro de
-- selección pintado y le come el stick al teclado.
UserInputService.GamepadConnected:Connect(pintarFoco)
UserInputService.GamepadDisconnected:Connect(function()
	if not Pad.hayMando() then
		GuiService.SelectedObject = nil
	end
end)

return Pad
