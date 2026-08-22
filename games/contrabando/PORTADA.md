# La portada: nombre, icono, miniatura y descripción

> 2026-08-18. Escrito sin Studio (JJ necesitaba la GPU). Aquí no hay código: es la parte del
> proyecto que `RESEARCH.md` §5 llama **el cuello de botella real**, y la única que no depende
> de que el juego esté terminado.
>
> Nada de esto está decidido todavía. Es material para decidir.

---

## DECIDIDO (22/08) — lo que hay que subir al portal

> Cerrado tras `REVISION.md`. Lo de abajo es el material con el que se decidió y se queda
> como registro; esto es lo que va.

**Pitch:** eres un **contrabandista**, no un repartidor. La diferencia no es de tono: el
nicho de reparto está lleno y promete llevar cajas, mientras que lo que este juego tiene es
que te persiguen.

**Título:**

```
🚚 Smuggler Run | Don't Get Caught
```

Por qué así: `Smuggler` es el tema y casi no se usa; `Don't Get Caught` es la tensión dicha
en tres palabras y es lo que se busca; el emoji da color en la cuadrícula. **No lleva
"Delivery"** a propósito -- esa palabra nos mete de cabeza en el nicho lleno.

Los corchetes de estado (`[NEW]`, `[UPDATE]`) se añaden **a partir de la primera
actualización**, no en el lanzamiento: en un juego que nadie conoce todavía no señalan nada.

**Descripción** (el primer párrafo es lo único que se lee):

```
🚚 You're a smuggler. Load your van, pick your route, and cross the city before they catch you.

👀 Marked corners spot you. The more they see you, the more thieves come after you
📦 Three routes, three payouts: the safe one pays x1, the dangerous one x10
🏃 Every pickup on the road makes you FASTER, and you lose it all if they reach you
🚐 Skateboard, bike, motorbike: each one carries more and hides less
🏆 Upgrade your warehouse so it keeps producing while you are away

Play with friends: on the red route anyone can rob anyone.
```

**Icono y miniatura:** seis piezas generadas con MiniMax `image-01` en `assets/portada/`
(`node scripts/portada.js`). **Tres enfoques de cada una a proposito**: el CTR es lo primero
que vamos a medir y con una sola imagen no hay nada que comparar -- si sale bajo, no se sabe
si el problema es el juego o el cartel. Con tres se cambia la portada sin tocar el juego y se
mira si el numero se mueve.

| Pieza | Que ensena | Veredicto |
|---|---|---|
| `icono-a` | La furgoneta huyendo con la carga encendida y un ladron detras | ✅ **el que va**: se lee a 150 px y dice de que va el juego |
| `icono-b` | La caja dorada con manos peleandose por ella | ❌ llamativa, pero la caja sale deformada y no dice que es un juego de conducir |
| `icono-c` | La cara del conductor y el faro del perseguidor en el retrovisor | 🟡 **el primero que hay que probar despues**: mucha emocion, pero oscuro |
| `miniatura-a` | La persecucion vista de lado | 🟡 correcta |
| `miniatura-b` | El robo EN EL ACTO: le arrancan la carga y las cajas caen | ✅ **la que va**: mas accion, mas contraste y cuenta lo que se pierde |
| `miniatura-c` | La ciudad entera desde arriba, con la rotonda | ❌ como miniatura, el coche es diminuto. 🟢 **sirve para las imagenes secundarias** de la pagina, donde si se mira con calma |

**Van `icono-a` + `miniatura-b`.** Y cuando haya CTR, la forma barata de subirlo es cambiar
UNA de las dos y volver a medir: `icono-c` primero, porque las caras expresivas rinden en la
cuadricula y es el enfoque mas distinto de los tres.

- La **miniatura** cuenta el juego de un vistazo: la furgoneta cargada con la caja dorada y
  dos ladrones en moto encima de ella.
- El **icono** costó tres intentos, y la lección vale para el siguiente que se genere: las
  dos primeras versiones salieron con **barra de luces azul y roja en el techo** -- una
  ambulancia con cajas, o sea lo contrario de lo que el juego dice. Prohibirla explícitamente
  ("no light bar, not a police vehicle") **no funcionó**: en estos modelos nombrar algo lo
  invoca aunque sea para negarlo. Lo que funcionó fue **darle al techo otra cosa** (una lona
  atada). Se describe lo que se quiere ver, no lo que no.

**Lo que le toca a JJ** (son casillas del portal, no código):

1. Subir icono y miniatura en *Creator Dashboard → Experience → Customize*.
2. Pegar título y descripción.
3. Género: **Adventure** (o *Action*). No "Simulator": promete progresión idle que este
   juego no da.
4. Poner la experiencia en **público**.
5. Comprobar que *Analytics* está activo -- de ahí salen el CTR y la D1, que son los dos
   números que deciden lo siguiente.

