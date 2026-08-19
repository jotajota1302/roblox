--!strict
--[[
	Config.luau — todas las constantes del juego en un único sitio. Sin lógica.

	LOS VALORES DE PROTOTIPO SE ELIGEN CON UN INTERRUPTOR, `Config.PROTOTIPO`, y no
	editando números a mano. Antes eran cinco constantes con un comentario al lado
	que decía a cuánto había que devolverlas -- o sea cinco ediciones que había que
	acordarse de hacer, todas juntas, el día de publicar, y ninguna de las cuales
	avisa si se olvida: el juego sale a producción con las legendarias diez veces
	más frecuentes de lo diseñado y la nave produciendo seis veces más deprisa, y
	todo funciona. Con el interruptor, publicar es cambiar `true` por `false`.

	Y las dos tablas están SIEMPRE presentes, así que las pruebas comprueban también
	la de producción -- que hasta ahora vivía en comentarios y no la había validado
	nadie nunca.
]]

local Config = {}

-- ¿Estamos midiendo o estamos jugando?
--
-- En prototipo, la mercancía buena sale mucho más a menudo y la nave produce cada
-- 30 s en vez de cada 3 min: es la única forma de ver una legendaria o un almacén
-- lleno sin jugar una hora, y sin verlos no se puede ajustar nada.
--
-- **A `false` antes de publicar.** Lo recuerda `VERIFICACION.md` §4, y ahora es una
-- sola línea en vez de cinco.
Config.PROTOTIPO = true

-- Economía
Config.CAJA_VALOR_BASE = 10
Config.DINERO_INICIAL = 0

-- Carga a pie
Config.CAPACIDAD_A_PIE = 3
Config.VELOCIDAD_BASE = 16
Config.PENALIZACION_POR_CAJA = 1.4 -- studs/s menos por unidad de peso transportada

-- Vehículos: el sumidero de dinero, y la regla de diseño innegociable es que la
-- progresión va por CAPACIDAD Y ACCESO, NUNCA POR POTENCIA. Ningún vehículo te
-- hace inatrapable: en el momento en que alguien es inalcanzable, el PvP muere y
-- las rutas rojas pasan a ser dinero gratis.
--
-- Por qué cada vehículo lleva su PROPIA penalización por peso en vez de compartir
-- PENALIZACION_POR_CAJA: con la penalización de ir a pie (1,4 por unidad), una
-- furgoneta cargada con sus 10 cajas caería a 0,4 studs/s y la salvaría el suelo
-- de velocidad -- es decir, iría al mínimo SIEMPRE, con lo que su capacidad no
-- valdría nada y no habría gradiente que decidir. Con 0,45 el recorrido va de
-- 14,4 (vacía) a 9,9 (a tope): siempre por debajo del equivalente a pie, que es
-- lo que exige "capacidad contra exposición", pero con margen real de decisión.
-- TAMAÑOS de la mercancía, y qué hace falta para moverla.
--
-- Es la regla que ata la progresión a lo que llevas, en vez de dejarla como un
-- número suelto de capacidad: **no puedes llevar algo grande sin un vehículo para
-- ello**. Con esto, ver en el almacén un objeto que paga x50 y no poder cogerlo es
-- lo que le da destino al dinero -- el vehículo deja de ser "una caja más" y pasa
-- a ser una LLAVE.
--
-- `huecos` es lo que ocupa de la capacidad; `nivel` es el listón que el vehículo
-- tiene que alcanzar para admitirlo.
--
-- `bono` es LO QUE PAGA DE MÁS POR SER GRANDE, y llegó midiendo. Sin él, esto es
-- lo que pagaba cada tamaño por hueco ocupado:
--
--     pequeño 54,7   mediano 40,5   grande 39,3   enorme 33,6
--
-- Es decir: cuanto más grande, PEOR negocio. El piano era lo más vistoso del
-- catálogo y lo peor que podías cargar, y el vehículo grande se vendía como "por
-- fin puedes llevar el piano" -- o sea, vendía una trampa. Con medio catálogo
-- siendo decoración cara, la mitad del garaje se quedaba sin motivo.
--
-- El bono invierte la curva: mover algo enorme exige vehículo, y lo que exige
-- inversión tiene que devolverla. La progresión sigue siendo por capacidad y
-- acceso, no por potencia.
Config.TAMANOS = {
	{ id = "pequeno", nivel = 1, huecos = 1, bono = 1 },
	{ id = "mediano", nivel = 2, huecos = 2, bono = 1.6 },
	{ id = "grande", nivel = 3, huecos = 4, bono = 2 },
	{ id = "enorme", nivel = 4, huecos = 8, bono = 2.6 },
}

