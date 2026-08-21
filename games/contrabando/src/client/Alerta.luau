--!strict
--[[
	Alerta.luau — lo que se ve cuando una camara te esta mirando.

	POR QUE EXISTE. *"Los efectos de cuando te pilla una camara tenemos que
	mejorarlos mucho"* (JJ). Y antes de esto no habia efecto NINGUNO: te fichaban y
	lo unico que ocurria era una linea de texto en una esquina y un numero que
	subia. O sea una consecuencia sin causa visible -- que es, palabra por palabra,
	la queja mas repetida de este proyecto: *"me detectan y no hay nadie"*.

	Lo que hace falta no es mas texto, es contestar tres preguntas a la vez y sin
	leer: QUE pasa (te ven), QUIEN (esa camara de ahi) y DESDE DONDE (por ese rayo).

	  · EL RAYO, del ojo de la camara a tu pecho. Es la pieza clave: convierte "hay
	    un numero subiendo" en "ese aparato de la esquina me esta apuntando", y de
	    paso ensena la linea que hay que romper -- si el rayo atraviesa una pared,
	    es que estas mal colocado.
	  · EL MARCO ROJO, que late en el borde de la pantalla. Ocupa la periferia y no
	    el centro a proposito: tienes que poder seguir conduciendo.
	  · EL CONO EN ROJO. El mismo cono naranja que llevabas viendo toda la partida,
	    ahora encendido -- asi se aprende de una vez que esa mancha del suelo era
	    esto.

	Y CUANDO NO TE VEN, LA CIUDAD SIGUE VIVA: las camaras cercanas barren su cono
	con una franja mas clara y su piloto late. Un cono quieto se lee como pintura
	del suelo; uno que barre se lee como algo que esta MIRANDO, y esa diferencia es
	la que hace que el jugador lo esquive en vez de ignorarlo.

	TODO ES LOCAL. Ni el rayo ni el barrido existen para los demas: el color de una
	pieza cambiado desde el cliente no viaja, y la camara que te ve a ti no tiene
	por que estar viendo a nadie mas. Lo unico que manda el servidor es el instante
	y de quien viene (`Remotes.VIGILADO`), igual que con el impulso del rastro.

	EL EFECTO SE APAGA SOLO. El servidor manda el aviso mientras dure --dos o tres
	veces por segundo-- y aqui se guarda un "vivo hasta". Asi salir del cono lo
	apaga sin que nadie tenga que mandar un segundo mensaje diciendo "ya no", que
	es la clase de mensaje que un dia se pierde y deja el rayo encendido para
	siempre.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

local Alerta = {}

-- Cuanto sobrevive la alerta al ultimo aviso. El servidor manda cada 0,4 s, asi que
-- 0,9 aguanta un mensaje perdido sin parpadear y se apaga rapido al salir del cono.
local MEMORIA = 0.9

-- Hasta donde se animan los conos. Mas alla no se distingue el barrido y recorrer
-- cuarenta y cinco camaras por fotograma no es gratis.
local CERCA = 170
local BARRIDO_PERIODO = 2.6

local ROJO = Color3.fromRGB(255, 62, 52)

local jugador = Players.LocalPlayer

-- El indice del mundo: que piezas son de que camara. Se hace UNA vez, cuando
-- aparece el mundo, por lo mismo que en `Senales`: recorrer el workspace en cada
-- fotograma para encontrar cosas que no se mueven es tirar el cliente.
type Camara = {
	poste: BasePart,
	ojo: BasePart?,
	piloto: BasePart?,
	cunas: { BasePart },
	tonos: { Color3 },
}

local camaras: { [string]: Camara } = {}
local mundoVisto: Instance? = nil

local function indexar()
	local mundo = workspace:FindFirstChild("Mundo")
	if mundo == nil or mundo == mundoVisto then
		return
	end
	mundoVisto = mundo
	camaras = {}

	local ojos: { BasePart } = {}
	local pilotos: { BasePart } = {}
	for _, d in mundo:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local id = d:GetAttribute("detectorId")
		if typeof(id) == "string" then
			local camara = camaras[id]
			if camara == nil then
				camara = { poste = d, ojo = nil, piloto = nil, cunas = {}, tonos = {} }
				camaras[id] = camara
			end
			if d.Name == "ConoDetector" then
				table.insert(camara.cunas, d)
				-- Su color de fabrica, para poder devolverlo despues de pintarlo de
				-- rojo o de aclararlo con el barrido. Se guarda AQUI y no se recalcula:
				-- el degradado del cono depende del angulo de cada tajada (ver
				-- `Cone.luau`) y rehacer esa cuenta en el cliente seria una segunda
				-- copia de la misma regla, o sea dos sitios que un dia diran cosas
				-- distintas.
				table.insert(camara.tonos, d.Color)
			else
				-- El poste es la pieza que lleva el id y NO es una cuna: de el sale la
				-- posicion, y el resto de la camara se le asigna por cercania.
				camara.poste = d
			end
		elseif d.Name == "CamaraOjo" then
			table.insert(ojos, d)
		elseif d.Name == "CamaraPiloto" then
			table.insert(pilotos, d)
		end
	end

	-- El ojo y el piloto no llevan id --son decorado, y ponerselo a cada pieza de
	-- cada camara engorda el mundo sin necesidad-- asi que se le asignan al poste
	-- mas cercano. Doce studs es de sobra: el ojo cuelga a 8,6 de alto y 2,4 de
	-- fondo del suyo, y la camara mas proxima esta a media calle.
	for _, ojo in ojos do
		for _, camara in camaras do
			if (ojo.Position - camara.poste.Position).Magnitude < 12 then
				camara.ojo = ojo
				break
			end
		end
	end
	for _, piloto in pilotos do
		for _, camara in camaras do
			if (piloto.Position - camara.poste.Position).Magnitude < 12 then
				camara.piloto = piloto
				break
			end
		end
	end
end

-- EL RAYO. Una sola pieza que se reutiliza: crear y destruir una por aviso son
-- varias por segundo, y este proyecto ya pago esa fuga con los emisores de chispas.
local rayo: BasePart? = nil

local function pintarRayo(desde: Vector3?, hasta: Vector3?)
	if desde == nil or hasta == nil then
		if rayo then
			rayo.Transparency = 1
		end
		return
	end
	if rayo == nil then
		local p = Instance.new("Part")
		p.Name = "RayoDeVigilancia"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = ROJO
		p.Parent = workspace
		rayo = p
	end
	local p = rayo :: BasePart
	local largo = (hasta - desde).Magnitude
	if largo < 1 then
		p.Transparency = 1
		return
	end
	-- Fino y palpitante. Un rayo de grosor constante se lee como una barra fija --
	-- que es la queja que se llevo por delante los bordes del cono--; latiendo se
	-- lee como una senal.
	local latido = 0.5 + 0.5 * math.sin(os.clock() * 16)
	p.Size = Vector3.new(0.14 + latido * 0.1, 0.14 + latido * 0.1, largo)
	p.CFrame = CFrame.lookAt(desde:Lerp(hasta, 0.5), hasta)
	p.Transparency = 0.15 + latido * 0.25
end

-- EL MARCO. Cuatro franjas en los bordes, cada una desvaneciendose hacia el centro
-- con un degradado. No es un velo sobre la pantalla: un tinte encima del mundo
-- mientras conduces es mareante y tapa justo lo que hay que mirar.
local marco: ScreenGui? = nil
local bordes: { Frame } = {}
local rotulo: TextLabel? = nil

local function construirMarco()
	if marco ~= nil then
		return
	end
	local pantalla = Instance.new("ScreenGui")
	pantalla.Name = "AlertaVigilancia"
	pantalla.ResetOnSpawn = false
	pantalla.IgnoreGuiInset = true
	-- Por debajo de todo lo que se pulsa, y sin recoger clics: es un adorno, y un
	-- adorno que se come una pulsacion es un boton que no responde.
	pantalla.DisplayOrder = 5
	pantalla.Enabled = false
	pantalla.Parent = jugador:WaitForChild("PlayerGui")
	marco = pantalla

	local lados = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.16), giro = 90 },
		{ pos = UDim2.fromScale(0, 0.84), size = UDim2.fromScale(1, 0.16), giro = 270 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.1, 1), giro = 0 },
		{ pos = UDim2.fromScale(0.9, 0), size = UDim2.fromScale(0.1, 1), giro = 180 },
	}
	for _, lado in lados do
		local franja = Instance.new("Frame")
		franja.BackgroundColor3 = ROJO
		franja.BorderSizePixel = 0
		franja.Position = lado.pos
		franja.Size = lado.size
		franja.Active = false
		franja.Parent = pantalla
		-- El degradado va en la TRANSPARENCIA, no en el color: asi el borde tine la
		-- pantalla y el centro queda limpio.
		local grad = Instance.new("UIGradient")
		grad.Rotation = lado.giro
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.25),
		})
		grad.Parent = franja
		table.insert(bordes, franja)
	end

	local texto = Instance.new("TextLabel")
	texto.Name = "Rotulo"
	texto.AnchorPoint = Vector2.new(0.5, 0)
	texto.Position = UDim2.fromScale(0.5, 0.055)
	texto.Size = UDim2.fromScale(0.3, 0.06)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.fromRGB(255, 210, 205)
	texto.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
	texto.TextStrokeTransparency = 0.2
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBlack
	texto.Text = Strings.get("ALERT_WATCHED")
	texto.Parent = pantalla
	rotulo = texto
