# Mapa propio — plan de implementación

> **Para quien ejecute esto:** las tareas van en orden y cada una acaba con el juego
> compilando y las pruebas en verde. No saltes tareas: la 3 deja el mundo a medias si la
> 1 no está.

**Objetivo:** sustituir la ciudad prestada del Creator Store por una retícula propia de
12 manzanas alineada a las coordenadas que el juego ya tiene, con los cuatro destinos en
cruces.

**Arquitectura:** la geometría de la retícula se extrae a un módulo puro nuevo
(`shared/Grid.luau`) del que beben los tres consumidores: `MapBuilder` planta desde él,
`Config` deriva los destinos de él, `SelfCheck` verifica contra él. Hoy esa información
está duplicada entre `MapBuilder` (server, no comprobable) y `Config` (coordenadas
sueltas), y es justo el tipo de duplicación que ya produjo un destino bajo un árbol.

**Stack:** Luau, Rojo, stylua. Pruebas con el `TestKit` del proyecto, ejecutadas dentro de
Studio por MCP.

**Spec:** [`../specs/2026-08-19-mapa-propio-design.md`](../specs/2026-08-19-mapa-propio-design.md)

## Restricciones globales

- Comentarios en **español**, identificadores en **inglés**.
- **Ningún texto de jugador fuera de `src/shared/Strings.luau`.** Los `warn()` y `print()`
  de consola no son texto de jugador y van en español.
- Los **ids nunca se traducen**: `"verde"`, `"ambar"`, `"roja"`, `"barrio"`.
- Sin meshes. Todo `Part`.
- El place se compila **siempre** en `games/contrabando/contrabando.rbxl`.
- Verificación obligatoria por tarea: `..\..\tools\stylua.exe --check src` y
  `..\..\tools\rojo.exe build --output contrabando.rbxl`.
- **Studio no puede estar en Play** al editar: Rojo sincroniza contra `Edit`.

## La retícula, de una vez

Estos números se repiten en varias tareas. Son la fuente:

```
Paso            146   (manzana 120 + calle 26)
Calles X        -766, -620, -474, -328, -182      (5 calles, 4 columnas)
Calles Z         754,  608,  462,  316            (4 calles, 3 filas)
Manzana col i   de (-753 + 146i) a (-633 + 146i)
Manzana fila j  de ( 329 + 146j) a ( 449 + 146j)
Extensión       X ∈ [-779, -169], Z ∈ [303, 767]
Cota transitable y = 19.2  (Config.ALMACEN_POS.Y)
```

Filas de sur a norte: fila 0 = roja, fila 1 = ámbar, fila 2 = verde.

**Un stud de desfase, explicado una vez.** `Config.POLIGONO_SALIDA.Z` vale 755 (sale de
`POLIGONO_CENTRO.Z - TAMANO.Y / 2` = 880 − 125) y la calle norte de la retícula está en
754. El spec cita las distancias desde 755 (147 / 293 / 439 / 731) y este plan las mide
sobre la retícula, desde 754 (146 / 292 / 438 / 730). Es el mismo camino contado desde un
stud más allá. Las pruebas exactas (`kit.eq`) usan **siempre** la cota de la retícula; las
que parten de `POLIGONO_SALIDA` usan tolerancia. El polígono no se mueve para cuadrar un
stud: cambiarlo tocaría el recinto, la zona segura y el spawn.

| Ruta | Cruce | (i, j) |
|---|---|---|
| barrio | (−620, 608) | (1, 2) |
| verde | (−766, 608) | (0, 2) |
| ámbar | (−474, 462) | (2, 1) |
| roja | (−328, 316) | (3, 0) |

---

### Tarea 1: `Grid.luau`, la retícula como módulo puro

**Ficheros:**
- Crear: `src/shared/Grid.luau`
- Crear: `src/shared/tests/Grid.spec.luau`
- Modificar: `src/shared/TestRunner.luau` (registrar la suite nueva)