-- `soloCalzada` marca los que NO pueden salirse del asfalto (ver Roads.luau). Es
-- lo que convierte el vehículo en una decisión en vez de en una mejora pasiva: los
-- caros corren, pero van por donde va todo el mundo; los baratos son lentos y
-- entran en cualquier callejón. Y si te sales con uno de motor, se queda aparcado
-- donde lo dejaste y hay que volver a por él.
--
-- POR ESO las velocidades ya no son casi planas. La regla vieja las mantenía entre
-- 16 y 22 para que nadie fuera inatrapable; esa regla SIGUE VIGENTE pero ahora se
-- sostiene por otro sitio -- quien te persigue puede cortar por donde tú no
-- puedes-- y eso permite que comprar una moto se note de verdad.
-- `expone` y `bulto` son EL EJE QUE EL PLAN ORIGINAL TENÍA Y SE PERDIÓ. El diseño
-- daba a cada vehículo una consecuencia distinta al ser alcanzado ("sueltas todo"
-- / "pierdes el 30 %" / "aguanta dos toques") y eso desapareció por el camino sin
-- que nadie lo decidiera: hoy todos pierden exactamente lo mismo.
--
-- Recuperado en dos números que se pelean entre sí, que es lo que lo hace una
-- decisión y no una mejora:
--
--   · `expone`  -- qué fracción de la carga pierdes cuando te alcanzan. A pie lo
--                  sueltas todo; en furgoneta, menos de un tercio.
--   · `bulto`   -- cuánto más lejos te fichan. Una furgoneta se ve venir; un
--                  monopatín, no.
--
-- Así lo grande no es "mejor": aguanta más golpes pero recibe más. Y encima va
-- atado al asfalto (soloCalzada). La regla de oro sigue intacta -- nadie corre más
-- por tener el vehículo caro.
-- `nivel` es EL NIVEL MÍNIMO PARA COMPRARLO, y llegó con la licencia (ver
-- RUMBO.md §3.A). Antes el único requisito era el dinero, y medido salía esto: la
-- ruta roja multiplica por diez GRATIS desde el primer minuto, mientras el garaje
-- entero cuesta 31.950 monedas para dar un ×2,15. El sumidero competía contra una
-- palanca que no costaba nada, y perdía.
--
-- Atar los peldaños al nivel no es una traba: es lo que convierte la experiencia
-- --que hasta ahora era un número que subía y nada más-- en el permiso para
-- acceder a lo siguiente. Y sigue siendo ACCESO, no potencia, que es la regla que
-- no se toca.
Config.VEHICULOS = {
	{
		id = "a_pie",
		capacidad = Config.CAPACIDAD_A_PIE,
		velocidadBase = Config.VELOCIDAD_BASE,
		penalizacionPorPeso = Config.PENALIZACION_POR_CAJA,
		tamanoMaximo = 1,
		coste = 0,
		nivel = 1,
		expone = 1.0,
		bulto = 1.0,
	},
	-- EL PRIMER PELDAÑO. Antes eran los patines (150) y se quitaron enteros a
	-- petición de JJ: van en los PIES, y eso pelea con la animación de andar --
	-- un personaje que camina con los patines puestos se ve mal se ponga donde se
	-- ponga. El monopatín hace el mismo papel (barato, va por todas partes) y
	-- además va DEBAJO del personaje, que es un sitio sin conflictos.
	--
	-- Hereda su precio, no el suyo: la primera compra tiene que caer en los
	-- primeros viajes o el dinero no significa nada al empezar.
	{
		id = "monopatin",
		capacidad = 5,
		velocidadBase = 19,
		penalizacionPorPeso = 1.0,
		tamanoMaximo = 2,
		coste = 150,
		nivel = 1,
		expone = 1.0,
		bulto = 1.0,
	},
	{
		id = "patinete",
		capacidad = 6,
		velocidadBase = 20,
		penalizacionPorPeso = 0.9,
		tamanoMaximo = 2,
		coste = 400,
		nivel = 2,
		expone = 0.9,
		bulto = 1.05,
	},
	{
		id = "patinete_electrico",
		capacidad = 7,
		velocidadBase = 24,
		penalizacionPorPeso = 0.8,
		tamanoMaximo = 2,
		soloCalzada = true,
		coste = 1400,
		nivel = 3,
		expone = 0.8,
		bulto = 1.15,
	},
	{
		id = "bicicleta",
		capacidad = 9,
		velocidadBase = 26,
		penalizacionPorPeso = 0.7,
		tamanoMaximo = 3,
		soloCalzada = true,
		coste = 2500,
		nivel = 4,
		expone = 0.7,
		bulto = 1.2,
	},
	{
		id = "moto",
		capacidad = 12,
		velocidadBase = 32,
		penalizacionPorPeso = 0.55,
		tamanoMaximo = 3,
		soloCalzada = true,
		coste = 4500,
		nivel = 6,
		expone = 0.55,
		bulto = 1.3,
	},
	{
		id = "coche",
		capacidad = 18,
		velocidadBase = 34,
		penalizacionPorPeso = 0.4,
		tamanoMaximo = 4,
		soloCalzada = true,
		coste = 8000,
		nivel = 8,
		expone = 0.4,
		bulto = 1.45,
	},
	{
		id = "furgoneta",
		capacidad = 26,
		velocidadBase = 30,
		penalizacionPorPeso = 0.28,
		tamanoMaximo = 4,
		soloCalzada = true,
		coste = 15000,
		nivel = 10,
		expone = 0.3,
		bulto = 1.6,
	},
}

Config.VEHICULO_INICIAL = "a_pie"

-- Rarezas: multiplicador de valor, peso que ocupa y probabilidad.
-- El peso de la legendaria es exactamente CAPACIDAD_A_PIE: cabe, pero te ocupa todo.
--
-- Las dos repartidas están aquí a la vez, y el interruptor elige. Las de producción
-- son las de `DISENO.md`; las de medir aflojan la cola para que una legendaria salga
-- en una sesión y no en una tarde.
Config.RAREZAS_PRODUCCION = {
	{ id = "comun", multiplicador = 1, peso = 1, probabilidad = 0.90 },
	{ id = "marcada", multiplicador = 10, peso = 1, probabilidad = 0.08 },
	{ id = "sellada", multiplicador = 50, peso = 2, probabilidad = 0.018 },
	{ id = "legendaria", multiplicador = 135, peso = 3, probabilidad = 0.002 },
}
Config.RAREZAS_PROTOTIPO = {
	{ id = "comun", multiplicador = 1, peso = 1, probabilidad = 0.70 },
	{ id = "marcada", multiplicador = 10, peso = 1, probabilidad = 0.20 },
	{ id = "sellada", multiplicador = 50, peso = 2, probabilidad = 0.08 },
	{ id = "legendaria", multiplicador = 135, peso = 3, probabilidad = 0.02 },
}
Config.RAREZAS = if Config.PROTOTIPO then Config.RAREZAS_PROTOTIPO else Config.RAREZAS_PRODUCCION

-- Dónde se planta el juego DENTRO de la ciudad (ver DISENO-CIUDAD.md §3).
--
-- No son cifras elegidas a ojo sobre un plano: salen de barrer el mapa con rayos
-- buscando parcelas con suelo bajo y hueco libre en 40 studs a la redonda -- 510
-- candidatas-- y quedarse con las que mejor clavan las distancias que se querían.
-- Un emplazamiento puesto a ojo acaba dentro de un edificio o en una azotea, y eso
-- no se ve hasta que alguien da a Play.
--
-- El almacén va en la esquina más apartada a propósito: la zona segura tiene que
-- estar lejos de todo lo demás para que SALIR signifique algo.
--
-- Este punto concreto se eligió DOS VECES. La primera vez bastaba con que hubiera
-- suelo plano, y el almacén acabó plantado encima de una pista de tenis de la
-- ciudad -- lo dijo JJ jugando: "estaría bien que el almacén no estuviera encima
-- de nada". El criterio bueno es más estricto y es el que se aplicó después: que
-- EL POLÍGONO: nuestra propia explanada, FUERA de la ciudad.
--
-- Las dos primeras versiones metieron el almacén dentro del mapa ajeno y las dos
-- salieron mal: la primera cayó sobre una pista de tenis, la segunda sobre una de
-- baloncesto con la canasta asomando por encima del tejado. El parche era
-- despejar la parcela --borrar las piezas de la ciudad que estorbaban-- y JJ puso
-- el dedo en la llaga: "que el almacén y el taller tengan su zona y no se pongan
-- encima del mapa de la ciudad tapando cosas".
--
-- Tiene razón por dos motivos, y el segundo importa más que el primero:
--
--   · destruir el mapa para hacerle sitio a lo nuestro deja huecos raros que
--     nadie entiende (media pista de baloncesto, una valla cortada);
--   · y un almacén metido entre edificios NO SE LEE como "tu base". La ciudad es
--     el sitio al que sales; si tu casa está dentro de ella, salir no significa
--     nada.
--
-- Así que el juego se planta en un polígono propio pegado al borde suroeste,
-- construido por nosotros (ver CityBuilder.explanada), con su carretera de acceso
-- a la ciudad. La ciudad no se toca ni un stud, y cruzar esa carretera es
-- literalmente salir de casa.
--
-- La ciudad va de X -774 a 774 y de Z -790 a 780 (medido). El polígono empieza
-- justo detrás de ese borde.
Config.POLIGONO_CENTRO = Vector3.new(-620, 19.2, 880)
Config.POLIGONO_TAMANO = Vector2.new(360, 250)
-- Por dónde se sale a la ciudad: el extremo norte del polígono, y desde ahí una
-- carretera hasta la calle más cercana.
-- EN LA BOCA EXACTA (centro.Z - alto/2 = 880 - 115), no unos studs más adentro:
-- la salida es el umbral, y la prueba de Perimeter lo comprueba porque puesta a
-- ojo se queda en mitad del patio y deja de significar "aquí se sale".
-- DERIVADA del borde, no escrita a mano. Se puso a ojo dos veces y las dos se
-- quedó dentro del patio al cambiar el tamaño del polígono -- la prueba de
-- Perimeter lo cazó las dos veces, pero una constante que hay que acordarse de
-- mover a mano cada vez que crece el recinto es una trampa esperando.
Config.POLIGONO_SALIDA = Vector3.new(
	Config.POLIGONO_CENTRO.X,
	Config.POLIGONO_CENTRO.Y,
	Config.POLIGONO_CENTRO.Z - Config.POLIGONO_TAMANO.Y / 2
)
Config.POLIGONO_ENGANCHE = Vector3.new(-593, 19.2, 679) -- la calle de la ciudad más cercana (medida)

