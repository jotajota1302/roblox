--!strict
local Cargo = require(script.Parent.Parent.Cargo)
local Config = require(script.Parent.Parent.Config)
local Goods = require(script.Parent.Parent.Goods)
local Vehicles = require(script.Parent.Parent.Vehicles)

return function(kit)
	-- LA REGLA NUEVA, que es de donde vive todo esto: no puedes llevar algo grande
	-- sin un vehículo para ello. Es lo que convierte al vehículo en una llave en
	-- vez de en un número de capacidad.
	local piano = { rareza = "sellada", objeto = "piano" }
	local sobre = { rareza = "marcada", objeto = "sobre" }

	local puedeAPie, motivo = Cargo.cabe({}, piano, 100, nil)
	kit.falsy("un piano no entra a pie, por mucho hueco que sobre", puedeAPie)
	kit.eq("y se dice que el problema es el vehiculo", motivo, "vehiculo_insuficiente")

	kit.truthy("pero un sobre si", (Cargo.cabe({}, sobre, 3, nil)))
	kit.truthy("y el piano entra en furgoneta", (Cargo.cabe({}, piano, 100, "furgoneta")))

	-- Y quedarse sin hueco es OTRA cosa, con otro motivo: uno dice vacía el zurrón
	-- y el otro dice ve a comprarte una moto. Desde dentro se ven igual --la pieza
	-- no se recoge-- y sin distinguirlos el jugador no sabe qué hacer.
	local lleno, motivoLleno = Cargo.cabe({ sobre, sobre, sobre }, sobre, 3, nil)
	kit.falsy("con el zurron lleno no cabe mas", lleno)
	kit.eq("y ese motivo es distinto", motivoLleno, "sin_hueco")

	-- La escalera de vehículos tiene que subir SIEMPRE en capacidad: si un peldaño
	-- diera menos que el anterior, comprarlo sería pagar por empeorar, y
	-- Vehicles.puedeComprar lo bloquearía dejando la tienda muerta a partir de ahí.
	local anterior = nil
	for _, v in Config.VEHICULOS do
		if anterior then
			kit.truthy(
				string.format("%s lleva mas que %s", v.nombre, anterior.nombre),
				v.capacidad > anterior.capacidad
			)
			kit.truthy(string.format("%s cuesta mas que %s", v.nombre, anterior.nombre), v.coste > anterior.coste)
			kit.truthy(
				string.format("%s no admite menos tamano que %s", v.nombre, anterior.nombre),
				v.tamanoMaximo >= anterior.tamanoMaximo
			)
		end
		anterior = v
	end

	-- LA REGLA DE ORO DEL DISEÑO: se progresa por capacidad y acceso, NUNCA por
	-- potencia. En el momento en que alguien es inalcanzable, el PvP muere y las
	-- rutas rojas pasan a ser dinero gratis. La capacidad se multiplica por ocho de
	-- punta a punta; la velocidad no puede ni acercarse a eso.
	local primero = Config.VEHICULOS[1]
	local ultimo = Config.VEHICULOS[#Config.VEHICULOS]
	kit.truthy("la capacidad crece mucho", ultimo.capacidad >= primero.capacidad * 6)
	kit.truthy("pero la velocidad casi nada", ultimo.velocidadBase < primero.velocidadBase * 1.5)
	kit.truthy("y nadie pasa del tope anticheat", ultimo.velocidadBase < Config.VELOCIDAD_MAXIMA_PLAUSIBLE)

	-- Todo objeto del catálogo tiene que ser alcanzable por ALGÚN vehículo, o sería
	-- mercancía que no se puede mover nunca: ocuparía sitio en el almacén y no
	-- habría forma de sacarla.
	local tope = 0
	for _, v in Config.VEHICULOS do
		tope = math.max(tope, v.tamanoMaximo)
	end
	for _, o in Goods.todos() do
		kit.truthy("el objeto " .. o.id .. " se puede mover con algo", Goods.nivelExigido(o.id) <= tope)
		kit.truthy("y ocupa algo", Goods.huecos(o.id) > 0)
	end

	-- Y a pie tiene que haber DE SOBRA con qué trabajar desde el primer minuto: si
	-- lo pequeño fuese raro, el jugador nuevo se quedaría mirando un almacén lleno
	-- de cosas que no puede tocar.
	local rng = Random.new(7)
	local aPie, total = 0, 400
	for _ = 1, total do
		if Goods.nivelExigido(Goods.tirada(rng, 1).id) <= 1 then
			aPie += 1
		end
	end
	kit.eq("con el tope a 1 solo sale lo pequeno", aPie, total)

	-- Con el tope alto siguen saliendo cosas pequeñas: lo grande es la excepción
	-- que emociona, no el pan de cada día.
	local grandes = 0
	for _ = 1, total do
		if Goods.nivelExigido(Goods.tirada(rng, 4).id) >= 3 then
			grandes += 1
		end
	end
	kit.truthy("lo grande sale, pero es minoria", grandes > 0 and grandes < total * 0.4)

	-- La medida de cada objeto se nota: un sofá es más ancho que alto y una estatua
	-- al revés. Es lo que permite saber QUÉ lleva otro jugador, no sólo que lleva.
	local sofa = Goods.medida("sofa", 1)
	local estatua = Goods.medida("estatua", 1)
	kit.truthy("el sofa es mas ancho que alto", sofa.X > sofa.Y)
	kit.truthy("la estatua mas alta que ancha", estatua.Y > estatua.X)
	kit.truthy("y lo enorme es mayor que lo pequeno", estatua.Y > Goods.medida("sobre", 1).Y)

	-- Una carga vieja (sin objeto, de antes del catálogo) tiene que seguir
	-- valiendo: cae a lo que diga su rareza en vez de romper la partida guardada.
	kit.truthy("una caja sin objeto sigue cabiendo", (Cargo.cabe({}, { rareza = "comun" }, 3, nil)))
	kit.truthy("y tiene etiqueta", #Goods.etiqueta(nil, "comun") > 0)

	-- Un id inventado no puede tumbar el dibujado de una pieza.
	kit.truthy("un objeto desconocido no revienta", Goods.medida("dragon", 1).Y > 0)
	kit.eq("y no exige mas que lo minimo", Goods.nivelExigido("dragon"), 1)

	-- El vehículo por defecto sigue siendo el de a pie, y sólo admite lo pequeño.
	kit.eq("a pie es el vehiculo inicial", Vehicles.deEstado(nil).id, Config.VEHICULO_INICIAL)
	kit.eq("y solo admite lo pequeno", Vehicles.deEstado(nil).tamanoMaximo, 1)
end