**Interfaces que produce** (de aquí beben las tareas 2, 3, 4 y 7):

```lua
Grid.PASO: number            -- 146
Grid.ANCHO_CALLE: number     -- 26
Grid.LADO_MANZANA: number    -- 120
Grid.COLUMNAS: number        -- 4
Grid.FILAS: number           -- 3
Grid.Y: number               -- 19.2, la cota transitable

Grid.xDeCalle(i: number): number      -- i de 0 a COLUMNAS
Grid.zDeCalle(j: number): number      -- j de 0 a FILAS
Grid.cruce(i: number, j: number): Vector3
Grid.limites(): (number, number, number, number)   -- xMin, xMax, zMin, zMax
Grid.manzana(col: number, fila: number): (number, number, number, number)  -- x0,x1,z0,z1
Grid.zonaDeFila(fila: number): string   -- "roja" | "ambar" | "verde"
Grid.filaDeZona(zona: string): number
Grid.enCalle(x: number, z: number): boolean
Grid.giros(desde: Vector3, hasta: Vector3): number
Grid.camino(desde: Vector3, hasta: Vector3): number   -- Manhattan sobre la retícula
```

`Grid.giros` cuenta los cambios de eje del recorrido en L más corto: 0 si comparten X o Z,
1 en cualquier otro caso dentro de la retícula. Existe porque "¿a cuántos giros está el
destino?" es la forma medible de "sé a dónde ir", y la tarea 7 la usa como comprobación.

- [ ] **Paso 1: escribir la suite que falla**

`src/shared/tests/Grid.spec.luau`:

```lua
--!strict
local Grid = require(script.Parent.Parent.Grid)

return function(kit)
	kit.eq("la calle 0 esta en el borde oeste", Grid.xDeCalle(0), -766)
	kit.eq("la calle de la boca del recinto", Grid.xDeCalle(1), -620)
	kit.eq("la ultima calle vertical", Grid.xDeCalle(Grid.COLUMNAS), -182)
	kit.eq("la calle horizontal bajo el recinto", Grid.zDeCalle(Grid.FILAS), 754)
	kit.eq("el borde sur", Grid.zDeCalle(0), 316)

	-- El paso es constante: si alguien mueve una calle a mano, esto lo caza.
	for i = 1, Grid.COLUMNAS do
		kit.eq("paso constante en X " .. i, Grid.xDeCalle(i) - Grid.xDeCalle(i - 1), Grid.PASO)
	end

	-- Las filas nombran zonas, y la verde es la de casa.
	kit.eq("la fila alta es la verde", Grid.zonaDeFila(2), "verde")
	kit.eq("la del medio es la ambar", Grid.zonaDeFila(1), "ambar")
	kit.eq("la de abajo es la roja", Grid.zonaDeFila(0), "roja")

	-- Los cuatro destinos, a un giro o ninguno de la boca del recinto.
	local boca = Vector3.new(-620, Grid.Y, 754)
	kit.eq("al barrio se va recto", Grid.giros(boca, Grid.cruce(1, 2)), 0)
	kit.eq("a la verde, un giro", Grid.giros(boca, Grid.cruce(0, 2)), 1)
	kit.eq("a la ambar, un giro", Grid.giros(boca, Grid.cruce(2, 1)), 1)
	kit.eq("a la roja, un giro", Grid.giros(boca, Grid.cruce(3, 0)), 1)

	-- Y la progresión de caminos que justifica el rediseño.
	kit.eq("camino al barrio", Grid.camino(boca, Grid.cruce(1, 2)), 146)
	kit.eq("camino a la verde", Grid.camino(boca, Grid.cruce(0, 2)), 292)
	kit.eq("camino a la ambar", Grid.camino(boca, Grid.cruce(2, 1)), 438)
	kit.eq("camino a la roja", Grid.camino(boca, Grid.cruce(3, 0)), 730)

	-- Un cruce es calle; el centro de una manzana no.
	kit.truthy("un cruce esta en calle", Grid.enCalle(-620, 608))
	kit.falsy("el centro de una manzana no", Grid.enCalle(-547, 681))
end
```