-- EL ALMACÉN Y EL TALLER, PEGADOS A LA BOCA DEL RECINTO (19/08).
--
-- Estaban en el fondo del polígono, a 177 studs de la salida: **quince segundos de
-- andar por tu propio patio antes de que empiece el juego**, y otros quince al
-- volver. Medido el ciclo del reparto más corto que existe --el del tutorial-- eran
-- 87 segundos, y más de la mitad era desplazamiento sin nada que decidir.
--
-- Ahora están a 77 studs de la boca. No es un ajuste de estética: es la mitad de
-- los treinta segundos que se iban en entrar y salir de casa.
Config.ALMACEN_POS = Vector3.new(-668, 19.2, 815)
Config.TALLER_POS = Vector3.new(-580, 19.2, 815)

-- Rutas. Ya NO se definen por distancia sino por DESTINO: con la ciudad de por
-- medio, la distancia es una consecuencia de dónde cae el sitio y de qué calles
-- te dejan llegar, no un parámetro que se elige. Lo que antes eran tres tramos de
-- la misma recta ahora son tres barrios con carácter propio, que es lo que
-- convierte la decisión de ruta de aritmética ("¿cuánto ando por cuánto cobro?")
-- en cualitativa ("¿qué tipo de peligro sé manejar?").
--
-- Distancias en línea recta desde el almacén: 420 / 848 / 1399. Andando serán más,
-- porque hay manzanas de por medio. La ROJA además obliga a cruzar a la parcela
-- separada del noreste por un paso estrecho: un cuello de botella natural para
-- emboscadas y patrullas que ninguna recta podía darnos.
--
-- `detectores` es la densidad de vigilancia de cada zona, y es lo que de verdad
-- las diferencia. La verde lleva unos pocos A PROPÓSITO y no cero: es donde se
-- aprende qué es un detector sin que salga caro.
-- `nivel` es el nivel mínimo para poder elegirla y `exigeMotor` pide además un
-- vehículo de calzada. Las dos cosas son LA LICENCIA (RUMBO.md §3.A): sin ellas,
-- el jugador nuevo elige la roja en su primer minuto, cobra diez veces más sin
-- haber hecho nada por merecerlo, y el resto de la progresión se queda sin sentido.
Config.RUTAS = {
	-- EL BARRIO: la rampa de entrada, y el único destino que existe al empezar.
	--
	-- POR QUÉ. Medido: la primera recompensa del juego llegaba a los ~100 s, y en el
	-- juego que inspiró esta tanda llega a los 3. La verde son 823 studs ANDANDO
	-- (camino real, no línea recta), o sea 56 s cargado -- más los 176 studs que ya
	-- hay del almacén a la salida. Para el que acaba de entrar, eso es todo lo que
	-- hay antes del primer premio.
	--
	-- EL ×0,4 SALE DE UNA CUENTA, no de un ajuste a ojo, y la primera versión de esto
	-- lo tenía mal. Con ×0,5 el barrio rendía MÁS que la verde: 119 monedas por
	-- minuto contra 113 a pie, y 1.028 contra 979 con furgoneta. O sea que un
	-- veterano tenía motivo para quedarse dando vueltas en el viaje de tutorial,
	-- que es exactamente lo que este multiplicador venía a evitar.
	--
	-- La cuenta usa el valor esperado de una caja (94 monedas: 70 % común, 20 %
	-- marcada ×10, 8 % sellada ×50, 2 % legendaria ×135) y los ciclos completos
	-- medidos -- 71 s el barrio, 150 s la verde, ida y vuelta incluidas.
	--
	-- Con ×0,4: barrio 95/min contra verde 113/min a pie, y 822 contra 979 con
	-- furgoneta. La verde gana en los dos casos, que es lo que tenía que pasar: el
	-- barrio es la puerta de entrada, no un atajo. Y por eso tampoco hace falta
	-- cerrarlo nunca.
	--
	-- SIN GUARIDAS y con una sola esquina fichada: el peligro se enseña, no se
	-- aplica. Perder la primera carga de tu vida es la forma más rápida de que
	-- alguien cierre el juego.
	--
	-- EL DESTINO, YA MEDIDO (19/08). El anterior --(-428, 623)-- estaba interpolado
	-- a ojo entre el enganche y la verde, y al medirlo con el pathfinder dentro del
	-- juego resultó que **no tenía camino desde ninguna parte**: caía debajo de un
	-- árbol de la ciudad, y la zona no era navegable en cincuenta studs a la
	-- redonda. La ruta del tutorial, la primera que juega alguien, era imposible de
	-- recorrer andando, y no lo dijo nadie porque nada revienta: la losa se planta,
	-- la baliza se ve, y el jugador simplemente no llega.
	--
	-- Es la trampa de los árboles otra vez (`CLAUDE.md`): el rayo desde el cielo se
	-- para en la copa, así que "el suelo" ahí sale a 87 studs de altura.
	--
	-- Éste está sobre calzada de verdad (Stone, no césped), sin copa encima, a 205
	-- studs de camino desde la salida --dentro de los 200-350 que exige la sonda de
	-- SelfCheck-- y a 358 del destino verde, que pide 250 como mínimo.
	{
		id = "barrio",
		multiplicador = 0.4,
		nivel = 1,
		destino = Vector3.new(-650, 19.2, 680),
		detectores = 1,
		guaridas = 0,
		-- SIN REFUGIOS, y no es un olvido: un refugio es el sitio donde te salvas de
		-- los ladrones, y aquí no hay ladrones. Pero además arregla un fallo medido:
		-- al entrar el barrio, sus candidatos a refugio competían con los de la
		-- verde --Shelter.repartir descarta los que caen a menos de 320 studs entre
		-- sí-- y LA VERDE SE QUEDABA SIN NINGUNO. Una ruta con peligro sin sitio
		-- donde refugiarse es una promesa rota.
		refugios = 0,
		pvp = "ninguno",
	},
	{
		id = "verde",
		multiplicador = 1,
		nivel = 1,
		-- ACERCADO EL 19/08, y el motivo está medido con el pathfinder dentro del
		-- juego: el destino viejo (-180, 540) quedaba a 436 studs en línea recta
		-- pero a **768 andando** -- un factor ×1,76, el peor de las cuatro rutas.
		-- La primera ruta que juega alguien eran 96 segundos de ida y vuelta antes
		-- de sumar cargar, elegir y entregar. JJ lo jugó y lo dijo en una línea:
		-- "es muy largo".
		--
		-- El sitio nuevo es un punto DEL CAMINO REAL viejo, así que no se ha
		-- inventado: es por donde ya se pasaba, y cae sobre calzada.
		--
		-- No está más cerca todavía por una regla que ya existía y que conviene no
		-- romper: `Mapa.spec` exige que dos destinos no queden a menos de 250 studs
		-- --dos porterías juntas se confunden al llegar, y entregar en la
		-- equivocada es perder el viaje entero--. Los puntos más cercanos del
		-- camino caían a 206-245 del barrio.
		--
		-- Y ESTÁ EN LLANO, que fue la segunda vuelta y se volvió a confirmar el 19/08.
		-- El otro sitio candidato, (-170, 669), cumple todas las distancias y además
		-- da un camino bastante más corto --511 studs contra 679, o sea 77 segundos
		-- de ciclo contra 96--, pero cae en cuesta: su carretera de acceso deja un
		-- canto de 2,6 studs donde nace, y ahí se traba el vehículo. Se probó a
		-- suavizar la pendiente máxima de las vías (0,21 → 0,17) y el canto sigue.
		--
		-- Se elige el llano: diecinueve segundos de viaje valen menos que un sitio
		-- donde el jugador se queda enganchado sin entender por qué.
		destino = Vector3.new(-620, 19.2, 555),
		detectores = 3,
		pvp = "ninguno",
	},
	{
		id = "ambar",
		multiplicador = 3,
		nivel = 3,
		-- ACERCADA igual que la verde: 1.034 studs de camino real eran 129 s de ida
		-- y vuelta a pie. El punto nuevo está a 740 del enganche sobre ese mismo
		-- camino -- 46 s de ida a pie, 31 con patinete eléctrico.
		destino = Vector3.new(-481, 19.2, 456),
		detectores = 9,
		pvp = "transportistas",
	},
	{
		id = "roja",
		multiplicador = 10,
		nivel = 8,
		-- Y ADEMÁS PIDE VEHÍCULO DE MOTOR. Es la única ruta con dos requisitos, y
		-- es a propósito: el ×10 es la palanca más fuerte del juego y tenía que
		-- estar DETRÁS del sumidero en vez de compitiendo con él. Con esto, el
		-- dinero que se gasta en el taller compra algo que el dinero solo no daba.
		exigeMotor = true,
		-- ACERCADA, y era la más urgente de las tres: 1.813 studs de camino real,
		-- o sea **227 segundos de ida y vuelta a pie**. Casi cuatro minutos de una
		-- sesión que en Roblox dura seis. El punto nuevo está a 1.050 del enganche
		-- sobre el mismo camino: 66 s de ida a pie, 31 en coche.
		--
		-- LO QUE SE PIERDE, y conviene tenerlo escrito: el destino viejo obligaba a
		-- cruzar a la parcela del noreste por un paso estrecho, un cuello de botella
		-- natural para emboscadas. Aquí no lo hay. Se acepta porque el cuello de
		-- botella era un regalo de un mapa ajeno y la duración es un problema
		-- medido; cuando el mapa se haga a medida, se recupera a propósito.
		destino = Vector3.new(-222, 19.2, 421),
		detectores = 18,
		pvp = "libre",
	},
}

