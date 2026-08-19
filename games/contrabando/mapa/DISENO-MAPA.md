# Diseño del mapa procedural

> **SUPERADO el 19/08 por
> [`../docs/specs/2026-08-19-mapa-propio-design.md`](../docs/specs/2026-08-19-mapa-propio-design.md).**
> Este documento diseñó una cuadrícula de 1600x1600 centrada en (0,0) para las
> posiciones que el juego tenía entonces. El 19/08 el mundo se encogió a la mitad y el
> almacén quedó **fuera** de ese cuadrado, así que la geometría de aquí ya no describe
> nada que exista. Se conserva porque el razonamiento sigue siendo el bueno --por qué
> generar en vez de heredar, qué aporta el carácter por zona, por qué la estética va la
> última-- y porque el generador que describe es el que se reescribió, no otro.
>
> Lo que cambió en el spec nuevo: la retícula se alinea a los puntos fijos del juego en
> vez de al revés, las zonas van por bandas y no en diagonal, y el plano se extrajo a
> `src/shared/Grid.luau` para que Config y SelfCheck beban de la misma fuente.

> 2026-08-17. Supersede la sección 3 de [`DISENO-CIUDAD.md`](DISENO-CIUDAD.md): en vez de
> montar un `.rbxm` del Creator Store, **generamos la ciudad por código**. El resto del
> spec (zonas, calor, detectores, robo) sigue vigente tal cual.
>
> Lo que responde este documento: cómo se construye el mapa, qué decisiones hace el
> generador y por qué, y qué partes se dejan para iteración posterior.

---

## 1. Por qué un mapa procedural

El `2701703521` resolvía un problema real (ver `DISENO-CIUDAD.md` §3 y `src/assets/LEEME.md`):
tenía 0 meshes, 0 scripts, 7152 piezas y cabía la geometría del juego. Adoptarlo fue la
decisión correcta **mientras no se hubiera validado si la ciudad como mecánica funcionaba**.
Tras la primera partida jugada con la carretera quedó claro que el problema no era la
estética: era la falta de un mapa con **carácter por zona**, y eso es justo lo que un mapa
genérico no te da gratis.

Generar el mapa por código resuelve cuatro cosas a la vez:

1. **Cero dependencia binaria.** `src/assets/Ciudad.rbxm` deja de existir; cualquier clon del
   repo arranca igual en cualquier máquina.
2. **Carácter por zona, no por herencia.** El generador sabe dónde está la verde, la ámbar y
   la roja, y planta cada una con su densidad, altura de edificios y ancho de calle. Un mapa
   genérico te obliga a "buscar" la zona buena para tu juego.
3. **Trazabilidad.** Todo cambio en el mapa es un diff en un `.luau`, no un re-import en
   Studio que puede traer scripts ajenos.
4. **Aprendizaje del jugador.** Las posiciones de los detectores, los cuellos de botella y
   los callejones están fijados por una semilla. Eso es lo que permite que un jugador
   reconozca "el cruce malo de la roja" y lo rodee — la habilidad que el viaje tenía que
   pedir y no pedía.

## 2. Lo que NO cambia

Por la regla de oro de `DISENO-CIUDAD.md` §2: **ni una regla del juego depende del mapa**.
Esto se mantiene:

- La economía: caja = 10 monedas, multiplicadores por rareza, valores de entrega.
- El almacén: produce con tope, no es asaltable nunca, cálculo offline.
- Los vehículos: progresión por capacidad y acceso, jamás por potencia.
- El robo: fracción, marcado, zona segura, herencia de ruta.
- El calor y las patrullas: detectores radio 35 studs, `PathfindingService` para perseguirlas.
- El bucle: recoger → elegir → viajar → cobrar → invertir.

El mapa entra como un `Model` en `workspace` con el nombre **`Ciudad`** (por compatibilidad
con `CityBuilder.luau`, que ya lo busca). La forma de las manzanas, los edificios y las
calles cambia; lo que el juego mide sobre ellas no.

## 3. Estructura

### Tamaño y cuadrícula