- [ ] **Paso 2: ejecutar y ver que falla**

En Studio (MCP, datamodel `Server`): correr `TestRunner`. Esperado: la suite `Grid` no
existe todavía → error de `require`.

- [ ] **Paso 3: escribir `Grid.luau`**

Módulo puro: sin `Instance`, sin servicios, sólo aritmética y `Vector3`. Constantes
derivadas unas de otras (`PASO = LADO_MANZANA + ANCHO_CALLE`) para que no puedan
discrepar. `xDeCalle(i) = X_PRIMERA + i * PASO` con `X_PRIMERA = -766`;
`zDeCalle(j) = Z_PRIMERA + j * PASO` con `Z_PRIMERA = 316`.

`enCalle(x, z)`: verdadero si `x` o `z` está a menos de `ANCHO_CALLE / 2` de alguna línea
de calle.

`giros(a, b)`: `0` si `a.X == b.X` o `a.Z == b.Z`, si no `1`.

`camino(a, b)`: `math.abs(a.X - b.X) + math.abs(a.Z - b.Z)`.

- [ ] **Paso 4: registrar la suite y ejecutar**

Añadir `Grid` a la lista de suites de `TestRunner.luau`. Correr. Esperado: todas en verde,
y las ~800 anteriores sin tocar.

- [ ] **Paso 5: formato, build y commit**

```
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
git add src/shared/Grid.luau src/shared/tests/Grid.spec.luau src/shared/TestRunner.luau
git commit
```

---

### Tarea 2: los cuatro destinos pasan a ser cruces

**Ficheros:**
- Modificar: `src/shared/Config.luau` — los cuatro `destino` de `Config.RUTAS`, y borrar
  `Config.POLIGONO_ENGANCHE`
- Modificar: `src/shared/tests/Mapa.spec.luau` — comprobaciones nuevas

**Consume:** `Grid.cruce`, `Grid.Y` (tarea 1).

Los destinos dejan de ser literales y se derivan:

```lua
destino = Grid.cruce(1, 2),   -- barrio
destino = Grid.cruce(0, 2),   -- verde
destino = Grid.cruce(2, 1),   -- ambar
destino = Grid.cruce(3, 0),   -- roja
```

`Config.POLIGONO_ENGANCHE` se borra: existía para enganchar la salida del recinto a la
calle más cercana de la ciudad ajena, medida a mano. Con retícula propia la boca del
recinto (X = −620) **está** en la calle 1. Hay que quitar también su uso en
`CityBuilder.luau` (grep `POLIGONO_ENGANCHE`); ese punto se cierra del todo en la tarea 6,
aquí basta con que compile.

- [ ] **Paso 1: escribir las comprobaciones nuevas en `Mapa.spec.luau`**

```lua
local Grid = require(script.Parent.Parent.Grid)

-- Cada destino cae en un cruce de la retícula, no en "donde había suelo llano".
for _, ruta in Routes.todas() do
	kit.truthy("el destino " .. ruta.id .. " esta en una calle", Grid.enCalle(ruta.destino.X, ruta.destino.Z))
end

-- Y todos a un giro o ninguno de la boca del recinto: es "sé a dónde ir",
-- convertido en una comprobación.
local boca = Config.POLIGONO_SALIDA
for _, ruta in Routes.todas() do
	kit.truthy("al destino " .. ruta.id .. " se llega con un giro o ninguno", Grid.giros(boca, ruta.destino) <= 1)
end

-- Las cuatro rutas salen en direcciones distintas. Cuatro distancias en la misma
-- dirección no se recuerdan; cuatro direcciones sí.
local vistos: { [string]: boolean } = {}
for _, ruta in Routes.todas() do
	local d = ruta.destino - boca
	local clave = string.format("%d,%d", math.sign(d.X), math.sign(d.Z))
	kit.falsy("la ruta " .. ruta.id .. " no repite direccion", vistos[clave])
	vistos[clave] = true
end
```

