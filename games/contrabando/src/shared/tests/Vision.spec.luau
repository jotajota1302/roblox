--!strict
--[[
	Vision.spec — que el ladrón tenga espalda.

	La regla que estas pruebas sujetan es la que convierte la persecución en algo que se
	juega: si pasas por detrás, no se entera. Sin ella el ladrón es omnisciente y la
	única respuesta posible es correr más.
]]

local Vision = require(script.Parent.Parent.Vision)

return function(kit)
	local ORIGEN = Vector3.new(0, 0, 0)
	local NORTE = Vector3.new(0, 0, 1)

	-- LO BASICO: delante si, detras no.
	kit.truthy("ve lo que tiene justo delante", Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(0, 0, 50), 60, 100))
	kit.falsy("y no ve lo que tiene justo detras", Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(0, 0, -50), 60, 100))
	kit.falsy(
		"ni lo que tiene a la espalda en diagonal",
		Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(40, 0, -40), 60, 100)
	)

	-- EL BORDE DEL CONO. Con semiapertura 60, algo a 45 grados entra y algo a 75 no.
	local en45 = Vector3.new(50, 0, 50)
	local en75 = Vector3.new(96.6, 0, 25.9)
	kit.truthy("a cuarenta y cinco grados todavia lo ve", Vision.dentroDelCono(ORIGEN, NORTE, en45, 60, 200))
	kit.falsy("a setenta y cinco ya no", Vision.dentroDelCono(ORIGEN, NORTE, en75, 60, 200))

	-- EL ALCANCE manda aunque este de frente: un ladron no ve al otro lado del mapa.
	kit.truthy("de frente y cerca, lo ve", Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(0, 0, 90), 60, 100))
	kit.falsy("de frente pero lejos, no", Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(0, 0, 110), 60, 100))

	-- SE MIDE EN PLANTA. Estar en una acera un stud mas alta no puede sacarte del cono:
	-- es el mismo error que un dia convirtio 83 studs de altura en "83 de desviacion".
	kit.truthy("la altura no cuenta", Vision.dentroDelCono(ORIGEN, NORTE, Vector3.new(0, 40, 50), 60, 100))

	-- CASOS RAROS, que son donde se cuelan los fallos.
	kit.truthy("encima de el lo ve, mire donde mire", Vision.dentroDelCono(ORIGEN, NORTE, ORIGEN, 60, 100))
	kit.falsy(
		"sin direccion de mirada no se inventa una",
		Vision.dentroDelCono(ORIGEN, Vector3.new(0, 0, 0), Vector3.new(0, 0, 10), 60, 100)
	)
	kit.truthy(
		"mirando hacia arriba, la componente en planta es la que decide",
		Vision.dentroDelCono(ORIGEN, Vector3.new(0, 50, 1), Vector3.new(0, 0, 50), 60, 100)
	)

	-- LA MEMORIA CORTA: va al ultimo sitio donde te vio, y deja de buscarte al caducar.
	local recuerdo = { donde = Vector3.new(10, 0, 10), cuando = 100 }
	kit.eq("recien perdido, va a donde te vio", Vision.aDondeVa(recuerdo, 102, 5), recuerdo.donde)
	kit.eq("pasada la memoria, te ha perdido", Vision.aDondeVa(recuerdo, 106, 5), nil)
	kit.eq("y sin recuerdo no va a ninguna parte", Vision.aDondeVa(nil, 100, 5), nil)
end
