--!strict
local Config = require(script.Parent.Parent.Config)
local Roads = require(script.Parent.Parent.Roads)
local Vehicles = require(script.Parent.Parent.Vehicles)

return function(kit)
	-- QUÉ ES ASFALTO. Se reconoce por el color porque la ciudad es un modelo ajeno
	-- y sus piezas se llaman como les dio la gana al autor: el mismo nombre vale
	-- para una acera y para un tejado.
	kit.truthy("el gris oscuro es calzada", Roads.esCalzada(Color3.fromRGB(72, 72, 76)))
	kit.truthy("y el gris medio tambien", Roads.esCalzada(Color3.fromRGB(120, 122, 124)))
	kit.falsy("el cesped no", Roads.esCalzada(Color3.fromRGB(40, 127, 71)))
	kit.falsy("la tierra tampoco", Roads.esCalzada(Color3.fromRGB(105, 64, 40)))
	-- El blanco queda fuera a propósito: en esta ciudad las fachadas y las líneas
	-- pintadas son casi blancas, y colarlas como calzada dejaría rodar por encima
	-- de los edificios.
	kit.falsy("una fachada blanca no es calle", Roads.esCalzada(Color3.fromRGB(240, 240, 244)))
	kit.falsy("ni el amarillo de una losa del juego", Roads.esCalzada(Color3.fromRGB(214, 176, 70)))

	-- QUIÉN NECESITA ASFALTO. Es la decisión de diseño entera en dos líneas: los
	-- baratos van por todas partes, los de motor van deprisa pero atados a la calle.
	--
	-- Y EL CARRO ROMPE EL PATRON A PROPOSITO (22/08). Era el escalón del coche, que sí
	-- exigía calzada, y ahora se TIRA yendo a pie: entras donde entra un peatón. Lo que
	-- te quita es lo otro -- ocupa la ranura, así que con el carro puesto no llevas
	-- impulsor y no subes a ningún tejado.
	--
	-- El remolque sí la conserva, y esa línea es la que salva la pieza que `Roads.luau`
	-- llama "la mejor que se le ha añadido al juego": por la calle deprisa y visible, o
	-- a pie por los atajos. Si TODO el catálogo fuera a pie, esa decisión se evaporaba.
	kit.falsy("ir a pie no depende de la calzada", Roads.exigeCalzada("a_pie"))
	kit.falsy("el monopatin va por donde sea", Roads.exigeCalzada("monopatin"))
	kit.falsy("y el patinete", Roads.exigeCalzada("patinete"))
	kit.falsy("el impulsor tampoco: se lleva puesto", Roads.exigeCalzada("impulsor"))
	kit.truthy("la moto necesita calle", Roads.exigeCalzada("moto"))
	kit.falsy("el carro NO, que se tira a pie", Roads.exigeCalzada("carro"))
	kit.truthy("pero el remolque si", Roads.exigeCalzada("remolque"))

	-- Y QUE SIGA HABIENDO DE LAS DOS CLASES, con el catálogo que sea. Es lo que de
	-- verdad hay que proteger: el día que el último `soloCalzada` se fuera del
	-- catálogo, la decisión "por la calle o por los atajos" desaparecería sin que nada
	-- diera error -- y con ella el sistema entero de rutas y patrullas.
	local Config = require(script.Parent.Parent.Config)
	local atados, libres = 0, 0
	for _, v in Config.VEHICULOS do
		if Roads.exigeCalzada(v.id) then
			atados += 1
		else
			libres += 1
		end
	end
	kit.truthy(string.format("hay vehiculos atados a la calzada (%d)", atados), atados >= 1)
	kit.truthy(string.format("y los hay que van por todas partes (%d)", libres), libres >= 1)
	kit.falsy("un vehiculo inventado no exige nada", Roads.exigeCalzada("submarino"))
	kit.falsy("y nil tampoco revienta", Roads.exigeCalzada(nil))

	-- Rodar aquí y ahora.
	kit.truthy("la moto rueda en la calle", Roads.puedeRodar("moto", true))
	kit.falsy("pero no en el parque", Roads.puedeRodar("moto", false))
	kit.truthy("el patinete rueda en el parque", Roads.puedeRodar("patinete", false))
	kit.falsy("a pie no se rueda", Roads.puedeRodar("a_pie", true))

	-- LA VELOCIDAD LA DA EL VEHÍCULO SÓLO SI VAS MONTADO. Con la moto aparcada al
	-- otro lado del parque vas a pie, aunque la moto siga siendo tuya.
	kit.eq("montado cuenta tu vehiculo", Roads.vehiculoQueCuenta("moto", true), "moto")
	kit.eq("aparcado cuentas tu como si fueras a pie", Roads.vehiculoQueCuenta("moto", false), Config.VEHICULO_INICIAL)

	-- Y LA REGLA QUE NO SE PUEDE ROMPER: el que va atado a la calzada tiene que
	-- ganar algo por estarlo. Si un vehículo de calle no fuera más rápido que uno
	-- que va por todas partes, comprarlo sería un castigo pagado con dinero.
	local libreMasRapido = 0
	for _, v in Config.VEHICULOS do
		if not v.soloCalzada then
			libreMasRapido = math.max(libreMasRapido, v.velocidadBase)
		end
	end
	for _, v in Config.VEHICULOS do
		if v.soloCalzada then
			kit.truthy(
				string.format("%s compensa ir atado a la calle (%d > %d)", v.id, v.velocidadBase, libreMasRapido),
				v.velocidadBase > libreMasRapido
			)
		end
	end

	-- Y ninguno pasa del tope antitrampas, que sigue existiendo: una velocidad por
	-- encima de él la rechaza el propio juego como imposible.
	for _, v in Config.VEHICULOS do
		kit.truthy(
			string.format("%s no pasa del tope antitrampas", v.id),
			Vehicles.get(v.id).velocidadBase < Config.VELOCIDAD_MAXIMA_PLAUSIBLE
		)
	end
end