- [ ] **Paso 2: ejecutar y ver que falla**

Esperado: los cuatro "está en una calle" en rojo, porque los destinos siguen siendo los
viejos.

- [ ] **Paso 3: cambiar los destinos y borrar `POLIGONO_ENGANCHE`**

- [ ] **Paso 4: ejecutar todo el `TestRunner`**

Esperado: verde. **Vigilar dos comprobaciones existentes de `Mapa.spec`** que dependen de
las distancias:

- `roja > ambar * 1.4` — con los cruces nuevos son 604 y 403 en línea recta; el margen es
  del 7 %. Si sale rojo, mover la roja a `Grid.cruce(4, 0)` (X = −182), que da 697.
- `ambar > verde * 1.4` — 403 frente a 229, holgado.

Si hay que mover la roja, **actualizar la tabla del spec** en el mismo commit: un plan que
deja el spec mintiendo es peor que no tener spec.

- [ ] **Paso 5: formato, build y commit**

---

### Tarea 3: la retícula plantada

**Ficheros:**
- Modificar: `src/server/MapBuilder.luau` — constantes, `xDeColumna`/`zDeFila`,
  `plantarSueloBase`, `plantarCalleX`, `plantarCalleZ`, `plantarAcerasManzana`

**Consume:** todo `Grid`.

Cambios:

1. Se borran `TAMANO_TOTAL`, `MITAD`, `N_MANZANAS`, `TAMANO_MANZANA`, `ANCHO_CALLE`,
   `Y_SUELO`. Pasan a leerse de `Grid`.
2. `xDeColumna(i)` / `zDeFila(j)` devuelven el borde bajo de la manzana `i`/`j`, derivado
   de `Grid.manzana`.
3. **Las calles perimetrales entran.** Hoy el bucle es `for i = 1, N_MANZANAS - 1`, así que
   sólo se plantan las calles interiores y el mapa no tiene borde por el que rodear. Pasa a
   `for i = 0, Grid.COLUMNAS`. Son 5 verticales y 4 horizontales.
4. **Todo sube a la cota del juego.** Hoy el suelo está en `y = 0` y las calles en
   `y = 0.25`; el almacén está en `y = 19.2`. La superficie transitable pasa a ser
   `Grid.Y`: la pieza de calzada tiene su cara superior exactamente ahí (centro en
   `Grid.Y - ALTO_CALLE / 2`). El suelo base va justo debajo.
5. `plantarSueloBase` cubre `Grid.limites()` con margen de 60 studs por lado, en piezas de
   como mucho 512 — el límite de 2048 por eje ya no es un riesgo con 610 de mapa, pero
   piezas más pequeñas dan raycasts más baratos.

- [ ] **Paso 1: aplicar los cambios de geometría**

- [ ] **Paso 2: build y carga en Studio**

```
..\..\tools\rojo.exe build --output contrabando.rbxl
```

Abrir `contrabando.rbxl`, **quitar Studio de Play si estaba**, y comprobar en el datamodel
`Edit` que el `Source` del módulo trae el cambio antes de medir nada.

- [ ] **Paso 3: medir el mundo construido**

Con `execute_luau` en el datamodel `Server`, tras arrancar Play:

```lua
local c = workspace:FindFirstChild("Ciudad")
local calles = c.Calles:GetChildren()
print(#calles)                        -- esperado: 9
local minY, maxY = math.huge, -math.huge
for _, p in calles do
	minY = math.min(minY, p.Position.Y + p.Size.Y / 2)
	maxY = math.max(maxY, p.Position.Y + p.Size.Y / 2)
end
print(minY, maxY)                     -- esperado: 19.2 y 19.2, sin decimales sueltos
```