| | |
|---|---|
| Extensión total | **1600 × 1600 studs** |
| Manzanas | **6 × 6 = 36** |
| Manzana | 240 × 240 studs |
| Calle | 32 studs de ancho (uniforme en fase 1; se varía por zona en fase 2) |
| Altura de calle | y = 0.5 (asfalto) |
| Altura de acera | y = 2.0 (losa) |
| Origen | (0, 0, 0) en el centro del mapa |

La elección de 1600×1600 y de 6×6 sale de cuadrar las posiciones que ya tienen los puntos
fijos del juego en `Config.luau` (almacén en `(-653, 21.8, 710)`, destinos en `(-180, 19,
540)`, `(240, 14.8, 420)` y `(600, 19.2, -180)`). Con 1500 studs el almacén quedaba a
40 studs del borde, demasiado cerca para la zona segura de 80 studs. Con 1600 hay 47
studs de margen y todo cabe holgadamente.

### Las tres zonas

Las zonas se reparten como una "L" con la verde en el SO, la ámbar en el centro y la roja
en el NE, igual que en la versión con el `.rbxm`. Esto preserva la asimetría que el diseño
original documentó: la roja está más lejos y, además, queda al otro lado de una zona de
manzanas más densas, lo que ya de por sí añade un cuello de botella natural.

| Zona | Posición | Manzanas | Densidad | Altura edificios | Calles | Callejones | Solares |
|---|---|---|---|---|---|---|---|
| 🟢 Verde | SO | 2×2 (4) | **1-2** edificios/manzana | 10-25 (1-2 plantas) | anchas (30) | 0 (la **plaza** es la escapatoria) | 1 (la plaza) |
| 🟡 Ámbar | Centro | 2×4 (8) | **2-3** edificios/manzana | 25-50 (2-4 plantas) | medias (25-30) | 1-2 por fila | **1** (corredor ámbar→roja) |
| 🔴 Roja | NE | 2×2 (4) | **3-5** edificios/manzana | 50-100 (4-8 plantas) | estrechas (15-20) | múltiples por fila | **1** (salida de la densa) |

**Solares**: manzanas vacías en ámbar y roja, el mismo papel mecánico que la plaza en
verde pero con función de **vía de escape** (no de atajo de aprendizaje). Posiciones
actuales, fijas a propósito para que sean aprendibles:

- 🟡 `(col=2, fila=2)` — corredor diagonal entre el destino ámbar y la roja.
- 🔴 `(col=4, fila=1)` — frontera roja-ámbar, salida natural si una patrulla cierra
  las calles de la zona densa.

La patrulla va atada a las calles y no puede cruzar el solar en diagonal; el jugador
sí. Si la partida jugada muestra que la patrulla entra al solar o que el jugador lo
descubre demasiado tarde, se cambia la coordenada y se vuelve a jugar — el mismo
flujo que con la plaza.

La densidad es ahora un **rango por zona**, no un número fijo: cada manzana tira los dados
con la semilla fija, así que el resultado es **estable entre partidas** pero **distinto entre
manzanas**. Lo que se gana con esto es que mirar el mapa desde arriba no parece un patrón
repetido — el ojo distingue "una zona más densa" sin tener que contar piezas.

### Puntos fijos del juego

Estos los sigue colocando `CityBuilder.luau` por código, sobre el mapa procedural:

- **Almacén** en `Config.ALMACEN_POS = (-653, 21.8, 710)` — esquina SO.
- **Taller** en `Config.TALLER_POS = (-653, 21.8, 600)` — junto al almacén, dentro de la
  zona segura.
- **Destinos** en las coords de `Config.RUTAS` — uno por zona.
- **Balizas** sobre los destinos, para orientarse desde lejos.
- **Detectores** en sitios fijos con semilla por ruta (lo que ya hace `CityBuilder`).

El generador **no debe tocar esas posiciones** — si una cae en mitad de un edificio, el
edificio se recorta o se omite en esa manzana. La geometría del juego manda sobre la
estética.

## 4. Cómo se construye

El generador vive en `src/server/MapBuilder.luau` y expone una sola función:

```lua
function MapBuilder.buildCiudad(padre: Instance): Model
    -- Crea un Model "Ciudad" con calles, aceras, edificios, plazas.
    -- Devuelve el Model para que CityBuilder lo use como suelo.
end
```

