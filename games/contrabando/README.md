# Contrabando — prototipo

Implementación de [`../DISENO.md`](../DISENO.md). Mide una sola
cosa: si transportar carga entretiene, y si la intercepción da tensión en vez de rabia.

## Arrancar

```powershell
..\..\tools\rojo.exe serve      # y Connect desde el plugin de Rojo en Studio
```

## Probar

Toda la lógica de reglas vive en `src/shared/` como módulos puros y se prueba dentro de
Studio. Con Rojo conectado, ejecutar en la consola de Studio (o por MCP):

```lua
print(require(game.ReplicatedStorage.Shared.TestRunner).run())
```

## Verificación mecánica

```powershell
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build
```

Ninguna de las dos garantiza que el juego funcione: el peor fallo del piloto compilaba
perfectamente. Probar siempre dentro de Studio.