Esperado: 9 calles, todas con la cara superior en 19.2 exacto. Si `minY ~= maxY`, hay un
bug de generación y se arregla aquí, no después.

- [ ] **Paso 4: formato, build y commit**

---

### Tarea 4: zonas por filas, plaza, solares y los tres hitos en la calle de salida

**Ficheros:**
- Modificar: `src/server/MapBuilder.luau` — `ZONAS`, `PLAZA`, `LOTES_VACANTES`,
  `centroDeZona`, `plantarHito`, `manzanasDe`, el resumen de `buildCiudad`

**Consume:** `Grid.zonaDeFila`, `Grid.filaDeZona`, `Grid.xDeCalle`, `Grid.manzana`.

```lua
-- Bandas por fila: la zona de una ruta es la que hay que atravesar para llegar.
ZONAS = {
	verde = { fila = 2, densidadMin = 1, densidadMax = 2, altoMin = 12, altoMax = 24 },
	ambar = { fila = 1, densidadMin = 2, densidadMax = 3, altoMin = 24, altoMax = 44 },
	roja  = { fila = 0, densidadMin = 3, densidadMax = 5, altoMin = 44, altoMax = 80 },
}

PLAZA = { col = 1, fila = 2 }              -- verde, al lado del destino del barrio
LOTES_VACANTES = {
	{ col = 2, fila = 1 },                 -- ámbar: pegado al destino ámbar
	{ col = 1, fila = 0 },                 -- roja: escape de la zona densa
}
```

**Los tres hitos van alineados en la calle que sale del recinto** (X = `Grid.xDeCalle(1)`
= −620), uno por banda, en el centro de su fila:

| Zona | Posición | Alto | Material |
|---|---|---|---|
| verde | (−620, 681) | 30 | SmoothPlastic |
| ámbar | (−620, 535) | 50 | SmoothPlastic |
| roja | (−620, 389) | 80 | Neon |

Esto es el cambio de orientación más importante del plan y merece decir por qué: **al
salir del recinto se ven las tres, en fila, cada una más lejos y más alta.** De un vistazo
se sabe cuánto hay hasta cada zona sin leer nada. Hoy hay que deducirlo de una baliza
suelta. Van con `CanCollide = false` y 4–6 studs de ancho en una calle de 26: se pasa al
lado, no estorban.

`centroDeZona(zona)` se reescribe: `Vector3.new(Grid.xDeCalle(1), Grid.Y, centro de la
fila de esa zona)`.

- [ ] **Paso 1: aplicar los cambios**

- [ ] **Paso 2: build, Studio, y medir**

```lua
local c = workspace:FindFirstChild("Ciudad")
for _, h in c.Hitos:GetChildren() do
	print(h.Name, h.Position, h.Size.Y)
end
print("edificios:", #c.Edificios:GetChildren())
```

Esperado: tres hitos con X = −620 y Z ∈ {681, 535, 389}; entre 20 y 40 edificios (12
manzanas menos 3 solares = 9 con edificios, densidad 1–5).

- [ ] **Paso 3: comprobar a ojo con `screen_capture`**

Colocar la cámara en la boca del recinto mirando al sur. Se tienen que ver las tres torres
en fila. **Si no se ven, este es el momento de saberlo**, no después de tres tareas más.

- [ ] **Paso 4: formato, build y commit**

---

### Tarea 5: desmontar la ciudad prestada

**Ficheros:**
- Modificar: `default.project.json` — quitar el bloque `"Ciudad"`
- Modificar: `games/contrabando/mapa/LEEME.md` — dice que el `.rbxm` no se monta, y hasta
  ahora mentía; ponerlo al día
- Modificar: `CLAUDE.md` (raíz del repo) — la línea «Activo a 17/08: la ciudad del Creator
  Store» pasa a la retícula propia