`Main.server.luau` lo llama antes de `CityBuilder.build()`, igual que cargaba el `.rbxm`
antes. La interfaz es deliberadamente compatible con el contrato existente: el `Model`
resultante se busca con `workspace:FindFirstChild("Ciudad")`, así `CityBuilder` no cambia.

### Algoritmo (fase 1 + fase 2)

1. **Crear el suelo base**: una cuadrícula de 4 piezas de 800×800 a `y=0`. Es la red de
   seguridad por si un raycast falla. El asfalto y las aceras van por encima.
2. **Plantar la cuadrícula de calles y aceras** en una pasada. Las calles se subdividen
   en segmentos (límite de 2048 por eje ya pagado en `CityBuilder.luau`).
3. **Para cada zona, plantar sus manzanas con sus edificios**:
   - **La plaza** de la verde (`col=1, fila=4`) se planta sin edificios: sólo suelo y
     aceras, queda como un rectángulo vacío enmarcado por la calle.
   - **Densidad por rango** (`rng:NextInteger(densidadMin, densidadMax)`) por zona, con
     la **misma semilla fija** (`7891`) para que cada partida tenga el mismo mapa. La
     variabilidad es por manzana, no por sesión.
   - **Plantar en fila** cuando la densidad es > 1: los edificios se reparten el ancho
     de la manzana con huecos de `GAP_ENTRE_EDIFICIOS = 10` studs. Esos huecos son los
     **callejones visibles** desde arriba y los pasos por donde la patrulla no cabe.
   - **Orientación de la fila** (X o Z) determinista por `(col, fila)`, así los
     edificios de una misma manzana están alineados y los callejones no se entrecruzan.
4. **Validar que los puntos fijos del juego no caen dentro de un edificio**. Si caen, el
   edificio se omite — y se avisa con `warn`, porque alguien tendrá que mirar por qué.

### Colores y materiales (fase 1)

Cubos de colores a propósito. La estética se elige después, con datos de si el bucle
engancha. Paleta mínima:

| | Color | Material |
|---|---|---|
| Calle | `Color3.fromRGB(46, 48, 54)` | SmoothPlastic |
| Acera | `Color3.fromRGB(140, 138, 132)` | SmoothPlastic |
| Edificios verdes | `Color3.fromRGB(120, 132, 96)` y variantes | SmoothPlastic |
| Edificios ámbar | `Color3.fromRGB(118, 110, 96)` y variantes | SmoothPlastic |
| Edificios rojos | `Color3.fromRGB(86, 88, 102)` y variantes | SmoothPlastic |
| Suelo base | `Color3.fromRGB(40, 40, 45)` | SmoothPlastic |

## 5. Lo que entra y lo que no (estado por fase)

### Fase 1 — Foundation (✅ hecho)

- Cuadrícula 6×6 con 3 zonas.
- Calles, aceras, edificios básicos.
- Suelo base de respaldo (red de seguridad).
- Validación de que los puntos fijos del juego no quedan encerrados.
- Compila, carga en Studio, el jugador puede caminar por las 3 zonas.

### Fase 2 — Carácter (✅ hecho)

- **Plaza en la zona verde** — manzana vacía enmarcada, atajo visible.
- **Densidad por rango** en vez de número fijo (1-2 / 2-3 / 3-5 según zona).
- **Plantar en fila** cuando la densidad es > 1, con `GAP_ENTRE_EDIFICIOS = 10` studs entre
  edificios. **Callejones visibles** desde arriba y desde el suelo.
- **Orientación de la fila** determinista por `(col, fila)`, así los callejones de una
  misma manzana son paralelos.

### Fase 2.5 — Solares (✅ hecho)

- **2 solares en ámbar y roja** — manzanas vacías como vías de escape. La patrulla
  va atada a las calles y no puede cruzarlos en diagonal; el jugador sí. Posiciones
  fijas (aprendibles) elegidas a mano: ámbar `(2,2)`, roja `(4,1)`.
- La **validación de puntos fijos** se aplica también a los solares, pero no retira
  nada porque no hay edificios.

### Fase 3 lite — Hitos + verificación (✅ hecho)

