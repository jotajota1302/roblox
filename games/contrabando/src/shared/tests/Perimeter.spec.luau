--!strict
local Config = require(script.Parent.Parent.Config)
local Perimeter = require(script.Parent.Parent.Perimeter)

local CENTRO = Vector3.new(0, 20, 0)
local R = 100

local function estado(cajas: number, ruta: string?, retorno: string?)
	local lista = {}
	for i = 1, cajas do
		table.insert(lista, { rareza = "comun", objeto = "cajon" })
	end
	return { cajas = lista, ruta = ruta, retornoZona = retorno }
end

return function(kit)
	-- LA REGLA: con carga y sin destino, no se sale.
	kit.truthy(
		"con carga y sin ruta, la valla se levanta",
		Perimeter.debeCerrar(estado(1), Vector3.new(50, 20, 0), CENTRO, R)
	)

	-- Y las tres formas de que NO se levante, que son las que impiden encerrar a
	-- nadie. Cada una vale por sí sola.
	kit.falsy("de vacio no hay valla", Perimeter.debeCerrar(estado(0), Vector3.new(50, 20, 0), CENTRO, R))
	kit.falsy("con ruta elegida tampoco", Perimeter.debeCerrar(estado(2, "roja"), Vector3.new(50, 20, 0), CENTRO, R))
	kit.falsy(
		"y con carga de vuelta menos: su destino ES el almacen",
		Perimeter.debeCerrar(estado(3, nil, "ambar"), Vector3.new(50, 20, 0), CENTRO, R)
	)
	kit.falsy("sin estado no se inventa una valla", Perimeter.debeCerrar(nil, Vector3.new(50, 20, 0), CENTRO, R))

	-- LA REGLA QUE EVITA EL ENCIERRO: quien está fuera nunca se encuentra una
	-- valla entre él y su almacén. Sin esto, cualquier estado raro --reaparecer
	-- fuera, un teleport-- dejaría al jugador dando vueltas alrededor de su casa.
	kit.falsy("desde fuera, la valla no existe", Perimeter.debeCerrar(estado(1), Vector3.new(300, 20, 0), CENTRO, R))

	-- En el PLANO, no en 3D: subirse a una azotea dentro del recinto no es salir.
	kit.truthy(
		"la altura no saca a nadie del recinto",
		Perimeter.debeCerrar(estado(1), Vector3.new(50, 400, 0), CENTRO, R)
	)

	-- El aviso de contacto, que es lo que reabre el selector cerrado con "Ahora no".
	kit.falsy("en el centro no estas tocando la valla", Perimeter.tocando(CENTRO, CENTRO, R, 14))
	kit.truthy("pegado a ella, si", Perimeter.tocando(Vector3.new(92, 20, 0), CENTRO, R, 14))
	-- Con margen: la valla frena antes del contacto exacto (el personaje tiene
	-- cuerpo), así que esperar a tocarla de verdad no dispararía nunca.
	kit.truthy("y justo antes de rozarla, tambien", Perimeter.tocando(Vector3.new(87, 20, 0), CENTRO, R, 14))

	-- LOS PANELES. Lo único que no se puede fallar aquí es dejar un hueco: una
	-- rendija por la que se cuela el jugador deja esto peor que no tener valla.
	local postes = Perimeter.postes(CENTRO, R, 24)
	kit.eq("salen los paneles pedidos", #postes, 24)
	for i, poste in postes do
		local dx = poste.posicion.X - CENTRO.X
		local dz = poste.posicion.Z - CENTRO.Z
		kit.near("el panel " .. i .. " esta sobre el circulo", math.sqrt(dx * dx + dz * dz), R, 0.01)
	end

	-- Anchos a medida del radio: tomar la cuerda por el arco es el error que abre
	-- las rendijas, y crece con el radio.
	local juntos = 0
	for i = 1, #postes do
		local siguiente = postes[if i == #postes then 1 else i + 1]
		local dx = postes[i].posicion.X - siguiente.posicion.X
		local dz = postes[i].posicion.Z - siguiente.posicion.Z
		local separacion = math.sqrt(dx * dx + dz * dz)
		if postes[i].ancho >= separacion then
			juntos += 1
		end
	end
	kit.eq("ningun panel deja hueco con el siguiente", juntos, #postes)

	-- La cara larga del panel, TANGENTE al círculo. Si saliera de canto, el anillo
	-- sería una fila de postes con el hueco entero entre ellos -- y eso no lo
	-- detecta ninguna de las cuentas de arriba, que sólo miran posiciones.
	for i, poste in postes do
		local rad = math.rad(poste.giro)
		-- A dónde va el eje X de la pieza tras girar `giro` grados sobre Y.
		local ejeX = Vector3.new(math.cos(rad), 0, -math.sin(rad))
		local radial = (poste.posicion - CENTRO)
		local unitaria = Vector3.new(radial.X, 0, radial.Z).Unit
		kit.near("el panel " .. i .. " es tangente al circulo", ejeX:Dot(unitaria), 0, 0.001)
	end

	-- Un número absurdo de paneles no puede producir una valla imposible.
	kit.eq("nunca menos de cuatro paneles", #Perimeter.postes(CENTRO, R, 1), 4)

	-- Y los valores por defecto son los de Config: dos copias del radio serían dos
	-- vallas distintas, la que se dibuja y la que frena.
	kit.truthy(
		"por defecto manda Config",
		Perimeter.debeCerrar(estado(1), Vector3.new(Config.RECINTO_RADIO - 5, 20, 0), Vector3.new(0, 20, 0))
	)
	kit.falsy(
		"y fuera de ese radio, no",
		Perimeter.debeCerrar(estado(1), Vector3.new(Config.RECINTO_RADIO + 5, 20, 0), Vector3.new(0, 20, 0))
	)
end
