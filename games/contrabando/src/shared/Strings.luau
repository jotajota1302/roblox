--!strict
--[[
	Strings.luau — TODO el texto que lee el jugador, y el único sitio donde se escribe.

	POR QUÉ EXISTE. El juego se tradujo al inglés a mano el 18/08 recorriendo 21
	ficheros, y esa misma noche JJ vio castellano en pantalla. Se parcheó. Al hacer
	el inventario aparecieron NUEVE textos más en castellano que el repaso no cazó
	("Cargar", "Oficina", "%d huecos", "Te vienen detras", "GUARIDA"...). Un repaso
	a mano no puede cerrar eso: mientras el texto viva repartido, la próxima línea
	que se escriba puede volver a salir en el idioma equivocado y nadie lo sabrá
	hasta jugar. La cura no es otro repaso, es que sólo haya un fichero.

	Y DE PASO, TRADUCIR. Roblox traduce solo --tabla en la nube + traducción
	automática, ~15 idiomas, gratis-- pero casa CADENAS ENTERAS. De nuestros ~130
	textos, dos tercios se construían pegando trozos ("You take out " .. nombre) o
	con string.format, y ninguno de ésos habría casado nunca. Con plantillas y
	parámetros con nombre, cada texto es una fila estable de la tabla.

	CÓMO SE USA:

		Strings.get("CARGO_EMPTY")
		Strings.get("CARGO_PAID", { monedas = 250, items = 3, ruta = Strings.ref("ROUTE_verde") })

	Los parámetros que son OTRO TEXTO viajan como referencia (Strings.ref), no como
	cadena: una cadena llegaría ya en inglés y se quedaría en inglés dentro de una
	frase alemana. Los números se sustituyen tal cual, que para eso no se traducen.

	EL SERVIDOR MANDA CLAVES, NO FRASES. Remotes.AVISO lleva (clave, args, color).
	No es sólo por traducir: hoy el servidor decidía en qué idioma hablar, y el
	idioma es del jugador -- en una partida con dos personas de países distintos no
	hay un idioma correcto que el servidor pueda elegir.

	EXCEPCIÓN, y es importante: el texto que el SERVIDOR planta en el mundo
	(rótulos de edificio, ProximityPrompt) lo ven todos los jugadores a la vez, así
	que no se puede traducir por persona desde aquí. Ésos se dejan en inglés en la
	instancia y los traduce el motor al dibujarlos (AutoLocalize casa la cadena
	contra la tabla de la nube). Por eso tienen que ser cadenas FIJAS, sin
	parámetros: "Buy" + el nombre del vehículo en ObjectText, nunca "Buy Car".

	ESTO FUNCIONA HOY SIN CONFIGURAR NADA. Sin traductor enchufado se devuelve el
	inglés de aquí abajo. El día que se suba la tabla al portal aparecen los
	idiomas sin cambiar una línea de código.
]]

local Strings = {}

-- Un parámetro que es a su vez un texto traducible.
export type Ref = { __clave: string, __args: { [string]: any }? }

-- La nube, si la hay. La enchufa el cliente (Main.client) porque
-- LocalizationService sólo tiene traductor de jugador ahí; este módulo se queda
-- PURO a propósito, para poder probarlo entero sin Studio y para que el servidor
-- pueda requerirlo sin arrastrar servicios.
local traductor: ((clave: string) -> string?)? = nil

function Strings.usarTraductor(fn: ((clave: string) -> string?)?)
	traductor = fn
end

--[[ ==========================================================================
     LOS TEXTOS. En inglés, que es el idioma de origen del juego.

     Las claves NO se traducen ni se tocan: son las filas de la tabla de la nube.
     Un {parametro} entre llaves se rellena en tiempo de ejecución.
     ========================================================================== ]]
