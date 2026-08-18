--!strict
--[[
	Perimeter.luau — el polígono y su puerta: por dónde NO se sale. Módulo PURO.

	EL PROBLEMA, dicho por JJ jugando: "no deberías poder salir de la zona del
	almacén a la ciudad si has cargado paquete y no eliges ruta". Y tenía razón por
	partida doble:

	  · salir sin ruta es un error MUDO y CARO -- haces el viaje entero, llegas al
	    destino y no cobras, porque la ruta sólo se elige en casa;
	  · y el aviso de texto que había no bastaba: dura tres segundos, aparece
	    cuando ya has cruzado, y no dice cómo arreglarlo.

	La solución no es un aviso mejor: es que ese error NO SE PUEDA COMETER.

	ERA UN ANILLO Y AHORA ES UNA PUERTA. La primera versión rodeaba el almacén con
	veinticuatro paneles en círculo, porque el almacén estaba metido en mitad de la
	ciudad y no había ningún borde natural. Al mudarnos al polígono propio (ver
	Config.POLIGONO_CENTRO) eso dejó de tener sentido: el polígono ya está cerrado
	por muros en tres lados y sólo tiene UNA boca, la que da a la carretera de
	acceso. Cerrar esa boca es más barato, se entiende sin explicación --una puerta
	es una puerta-- y no deja paneles flotando sobre el vacío en las esquinas.

	TRES REGLAS que hacen que la puerta nunca encierre a nadie:

	  1. sin carga, no hay puerta (volver a por más es libre);
	  2. con ruta elegida, tampoco (ya has decidido: vete);
	  3. y sólo se cierra si estás DENTRO. Quien esté fuera nunca se encuentra una
	     puerta entre él y su almacén, pase lo que pase con su estado.

	La tercera es la que importa de verdad: sin ella, cualquier estado raro --
	reaparecer fuera, un teleport, una carga de vuelta a medias-- dejaría al
	jugador dando vueltas alrededor de su propia casa sin poder entrar.
]]

local Config = require(script.Parent.Config)

local Perimeter = {}

export type EstadoRecinto = {
	cajas: { any },
	ruta: string?,
	retornoZona: string?,
}

-- ¿Está dentro del polígono? RECTÁNGULO y no círculo: el polígono es rectangular
-- y un radio dejaría fuera las esquinas (donde está el taller) o de más por los
-- lados. Se mide en el plano, como todo lo demás: subirse a un tejado dentro del
-- recinto no es salir.
--
-- El margen se suma al medir: la boca es un hueco en un muro, y el personaje tiene
-- cuerpo, así que "dentro" tiene que incluir el grosor de la puerta.
function Perimeter.dentro(posicion: Vector3, margen: number?): boolean
	local centro = Config.POLIGONO_CENTRO
	local medida = Config.POLIGONO_TAMANO
	local m = margen or 0
	local dx = math.abs(posicion.X - centro.X)
	local dz = math.abs(posicion.Z - centro.Z)
	return dx <= medida.X / 2 + m and dz <= medida.Y / 2 + m
end

-- ¿Está cerrada la puerta para este jugador, ahora mismo?
--
-- La carga DE VUELTA no cuenta: en ese viaje no hay ruta que elegir (ya la
-- elegiste a la ida) y el destino es precisamente el almacén, así que una puerta
-- cerrada ahí sería exactamente el encierro que la regla 3 existe para evitar.
function Perimeter.debeCerrar(estado: EstadoRecinto?, posicion: Vector3): boolean
	if estado == nil then
		return false
	end
	if #estado.cajas == 0 then
		return false
	end
	if estado.ruta ~= nil or estado.retornoZona ~= nil then
		return false
	end
	return Perimeter.dentro(posicion, 20)
end

-- ¿Está el jugador llegando a la puerta? Es lo que reabre el selector de ruta que
-- cerró con "Ahora no": ir hacia la salida ES decir "ya me voy", y responder a ese
-- gesto con la pregunta vale más que cualquier cartel.
function Perimeter.tocando(posicion: Vector3, margen: number?): boolean
	local centro = Config.POLIGONO_CENTRO
	local medida = Config.POLIGONO_TAMANO
	-- La boca está en el lado NORTE (Z menor), que es el que da a la ciudad.
	local borde = centro.Z - medida.Y / 2
	return posicion.Z <= borde + (margen or 45)
end

export type Poste = {
	posicion: Vector3,
	giro: number, -- grados alrededor de Y
	ancho: number,
}

-- Los paneles que cierran la boca. Son pocos y en línea, no un anillo: el resto
-- del polígono ya está cerrado por sus muros.
function Perimeter.postes(cuantos: number?): { Poste }
	local centro = Config.POLIGONO_CENTRO
	local medida = Config.POLIGONO_TAMANO
	local n = math.max(2, cuantos or 6)
	local lista: { Poste } = {}
	-- Un pelín más ancha que la boca, para que no se pueda pasar rozando el muro.
	local total = medida.X + 8
	local ancho = total / n
	local z = centro.Z - medida.Y / 2
	for i = 1, n do
		local x = centro.X - total / 2 + ancho * (i - 0.5)
		table.insert(lista, {
			posicion = Vector3.new(x, centro.Y, z),
			-- Sin girar: la puerta es perpendicular a la salida, así que su cara
			-- larga ya va en X, que es como se crea una pieza por defecto.
			giro = 0,
			-- Con solape: dos paneles que se tocan justo en la punta dejan pasar por
			-- la juntura en cuanto el suelo no es perfectamente plano.
			ancho = ancho * 1.06,
		})
	end
	return lista
end

return Perimeter
