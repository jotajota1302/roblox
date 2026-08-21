--!strict
local Bounds = require(script.Parent.Parent.Bounds)
local Config = require(script.Parent.Parent.Config)
local Grid = require(script.Parent.Parent.Grid)

return function(kit)
	-- LO QUE NO PUEDE FALLAR NUNCA: ningún sitio donde se juega de verdad cuenta
	-- como "fuera". Un guardián con falsos positivos teletransporta a gente que
	-- está jugando bien, que es un fallo bastante peor que el que arregla.
	kit.falsy("el almacen esta dentro", Bounds.fuera(Config.ALMACEN_POS))
	kit.falsy("el centro del recinto esta dentro", Bounds.fuera(Config.POLIGONO_CENTRO))

	for i = 0, Grid.COLUMNAS do
		for j = 0, Grid.FILAS do
			local cruce = Grid.cruce(i, j)
			kit.falsy(string.format("el cruce %d,%d esta dentro", i, j), Bounds.fuera(cruce))
		end
	end

	-- Y una azotea: los edificios miden decenas de studs y subirse a uno no puede
	-- dar por perdido a nadie. Sólo se vigila hacia abajo.
	kit.falsy("una azotea sigue estando dentro", Bounds.fuera(Grid.cruce(2, 1) + Vector3.new(0, 200, 0)))

	-- EL NaN, que es el caso para el que existe el modulo. Tiene que salir por su
	-- propia rama: un NaN sale FALSO en toda comparacion (`nan < x` y `nan > x` son
	-- los dos falsos), asi que sin la comprobacion explicita se colaria por bueno.
	local nan = 0 / 0
	kit.eq("una posicion con nan se caza", Bounds.fuera(Vector3.new(nan, 19, 800)), "nan")
	kit.eq("y da igual en que eje este", Bounds.fuera(Vector3.new(-620, 19, nan)), "nan")
	kit.eq("y la altura tambien cuenta", Bounds.fuera(Vector3.new(-620, nan, 800)), "nan")

	-- La caida. A -500 Roblox destruye al personaje; esto tiene que saltar bastante
	-- antes para que dé tiempo a devolverlo.
	kit.eq("caer por debajo del mundo se caza", Bounds.fuera(Vector3.new(-620, Bounds.fondo() - 1, 800)), "abajo")
	kit.truthy("y salta antes de que Roblox destruya a -500", Bounds.fondo() > -500 + 300)
	kit.falsy("un socavon de veinte studs no cuenta", Bounds.fuera(Vector3.new(-620, Grid.Y - 20, 800)))

	-- LA RELACION QUE HACE FALSO TODO LO DEMAS. Hay una red invisible bajo el mapa
	-- que para las caidas: si el fondo del guardian quedara POR DEBAJO de ella,
	-- quien se cayera aterrizaria sobre la red, se quedaria ahi tumbado y el
	-- guardian no lo veria nunca -- que es exactamente lo que hacia la primera
	-- version. Se prueba aqui porque es la clase de cosa que se rompe cambiando un
	-- numero en el otro fichero.
	kit.truthy("el guardian caza al que cae ANTES de que llegue a la red", Bounds.fondo() > Bounds.RED_Y)
	kit.eq(
		"y quien acabe tumbado en la red cuenta como perdido",
		Bounds.fuera(Vector3.new(-620, Bounds.RED_Y + 1, 800)),
		"abajo"
	)
	kit.truthy("la red sigue muy por encima de donde Roblox destruye", Bounds.RED_Y > -500 + 300)

	-- Y los 255 km de la captura de JJ, que es el caso real que hay que cazar.
	kit.eq("los 255 km de la captura se cazan", Bounds.fuera(Vector3.new(255152, 19, 800)), "lejos")
	kit.eq("y hacia el otro lado igual", Bounds.fuera(Vector3.new(-620, 19, -80000)), "lejos")

	-- El margen es generoso A PROPOSITO: hay que estar a mas de un mapa entero de
	-- distancia para que salte. Si alguien lo aprieta un dia, esto lo dice.
	local x0, x1, z0, z1 = Bounds.caja()
	kit.truthy("la caja es mas ancha que el mapa mas dos margenes", x1 - x0 > 610 + Bounds.MARGEN)
	kit.truthy("y mas larga tambien", z1 - z0 > 465 + Bounds.MARGEN)
	kit.falsy("justo al borde de la caja todavia se juega", Bounds.fuera(Vector3.new(x0 + 1, Grid.Y, z0 + 1)))
	kit.eq("un stud mas alla ya no", Bounds.fuera(Vector3.new(x0 - 1, Grid.Y, z0 + 1)), "lejos")
end