local TEXTOS: { [string]: string } = {
	-- ---- Panel de estado -------------------------------------------------
	HUD_MONEY = "Money",
	HUD_CARGO = "Cargo",
	HUD_WAREHOUSE = "Warehouse",
	HUD_HEAT = "Heat",
	HUD_NEXT = "Next",
	HUD_CONTACTS = "Contacts",
	HUD_GOAL = "Goal",

	-- ---- La línea de misión: qué toca hacer AHORA -------------------------
	MISSION_TAKE_HOME = "Take the cargo to your warehouse",
	MISSION_PICK_RETURN = "Pick up the return cargo",
	MISSION_DELIVER_IN = "Deliver in {ruta}",
	-- Ya no se elige en la salida: desde el 19/08 el selector sale al coger la carga.
	MISSION_PICK_ROUTE = "Pick where you are taking it",
	MISSION_BACK_TO_VEHICLE = "Go back for your loaded vehicle",
	MISSION_BUY_RIDE = "Buy the {vehiculo} at the workshop",
	MISSION_LOAD_GOODS = "Load goods at the warehouse",
	MISSION_PRODUCING = "The warehouse is producing: wait",

	-- ---- Los controles en pantalla ---------------------------------------
	ACTION_GET_ON = "get on the vehicle",
	ACTION_GET_OFF = "get off the vehicle",
	ACTION_DELIVER = "deliver the cargo",
	ACTION_INTERACT = "pick up, buy and use",

	-- El rotulo del portal de una vivienda de entrega. Corto a proposito: va sobre
	-- la puerta, se lee de paso y compite con las ventanas encendidas.
	DELIVERY_DOOR = "DROP-OFF",

	-- LO QUE HACE CADA RECOGIBLE, escrito encima de el.
	--
	-- La silueta sola no basta: a la distancia a la que hay que DECIDIR si te
	-- desvias, un rayo y una flecha son cuatro pixeles cada uno. Una palabra corta se
	-- lee antes que una forma pequena, y son tres palabras que se aprenden una vez.
	PICKUP_BOOST = "BOOST",
	PICKUP_JUMP = "JUMP",
	PICKUP_SHIELD = "SHIELD",

	-- Los dos lados del escudo. Al que roba tambien se le dice, o lee "no me he
	-- llevado nada" como que el juego esta roto.
	SHIELD_HELD = "Your shield held. They got nothing.",
	SHIELD_BLOCKED = "Shielded. Nothing to take.",

	-- ---- Brújula ---------------------------------------------------------
	COMPASS_HERE = "here",
	COMPASS_METERS = "{metros} m",
	COMPASS_BACK_HOME = "Back to the warehouse",
	COMPASS_RETURN_CARGO = "Return cargo there",
	COMPASS_DROP = "{ruta} drop",
	COMPASS_PICK_ROUTE = "Pick where you are taking it",
	COMPASS_YOUR_WAREHOUSE = "Your warehouse",

	-- ---- Selector de ruta -------------------------------------------------
	PICKER_TITLE = "Which way out?",
	PICKER_NOT_NOW = "Not now",
	PICKER_DETAIL = "{metros}m  ·  {fichadas} hotspots  ·  {guaridas} dens",

	-- ---- Las rutas. Cuatro etiquetas cortas, una por zona ------------------
	ROUTE_verde = "GREEN",
	ROUTE_ambar = "AMBER",
	ROUTE_roja = "RED",
	ROUTE_REQ_LEVEL = "Level {nivel}",
	ROUTE_REQ_LEVEL_RIDE = "Level {nivel} and a road vehicle",
	-- El primer reparto viene ya elegido: al que acaba de entrar no se le pide que
	-- decida antes de haber cobrado nunca. Se le dice a dónde va y cuánto paga.
	ROUTE_FIRST_SET = "First run: {ruta}  ·  follow the lights",

	-- ---- Los hitos --------------------------------------------------------
	GOAL_primera = "Deliver your first package",
	GOAL_tres = "Deliver 3 packages",
	GOAL_ambar = "Reach level 3 to unlock the {ruta} route",
	GOAL_ocho = "Deliver 8 packages",
	GOAL_roja = "Level 8 and a road vehicle for the {ruta} route",
	GOAL_PROGRESS_DELIVERIES = "{hechas} of {total} deliveries",
	GOAL_PROGRESS_LEVEL = "level {actual} of {total}",
	GOAL_DONE_REWARD = "{hito}  (+{monedas})",

	-- ---- Vehículos --------------------------------------------------------
	RIDE_a_pie = "On foot",
	RIDE_monopatin = "Skateboard",
	RIDE_patinete = "Scooter",
	RIDE_patinete_electrico = "E-Scooter",
	RIDE_bicicleta = "Bike",
	RIDE_moto = "Motorbike",
	RIDE_coche = "Car",
	RIDE_furgoneta = "Van",

	-- ---- Tamaños de bulto -------------------------------------------------
	SIZE_pequeno = "small",
	SIZE_mediano = "medium",
	SIZE_grande = "large",
	SIZE_enorme = "huge",

	-- ---- Mercancías -------------------------------------------------------
	GOODS_sobre = "Sealed envelope",
	GOODS_joyero = "Jewel box",
	GOODS_frasco = "Vial",
	GOODS_libro = "Old book",
	GOODS_maletin = "Briefcase",
	GOODS_cajon = "Fruit crate",
	GOODS_maceta = "Flower pot",
	GOODS_urna = "Urn",
	GOODS_television = "TV set",
	GOODS_baul = "Trunk",
	GOODS_barril = "Barrel",
	GOODS_nevera = "Fridge",
	GOODS_sofa = "Sofa",
	GOODS_piano = "Piano",
	GOODS_estatua = "Statue",
	-- Lo que se enseña cuando una pieza no tiene objeto conocido. Era "Bulto":
	-- uno de los nueve castellanos que sobrevivieron a la traducción a mano.
	GOODS_UNKNOWN = "Package",
	-- Qué ES la pieza según su rareza: lo que se lee encima de la caja.
	RARITY_comun = "Crate",
	RARITY_marcada = "Briefcase",
	RARITY_sellada = "Sealed case",
	RARITY_legendaria = "Urn",
	GOODS_LABEL = "{nombre}  x{multiplicador}",

	-- ---- Habilidades ------------------------------------------------------
	SKILL_camuflaje = "Camouflage",
	SKILL_camuflaje_DESC = "Hotspots spot you from closer",
	SKILL_aguante = "Grit",
	SKILL_aguante_DESC = "You lose less cargo when they catch you",
	SKILL_vista = "Eyes",
	SKILL_vista_DESC = "See dens and thieves from further away",
	SKILL_senuelo = "Decoy",
	SKILL_senuelo_DESC = "Drop a lure: thieves go for it, not you",

	-- ---- Menú lateral -----------------------------------------------------
	MENU_SKILLS = "Skills",
	MENU_WAREHOUSE = "Warehouse",
	MENU_WORKSHOP = "Workshop",
	MENU_DECOY = "Decoy",
	MENU_DECOY_COOLDOWN = "Decoy {segundos}s",
	MENU_CLOSE = "X",
	MENU_SKILLS_TITLE = "Skills  ·  {contactos} contacts",
	MENU_SKILL_LEVEL = "{descripcion}  ·  level {peldano} of {total}",
	MENU_SKILL_MAXED = "{descripcion}  ·  maxed",
	MENU_DONE = "Done",
	MENU_WAREHOUSE_TITLE = "Warehouse, level {nivel}",
	MENU_WAREHOUSE_SUB = "holds {tope}  ·  produces every {ritmo}s",
	MENU_WAREHOUSE_PLAIN = "your warehouse",
	MENU_MAXED = "Maxed",
	MENU_MAXED_SUB = "nothing left to upgrade",
	MENU_LEVEL = "Level {nivel}",
	MENU_NOTHING_TO_BUY = "Nothing to buy",
	MENU_NOTHING_TO_BUY_SUB = "you own them all",
	MENU_RIDE_DETAIL = "carries {capacidad}  ·  {velocidad} studs/s",
	MENU_RIDE_LOCKED = "{detalle}  ·  needs level {nivel}",
	MENU_LOCKED = "Locked",
	MENU_GARAGE_TITLE = "Take out of garage",
	MENU_GARAGE_SUB = "still at the workshop: which one you take is the run's decision",

	-- ---- Taller y muelle, en el mundo -------------------------------------
	GATE_PICK_ROUTE = "LOAD UP TO LEAVE",
	-- Los dos motivos por los que la valla se cierra, cada uno con su frase: un texto
	-- unico mandaba a elegir ruta al que salia de vacio, que es lo que no le falta.
	GATE_NO_CARGO = "Nothing to deliver: load up at the warehouse",
	GATE_NO_ROUTE = "You cannot leave with cargo and no route",
	GARAGE_CARD = "{vehiculo}{fuera}\n{huecos} slots  ·  {terreno}",
	GARAGE_OUT = "  (out)",
	GARAGE_ROAD_ONLY = "road only",
	GARAGE_ANYWHERE = "goes anywhere",
	GARAGE_STORE = "Store",
	GARAGE_TAKE_OUT = "Take out",
	STOCK_LOAD = "Load",
	STOCK_LOAD_RETURN = "Load return cargo",
	OFFICE_UPGRADE = "Upgrade warehouse  ·  {coste}",
	OFFICE_UPGRADE_SUB = "Holds {tope}  ·  every {ritmo}s",
	OFFICE_MAXED = "Warehouse maxed",
	OFFICE_NAME = "Office",

	-- ---- Placas sobre los personajes --------------------------------------
	NAMEPLATE_NAME = "{jugador}  ·  lv {nivel}",
	NAMEPLATE_CARGO = "carrying {cuantas}  ·  {mejor}",
	-- Lo que se lee sobre la carga que llevas a la espalda: la pieza más valiosa y
	-- cuántas más van detrás.
	BACKPACK_MORE = "{pieza}  +{cuantas}",
	THIEF_PLATE = "THIEF",

	-- ---- Rótulos que planta el servidor -----------------------------------
	-- Cadenas FIJAS a propósito: las traduce el motor al dibujarlas, y para eso
	-- tienen que casar enteras contra la tabla. Ver la nota de la cabecera.
	SIGN_WAREHOUSE = "YOUR WAREHOUSE",
	SIGN_VEHICLES = "VEHICLES",
	SIGN_DEN = "DEN",
	SIGN_POLICE = "POLICE",
	SIGN_OFFICE = "OFFICE",
	-- La salida ya no elige nada: desde el 19/08 la ruta se escoge al coger el
	-- paquete. El cartel se queda diciendo sólo qué es este sitio.
	-- Bajo el arco. Dice lo que separa, no lo que hay que hacer: de aquí para dentro es
	-- tu polígono -- almacén y taller-- y de aquí para fuera, la ciudad.
	SIGN_EXIT = "CITY  ·  keep your cargo safe",
	SIGN_PARKED = "you parked here",
	PROMPT_BUY = "Buy",
	PROMPT_BUY_VEHICLE = "Buy vehicle",
	PROMPT_DROP_CARGO = "Drop cargo here",
	-- El locker de entrega. "Deliver" y no "Drop off" porque el boton del aviso es
	-- estrecho y en aleman o en frances lo largo se corta -- y lo que no se puede
	-- leer no es una accion, es un adorno.
	PROMPT_DELIVER = "Deliver",
	PROMPT_LOCKER = "Parcel locker",
	PROMPT_UPGRADE = "Upgrade warehouse",
	PROMPT_DEALERSHIP = "Dealership",
	-- El escaparate: nombre, precio y nivel del vehículo. Se monta en el SERVIDOR
	-- y lo ven todos igual, así que sale siempre en inglés -- ver la nota de la
	-- cabecera sobre el texto del mundo.
	SHOWROOM_LABEL = "{vehiculo}  ·  {precio}{nivel}",
	SHOWROOM_LEVEL = "  ·  level {nivel}",
	ROUTE_SIGN = "{ruta}  {paga}",

	-- ---- La red de seguridad -----------------------------------------------
	-- Se ve cuando el guardián de Avatar te devuelve al mapa. Dice que ha pasado
	-- algo y no lo disimula: si un día esto sale a menudo, quiero que se note.
	RESCUE_BACK = "Out of the world ({motivo}) at {x},{y},{z}, speed {velocidad}. Back on track.",

	-- ---- Entregas y cobros -------------------------------------------------
	CARGO_NEED_BIGGER = "You need a bigger vehicle: that one is {tamano}",
	CARGO_LOADED_RETURN = "You load {cuantas} items to take back",
	CARGO_PAID = "+{monedas} for {items} items on {ruta}",
	-- El regreso instantáneo tras entregar. Sustituye a CARGO_LOADED_RETURN, que
	-- anunciaba la carga del viaje de vuelta: ya no hay viaje de vuelta.
	CARGO_WARPED_HOME = "Delivered. Back at the warehouse.",
	-- El cartelon del centro de la pantalla al entregar. Una palabra y la cifra: es
	-- lo que se lee de un vistazo mientras el mundo se desvanece a tu alrededor.
	DELIVERED_BANNER = "DELIVERED",
	DELIVERED_AMOUNT = "+{monedas}",
	CARGO_LEVEL_UP = "Level {nivel}!",
	CARGO_EMPTY = "You are not carrying anything",
	CARGO_NO_ROUTE_FAR = "You left with no route: go back to the warehouse exit",
	CARGO_NOT_THERE_YET = "Not there yet: follow the {ruta} beacon",
	CARGO_NO_ROUTE = "You left with no route, so this cargo is worthless here",
	CARGO_WRONG_DROP = "This is the {aqui} drop and yours is {tuya}",
	CARGO_LOST_ON_RESPAWN = "You lost what you were carrying when you respawned",

	-- ---- Contactos y señuelo ----------------------------------------------
	CONTACT_LEARNED = "Learned: {habilidad}",
	DECOY_NOT_OWNED = "You do not have the decoy yet",
	DECOY_COOLDOWN = "Decoy ready in {segundos}s",
	DECOY_DROPPED = "Decoy dropped",

	-- ---- Vehículos: comprar, sacar, aparcar --------------------------------
	RIDE_PRESS_TO_MOUNT = "Press V to get on or off",
	RIDE_TAKE_OUT = "You take out {vehiculo}",
	RIDE_BOUGHT_OUT = "{vehiculo}: you carry {huecos} slots and bigger items",
	RIDE_BOUGHT_PARKED = "{vehiculo} parked in your garage: take it out once unloaded",
	RIDE_NONE_YET = "You do not have a vehicle yet",
	RIDE_PARKED_WITH_CARGO = "You park it here with {cuantas} items inside",
	RIDE_PARKED = "You park it here",
	RIDE_TOO_FAR = "Your vehicle is {metros}m away",
	RIDE_CARGO_BACK = "You pick your {cuantas} items back up",
	RIDE_SENT_HOME = "Your vehicle went back to the workshop",
	RIDE_BACK_ON_WITH_CARGO = "Back on it, with your {cuantas} items",
	RIDE_BACK_ON = "Back on it",
	RIDE_GET_OFF_WITH_CARGO = "You get off: {cuantas} items stay in the vehicle",
	RIDE_GET_OFF_NO_ROAD = "You get off: no driving here",

	-- ---- Calor y persecución -----------------------------------------------
	HEAT_SAFE = "Safe at your warehouse",
	HEAT_SPOTTED = "A watched corner clocked you  ·  heat {nivel}/{maximo}",
	HEAT_CLEAR = "Nobody is chasing you",
	HEAT_INHERITED = "You take their cargo and their heat  ·  {nivel}/{maximo}",
	CHASE_BEHIND_YOU = "They are coming for you",
	CHASE_LOST_THEM = "You lost them",
	CHASE_ON_YOU = "Someone picked up your trail",
	ROBBED = "Robbed! They take {cuantas} items",
	ROBBED_EMPTY = "Robbed, but you were empty",
	ROBBED_BY_PLAYER = "{jugador} robbed {cuantas} items from you",

	-- ---- Almacén ------------------------------------------------------------
	WAREHOUSE_DROPPED = "You drop {cuantas} items at the warehouse",
	WAREHOUSE_UPGRADED = "Warehouse level {nivel}: holds {tope}, produces every {ritmo}s",
	WAREHOUSE_AWAY_FULL = "While you were away: {cuantas} items. The warehouse is FULL and stopped producing",
	WAREHOUSE_AWAY = "While you were away: {cuantas} items waiting",

	-- ---- Los "no puedes", uno por motivo -----------------------------------
	-- La clave lleva el motivo que devuelve el servidor, para que la tabla de
	-- traducciones y la de reglas se lean en paralelo.
	DENY_sin_dinero = "Not enough money",
	DENY_ya_lo_tienes = "You already own that vehicle",
	DENY_ya_tienes_uno_mejor = "Yours is better",
	DENY_no_esta_a_la_venta = "That is not for sale",
	DENY_vehiculo_desconocido = "That vehicle does not exist",
	DENY_lejos_taller = "You have to be at a workshop",
	DENY_con_carga = "Unload before switching vehicles",
	DENY_no_cabe_la_carga = "Your cargo does not fit in there: unload first",
	DENY_carga_demasiado_grande = "What you carry does not fit in that vehicle",
	DENY_no_es_tuyo = "That vehicle is not yours",
	DENY_ya_lo_llevas = "You are already using it",
	DENY_nivel_insuficiente = "Your level is too low for that vehicle",
	DENY_BUY = "You cannot buy that",
	DENY_TAKE_OUT = "You cannot take that out",
	DENY_necesitas_motor = "That route needs a road vehicle",
	DENY_ruta_desconocida = "That route does not exist",
	DENY_ROUTE = "You cannot leave that way",
	DENY_LEVEL_TOO_LOW = "Level too low: {requisito}",
	DENY_en_ruta = "You are already on a run: deliver first",
	DENY_sin_carga_ruta = "Pick something up at the warehouse first",
	DENY_fuera_del_recinto = "Routes are picked at your yard, not mid-run",
	DENY_lejos_almacen = "You have to be at the warehouse",
	DENY_al_maximo = "Your warehouse is already maxed",
	DENY_lejos_devolver = "Get closer to the warehouse to drop it",
	DENY_ya_en_ruta = "You already picked a route: this gets delivered at its drop",
	DENY_DROP = "You cannot drop cargo here",
	DENY_UPGRADE = "You cannot upgrade that",
}

