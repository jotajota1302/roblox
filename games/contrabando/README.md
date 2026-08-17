# Contrabando — prototipo

Implementación de [`DISENO.md`](DISENO.md). Mide una sola cosa: si transportar carga
entretiene, y si la intercepción da tensión en vez de rabia.

## Arrancar

Dos formas, según si hay alguien delante de Studio para pulsar Connect:

```powershell
..\..\tools\rojo.exe serve      # sincronización en vivo; Connect desde el plugin de Rojo
```

```powershell
..\..\tools\rojo.exe build --output contrabando.rbxl   # genera el place ya montado
```

La segunda no necesita el plugin: el `.rbxl` que sale ya lleva todo el árbol del proyecto
dentro, así que basta abrirlo en Studio. A cambio no hay sincronización en vivo — tras
cambiar código hay que reconstruirlo, o escribir el `.Source` de los módulos por MCP.

## Probar

Toda la lógica de reglas vive en `src/shared/` como módulos puros y se prueba dentro de
Studio, porque Luau no corre fuera de Roblox. En la consola de Studio (o por MCP):

```lua
-- require() cachea por instancia: llamarlo dos veces devuelve el resultado de la primera
-- aunque el código haya cambiado, y verías verde sobre código que ya no existe. El clon
-- da instancias nuevas y aísla cada tanda.
local clon = game.ReplicatedStorage.Shared:Clone()
clon.Name = "SharedTestRun"
clon.Parent = game.ReplicatedStorage
local ok, resultado = pcall(function()
	return require(clon.TestRunner).run()
end)
clon:Destroy()
print(if ok then resultado else "LA TANDA REVENTO: " .. tostring(resultado))
```

## Verificación mecánica

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

Ninguna de las dos garantiza que el juego funcione: el peor fallo del piloto compilaba
perfectamente. Probar siempre dentro de Studio.
