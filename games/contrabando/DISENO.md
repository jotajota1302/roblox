# Diseño: rutas de contrabando

> 2026-08-17. Diseño validado del target B de [`TARGETS.md`](TARGETS.md).
> Nombre y ambientación **sin decidir a propósito** (ver sección 6).
>
> Lo que responde: qué pasa en los primeros 60 segundos, por qué el jugador vuelve
> mañana, y cómo la presencia de otro jugador cambia la partida.

---

## 1. En una frase

Tienes un almacén que produce mercancía mientras no estás. Cuando entras, decides **qué
llevar, a dónde y por qué ruta** — y en las rutas que más pagan, cualquiera puede
alcanzarte y quitarte parte de la carga.

**Jugable en solitario desde el primer jugador. Mejor cuando hay gente.** Ese es el
criterio que descartó a los demás candidatos.

---

## 2. El bucle

### Los primeros 60 segundos (sin tutorial)

| Tiempo | Qué pasa | Qué aprende sin que se lo digan |
|---|---|---|
| 0-5 s | Apareces en tu almacén. **3 cajas brillando** y una flecha hacia la salida | Esto es mío, eso se coge |
| 5-15 s | Recoges las cajas tocándolas. **Te ralentizas visiblemente** | Llevar carga cuesta |
| 15-20 s | En la salida aparecen **tres destinos con su precio**: verde ×1, ámbar ×3, roja ×10 | Más dinero = más peligro, y **yo elijo** |
| 20-50 s | Viajas. Por el camino **ves a otros con carga** | Aquí hay gente, y llevan cosas de valor |
| 50-60 s | Entregas. Número grande y sonido de recompensa. Al volver, **el almacén ya tiene una caja nueva** | Esto produce solo. Hay motivo para volver |

En un minuto ha aprendido las cinco reglas y ya ha tomado una decisión con consecuencias.

### El ciclo (8-15 minutos por sesión)

```
   ┌─────────────────────────────────────────────┐
   ▼                                             │
[ALMACÉN]   recoges lo producido en tu ausencia  │
   │                                             │
   ▼                                             │
[DECISIÓN]  ¿qué llevo, a dónde, por qué ruta?   │
   ▼                                             │
[VIAJE]     2-7 min · aquí vive toda la tensión  │
   ▼                                             │
[ENTREGA]   cobras el margen                     │
   ▼                                             │
[INVERSIÓN] almacén, vehículo, consumibles ──────┘
```

La decisión de ruta es el corazón: **cada viaje es una apuesta tuya**, no un castigo que
te cae encima.

### Por qué vuelve mañana

1. **El almacén produce con tope.** 1 caja cada 3 minutos hasta 10. Al llenarse **deja de
   producir**: no volver es desperdiciar tiempo. Mejorar la capacidad es el sumidero
   principal de dinero y **alarga tu ventana de ausencia**, así que la cadencia de retorno
   crece con el jugador en vez de agobiarle siempre igual.
2. **Los precios rotan** cada pocos minutos: siempre hay un destino que hoy paga el triple.
3. **Evento global "Redada"** a horas fijas: 10 minutos con todas las rutas a ×3 y más
   interceptores sueltos. Sincroniza a todo el mundo a la vez. *(Fuera del prototipo: sin
   masa de jugadores no tiene sentido.)*

---

## 3. Economía

Todo se mide en **cajas**. Valor base: **10 monedas**. El resto son multiplicadores.

### Rutas

| Ruta | Multiplicador | Duración | PvP | Por caja |
|---|---|---|---|---|
| 🟢 Verde | ×1 | 2 min | Ninguno | 10 |
| 🟡 Ámbar | ×3 | 4 min | **Sólo entre transportistas** | 30 |
| 🔴 Roja | ×10 | 7 min | Libre | 100 |

**Qué significa "sólo entre transportistas":** en la ruta ámbar únicamente puede robarte
alguien que **también lleve carga**. No se puede ir de caza con las manos vacías y sin
arriesgar nada propio.

Es un filtro elegante: obliga al cazador a tener algo que perder, así que la ruta ámbar es
donde se aprende el PvP con red de seguridad. La roja no tiene esa restricción — ahí puede
cazarte cualquiera, incluso alguien que salga del almacén sin nada encima sólo a por ti.

### Almacén

| | Nivel 1 | Subir de nivel |
|---|---|---|
| Ritmo | 1 caja / 3 min | 1.000 monedas |
| Tope | 10 cajas | |

**El almacén no es asaltable. Nunca.** Sólo está en juego lo que llevas encima. Sin esa
garantía, la gente abandona tras el primer mal día.

### Vehículos: capacidad contra exposición

| | Capacidad | Velocidad | Al ser alcanzado | Coste |
|---|---|---|---|---|
| A pie | 3 | Normal | Sueltas todo | — |
| Moto | 4 | +25% | Sueltas todo | 500 |
| Furgoneta | 10 | −10% | Pierdes 30% | 5.000 |
| Camión | 25 | −30%, **visible de lejos** | Pierdes 30%, aguanta 2 toques | 50.000 |

