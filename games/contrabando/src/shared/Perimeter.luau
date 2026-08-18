--!strict
--[[
	Perimeter.luau — el recinto del almacén: por dónde NO se sale. Módulo PURO.

	EL PROBLEMA, dicho por JJ jugando: "no deberías poder salir de la zona del
	almacén a la ciudad si has cargado paquete y no eliges ruta". Y tenía razón por
	partida doble:

	  · salir sin ruta es un error MUDO y CARO -- haces el viaje entero, llegas al
	    destino y no cobras, porque el servidor exige que la ruta se elija en la
	    salida y ya no puedes volver a elegirla;
	  · y el aviso de texto que había no bastaba: dura tres segundos, aparece
	    cuando ya has cruzado, y no dice cómo arreglarlo.

	La solución no es un aviso mejor: es que ese error NO SE PUEDA COMETER. Con
	carga y sin destino, el recinto está cerrado -- se ve, se choca contra él, y al
	tocarlo vuelve a ofrecerse la elección.

	TRES REGLAS que hacen que la valla nunca encierre a nadie:

	  1. sin carga, no hay valla (volver a por más es libre);
	  2. con ruta elegida, no hay valla (ya has decidido: vete);
	  3. y sólo se levanta si estás DENTRO. Quien esté fuera nunca se encuentra
	     una valla entre él y su almacén, pase lo que pase con su estado.

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

-- La distancia al centro EN EL PLANO, igual que en Shelter y por el mismo motivo:
-- la valla es un anillo, no una burbuja. Medido en 3D, subirse a una azotea de
-- diez pisos dentro del recinto contaría como estar fuera.
local function distanciaPlana(posicion: Vector3, centro: Vector3): number
	local dx = posicion.X - centro.X
	local dz = posicion.Z - centro.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- ¿Está dentro del recinto? Es la comprobación que usa el SERVIDOR para aceptar
-- una elección de ruta: elegir vale en todo el recinto, no sólo en la losa de la
-- salida. El motivo es que el selector también se abre al llegar a la valla --a
-- setenta studs de la salida-- y una pantalla cuyos botones el servidor rechaza
-- es peor que no tener pantalla.
--
-- Lo que esto NO afloja: fuera del recinto no se elige, así que sigue sin poder
-- cambiarse de ruta a mitad de viaje.
function Perimeter.dentro(posicion: Vector3, centro: Vector3, radio: number?): boolean
	return distanciaPlana(posicion, centro) <= (radio or Config.RECINTO_RADIO)
end

-- ¿Está cerrado el recinto para este jugador, ahora mismo?
--
-- La carga DE VUELTA no cuenta: en ese viaje no hay ruta que elegir (ya la
-- elegiste a la ida) y el destino es precisamente el almacén, así que una valla
-- ahí sería exactamente el encierro que la regla 3 existe para evitar.
function Perimeter.debeCerrar(estado: EstadoRecinto?, posicion: Vector3, centro: Vector3, radio: number?): boolean
	if estado == nil then
		return false
	end
	if #estado.cajas == 0 then
		return false
	end
	if estado.ruta ~= nil or estado.retornoZona ~= nil then
		return false
	end
	return Perimeter.dentro(posicion, centro, radio)
end

-- ¿Está el jugador pegado a la valla? Es lo que reabre el selector de ruta que
-- cerró con "Ahora no": llegar a la valla ES decir "ya quiero salir", y responder
-- a ese gesto con la pregunta es mejor que cualquier cartel.
--
-- El margen se mide hacia dentro: la valla frena antes de que la toques (el
-- personaje tiene cuerpo), así que esperar al contacto exacto no dispararía nunca.
function Perimeter.tocando(posicion: Vector3, centro: Vector3, radio: number?, margen: number?): boolean
	local r = radio or Config.RECINTO_RADIO
	return distanciaPlana(posicion, centro) >= r - (margen or 14)
end

export type Poste = {
	posicion: Vector3,
	giro: number, -- grados alrededor de Y, para que el panel quede tangente
	ancho: number,
}

-- Dónde van los paneles de la valla. Un anillo se dibuja con N paneles rectos, y
-- esta cuenta es la que decide cuántos y de qué ancho para que no queden huecos.
--
-- Se devuelve el ANCHO calculado en vez de dejarlo fijo porque el error de tomar
-- la cuerda por el arco crece con el radio: con paneles a medida el anillo cierra
-- solo, y con un ancho a ojo aparecerían rendijas por las que se cuela el
-- jugador -- que es el único fallo que dejaría esto peor que no tener valla.
function Perimeter.postes(centro: Vector3, radio: number?, cuantos: number?): { Poste }
	local r = radio or Config.RECINTO_RADIO
	local n = math.max(4, cuantos or Config.RECINTO_PANELES)
	local lista: { Poste } = {}
	-- La cuerda de cada sector, con un 6 % de solape: dos paneles que se tocan
	-- justo en la punta dejan pasar por la esquina en cuanto el suelo no es plano.
	local ancho = 2 * r * math.sin(math.pi / n) * 1.06
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		table.insert(lista, {
			posicion = Vector3.new(centro.X + math.cos(a) * r, centro.Y, centro.Z + math.sin(a) * r),
			-- El panel queda TANGENTE al círculo, no mirando al centro: su cara
			-- larga (el eje X de la pieza) tiene que seguir la curva. De ahí el
			-- cuarto de vuelta -- sin él los paneles saldrían de canto y el anillo
			-- sería una fila de postes con el hueco entero entre ellos.
			giro = -math.deg(a) - 90,
			ancho = ancho,
		})
	end
	return lista
end

return Perimeter
