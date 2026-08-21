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

-- El plano de la ciudad. Los destinos de las rutas SE DERIVAN de él y ya no se
-- escriben a mano: cada vez que se escribieron a mano acabaron donde había suelo
-- llano en un mapa ajeno --uno debajo de un árbol, otro sobre un zócalo-- en vez de
-- donde el juego los quería.
local Grid = require(script.Parent.Grid)

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

-- ─────────────────────────────────────────────────────────────────────────────
-- EL MAPA DESNUDO: solo edificios, calles y lo que decide algo.
--
-- Lo pidio JJ el 20/08 --*"quitemos del mapa todas las estructuras menos edificios
-- y carreteras, ahora para probar"*-- y el inventario le da la razon: la ciudad
-- entera son 67 piezas y el mundo encima son 1.042. De esas, 675 son el sistema de
-- vigilancia (450 conos y 225 de camara) y unas 135 son talleres de zona y
-- refugios repartidos por la ciudad.
--
-- Lo que se apaga son los EDIFICIOS DE SERVICIO sembrados por el mapa -- los
-- talleres de zona y los refugios. Son estructuras que se plantan buscando hueco,
-- compiten a la vista con lo que si hay que mirar, y ninguno es el bucle: el
-- taller de casa sigue estando y el calor se sigue enfriando, solo que mas
-- despacio y sin un sitio al que correr.
--
-- NO se apagan las camaras ni los recogibles ni las viviendas de entrega, aunque
-- sean piezas: no son decorado, son las reglas dibujadas.
--
-- Va detras de un interruptor y no borrado, y esa es toda la gracia: volver cuesta
-- cambiar `true` por `false`. Un mapa que se poda a mano no se puede comparar con
-- el de antes, y comparar es justamente para lo que se poda.
Config.MAPA_DESNUDO = true

-- Economía
Config.CAJA_VALOR_BASE = 10

-- LO QUE DA DE EXPERIENCIA UN VIAJE, antes de multiplicarlo por la ruta. Con 25, la
-- verde da 25, la ambar 75 y la roja 250, que son sus multiplicadores exactos: la
-- decision del juego --a que zona me meto-- es la que gobierna el nivel.
--
-- El numero sale de la curva: el nivel 2 pide 100 y con 25 cae en cuatro viajes
-- verdes, que es lo que este proyecto quiere --que el jugador nuevo vea el sistema
-- funcionar en su primera sesion-- sin que caiga en el primero, que no ensena nada.
Config.XP_POR_VIAJE = 25
Config.DINERO_INICIAL = 0

-- Carga a pie
Config.CAPACIDAD_A_PIE = 3

-- LA VELOCIDAD A PIE, subida de 16 a 20 el 20/08.
--
-- Dieciseis es el valor por defecto de Roblox, y ese es exactamente el problema:
-- lo dijo JJ comparando con otro juego de la plataforma --*"el movimiento tiene
-- que ser mas rapido y mas agil"*-- y tenia razon en algo que se mide. Este juego
-- es DESPLAZARSE: entre la eleccion de ruta y la entrega no hay otra cosa. Un
-- juego cuyo verbo principal va a la velocidad que trae la caja de serie se
-- siente como una demo, por buenas que sean las decisiones que ofrece.
--
-- Sube TODA la escalera con ella (+4 studs/s a cada vehiculo), y eso no es
-- cosmetico: si solo subiera el peaton, el monopatin --primer peldano, 19-- seria
-- mas lento que andar y la primera compra del juego, un castigo.
--
-- Y no rompe nada de lo que la sujetaba: las patrullas van a `max(velocidad del
-- nivel de calor, velocidad del perseguido + 3)`, asi que se ajustan solas. La
-- regla de oro sigue intacta -- nadie es inalcanzable, porque quien te persigue
-- corre siempre mas que tu.
Config.VELOCIDAD_BASE = 20
Config.PENALIZACION_POR_CAJA = 1.4 -- studs/s menos por unidad de peso transportada

