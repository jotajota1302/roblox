--!strict
--[[
	Caches.luau — donde se esconden los alijos. Modulo PURO.

	POR QUE EXISTE. *"Deberiamos poner por ahi puntos de experiencia sueltos
	tambien, no solo en el camino, asi premiamos la exploracion y el coger artefactos
	que te pueden servir"* (JJ). Y es la pieza que le falta al mapa: hoy TODO lo que
	se gana esta sobre la linea que va de casa al destino -- las migas, los
	contactos, la entrega. La ciudad entera que hay a los lados no da nada, asi que
	no hay ninguna razon para mirarla. Un mapa que no se mira igual podria ser un
	pasillo.

	LA REGLA QUE LOS DEFINE: un alijo tiene que estar LEJOS DE TODOS LOS CAMINOS.
	No de "tu" camino: de los tres. Si uno cayera sobre la ruta roja, para quien va
	por la roja no seria una exploracion, seria una miga mas -- y para el que va por
	la verde seria una razon para cambiarse de ruta, que es lo ultimo que se quiere.
	Lo que premian es SALIRSE, y salirse tiene que costar lo mismo salgas de donde
	salgas.

	Y CERCA DE UNA CALLE, no en mitad de una manzana. Es la leccion mas cara de este
	proyecto en cuanto a recogibles: los racimos se quitaron porque *"salen paquetes
	fuera de la ruta y no se pueden coger"* -- lo que se VE y no se ALCANZA no se lee
	como una decision, se lee como un fallo. Un alijo tiene que estar en un sitio al
	que se llega andando, y a ser posible al que se llega VIENDO que se puede llegar:
	por eso se plantan sobre el eje de las calles y no en los patios.

	DETERMINISTA. La misma semilla da los mismos escondites, igual que los destinos:
	sin eso, "me ha salido un alijo imposible" no se puede volver a mirar. Y como el
	mapa es fijo y aprendible, un jugador que repite acaba sabiendo donde suelen
	estar -- que es exactamente el conocimiento que este juego quiere premiar.
]]

local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)
local Perimeter = require(script.Parent.Perimeter)

local Caches = {}

-- A cuanto tiene que estar del camino mas cercano para que valga como desvio.
--
-- Sesenta studs son unos cuatro segundos de ida y cuatro de vuelta a pie cargado:
-- se paga con tiempo, que es lo unico que de verdad escasea aqui, y no tanto como
-- para que nadie se desvie nunca. Por debajo de 40 el alijo se recoge sin querer al
-- pasar --y entonces no premia explorar, premia caminar-- y por encima de 90 se
-- convierte en una excursion que solo hace quien ya iba sobrado.
Caches.LEJOS = 60

-- Los sitios posibles: los cruces de la reticula y los puntos medios de cada tramo
-- de calle. Los puntos medios importan mas de lo que parece -- un alijo en un cruce
-- se ve desde las cuatro calles que llegan a el, y uno a mitad de tramo solo desde
-- dos: el segundo es un escondite y el primero es un cartel.
local function candidatos(): { Vector3 }
	local lista: { Vector3 } = {}
	for i = 0, Grid.COLUMNAS do
		for j = 0, Grid.FILAS do
			local cruce = Grid.cruce(i, j)
			table.insert(lista, cruce)
			if i < Grid.COLUMNAS then
				local siguiente = Grid.cruce(i + 1, j)
				table.insert(lista, cruce:Lerp(siguiente, 0.5))
			end
			if j < Grid.FILAS then
				local siguiente = Grid.cruce(i, j + 1)
				table.insert(lista, cruce:Lerp(siguiente, 0.5))
			end
		end
	end
	return lista
end

