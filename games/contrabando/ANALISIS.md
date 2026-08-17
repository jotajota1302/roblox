# Análisis del juego: dónde estamos y si esto tiene futuro

> 2026-08-17, al final de la sesión del rediseño. Escrito a petición de JJ.
> Lo que responde: qué es el juego hoy, cómo se compara con los líderes de la
> plataforma, si le vemos futuro, y qué falta exactamente para tenerlo.
>
> **Aviso de honestidad:** este documento contiene la crítica más incómoda del
> proyecto, en la sección 5. Si sólo se lee una parte, que sea ésa.

---

## 1. Qué es el juego hoy

**Eres un repartidor en una ciudad.** Tu almacén produce mercancía mientras no estás. Vuelves,
eliges qué cargar, eliges destino, y cruzas la ciudad esquivando ladrones. Si llegas, cobras.
Con el dinero compras vehículos que llevan más y cosas más grandes.

### El bucle, en una línea

`producir (offline) → elegir qué cargar → elegir destino → viajar esquivando → cobrar → comprar vehículo`

### Los sistemas, y qué decide cada uno

| Sistema | Qué decide el jugador | Estado |
|---|---|---|
| **Almacén** | Cuándo volver (produce con tope, deja de producir lleno) | Funciona |
| **Catálogo** (15 objetos) | Qué cargar: tamaño contra valor | Funciona |
| **Vehículos** (9) | En qué invertir: capacidad y acceso a lo grande | Funciona |
| **Destinos** (3 zonas) | Cuánto riesgo por cuánto pago | Funciona |
| **Peligro** (0-3) | Cómo cruzar: esquivar esquinas fichadas o correr | Funciona |
| **Ladrones** (PNJ) | Cuándo huir, y hacia dónde | Funciona |
| **Comisarías** (6) | Refugiarse cuesta tiempo, o arriesgar | Funciona |
| **Robo entre jugadores** | Cazar o transportar | **Nunca probado con 2 personas** |

### Tamaño

- **~8.000 líneas** de Luau en 29 módulos
- **~930 líneas** de pruebas: **298 casos**, todos verdes
- **~1.300 líneas** de documentación de diseño y verificación
- Mundo: ciudad de 1548×1569 studs, 30 esquinas fichadas, 6 comisarías, 3 destinos

---

## 2. Comparación con los líderes de la plataforma

Los dos fenómenos de referencia (`MERCADO.md`) y dónde encajamos:

| | Grow a Garden | Steal a Brainrot | **Nosotros** |
|---|---|---|---|
| Escala | 35.500 M visitas | 25,8 M concurrentes (récord) | 0 |
| Bucle en solitario | Plantar, esperar, recolectar | Acumular en tu base | Producir, cargar, viajar, cobrar |
| Capa social | Comparar jardines | **Robar a otros** | **Robar a otros** |
| Duración de un ciclo | **segundos** | **segundos** | **50-200 s** |
| Progresión visible | El jardín crece | **La base crece y se enseña** | Sólo el vehículo |
| Se entiende en | ~5 segundos | ~5 segundos | **~2 minutos** |

### Lo que hicimos bien

**La estructura es la correcta, y no por casualidad.** `MERCADO.md` concluyó que el único
formato que aprueba los cinco criterios es *"un bucle de progresión jugable en solitario con
una capa social de fricción encima"*, y que la fricción concreta que disparó Steal a Brainrot
fue **robar**. Tenemos exactamente eso. No estamos en un género equivocado.

Y la capa social está bien diseñada: robar no es gratis (heredas la ruta, el peligro y quedas
marcado 60 s), el almacén no es asaltable nunca, y hay zona segura. Eso evita el fallo que
mata a los clones malos, donde robar es tan rentable que nadie transporta.

### Las tres diferencias que sí preocupan

**1. Nuestro ciclo es 10-40 veces más largo.** En Grow a Garden plantas y recolectas en
segundos. Aquí un viaje son entre 50 y 200 segundos. La mediana de sesión de la plataforma
son ~6 minutos: eso da **2-4 viajes por sesión**, contra decenas de acciones en los líderes.
Menos ciclos significa menos veces que el juego te da una recompensa, y la recompensa por
ciclo es lo que fija el ritmo de dopamina.

**2. No tenemos nada que crezca y se vea.** Ésta es, en mi opinión, la diferencia más grave.
En Steal a Brainrot tu base crece, se llena y **se la enseñas a la gente**: es tu marcador
público y tu motivo para volver mañana. Aquí lo único permanente es el vehículo, y el almacén
tiene tope 10 y se vacía cada vez. **Un jugador que vuelve mañana no tiene nada que mirar.**

**3. Tardamos dos minutos en explicarnos.** Un jugador de Roblox decide en los primeros 30
segundos. Nosotros tenemos rutas, peligro, tamaños, vehículos, comisarías y un catálogo de 15
objetos. Cada pieza está justificada, pero **juntas son mucho** para los primeros 30 segundos.

---

## 3. Análisis de jugabilidad

### Lo que está bien resuelto

- **Hay decisión real en tres momentos distintos**: qué cargar, por dónde ir, y cuándo huir o
  aguantar. Tres decisiones por viaje es más de lo que tienen la mayoría de los clones.
- **La decisión de carga es elegante.** Tamaño y valor van juntos y son aprendibles: el joyero
  es pequeño y paga ×50, el sofá ocupa medio camión por calderilla. Esa memoria es habilidad
  real, y hace que la segunda partida se juegue mejor que la primera.
- **El vehículo es una llave, no un número.** Ver mercancía que no puedes mover es mejor
  motivación que "llevas una caja más".
