# Textos centralizados y multiidioma

> 2026-08-19. Diseño acordado con JJ tras preguntar *"¿podemos preparar todos los textos para
> el multiidioma? ¿o esto cómo funciona en Roblox?"*.

---

## 1. El problema

Hoy los ~130 textos que lee el jugador están **escritos a mano allí donde se pintan**: 13
ficheros de cliente y 8 de servidor. Eso produce dos daños distintos, y el segundo es el que
motivó esta tanda.

**El daño de hoy: idiomas mezclados.** Se tradujo el juego al inglés el 18/08 recorriendo los
ficheros a mano, y el 18/08 por la noche JJ vio castellano en pantalla. Se parcheó. Al hacer
el inventario para este diseño aparecieron **nueve textos más en castellano** que aquel repaso
no cazó:

| Dónde | Texto |
|---|---|
| `Stock.luau:115` | `"Cargar"` |
| `Main.client.luau:490` | `"Oficina"` |
| `Garage.luau:220` | `"%d huecos"` |
| `InterceptService.luau:129` | `"Te vienen detras"` |
| `WarehouseService.luau:30-31` | `"No te llega el dinero"`, `"Tu nave ya esta al maximo"` |
| `WarehouseService.luau:38` | `"Ya has elegido ruta: esto se entrega en su destino"` |
| `WarehouseService.luau:359` | `"No se puede mejorar"` |
| `Goods.luau:228` | `"Bulto"` |
| `CityBuilder.luau:1610,1826,1962` | `"GUARIDA"`, `"Oficina"`, `"Concesionario"` |

Un repaso a mano no puede cerrar esto: **mientras el texto viva en 21 ficheros, la próxima
línea que se escriba puede volver a salir en el idioma equivocado y nadie lo sabrá hasta
jugar**. La cura no es otro repaso, es que sólo haya un sitio donde escribir texto.

**El daño de mañana: no se puede traducir.** Ver §2.

## 2. Cómo funciona la localización en Roblox

Tres piezas, y ninguna la escribimos nosotros:

- **Tabla de localización en la nube.** Vive en el panel del creador. Una fila por texto:
  clave, original, y una columna por idioma.
- **Captura automática de texto.** Se activa en el portal y recoge sola los textos que
  aparecen en GUIs mientras la gente juega.
- **Traducción automática.** Máquina, gratis, ~15 idiomas, se activa por idioma.

En tiempo de juego, todo `GuiObject` con texto tiene `AutoLocalize = true`: si su cadena
coincide con una fila de la tabla, el motor la sustituye por la traducción del jugador **sin
que el código se entere**. El idioma sale de la cuenta del jugador, no de un ajuste nuestro.
Para lo que no es un rótulo fijo está `LocalizationService:GetTranslatorForPlayerAsync` →
`translator:FormatByKey("clave", { monedas = 250 })`.

**Y aquí está el problema con nuestro código.** El mecanismo automático casa **cadenas
enteras**. Nuestros textos casi nunca lo son:

| | Cuántos | ¿Se traduciría solo? |
|---|---|---|
| Rótulos fijos en pantalla y carteles 3D | 28 | **Sí**, tal cual |
| Textos con números (`"+%d for %d items on %s"`) | ~34 | **No.** Cada combinación de cifras sería una fila distinta |
| Avisos compuestos en el servidor (`"You take out " .. def.nombre`) | 44 | **No**, mismo motivo |
| Nombres de catálogo (vehículos, mercancías, rutas, nave) | 51 | Sueltos sí; pegados a una frase, no |

Publicar hoy y encender la traducción automática traduciría **alrededor de un tercio** del
juego. Es decir: reproduciría el bug de idiomas mezclados, pero a escala y en quince idiomas.

## 3. La decisión

Un módulo único, `src/shared/Strings.luau`, con **todos** los textos del jugador, y parámetros
con nombre en vez de `%s`/`%d`:

```lua
CARGO_PAID = "+{monedas} for {items} items on {ruta}",
GARAGE_TAKEOUT = "You take out {vehiculo}",
```

Cinco reglas que salen de esa decisión:

### 3.1 El servidor manda claves, no frases

`Remotes.AVISO` pasa de `(texto, color)` a `(clave, args, color)`. El cliente resuelve.

No es sólo por traducir: **hoy el servidor decide en qué idioma habla, y el idioma es del
jugador**. En una partida con dos personas de países distintos el servidor no tiene un idioma
correcto que elegir. La clave sí viaja bien.

### 3.2 Los parámetros que son texto viajan como referencia

`"You take out {vehiculo}"` necesita meter dentro otro texto traducible. Un `string` suelto no
vale: llegaría en inglés y se quedaría en inglés dentro de una frase alemana. Por eso:

```lua
Strings.ref("RIDE_furgoneta")  -- => { __clave = "RIDE_furgoneta" }
```

`Strings.get` resuelve las referencias antes de sustituir. Un argumento que es número o cadena
suelta se sustituye tal cual (los números no se traducen).

### 3.3 Los catálogos guardan claves, no nombres