-- LO ALTO QUE SALTA, que es la otra mitad de "mas agil".
--
-- Roblox trae 7,2 studs. Con 10 se sube a una acera o a una losa sin frenar y se
-- salta un seto de camino, que es lo que separa "recorrer" de "moverse". No es
-- una ventaja de escape: los ladrones no van a pie por donde tu vas, van por las
-- calles, y saltar no acorta ninguna ruta -- solo quita los tropiezos.
Config.SALTO_ALTURA = 10

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
		velocidadBase = 23,
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
		velocidadBase = 24,
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
		velocidadBase = 28,
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
		velocidadBase = 30,
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
		velocidadBase = 36,
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
		velocidadBase = 38,
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
		velocidadBase = 34,
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
-- ENCOGIDO A LA MITAD el 20/08. Lo pidio JJ --*"deberiamos reducir la parte donde
-- esta el taller y el almacen, hay mucho terreno que no sirve para nada"*-- y
-- medirlo le dio la razon de sobra: contando las piezas por franjas de 25 studs
-- desde la boca, **de Z 880 a 1005 no habia NI UNA**. La mitad trasera del recinto
-- era cesped. A lo ancho, lo construido iba de X -713 a -486: 226 studs de los 360.
--
--   antes  360 x 250 = 90.000 studs cuadrados
--   ahora  300 x 150 = 45.000, con lo util cabiendo entero y con margen
--
-- Y no es una cuestion de estetica: el recinto es donde EMPIEZA Y TERMINA cada
-- viaje, asi que cada stud de cesped vacio es tiempo andando sin decidir nada. La
-- caja negra del 20/08 lo enseño en crudo -- del ciclo medido, la parte de dentro
-- de casa se lleva mas que el viaje.
--
-- EL CENTRO EN X NO SE MUEVE, y eso es innegociable: la calle X=-620 de la
-- reticula pasa por la boca del recinto (ver la cabecera de Grid), asi que al salir
-- ya estas EN una calle. Mover el centro para "centrar el contenido" alinearia la
-- puerta con una manzana. Lo que se mueve es el fondo, que es donde sobra.
--
-- Y SE ENCOGE OTRA VEZ (21/08): *"la zona de la guarida o el almacen, taller etc
-- deberia ser mas pequena no? Veo que sobra mapa ahi y quita protagonismo"* (JJ).
--
-- Tenia razon y la cuenta lo dice sin discusion: el recinto media 300 x 150 y lo que
-- hay dentro --el almacen (90x90) y el taller (96x60)-- ocupa 181 x 90. Sobraban 119
-- studs a lo ancho y 60 a lo largo, o sea casi la mitad de la superficie, en patio
-- vacio. Y el patio vacio no es neutro: es lo primero que se ve al empezar la
-- partida, esta pegado a la unica pantalla donde el jugador decide algo, y cuanto
-- mas grande es mas parece que el juego pasa AHI en vez de en la ciudad.
--
-- 210 x 120 deja doce studs de margen alrededor de lo que hay. La superficie baja de
-- 45.000 a 25.200 studs cuadrados: casi la mitad.
--
-- EL CENTRO EN Z SE MUEVE A 815 y no es cosmetico: la salida se DERIVA del borde
-- norte (centro.Z - largo/2), y ese borde tiene que quedarse en 755 porque ahi es
-- donde engancha con la calle 1 de la reticula. Encoger dejando el centro en 830
-- habria metido la boca 20 studs dentro de la ciudad.
Config.POLIGONO_CENTRO = Vector3.new(-620, 19.2, 815)
Config.POLIGONO_TAMANO = Vector2.new(210, 120)
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
-- DONDE EL RECINTO SE ENGANCHA A LA CIUDAD. Era un punto medido a mano sobre el
-- mapa ajeno --la calle más cercana que hubiera-- y por eso quedaba en diagonal, a
-- 27 studs al este y 76 al sur de la boca, con una carretera improvisada uniendo
-- las dos cosas. Esa carretera es la que un día murió volando 3,4 studs sobre el
-- césped y dejó las cuatro rutas sin camino a la vez.
--
-- Con retícula propia el enganche es el cruce que hay justo debajo de la boca: la
-- calle 1 pasa por ella. Ya no hay nada que unir, y el punto se DERIVA en vez de
-- medirse.
Config.POLIGONO_ENGANCHE = Grid.cruce(1, Grid.FILAS)

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
		id = "verde",
		multiplicador = 1,
		nivel = 1,
		-- SIN GUARIDA NI REFUGIO PROPIOS, y no es un olvido: es que no caben.
		--
		-- La verde mide 293 studs de camino y comparte su primera mitad con el barrio,
		-- así que su tramo útil lo parten tres cosas -- la zona segura de casa, el
		-- cruce del tutorial y su propio destino-- y lo que queda son dos trozos de
		-- veinte studs. Se intentó repartir con más resolución y con márgenes menores,
		-- y lo único que se conseguía era plantar el refugio encima de la losa del
		-- barrio: el sitio al que corres siendo el sitio donde cobras.
		--
		-- Que sea así encaja con lo que la verde ES: la segunda rampa, ×1, sin robo
		-- entre jugadores. Los ladrones siguen apareciendo --el respaldo los saca por
		-- delante, sobre el camino-- y el calor se apaga entregando, que ahora te
		-- devuelve a casa al instante. El peligro con sitios fijos que aprender
		-- empieza en la ámbar, que es donde el mapa tiene sitio para ponerlos.
		guaridas = 0,
		refugios = 0,
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
		-- MUDADA AL CRUCE RECTO EL 20/08, heredando el sitio de la ruta de aprendizaje
		-- que habia aqui. Lo pidio JJ mirando el selector: *"no entiendo lo de LOCAL
		-- del inicio, a green amber o red me parecia suficiente"*. Y tenia razon en el
		-- fondo, no solo en el nombre: el mapa promete TRES bandas --verde, ambar,
		-- roja-- y el selector ofrecia cuatro etiquetas, una de las cuales no era un
		-- color. Un concepto de mas en la primera pantalla, que es donde menos margen
		-- hay para explicar nada.
		--
		-- La ruta de aprendizaje no se pierde: se funde en esta. Las dos vivian en la
		-- misma banda verde --cruce (1,2) y (0,2), misma fila-- asi que la verde no se
		-- mueve de su zona, solo se acerca. Y el primer viaje MEJORA: sigue siendo el
		-- cruce recto de 146 studs sin girar, veinte segundos medidos, pero paga x1 en
		-- vez de x0,4.
		destino = Grid.cruce(1, 2), -- el cruce recto al salir del recinto: 146 studs, cero giros
		-- DOS, que es la densidad de la verde de antes sobre un camino de la mitad de
		-- largo. La de aprendizaje llevaba uno --ahi el peligro se ensena, no se
		-- aplica-- y esta ya no es solo aprendizaje: es la primera ruta de verdad.
		detectores = 2,
		pvp = "ninguno",
	},
	{
		id = "ambar",
		multiplicador = 3,
		nivel = 3,
		-- ACERCADA igual que la verde: 1.034 studs de camino real eran 129 s de ida
		-- y vuelta a pie. El punto nuevo está a 740 del enganche sobre ese mismo
		-- camino -- 46 s de ida a pie, 31 con patinete eléctrico.
		destino = Grid.cruce(2, 1), -- al este, cruzando a la banda ambar: 438 studs, un giro
		detectores = 9,
		pvp = "transportistas",
	},
	{
		id = "roja",
		multiplicador = 10,
		nivel = 8,
		-- DOS REFUGIOS, y es el unico sitio del juego donde hace falta mas de uno.
		--
		-- Medido el 20/08 recorriendo el camino de cada ruta y buscando el refugio mas
		-- cercano: la roja tenia el 45 % de su recorrido a mas de 200 studs del unico
		-- que hay, con un punto a 345. Y es la ruta con mas ladrones, mas detectores y
		-- la unica que paga x10 -- justo la que no puede quedarse sin sitio donde
		-- meterse.
		--
		-- La causa es geometrica: mide 730 studs, el doble que la ambar, y comparte con
		-- ella el primer tramo, asi que sus candidatos chocaban --`sitioLlano` rechaza
		-- lo que cae encima de algo ya puesto-- y el que sobrevivia era siempre el del
		-- principio. Con dos, el reparto los separa a lo largo del camino y el tramo
		-- final deja de estar desnudo.
		refugios = 2,
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
		destino = Grid.cruce(3, 0), -- al fondo de la banda roja: 730 studs, un giro
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

-- LA ESQUINA VIGILADA TAMBIEN MIRA, y esto es de las cosas que cambian el juego.
--
-- Hasta el 20/08 era un sensor de proximidad puro: entrabas en su radio y te
-- fichaba, con o sin pared de por medio. Medido a proposito --de pie al otro lado
-- de `Edificio_0_0_1`, a 30 studs-- el calor subia igual. Y la caja negra lo
-- remato: en un viaje entero de la ruta verde el aviso *"alguien ha visto tu
-- rastro"* salto con UN ladron cerca y CERO que te vieran. Eso es lo que JJ
-- describio como *"no acabo de ver el tema de la deteccion de las esquinas; que te
-- detecten solo enemigos si miran"*.
--
-- Ahora la esquina tiene cara: mira a un rumbo fijo, dibuja su cono en el suelo
-- igual que el ladron, y solo ficha a quien esta DENTRO del cono y sin pared de
-- por medio. Con eso, la vigilancia deja de ser un impuesto por pasar y pasa a ser
-- lo que prometia el diseno: algo que se lee en el mapa y se rodea.
--
-- 45 grados de semiapertura (90 de par en par) y no los 60 del ladron. La esquina
-- no se mueve, asi que su cono es la unica informacion que da: tiene que quedar un
-- cuadrante ciego GRANDE y evidente, o "pasar por detras" seria una casualidad en
-- vez de una jugada.
Config.DETECTOR_VISION_ANGULO = 45

-- CUANTO TIEMPO SIGUE VALIENDO EL CHIVATAZO DE UNA CAMARA.
--
-- Lo pidio JJ, y de paso dijo lo que este sistema tenia mal montado desde el
-- principio: *"que cuando te detecte una camara se alerten los ladrones y se
-- acerquen -- es el objetivo, no?"*. Si.
--
-- Hasta ahora la camara solo subia el CALOR, y el calor solo decidia CUANTOS
-- ladrones salian. Los que ya estaban en la calle no se enteraban de nada: seguian
-- esperando a verte con sus propios ojos. Asi que ser fichado no tenia consecuencia
-- inmediata, y una amenaza que no llega es una amenaza que no se respeta.
--
-- Ahora la camara hace lo que hace una camara: no te roba, te DELATA. Todas las
-- patrullas de ese jugador reciben tu ultima posicion conocida y van hacia alla,
-- aunque no te vean.
--
-- Doce segundos, el doble que la memoria de un ladron (4). Un ladron te pierde
-- cuando doblas una esquina; una camara ha dado un aviso por radio, y eso no
-- caduca porque tu te muevas. Es lo que hace que valga la pena rodear la esquina
-- vigilada aunque te cueste veinte studs.
Config.CAMARA_MEMORIA = 12

-- HACIA DONDE MIRA CADA UNA. Cuatro rumbos cardinales repartidos por el indice de
-- la esquina, y por tanto FIJOS Y APRENDIBLES, como todo lo demas de este mapa: la
-- misma esquina mira siempre igual, asi que la segunda vez que haces una ruta ya
-- sabes por donde ibas mal.
--
-- El paso de 3 y no de 1 es para que dos esquinas seguidas no miren al mismo sitio:
-- con paso 1 el rumbo gira una cuarta por esquina y salen tramos enteros barridos
-- en la misma direccion.
Config.DETECTOR_RUMBOS = { 0, 90, 180, 270 }
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
-- REESCALADOS AL TRAMO REAL (19/08). Con la retícula, el tramo por el que se reparten
-- refugios y guaridas mide 146 studs en la verde, no 300: con los márgenes de antes
-- --85 de casa, 55 del destino-- el hueco útil quedaba en seis studs y el refugio se
-- plantaba ENCIMA de la losa del destino. Lo cazó la sonda: "Destino_verde se pisa por
-- arriba, lo que se pisa ahí es Refugio_1".
-- 18 y no 45: desde que las manzanas se construyen por el perímetro, sus alas tienen
-- entre 28 y 40 studs de fondo, así que apartarse 45 del eje de la calle mete el
-- refugio DENTRO de un edificio. Y esos edificios ya no se pueden despejar --el mapa
-- es nuestro y se marca con `delMapa`-- así que el refugio se quedaría enterrado.
--
-- Con 18, el sitio al que corres está pegado al bordillo: se entra desde la calle, que
-- es lo que uno espera de un portal.
Config.REFUGIO_DESVIO = 18

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
-- 90 y no 50: el margen se cuenta a lo largo del camino desde la boca del recinto, y
-- la boca ya está a 60 studs del almacén -- así que 50 dejaba caer un refugio a 84 de
-- casa, dentro de la zona segura, donde meterse nunca es lo mejor que puedes hacer
-- porque el almacén está al lado y apaga el calor entero.
Config.REFUGIO_MARGEN_CASA = 90
-- Y lo que se aparta del destino, por el otro lado: un refugio a las puertas de la
-- entrega llega cuando el viaje ya está hecho.
Config.REFUGIO_MARGEN_DESTINO = 50
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
Config.REFUGIO_SEPARACION = 70

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
-- UNA POR RUTA, no tres. Con tres salían TRECE guaridas en un mapa de 610 x 464 --una
-- cada cuarenta studs de camino-- y dos consecuencias: el sitio del que huyes estaba
-- en todas partes, y ocupaban tanto que el refugio de la verde ya no encontraba dónde
-- plantarse (los refugios esquivan a las guaridas a propósito, para no mandarte a
-- guarecerte encima de lo que te persigue).
--
-- Con una por ruta, cada zona tiene un origen de peligro que se puede aprender y
-- rodear, que es lo que la guarida vino a ser.
-- CERO DESDE EL 20/08, y el sistema se queda entero por debajo.
--
-- Las guaridas eran edificios fijos de los que salian los ladrones, marcados en el
-- mapa para poder rodearlos. La idea era buena y estuvo ROTA desde el principio: el
-- ladron nacia sobre el tejado de su propia nave y no podia bajar, asi que durante
-- todo el desarrollo el peligro fue decorativo. Se arreglo esa misma manana, y JJ --que
-- las habia sufrido sin funcionar-- pidio quitarlas: *"el tema guaridas quitalo por
-- ahora porque no funcionan"*.
--
-- Se apaga con un cero en vez de borrar el codigo: la maquinaria --plantarlas, marcarlas
-- en el minimapa, hacer que el ladron salga por su puerta-- sigue ahi y probada, y
-- volver a encenderlas es cambiar este numero. Lo que no se puede es dejar a medias un
-- sistema que ya demostro que se rompe en silencio.
--
-- Sin guaridas, los ladrones salen por el respaldo que siempre existio: un cono hacia
-- donde vas, para que aparezcan DELANTE y los veas venir en vez de encontrartelos
-- encima.
Config.GUARIDAS_POR_RUTA = 0

-- Cuánto se apartan del camino recto. Menos que los refugios (100): una guarida
-- pegada al corredor es un obstáculo que hay que rodear, y ése es su trabajo.
Config.GUARIDA_DESVIO = 16

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

-- EL CAMPO DE VISION DEL LADRON, que es lo que le da espalda.
--
-- Hasta el 20/08 te perseguia por el hecho de existir: en cuanto el calor lo sacaba a
-- la calle sabia donde estabas, y la unica respuesta posible era correr mas. Eso hace
-- un juego de reflejos, y este quiere ser uno de decisiones. Lo pidio JJ viendolos
-- funcionar por primera vez: *"que solo detecten a la persona cuando esten mirando
-- hacia el... para que si pasas por detras no se enteren"*.
--
-- 60 de SEMIapertura, o sea 120 de par en par: es lo que abarca una persona sin girar
-- la cabeza, y deja una espalda de 240 por la que de verdad se puede pasar.
Config.LADRON_VISION_ANGULO = 60

-- Y hasta donde llega. Un poco mas que la distancia a la que aparecen (90-140), para
-- que el que sale delante de ti te vea de entrada: si naciera ya ciego, la mitad de las
-- apariciones no significarian nada.
Config.LADRON_VISION_ALCANCE = 120

-- CUANTO RECUERDA DONDE TE VIO. Sin memoria, un ladron que te pierde se queda plantado
-- y se le nota tonto enseguida; con memoria infinita no tiene espalda. Cuatro segundos
-- bastan para que venga hasta la esquina por la que desapareciste -- y si al llegar no
-- estas, te ha perdido de verdad.
Config.LADRON_MEMORIA = 4

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
--
-- Subido de 40 a 54 con la escalera entera: el coche va a 38 y el impulso del
-- rastro suma hasta 12, o sea 50 en el mejor caso imaginable. El tope tiene que
-- quedar POR ENCIMA de lo que el propio juego reparte, o el antitrampas empieza a
-- expulsar a quien juega bien -- que es la peor avería que puede tener un
-- antitrampas, porque el que hace trampas no se queja y el jugador honrado se va.
Config.VELOCIDAD_MAXIMA_PLAUSIBLE = 54

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
-- SEPARADAS, no seguidas. Es el segundo movimiento del mismo sistema y lo pidio
-- JJ el 20/08: *"podemos dejarlos mas espaciados y que sean un rayo, y que te den
-- un empujoncito de velocidad temporal por si estas huyendo; asi para rutas mas
-- dificiles puede venir bien recogerlos"*.
--
-- El paso de 22 nacio para que la fila DIBUJARA el camino, y ese trabajo ya no es
-- suyo: la ruta se pinta en el plano del minimapa desde que se quito la linea del
-- asfalto. Liberada de senalizar, la miga puede volver a ser lo unico que de
-- verdad es -- un premio-- y un premio cada segundo y medio no es un premio, es
-- una alfombra.
--
-- Con 40 se pisa una cada dos segundos, y cada una vale siete veces mas
-- que antes. Eso convierte "cojo la siguiente o corto por aqui" en una pregunta
-- con respuesta distinta segun lo que lleves detras, que es exactamente lo que no
-- pasaba cuando cada pieza valia 0,4 studs/s.
Config.RASTRO_PASO = 40

-- Y NUNCA MENOS DE ESTO, por corta que sea la ruta.
--
-- Existe porque un paso absoluto no sobrevive a que cambie el largo de aquello que
-- mide: la verde se acorto de 558 studs a 147 el 19/08, el paso se quedo en 22, y
-- con el corredor util en 89 studs la primera ruta del juego se quedo con UN rayo.
-- Nadie lo vio -- las sondas contaban piezas plantadas, no piezas por ruta.
--
-- Cuatro es el minimo con el que la mecanica se ENSENA: uno no es una fila, dos no
-- es una cadena, y con cuatro seguidas el jugador nuevo ve por primera vez lo que
-- pasa cuando se encadenan. La ruta corta los reparte mas juntos, que es justo lo
-- que debe hacer una ruta corta.
Config.RASTRO_MINIMO = 4

-- ─────────────────────────────────────────────────────────────────────────────
-- DOS CLASES DE RECOGIBLE, no una.
--
-- Lo pidio JJ el 20/08: *"los paquetes a recoger deberian ser items diferentes:
-- uno da velocidad, el otro mega salto, algo asi"*. Y es mas que variedad -- es lo
-- que convierte la fila en una DECISION. Con una sola clase, seguir el rastro es
-- una regla ("pisalo todo"); con dos, cada pieza que ves a lo lejos plantea una
-- pregunta distinta, porque velocidad y salto no sirven para lo mismo: la
-- velocidad es para la recta y el salto es para el atajo.
--
-- Se ALTERNAN por indice, asi que el reparto es fijo y aprendible como todo lo
-- demas de este mapa: la segunda vez que haces una ruta sabes cual viene.
Config.RECOGIBLE_VELOCIDAD = "velocidad"
Config.RECOGIBLE_SALTO = "salto"
Config.RECOGIBLE_ESCUDO = "escudo"

-- Los tres, EN ORDEN DE REPARTO. Se turnan por indice, asi que la fila alterna
-- boost, salto, escudo, boost... y el jugador que repite una ruta sabe cual viene.
Config.RECOGIBLES = { Config.RECOGIBLE_VELOCIDAD, Config.RECOGIBLE_SALTO, Config.RECOGIBLE_ESCUDO }

-- CUANTO SALTA con el impulso puesto, como multiplo de Config.SALTO_ALTURA.
--
-- Con 2,2 se pasa de 10 a 22 studs, que es subirse de un brinco a la planta baja
-- de un edificio de la reticula. Ese numero no es decorativo: es lo que hace que
-- el salto sea un ATAJO --cortar por encima de una manzana en vez de rodearla-- y
-- no solo un brinco mas alto. Si no abriera camino nuevo, seria velocidad peor.
Config.SALTO_IMPULSO_FACTOR = 2.2

-- Y CUANTO DURA. Ocho segundos es lo que se tarda en cruzar una manzana a la
-- carrera: da para usarlo donde lo coges, no para llevartelo media ruta. Se
-- refresca al coger otro, no se acumula -- acumular convertiria un rastro de seis
-- saltos en un minuto entero volando, y entonces la ciudad deja de existir.
Config.SALTO_IMPULSO_SEGUNDOS = 8

-- EL ESCUDO ANTIRROBO. Lo pidio JJ como tercera clase de recogible, y es la que le
-- faltaba al juego: hasta ahora TODO lo que se recoge sirve para ir mas deprisa, y
-- eso deja una sola respuesta a cualquier problema -- correr mas.
--
-- El escudo contesta otra pregunta. Cuando ya te han visto y no vas a ganar la
-- carrera, la jugada deja de ser "acelera" y pasa a ser "aguanta". Y encaja con lo
-- unico que de verdad duele en este juego: que te quiten la carga.
--
-- DOCE SEGUNDOS. Mas que el salto porque no acorta el viaje ni un stud: solo evita
-- una perdida, y una perdida que puede no llegar a pasar. Un escudo corto seria un
-- premio que casi siempre caduca sin haber servido para nada.
Config.ESCUDO_SEGUNDOS = 12

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
-- LA RECARGA, LARGA A PROPÓSITO. Con 15 segundos, una miga que cogías al empezar
-- estaba otra vez encendida antes de llegar al destino -- y desde dentro eso se ve
-- exactamente como lo describió JJ: "los paquetes que se cogen no desaparecen". No era
-- que no desaparecieran: es que volvían.
--
-- Con 240 no vuelven dentro del mismo viaje ni del siguiente. La recarga existe para
-- que el mapa no se quede pelado en una partida larga, no para reponer el rastro que
-- acabas de recorrer.
Config.CONTACTO_RECARGA = 240

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
	-- La verde lleva cuatro doradas y un racimo. Bajo de seis a cuatro al mudarse al
	-- cruce recto: seis sobre 146 studs es una cada veinticuatro, y un rastro tan
	-- tupido deja de leerse como un camino y pasa a ser una alfombra.
	verde = { sueltos = 4, racimos = 1 },
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
-- Reajustada OTRA VEZ el 20/08, y al reves que la vez anterior: cada pieza vale
-- 3 studs/s en lugar de 0,4, y el techo sube de 6 a 12.
--
-- El motivo es que 0,4 no se notaba. A pie son 20 studs/s: coger una miga movia la
-- velocidad un DOS POR CIENTO, o sea nada que un ojo humano pueda ver -- habia que
-- encadenar quince para que el viaje cambiara, y quince es medio recorrido. El
-- premio existia en el numero y no en la mano.
--
-- Con 3, una sola pieza es un +15 % que se ve al instante, y cuatro seguidas te
-- ponen a 32 -- por encima de cualquier patrulla que te venga detras. Eso es lo
-- que lo convierte en una herramienta de fuga en vez de en una estadistica: cuando
-- oyes la sirena, la respuesta pasa a ser "vete a por la fila", que es una decision
-- que el jugador puede tomar.
Config.RACHA_POR_CONTACTO = 3
Config.RACHA_MAXIMA = 12 -- el coche (38) queda en 50, con el antitrampas en 54

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
-- La gracia baja a 3 con el paso nuevo. Y ojo a lo que significa DECAE ahora: se
-- cuenta en PIEZAS por segundo, asi que perder una es perder 3 studs/s. Del tope
-- al suelo van cuatro segundos, que es lo que hace que el impulso sea TEMPORAL de
-- verdad -- y lo que hay que sostener para que siga siendolo si alguien vuelve a
-- tocar el valor de la pieza.
Config.RACHA_GRACIA = 3
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
-- LA RUTA CON LA QUE SE EMPIEZA. Ya no se asigna sola al coger el primer paquete
-- --desde el 19/08 el selector aparece en ese momento y elige el jugador-- pero sigue
-- siendo la que tiene que estar abierta sin nivel ni hitos, y eso lo comprueban las
-- pruebas: si un día se cierra, el jugador nuevo se queda con el zurrón lleno y sin
-- ningún destino que pueda elegir.
Config.RUTA_PRIMERA = "verde"

Config.HITOS = {
	-- Ya no abre nada: la verde esta abierta de salida desde que absorbio la ruta de
	-- aprendizaje. Sigue pagando la primera entrega, que es el unico peldano que
	-- todo el mundo pisa.
	{ id = "primera", entregas = 1, monedas = 50 },
	{ id = "tres", entregas = 3, monedas = 250 },
	{ id = "ambar", nivel = 3 },
	{ id = "ocho", entregas = 8, monedas = 1000 },
	{ id = "roja", nivel = 8, exigeMotor = true },
}

return Config
