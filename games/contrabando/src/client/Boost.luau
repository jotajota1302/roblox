--!strict
--[[
	Boost.luau — el golpe de camara al coger un rayo.

	POR QUE EXISTE. La velocidad del rastro llevaba desde que se invento sin
	notarse: cada pieza valia 0,4 studs/s sobre 16, o sea un dos por ciento, y lo
	unico que cambiaba en pantalla era un numerito entre parentesis en el HUD. El
	premio existia en la hoja de calculo.

	Subir el valor arregla la mitad --ahora una pieza es +15 %-- pero solo la mitad:
	un cambio de velocidad, por grande que sea, es dificil de percibir cuando no
	tienes con que compararlo. Lo que lo hace evidente es el instante. Por eso esto
	no dibuja "vas rapido", dibuja "ACABAS de acelerar": el campo de vision se abre
	deprisa y se cierra despacio. DEPRISA NO ES DE GOLPE -- la primera version lo
	escribia en un solo fotograma y se sintio como un tiron, no como un empujon.

	VA EN EL CLIENTE Y SOLO PARA TI, y no por ahorro: la camara es tuya. Lo que el
	servidor manda es el instante (Remotes.IMPULSO); lo que se hace con el es cosa
	de cada maquina, igual que las senales del rastro.

	Y ES ACUMULABLE A PROPOSITO: coger dos rayos seguidos no reinicia el tiron, lo
	suma. Encadenar tiene que sentirse distinto a coger uno suelto, que es
	justamente la diferencia que el juego quiere que se aprenda.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Boost = {}

-- Cuanto se abre el objetivo por rayo, y hasta donde. Grados de campo de vision.
--
-- Ocho grados es mucho para un tiron continuo y poco para uno que dura medio
-- segundo: es el margen en el que el ojo lo registra como un empujon y no como un
-- mareo. El tope a 16 esta para el caso de la cadena -- tres rayos en dos segundos
-- no pueden dejar la pantalla en ojo de pez.
-- Cuanto pide el impulso por rayo, y hasta donde. Grados de campo de vision.
--
-- BAJADO DE 8 A 5 (y el tope de 16 a 10) el mismo dia que se estreno: *"los efectos
-- son bruscos"*. Y lo eran por dos motivos distintos que se sumaban -- era mucho, y
-- ademas entraba de golpe.
local POR_RAYO = 5
local TOPE = 10

-- Lo que tarda en volver a su sitio, en grados por segundo.
local CIERRE_POR_SEGUNDO = 14

-- Y LO QUE TARDA EN LLEGAR, que es lo que faltaba. La primera version escribia el
-- campo de vision de golpe en el mismo fotograma de la recogida: un salto de 8
-- grados en 16 milisegundos no se lee como aceleracion, se lee como un tiron.
--
-- Ahora hay dos numeros --lo que el impulso PIDE y lo que la camara PINTA-- y el
-- segundo persigue al primero con suavizado exponencial. Sube en 90 ms (rapido, es
-- el golpe) y baja en 260 (lento, es la inercia). Que no sean iguales es justo lo
-- que lo hace sentir un empujon en vez de un parpadeo.
local TAU_SUBIDA = 0.09
local TAU_BAJADA = 0.26

local pedido = 0
local pintado = 0
local base: number? = nil
local conectado = false

local function camara(): Camera?
	return Workspace.CurrentCamera
end

-- El campo de vision de referencia se lee LA PRIMERA VEZ y se recuerda. Leerlo en
-- cada golpe daria el valor ya inflado por el golpe anterior, y la camara se iria
-- abriendo sola hasta el tope sin volver nunca -- que es el fallo clasico de los
-- efectos que se montan sobre su propio resultado.
local function referencia(cam: Camera): number
	if base == nil then
		base = cam.FieldOfView
	end
	return base :: number
end

local function tick(dt: number)
	local cam = camara()
	if cam == nil then
		return
	end
	if pedido <= 0 and pintado <= 0.05 then
		-- Ya no queda nada que animar: se deja el campo de vision EXACTO y se para.
		-- Sin este remate quedaria una decima de grado colgando para siempre, y la
		-- siguiente vez que algo lea el valor de referencia lo leeria torcido.
		if pintado ~= 0 then
			pintado = 0
			cam.FieldOfView = referencia(cam)
		end
		return
	end

	pedido = math.max(0, pedido - CIERRE_POR_SEGUNDO * dt)
	local tau = if pedido > pintado then TAU_SUBIDA else TAU_BAJADA
	pintado += (pedido - pintado) * (1 - math.exp(-dt / tau))
	cam.FieldOfView = referencia(cam) + pintado
end

-- Se llama al recibir Remotes.IMPULSO.
function Boost.golpe()
	local cam = camara()
	if cam == nil then
		return
	end
	referencia(cam)
	pedido = math.min(pedido + POR_RAYO, TOPE)

	if not conectado then
		conectado = true
		RunService.RenderStepped:Connect(tick)
	end
end

-- Al morir o al cambiar de camara, el objetivo vuelve a su sitio de una vez. Sin
-- esto, reaparecer en mitad de un tiron deja la camara abierta hasta que se
-- consuma sola, y el jugador nuevo ve el mundo deformado sin saber por que.
function Boost.soltar()
	pedido = 0
	pintado = 0
	local cam = camara()
	if cam and base then
		cam.FieldOfView = base
	end
end

return Boost
