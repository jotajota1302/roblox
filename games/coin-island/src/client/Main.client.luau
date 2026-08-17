--[[
	Main.client.luau — punto de entrada del CLIENTE.

	El sufijo ".client" hace que Rojo lo convierta en un LocalScript. Vive en
	StarterPlayerScripts, que Roblox copia dentro de cada jugador cuando entra.
	Así que este código se ejecuta una vez por jugador, EN SU MÁQUINA.

	Consecuencias que hay que tener en la cabeza siempre:
	  · Aquí `Players.LocalPlayer` existe (en el servidor es nil: hay muchos jugadores).
	  · Lo que hagas aquí solo lo ve este jugador.
	  · Nada de lo que se decida aquí es fiable para el juego. Solo presentación.
]]

local Ui = require(script.Parent:WaitForChild("Ui"))

Ui.start()

print("[Isla de Monedas] Cliente listo.")
