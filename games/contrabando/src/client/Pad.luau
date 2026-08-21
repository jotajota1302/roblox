--!strict
--[[
	Pad.luau — el mando, en un solo sitio.

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