El `.rbxm` **no se borra**: sigue en `mapa/` como respaldo, y §9 del spec explica por qué
revertir ya no es gratis.

`Main.server.luau:77` ya tiene el guard `if MapBuilder and workspace:FindFirstChild("Ciudad") == nil`,
así que al dejar de montarlo Rojo, el generador toma el relevo solo. **Ese guard no se
toca**: es lo que impide que se superpongan dos ciudades, y ya se pagó una vez.

- [ ] **Paso 1: quitar el bloque del `default.project.json`**

- [ ] **Paso 2: build y arrancar**

Esperado en consola: el resumen de `[MapBuilder]` y **una sola** `Ciudad` en `workspace`.

```lua
local n = 0
for _, m in workspace:GetChildren() do
	if m.Name == "Ciudad" then n += 1 end
end
print("ciudades:", n)   -- esperado: 1
```

- [ ] **Paso 3: recorrer las cuatro rutas con el pathfinder**

```lua
local PF = game:GetService("PathfindingService")
local Config = require(game.ReplicatedStorage.Shared.Config)
for _, r in Config.RUTAS do
	local p = PF:CreatePath()
	p:ComputeAsync(Config.POLIGONO_SALIDA, r.destino)
	local largo = 0
	local ws = p:GetWaypoints()
	for i = 2, #ws do largo += (ws[i].Position - ws[i-1].Position).Magnitude end
	print(r.id, p.Status, math.floor(largo))
end
```

Esperado: `Success` en las cuatro, y longitudes dentro del 15 % de 146 / 292 / 438 / 730.
**Si alguna da `NoPath`, parar aquí**: es el fallo que ya costó una sesión entera, y
arrastrarlo a la tarea 6 hace imposible saber cuál de los dos cambios lo rompió.

- [ ] **Paso 4: actualizar los dos documentos y commit**

---

### Tarea 6: enterrar el código que peleaba con el terreno ajeno

**Ficheros:**
- Modificar: `src/server/CityBuilder.luau`

Se borra:

| Qué | Por qué existía |
|---|---|
| `acceso()` y su envolvente de conos | tender camino sobre terreno irregular |
| `limitarDesdeExtremos()`, `SALTO_MAXIMO`, `LEVANTE_MAXIMO` | evitar escalones que cortan el navmesh |
| `asentar()` y `RESCATE_MAXIMO` | bajar lo que flotaba, subir lo enterrado |
| la cadena de rebotes de `sueloDeLaCiudad()` | saltarse las 2.048 copas de árbol del `.rbxm` |
| los usos de `Config.POLIGONO_ENGANCHE` | enganchar a una calle ajena |

`sueloDeLaCiudad()` **no se borra**: sigue habiendo edificios sobre los que no se debe
plantar. Se queda en un raycast único hacia abajo, sin la cadena de reintentos.

Lo que **no se toca** en esta tarea, aunque lo parezca: el orden de construcción. Los
contactos se siembran los últimos a propósito (una comisaría dejó 19 de 55 píldoras fuera
de alcance por sembrarlas antes), y ese orden sigue siendo correcto con suelo plano.

- [ ] **Paso 1: borrar, una función cada vez, compilando entre medias**

`..\..\tools\rojo.exe build --output contrabando.rbxl` después de cada borrado. Un borrado
que no compila señala un uso que no se vio en el grep.

- [ ] **Paso 2: contar lo que se ha ido**

```
git diff --stat src/server/CityBuilder.luau
```

Anotar el número en el commit: es el argumento de que el cambio de mapa se paga solo.

- [ ] **Paso 3: arrancar y correr `SelfCheck`**

Esperado: las 81 comprobaciones actuales en verde. Las que fallen por coordenadas de
destino se arreglan en la tarea 7; cualquier otra cosa roja **se arregla aquí**.

- [ ] **Paso 4: formato, build y commit**

---

### Tarea 7: `SelfCheck` aprende a comprobar la orientación