-- La distancia de un punto a una polilinea, en el plano. Es la misma cuenta que
-- `Contacts.distanciaAlCamino` y esta repetida A PROPOSITO: `Contacts` habla de lo
-- que se planta SOBRE el camino y esto de lo que se planta LEJOS de el, y hacer que
-- uno dependa del otro ataria dos sistemas que no tienen nada que ver salvo la
-- geometria. Son ocho lineas; el acoplamiento sale mas caro.
local function alCamino(punto: Vector3, camino: { Vector3 }): number
	local mejor = math.huge
	for i = 1, #camino - 1 do
		local a, b = camino[i], camino[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if ab.Magnitude < 0.01 then
			continue
		end
		local ap = Vector3.new(punto.X - a.X, 0, punto.Z - a.Z)
		local t = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
		local d = (ap - ab.Unit * t).Magnitude
		if d < mejor then
			mejor = d
		end
	end
	return mejor
end

-- Los escondites que valen, en orden: lejos de todos los caminos y fuera de casa.
--
-- Devuelve TODOS los que cumplen y no solo los que se van a usar, porque quien
-- planta descarta luego los que no encuentran calle donde caer: si el filtro de
-- "cuantos" se hiciera aqui, cada sitio perdido en el mundo seria un alijo menos y
-- la partida tendria menos premios sin que nadie supiera por que. Es el mismo
-- motivo por el que las migas doradas se reparten sobre las plantadas.
function Caches.sitios(caminos: { { Vector3 } }): { Vector3 }
	local buenos: { Vector3 } = {}
	for _, punto in candidatos() do
		-- Fuera de la zona segura: un alijo dentro de casa se recoge sin salir, y
		-- entonces no premia explorar -- premia estar quieto.
		if Perimeter.dentro(punto, Config.ZONA_SEGURA_RADIO) then
			continue
		end
		local cerca = false
		for _, camino in caminos do
			if alCamino(punto, camino) < Caches.LEJOS then
				cerca = true
				break
			end
		end
		if not cerca then
			table.insert(buenos, punto)
		end
	end
	return buenos
end

-- Cuales de esos se usan esta partida, repartidos por el mapa.
--
-- SE BARAJA Y SE COGEN LOS PRIMEROS, en vez de sortear uno a uno: sorteando con
-- repeticion salen dos alijos en el mismo sitio, y dos premios juntos en una ciudad
-- de mil studs no son dos escondites, son uno el doble de grande.
function Caches.elegidos(caminos: { { Vector3 } }, cuantos: number, semilla: number): { Vector3 }
	local buenos = Caches.sitios(caminos)
	local rng = Random.new(semilla)
	for i = #buenos, 2, -1 do
		local j = rng:NextInteger(1, i)
		buenos[i], buenos[j] = buenos[j], buenos[i]
	end
	local salida: { Vector3 } = {}
	for i = 1, math.min(cuantos, #buenos) do
		table.insert(salida, buenos[i])
	end
	return salida
end

-- QUE TE LLEVAS AL ABRIRLO. Siempre experiencia; a veces, ademas, un artefacto.
--
-- SIEMPRE ALGO, y esa es la regla que hace que merezca la pena desviarse la
-- SEGUNDA vez. Un cofre que a veces sale vacio ensena en dos intentos que no vale
-- la pena, y a partir de ahi el mapa vuelve a ser un pasillo. La variedad esta en
-- lo que toca ademas, no en si toca.
--
-- Puro y con la tirada por parametro para poder probarlo: `Random` aqui dentro
-- haria que la prueba dependiera de la suerte.
function Caches.premio(tirada: number): (number, string?)
	if tirada < Config.ALIJO_PROBABILIDAD_OBJETO then
		-- El artefacto alterna por la propia tirada, asi que no hace falta un segundo
		-- sorteo: la mitad baja del tramo da salto y la alta, escudo.
		local cual = if tirada < Config.ALIJO_PROBABILIDAD_OBJETO / 2
			then Config.RECOGIBLE_SALTO
			else Config.RECOGIBLE_ESCUDO
		return Config.ALIJO_XP, cual
	end
	return Config.ALIJO_XP, nil
end

return Caches