- **Escapar se lee en el mapa.** Los ladrones van más rápido pero atados a las calles; tú
  cortas por parques. Eso convierte el escenario en mecánica, que es la única razón de peso
  para tener una ciudad.

### Lo que me preocupa de la jugabilidad

- **El viaje sigue teniendo tramos muertos.** Con las esquinas fichadas repartidas, hay
  encuentros — pero entre encuentro y encuentro sigue habiendo 15-20 segundos de sólo correr.
  Mejor que la recta vacía original, pero no es todavía "pasa algo constantemente".
- **La ruta verde puede ser demasiado fácil y la roja demasiado lejos.** 1.399 studs de ida
  son ~2 minutos sólo de trayecto. Nadie ha comprobado si la roja compensa.
- **No hay nada que hacer mientras esperas** a que el almacén produzca. En los líderes esa
  espera se llena mirando lo que tienes.
- **La muerte del bucle es el aburrimiento, no el fracaso.** Perder media carga es leve; el
  riesgo real es que dé igual.

---

## 4. ¿Le vemos futuro?

**Sí, con una condición y una reserva.**

**Sí**, porque la estructura es la que el mercado premia hoy, la capa social está bien
diseñada, y el juego es jugable de punta a punta con 298 pruebas que lo sostienen. Eso es
más de lo que tiene el 95 % de lo que se publica en Roblox.

**La condición**: que el bucle enganche diez minutos. Sin eso, nada de lo demás importa.

**La reserva**: la ventaja competitiva de este proyecto no es el género —está saturado— sino
la ejecución. Y la ejecución se demuestra con retención, no con sistemas. Hoy tenemos muchos
sistemas y **cero minutos medidos**.

---

## 5. La crítica incómoda: hemos hecho justo lo que el plan decía que no hiciéramos

`TARGETS.md`, sección 7, escrito antes de empezar:

> **Lo que NO hay que hacer al principio:** arte bonito, muchos tipos de mercancía, mapa
> grande, historia. Un almacén, tres destinos, una mercancía y la intercepción. **Si eso no
> engancha, nada de lo demás lo va a arreglar.**

Lo que hay hoy: mapa grande, quince tipos de mercancía, nueve vehículos con modelos 3D, y un
sistema de persecución. Los cuatro puntos, salvo la historia.

**No digo que esté mal hecho.** Casi todo salió de defectos reales encontrados jugando —el
viaje estaba vacío, la mercancía era indistinguible, los botones no decían dónde ni cuándo— y
cada pieza arregla algo que fallaba. Pero conviene mirarlo de frente:

- El criterio de kill de la semana 1 —*¿el bucle solo entretiene?*— **se comprobó una vez, dio
  que NO, y no se ha vuelto a comprobar.**
- Todo lo construido después es la *respuesta* a ese no, y es una respuesta razonada. Pero
  sigue siendo **una hipótesis sin medir**.
- Cada sistema nuevo que añadimos sin medir es una apuesta más sobre la misma mesa.

El riesgo concreto: que el problema del viaje vacío no fuera la falta de contenido sino la
**duración**, y que hayamos llenado de sistemas un trayecto que simplemente era demasiado
largo. Si es eso, la solución no era nada de lo que hemos hecho — era acortar.

**Se resuelve en diez minutos de partida.** No hay ningún atajo.

---

## 6. Qué falta, en orden

### Ahora mismo, y bloquea todo lo demás

1. **Jugar diez minutos seguidos.** La pregunta exacta: *al ver saltar el primer ladrón,
   ¿te apetece correr, o esperar a que pase?* Y al terminar un viaje: *¿te apetece otro?*
2. **Probar el robo con dos personas.** Nunca se ha hecho. Es la mitad del diseño y la razón
   por la que el género funciona en Roblox. Studio lo permite: *Probar → Clientes y servidores*.

### Si el bucle engancha

3. **Algo que crezca y se vea.** Es la diferencia más grande con los líderes. El almacén
   debería poder ampliarse y **verse lleno**: más sitios de muelle, más tope, mercancía
   acumulada a la vista. Hoy el dinero sólo compra velocidad y capacidad; debería comprar
   también **estatus visible**.
4. **Los primeros 30 segundos.** Un jugador nuevo tiene que entender qué hacer sin leer. Hoy
   hay demasiadas piezas a la vez; probablemente haya que **introducirlas por etapas**
   (empezar sin peligro y sin catálogo, y que aparezcan al segundo o tercer viaje).
5. **Telemetría.** `Telemetry.luau` ya registra eventos, pero nadie los mira. Sin datos, cada
   ajuste de balance es una opinión.

### Antes de publicar en serio

6. **Miniatura e icono.** Según `MERCADO.md`, el CTR en Discover es *el cuello de botella real
   del proyecto*. Un juego que no se pulsa no se juega, por bueno que sea.
7. **Revertir los valores `PROTOTIPO:`** de `Config.luau` (distancias, ritmo del almacén,
   probabilidades de rareza), que están puestos para medir en una sesión, no para jugar.
8. **Nombre y ambientación definitivos.** El juego se sigue llamando "contrabando" y ya no lo
   es: eres un repartidor.

### Lo que NO hay que hacer todavía

- Más contenido: más objetos, más vehículos, más zonas.
- Más mapa.
- Coches conducibles.
- Cualquier cosa que empiece por "y además podríamos…".

---

## 7. Resumen en cinco líneas

1. El juego está **construido, probado y es jugable de punta a punta**.
2. Su estructura es **la que el mercado premia** y la capa social está bien diseñada.
3. Le faltan las dos cosas que tienen los líderes: **ciclos cortos** y **progresión visible**.
4. Hemos añadido muchos sistemas **sin volver a medir** si el bucle engancha.
5. **Todo depende de una partida de diez minutos que nadie ha jugado todavía.**