-- LA CARGA DE VUELTA. Cada destino te da mercancía para llevar al almacén, y el
-- almacén te la compra.
--
-- Existe porque la vuelta era tiempo muerto puro: ~90 segundos por la ruta roja
-- yendo de vacío, sin nada que llevar, sin nadie que pudiera robarte y sin una
-- sola decisión. Eso era LA MITAD del ciclo sin juego.
--
-- La alternativa evidente --repartir varios almacenes por el mapa-- acorta ese
-- tramo pero no lo llena, y encima dispersa a los jugadores: con el mapa que hay,
-- dos personas volviendo a almacenes distintos no se cruzan jamás, y los
-- encuentros son justo lo que hace funcionar a este género. Así que se llena el
-- viaje en vez de acortarlo, y se conserva UN solo almacén al que vuelve todo el
-- mundo.
--
-- PAGA MENOS QUE LA IDA, y esa proporción es lo que mantiene la jerarquía: si el
-- retorno rindiera igual, la ruta elegida daría lo mismo y la decisión de destino
-- --que es el corazón del juego-- se quedaría sin peso. Un 60 % hace que la vuelta
-- valga la pena sin competir con el viaje de verdad.
Config.RETORNO_FRACCION = 0.6

-- Cuántas piezas te ofrece un destino al entregar. Pocas y pequeñas: la vuelta es
-- un extra, no un segundo almacén. Y pequeñas de tamaño a propósito, para que
-- quepan a pie -- si hicieran falta vehículo, el jugador nuevo volvería de vacío
-- igual y no habríamos arreglado nada.
Config.RETORNO_PIEZAS = 3

-- Almacén. Cada cuántos segundos aparece una pieza: 3 minutos en producción, 30
-- segundos mientras se mide -- esperar tres minutos por caja hace imposible probar
-- nada de lo que cuelga del almacén en una sesión. Lo elige `Config.PROTOTIPO`.
Config.ALMACEN_RITMO = if Config.PROTOTIPO then 30 else 180
Config.ALMACEN_TOPE = 10

-- LA NAVE SE MEJORA: el sumidero que no se acaba (RUMBO.md §3.C).
--
-- Estaba en el plan original desde el principio y nunca se hizo, y su ausencia es
-- la que dejaba el juego sin motivo para volver mañana: el garaje era el ÚNICO
-- destino del dinero, y medido se compra entero con siete viajes rojos. Después
-- no quedaba nada que querer.
--
-- Mejorar la nave hace justo lo que el garaje no puede hacer: **alarga tu ventana
-- de ausencia**. Con tope 10 y una caja cada 30 s, dejar de jugar cinco minutos ya
-- es desperdiciar producción; con tope 30 puedes irte a cenar. La cadencia de
-- retorno crece con el jugador en vez de agobiarle igual desde el primer día.
--
-- Y ARREGLA DE PASO EL TECHO DE LA CAPACIDAD: un almacén lleno de nivel 1 pesa
-- unos 23 huecos, así que hoy comprar algo que cargue más de 24 no sirve de nada
-- --el coche ya está en el techo y la furgoneta lo pasa-- y eso deja la mitad del
-- garaje sin sentido. Con la nave subida hay de verdad qué llevar.
--
-- El nivel 1 NO repite los números: los toma de las constantes de arriba, para que
-- no haya dos sitios diciendo a qué ritmo produce una nave sin mejorar.
Config.NAVE_MEJORAS = {
	{ ritmo = Config.ALMACEN_RITMO, tope = Config.ALMACEN_TOPE, coste = 0 },
	{ ritmo = 24, tope = 14, coste = 1200 },
	{ ritmo = 19, tope = 18, coste = 4000 },
	{ ritmo = 15, tope = 24, coste = 12000 },
	{ ritmo = 12, tope = 30, coste = 30000 },
	{ ritmo = 10, tope = 38, coste = 70000 },
	{ ritmo = 8, tope = 48, coste = 150000 },
}

