--!nocheck
--[[
	observar.luau — la caja negra de una partida.

	POR QUE EXISTE. Toda esta sesion se diagnostico midiendo numeros y deduciendo lo
	visual, y JJ lo resumio en una linea: *"nada, no esta bien"*. Tenia razon en el
	fondo -- el radar llevaba roto todo el rato (tu punto caia en Y=1,09, fuera del
	panel recortado) y ninguna de las 875 pruebas ni de las 71 sondas del mundo lo
	dice, porque ninguna mira la PANTALLA.

	Asi que en vez de simular yo lo que creo que hace un jugador, esto anota lo que
	pasa mientras juega el de verdad: una linea por segundo con donde esta, a que
	velocidad va, que le esta pasando y --lo que faltaba-- QUE VE, leido del propio
	PlayerGui.

	COMO SE USA, desde el MCP con Studio EN PLAY (datamodel Server):
	  1. pegar este fichero en execute_luau  ->  arranca y devuelve "grabando"
	  2. JJ juega un ciclo completo (elegir ruta, ir, entregar, volver)
	  3. volver a pegarlo con MODO = "leer"   ->  devuelve el registro entero

	El registro vive en un StringValue del workspace y no en una variable, porque
	cada llamada de execute_luau corre en su propio entorno: una tabla local no
	sobrevive de una llamada a la siguiente, y el datamodel si.
]]

local MODO = "grabar" -- "grabar" | "leer" | "parar"

local Players = game:GetService("Players")

local CAJA = "CajaNegra"

local function caja(): StringValue
	local v = workspace:FindFirstChild(CAJA)
	if v == nil then
		v = Instance.new("StringValue")
		v.Name = CAJA
		v.Parent = workspace
	end
	return v
end

if MODO == "leer" then
	local v = workspace:FindFirstChild(CAJA)
	return if v then v.Value else "no hay caja negra: arrancala con MODO grabar"
end

if MODO == "parar" then
	local v = workspace:FindFirstChild(CAJA)
	if v then
		v:SetAttribute("grabando", false)
	end
	return "parada"
end

local v = caja()
v.Value = ""
v:SetAttribute("grabando", true)
v:SetAttribute("arranque", os.clock())

-- Lo que se anota de la INTERFAZ. Es la mitad que faltaba: el estado del juego ya
-- se puede leer del mundo, pero "que hay encendido en pantalla" solo se sabe
-- mirando el PlayerGui -- y es donde estaban los tres fallos de hoy.
local function pantalla(player: Player): string
	local pg = player:FindFirstChild("PlayerGui")
	if pg == nil then
		return "sin gui"
	end
	local trozos = {}

	local mini = pg:FindFirstChild("Minimapa")
	local panel = mini and mini:FindFirstChild("Panel")
	if panel then
		local yo = panel:FindFirstChild("Yo")
		if yo then
			local p = yo.Position
			-- FUERA si su fraccion se sale de [0,1]: el panel recorta a sus hijos, asi
			-- que salirse es desaparecer. Esto es exactamente el fallo del radar.
			local dentro = p.X.Scale >= 0 and p.X.Scale <= 1 and p.Y.Scale >= 0 and p.Y.Scale <= 1
			table.insert(trozos, string.format("yo=%.2f,%.2f%s", p.X.Scale, p.Y.Scale, if dentro then "" else " FUERA"))
		end
		local marcas = 0
		for _, d in panel:GetChildren() do
			if d:IsA("GuiObject") and d.Visible and d.Name ~= "Plano" then
				marcas += 1
			end
		end
		table.insert(trozos, "marcas=" .. marcas)
	end

	local hud = pg:FindFirstChild("ContrabandoHud")
	if hud then
		local halo = hud:FindFirstChild("HaloPeligro")
		if halo and halo.Visible then
			table.insert(trozos, "HALO")
		end
		local aviso = hud:FindFirstChild("Aviso")
		if aviso and aviso.Text ~= "" then
			table.insert(trozos, "aviso=«" .. aviso.Text .. "»")
		end
	end

	local cam = workspace.CurrentCamera
	if cam then
		table.insert(trozos, string.format("fov=%.1f", cam.FieldOfView))
	end
	return table.concat(trozos, " ")
end

-- Quien te ve AHORA MISMO, calculado igual que lo calcula el servidor. Es el dato
-- que el juego ya sabe y no cuenta -- *"no veo quien me ve"*.
local function quienTeVe(root: BasePart): string
	local patrullas = workspace:FindFirstChild("Patrullas")
	if patrullas == nil then
		return "0 ladrones"
	end
	local cerca, viendo = 0, 0
	for _, agente in patrullas:GetChildren() do
		local suya = agente:FindFirstChild("HumanoidRootPart")
		if suya == nil then
			continue
		end
		local d = (suya.Position - root.Position).Magnitude
		if d > 320 then
			continue
		end
		cerca += 1
		-- Cono en planta + pared de por medio, las dos condiciones del servidor.
		local hacia = root.Position - suya.Position
		local plano = Vector3.new(hacia.X, 0, hacia.Z)
		local mira = suya.CFrame.LookVector
		local mirap = Vector3.new(mira.X, 0, mira.Z)
		if plano.Magnitude > 1 and mirap.Magnitude > 0.01 then
			local cos = plano.Unit:Dot(mirap.Unit)
			if cos >= math.cos(math.rad(60)) and plano.Magnitude <= 120 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { agente, root.Parent }
				local golpe = workspace:Raycast(suya.Position, root.Position - suya.Position, params)
				if golpe == nil then
					viendo += 1
				end
			end
		end
	end
	return string.format("%d cerca / %d TE VEN", cerca, viendo)
end

task.spawn(function()
	local v = caja()
	local t0 = os.clock()
	local lineas = {}
	local antes: Vector3? = nil
	while v:GetAttribute("grabando") == true and os.clock() - t0 < 900 do
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if root and h then
				local vel = 0
				if antes then
					local d = root.Position - antes
					vel = math.sqrt(d.X * d.X + d.Z * d.Z)
				end
				antes = root.Position
				table.insert(
					lineas,
					string.format(
						"%5.1fs  (%5d,%5d)  real %4.1f / tope %4.1f  |  %s  |  %s",
						os.clock() - t0,
						root.Position.X,
						root.Position.Z,
						vel,
						h.WalkSpeed,
						quienTeVe(root),
						pantalla(player)
					)
				)
			end
		end
		if #lineas > 0 and #lineas % 5 == 0 then
			v.Value = table.concat(lineas, "\n")
		end
		task.wait(1)
	end
	v.Value = table.concat(lineas, "\n")
	v:SetAttribute("grabando", false)
end)

return "grabando. Que JJ juegue un ciclo completo; luego leer con MODO = 'leer'."
