--!strict
--[[
	Vision.luau — quién ve a quién. Módulo PURO.

	POR QUÉ EXISTE. Hasta el 20/08 el ladrón te perseguía por el simple hecho de que
	existieras: en cuanto el calor lo sacaba a la calle, sabía dónde estabas y no había
	forma de despistarlo salvo correr más. Eso hace un juego de reflejos, y éste quería
	ser uno de decisiones.

	Lo pidió JJ viéndolos funcionar por primera vez: *"estaría bien que sólo detectaran
	a la persona cuando estén mirando hacia él, que tengan como un foco visual o campo
	de visión hacia delante, y que se vea así, para que si pasas por detrás no se
	enteren"*. Y es exactamente la regla que convierte una persecución en algo que se
	juega: si el peligro tiene una espalda, esconderse existe.

	La cuenta es un producto escalar y podría estar dentro de PatrolService. Vive aquí
	--y con pruebas-- por lo que este proyecto ya sabe de sí mismo: la lógica que se
	queda dentro de un servicio no se puede comprobar sin abrir Studio, y lo que no se
	comprueba se rompe en silencio. El sistema de vigilancia entero estuvo apagado
	durante todo el desarrollo y nadie lo supo.
]]

local Vision = {}

-- ¿Está `donde` dentro del cono de quien está en `desde` mirando hacia `mirando`?
--
-- SE MIDE EN PLANTA, ignorando la altura, y no es pereza: las dos figuras están de pie
-- sobre el mismo suelo, y meter la Y sólo consigue que estar en una acera un stud más
-- alta te saque del cono. Es el mismo error que un día convirtió 83 studs de altura en
-- "83 studs de desviación".
--
-- `angulo` es la SEMIAPERTURA en grados: 60 significa un cono de 120 de par en par, que
-- es lo que abarca una persona sin girar la cabeza.
function Vision.dentroDelCono(
	desde: Vector3,
	mirando: Vector3,
	donde: Vector3,
	angulo: number,
	alcance: number
): boolean
	local dx = donde.X - desde.X
	local dz = donde.Z - desde.Z
	local distancia = math.sqrt(dx * dx + dz * dz)
	if distancia > alcance then
		return false
	end
	-- Encima de él: no hay dirección que valga, y decir que no lo ve sería absurdo.
	if distancia < 1 then
		return true
	end

	local lx, lz = mirando.X, mirando.Z
	local largo = math.sqrt(lx * lx + lz * lz)
	if largo < 0.001 then
		-- Sin dirección de mirada no se inventa una: mejor ciego que omnisciente.
		return false
	end

	-- Producto escalar de los dos unitarios = coseno del ángulo que los separa.
	local coseno = (dx * lx + dz * lz) / (distancia * largo)
	return coseno >= math.cos(math.rad(angulo))
end

-- Lo mismo, pero contando el ÚLTIMO SITIO DONDE TE VIO.
--
-- Un ladrón que te pierde de vista y se queda plantado es tonto de una forma que se
-- nota enseguida; uno que sigue sabiendo dónde estás no tiene espalda. La memoria corta
-- resuelve las dos cosas: durante `memoria` segundos va hacia donde te vio por última
-- vez, y si al llegar no estás, te ha perdido de verdad.
--
-- Devuelve a dónde debe ir, o nil si ya no te busca.
export type Recuerdo = {
	donde: Vector3,
	cuando: number,
}

function Vision.aDondeVa(recuerdo: Recuerdo?, ahora: number, memoria: number): Vector3?
	if recuerdo == nil then
		return nil
	end
	if ahora - recuerdo.cuando > memoria then
		return nil
	end
	return recuerdo.donde
end

return Vision
