--!nocheck
--[[
	sync.luau — trae el codigo del disco a Studio sin plugin y sin Connect.

	Se ejecuta con el MCP en el datamodel **Edit** (en Play no sirve de nada: una
	sesion de Play corre sobre el snapshot que se hizo al arrancarla, asi que hay que
	parar, sincronizar y volver a arrancar).

	Al otro lado esta `scripts/sync-server.js`, que sirve en JSON la lista de modulos
	con su ruta dentro del datamodel y su codigo. La correspondencia sale del
	sourcemap del propio Rojo, asi que es la misma que usaria su plugin.

	Escribe SOLO lo que ha cambiado, y por dos motivos: escribir 909 KB de Source de
	golpe hace que Studio se piense un rato, y --mas importante-- el informe de vuelta
	dice exactamente que modulos se han movido. Un "0 cambios" cuando esperabas uno es
	la senal de que estas mirando el sitio equivocado, que en este proyecto ya ha
	costado sesiones enteras.
]]

local HttpService = game:GetService("HttpService")

-- Studio bloquea las peticiones si esto esta apagado, y el error que da no menciona
-- la causa. Se enciende aqui en vez de pedirselo al usuario.
pcall(function()
	HttpService.HttpEnabled = true
end)

local ok, crudo = pcall(function()
	return HttpService:GetAsync("http://127.0.0.1:34873/arbol", true)
end)
if not ok then
	return "no contesta el servidor de sincronizacion: " .. tostring(crudo) .. "\n(arrancalo con: node scripts/sync-server.js)"
end

local vale, lista = pcall(function()
	return HttpService:JSONDecode(crudo)
end)
if not vale then
	return "el servidor contesto algo que no es JSON: " .. tostring(lista)
end

-- Baja por el datamodel siguiendo la ruta ("ReplicatedStorage/Shared/Config") y CREA
-- el modulo si no existe.
--
-- Crearlos hizo falta enseguida: un fichero nuevo --`Vision.luau`, el primer dia que se
-- uso esto-- no tiene sitio en un place compilado antes de escribirlo, y sin esto habia
-- que recompilar y reabrir Studio, que es justo lo que el sincronizador venia a evitar.
--
-- Lo que NO se crea son las carpetas intermedias: si falta `Shared`, el place esta
-- construido con otro `project.json` y eso es un problema de verdad que no hay que
-- esconder plantando una carpeta vacia encima.
local function buscar(ruta: string, clase: string?): Instance?
	local aqui: Instance = game
	local trozos = {}
	for trozo in string.gmatch(ruta, "[^/]+") do
		table.insert(trozos, trozo)
	end
	for i, trozo in trozos do
		local siguiente = aqui:FindFirstChild(trozo)
		if siguiente == nil then
			if i < #trozos then
				-- Falta una carpeta intermedia: eso no se inventa.
				return nil
			end
			local nueva = Instance.new((clase or "ModuleScript") :: any)
			nueva.Name = trozo
			nueva.Parent = aqui
			return nueva
		end
		aqui = siguiente
	end
	return aqui
end

local cambiados, iguales, perdidos = {}, 0, {}
for _, entrada in lista do
	local destino = buscar(entrada.ruta, entrada.clase)
	if destino == nil or not destino:IsA("LuaSourceContainer") then
		table.insert(perdidos, entrada.ruta)
		continue
	end
	if destino.Source == entrada.codigo then
		iguales += 1
	else
		destino.Source = entrada.codigo
		table.insert(cambiados, entrada.ruta)
	end
end

local partes = {
	string.format("%d modulos: %d actualizados, %d ya estaban al dia", #lista, #cambiados, iguales),
}
for _, r in cambiados do
	table.insert(partes, "  ~ " .. r)
end
if #perdidos > 0 then
	table.insert(partes, string.format("  ! %d sin sitio en el datamodel (el place es de otra version):", #perdidos))
	for i = 1, math.min(5, #perdidos) do
		table.insert(partes, "      " .. perdidos[i])
	end
end
return table.concat(partes, "\n")
