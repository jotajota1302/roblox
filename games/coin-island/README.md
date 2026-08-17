# Isla de Monedas — piloto para entender Roblox

Juego mínimo pero **completo y real**: mundo 3D, multijugador, economía, tienda,
guardado en la nube y dos productos de pago. ~700 líneas de Luau muy comentadas.

No es un juego para ganar dinero (ver [`../RESEARCH.md`](../RESEARCH.md) para por qué).
Es un juego para que en una tarde entiendas **cómo está montado** cualquier juego de Roblox.

Particularidad a propósito: **el mapa y la interfaz se generan por código**, no a mano en
Studio. Así todo vive en git, se puede revisar en un diff y cambiar un número aquí cambia
el juego al instante. El fichero `.rbxl` de Studio queda vacío y es desechable.

---

## 1. Qué enseña cada fichero

| Fichero | Concepto de Roblox que ilustra |
|---|---|
| `default.project.json` | Cómo Rojo mapea carpetas del disco a los **servicios** de Roblox |
| `src/shared/Config.luau` | ModuleScript, `require()`, `ReplicatedStorage` (lo ven cliente y servidor) |
| `src/shared/Remotes.luau` | **RemoteEvent**: la única forma de que cliente y servidor hablen |
| `src/server/Main.server.luau` | Punto de entrada del servidor y orden de arranque explícito |
| `src/server/WorldBuilder.luau` | Crear el mundo 3D por código: `Part`, `Vector3`, `Anchored`, `SpawnLocation` |
| `src/server/PlayerData.luau` | **DataStore** (guardado en la nube), `leaderstats`, `pcall`, `BindToClose` |
| `src/server/CoinService.luau` | `.Touched`, **debounce**, `RunService.Heartbeat`, `task.delay`, atributos |
| `src/server/ShopService.luau` | **Seguridad**: validar todo lo que manda el cliente. El fichero más importante |
| `src/server/MonetizationService.luau` | Game passes, developer products, `ProcessReceipt` idempotente |
| `src/client/Main.client.luau` | LocalScript: código que corre en la máquina del jugador |
| `src/client/Ui.luau` | Interfaz por código: `ScreenGui`, `UDim2`, `UIListLayout` |

### Las 3 ideas que hay que llevarse

1. **Cliente y servidor son dos máquinas distintas.** No comparten variables. Solo se
   hablan por RemoteEvents. `Players.LocalPlayer` existe en el cliente y es `nil` en el
   servidor.
2. **El cliente miente.** Un jugador con un exploit ejecuta lo que quiera en su máquina.
   Por eso el servidor calcula el precio, comprueba el saldo y decide. Ver
   `ShopService.luau`: el cliente solo manda `"speed"`, nada más.
3. **Casi todo es un objeto en un árbol.** El mundo (`Workspace`), la interfaz, los datos:
   todo son instancias con propiedades, hijos y eventos.

---

## 2. Puesta en marcha

### Paso 1 — Instalar Roblox Studio (lo único que no puedo hacer yo)

Descárgalo de <https://create.roblox.com/> → botón **Start Creating**. Necesitas una cuenta
de Roblox. El instalador pesa poco y tarda un par de minutos.

### Paso 2 — Herramientas

Ya están descargadas en `../tools/` (rojo.exe, stylua.exe, Rojo.rbxm). Si algún día
clonas el repo en otro sitio:

```powershell
powershell -ExecutionPolicy Bypass -File ..\setup.ps1
```

### Paso 3 — Instalar el plugin de Rojo en Studio

El plugin es lo que deja que Studio reciba los cambios que guardas en VS Code.

1. Abre Studio → pestaña **Plugins** → botón **Plugins Folder**. Se abre una carpeta
   (normalmente `%LOCALAPPDATA%\Roblox\Plugins`).
2. Copia ahí el fichero `../tools/Rojo.rbxm`.
3. Cierra y vuelve a abrir Studio. Debe aparecer un botón **Rojo** en la pestaña Plugins.

> Alternativa: en Studio, **Toolbox → Creator Store → Plugins**, busca "Rojo" y dale a
> Install. Es el mismo plugin.

### Paso 4 — Arrancar el servidor de Rojo

En una terminal, desde la carpeta `coin-island`:

```powershell
..\tools\rojo.exe serve
```

Déjala abierta. Dirá algo como `Rojo server listening on port 34872`.

### Paso 5 — Conectar Studio

1. En Studio: **File → New** (plantilla Baseplate).
2. Pestaña **Plugins → Rojo → Connect**.
3. El árbol del juego se llena solo con nuestras carpetas (`Server`, `Client`, `Shared`).

