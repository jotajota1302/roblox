# La portada: nombre, icono, miniatura y descripción

> 2026-08-18. Escrito sin Studio (JJ necesitaba la GPU). Aquí no hay código: es la parte del
> proyecto que `RESEARCH.md` §5 llama **el cuello de botella real**, y la única que no depende
> de que el juego esté terminado.
>
> Nada de esto está decidido todavía. Es material para decidir.

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

**Esto lo decide JJ. Todo lo de abajo está en los dos idiomas para que se pueda elegir.**

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

1. **Decidir el idioma.** Todo lo demás depende de eso.
2. Elegir nombre y escribir la descripción definitiva.
3. Generar icono y miniatura con MiniMax, y **la segunda miniatura con gameplay real** —
   necesita el juego a mano, así que va después de la partida de prueba.
4. Publicar. Y sólo entonces mirar los números: D1 ≥ 20 %, sesión ≥ 8 min (`TARGETS.md`).
