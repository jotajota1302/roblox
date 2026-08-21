--!strict
--[[
	Rigs.luau — de que esta hecho un personaje. Modulo PURO salvo por mirar hijos.

	POR QUE EXISTE. Este juego crea sus personajes en R6 a proposito (ver
	`Avatar.luau`: el R15 son quince MeshPart y sin publicar el place el jugador sale
	invisible), pero **no siempre lo consigue** -- si `Avatar.cargar` falla o el place
	esta publicado, Roblox entrega el R15 de siempre. Medido el 21/08 en una partida
	real: el personaje era R15 con `UpperTorso`.

	Y ahi salto el fallo: TRES ficheros distintos buscaban `character.Torso`, que en
	R15 no existe. `CargoService` caia a la `HumanoidRootPart` --una pieza invisible
	que NO sigue las animaciones-- y de ahi *"la mochila no se mueve bien"*: iba
	pegada a un punto que no se inclina ni se balancea, asi que flotaba rigida
	mientras el cuerpo andaba.

	No revienta nada, y por eso duro: hay mochila, esta en su sitio y sigue al
	jugador. Solo que no se mueve con el.

	La regla es la de siempre en esta casa: si la misma pregunta se hace en tres
	sitios, un dia dos de ellos cambian y el tercero no. Aqui se hace una vez.
]]

local Rigs = {}

-- EL TORSO, en el rig que sea. En R15 es `UpperTorso` --el de arriba, el que lleva
-- los hombros-- y en R6 es `Torso`. La raiz queda de ultimo recurso y no de primera
-- opcion: sirve para que nada reviente, no para colgar cosas de ella.
function Rigs.torso(character: Instance): BasePart?
	local arriba = character:FindFirstChild("UpperTorso")
	if arriba and arriba:IsA("BasePart") then
		return arriba
	end
	local clasico = character:FindFirstChild("Torso")
	if clasico and clasico:IsA("BasePart") then
		return clasico
	end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

-- Donde SE APOYA la espalda, en coordenadas del torso. El R15 tiene el torso mas
-- corto y mas alto que el R6, asi que una mochila colocada con las medidas del uno
-- queda a la altura del cuello en el otro.
function Rigs.esR15(character: Instance): boolean
	return character:FindFirstChild("UpperTorso") ~= nil
end

return Rigs