-- Radio alrededor de la salida en el que se puede elegir ruta. Vive aquí, y no
-- en RouteService, porque el CLIENTE también lo necesita: el selector de ruta
-- sólo debe aparecer donde el servidor va a aceptar la elección. Con dos copias
-- del número, el día que una cambie el jugador vería una pantalla que al pulsar
-- no hace nada -- y un botón que no responde se lee como un juego roto.
Config.DISTANCIA_SALIDA = 40

-- Calor: el reloj de tensión del viaje (ver DISENO-CIUDAD.md §4). Sube por lo que
-- haces, baja por lo que consigues, y decide cuánta policía tienes encima.
Config.CALOR_MAXIMO = 3

-- Radio de un detector y, sobre todo, cuánto tarda en poder volver a dispararse
-- contra el MISMO jugador. Sin ese bloqueo, quedarse quieto encima de un poste
-- sube a 3 en dos segundos: el sistema deja de ser una decisión y pasa a ser una
-- trampa. 30 s es más que de sobra para cruzar su radio a cualquier velocidad.
Config.DETECTOR_RADIO = 35
Config.DETECTOR_BLOQUEO = 30

-- Cuánto tarda en bajar un nivel de calor sin vigilancia encima. Es la válvula de
-- escape, y no es opcional: sin ella la única estrategia sensata es no salir del
-- almacén, y entonces no hay juego.
Config.CALOR_SEGUNDOS_POR_NIVEL = 20

-- REFUGIOS: sitios del mapa donde no te pueden alcanzar.
--
-- Existen porque hasta ahora la única zona segura era el almacén -- UN punto en
-- una esquina del mapa -- y eso deja al jugador perseguido con una sola opción:
-- correr y aguantar. Correr HACIA algo es una decisión; correr a secas es un
-- castigo que sólo se puede esperar a que pase.
--
-- Y hacen por el mapa lo que faltaba desde la primera partida: que la ruta elegida
-- cambie EL CAMINO y no sólo su longitud. Con refugios repartidos aparecen
-- trayectos que los van encadenando --más largos, más seguros-- frente a atajos
-- expuestos que pagan igual pero sin red.
--
-- Radio pequeño comparado con la zona segura del almacén (150): un refugio es un
-- portal donde meterse, no un barrio entero a salvo.
Config.REFUGIO_RADIO = 45

-- Dentro se enfría MUCHO más rápido, pero NO al instante. Esa diferencia con el
-- almacén (que apaga el calor de golpe) es lo que impide que un refugio sea un
-- botón de "anular la persecución": sigue costando lo único que de verdad escasea
-- en una sesión, que es tiempo. Cinco segundos por nivel contra veinte a la
-- intemperie: merece la pena desviarse, y aun así tres estrellas son quince
-- segundos parado sin cobrar.
Config.REFUGIO_SEGUNDOS_POR_NIVEL = 5

-- Cuántos por ruta y a qué altura del trayecto. Desviados de la línea a propósito:
-- un refugio que te pilla de paso no es una decisión, es un regalo. Hay que querer
-- ir.
-- UNO POR RUTA, no dos. Con dos por ruta salían seis repartidos por una ciudad
-- de 1.500 studs y acababan siendo mobiliario: "los puntos de refugio deberían
-- ser menos y estar más espaciados" (JJ). Un refugio sólo significa algo si
-- llegar a él es una decisión, y para eso tiene que ser el único que tienes cerca.
Config.REFUGIOS_POR_RUTA = 1
Config.REFUGIO_DESVIO = 85

-- LO QUE TIENE QUE APARTARSE DE CASA, medido en studs desde el borde de la zona
-- segura. Lo destapó JJ jugando: *"hay un refugio justo a la salida del almacén,
-- no tiene sentido"*. Y no lo tenía -- el de la ruta verde caía a 230 studs del
-- almacén, o sea con su puerta a 35 studs de donde acaba la zona segura.
--
-- Un refugio ahí no es una decisión: es una versión peor del almacén. El almacén
-- apaga el calor de golpe y además es donde cobras; si el refugio está pegado a
-- él, meterse dentro nunca puede ser lo mejor que puedes hacer, y una opción que
-- nunca gana es una opción que no existe. El refugio empieza a significar algo
-- justo donde volver a casa empieza a doler.
--
-- Con 200, el refugio queda a 350 del centro del almacén y su puerta a más del
-- doble de la zona segura. El motivo de que esto se mida en STUDS y no en fracción
-- del trayecto es el mismo que ya enseñaron las guaridas: un 0,33 dice cosas muy
-- distintas en una ruta de 600 y en una de 1.700.
Config.REFUGIO_MARGEN_CASA = 85
-- Y lo que se aparta del destino, por el otro lado: un refugio a las puertas de la
-- entrega llega cuando el viaje ya está hecho.
Config.REFUGIO_MARGEN_DESTINO = 55
-- Y la distancia mínima entre dos refugios cualesquiera, aunque sean de rutas
-- distintas: sin ella, dos rutas que pasan cerca plantan los suyos casi pegados
-- y vuelven a parecer mobiliario urbano.
--
-- BAJADA DE 320 A 240 el 19/08, al comprimir las rutas, y es una consecuencia
-- aritmética y no un apaño. Un refugio tiene que caer entre REFUGIO_MARGEN_CASA
-- (200) y el destino menos REFUGIO_MARGEN_DESTINO (140): con la verde en 558 de
-- recta, eso deja un tramo útil de 218 studs. Los tres corredores que piden
-- refugio salen del MISMO almacén, así que en sus primeros cientos de studs van
-- casi pegados -- y exigir 320 entre ellos hacía imposible plantar más de dos.
-- Medido: se plantaban 2 para 3 rutas, y la que se quedaba fuera cambiaba según
-- dónde cayeran los destinos.
--
-- Una ruta con ladrones y sin sitio donde refugiarse es una promesa rota, así que
-- entre "no pegados" y "que exista", manda que exista. 240 sigue siendo más de
-- cinco veces el radio de un refugio (45): no se tocan ni se confunden.
Config.REFUGIO_SEPARACION = 100

