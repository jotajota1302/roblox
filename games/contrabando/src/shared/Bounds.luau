--!strict
--[[
	Bounds.luau — dónde acaba el mundo, y cómo se sabe que te has salido.

	EXISTE POR *"CUANDO LLEGO AL MEDIO DESAPAREZCO"* (JJ), Y EL SÍNTOMA ENGAÑA. Se
	buscó la causa leyendo el código y no apareció: todo lo que mueve al jugador --el
	regreso al almacén, el spawn, el vehículo-- está acotado. Se buscó un agujero en
	el suelo y las sondas daban verde. El módulo se escribió a ciegas, para al menos
	DETECTAR lo que no se sabía explicar.

	Y al medir con él puesto salió, en una posición que lo explica todo:

		jugador en -471.0, **-56.0**, 522.3

	Y = -56. El jugador NO se había ido a ninguna parte: estaba tumbado sobre la RED
	DE SEGURIDAD invisible que hay 76 studs por debajo de la ciudad, andando por una
	plancha que nadie ve. Y X = -471 es el centro del mapa casi exacto (el centro
	está en -474): "el medio", literalmente.

	Por eso ninguna sonda lo cazaba. No hay error, no hay muerte, no hay caída al
	vacío: la red hace su trabajo --evita que Roblox destruya el personaje a -500--
	y a cambio deja al jugador en un limbo del que no se sale y que desde arriba se
	ve como una desaparición.

	DE AHÍ SALE LA COTA DE ABAJO, y es la lección de este módulo: la primera versión
	ponía el fondo a -130, que suena prudente y NO HABRÍA CAZADO ESTE CASO -- la red
	para la caída en -60, muy por encima. Un guardián que llega tarde es peor que no
	tener guardián, porque parece que hay red. Ver `Bounds.CAIDA`.

	La segunda razón sigue siendo válida: Roblox destruye a -500 studs, y un jugador
	que se sale del mapa no ve un error, ve que desaparece y pierde la partida.

	La caja es GENEROSA a propósito. No está aquí para corregir a nadie que se suba
	a un tejado o se cuele detrás del almacén: sólo para cazar lo que está tan lejos
	que no puede ser un jugador andando. Un límite ajustado teletransportaría a
	gente que juega bien, y eso sería un fallo peor que el que arregla.
]]

local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)

local Bounds = {}

-- Cuánto se le deja salirse antes de darlo por perdido. Un mapa entero de sobra:
-- con el recinto incluido el mundo mide 610 x 602 studs, así que para que esto
-- salte hay que estar más lejos del borde de lo que mide el mapa de lado a lado.
Bounds.MARGEN = 600

-- Y cuánto puede caer antes de darlo por perdido.
--
-- 60, Y EL NÚMERO IMPORTA MÁS DE LO QUE PARECE. La primera versión ponía 150, que
-- suena prudente y era inútil: hay una RED DE SEGURIDAD invisible por debajo del
-- mapa que para las caídas, así que un jugador que se cae no sigue bajando -- se
-- queda tumbado sobre ella. Con el fondo a -130 el guardián no lo habría visto
-- nunca, y el jugador se habría quedado exactamente igual de perdido que antes,
-- sólo que vivo. Un guardián que no llega a tiempo es peor que ninguno, porque
-- parece que hay red.
--
-- Con 60 el fondo queda en -40,8: por debajo de cualquier sitio donde se juegue
-- (todo el mapa está a 19,2) y POR ENCIMA de la red, así que se caza al que cae
-- antes de que llegue a ella. Y quedan 460 studs hasta donde Roblox destruye.
Bounds.CAIDA = 60

-- La cota de la red de seguridad. Vive aquí y no en `CityBuilder` para que su
-- relación con el fondo del guardián se pueda comprobar en una prueba pura: si un
-- día alguien sube la red por encima del fondo, el guardián deja de servir y nadie
-- se enteraría.
--
-- -90 está por debajo de TODO lo que el mapa construye. Medido en el mundo ya
-- montado: la pieza más baja es el zócalo del polígono, a -73,8; a -90 la red pasa
-- por debajo en vez de atravesarlo.
Bounds.RED_Y = -90

-- La caja del mundo: x0, x1, z0, z1, ya con el margen puesto.
--
-- No es sólo la retícula. El recinto del almacén cuelga por el sur, FUERA del
-- rectángulo de calles (la retícula acaba en z=767 y el recinto llega a 905), y es
-- donde empieza cada partida: calcular la caja sólo con `Grid.limites()` habría
-- dado por perdido a todo el que estuviera en su propia base.
-- EL RECTÁNGULO QUE OCUPA EL MUNDO, sin margen: la retícula de calles MÁS el
-- recinto del almacén.
--
-- Existe suelta porque hace falta en dos sitios que no son este: la caja del
-- guardián (aquí abajo, con margen) y el suelo base que planta `MapBuilder` (con
-- el suyo, más pequeño). Que las dos cuentas salgan de aquí es lo que impide que
-- se separen -- y ya se separaron una vez: el suelo base se calculaba sólo con
-- `Grid.limites()` y se paraba en z=827 mientras el recinto llega a 905, dejando
-- 78 studs de VACÍO rodeando el sitio donde empieza cada partida. Medido con una
-- rejilla de 4 studs: 1.444 puntos sin suelo, todos ahí, y cero en la ciudad.
function Bounds.mundo(): (number, number, number, number)
	local x0, x1, z0, z1 = Grid.limites()

	local recintoX = Config.POLIGONO_TAMANO.X / 2
	local recintoZ = Config.POLIGONO_TAMANO.Y / 2
	return math.min(x0, Config.POLIGONO_CENTRO.X - recintoX),
		math.max(x1, Config.POLIGONO_CENTRO.X + recintoX),
		math.min(z0, Config.POLIGONO_CENTRO.Z - recintoZ),
		math.max(z1, Config.POLIGONO_CENTRO.Z + recintoZ)
end

function Bounds.caja(): (number, number, number, number)
	local x0, x1, z0, z1 = Bounds.mundo()
	return x0 - Bounds.MARGEN, x1 + Bounds.MARGEN, z0 - Bounds.MARGEN, z1 + Bounds.MARGEN
end

-- El suelo por debajo del cual ya no hay juego.
function Bounds.fondo(): number
	return Grid.Y - Bounds.CAIDA
end

-- Devuelve el MOTIVO por el que esa posición está fuera del mundo, o `nil` si está
-- dentro. Un motivo y no un booleano porque lo que se hace con esto es escribirlo
-- en la consola: "nan" y "abajo" apuntan a causas distintas y saber cuál fue es la
-- mitad del diagnóstico que hoy falta.
function Bounds.fuera(pos: Vector3): string?
	-- NaN PRIMERO, y con la comparación rara a propósito: un NaN no es igual ni a
	-- sí mismo, y es la ÚNICA forma de detectarlo. Va antes que nada porque un NaN
	-- sale falso en todas las comparaciones de abajo: `nan < x0` es falso, `nan >
	-- x1` también, así que una posición rota pasaría por buena y el guardián no
	-- serviría justo en el caso para el que se escribió.
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
		return "nan"
	end

	if pos.Y < Bounds.fondo() then
		return "abajo"
	end

	local x0, x1, z0, z1 = Bounds.caja()
	if pos.X < x0 or pos.X > x1 or pos.Z < z0 or pos.Z > z1 then
		return "lejos"
	end

	return nil
end

return Bounds
