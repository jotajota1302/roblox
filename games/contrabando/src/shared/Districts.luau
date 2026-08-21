--!strict
--[[
	Districts.luau — que es cada manzana de la ciudad. Modulo PURO.

	POR QUE EXISTE: *"la ciudad no esta acabada, estaria bien ir zona por zona
	dejando cada manzana trabajada y que la ciudad se ampliara un poco mas pero
	creciendo desde el sentido y la logica, no copy paste"* (JJ).

	Y "copy paste" era literal. Hasta hoy TODAS las manzanas se construian con la
	misma funcion --cuatro alas por el perimetro, patio dentro, un callejon-- y lo
	unico que las distinguia era lo altas que salian las cajas. Tres manzanas
	seguidas de la misma zona eran indistinguibles, asi que la ciudad no daba
	referencias: todas las esquinas eran la misma esquina. Eso ya se pago una vez con
	el mapa del Creator Store (*"no se hacia donde tirar"*, *"el sitio es feo y
	confuso"*) y se estaba repitiendo con el mapa propio.

	LO QUE HACE FALTA NO ES MAS DETALLE: ES QUE CADA MANZANA SEA UNA COSA. Un
	mercado, una plaza, un aparcamiento, unas naves, un solar en obras. Cinco siluetas
	distintas dan cinco referencias; cincuenta cajas con ventanas dan cero.

	EL PLANO ESTA ESCRITO A MANO, Y ESO ES LA MITAD DEL PUNTO. Se podria sacar de una
	formula sobre (col, fila) --y seria una linea-- pero una formula es exactamente
	copy paste con otro nombre: reparte por aritmetica, no por sentido. Aqui los
	talleres estan pegados a tu almacen porque es donde estarian, el mercado en la
	banda comercial, las torres en el centro caro, y el poligono industrial en las
	afueras que no tienen ruta. Son veinte decisiones, y se leen de un vistazo.

	LO QUE FIJA LA PRUEBA (Districts.spec) es lo que la vista no perdona: que no haya
	tres manzanas iguales seguidas en ninguna fila ni columna --que es como se ve un
	patron-- y que cada zona tenga a la vez sitio por donde cortar y sitio que
	obligue a rodear. Si un dia alguien reordena el plano, eso sigue siendo cierto o
	la bateria se entera.
]]

local Grid = require(script.Parent.Grid)

local Districts = {}

-- LOS USOS. Cada uno es una silueta distinta desde la calle, que es el unico
-- criterio que importa: si dos usos se ven igual, sobra uno.
Districts.RESIDENCIAL = "residencial" -- el perimetro cerrado de siempre, con su callejon
Districts.TORRES = "torres" -- dos o tres bloques altos y separados, sobre zocalo
Districts.MERCADO = "mercado" -- soportales bajos y puestos con toldos dentro
Districts.TALLERES = "talleres" -- naves anchas y bajas, patio con contenedores
Districts.PLAZA = "plaza" -- cesped, arboles y fuente: el punto de referencia
Districts.PARQUE = "parque" -- arbolado sin fuente, mas suelto que la plaza
Districts.SOLAR = "solar" -- obra parada: vallas, montones y un andamio
Districts.APARCAMIENTO = "aparcamiento" -- explanada pintada con coches quietos
-- Los tres del 22/08. *"Quiero un mapa muy trabajado... que los edificios tengan
-- identidad, haya plazas, jardines etc"* (JJ). Los tres primeros usos que se anadieron
-- (mercado, solar, aparcamiento) eran explanadas; estos tres son SITIOS, cosas que
-- solo hay una o dos en una ciudad y por eso sirven para decir donde estas.
Districts.ESCUELA = "escuela" -- edificio en U con patio de recreo y pista; se rodea
Districts.CANCHA = "cancha" -- pista deportiva vallada con gradas: se cruza por las bandas
Districts.GASOLINERA = "gasolinera" -- marquesina, surtidores y tienda: la explanada mas abierta

-- POR DONDE SE PUEDE CORTAR. No es una propiedad estetica: decide si la manzana es
-- un atajo (y entonces la patrulla, atada a las calles, tiene que rodearla) o un
-- muro. La proporcion entre unas y otras es lo que hace que la calle siga siendo la
-- calle -- con media ciudad atravesable, el trazado deja de significar nada.
local ATRAVESABLE: { [string]: boolean } = {
	[Districts.PLAZA] = true,
	[Districts.PARQUE] = true,
	[Districts.SOLAR] = true,
	[Districts.APARCAMIENTO] = true,
	[Districts.MERCADO] = true,
	[Districts.CANCHA] = true,
	[Districts.GASOLINERA] = true,
	-- La ESCUELA no: su patio esta vallado, que es lo que le da sentido tenerla al
	-- lado de la plaza -- un sitio grande y reconocible que hay que RODEAR.
}

function Districts.atravesable(uso: string): boolean
	return ATRAVESABLE[uso] == true
end

-- EL PLANO, fila a fila y de oeste a este. La clave es "col,fila".
--
-- Se lee como se ve desde arriba: la primera linea es la fila 2 --la de casa, la que
-- toca el recinto-- y la ultima es la fila -1, las afueras.
local PLANO: { [string]: string } = {
	-- FILA 2 · VERDE. El barrio de casa. Sales del recinto por la calle 1, asi que
	-- las manzanas 0 y 1 son lo primero que ves de la ciudad en cada partida.
	["-2,2"] = Districts.ESCUELA, -- la esquina noroeste del barrio: un sitio, no una manzana mas
	["-1,2"] = Districts.PARQUE, -- el borde arbolado: se ve desde la salida
	["0,2"] = Districts.TALLERES, -- el poligono chico pegado a tu nave: lo que habria al lado
	["1,2"] = Districts.PLAZA, -- LA plaza, enfrente de la boca. El punto de referencia del mapa
	["2,2"] = Districts.RESIDENCIAL,
	["3,2"] = Districts.CANCHA, -- el extremo este del barrio, y la primera cosa distinta yendo al este

	-- FILA 1 · AMBAR. La banda comercial: es la que se cruza para casi todo.
	["-2,1"] = Districts.GASOLINERA, -- en la salida oeste de la ciudad, que es donde estaria
	["-1,1"] = Districts.RESIDENCIAL,
	["0,1"] = Districts.RESIDENCIAL,
	["1,1"] = Districts.MERCADO, -- el mercado, en la zona de comercio y en el eje de salida
	["2,1"] = Districts.SOLAR, -- la via de escape de la ambar (estaba aqui desde el 19/08)
	["3,1"] = Districts.TORRES, -- el primer bloque alto: marca desde lejos donde empieza lo caro

	-- FILA 0 · ROJA. El centro denso, el unico sitio donde el caserio tapa el cielo.
	["-2,0"] = Districts.TALLERES,
	["-1,0"] = Districts.RESIDENCIAL,
	["0,0"] = Districts.TORRES,
	["1,0"] = Districts.SOLAR, -- el escape de la roja hacia el oeste (tambien del 19/08)
	["2,0"] = Districts.TORRES,
	["3,0"] = Districts.APARCAMIENTO,

	-- FILA -1 · AFUERAS. Sin ruta y sin entregas: lo unico que se gana aqui son
	-- alijos. Por eso es la banda mas desahogada del mapa -- se viene a mirar, no a
	-- cruzar, y una zona por la que hay que pasar obligado no premia explorar.
	["-2,-1"] = Districts.PARQUE,
	["-1,-1"] = Districts.SOLAR,
	["0,-1"] = Districts.TALLERES,
	["1,-1"] = Districts.APARCAMIENTO,
	["2,-1"] = Districts.TALLERES,
	["3,-1"] = Districts.RESIDENCIAL,
}

-- El uso de una manzana. `residencial` de respaldo y no un error: si un dia la
-- reticula crece y el plano se queda corto, la ciudad sale entera y con una manzana
-- normal de mas, en vez de con un agujero.
function Districts.uso(col: number, fila: number): string
	return PLANO[string.format("%d,%d", col, fila)] or Districts.RESIDENCIAL
end

-- ¿Esta manzana esta ESCRITA en el plano, o le esta tocando el respaldo? Existe
-- solo para la prueba, y merece la pena: el respaldo de `uso` es lo que hace que
-- ampliar la reticula no deje agujeros, y por eso mismo una manzana olvidada saldria
-- como residencial sin que nadie se entere. La bateria pregunta por el plano, no por
-- lo que se acaba plantando.
function Districts.declarado(col: number, fila: number): boolean
	return PLANO[string.format("%d,%d", col, fila)] ~= nil
end

-- Todas las manzanas de la ciudad, con su zona y su uso. Una sola travesia de la
-- reticula, aqui, en vez de tres bucles anidados repetidos en cada llamador.
export type Manzana = {
	col: number,
	fila: number,
	zona: string,
	uso: string,
}

function Districts.manzanas(): { Manzana }
	local lista: { Manzana } = {}
	for fila = Grid.FILA_MAX - 1, Grid.FILA_MIN, -1 do
		for col = Grid.COL_MIN, Grid.COL_MAX - 1 do
			table.insert(lista, {
				col = col,
				fila = fila,
				zona = Grid.zonaDeFila(fila),
				uso = Districts.uso(col, fila),
			})
		end
	end
	return lista
end

return Districts
