# Proyecto: juegos en Roblox

Investigación de viabilidad + piloto de aprendizaje + desarrollo del primer juego con
intención comercial. **Tiene repo git propio** (https://github.com/jotajota1302/roblox);
el resto de carpetas de `IDEAS/` no. Nunca hagas `git init` en la raíz de `IDEAS/`: hay
`.env` con credenciales de otros proyectos.

## Estructura del repo

Un repo, varios juegos. En la raíz sólo vive lo que sirve a todos:

```
RESEARCH.md MERCADO.md TARGETS.md    Análisis transversal, no de un juego concreto
setup.ps1                            Descarga rojo + stylua + docs oficiales
tools/ creator-docs/                 Compartidos, no versionados
games/
├── coin-island/                     Piloto de aprendizaje (terminado)
└── contrabando/                     Juego con intención comercial
    ├── DISENO.md                    Spec: la autoridad de ese juego
    ├── docs/plans/                  Planes de implementación
    └── src/                         Código
```

**Un juego nuevo es una carpeta nueva en `games/`**, con su propio spec dentro. Lo de la
raíz no se duplica por juego.

## Documentos clave (léelos antes de proponer nada)

Se leen en este orden, cada uno responde a una pregunta:

1. `RESEARCH.md` — **¿se gana dinero?** Economía real, distribución de ingresos, herramientas.
2. `MERCADO.md` — **¿qué formato?** Géneros, saturación, benchmarks de retención.
3. `TARGETS.md` — **¿qué juego?** Anatomía de los éxitos y los 3 conceptos candidatos.
4. `games/contrabando/DISENO.md` — el spec del juego en desarrollo.
5. `games/coin-island/README.md` — el piloto y cómo funciona Roblox por dentro.

## Decisiones tomadas (no reabrir sin preguntar)

- **El criterio de éxito es la retención, no el dinero.** D1 <15% → pivotar. 20-30% → iterar.
  >35% con sesión >8 min → invertir. Todo lo demás es secundario.
- **Target elegido: rutas de contrabando** (target B de `TARGETS.md`). Bucle de progresión
  jugable en solitario + intercepción entre jugadores como capa social.
- **Nada de IA generativa en tiempo de ejecución.** Pierde entre 10 y 60 veces lo que
  ingresa por jugador y empeora con el éxito (`MERCADO.md`, sección 6). La IA se usa en
  producción, nunca en la partida.
- **Nada de narrativa como motor.** Una historia se juega una vez; hunde D1/D7.
- **No reutilizar material de `crime/` ni de `rpg-narrativo/`.** Decisión explícita de JJ:
  quiere que este proyecto se evalúe por sí mismo.
- Iterar rápido y pivotar con datos, no con corazonadas. Los criterios de kill están en
  `TARGETS.md`, sección 7.

## Generación de assets: qué herramienta para qué

| Necesidad | Herramienta | Por qué |
|---|---|---|
| **Modelos 3D** (objetos, vehículos, decorado) | **Cube 3D de Studio** (`generate_mesh` vía MCP) | Devuelve MeshParts ya usables y texturizados, y pasa la moderación de Roblox automáticamente. Probado: un baúl con correas y herrajes en ~1 min con 3.000 triángulos |
| **Materiales / texturas de superficie** | `generate_material` (MCP) | Genera MaterialVariant nativos |
| **Modelos paramétricos ajustables** | `generate_procedural_model` (MCP) | Primitivas con atributos editables sin regenerar |
| **Miniatura e icono del juego** | **MiniMax** (`image-01`) | Es 2D y es **marketing**: decide el CTR en el Discover, que es el cuello de botella real del proyecto. Estilo saturado y llamativo, no arte de portada |
| **Iconos de inventario y UI** | **MiniMax** | 2D puro. El pipeline del RPG narrativo es transferible |
| **Vídeo promocional (TikTok / Shorts)** | **Grabar gameplay real**, no generar | La gente quiere ver el juego. El vídeo generado aporta poco aquí |

**Momento de hacer arte: cuando D1 lo justifique, no antes.** Durante el prototipo, cubos
de colores. Ponerse con los assets pronto es la forma más común de sentir que se avanza sin
responder a la única pregunta que importa.

## Convenciones

- **Comentarios en español** en este proyecto (a diferencia del RPG narrativo, que van en
  inglés): el código es también material de aprendizaje. Identificadores en inglés.
- Sin dependencias externas salvo necesidad clara.
- El mundo y la interfaz **se generan por código**, no a mano en Studio. Así todo vive en
  git y es revisable en un diff; el `.rbxl` es un artefacto desechable.
- Diseño **móvil primero**: tamaños en Scale con `UISizeConstraint`, contenido desplazable,
  botones de 48px mínimo, y nada en las esquinas inferiores (son del joystick y del botón
  de salto de Roblox). Verificar con la skill `rbx-device-simulator-lua` antes de dar por
  buena cualquier pantalla.

## Flujo de trabajo

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1   # rojo + stylua + docs (todo en ./tools)
cd games\<juego>
..\..\tools\rojo.exe serve                           # y Connect desde el plugin de Studio
```

**Verificación obligatoria antes de dar algo por hecho:**

```powershell
..\..\tools\stylua.exe --check src    # 0 = sintaxis y formato limpios
..\..\tools\rojo.exe build            # que compile
```

Y **probarlo dentro de Studio** con el MCP. Que compile no significa que funcione: el peor
fallo de este proyecto compilaba perfectamente.

## MCP de Roblox Studio

Activado en scope user. `list_roblox_studios` para el `studio_id`, luego `execute_luau`
(datamodel `Edit` / `Server` / `Client`), `start_stop_play`, `search_game_tree`,
`screen_capture`.

Avisos verificados:

- **`get_console_output` se cuelga y da timeout.** No usarlo; diagnosticar con
  `execute_luau` inspeccionando el estado.
- **`require()` dentro de `execute_luau` NO comparte estado con el servidor real** (corre en
  un sandbox aparte). Para verificar hay que actuar sobre el mundo (mover partes, disparar
  remotes) y leer el resultado, no llamar a los módulos.
- Los setters del simulador de dispositivos **fallan en PlayServer**: fijar el dispositivo
  antes de entrar en Play.
- Para medir la interfaz, comparar contra el área real del `ScreenGui`, **nunca** contra
  `Camera.ViewportSize`: con el simulador activo no coinciden (el inset desplaza el origen)
  y salen falsos positivos.
- Y en la misma medición, restar `gui.AbsolutePosition` a la posición de cada hijo. Con
  `ScreenInsets = DeviceSafeInsets` el origen del `ScreenGui` no es (0,0) sino algo como
  (0,−58), así que todo lo colocado arriba parece salirse de pantalla sin estarlo.

## Trampas de Roblox ya pagadas

- **`DataStoreService:GetDataStore()` LANZA una excepción** si el place no está publicado.
  Llamarlo al cargar un módulo hace que el `require()` reviente y **mata el script entero**:
  juego sin mapa, sin personaje y sin pista del motivo. Todo lo que pueda lanzar va perezoso
  y dentro de `pcall`.
- **`MeshPart.MeshId` NO se puede escribir en tiempo de ejecución.** `Instance.new("MeshPart")`
  seguido de `m.MeshId = "rbxassetid://…"` falla con *"lacking capability NotAccessible"*:
  MeshId sólo se escribe desde Studio o un plugin. En un servidor hay que pedir la pieza a
  `AssetService:CreateMeshPartAsync(meshId)`; sobre el resultado, `TextureID` y `Size` sí se
  asignan con normalidad. Y como esa llamada espera al servidor de assets, **nunca va en el
  camino de arranque**: primero el mundo jugable, el decorado después en otro hilo.
- **El personaje aparece antes de que tu código construya el mundo.** Si generas el mapa por
  código, usa `Players.CharacterAutoLoads = false` durante el arranque.
- Un `require` que falla se propaga: protege los del punto de entrada.
- Los emojis en `TextLabel` suelen salir como `□`. No usarlos.

## Regla de oro

**El bucle antes que el contenido, y los datos antes que el bucle.** Si algo no se puede
medir en D1 o en sesión media, no es una prioridad.
