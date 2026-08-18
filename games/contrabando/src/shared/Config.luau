--!strict
--[[
	Config.luau — todas las constantes del juego en un único sitio. Sin lógica.

	Las marcadas con PROTOTIPO: difieren a propósito de DISENO.md para
	poder medir en una sesión lo que en producción tardaría horas. Revertirlas antes
	de publicar.
]]

local Config = {}

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
Config.TAMANOS = {
	{ id = "pequeno", nombre = "pequeño", nivel = 1, huecos = 1 },
	{ id = "mediano", nombre = "mediano", nivel = 2, huecos = 2 },
	{ id = "grande", nombre = "grande", nivel = 3, huecos = 4 },
	{ id = "enorme", nombre = "enorme", nivel = 4, huecos = 8 },
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
Config.VEHICULOS = {
	{
		id = "a_pie",
		nombre = "A pie",
		capacidad = Config.CAPACIDAD_A_PIE,
		velocidadBase = Config.VELOCIDAD_BASE,
		penalizacionPorPeso = Config.PENALIZACION_POR_CAJA,
		tamanoMaximo = 1,
		coste = 0,
	},
	{
		id = "patines",
		nombre = "Patines",
		capacidad = 4,
		velocidadBase = 18,
		penalizacionPorPeso = 1.2,
		tamanoMaximo = 1,
		coste = 150,
	},
	{
		id = "monopatin",
		nombre = "Monopatín",
		capacidad = 5,
		velocidadBase = 19,
		penalizacionPorPeso = 1.0,
		tamanoMaximo = 2,
		coste = 350,
	},
	{
		id = "patinete",
		nombre = "Patinete",
		capacidad = 6,
		velocidadBase = 20,
		penalizacionPorPeso = 0.9,
		tamanoMaximo = 2,
		coste = 700,
	},
	{
		id = "patinete_electrico",
		nombre = "Patinete eléctrico",
		capacidad = 7,
		velocidadBase = 24,
		penalizacionPorPeso = 0.8,
		tamanoMaximo = 2,
		soloCalzada = true,
		coste = 1400,
	},
	{
		id = "bicicleta",
		nombre = "Bicicleta",
		capacidad = 9,
		velocidadBase = 26,
		penalizacionPorPeso = 0.7,
		tamanoMaximo = 3,
		soloCalzada = true,
		coste = 2500,
	},
	{
		id = "moto",
		nombre = "Moto",
		capacidad = 12,
		velocidadBase = 32,
		penalizacionPorPeso = 0.55,
		tamanoMaximo = 3,
		soloCalzada = true,
		coste = 4500,
	},
	{
		id = "coche",
		nombre = "Coche",
		capacidad = 18,
		velocidadBase = 34,
		penalizacionPorPeso = 0.4,
		tamanoMaximo = 4,
		soloCalzada = true,
		coste = 8000,
	},
	{
		id = "furgoneta",
		nombre = "Furgoneta",
		capacidad = 26,
		velocidadBase = 30,
		penalizacionPorPeso = 0.28,
		tamanoMaximo = 4,
		soloCalzada = true,
		coste = 15000,
	},
}

Config.VEHICULO_INICIAL = "a_pie"

-- Rarezas: multiplicador de valor, peso que ocupa y probabilidad.
-- El peso de la legendaria es exactamente CAPACIDAD_A_PIE: cabe, pero te ocupa todo.
Config.RAREZAS = {
	{ id = "comun", multiplicador = 1, peso = 1, probabilidad = 0.70 }, -- PROTOTIPO: 0.90
	{ id = "marcada", multiplicador = 10, peso = 1, probabilidad = 0.20 }, -- PROTOTIPO: 0.08
	{ id = "sellada", multiplicador = 50, peso = 2, probabilidad = 0.08 }, -- PROTOTIPO: 0.018
	{ id = "legendaria", multiplicador = 135, peso = 3, probabilidad = 0.02 }, -- PROTOTIPO: 0.002
}

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
-- NO HAYA NADA de la ciudad por encima del suelo en 70 studs a la redonda, que
-- haya una calle cerca y, sobre todo, QUE EL SUELO SEA LLANO.
--
-- Lo tercero se aprendió caro. La primera elección puntuaba espacio libre y
-- lejanía del centro, y salió una parcela con NUEVE STUDS de desnivel a lo largo
-- de sus 90: la losa se apoyaba en el lado alto y por el bajo quedaba colgando en
-- el aire sobre una calle, con un escalón infranqueable. En la foto de JJ jugando
-- se ve el almacén flotando y a él en la carretera de debajo -- "el almacén no
-- está bien posicionado en el mapa".
--
-- La parcela de ahora se eligió barriendo el cuadrante entero y midiendo el
-- desnivel de la huella (92x92) además de todo lo anterior: 0,20 studs de
-- diferencia entre su punto más alto y el más bajo, nada encima, y una calle a 40
-- studs por el norte. La del taller y la de la salida se comprobaron igual (0,01
-- y 0,20).
Config.ALMACEN_POS = Vector3.new(-600, 19.2, 640)
Config.TALLER_POS = Vector3.new(-600, 19.2, 530)

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
Config.RUTAS = {
	{
		id = "verde",
		multiplicador = 1,
		destino = Vector3.new(-180, 19, 540),
		detectores = 3,
		pvp = "ninguno",
	},
	{
		id = "ambar",
		multiplicador = 3,
		destino = Vector3.new(240, 14.8, 420),
		detectores = 9,
		pvp = "transportistas",
	},
	{
		id = "roja",
		multiplicador = 10,
		destino = Vector3.new(600, 19.2, -180),
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

-- Almacén
Config.ALMACEN_RITMO = 30 -- PROTOTIPO: 180 (1 caja cada 3 min)
Config.ALMACEN_TOPE = 10

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
Config.REFUGIOS_POR_RUTA = 2
Config.REFUGIO_DESVIO = 120

-- Patrullas por nivel de calor, y a qué velocidad van.
--
-- SON MÁS RÁPIDAS QUE EL JUGADOR A PROPÓSITO, y eso sólo es justo por lo otro que
-- las define: van ATADAS A LAS CALLES. Tú eres más lento (de 9,9 cargado a 16 de
-- vacío) pero puedes cortar por parques, callejones y solares. Escapar es leer el
-- mapa, no ganar una carrera -- y eso es exactamente lo que convierte a la ciudad
-- en una mecánica en vez de en un decorado. Si algún día las patrullas pudieran
-- atajar, habría que bajarlas por debajo de la velocidad cargada o el sistema se
-- convierte en un impuesto: te pillan siempre y la decisión desaparece.
Config.PATRULLAS = {
	[0] = { cantidad = 0, velocidad = 0 },
	[1] = { cantidad = 1, velocidad = 18 },
	[2] = { cantidad = 2, velocidad = 20 },
	[3] = { cantidad = 3, velocidad = 22 },
} :: { [number]: { cantidad: number, velocidad: number } }

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
Config.ZONA_SEGURA_RADIO = 150

-- EL RECINTO DEL ALMACÉN: la valla que no te deja salir a la ciudad con carga y
-- sin destino elegido (ver Perimeter.luau, que tiene el porqué entero).
--
-- 130 studs no es un número redondo: es el mínimo que deja DENTRO las dos cosas
-- que hay que poder hacer con la carga puesta -- la salida, donde se elige ruta
-- (a 60 del almacén), y el taller, donde se compra vehículo (a 110). Con menos,
-- la valla te separaría de la tienda justo cuando acabas de cargar; con más, se
-- comería la zona segura y la valla aparecería en mitad de la ciudad.
Config.RECINTO_RADIO = 130
-- Paneles del anillo. Con menos de 20 la cuerda se separa tanto del arco que los
-- paneles cortan por dentro del radio; con muchos más son piezas de sobra en un
-- juego que tiene que ir en un móvil de gama baja.
Config.RECINTO_PANELES = 24
-- Alto: por encima del salto de Roblox con vehículo y con margen. Una valla que
-- se salta es una valla que enseña a saltársela.
Config.RECINTO_ALTO = 26

-- Sonidos. Los efectos NO son decoración: son información. Que suene una alerta al
-- acercarse un perseguidor es la diferencia entre persecución y emboscada injusta.
-- Los ids se rellenan en la Tarea 11 buscándolos en la biblioteca de Roblox.
-- Un id vacío no reproduce nada y no rompe: el juego funciona igual, sólo más mudo.
-- El tipo explícito no es adorno: sin él, indexar con una clave variable
-- (Config.SONIDOS[clave]) es un error de tipo en --!strict.
Config.SONIDOS = {
	cobro = "rbxassetid://1319346243", -- "Money,Coins,Drop In Cash Register" (codes4breakfast)
	robo = "rbxassetid://98330897555423", -- "punch2" (GRISAlLLE)
	alerta = "rbxassetid://9119159511", -- "Siren Blat 2 (SFX)" (ProSoundEffects)
} :: { [string]: string }

-- Anticheat: nadie corre más que esto ni en el mejor de los casos.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 40

return Config
