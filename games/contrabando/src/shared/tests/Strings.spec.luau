--!strict
-- Pruebas del fichero de textos. Las cinco últimas no comprueban una función:
-- comprueban el CONTENIDO de la tabla, que es donde estaba el bug real. Un texto
-- en castellano o un catálogo sin su fila no rompen nada al ejecutar -- se ven
-- jugando, tarde y por casualidad, que es exactamente como se descubrieron los
-- nueve castellanos que sobrevivieron a la traducción a mano del 18/08.

local Config = require(script.Parent.Parent.Config)
local Goods = require(script.Parent.Parent.Goods)
local Skills = require(script.Parent.Parent.Skills)
local Strings = require(script.Parent.Parent.Strings)

return function(kit)
	-- ---- El formateo -----------------------------------------------------
	kit.eq("sin parámetros devuelve la plantilla", Strings.format("Hello", nil), "Hello")
	kit.eq("sustituye un parámetro", Strings.format("Level {nivel}", { nivel = 4 }), "Level 4")
	kit.eq("sustituye varios", Strings.format("+{monedas} for {items}", { monedas = 250, items = 3 }), "+250 for 3")
	kit.eq("lo que no es parámetro no se toca", Strings.format("100% sure {x}", { x = "ok" }), "100% sure ok")

	-- EL HUECO SE VE. Un parámetro que nadie rellena deja la llave a la vista en
	-- vez de un blanco: el blanco pasa la revisión y "{monedas}" no.
	kit.eq("el parámetro que falta se queda visible", Strings.format("+{monedas} now", {}), "+{monedas} now")

	-- ---- Las referencias --------------------------------------------------
	kit.eq(
		"una referencia se traduce también",
		Strings.get("MISSION_DELIVER_IN", { ruta = Strings.ref("ROUTE_verde") }),
		"Deliver in GREEN"
	)
	-- Una referencia rota devuelve la clave, no revienta: el juego sigue y la
	-- errata se ve en pantalla.
	kit.eq(
		"una referencia a una clave que no existe no rompe",
		Strings.get("MISSION_DELIVER_IN", { ruta = Strings.ref("ROUTE_no_existe") }),
		"Deliver in ROUTE_no_existe"
	)
	kit.eq("una clave desconocida se devuelve tal cual", Strings.get("NO_EXISTE"), "NO_EXISTE")

	-- ---- El traductor de la nube -----------------------------------------
	Strings.usarTraductor(function(clave)
		return if clave == "HUD_MONEY" then "Dinero" else nil
	end)
	kit.eq("con traductor, manda la nube", Strings.get("HUD_MONEY"), "Dinero")
	kit.eq("y lo que la nube no tiene cae al inglés", Strings.get("HUD_CARGO"), "Cargo")
	-- Un traductor que revienta no puede llevarse el juego por delante: sin esto,
	-- quedarse sin red dejaría la pantalla en blanco en vez de en inglés.
	Strings.usarTraductor(function()
		error("sin red")
	end)
	kit.eq("un traductor que falla cae al inglés", Strings.get("HUD_CARGO"), "Cargo")
	Strings.usarTraductor(nil)
	kit.eq("y quitándolo se vuelve al inglés", Strings.get("HUD_MONEY"), "Money")

	-- ---- El contenido de la tabla ----------------------------------------
	local vacios, conFormat, malParametro = 0, 0, 0
	for clave, texto in Strings.TEXTOS do
		if texto == "" then
			vacios += 1
		end
		-- Un string.format colado es un texto que NO se puede traducir: el "%d" se
		-- rellena aquí y la cadena que llega a la tabla es distinta cada vez.
		if string.find(texto, "%%[sdf]") then
			conFormat += 1
		end
		-- Llaves mal escritas ("{}", "{ nivel }") no sustituyen nada y salen en
		-- pantalla tal cual.
		for dentro in string.gmatch(texto, "{([^}]*)}") do
			if dentro == "" or string.match(dentro, "^[%w_]+$") == nil then
				malParametro += 1
			end
		end
		if string.match(clave, "^[A-Z][%w_]*$") == nil then
			kit.truthy("la clave " .. clave .. " no tiene forma de clave", false)
		end
	end
	kit.eq("ningún texto está vacío", vacios, 0)
	kit.eq("ningún texto usa string.format", conFormat, 0)
	kit.eq("ningún parámetro está mal escrito", malParametro, 0)

	-- ---- Y LO QUE EMPEZÓ TODO: nada en castellano -------------------------
	--
	-- Red tosca a propósito. No distingue idiomas: caza la recaída concreta que ya
	-- pasó dos veces --una palabra del código colada en la interfaz-- y lo hace en
	-- una prueba en vez de en una partida.
	--
	-- Las tildes se buscan UNA A UNA y con búsqueda literal, no con una clase
	-- "[áéí]": los patrones de Lua van por bytes y "á" ocupa dos, así que la clase
	-- casaría bytes sueltos y el separador "·" que llevan medio de los textos
	-- comparte el primer byte con "¿". Medido: daba positivo en casi toda la tabla.
	local TILDES = { "á", "é", "í", "ó", "ú", "ñ", "Á", "É", "Í", "Ó", "Ú", "Ñ", "¿", "¡" }
	local RASTROS = { "huecos", "Oficina", "Cargar", "Bulto", "Guarida", "Concesionario", "Almacen", "Dinero" }
	--
	-- Se miran SIN los {parametros}: el nombre de un parámetro es código, y el
	-- código de esta casa va en castellano ("{huecos}", "{cuantas}"). Lo que tiene
	-- que estar en inglés es lo que se ve. Sin esta línea, GARAGE_CARD daba rojo
	-- por llamarse "huecos" su hueco.
	local castellanos = {}
	for clave, plantilla in Strings.TEXTOS do
		local texto = string.gsub(plantilla, "{[%w_]+}", "")
		local sospechoso = false
		for _, letra in TILDES do
			if string.find(texto, letra, 1, true) then
				sospechoso = true
				break
			end
		end
		if not sospechoso then
			for _, palabra in RASTROS do
				if string.find(texto, palabra, 1, true) then
					sospechoso = true
					break
				end
			end
		end
		if sospechoso then
			table.insert(castellanos, clave)
		end
	end
	kit.eq("ningún texto se quedó en castellano: " .. table.concat(castellanos, ", "), #castellanos, 0)

	-- ---- Cobertura de los catálogos --------------------------------------
	--
	-- Añadir un vehículo o una mercancía sin su fila aquí es un juego que enseña
	-- "RIDE_camion" al jugador. Esto lo caza al añadirlo, no al verlo.
	local function cubre(prefijo: string, lista: { any }, campo: string?)
		local faltan = {}
		for _, d in lista do
			local clave = prefijo .. tostring(d.id)
			if Strings.TEXTOS[clave] == nil then
				table.insert(faltan, clave)
			end
			if campo ~= nil and Strings.TEXTOS[clave .. campo] == nil then
				table.insert(faltan, clave .. campo)
			end
		end
		kit.eq("todo " .. prefijo .. " tiene texto: " .. table.concat(faltan, ", "), #faltan, 0)
	end

	cubre("RIDE_", Config.VEHICULOS)
	cubre("SIZE_", Config.TAMANOS)
	cubre("ROUTE_", Config.RUTAS)
	cubre("GOAL_", Config.HITOS)
	cubre("GOODS_", Goods.todos())
	cubre("SKILL_", Skills.CATALOGO, "_DESC")

	-- Y al revés en lo que más duele: cada motivo de rechazo que devuelve el
	-- servidor tiene que tener su explicación. Un motivo sin texto le enseña al
	-- jugador la clave interna justo cuando algo le ha salido mal.
	local MOTIVOS = {
		"sin_dinero",
		"ya_lo_tienes",
		"ya_tienes_uno_mejor",
		"no_esta_a_la_venta",
		"vehiculo_desconocido",
		"lejos_taller",
		"con_carga",
		"no_cabe_la_carga",
		"carga_demasiado_grande",
		"no_es_tuyo",
		"ya_lo_llevas",
		"nivel_insuficiente",
		"necesitas_motor",
		"ruta_desconocida",
		"en_ruta",
		"sin_carga_ruta",
		"fuera_del_recinto",
		"lejos_almacen",
		"al_maximo",
		"lejos_devolver",
		"ya_en_ruta",
	}
	local sinExplicacion = {}
	for _, motivo in MOTIVOS do
		if Strings.TEXTOS["DENY_" .. motivo] == nil then
			table.insert(sinExplicacion, motivo)
		end
	end
	kit.eq("todo rechazo se explica: " .. table.concat(sinExplicacion, ", "), #sinExplicacion, 0)
end