end

-- Lo que dura la alerta y de quien viene.
local vivaHasta = 0
local quien: string? = nil
local donde: Vector3? = nil
local sonando = false

-- La ultima camara que se pinto de rojo, para poder devolverle su color aunque la
-- siguiente alerta venga de otra. Sin esto, encadenar dos camaras deja la primera
-- roja para el resto de la partida.
local tenida: Camara? = nil

local function devolverColor()
	local camara = tenida
	if camara == nil then
		return
	end
	for i, cuna in camara.cunas do
		cuna.Color = camara.tonos[i]
	end
	tenida = nil
end

-- El servidor dice quien te ve. Se llama varias veces por segundo mientras dure.
function Alerta.vigilado(id: any, posicion: any, _nivel: any, _subio: any)
	if typeof(posicion) ~= "Vector3" then
		return
	end
	local nueva = vivaHasta < os.clock()
	vivaHasta = os.clock() + MEMORIA
	quien = if typeof(id) == "string" then id else nil
	donde = posicion
	if nueva then
		sonando = true
	end
end

-- ¿Suena la alarma? Lo pregunta el cliente para no meter aqui un require a Sfx: el
-- sonido es suyo, y este modulo solo sabe cuando empieza una alerta nueva.
function Alerta.hayQueSonar(): boolean
	if not sonando then
		return false
	end
	sonando = false
	return true
