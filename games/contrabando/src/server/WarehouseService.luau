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
	return estado.almacenCajas
end

function WarehouseService.disponibles(player: Player): number
	return actualizar(player)
end

function WarehouseService.reclamar(player: Player): number
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

	local cogidas = 0
	while estado.almacenCajas > 0 do
		local caja = CargoService.nuevaCaja()
		if not Cargo.cabe(estado.cajas, caja, Config.CAPACIDAD_A_PIE) then
			break
		end
		CargoService.recoger(player, caja)
		estado.almacenCajas -= 1
		cogidas += 1
	end

	PlayerState.sync(player)
	return cogidas
end

function WarehouseService.start()
	Remotes.event(Remotes.RECLAMAR).OnServerEvent:Connect(function(player)
		WarehouseService.reclamar(player)
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