-- Patrullas por nivel de calor, y a qué velocidad van.
--
-- SON MÁS RÁPIDAS QUE EL JUGADOR A PROPÓSITO, y eso sólo es justo por lo otro que
-- las define: van ATADAS A LAS CALLES. Tú eres más lento (de 9,9 cargado a 16 de
-- vacío) pero puedes cortar por parques, callejones y solares. Escapar es leer el
-- mapa, no ganar una carrera -- y eso es exactamente lo que convierte a la ciudad
-- en una mecánica en vez de en un decorado. Si algún día las patrullas pudieran
-- atajar, habría que bajarlas por debajo de la velocidad cargada o el sistema se
-- convierte en un impuesto: te pillan siempre y la decisión desaparece.
-- LAS GUARIDAS: de dónde salen los ladrones.
--
-- Petición de JJ jugando: "no ves en el mapa dónde están los ladrones y su zona de
-- influencia, te aparecen de repente; deberías poder mirar el mapa y planear por
-- dónde ir". Y era literal -- los ladrones se materializaban a 90-140 studs del
-- jugador, en cualquier dirección, sin venir de ningún sitio.
--
-- Un peligro que no se puede anticipar no es tensión: es un impuesto. Con guaridas
-- fijas y marcadas pasan tres cosas a la vez: se pueden rodear (que es la
-- habilidad que este juego decía pedir y no pedía), explican de dónde viene el que
-- te persigue, y le dan a cada zona un carácter que el color solo no da.
--
-- TRES POR RUTA. Empezaron siendo dos --"que el corredor pueda recorrerse
-- esquivándolas"-- y se midió lo que pasaba: con dos, en el 61 % del viaje NO
-- había ninguna guarida a distancia útil, así que el ladrón seguía saliendo de la
-- nada la mayor parte del tiempo. Es decir: el arreglo no arreglaba nada durante
-- más de la mitad del trayecto.
--
-- Barrido de parámetros sobre las tres rutas (cobertura media / peor ruta):
--   2 guaridas, alcance 260 -> 65 % / 31 %
--   2 guaridas, alcance 380 -> 84 % / 61 %
--   3 guaridas, alcance 380 -> 93 % / 79 %
--   4 guaridas, alcance 300 -> 93 % / 80 %  (lo mismo, con más estorbo)
--
-- Tres es donde la curva se aplana. Siguen apartadas del camino, así que rodearlas
-- sigue siendo posible: lo que cambia es que ahora casi siempre hay una de la que
-- venir, que era el punto.
Config.GUARIDAS_POR_RUTA = 3

-- Cuánto se apartan del camino recto. Menos que los refugios (100): una guarida
-- pegada al corredor es un obstáculo que hay que rodear, y ése es su trabajo.
Config.GUARIDA_DESVIO = 45

-- A qué distancia del jugador una guarida sirve para soltar a un ladrón. Por
-- debajo de APARICION_MIN sería una emboscada; por encima de esto el ladrón
-- llegaría tan tarde que daría igual, así que se cae al método viejo (un punto
-- cualquiera alrededor) antes que quedarse sin amenaza.
--
-- 380 y no 260, y el motivo es el mismo que el de arriba: con 260 la mayor parte
-- del viaje se quedaba sin guarida útil. Un ladrón que sale a 380 studs tarda unos
-- veinte segundos en plantarse encima -- va más rápido que tú cargado, así que
-- llega igual, y llega desde un sitio que estaba en el mapa.
Config.GUARIDA_ALCANCE = 250

Config.PATRULLAS = {
	[0] = { cantidad = 0, velocidad = 0 },
	[1] = { cantidad = 1, velocidad = 18 },
	[2] = { cantidad = 2, velocidad = 20 },
	[3] = { cantidad = 3, velocidad = 22 },
} :: { [number]: { cantidad: number, velocidad: number } }

-- CUÁNTOS LADRONES MÁS SALEN SI LLEVAS ALGO CARO (sellada o legendaria).
--
-- Es `RUMBO.md` §3.B, y su gracia está en de dónde NO viene: no salen más porque
-- hayas subido de nivel. Escalar la amenaza con el nivel enseña al jugador que
-- progresar le empeora la vida, que es justo lo contrario de lo que tiene que
-- aprender. Escalarla con **lo que ha decidido cargar** es una consecuencia suya,
-- y es la tensión que el diseño buscaba desde el principio: una legendaria por la
-- roja vale 13.500, y tu haz de luz se ve desde el otro extremo del mapa.
--
-- Uno, no dos: con calor 3 ya hay tres encima, y cuatro es el techo de lo que se
-- puede esquivar antes de que dejar de ser tensión y pase a ser atropello. Y sólo
-- suma si el calor ya había sacado a alguien -- ver Heat.patrullas.
Config.PATRULLAS_EXTRA_CARGA_CARA = 1

-- A cuánto te alcanza una patrulla, y qué te cuesta. NO MATA: morir es que te
-- echen de la sesión, y perder mercancía es que te salga mal un viaje y quieras
-- otro. La mitad, y no todo, para que un mal viaje siga valiendo la pena terminarlo.
Config.PATRULLA_ALCANCE = 6
Config.PATRULLA_FRACCION = 0.5

-- Intercepción
Config.ROBO_DISTANCIA = 5 -- studs
Config.ALERTA_DISTANCIA = 60 -- a esta distancia ya se avisa: "te vienen detrás"
Config.ROBO_FRACCION = 0.30
Config.MARCADO_SEGUNDOS = 60
Config.INTERCEPT_HZ = 5

-- Zona segura alrededor del origen (el almacén se construye ahí, ver WorldBuilder):
-- dentro de este radio no se roba a nadie, ni siquiera en la roja. Sin esto, un
-- ladrón parado en la salida roba a todo el que elige ruta en el instante mismo de
-- elegirla, antes de dar un paso -- no viola "el almacén no es asaltable" a la
-- letra (su contenido sigue intocable), pero rompe el espíritu: la zona de partida
-- tiene que ser segura.
-- ⚠ ESTA CONSTANTE Y LAS DE ABAJO (márgenes y desvíos de refugios, guaridas y
-- racimos) SE REESCALARON JUNTAS el 19/08 al encoger el mundo, y tienen que seguir
-- moviéndose juntas: todas dicen "cuánto es lejos" y todas se calibraron para unas
-- rutas que medían el doble. Una sola sin reescalar no da un error -- da un juego
-- donde media ruta cabe dentro de la zona segura, o donde ningún refugio encuentra
-- sitio, y nada avisa.
--
-- Bajada de 150 a 90 al encoger el mundo, y es aritmética: la zona segura es el
-- trozo del mapa donde no pasa nada, y con las rutas a la mitad de distancia un
-- radio de 150 se comía el principio de todos los viajes -- ni contactos, ni
-- detectores, ni guaridas pueden plantarse dentro. 90 sigue cubriendo el recinto
-- entero y su carretera de acceso, que es lo que tiene que proteger.
Config.ZONA_SEGURA_RADIO = 90

-- EL RECINTO DEL ALMACÉN: la valla que no te deja salir a la ciudad con carga y
-- sin destino elegido (ver Perimeter.luau, que tiene el porqué entero).
--
-- El recinto YA NO ES UN RADIO: es el polígono entero, que es rectangular (ver
-- Perimeter.dentro). Lo único que queda aquí es cuántos paneles cierran su boca.
--
-- Ocho para 320 studs de ancho: cuarenta studs por panel, que es una pieza
-- manejable y con solape suficiente para que no queden rendijas.
Config.RECINTO_PANELES = 8
-- Alto: por encima del salto de Roblox con vehículo y con margen. Una puerta que
-- se salta es una puerta que enseña a saltársela.
Config.RECINTO_ALTO = 26