end

local function pintarBarrido(ahora: number)
	local raiz = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if raiz == nil then
		return
	end
	for id, camara in camaras do
		if (camara.poste.Position - raiz.Position).Magnitude > CERCA then
			continue
		end
		if id == quien and os.clock() < vivaHasta then
			continue -- esa la esta pintando la alerta
		end
		-- APAGADO NO SE ANIMA. El cono solo se ve durante un viaje (lo enciende
		-- `Senales`), y aclarar tajadas invisibles cuesta lo mismo que aclarar las
		-- visibles sin que lo vea nadie.
		local primera = camara.cunas[1]
		if primera == nil or primera.Transparency >= 1 then
			continue
		end
		-- La fase sale de la POSICION de la camara y no de un contador propio: asi
		-- cada una barre por su cuenta --cuarenta y cinco camaras sincronizadas
		-- pareceria una sola cosa parpadeando-- y ademas no hay estado que guardar.
		local fase = (ahora / BARRIDO_PERIODO + (camara.poste.Position.X + camara.poste.Position.Z) * 0.01) % 1
		local tajadas = tonumber(primera:GetAttribute("tajadas")) or 6
		-- Va y vuelve (triangular, no en sierra): una camara que barre siempre en el
		-- mismo sentido se lee como un radar; una que va y viene, como alguien
		-- mirando a un lado y a otro.
		local recorrido = if fase < 0.5 then fase * 2 else (1 - fase) * 2
		local activa = math.floor(recorrido * tajadas)
		for i, cuna in camara.cunas do
			local base = camara.tonos[i]
			local suya = tonumber(cuna:GetAttribute("tajada")) or -1
			cuna.Color = if suya == activa then base:Lerp(Color3.new(1, 1, 1), 0.35) else base
		end
		if camara.piloto then
			-- El piloto late al mismo ritmo que barre su cono: son el mismo aparato.
			local brillo = 0.35 + 0.65 * math.abs(math.sin(ahora * 2))
			camara.piloto.Color = Color3.fromRGB(255, 70, 60):Lerp(Color3.new(0, 0, 0), 1 - brillo)
		end
	end
