# src/assets — lo que no cabe en un fichero de texto

Aquí vive el único trozo del juego que **no** está escrito en código: el escenario.

## Ciudad.rbxm

El mapa sobre el que se juega. Modelo público `2701703521` del Creator Store.

**No está en git como un id porque no se puede.** `InsertService:LoadAsset` falla con
*"User is not authorized to access Asset"*: Roblox sólo carga en runtime los assets de tu
propia cuenta, nunca uno ajeno del Toolbox. Así que el mapa tiene que viajar como fichero.

Verificado antes de adoptarlo (ver `DISENO-CIUDAD.md` §3): 1548 × 1569 studs, 7152 piezas,
**0 meshes** (se ve sin publicar el place) y **0 scripts** (sin backdoor, que es el riesgo
real de los modelos del Toolbox).

### Cómo se regenera si se pierde

1. En Studio, insertar el asset `2701703521`.
2. Botón derecho sobre el modelo en el Explorador → **Save to File…**
3. Guardarlo aquí, con el nombre exacto `Ciudad.rbxm`.

Rojo lo monta en `Workspace.Ciudad` (ver `default.project.json`). Nada del juego depende de
su contenido: el almacén, el taller, los destinos, los detectores y las patrullas los pone
`CityBuilder` por código. La ciudad aporta calles y edificios, y ni una regla vive en ella.

### Por qué un binario en un repo que presume de código

`CLAUDE.md` dice que el mundo se genera por código. El motivo de esa regla es que todo sea
reproducible desde git y que el `.rbxl` sea desechable — y un `.rbxm` versionado cumple ese
motivo, aunque no se pueda leer en un diff. Generar la ciudad por código **queda abierto**
como salida si el mapa ajeno nos aprieta: decisión aplazada, no descartada.
