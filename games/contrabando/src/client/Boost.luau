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
	no dibuja "vas rapido", dibuja "ACABAS de acelerar": un tiron de campo de vision
	que se abre de golpe y se cierra en medio segundo.

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
local POR_RAYO = 8
local TOPE = 16

-- Lo que tarda en volver. Rapido al abrir (el golpe) y lento al cerrar (la
-- inercia): si volviera a la misma velocidad, se leeria como un parpadeo.
local CIERRE_POR_SEGUNDO = 22

local extra = 0
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
	if cam == nil or extra <= 0 then
		return
	end
	extra = math.max(0, extra - CIERRE_POR_SEGUNDO * dt)
	cam.FieldOfView = referencia(cam) + extra
end

-- Se llama al recibir Remotes.IMPULSO.
function Boost.golpe()
	local cam = camara()
	if cam == nil then
		return
	end
	referencia(cam)
	extra = math.min(extra + POR_RAYO, TOPE)
	cam.FieldOfView = (base :: number) + extra

	if not conectado then
		conectado = true
		RunService.RenderStepped:Connect(tick)
	end
end

-- Al morir o al cambiar de camara, el objetivo vuelve a su sitio de una vez. Sin
-- esto, reaparecer en mitad de un tiron deja la camara abierta hasta que se
-- consuma sola, y el jugador nuevo ve el mundo deformado sin saber por que.
function Boost.soltar()
	extra = 0
	local cam = camara()
	if cam and base then
		cam.FieldOfView = base
	end
end

return Boost
