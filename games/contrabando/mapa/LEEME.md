# `mapa/` — el trabajo del mapa, agrupado

> **Actualizado el 19/08.** Desde esta fecha la ciudad ES la retícula propia y el
> `.rbxm` ya no se monta: el bloque `"Ciudad"` salió del `default.project.json`.
> Entre el 17 y el 19 este documento decía lo mismo y no era verdad -- el bloque
> seguía puesto-- así que si vuelves a esta carpeta, **fíate del
> `default.project.json`, no de este párrafo**.
>
> El spec vigente es
> [`../docs/specs/2026-08-19-mapa-propio-design.md`](../docs/specs/2026-08-19-mapa-propio-design.md).
> El [`DISENO-MAPA.md`](DISENO-MAPA.md) de esta carpeta lo precede: diseñaba una
> cuadrícula de 1600x1600 para un mundo que se encogió a la mitad el 19/08, así que
> sus números ya no valen aunque su razonamiento sí.
>
> Y el plano ya no vive aquí ni en `MapBuilder`: vive en `../src/shared/Grid.luau`,
> que es de donde beben también `Config` (para los destinos) y `SelfCheck` (para
> verificarlos).

## Qué hay aquí

| Fichero | Para qué |
|---|---|
| [`DISENO-MAPA.md`](DISENO-MAPA.md) | El spec: por qué procedural, cómo se construye, qué entra y qué no en cada fase |
| [`Ciudad.rbxm`](Ciudad.rbxm) | El asset original del Creator Store (id `2701703521`). **No se monta**: la ciudad ahora es procedural. Se conserva por si en algún momento queremos volver a él |
| [`LEEME-ASSET.md`](LEEME-ASSET.md) | Nota histórica del asset: qué tenía, por qué se quitó, cómo volver a importarlo si hace falta |
| `LEEME.md` | Este índice — **léeme primero** si llegas a esta carpeta sin contexto |

## Dónde está el resto (código, no se puede mover aquí)

El código **no** vive aquí: Rojo mapea `src/server/` a
`ServerScriptService.Server`, y el módulo tiene que estar en ese árbol para
que `Main.server.luau` lo pueda requerir. Moverlo aquí rompería el build.

| Fichero | Qué hace |
|---|---|
| [`../src/server/MapBuilder.luau`](../src/server/MapBuilder.luau) | El generador procedural: planta suelo, calles, aceras, edificios por zona, valida puntos fijos |
| [`../src/server/Main.server.luau`](../src/server/Main.server.luau) | El arranque: llama a `MapBuilder.buildCiudad(workspace)` antes de `CityBuilder.build()` |
| [`../src/server/CityBuilder.luau`](../src/server/CityBuilder.luau) | Sin cambios — usa el `Model "Ciudad"` que crea MapBuilder como suelo para sus raycasts |
| [`../default.project.json`](../default.project.json) | Borrado el bloque `Ciudad.rbxm` (ya no se monta) |

## Cómo revertir al asset del Creator Store

Si la fase 1 no convence tras jugarla, volver al `.rbxm` son **3 pasos**:

1. Copiar este `Ciudad.rbxm` a `../src/assets/` (o donde apunte el `default.project.json`).
2. Restaurar el bloque `"Ciudad": { "$path": ... }` en `../default.project.json`.
3. Borrar la llamada a `MapBuilder.buildCiudad` en `../src/server/Main.server.luau`.

El spec de `DISENO-MAPA.md` se queda como documentación de por qué se intentó
y qué se aprendió.

## Cómo regenerar el `.rbxm` desde el Creator Store

Si por algún motivo se pierde el `Ciudad.rbxm` que está aquí, se vuelve a sacar
del Creator Store con el id `2701703521`. Pasos detallados en
[`LEEME-ASSET.md`](LEEME-ASSET.md).

## Fases

| Fase | Estado | Qué pregunta responde |
|---|---|---|
| **1. Foundation** | ✅ Hecho | ¿Compila y carga el mapa procedural? ¿Las 3 zonas se distinguen? |
| **2. Carácter** | ✅ Hecho | ¿Las 3 zonas se *sienten* distintas al caminar? ¿Los callejones generan tensión en la roja? ¿La plaza de la verde es un atajo visible? |
| **2.5. Solares** | ✅ Hecho | ¿Los solares de ámbar y roja funcionan como vías de escape cuando una patrulla te pisa los talones? |
| **3 lite. Hitos + verificación** | ✅ Hecho | ¿El jugador se orienta de un vistazo? ¿Los solares están conectados al almacén? |
| **4. Estética** | ⏳ Pendiente | **NO entra hasta que el bucle enganche.** El bucle mide el juego, el arte mide el juicio del desarrollador — y el juicio no se mide hasta que el bucle probó que hay juego. |

El criterio para matar el proyecto **no cambia** con esto: el bucle tiene que
aguantar 10 minutos andando, sin PvP, antes de invertir en arte. El mapa es
geometría al servicio de ese bucle.