---

## 0. La decisión que hay que tomar antes que ninguna otra: el idioma

**El juego está entero en español.** Los avisos ("Entrega tu primer paquete", "Te vienen
detrás", "Elige destino en la salida"), los nombres de los vehículos, los hitos, el selector
de ruta. Es coherente con la convención del proyecto — comentarios en español porque es
material de aprendizaje — pero **el jugador no es el mismo que el programador**.

Los números que importan:

- Roblox tiene su masa de usuarios en **inglés**; el español es un mercado secundario dentro
  de la plataforma.
- El descubrimiento funciona por señales **por usuario** (`RESEARCH.md` §5), así que un juego
  con menos jugadores potenciales no está penalizado *per se*… pero sí lo está por CTR: un
  título en español lo saltan los angloparlantes, y son la mayoría de quien lo verá.

Tres caminos, con lo que cuesta cada uno:

| | Qué implica | Coste |
|---|---|---|
| **Inglés** | Traducir todos los textos de interfaz y la portada. El código y los comentarios se quedan en español | Un día de trabajo. Es el mercado grande |
| **Español** | No tocar nada. Competencia mucho menor en el nicho hispano, y el juego se entiende sin traducir | Cero |
| **Los dos** | Roblox tiene sistema de localización propio (`LocalizationService` + tablas de traducción) | Más trabajo y una capa nueva que mantener |

**Mi recomendación: inglés para la portada y la interfaz, ya.** No por gusto sino porque la
portada se decide en un vistazo de Discover y ahí el idioma es la primera barrera. El coste es
bajo *ahora* —los textos son pocos y están centralizados— y sube cada semana que se añade
contenido.

> **DECIDIDO (18/08): inglés.** La interfaz del juego ya está traducida — unos 130 textos, de
> los avisos a los nombres de las mercancías. Los comentarios, los logs y las pruebas siguen
> en español, y los ids internos no se tocaron (son claves del DataStore).
>
> **Y AL FINAL SE HIZO LA TERCERA OPCIÓN (19/08), que resultó más barata de lo que dice la
> tabla de arriba.** Roblox traduce solo: tabla en la nube + traducción automática, ~15
> idiomas, gratis. Lo que costaba no era traducir, era que nuestro texto fuera *traducible* —
> vivía suelto en 21 ficheros y dos tercios se construían pegando trozos, que no casan contra
> ninguna fila de la tabla. Ahora los 208 textos viven en `src/shared/Strings.luau` con
> parámetros con nombre, y `node scripts/export-locale.js` saca el CSV que se sube al portal.
>
> **No hay ningún idioma encendido todavía, y es deliberado**: esto no mueve la D1 y el inglés
> cubre a la mayoría de quien nos verá. Encenderlos es una casilla del portal el día que haya
> jugadores a los que les sirva. Lo que se ganó es el fichero único, que es la cura de raíz del
> bug de idiomas mezclados — parcheado dos veces a mano, y las dos se escapó algo.

**Lo de abajo se queda en los dos idiomas por si algún día se localiza.**

---

## 1. El nombre

Cómo se nombra en esta plataforma, mirando lo que funciona (el juego de referencia se llama
*[X2] +1 Speed Keyboard Escape | Candy & Chocolate*):

- **El nombre es una consulta de búsqueda**, no una marca. Lleva las palabras que la gente
  teclea: lo que se hace en el juego, no cómo se llama tu mundo.
- **Un modificador delante entre corchetes** (`[X2]`, `[NEW]`, `[UPDATE]`) para señalar que
  está vivo. Se cambia con cada actualización y sube el CTR.
- **Separador `|` y un segundo grupo de palabras** con el tema.
- Emoji al principio si aporta color en la cuadrícula. Uno, no tres.

### Candidatos, en inglés

| Nombre | Por qué |
|---|---|
| **🚚 Smuggler Run \| Deliver & Escape** | "Smuggler" es el tema, "Deliver" y "Escape" son las dos cosas que se hacen. Recomendado |
| 📦 Contraband Delivery \| Don't Get Robbed | "Don't get robbed" describe la tensión real (el robo entre jugadores) |
| 🚚 Smuggle Simulator \| Routes & Thieves | "Simulator" es la etiqueta de género con más búsqueda, pero promete progresión idle que este juego no da |

### Candidatos, en español

| Nombre | Por qué |
|---|---|
| **🚚 Contrabando \| Reparte y Escapa** | Directo, y las dos palabras son las dos mecánicas |
| 📦 Rutas de Contrabando \| No te Roben | La segunda mitad cuenta la tensión |

**Lo que NO conviene**: nombres de una sola palabra sin contexto ("Contrabando" a secas), ni
guiños que sólo entiende quien ya jugó ("Sal Negra", "El Polígono").

---

## 2. La descripción

Estructura que funciona en la tienda de Roblox: una frase que promete, una lista corta de
verbos, y la llamada a la acción. Lo que se lee es el primer párrafo — el resto lo ve quien ya
ha decidido.

### Inglés

```
🚚 You're a smuggler. Load your van, pick your route, and cross the city.

📦 Three routes, three payouts — the safer one pays x1, the dangerous one x10
👀 Marked corners spot you. The more they see you, the more thieves come
🏃 Every pickup on the road makes you FASTER — but you lose it all if they catch you
🚐 Skateboard, bike, motorbike, car, van: each one carries more and hides less
🏆 Upgrade your warehouse so it keeps producing while you're away

Play with friends: anyone can rob anyone on the red route.
```

### Español

```
🚚 Eres un repartidor de contrabando. Carga la furgoneta, elige ruta y cruza la ciudad.

📦 Tres rutas, tres pagas: la segura da ×1, la peligrosa ×10
👀 Las esquinas fichadas te ven pasar. Cuanto más te ven, más ladrones salen
🏃 Cada cosa que recoges por el camino te hace MÁS RÁPIDO, y lo pierdes todo si te alcanzan
🚐 Monopatín, bici, moto, coche, furgoneta: cada uno carga más y se esconde menos
🏆 Mejora tu nave para que siga produciendo mientras no estás

Juega con amigos: en la ruta roja cualquiera puede robar a cualquiera.
```

---

## 3. El icono (512×512)

Es lo que se ve en la cuadrícula de Discover, **a menudo a menos de 150 px**. Todo lo que no
se lea a ese tamaño sobra.

**Brief para generar con MiniMax `image-01`:**

> Ilustración estilo cartel, colores muy saturados, contorno negro grueso. Primer plano de un
> personaje con una caja de cartón grande en brazos, corriendo hacia la cámara, mirando por
> encima del hombro con cara de susto. Detrás, desenfocada, una figura oscura persiguiéndole.
> Fondo: calle de ciudad al atardecer, naranjas y morados. Composición vertical centrada, el
> personaje ocupa el 70 % del encuadre. Sin texto.

**Por qué así:**

- **Una cara con una emoción** — es lo que más CTR da en esta plataforma, y funciona a
  cualquier tamaño.
- **Dos elementos y nada más**: el que huye y el que persigue. Un icono con la ciudad entera
  se convierte en una mancha a 150 px.
- **Sin texto**: el nombre ya va debajo, y el texto dentro del icono es lo primero que se
  vuelve ilegible.
- **Naranjas y morados** porque la cuadrícula de Roblox está llena de azules y verdes.

## 4. La miniatura (1920×1080)

Se ve al entrar en la página del juego, cuando la persona **ya ha hecho clic**. Su trabajo no
es llamar la atención: es **explicar el juego en dos segundos** y confirmar la decisión.

**Brief:**

> La misma escena en horizontal, con más aire: el repartidor cargado corriendo por una calle,
> dos perseguidores detrás, y al fondo el almacén iluminado. Arriba a la izquierda, tres
> rutas marcadas con sus multiplicadores (×1, ×3, ×10) como en un mapa. Mismo estilo saturado
> con contorno negro.

**Y una segunda miniatura**: captura de **gameplay real**, sin retocar. Las dos juntas dicen
"esto es lo que promete" y "esto es lo que hay", y la segunda es la que evita la decepción de
los primeros treinta segundos — que es donde se pierde la retención D1.

---

## 5. Lo que NO hay que hacer

- **No poner "SIMULATOR" si no lo es.** Trae al público equivocado, que se va en un minuto y
  te hunde justo la señal que decide el descubrimiento.
- **No prometer multijugador masivo.** El juego se juega solo desde el primer jugador; la
  gente es la salsa, no el requisito.
- **No gastar un euro en anuncios antes de tener D1** (`RESEARCH.md` §5): una visita comprada
  a 0,02 $ necesita ~5,3 visitas de vida para recuperarse. Sin retención, es quemar dinero.
- **No generar el vídeo promocional.** Se graba gameplay real: la gente quiere ver el juego.

---

## 6. Orden de trabajo

1. ~~**Decidir el idioma.**~~ **Hecho: inglés**, la interfaz está traducida y verificada en
   Studio, y el juego queda preparado para encender más idiomas sin tocar código.
2. Elegir nombre y escribir la descripción definitiva.
3. Generar icono y miniatura con MiniMax, y **la segunda miniatura con gameplay real** —
   necesita el juego a mano, así que va después de la partida de prueba.
4. Publicar. Y sólo entonces mirar los números: D1 ≥ 20 %, sesión ≥ 8 min (`TARGETS.md`).