A partir de aquí: **guardas en VS Code → aparece en Studio al instante.**

### Paso 6 — Jugar

Pulsa **Play** (F5). Deberías ver la isla, monedas girando, el contador arriba a la
izquierda y el botón de tienda abajo a la derecha.

> Verás un aviso en la consola sobre el DataStore. Es normal: Studio no puede guardar en la
> nube hasta que publiques el juego y actives
> **Game Settings → Security → Enable Studio Access to API Services**. El juego funciona
> igual, simplemente no recuerda tu progreso entre sesiones.

---

## 3. Cosas para tocar y ver qué pasa

Todas están en `src/shared/Config.luau`, cambias un número y guardas:

| Cambia | Qué observas |
|---|---|
| `COIN_COUNT = 200` | Rendimiento: el servidor mueve 200 monedas por fotograma |
| `COIN_RESPAWN_SECONDS = 0.5` | El bucle de juego se vuelve frenético. ¿Es más divertido o menos? |
| `ARENA_SIZE = 60` | Mapa pequeño: las monedas se agolpan. El tamaño **es** diseño |
| `BASE_WALK_SPEED = 50` | Por qué la velocidad base de Roblox es 16 y no otra |
| `UPGRADES[1].baseCost = 1` | Economía rota: todo se compra en 20 segundos y te aburres |

Y un experimento que enseña lo de la seguridad mejor que cualquier explicación: intenta
darte monedas desde el cliente. Añade en `Ui.luau` algo como `state.coins = 999999` antes
de `refresh()`. Verás 999999 en pantalla... y al comprar, el servidor te lo negará, porque
él sabe la verdad.

---

## 4. Publicar el juego

1. En Studio: **File → Publish to Roblox As...**
2. Nombre, descripción, y **Create**.
3. Para que otros entren: web de Roblox → **Creations** → tu juego → pestaña
   **Configure → Permissions → Public**.

Es gratis, inmediato y sin revisión previa. A partir de ese momento cualquiera puede jugar.

---

## 5. Activar el dinero de verdad

El código de monetización ya está escrito, solo faltan los IDs (hay que publicar antes):

**Game pass "x2 monedas"**
1. Web de Roblox → **Creations** → tu juego → **Monetization → Passes → Create a Pass**.
2. Ponle nombre, precio en Robux y guarda.
3. Entra en el pase, copia el número del **ID** (está en la URL).
4. Pégalo en `Config.GAME_PASS_ID`.

**Developer product "+100 monedas"**
1. Mismo sitio → **Monetization → Developer Products → Create**.
2. Copia el ID y pégalo en `Config.PRODUCT_ID`.

Con eso, los botones de la tienda abren la ventana de compra real de Robux.

**Recordatorio de la economía** (detalle en `../RESEARCH.md`): de cada 100 Robux que
gasta un jugador tú cobras 70, y esos 70 Robux valen ~0,27 $ al cambiarlos por dinero real.
Necesitas 30.000 Robux ganados (= 114 $) para poder hacer tu primer cobro.

---

## 6. Chuleta de servicios de Roblox

| Servicio | Para qué | ¿Quién lo ve? |
|---|---|---|
| `Workspace` | El mundo 3D | Todos |
| `ServerScriptService` | Código de servidor | Solo servidor |
| `ReplicatedStorage` | Datos y remotes compartidos | Ambos |
| `StarterPlayer.StarterPlayerScripts` | Código de cliente | Se copia a cada jugador |
| `StarterGui` | Interfaz de partida | Se copia a cada jugador |
| `Players` | Lista de jugadores, eventos de entrada/salida | Ambos |
| `DataStoreService` | Base de datos persistente | Solo servidor |
| `MarketplaceService` | Compras con Robux | Ambos |
| `RunService` | Bucle de fotogramas (`Heartbeat`) | Ambos |

Sufijos de fichero que interpreta Rojo:

| Fichero | Se convierte en |
|---|---|
| `Foo.luau` | ModuleScript (código que otros cargan con `require`) |
| `Foo.server.luau` | Script (servidor) |
| `Foo.client.luau` | LocalScript (cliente) |

---

## 7. Comandos útiles

```powershell
..\tools\rojo.exe serve                      # desarrollo: sincroniza con Studio
..\tools\rojo.exe build -o juego.rbxl        # empaqueta el juego en un fichero
..\tools\stylua.exe src                      # formatea todo el Luau
..\tools\stylua.exe --check src              # verifica formato y sintaxis (0 = limpio)
```