Strings.TEXTOS = TEXTOS

-- Marca un parámetro como "esto es otro texto, tradúcelo también".
--
-- Lleva sus propios parámetros porque un texto anidado puede tener huecos: el
-- hito de la ámbar dice "Reach level 3 to unlock the {ruta} route", y meterlo
-- dentro del aviso de recompensa sin sus argumentos enseñaría "{ruta}" en
-- pantalla.
function Strings.ref(clave: string, args: { [string]: any }?): Ref
	return { __clave = clave, __args = args }
end

-- La plantilla en el idioma del jugador, o el inglés de arriba si no hay nube.
--
-- La clave desconocida se devuelve TAL CUAL en vez de vacío: un hueco en blanco
-- en pantalla no se ve y una clave a la vista sí. Las erratas se cazan jugando.
function Strings.plantilla(clave: string): string
	if traductor ~= nil then
		local ok, texto = pcall(traductor :: any, clave)
		if ok and type(texto) == "string" and texto ~= "" then
			return texto
		end
	end
	return TEXTOS[clave] or clave
end

-- Rellena los {parametros}. Puro: no mira la nube, así que se prueba solo.
--
-- Un parámetro que falta se DEJA VISIBLE ("{monedas}") por lo mismo que la clave
-- desconocida: el hueco silencioso pasa la revisión y el visible no.
function Strings.format(plantilla: string, args: { [string]: any }?): string
	if args == nil then
		return plantilla
	end
	local salida = string.gsub(plantilla, "{([%w_]+)}", function(nombre)
		local valor = args[nombre]
		if valor == nil then
			-- Devolver nil deja la coincidencia intacta: "{monedas}" se queda.
			return nil
		end
		if type(valor) == "table" and valor.__clave ~= nil then
			return Strings.get(valor.__clave, valor.__args)
		end
		return tostring(valor)
	end)
	return salida
end

-- Desmonta una referencia en (clave, argumentos), que es como viaja un aviso por
-- el remote. Existe para que los servicios no tengan que hurgar en los campos de
-- la referencia para mandarla.
function Strings.partes(ref: Ref): (string, { [string]: any }?)
	return ref.__clave, ref.__args
end

function Strings.get(clave: string, args: { [string]: any }?): string
	return Strings.format(Strings.plantilla(clave), args)
end

return Strings
