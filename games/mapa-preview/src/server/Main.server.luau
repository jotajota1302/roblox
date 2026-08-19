--!strict
--[[
	Main.server.luau — punto de entrada del proyecto standalone de vista
	previa del mapa. **NO** es el juego: no hay servicios, ni estado, ni
	reglas. Sólo genera la ciudad procedural y la deja en `workspace.Ciudad`
	para que se pueda inspeccionar visualmente en Studio.

	Usa exactamente el mismo MapBuilder que `games/contrabando/`, así lo
	que ves aquí es lo que vería el jugador al dar a Play. La diferencia es
	que aquí **no hay juego encima** (sin warehouse, sin destinos, sin
	personajes, sin DataStore) — es el mapa pelado.

	Para regenerar con la misma semilla, vuelve a dar a Play en Studio.
]]

local MapBuilder = require(script.Parent.MapBuilder)

-- Generar la ciudad. MapBuilder.buildCiudad hace todo:
--   1. Suelo base
--   2. Calles y aceras
--   3. Manzanas, edificios, solares, hitos
--   4. Validación de puntos fijos
--   5. Resumen de build (impreso en consola)
--   6. Verificación de conectividad con PathfindingService
MapBuilder.buildCiudad(workspace)

print("[mapa-preview] listo — abre el Explorer y mira Workspace.Ciudad")