end

local function tick()
	indexar()
	local ahora = os.clock()
	local viva = ahora < vivaHasta

	if marco then
		marco.Enabled = viva
	end
	if viva then
		-- El latido del marco: rapido, porque lo que dice es "ahora, muevete".
		local latido = 0.5 + 0.5 * math.sin(ahora * 9)
		for _, franja in bordes do
			franja.BackgroundTransparency = 0.35 + latido * 0.35
		end
		if rotulo then
			rotulo.TextTransparency = 0.1 + latido * 0.5
		end
	end

	local camara = if quien ~= nil then camaras[quien] else nil
	if viva then
		local raiz = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local desde = if camara and camara.ojo then camara.ojo.Position else donde
		if desde ~= nil and raiz ~= nil then
			pintarRayo(desde, raiz.Position + Vector3.new(0, 0.6, 0))
		else
			pintarRayo(nil, nil)
		end
		if camara ~= nil and camara ~= tenida then
			devolverColor()
			tenida = camara
		end
		if camara ~= nil then
			for _, cuna in camara.cunas do
				cuna.Color = ROJO
			end
		end
	else
		pintarRayo(nil, nil)
		devolverColor()
	end

	pintarBarrido(ahora)
end

local arrancado = false
local avisado = false

function Alerta.build()
	construirMarco()
	if arrancado then
		return
	end
	arrancado = true
	-- EN HEARTBEAT, y no en el bucle de 4 Hz del cliente ni en RenderStepped.
	--
	-- Ni en el de 4 Hz porque el rayo sigue al jugador, y a cuatro fotogramas por
	-- segundo un rayo que te apunta se lee como un rayo que da saltos.
	--
	-- Y no en RenderStepped por dos motivos. El bueno: RenderStepped bloquea el
	-- dibujado del fotograma, asi que ahi solo debe ir lo que tenga que estar
	-- sincronizado con la camara, y esto no lo esta. El practico: con la ventana de
	-- Studio SIN FOCO, RenderStepped da cero llamadas por segundo -- o sea que el
	-- efecto no se puede medir por el MCP, que es como se comprueba todo aqui. Se
	-- midio: con la ventana detras, la cadera de una patrulla marcaba 0.00 ocho
	-- veces seguidas mientras el cuerpo iba a 16 studs/s.
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(tick)
		-- El aviso, UNA vez por sesion: esto corre sesenta veces por segundo y un
		-- warn por fotograma llena el historial y esconde justo el error que se
		-- quiere leer. Con `LogService:GetLogHistory()` desde el MCP, esa linea es
		-- ahora la diferencia entre un diagnostico de un segundo y una tarde.
		if not ok and not avisado then
			avisado = true
			warn("[Contrabando] fallo pintando la alerta: " .. tostring(err))
		end
	end)
end

return Alerta
