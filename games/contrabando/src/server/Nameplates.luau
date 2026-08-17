--!strict
--[[
	Nameplates.luau — quién es el que viene por la calle.

	EL PROBLEMA QUE RESUELVE es el más grave del multijugador de este juego: cuando
	dos repartidores se cruzan, hoy no hay forma de saber NADA del otro. Los dos son
	muñecos idénticos. Y en un juego donde puedes robar o que te roben, eso no es un
	detalle estético -- es la información sobre la que se decide si te acercas o te
	apartas, y sin ella el encuentro no significa nada.

	Lo que se enseña, y por qué exactamente eso:

	  · NOMBRE, para que haya alguien y no algo.
	  · NIVEL, porque es lo único que no se puede gastar. Dos jugadores con la misma
	    cartera pueden llevar uno diez minutos y otro diez horas; el dinero no
	    distingue veteranos y el nivel sí.
	  · QUÉ LLEVA ENCIMA, que es lo que decide si merece la pena perseguirle.

	El VEHÍCULO no hace falta ponerlo por escrito: se ve, y se ve mejor que un
	texto. Un tipo en furgoneta se reconoce a cien metros.

	Se monta en el SERVIDOR, como la carga y el vehículo, y por el mismo motivo:
	una etiqueta que sólo ve su dueño no informa a nadie.
]]

local Players = game:GetService("Players")

local Levels = require(game.ReplicatedStorage.Shared.Levels)
local Goods = require(game.ReplicatedStorage.Shared.Goods)
local PlayerState = require(script.Parent.PlayerState)

local Nameplates = {}

-- Hasta dónde se lee. Más allá de esto la ciudad ya no deja ver a nadie, y
-- carteles flotando entre edificios sólo serían ruido.
local ALCANCE = 220

-- El color del nivel: gris para los que empiezan, y sube hasta el oro. Es lo que
-- permite juzgar a alguien de un vistazo sin leer el número, que es lo único que
-- da tiempo a hacer mientras corres.
local function colorDeNivel(nivel: number): Color3
	if nivel >= 25 then
		return Color3.fromRGB(238, 202, 122)
	elseif nivel >= 12 then
		return Color3.fromRGB(190, 150, 235)
	elseif nivel >= 5 then
		return Color3.fromRGB(120, 190, 255)
	end
	return Color3.fromRGB(198, 200, 206)
end

function Nameplates.refrescar(player: Player)
	local character = player.Character
	local cabeza = character and character:FindFirstChild("Head") :: BasePart?
	if not cabeza then
		return
	end

	local estado = PlayerState.peek(player)
	local nivel = Levels.nivelDe(estado and estado.xp or 0)

	local placa = cabeza:FindFirstChild("Placa") :: BillboardGui?
	if not placa then
		placa = Instance.new("BillboardGui")
		placa.Name = "Placa"
		-- Pequeña a propósito. La primera versión medía 9 studs de ancho y a diez
		-- metros ocupaba media pantalla: un cartel que tapa el juego deja de ser
		-- información y pasa a ser un estorbo. Esto tiene que leerse de reojo, no
		-- competir con lo que hay detrás.
		placa.Size = UDim2.fromScale(4.5, 1.2)
		placa.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		-- NO AlwaysOnTop: si se viera a través de los edificios, esconderse dejaría
		-- de servir para nada -- y esconderse es media mecánica del juego.
		placa.AlwaysOnTop = false
		placa.MaxDistance = ALCANCE
		placa.Parent = cabeza

		local nombre = Instance.new("TextLabel")
		nombre.Name = "Nombre"
		nombre.Size = UDim2.fromScale(1, 0.55)
		nombre.BackgroundTransparency = 1
		nombre.TextScaled = true
		nombre.Font = Enum.Font.GothamBold
		nombre.TextStrokeTransparency = 0.3
		nombre.Parent = placa

		local carga = Instance.new("TextLabel")
		carga.Name = "Carga"
		carga.Position = UDim2.fromScale(0, 0.55)
		carga.Size = UDim2.fromScale(1, 0.45)
		carga.BackgroundTransparency = 1
		carga.TextScaled = true
		carga.Font = Enum.Font.GothamMedium
		carga.TextStrokeTransparency = 0.45
		carga.Parent = placa
	end

	local nombre = placa:FindFirstChild("Nombre") :: TextLabel?
	local carga = placa:FindFirstChild("Carga") :: TextLabel?
	if nombre then
		nombre.Text = string.format("%s  ·  nv %d", player.DisplayName, nivel)
		nombre.TextColor3 = colorDeNivel(nivel)
	end
	if carga then
		local cajas = estado and estado.cajas or {}
		if #cajas == 0 then
			-- De vacío no se anuncia nada. Que la línea desaparezca ES la
			-- información: quien no lleva carga no es un objetivo, y saberlo de un
			-- vistazo es lo que evita persecuciones que no llevan a ningún sitio.
			carga.Text = ""
		else
			-- Se anuncia la pieza MÁS VALIOSA, no el total: es el dato que decide si
			-- merece la pena perseguir a alguien.
			local mejor = cajas[1]
			for _, c in cajas do
				local a, defA = pcall(Goods.get, c.objeto or "")
				local b, defB = pcall(Goods.get, mejor.objeto or "")
				if a and b and defA and defB then
					local ra = defA.rareza
					local rb = defB.rareza
					if ra == "legendaria" or (ra == "sellada" and rb ~= "legendaria") then
						mejor = c
					end
				end
			end
			carga.Text = string.format("lleva %d  ·  %s", #cajas, Goods.etiqueta(mejor.objeto, mejor.rareza))
			carga.TextColor3 = Color3.fromRGB(238, 202, 122)
		end
	end
end

function Nameplates.start()
	local function seguir(player: Player)
		player.CharacterAdded:Connect(function()
			-- Un respiro: la cabeza no existe en el instante exacto del evento.
			task.delay(0.6, function()
				Nameplates.refrescar(player)
			end)
		end)
		if player.Character then
			Nameplates.refrescar(player)
		end
	end

	Players.PlayerAdded:Connect(seguir)
	-- Y los que ya estuvieran dentro al arrancar el servidor, que en Studio es
	-- SIEMPRE el caso: sin este barrido, el jugador de la sesión de Play se queda
	-- sin placa para siempre porque su PlayerAdded ya pasó.
	for _, player in Players:GetPlayers() do
		seguir(player)
	end

	-- Refresco periódico. La carga cambia por muchas vías -- recoger, entregar, que
	-- te roben, que te alcancen -- y encadenar una llamada en cada una es garantía
	-- de olvidarse de alguna. Dos veces por segundo es de sobra para un cartel.
	task.spawn(function()
		while true do
			task.wait(0.5)
			PlayerState.forEach(function(player)
				pcall(Nameplates.refrescar, player)
			end)
		end
	end)
end

return Nameplates