**Ficheros:**
- Modificar: `src/server/SelfCheck.luau`

**Consume:** `Grid` (tarea 1).

Cuatro comprobaciones nuevas, sobre el mundo ya construido:

1. **Cada destino, a dos giros o menos de la boca.** `Grid.giros` da 0 o 1 sobre la
   retícula; el listón se pone en 2 para dejar margen a que un edificio obligue a rodear
   una manzana. Es "no sé a dónde ir" convertido en prueba.
2. **Desde cada cruce se ve un hito de su zona.** Raycast desde el cruce (a altura de ojo,
   `Grid.Y + 5`) al hito de la banda; pasa si no hay obstrucción o si lo primero que toca
   es el propio hito. Listón: 90 % de los cruces.
3. **El suelo es plano donde se camina.** Recorrer las calles y comprobar que no hay salto
   de cota mayor de 0,5 studs entre piezas contiguas. Con retícula propia debe ser
   trivialmente cierto: si falla, hay un bug de generación.
4. **Las cuatro distancias de camino** están dentro del 15 % de 146 / 292 / 438 / 730,
   medidas con `PathfindingService`.

Y se **actualizan** las que dependen de coordenadas: la horquilla del barrio (hoy 90–220,
con el cruce nuevo el camino es 146 — sigue dentro) y las que citan destinos literales.

El guard de rutas con `guaridas = 0` / `refugios = 0` se queda: el barrio a 146 studs
sigue sin tramo útil para refugios (`REFUGIO_MARGEN_CASA = 85` + `REFUGIO_MARGEN_DESTINO =
55` ya suman 140), exactamente igual que hoy.

- [ ] **Paso 1: añadir las cuatro comprobaciones**

- [ ] **Paso 2: build, arrancar, correr `SelfCheck`**

Esperado: 85 comprobaciones, todas verdes.

- [ ] **Paso 3: romper una a propósito**

Mover a mano un hito 300 studs en `execute_luau` y volver a correr `SelfCheck`. Esperado:
la comprobación 2 se pone roja. **Una sonda que nunca se ha visto fallar no es una sonda,
es un adorno** — y este proyecto ya tuvo una (`asentar`) que no hacía nada durante horas.
Deshacer el movimiento después.

- [ ] **Paso 4: formato, build y commit**

---

### Tarea 8: documentación y cierre

**Ficheros:**
- Modificar: `games/contrabando/JUEGO.md` — tabla de rutas, distancias y ciclos
- Modificar: `games/contrabando/VERIFICACION.md` — las cuatro comprobaciones nuevas
- Modificar: `games/contrabando/mapa/DISENO-MAPA.md` — marcarlo como superado por el spec
  nuevo, con un enlace. **No se borra**: explica por qué se intentó una retícula de
  1600×1600 y qué se aprendió.
- Modificar: `games/contrabando/RUMBO.md` — cerrar el punto del mapa

- [ ] **Paso 1: actualizar los cuatro documentos con las distancias medidas**

No con las calculadas: con las que devolvió el pathfinder en la tarea 5. `JUEGO.md` ya
mintió una vez sobre las distancias (decía 250/420/848/1399 cuando eran
386/622/1039/1682) y costó una discusión entera.

- [ ] **Paso 2: pasada completa de verificación**

```
..\..\tools\stylua.exe --check src
..\..\tools\rojo.exe build --output contrabando.rbxl
```

Y en Studio: `TestRunner` (~800 casos) y `SelfCheck` (85). Los dos en verde.

- [ ] **Paso 3: commit y push**

- [ ] **Paso 4: decirle a JJ que entre a jugar**

Con una pregunta concreta, no "a ver qué te parece": **al salir del recinto, ¿sabes a
dónde vas sin leer nada?** Es la única de las tres quejas que este plan puede contestar
por sí solo; "no pasa nada por el camino" es el trabajo siguiente y necesita su propio
diseño.