- **3 hitos de zona** (uno por zona) en el centro visual de cada una, donde
  convergen 4 calles. NO son estética — son **mecánica de navegación**: el jugador
  ve el hito desde lejos y sabe en qué zona está. Material SmoothPlastic para
  verde y ámbar (discretos), Neon para la roja (faro funcional, visible desde el
  otro extremo del mapa). Tamaños 30/50/80 studs.
- **Resumen de build impreso al construir**: edificios por zona, solares, hitos. Lo
  ve JJ en la consola de Studio y verifica de un vistazo que la semilla y las
  densidades están dando lo que esperaba.
- **Verificación de conectividad vía `PathfindingService`**: desde cada solar al
  almacén, dentro de `pcall` para no romper el arranque si falla. Detecta
  **callejones sin salida** antes de jugar, no en mitad de una ronda.

### Fase 4 — Estética (sigue pendiente, **NO entra hasta que el bucle enganche**)

- Calles con ancho variable por zona.
- Iluminación urbana (farolas, ventanas).
- Letreros o rótulos en edificios.
- Variación de tejados (azoteas, antenas, etc.).
- Optimización (chunking, LOD, etc.).
- Paleta y materiales definitivos.

## 6. Cómo sabremos si funciona

Igual que con el resto del proyecto: **jugando**. El criterio es el mismo que
`DISENO-CIUDAD.md` §6:

1. JJ entra al juego con el mapa procedural cargado.
2. **Camina por la verde**: ¿la plaza se nota como atajo, no como terreno vacío sin más?
3. **Camina por la ámbar**: ¿los callejones se notan como tales, no como "calle rara"?
   ¿El solar de `(2,2)` se ve como una vía de escape real si una patrulla te pisa
   los talones?
4. **Camina por la roja**: ¿se siente denso y vigilado? ¿se ven los callejones como pasos
   de evasión reales? ¿la patrulla los usa o va siempre por la calle principal? ¿El
   solar de `(4,1)` es la salida natural cuando te acorralan?
5. **Tira la legendaria y elige la roja** (criterio DISENO.md §3): ¿el haz de luz +
   los callejones + los solares + las patrullas suman la tensión que la decisión
   pide, o son cuatro elementos sueltos que no enganchan juntos?

Si la fase 2.5 falla en alguno de estos, fase 3 ataca eso antes que la estética. La estética
sólo se trabaja **después** de medir si el bucle engancha, y no antes.

## 7. Riesgos conocidos

- **2048 studs por eje**: ya pagado. Los segmentos de calle se subdividen.
- **El personaje R6**: ya resuelto en `Avatar.luau`. Sin meshes descargables, un R15 es un
  fantasma. El mapa procedural no usa meshes, así que el problema no empeora.
- **Rendimiento**: 36 manzanas × 3-4 edificios = ~120 piezas. Más calles y aceras. Total
  estimado **< 500 piezas** para el mapa entero — muy por debajo de las 7152 del `.rbxm`
  y de los límites de un servidor medio.
- **Que el almacén quede encerrado**: se valida tras generar; si pasa, se omite el
  edificio conflictivo y se avisa.
- **Que los detectores que planta `CityBuilder` caigan dentro de un edificio**: el
  `sueloDeLaCiudad()` actual ya hace raycast, así que si el detector cae sobre un edificio,
  lo plantará **encima** del edificio. En fase 1 se documenta el caso y en fase 2 se ajusta
  la semilla de detectores para esquivar edificios. La regla innegociable es que el poste
  SIEMPRE toque suelo real, no el tejado de un edificio.

## 8. Reversibilidad

El mapa procedural **reemplaza** al `.rbxm` en `default.project.json`. Si por la razón que
sea la fase 1 no convence:

- Revertir es **un cambio de 4 líneas** en `default.project.json` y borrar la llamada a
  `MapBuilder.buildCiudad` en `Main.server.luau`.
- El `.rbxm` no se borra del disco durante esta fase, sólo deja de montarse.
- El coste de mantener ambas opciones durante una semana es ~10 líneas; el coste de
  empezar a invertir en una y descubrir que la otra era mejor es un sprint perdido.

Por eso la fase 1 es **mínima y reversible**, no bonita.
