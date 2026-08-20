--!strict
--[[
	Palette.luau — los colores del juego, en un solo sitio.

	Existía por duplicado: el mundo pintaba el destino rojo desde WorldBuilder y el
	selector pintaba su botón rojo desde RoutePicker, cada uno con su propia copia
	del RGB. Mientras coincidan no pasa nada; el día que alguien retoque uno, el
	botón que eliges y el sitio al que llegas dejan de ser del mismo color y el
	jugador pierde la única pista visual de que va bien.

	Aquí no hay decisiones de arte, sólo el código de cada color: el prototipo es
	deliberadamente feo (ver la cabecera de WorldBuilder).
]]

local Palette = {}

Palette.RUTAS = {
	-- El barrio en gris azulado: es el único destino que no promete peligro, y
	-- darle uno de los tres colores del semáforo lo haría parecer lo que no es.
	-- El AZUL ENTERO sigue reservado a las comisarías, así que éste tira a piedra.
	verde = Color3.fromRGB(60, 140, 70),
	ambar = Color3.fromRGB(200, 150, 50),
	roja = Color3.fromRGB(170, 60, 60),
} :: { [string]: Color3 }

Palette.DESCONOCIDO = Color3.fromRGB(120, 120, 120)

-- El ladrón: tonos apagados y oscuros. Es lo contrario del azul, que a partir
-- del cambio de tema queda RESERVADO ENTERO para las comisarías -- si el que te
-- persigue y el sitio donde te refugias comparten color, el jugador tiene que
-- pararse a mirar cuál es cuál justo cuando no puede pararse.
Palette.LADRON = Color3.fromRGB(64, 56, 62)
Palette.COMISARIA = Color3.fromRGB(74, 118, 176)

Palette.ALMACEN = Color3.fromRGB(120, 100, 60)
Palette.SALIDA = Color3.fromRGB(200, 190, 120)
Palette.TALLER = Color3.fromRGB(70, 90, 130)

-- Avisos. El rojo es "te está pasando algo malo", el ámbar "has hecho algo
-- agresivo", el verde "te ha salido bien".
Palette.AVISO_MALO = Color3.fromRGB(220, 80, 80)
Palette.AVISO_AGRESIVO = Color3.fromRGB(230, 180, 70)
Palette.AVISO_BUENO = Color3.fromRGB(120, 200, 130)

function Palette.ruta(id: string): Color3
	return Palette.RUTAS[id] or Palette.DESCONOCIDO
end

return Palette
