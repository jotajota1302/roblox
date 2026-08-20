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
-- LA VALLA SE CIERRA POR DOS MOTIVOS, y los dos son el mismo: salir así no lleva a
-- ninguna parte.
--
--   · SIN CARGA. Petición de JJ jugando: "no debería poder salir de la zona donde
--     están los almacenes y el taller sin paquete". Tiene razón y arregla un agujero
--     del arranque -- hoy se puede cruzar el arco de vacío, andar hasta un destino y
--     descubrir allí que no había nada que entregar. Un juego que te deja hacer un
--     viaje entero para nada no es libertad, es una trampa.
--
--   · CON CARGA Y SIN DESTINO. La de siempre: llegar y no cobrar porque nunca
--     elegiste a dónde ibas.
--
-- En los dos casos la valla no castiga, INFORMA: aparece justo donde ibas a
-- equivocarte, y se abre sola en cuanto arreglas lo que le falta al viaje.
function Perimeter.debeCerrar(estado: EstadoRecinto?, posicion: Vector3): boolean
	if estado == nil then
		return false
	end
	local sinCarga = #estado.cajas == 0
	local sinDestino = estado.ruta == nil and estado.retornoZona == nil
	if not sinCarga and not sinDestino then
		return false
	end
	return Perimeter.dentro(posicion, 20)
end

-- Por qué está cerrada, para que el aviso pueda decirlo. Devuelve nil si está
-- abierta: dos preguntas distintas --¿cierra? ¿por qué?-- comparten una sola regla,
-- que es lo que impide que se contradigan.
function Perimeter.motivoDeCierre(estado: EstadoRecinto?, posicion: Vector3): string?
	if not Perimeter.debeCerrar(estado, posicion) then
		return nil
	end
	return if estado ~= nil and #estado.cajas == 0 then "sin_carga" else "sin_destino"
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

-- LOS PANELES DE LA VALLA, y ahora son un ANILLO, no una linea.
--
-- Hasta el 20/08 cerraban solo la boca --el lado norte-- con un argumento que
-- parecia bueno: el resto del recinto ya esta cerrado por sus muros de piedra, asi
-- que poner barrera donde ya hay muro era redundante.
--
-- Redundante para el codigo, invisible para el jugador. Lo dijo JJ: *"la pared que
-- sale, que no nos deja salir, que sea mucho mas evidente y envuelva toda la
-- zona"*. Y el motivo es de lectura, no de fisica: una barrera en un solo lado no
-- se lee como "estas encerrado hasta que arregles el viaje", se lee como "hay un
-- panel raro ahi". Lo que comunica el encierro es el ANILLO -- mires donde mires,
-- la frontera esta, y es la misma.
--
-- Los muros siguen siendo los que paran; esto sigue siendo lo que INFORMA. Que la
-- barrera coincida con el muro en tres lados no sobra: es lo que hace que los
-- cuatro lados digan lo mismo.
--
-- `cuantos` es el numero de paneles del lado NORTE (la boca). Los otros tres
-- reciben los que les tocan segun su largo, para que el paso sea el mismo en todo
-- el anillo -- si el lado largo llevara los mismos que el corto, sus paneles
-- saldrian del doble de ancho y la valla se veria de dos materiales.
function Perimeter.postes(cuantos: number?): { Poste }
	local centro = Config.POLIGONO_CENTRO
	local medida = Config.POLIGONO_TAMANO
	local n = math.max(2, cuantos or 6)
	local lista: { Poste } = {}
	-- Un pelin mas ancho que el lado, para que no se pueda pasar rozando la esquina.
	local paso = (medida.X + 8) / n

	-- Cada lado: su eje, cuanto mide, donde esta fijo y hacia donde mira el panel.
	-- El giro es el de la CARA LARGA: norte y sur van en X (giro 0), poniente y
	-- levante en Z (giro 90).
	local lados = {
		{ largo = medida.X + 8, fijo = centro.Z - medida.Y / 2, eje = "x", giro = 0 },
		{ largo = medida.X + 8, fijo = centro.Z + medida.Y / 2, eje = "x", giro = 0 },
		{ largo = medida.Y + 8, fijo = centro.X - medida.X / 2, eje = "z", giro = 90 },
		{ largo = medida.Y + 8, fijo = centro.X + medida.X / 2, eje = "z", giro = 90 },
	}

	for _, lado in lados do
		local cuantosLado = math.max(2, math.floor(lado.largo / paso + 0.5))
		local ancho = lado.largo / cuantosLado
		for i = 1, cuantosLado do
			local d = -lado.largo / 2 + ancho * (i - 0.5)
			local pos = if lado.eje == "x"
				then Vector3.new(centro.X + d, centro.Y, lado.fijo)
				else Vector3.new(lado.fijo, centro.Y, centro.Z + d)
			table.insert(lista, {
				posicion = pos,
				giro = lado.giro,
				-- Con solape: dos paneles que se tocan justo en la punta dejan pasar
				-- por la juntura en cuanto el suelo no es perfectamente plano.
				ancho = ancho * 1.06,
			})
		end
	end
	return lista
end

-- Los paneles de LA BOCA solamente, que es el unico lado por el que se sale de
-- verdad. Lo usan las pruebas y quien tenga que hablar de la puerta y no de la caja.
function Perimeter.postesDeLaBoca(cuantos: number?): { Poste }
	local boca = Config.POLIGONO_CENTRO.Z - Config.POLIGONO_TAMANO.Y / 2
	local salida: { Poste } = {}
	for _, poste in Perimeter.postes(cuantos) do
		if math.abs(poste.posicion.Z - boca) < 0.01 then
			table.insert(salida, poste)
		end
	end
	return salida
end

return Perimeter