-- Sonidos. Los efectos NO son decoración: son información. Que suene una alerta al
-- acercarse un perseguidor es la diferencia entre persecución y emboscada injusta.
-- Los ids se rellenan en la Tarea 11 buscándolos en la biblioteca de Roblox.
-- Un id vacío no reproduce nada y no rompe: el juego funciona igual, sólo más mudo.
-- El tipo explícito no es adorno: sin él, indexar con una clave variable
-- (Config.SONIDOS[clave]) es un error de tipo en --!strict.
-- EL RUIDO DE CADA VEHÍCULO. "Aunque vayas en vehículo suenan los pasos del
-- personaje" (JJ): callarlos era la mitad del arreglo, y ésta es la otra.
--
-- SON DE LA BIBLIOTECA DE ROBLOX, no generados. Se valoró generarlos con MiniMax
-- y no compensa: un audio propio hay que subirlo a la cuenta y pasar moderación,
-- mientras que estos son de ProSoundEffects --la misma casa que la sirena que ya
-- usamos-- y se comprobó que los cuatro cargan y suenan (27 s, 34,9 s, 10,4 s y
-- 9,7 s de duración medida).
--
-- TRES SAMPLES PARA NUEVE VEHÍCULOS, no nueve: lo que distingue una furgoneta de
-- una moto es sobre todo el TONO, así que el mismo motor a 0,72 y a 1,15 da dos
-- vehículos distintos sin descargar nada más. Menos assets, menos que puede
-- fallar, y arranca antes.
--
-- El `tono` es también la escala del juego hecha sonido: cuanto más grave, más
-- grande. Se oye quién viene antes de verlo, que en un juego de robar es
-- información y no adorno.
Config.SONIDO_MOTOR = "rbxassetid://9112787430" -- "Go Kart Engine Constant 1" (ProSoundEffects)
Config.SONIDO_RUEDAS = "rbxassetid://9125955680" -- "Skateboard Constant Rolling" (ProSoundEffects)
Config.SONIDO_PEDALES = "rbxassetid://7453582428" -- "Bicycle Pedalling"

-- `motor` separa dos cosas que suenan MUY distinto: un motor tiene ralentí --se
-- oye parado-- y una rueda no hace absolutamente ningún ruido si no te mueves.
--
-- La primera versión trataba una tabla como a una moto: rodadura constante,
-- también quieto, y a tono agudo. El resultado, en palabras de JJ: "el sonido de
-- los patines es insoportable". Lo era: un siseo agudo que no paraba nunca y que
-- además no correspondía a nada de lo que estabas haciendo.
--
-- Ahora lo que no tiene motor CALLA al pararse y suena discreto al rodar, con el
-- tono bajado: la rodadura es un detalle de fondo, no un instrumento.
Config.SONIDOS_VEHICULO = {
	monopatin = { sonido = Config.SONIDO_RUEDAS, tono = 0.8, volumen = 0.13, motor = false },
	patinete = { sonido = Config.SONIDO_RUEDAS, tono = 0.75, volumen = 0.14, motor = false },
	patinete_electrico = { sonido = Config.SONIDO_MOTOR, tono = 1.2, volumen = 0.22, motor = true },
	bicicleta = { sonido = Config.SONIDO_PEDALES, tono = 0.95, volumen = 0.18, motor = false },
	moto = { sonido = Config.SONIDO_MOTOR, tono = 1.1, volumen = 0.4, motor = true },
	coche = { sonido = Config.SONIDO_MOTOR, tono = 0.85, volumen = 0.38, motor = true },
	furgoneta = { sonido = Config.SONIDO_MOTOR, tono = 0.72, volumen = 0.42, motor = true },
} :: { [string]: { sonido: string, tono: number, volumen: number, motor: boolean } }

Config.SONIDOS = {
	cobro = "rbxassetid://1319346243", -- "Money,Coins,Drop In Cash Register" (codes4breakfast)
	robo = "rbxassetid://98330897555423", -- "punch2" (GRISAlLLE)
	alerta = "rbxassetid://9119159511", -- "Siren Blat 2 (SFX)" (ProSoundEffects)
} :: { [string]: string }

-- Anticheat: nadie corre más que esto ni en el mejor de los casos.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40

-- ─────────────────────────────────────────────────────────────────────────────
-- LOS CONTACTOS: la moneda de las habilidades, que se recoge por el camino.
--
-- POR QUÉ EXISTEN. Toda la experiencia del juego se otorgaba en UNA línea
-- (CargoService, al entregar): durante los 54-100 segundos de viaje el jugador no
-- ganaba nada y sólo podía perder. El viaje era un impuesto entre dos momentos
-- buenos. Los contactos ponen algo bueno DENTRO del viaje.
--
-- No ocupan hueco del zurrón y NO SE PUEDEN ROBAR, a propósito: la economía de
-- monedas y el eje de riesgo ya están equilibrados, y una moneda paralela que no
-- los toca no puede desequilibrarlos.
-- Studs de recogida, por proximidad: no hay que pulsar. Subido de 10 a 14 el
-- 19/08 al entrar el rastro, y no por generosidad: con una fila continua, recoger
-- tiene que ser FLUIDO. Diez studs obligaban a pisar cada píldora casi en el
-- centro, y una fila que se rompe porque has pasado a un metro no enseña "sigue
-- el camino", enseña "vete pegado a la línea". Catorce perdona el bordillo.
Config.CONTACTO_RADIO = 14
Config.CONTACTO_VALOR_SUELTO = 1
Config.CONTACTO_VALOR_RACIMO = 5
-- El rastro no paga: su trabajo es el CAMINO y la VELOCIDAD, no la moneda. Si
-- pagara, la economía de habilidades se multiplicaría por cinco de un día para
-- otro sin que nadie lo hubiera decidido.
Config.CONTACTO_VALOR_RASTRO = 0

-- ─────────────────────────────────────────────────────────────────────────────
-- EL RASTRO: la fila de píldoras que DIBUJA la ruta y te acelera al seguirla.
--
-- POR QUÉ, dicho por JJ tras jugarlo: "es muy largo, nada atractivo; para que
-- enganche a seguir la ruta deberíamos poner la ruta indicada con píldoras que se
-- van recogiendo y aumentan la velocidad, más seguidos".
--
-- Los contactos ya hacían la mitad de esto, pero eran SEIS en la ruta verde: uno
-- cada 128 studs, o sea uno cada ocho segundos. Eso no es un rastro, es una
-- rifa -- ni marca por dónde ir ni se siente como un premio continuo.
--
-- Con el paso a 22 studs la verde pasa de 6 piezas a ~17, y a 16 studs/s eso es
-- **algo bueno cada 1,4 segundos**. Es el patrón de los juegos que enganchan en
-- esta plataforma: la recompensa no está al final del trayecto, ES el trayecto.
--
-- Y de paso resuelve un problema que no era de premio sino de orientación: la
-- brújula te dice hacia dónde, pero no por dónde. La fila de luces sí.
Config.RASTRO_PASO = 22

-- Dónde empieza y acaba la fila. Empieza justo al salir de la zona segura -- el
-- rastro tiene que estar esperándote cuando pisas la calle, no doscientos studs
-- después -- y llega casi hasta el destino, al revés que los sueltos, que se
-- paraban a 60: quien sigue el rastro tiene que acabar EN la entrega.
Config.RASTRO_DESDE = 20
Config.RASTRO_HASTA = 25

