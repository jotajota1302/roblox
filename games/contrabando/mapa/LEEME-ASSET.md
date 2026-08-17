# `Ciudad.rbxm` — el asset original, conservado como histórico

> 2026-08-17. Este fichero es el modelo del Creator Store (id `2701703521`)
> que se usaba como `Workspace.Ciudad` hasta que se sustituyó por el
> generador procedural. Ya **no se monta** — `default.project.json` no lo
> referencia — pero se conserva en el repo por si en algún momento hace
> falta volver a él, o para comparar geometría con el mapa procedural.

## Por qué se reemplazó

Ver [`DISENO-MAPA.md`](DISENO-MAPA.md) para el argumento completo. Resumen:

- Un binario en git no es revisable en un diff.
- El modelo genérico no tenía carácter por zona — el generador procedural
  sí, y era la pieza que el rediseño del viaje (`DISENO-CIUDAD.md`) pedía
  para que la mecánica funcionara.
- 0 dependencia externa = cualquier clon del repo arranca igual en
  cualquier máquina, sin pasos manuales.

## Características medidas del asset (de la época en que se usaba)

| | |
|---|---|
| Id del Creator Store | `2701703521` |
| Extensión | 1548 × 1569 studs |
| Piezas | 7152 |
| Meshes | 0 (se veía sin publicar el place) |
| Scripts | 0 (sin backdoor) |
| Suelo andable | 94 % de 225 sondeos |

Eran las dos cifras que justificaban adoptarlo: 0 meshes y 0 scripts. La
primera quitaba la trampa de "no se ve hasta publicar"; la segunda, el
riesgo real de los modelos del Toolbox.

## Si por algún motivo hay que volver a usarlo

1. Copiar este `Ciudad.rbxm` a `../src/assets/`.
2. Restaurar el bloque `"Ciudad": { "$path": ... }` en
   `../default.project.json` (borrado el 2026-08-17).
3. Borrar la llamada a `MapBuilder.buildCiudad` en
   `../src/server/Main.server.luau`.

Son **dos cambios de 3 líneas** en total. El spec de `DISENO-MAPA.md` se
queda como documentación de por qué se intentó y qué se aprendió.

## Si se pierde este `.rbxm` y hay que regenerarlo

1. En Roblox Studio, abrir el **Toolbox** y buscar el id `2701703521`, o
   ir directo por la URL
   `https://create.roblox.com/store/asset/2701703521/City-Map`.
2. Insertarlo en un Baseplate vacío.
3. Click derecho sobre el modelo en el Explorador →
   **Save to File…** → guardar con el nombre exacto `Ciudad.rbxm` en esta
   carpeta (`mapa/`), sobreescribiendo el que falta.

`InsertService:LoadAsset` **no sirve** en runtime: probado, devuelve
*"User is not authorized to access Asset"*. Roblox sólo carga en runtime
los assets de tu propia cuenta, así que un modelo ajeno no puede vivir
como un id en el código — de ahí que el mapa tenga que viajar como
fichero.