`Config.VEHICULOS`, `Config.RUTAS`, `Config.TAMANOS`, `Config.HITOS`, `Goods.LISTA`,
`Skills.CATALOGO` y `Warehouse` pierden su campo `nombre`/`texto`/`descripcion` literal y lo
sustituyen por la clave derivada del id (`RIDE_coche`, `GOODS_piano`, `ROUTE_verde`,
`SIZE_pequeno`, `SKILL_camuflaje`, `SKILL_camuflaje_DESC`, `GOAL_primera`, `WH_pequeno`).

Los **ids no se tocan**: son claves del DataStore y de la telemetría.

### 3.4 El identificador nunca es la etiqueta

`Menu.luau` usa hoy la misma cadena como texto del botón y como clave del panel abierto
(`abierto == "Skills"`). Traducir ese botón rompería el menú: se pintaría *Fähigkeiten* y la
comparación con `"Skills"` fallaría para siempre.

Es el fallo clásico de una localización hecha con prisa, y aquí ya está plantado. Se separan:
id interno `"skills"`, texto `Strings.get("MENU_SKILLS")`.

### 3.5 Funciona hoy sin tocar nada en el portal

`Strings.get` intenta primero la tabla de la nube y, si no hay traductor o no existe la fila,
**cae al inglés que lleva dentro**. Consecuencia: el módulo funciona en cuanto se escribe, sin
configurar nada, y el día que se suba la tabla aparecen los idiomas **sin cambiar una línea**.

La parte de la nube se aísla en el cliente y va con `pcall`: `GetTranslatorForPlayerAsync`
cede (yield) y falla sin red. Un juego que se queda en negro porque no pudo pedir traducciones
es peor que un juego en inglés.

## 4. Arquitectura

```
Strings.luau  (puro, compartido)
  ├─ TEXTOS: { [clave] = "plantilla en inglés" }
  ├─ Strings.format(plantilla, args) -> string     ← puro, con pruebas
  ├─ Strings.ref(clave)              -> Ref
  ├─ Strings.get(clave, args)        -> string     ← usa el traductor si lo hay
  └─ Strings.usarTraductor(fn)                     ← el cliente enchufa la nube aquí

Cliente                          Servidor
  Main.client enchufa el          avisar(player, "CARGO_EMPTY", { … })
  traductor al arrancar             → FireClient(clave, args, color)
  Hud/Menu/… llaman Strings.get
```

`Strings` es **puro**: no requiere `LocalizationService` ni ningún servicio de Roblox. El
traductor se le inyecta desde el cliente. Así se puede probar entero sin Studio y el servidor
puede requerirlo sin arrastrar nada.

## 5. Qué se prueba

Pruebas nuevas en `src/shared/tests/Strings.spec.luau`:

1. `format` sustituye `{nombre}`, deja intacto lo que no es parámetro, y **no se traga un
   parámetro que falta**: lo deja visible (`{monedas}`) en vez de vacío, porque un hueco
   silencioso en pantalla no se detecta y un `{monedas}` a la vista sí.
2. Las referencias anidadas se resuelven, y una referencia a una clave que no existe no
   revienta.
3. **Ninguna plantilla tiene un parámetro que nadie rellena** — recorre todas las claves.
4. **Ningún texto del catálogo se queda sin clave**: por cada vehículo, mercancía, ruta,
   tamaño, habilidad, hito y nivel de nave existe su fila en `TEXTOS`.
5. **No hay claves duplicadas ni textos vacíos.**
6. **Ninguna plantilla contiene `%s`/`%d`** — un `string.format` colado sería un texto que no
   se puede traducir.

Y una que no es de traducción sino de idioma, que es lo que empezó todo:

7. **Ningún texto contiene caracteres del castellano** (`á é í ó ú ñ ¿ ¡`) ni palabras
   castellanas frecuentes de nuestro código (`huecos`, `Oficina`, `Cargar`, `Bulto`,
   `Guarida`, `Concesionario`, `nave`, `dinero`). Es una red tosca a propósito: no distingue
   idiomas, sólo caza la recaída concreta que ya nos pasó dos veces.

## 6. La exportación

`scripts/export-locale.js` (Node, sin dependencias) lee `Strings.luau` y escribe el CSV que
pide el portal de localización:

```
Key,Source,Context,Example,Source Language (en)
CARGO_PAID,"+{monedas} for {items} items on {ruta}",Game,,+250 for 3 items on GREEN
```

Se sube a mano al portal. **No se automatiza el subir**: es una acción sobre la ficha pública
del juego y va cuando JJ decida, no cuando corra un script.

## 7. Lo que NO entra

- **No se traduce nada a mano.** Las columnas de idioma las rellena Roblox.
- **No se activa ningún idioma todavía.** Esto no mueve la D1; el valor de hoy es el fichero
  único. Encender idiomas es una casilla del portal cuando haya jugadores.
- **No se tocan comentarios, logs ni pruebas.** Siguen en castellano: son material de
  aprendizaje y no los lee ningún jugador (`CLAUDE.md`).
- **No se toca el chat de Roblox ni sus menús.** Ya siguen el idioma de la cuenta del jugador;
  no son nuestros.
