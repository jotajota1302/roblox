--!strict
-- Los alijos: lo unico que se gana FUERA del camino. Lo que hay que fijar aqui es
-- justamente eso -- el dia que uno caiga sobre una ruta, deja de premiar explorar y
-- pasa a ser una miga mas, y eso no da ningun error.
local Caches = require(script.Parent.Parent.Caches)
local Config = require(script.Parent.Parent.Config)
local Grid = require(script.Parent.Parent.Grid)
local Perimeter = require(script.Parent.Parent.Perimeter)

return function(kit)
	local caminos: { { Vector3 } } = {}
	for _, ruta in Config.RUTAS do
		local camino = { Config.ALMACEN_POS }
		for _, p in Grid.porCalles(Config.POLIGONO_SALIDA, ruta.destino) do
			table.insert(camino, p)
		end
		table.insert(caminos, camino)
	end

	local sitios = Caches.sitios(caminos)
	kit.truthy("hay escondites donde plantar alijos", #sitios >= Config.ALIJOS)

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
			mejor = math.min(mejor, (ap - ab.Unit * t).Magnitude)
		end
		return mejor
	end

	local pegados, enCasa = 0, 0
	for _, sitio in sitios do
		for _, camino in caminos do
			if alCamino(sitio, camino) < Caches.LEJOS then
				pegados += 1
			end
		end
		if Perimeter.dentro(sitio, Config.ZONA_SEGURA_RADIO) then
			enCasa += 1
		end
	end
	-- LEJOS DE LOS TRES CAMINOS, no solo del tuyo: uno sobre la roja seria una miga
	-- gratis para quien va por la roja y una razon para cambiarse de ruta para todos
	-- los demas.
	kit.eq("ningun escondite cae pegado a una ruta", pegados, 0)
	-- Y FUERA DE CASA: dentro de la zona segura se recogeria sin salir, o sea que
	-- premiaria estar quieto.
	kit.eq("ninguno cae dentro de la zona segura", enCasa, 0)

	-- MISMA SEMILLA, MISMOS ESCONDITES. Es lo que permite volver a mirar una partida
	-- rara, y lo que hace que un jugador que repite acabe sabiendo donde suelen estar
	-- -- que es el conocimiento que este juego quiere premiar.
	local a = Caches.elegidos(caminos, Config.ALIJOS, 4242)
	local b = Caches.elegidos(caminos, Config.ALIJOS, 4242)
	kit.eq("se eligen los que se piden", #a, math.min(Config.ALIJOS, #sitios))
	local iguales = true
	for i, sitio in a do
		if (sitio - b[i]).Magnitude > 0.01 then
			iguales = false
		end
	end
	kit.truthy("con la misma semilla salen los mismos", iguales)

	-- Y NINGUNO REPETIDO. Sorteando uno a uno con repeticion salen dos en el mismo
	-- sitio, y dos premios juntos no son dos escondites: son uno el doble de grande.
	local vistos: { [string]: boolean } = {}
	local repetidos = 0
	for _, sitio in a do
		local clave = string.format("%.0f,%.0f", sitio.X, sitio.Z)
		if vistos[clave] then
			repetidos += 1
		end
		vistos[clave] = true
	end
	kit.eq("no se repite ningun escondite", repetidos, 0)

	-- Con semillas distintas, reparto distinto: si no, el sorteo seria decorativo.
	local otro = Caches.elegidos(caminos, Config.ALIJOS, 99)
	local algunoCambia = false
	for i, sitio in otro do
		if a[i] == nil or (sitio - a[i]).Magnitude > 0.01 then
			algunoCambia = true
		end
	end
	kit.truthy("con otra semilla cambian los escondites", algunoCambia)

	-- EL PREMIO: SIEMPRE algo. Un escondite que a veces sale vacio ensena en dos
	-- intentos que no vale la pena desviarse.
	local conObjeto, sinObjeto = 0, 0
	for i = 0, 99 do
		local xp, objeto = Caches.premio(i / 100)
		kit.eq("un alijo siempre paga experiencia (tirada " .. i .. ")", xp, Config.ALIJO_XP)
		if objeto ~= nil then
			conObjeto += 1
		else
			sinObjeto += 1
		end
	end
	kit.truthy("y a veces ademas un artefacto", conObjeto > 0)
	kit.truthy("pero no siempre", sinObjeto > 0)
	-- La proporcion es la de Config, no una que se haya ido colando por el camino.
	kit.eq("uno de cada tres lleva artefacto", conObjeto, math.floor(Config.ALIJO_PROBABILIDAD_OBJETO * 100))

	-- Y EL ARTEFACTO ES DE LOS QUE CABEN EN UNA CASILLA. Si algun dia se colara la
	-- velocidad --que no se guarda-- el alijo pagaria un objeto que se tira.
	for i = 0, 99 do
		local _, objeto = Caches.premio(i / 100)
		if objeto ~= nil then
			local guardable = false
			for _, id in Config.OBJETOS_GUARDABLES do
				if id == objeto then
					guardable = true
				end
			end
			kit.truthy("el artefacto del alijo cabe en una casilla (" .. objeto .. ")", guardable)
		end
	end

	-- EL RADIO DE RECOGIDA TIENE QUE SER MAYOR QUE EL DE UNA MIGA. Un alijo esta
	-- APARTADO del eje de la calle: si hubiera que pisarlo exacto, la mitad de las
	-- veces se veria y no se cogeria -- que es la queja que se llevo por delante los
	-- racimos.
	kit.truthy("se recoge desde mas lejos que una miga", Config.ALIJO_RADIO > Config.CONTACTO_RADIO)
	-- Y LA RECARGA, MAS LARGA QUE UN VIAJE: si no, dar una ronda de alijos en bucle
	-- seria mejor negocio que repartir, y el juego dejaria de ser un juego de rutas.
	kit.truthy("no se pueden farmear en bucle", Config.ALIJO_RECARGA > 120)

	-- Y LA MARCA DEL SUELO CABE EN LA CALLE. Es la unica cota que impide que vuelva a
	-- pasar lo del 21/08: el halo salia de `ALIJO_RADIO * 1.6` --28,8 studs sobre una
	-- calzada de 26-- asi que el disco amarillo pintaba la calle entera y el alijo
	-- dejaba de leerse como un premio. Nada dio error; se vio jugando.
	--
	-- Atado al ancho de calle y no a un numero suelto, porque un absoluto no sobrevive
	-- a que cambie aquello que mide: el dia que la calzada se estreche, esta prueba se
	-- entera y `RASTRO_PASO` no se entero.
	kit.truthy("la marca del alijo no pinta la calzada entera", Config.ALIJO_HALO < Grid.ANCHO_CALLE)
	-- Y sigue siendo mayor que el bulto: una marca mas pequena que la caja no marca.
	kit.truthy("la marca es mayor que el bulto que senala", Config.ALIJO_HALO > 3.4)
end
