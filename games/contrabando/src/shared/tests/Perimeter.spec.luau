--!strict
local Config = require(script.Parent.Parent.Config)
local Perimeter = require(script.Parent.Parent.Perimeter)

local CENTRO = Config.POLIGONO_CENTRO
local MEDIDA = Config.POLIGONO_TAMANO

local function estado(cajas: number, ruta: string?, retorno: string?)
	local lista = {}
	for _ = 1, cajas do
		table.insert(lista, { rareza = "comun", objeto = "cajon" })
	end
	return { cajas = lista, ruta = ruta, retornoZona = retorno }
end

local function dentroDelPoligono(): Vector3
	return Vector3.new(CENTRO.X, CENTRO.Y, CENTRO.Z)
end

return function(kit)
	-- LA REGLA: con carga y sin destino, no se sale.
	kit.truthy("con carga y sin ruta, la puerta se cierra", Perimeter.debeCerrar(estado(1), dentroDelPoligono()))

	-- Y DE VACIO TAMBIEN SE CIERRA, desde el 19/08. Es un cambio de regla pedido
	-- jugando: *"no deberia poder salir de la zona donde estan los almacenes y el
	-- taller sin paquete, deberia salir como una pared transparente roja que me
	-- obligue a ir a por un paquete"*. Salir con las manos vacias no era una jugada,
	-- era la forma mas comun de empezar mal una partida.
	--
	-- Esta linea afirmaba lo contrario y se quedo sin tocar cuando se cambio la
	-- regla, asi que la bateria defendia el diseno viejo contra el nuevo. Se ve
	-- porque falla; el peligro real es la prueba que se ajusta al codigo sin mirar,
	-- y por eso queda escrito de donde viene la regla.
	kit.truthy("de vacio la puerta se cierra", Perimeter.debeCerrar(estado(0), dentroDelPoligono()))
	kit.eq("y dice por que", Perimeter.motivoDeCierre(estado(0), dentroDelPoligono()), "sin_carga")
	kit.eq(
		"con carga y sin ruta el motivo es otro",
		Perimeter.motivoDeCierre(estado(1), dentroDelPoligono()),
		"sin_destino"
	)

	-- Las formas de que NO se cierre, que son las que impiden encerrar a nadie.
	-- Cada una vale por si sola.
	kit.falsy("con ruta elegida tampoco", Perimeter.debeCerrar(estado(2, "roja"), dentroDelPoligono()))
	kit.falsy(
		"y con carga de vuelta menos: su destino ES el almacen",
		Perimeter.debeCerrar(estado(3, nil, "ambar"), dentroDelPoligono())
	)
	kit.falsy("sin estado no se inventa una puerta", Perimeter.debeCerrar(nil, dentroDelPoligono()))

	-- LA REGLA QUE EVITA EL ENCIERRO: quien está fuera nunca se encuentra una
	-- puerta entre él y su almacén.
	local lejos = Vector3.new(CENTRO.X, CENTRO.Y, CENTRO.Z - MEDIDA.Y)
	kit.falsy("desde fuera, la puerta no existe", Perimeter.debeCerrar(estado(1), lejos))

	-- EL POLÍGONO ES UN RECTÁNGULO, no un círculo: sus esquinas cuentan, y ahí es
	-- justo donde están el almacén y el taller.
	kit.truthy("el centro esta dentro", Perimeter.dentro(CENTRO))
	kit.truthy("el almacen esta dentro", Perimeter.dentro(Config.ALMACEN_POS))
	kit.truthy("y el taller tambien", Perimeter.dentro(Config.TALLER_POS))
	kit.truthy(
		"una esquina cuenta como dentro",
		Perimeter.dentro(Vector3.new(CENTRO.X + MEDIDA.X / 2 - 2, CENTRO.Y, CENTRO.Z + MEDIDA.Y / 2 - 2))
	)
	kit.falsy(
		"y un paso mas alla, fuera",
		Perimeter.dentro(Vector3.new(CENTRO.X + MEDIDA.X / 2 + 30, CENTRO.Y, CENTRO.Z))
	)
	-- En el PLANO: subirse a un tejado dentro del recinto no es salir.
	kit.truthy("la altura no saca a nadie", Perimeter.dentro(Vector3.new(CENTRO.X, CENTRO.Y + 400, CENTRO.Z)))

	-- LA SALIDA ESTÁ EN LA BOCA NORTE, que es la que da a la ciudad. Si esto se
	-- rompe, la puerta se dibuja en el lado por el que nadie pasa.
	kit.truthy("la salida del poligono cae en el borde norte", Config.POLIGONO_SALIDA.Z <= CENTRO.Z - MEDIDA.Y / 2 + 2)
	kit.truthy(
		"y el enganche con la ciudad, mas al norte todavia",
		Config.POLIGONO_ENGANCHE.Z < Config.POLIGONO_SALIDA.Z
	)

	-- El aviso de proximidad a la puerta, que reabre el selector cerrado con
	-- "Ahora no".
	kit.truthy("junto a la boca, si", Perimeter.tocando(Vector3.new(CENTRO.X, CENTRO.Y, CENTRO.Z - MEDIDA.Y / 2 + 10)))
	kit.falsy(
		"en el fondo del poligono, no",
		Perimeter.tocando(Vector3.new(CENTRO.X, CENTRO.Y, CENTRO.Z + MEDIDA.Y / 2 - 10))
	)

	-- LOS PANELES. Lo único que no se puede fallar es dejar un hueco: una rendija
	-- por la que se cuela el jugador deja esto peor que no tener puerta.
	local postes = Perimeter.postes(6)
	kit.eq("salen los paneles pedidos", #postes, 6)
	local ancho = 0
	local minX, maxX = math.huge, -math.huge
	for _, p in postes do
		ancho += p.ancho
		minX = math.min(minX, p.posicion.X - p.ancho / 2)
		maxX = math.max(maxX, p.posicion.X + p.ancho / 2)
		kit.near("todos en la boca", p.posicion.Z, CENTRO.Z - MEDIDA.Y / 2, 0.01)
	end
	kit.truthy("los paneles cubren la boca entera", maxX - minX >= MEDIDA.X)
	kit.truthy("y con solape, sin rendijas", ancho > MEDIDA.X)

	-- Un número absurdo de paneles no puede producir una puerta imposible.
	kit.eq("nunca menos de dos paneles", #Perimeter.postes(1), 2)
end
