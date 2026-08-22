# Publicar: los pasos, uno a uno

> 2026-08-22. Todo lo que hay que hacer en el portal de Roblox para que el juego salga.
> No hay nada de código aquí: el juego ya está listo y publicado como *place*; lo que
> falta son ajustes de la ficha y el interruptor de público.
>
> **Tiempo: unos 15 minutos.** Los ficheros ya están preparados en el tamaño exacto.

---

## Antes de empezar

Los datos del juego, por si algún paso los pide:

| | |
|---|---|
| **Universe ID** | `10732113535` |
| **Place ID** | `91033529404976` |
| **Enlace directo al panel** | https://create.roblox.com/dashboard/creations/experiences/10732113535/configure |

Y las imágenes, ya recortadas a la medida que pide Roblox:

```
games\contrabando\assets\portada\listo\
├── ICONO-512.png                   ← el icono (512x512)
├── MINIATURA-1920.jpg              ← la miniatura (1920x1080)
├── alternativa-ICONO-512.png       ← para MÁS ADELANTE, no ahora
└── secundaria-CIUDAD-1920.jpg      ← segunda miniatura, opcional
```

> **La miniatura va en JPEG y no en PNG**, y no es capricho: en PNG pesaba 4 MB y el
> formulario del portal **se quedaba sin reaccionar, sin decir por qué**. En JPEG de
> calidad 92 son 301 KB y entra a la primera. El icono sí se queda en PNG: se ve a 150 px
> y con mucho contraste, y ahí los artefactos del JPEG se notan en los bordes duros.

Si hay que volver a generarlas: `node scripts\portada.js --force` y luego
`powershell -ExecutionPolicy Bypass -File scripts\preparar-portada.ps1`.

---

## Paso 1 · El icono

1. Entra en https://create.roblox.com/dashboard/creations
2. Pincha en la experiencia (**Contrabando**).
3. En el menú de la izquierda: **Configure → Thumbnails** (en algunas versiones el icono
   está en **Basic Settings**, en la parte de arriba, como *Experience Icon*).
4. Sube **`ICONO-512.png`**.

> Sólo hay **un** icono por juego, y es lo que se ve en la cuadrícula del Discover, a
> menudo a menos de 150 px.

---

## ⚠️ Dos trampas que ya se pagaron

**1. Las miniaturas tienen DOS sitios, y hay que subirlas en los dos.** Dentro de
*Miniaturas* hay dos pestañas: **Página De Inicio** y **Página De Detalles De La
Experiencia**. Subirla sólo en la primera deja la segunda vacía, y entonces la ficha
pública del juego enseña **la imagen genérica de Roblox** (un prado con un puente).

**2. El alcance no lo decide el juego, lo decide la CUENTA.** El cuestionario de contenido
puede salir "Mínima" —apta para todas las edades— y aun así la experiencia queda limitada a
*"mayores de 16 años y amigos de confianza"*, porque el nivel de publicación depende de la
cuenta del creador. Se mira en **Configuración → Elegibilidad → Permisos de publicación**, y
para llegar a todas las edades hacen falta tres cosas: verificación de identidad,
verificación de edad y **verificación en dos pasos**. Las dos primeras son un trámite; la
tercera se olvida, y sin ella el juego no lo ve casi nadie.

Con el alcance limitado, **el CTR y la D1 no se pueden medir**: no porque el juego sea bueno
o malo, sino porque no llega a nadie a quien medir.

---

## Paso 2 · La miniatura

1. Sigues en la misma experiencia. Menú izquierdo: **Configure → Places**.
2. Pincha en el place (**Contrabando**).
3. En el menú de la izquierda de esa pantalla: **Thumbnails**.
4. Sube **`MINIATURA-1920.jpg`**.
5. *(Opcional)* Sube también **`secundaria-CIUDAD-1920.jpg`** como segunda imagen. Es la
   vista aérea de la ciudad: no vale de portada porque el coche sale diminuto, pero en la
   página del juego —donde la gente ya está mirando con calma— enseña que hay un mapa.

> Se admiten **hasta 10** miniaturas, en 16:9. **La primera es la que manda**: es la que
> acompaña al icono. Si subes las dos, asegúrate de que la de la furgoneta queda arriba
> (se arrastran para ordenarlas).

---

## Paso 3 · Nombre y descripción

En **Configure → Basic Settings**.

**Nombre** — cópialo tal cual:

```
🚚 Smuggler Run | Don't Get Caught
```

**Descripción** — cópiala entera:

```
🚚 You're a smuggler. Load your van, pick your route, and cross the city before they catch you.

👀 Marked corners spot you. The more they see you, the more thieves come after you
📦 Three routes, three payouts: the safe one pays x1, the dangerous one x10
🏃 Every pickup on the road makes you FASTER, and you lose it all if they reach you
🚐 Skateboard, bike, motorbike: each one carries more and hides less
🏆 Upgrade your warehouse so it keeps producing while you are away

Play with friends: on the red route anyone can rob anyone.
```

---

## Paso 4 · Género

En la misma pantalla, **Genre**: elige **Adventure**.

> **No pongas "Simulator"**, aunque tenga más búsquedas: esa etiqueta promete progresión
> idle —dejarlo corriendo y volver a recoger— y este juego no da eso. Un jugador que entra
> esperando un simulador se va en treinta segundos, y eso es exactamente lo que hunde la D1.

---

## Paso 5 · Ponerlo en público

1. **Configure → Settings**.
2. En **Audience**, elige **Public**.
3. **Save Changes**.

Ya está fuera.

---

## Paso 6 · Comprobar que se está midiendo

En el menú izquierdo, **Analytics**. Los dos números que importan:

| Número | Dónde | Qué dice |
|---|---|---|
| **CTR** (click-through rate) | *Acquisition* / *Discovery* | De cada 100 que ven el icono, cuántos entran. Mide **el cartel** |
| **D1** (day-1 retention) | *Engagement* / *Retention* | De cada 100 que juegan, cuántos vuelven al día siguiente. Mide **el juego** |

Tardan **24-48 h** en tener sentido, y hacen falta unos 100 jugadores para que el número
no sea ruido. Antes de eso no significan nada: no mires cada hora.

---

## Qué hacer cuando lleguen los números

Está en [`../../REVISION.md`](../../REVISION.md), pero resumido, y **la gracia es que cada
caso se arregla en un sitio distinto**:

| CTR | D1 | Qué pasa | Qué se toca |
|---|---|---|---|
| bajo | — | Nadie entra | **El cartel**: probar `alternativa-ICONO-512.png`, cambiar el nombre. No se toca el juego |
| bien | <15 % | Entran y no vuelven | **El bucle**: opción 2 de `REVISION.md` (girar hacia el robo) |
| bien | >15 % | Hay algo | Iterar el bucle, y **ahora sí** vale la pena el arte y los vehículos |

**Y lo importante: no tocamos el juego hasta tener estos dos números.** Cinco días de esta
semana fueron opiniones sobre un juego que nadie había jugado.

---

## Si algo no cuadra

- **No encuentras "Thumbnails"**: el panel de Roblox cambia de sitio las cosas cada pocos
  meses. Busca *Icon* y *Thumbnails* dentro de **Configure**; si no, están en **Basic
  Settings**.
- **Rechaza la imagen**: comprueba que es la de la carpeta `listo\` (las de fuera están a
  1024x1024 y 1280x720, que no son las medidas del portal).
- **Tarda en aparecer**: las imágenes pasan por moderación automática. Suele ser rápido,
  pero puede tardar unos minutos.