-- Se apagan al pisarlas y vuelven. Corta, y bajada de 45 a 15 el 19/08 por una
-- consecuencia directa de acortar las rutas: con la verde en 26 s de ida, una
-- recarga de 45 dejaba TODO el viaje de vuelta a oscuras y sin racha. La vuelta
-- ya era la mitad floja del ciclo; no podía además quedarse sin el gancho.
Config.CONTACTO_RECARGA = 15

-- Cuántos por ruta. Ahora `sueltos` NO es cuántas piezas hay, sino cuántas de las
-- del rastro son DORADAS (las que además pagan contacto). El total de piezas lo
-- decide el largo del camino y RASTRO_PASO.
--
-- El número se ha dejado igual que antes a propósito: el rastro cambia lo que se
-- SIENTE, no lo que se gana. Las habilidades siguen costando lo que costaban y
-- tardando lo que tardaban, así que este cambio no puede desequilibrar la
-- progresión -- que es justo lo que hay que poder afirmar cuando se toca el
-- sistema por el que pasa el jugador cada segundo del viaje.
Config.CONTACTOS_POR_RUTA = {
	-- El barrio lleva tres doradas y ningún racimo: es el viaje donde se aprende
	-- que hay cosas que recoger, no donde se decide si merece la pena desviarse.
	barrio = { sueltos = 3, racimos = 0 },
	verde = { sueltos = 6, racimos = 1 },
	ambar = { sueltos = 10, racimos = 2 },
	roja = { sueltos = 16, racimos = 3 },
} :: { [string]: { sueltos: number, racimos: number } }

-- Los racimos van apartados, pegados a un peligro, y son la decisión: el premio
-- está donde está el riesgo. El desvío es menor que el de una guarida (70) para
-- que ir a por uno sea un rodeo y no una expedición.
Config.CONTACTO_RACIMO_DESVIO = 38

-- LA RACHA: cada pieza recogida te acelera, y la velocidad es DEL VIAJE, no
-- tuya. La velocidad permanente está descartada desde el principio (ver la
-- cabecera de Levels.luau): chocaría con la regla de que nadie puede volverse
-- inalcanzable, y sin alcance no hay PvP.
--
-- Así se puede acelerar de verdad sin romperla: se pierde entera al entregar y al
-- ser alcanzado, y los ladrones escalan con la velocidad ACTUAL del perseguido,
-- racha incluida.
--
-- Reajustada el 19/08 al entrar el rastro: cada pieza vale MENOS (0,4 en vez de
-- 0,5) porque hay muchas más, y el techo sube de 4 a 6 porque ahora se puede
-- sostener. A pie son 16 → 22 studs/s, un 37 % más rápido, que es lo que hace que
-- seguir el rastro se note en el reloj y no sólo en el contador.
Config.RACHA_POR_CONTACTO = 0.4
Config.RACHA_MAXIMA = 6 -- el coche (34) queda recortado en 38, con el antitrampas en 40

-- LA CADENA: la racha se cae sola si dejas de recoger.
--
-- Es lo que convierte el rastro en un juego en vez de en un pasillo decorado. Sin
-- esto, recoger seis píldoras al principio y luego ir en línea recta rinde igual
-- que seguir la fila entera -- y entonces el rastro no pide nada, así que no
-- engancha. Con esto, el viaje tiene una pregunta constante ("¿me desvío a por
-- la siguiente o corto por aquí?") que antes sólo aparecía en los racimos.
--
-- Los cuatro segundos de gracia salen del paso del rastro: a 22 studs y 16
-- studs/s se pisa una cada 1,4 s, así que quien va por la fila no la pierde nunca
-- y quien la abandona lo nota enseguida. Y decae UNA pieza por segundo, no de
-- golpe: perderlo todo por un semáforo es castigo, perderlo poco a poco es aviso.
Config.RACHA_GRACIA = 4
Config.RACHA_DECAE = 1

-- LAS HABILIDADES. Todas se montan sobre un número que ya se calculaba: ninguna
-- crea un sistema nuevo y NINGUNA DA VELOCIDAD.
--
-- El suelo de robo es la regla de oro escrita en un número: `expone` es un
-- multiplicador, así que apilar factores sin suelo acabaría llevando a cero la
-- fracción robada -- inmunidad por la puerta de atrás, que es exactamente lo que
-- el diseño prohíbe.
Config.ROBO_FRACCION_MINIMA = 0.10

Config.SENUELO_DURACION = 6 -- segundos que los ladrones van al señuelo y no a ti
Config.SENUELO_RECARGA = 45
Config.SENUELO_RADIO = 120 -- a quién despista

-- ─────────────────────────────────────────────────────────────────────────────
-- LOS HITOS: qué toca hacer ahora, y qué se gana al hacerlo.
--
-- POR QUÉ EXISTEN. Medido: la primera recompensa del juego llegaba a los ~100 s,
-- y en el juego que lo inspiró llega a los 3. Además, un jugador nuevo no tenía
-- forma de saber qué se esperaba de él ni cuánto faltaba para lo siguiente: la
-- licencia por nivel existía desde el 18/08 pero sólo se descubría chocando.
--
-- SE CUENTAN ENTREGAS, NO NIVEL, en los peldaños de abajo: el nivel sube con el
-- dinero cobrado, así que su ritmo depende de qué llevabas encima y no de cuánto
-- has jugado. Uno con suerte en el sorteo de rarezas saltaría dos peldaños en su
-- primer viaje y otro se quedaría atascado haciendo exactamente lo mismo.
--
-- `abre` es una LLAVE: la ruta verde no existe hasta el primer hito. Por eso el
-- servidor lo comprueba y no se fía del selector.
-- LA RUTA DEL PRIMER REPARTO, la que se pone sola.
--
-- Al jugador que acaba de entrar no se le pide que decida: coge lo que hay en la
-- nave, sale, y el destino ya está puesto. Decidir viene DESPUÉS de haber cobrado
-- una vez, cuando "×0,4 contra ×1" significa algo porque ya sabes lo que es un
-- viaje.
--
-- Es la primera de las ideas de `V1.md` §4 ("los primeros treinta segundos no
-- tienen gancho"), y el motivo es medible: hoy el que entra se encuentra una valla
-- que le frena con un "elige destino" antes de haber ganado nada. Una pantalla de
-- decisión antes de la primera recompensa es fricción pura -- no puede elegir bien
-- porque todavía no sabe qué está eligiendo.
--
-- Tiene que ser una ruta SIN LICENCIA ni hito, o el regalo sería una puerta
-- cerrada. Una prueba lo comprueba contra Goals en vez de fiarlo a este comentario.
Config.RUTA_PRIMERA = "barrio"

Config.HITOS = {
	{ id = "primera", entregas = 1, monedas = 50, abre = "verde" },
	{ id = "tres", entregas = 3, monedas = 250 },
	{ id = "ambar", nivel = 3 },
	{ id = "ocho", entregas = 8, monedas = 1000 },
	{ id = "roja", nivel = 8, exigeMotor = true },
}

return Config
