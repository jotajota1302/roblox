--!strict
--[[
	WarehouseService.luau — el almacén: produce mientras no estás y te da carga al volver.

	EL ALMACÉN NO ES ASALTABLE. NUNCA. Sólo está en juego lo que llevas encima. Sin
	esa garantía la gente abandona tras el primer mal día, y ninguna cifra de
	retención sobrevive a eso. Aquí no hay ni un remote que permita tocar el almacén
	de otro: ni siquiera existe la posibilidad de expresarlo.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Cargo = require(game.ReplicatedStorage.Shared.Cargo)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Warehouse = require(game.ReplicatedStorage.Shared.Warehouse)
local CargoService = require(script.Parent.CargoService)
local PlayerState = require(script.Parent.PlayerState)

local DISTANCIA_ALMACEN = 45

local WarehouseService = {}
local almacen: BasePart? = nil

function WarehouseService.registrarAlmacen(part: BasePart)
	almacen = part
end

-- La producción se calcula al consultarla, no con un temporizador: una resta al
-- entrar cubre igual de bien diez minutos que dos semanas.
local function actualizar(player: Player): number
	local estado = PlayerState.get(player)
	local ahora = os.time()
	-- Warehouse.avanzar() sólo consume los periodos que de verdad dieron caja: si
	-- aquí se pusiera almacenUltimaVisita = ahora sin más (como hacía antes), el
	-- bucle de refresco de 5 s con un ritmo de 30 tiraría el resto en cada muestra
	-- y el almacén no produciría NUNCA con el jugador conectado.
	estado.almacenCajas, estado.almacenUltimaVisita = Warehouse.avanzar(
		estado.almacenCajas,
		estado.almacenUltimaVisita,
		ahora,
		Config.ALMACEN_RITMO,
		Config.ALMACEN_TOPE
	)

	-- La lista de piezas se pone al día con el contador. La rareza se sortea AL
	-- PRODUCIR y no al recoger, que es lo que convierte el almacén en una decisión:
	-- si se tirara al recoger, mirar la pila no diría nada y elegir sería imposible.
	-- Lo que sale ya no cambia -- una urna que aparece sigue siendo una urna aunque
	-- el jugador tarde una hora en volver a por ella.
	if estado.almacen == nil then
		estado.almacen = {}
	end
	while #estado.almacen < estado.almacenCajas do
		table.insert(estado.almacen, CargoService.nuevaCaja())
	end
	-- Y si el contador bajó por cualquier vía, la lista le sigue: dos fuentes de
	-- verdad sobre lo mismo acaban divergiendo, y la que divergiera aquí regalaría
	-- mercancía o la haría desaparecer.
	while #estado.almacen > estado.almacenCajas do
		table.remove(estado.almacen)
	end

	return estado.almacenCajas
end

function WarehouseService.disponibles(player: Player): number
	return actualizar(player)
end

-- `indice` es la pieza CONCRETA que se quiere (la que el jugador tiene delante).
-- Sin él se coge lo que quepa por orden, que es lo que hace el botón del HUD.
--
-- El índice viene del cliente, así que se valida como todo lo que viene de fuera:
-- que sea un número, que esté dentro del rango y que la pieza exista. Sin eso, un
-- índice inventado sacaría del almacén algo que no está.
function WarehouseService.reclamar(player: Player, indice: number?): number
	local estado = PlayerState.get(player)
	actualizar(player)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not almacen then
		return 0
	end
	if (root.Position - almacen.Position).Magnitude > DISTANCIA_ALMACEN then
		return 0
	end

	local capacidad = Cargo.capacidad(estado.vehiculo)

	if typeof(indice) == "number" then
		local i = math.floor(indice)
		local caja = estado.almacen[i]
		if caja == nil then
			return 0
		end
		-- La capacidad la manda el vehículo, no la constante de ir a pie: con
		-- aquélla el almacén dejaba de llenar en 3 aunque la furgoneta admitiera 10,
		-- y la mejora recién pagada no hacía nada visible.
		if not Cargo.cabe(estado.cajas, caja, capacidad) then
			return 0
		end
		table.remove(estado.almacen, i)
		estado.almacenCajas -= 1
		CargoService.recoger(player, caja)
		PlayerState.sync(player)
		return 1
	end

	local cogidas = 0
	while estado.almacenCajas > 0 and #estado.almacen > 0 do
		local caja = estado.almacen[1]
		if not Cargo.cabe(estado.cajas, caja, capacidad) then
			break
		end
		table.remove(estado.almacen, 1)
		estado.almacenCajas -= 1
		CargoService.recoger(player, caja)
		cogidas += 1
	end

	PlayerState.sync(player)
	return cogidas
end

function WarehouseService.start()
	Remotes.event(Remotes.RECLAMAR).OnServerEvent:Connect(function(player, indice)
		-- El índice se pasa tal cual y se valida DENTRO de reclamar, que es donde
		-- están los datos con los que se puede juzgar. Lo único que se hace aquí es
		-- no dejar pasar nada que no sea un número: cualquier otra cosa se trata
		-- como "coge lo que quepa", que es el comportamiento del botón.
		WarehouseService.reclamar(player, if typeof(indice) == "number" then indice else nil)
	end)

	-- Sincroniza cada 5 s para que el contador del HUD suba solo mientras el
	-- jugador mira: ver el almacén llenarse es parte del motivo para volver.
	task.spawn(function()
		while true do
			task.wait(5)
			PlayerState.forEach(function(player)
				actualizar(player)
				PlayerState.sync(player)
			end)
		end
	end)
end

return WarehouseService