**Regla de diseño innegociable:** la progresión va por **capacidad y acceso, nunca por
potencia**. Ningún vehículo te hace inatrapable. Un novato en moto puede escapar del mejor
jugador del servidor. En el momento en que alguien se vuelve inalcanzable, el PvP muere y
las rutas rojas pasan a ser dinero gratis.

Los escudos y defensas son **consumibles de un solo uso**, no equipo permanente: un escudo
permanente es escalado de poder disfrazado; uno de un solo uso es una decisión ("¿lo gasto
ahora o me lo guardo para la roja?").

### Cajas raras: el golpe de suerte, atado al riesgo social

| Tipo | Probabilidad | Valor | Peso | Aspecto |
|---|---|---|---|---|
| Común | 90% | ×1 | 1 | Normal |
| Marcada | 8% | ×10 | 1 | Brilla suave |
| Sellada | 1,8% | ×50 | 2 | Brilla fuerte |
| Legendaria | 0,2% | ×135 | **3** | **Haz de luz visible en todo el mapa** |

El peso de la legendaria es exactamente la capacidad de ir a pie: **cabe, pero te ocupa
todo**. Un jugador nuevo puede transportar su premio gordo sin necesitar vehículo — sólo
tiene que renunciar a llevar nada más ese viaje.

Los multiplicadores **se combinan con los de ruta**: una legendaria por la roja son
`10 × 135 × 10 = 13.500` monedas en un viaje.

De ahí sale la decisión más tensa del juego:

> Te ha salido una legendaria. Por la verde son 1.350 seguros. Por la roja, 13.500 — pero
> tu haz de luz se ve desde el otro extremo del mapa y **todos saben dónde estás y qué
> llevas**.

Una sola mecánica que da el subidón de suerte, crea una decisión difícil de verdad y
fabrica los momentos PvP memorables **sin obligar a nadie a pelear**.

### Robar no es cobrar

Al alcanzar a alguien te llevas su carga, pero **no recibes dinero**: ahora eres tú quien
tiene que llegar a un destino con ella, cargado, lento y **marcado 60 segundos**. La
víctima recibe aviso de quién fue y hacia dónde va.

Robar **no es un atajo: es empezar un viaje en desventaja.** Eso impide que interceptar sea
trivialmente mejor que transportar, que es como degeneran estos sistemas.

### Monetización (más adelante)

**Se monetiza la parte tranquila, nunca la competitiva.**

- ✅ Pase "×2 producción", producto "recarga instantánea", ampliaciones de capacidad.
- ❌ Nada que dé ventaja en la persecución: ni radar, ni velocidad, ni escudos con Robux.

Pagar por ir más rápido que otro jugador es la forma más eficaz de matar un juego PvP.

---

## 4. Arquitectura

Mismo patrón validado en el piloto: punto de entrada que arranca servicios protegidos con
`pcall`, mundo por código, y **el servidor como única fuente de verdad**.

### Módulos

**Servidor** — `PlayerData` (dinero, vehículos, progreso, persistencia) · `WarehouseService`
(producción y cálculo offline) · `CargoService` (cajas, rarezas, carga) · `RouteService`
(rutas, precios rotativos, **validación de entregas**) · `InterceptService` (detección,
transferencia, marcado) · `EventService` (Redada) · `AntiCheat` · `WorldBuilder`.

**Cliente** — interfaz, efectos visuales de carga y haz de luz, realimentación de
persecución. **Cero lógica de juego.**

### La producción offline no simula nada

```
cajas = min( tope, floor( (ahora − ultimaVisita) / ritmo ) )
```

Una resta al entrar. Sin procesos en segundo plano, sin coste, y da igual que estuviera
fuera diez minutos o dos semanas.

### El riesgo técnico real: el cliente controla su movimiento

En Roblox el personaje pertenece al cliente por diseño. Un exploit puede teletransportarse
— y el núcleo de este juego es una persecución. **No se elimina; se le quita el
incentivo:**

1. **La intercepción la detecta el servidor**, recorriendo jugadores 5 veces por segundo.
   No existe ningún remote de "he tocado a este": esa llamada sería el primer exploit.
2. **La entrega se valida contra la posición del servidor.** Teletransportarse al destino
   no sirve si el servidor no te ha visto llegar.
3. **Detección de velocidad imposible**, y ante una anomalía **se invalida la carga en vez
   de expulsar**: más suave con los falsos positivos (lag, caídas) y quita el beneficio.

### Flujo de un robo

```
[Servidor · cada 0,2 s]  recorre jugadores con carga
        │
        ▼  ¿alguien a menos de 5 studs?
   valida: ¿lleva carga? ¿el otro no está marcado?
           ¿velocidades plausibles?
        │
        ▼  transfiere 30% · marca al ladrón 60 s
        ├──► avisa a la víctima (quién y hacia dónde)
        └──► pinta al ladrón en el mapa de todos
```

El cliente **sólo recibe el resultado**.

---

## 5. Assets: qué herramienta para qué

| Necesidad | Herramienta | Cuándo |
|---|---|---|
| Modelos 3D | **Cube 3D** de Studio (`generate_mesh`) | 3-4 en el prototipo: caja, furgoneta, almacén |
| Materiales | `generate_material` | Al pulir |
| Miniatura e icono | **MiniMax** `image-01` | Al publicar. Es **marketing**: decide el CTR en Discover |
| Iconos de UI | **MiniMax** | Al pulir |
| **Efectos de sonido** | **Biblioteca de Roblox** | **En el prototipo** — ver abajo |
| Música | **MiniMax** `music-2.6` | Al publicar |
| Vídeo promocional | **Grabar gameplay real** | Al publicar |

Límites verificados en la documentación oficial: **2.000 assets de audio gratis cada 30
días** con identidad verificada, 100 sin verificar. Pasan moderación como cualquier asset.

**Los efectos de sonido no son decoración, son información.** La alerta de "te vienen
detrás" afecta directamente a si la intercepción se siente como persecución o como
emboscada injusta. Por eso entran en el prototipo — y salen de la biblioteca de Roblox,
que es gratis, instantánea y ya moderada. La música, en cambio, no cambia si el bucle
engancha.

**Principio general:** el arte bonito **contamina la medición**. Si el prototipo es
atractivo, cuando alguien aguante diez minutos no sabrás si fue por el bucle o por lo
bonito. Y el bucle es lo único que estamos midiendo.

---

## 6. Alcance del prototipo

### Orden de construcción: lo que puede matar el proyecto va primero

| # | Qué se construye | Qué pregunta responde |
|---|---|---|
| 1 | **El viaje**: coger carga, moverte lento, entregar, cobrar | ¿Transportar es entretenido **por sí solo**? |
| 2 | **Elección de ruta** | ¿Decidir cuánto riesgo asumir engancha? |
| 3 | **Cajas raras** | ¿El golpe de suerte da el subidón esperado? |
| 4 | **Almacén** con producción, tope y cálculo offline | ¿Vuelve la gente mañana? |
| 5 | **Intercepción** | ¿Da tensión o da rabia? |
| 6 | Persistencia y verificación en móvil | ¿Aguanta fuera del laboratorio? |

Si el paso 1 falla, **no hay proyecto**, y se sabe en días. El multijugador va el quinto a
propósito: es lo más caro y lo más divertido de programar, o sea, la trampa perfecta para
gastar tres semanas sin comprobar nada.

### Entra

Un almacén · tres destinos · tres niveles de ruta · carga a pie (3) y **un solo vehículo**
(furgoneta) como primer sumidero · las cuatro rarezas · intercepción con robo parcial y
marcado · guardado en la nube · 3-4 modelos de Cube 3D · 3-4 efectos de sonido.

### No entra

❌ Mapa bonito o grande ❌ Música ❌ Los otros vehículos ❌ Evento Redada ❌ Monetización
❌ Iconos y miniatura ❌ **Nombre y ambientación definitivos**

La ambientación se elige después y **por diferenciación de mercado**, no por gusto: vestir
el juego antes de saber si el esqueleto aguanta es apostar a un caballo que no hemos visto
correr.

### Medición

Roblox da analítica propia (D1, D7, sesión media) a partir de 100 jugadores diarios. Por
debajo vamos a ciegas, así que el prototipo lleva **telemetría propia desde el primer día**:
entradas, duración de sesión, viajes completados, viajes interceptados, ruta elegida y
**punto de abandono** — el dato más valioso de todos.

### Criterios para matarlo

| Momento | Comprobación | Si falla |
|---|---|---|
| Paso 1 | ¿Aguantas 10 minutos seguidos tú mismo, sin PvP? | Rehacer el viaje. Sin esto no hay juego |
| Paso 5 | Con 3-4 personas: ¿tensión o frustración? | Ajustar reparto y marcado |
| Publicado | **D1 < 15%** con 100+ jugadores | Pasar al target A (excavación) |
| Publicado | Sesión media < 6 min | El bucle es demasiado corto |

Escritos **antes de empezar** a propósito: para que pivotar sea leer un número y no
discutir una corazonada cuando ya le hayamos cogido cariño.

---

## 7. Verificación

Lo aprendido en el piloto: **que compile no significa que funcione** — el peor fallo del
piloto compilaba perfectamente.

- `stylua --check` y `rojo build` como mínimo mecánico.
- **Pruebas dentro de Studio por MCP**, actuando sobre el mundo (mover jugadores, forzar
  proximidad, disparar remotes con basura) y leyendo el resultado.
- **Un intento de exploit por cada sistema nuevo**: ids inventados, tipos incorrectos,
  llamadas en bucle. El servidor no debe inmutarse.
- Verificación en móvil con el simulador de dispositivos antes de dar por buena cualquier
  pantalla.
