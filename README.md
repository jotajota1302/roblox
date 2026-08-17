# Roblox — investigación y piloto

Dos cosas viven aquí:

## 📊 [`RESEARCH.md`](RESEARCH.md) — ¿se puede ganar dinero?

Investigación con datos verificados contra la documentación oficial de Roblox (agosto 2026):
cómo entra el dinero y cuánto se queda cada uno, cuánto gana la gente de verdad, las 8 vías
de monetización, por qué el cuello de botella es el descubrimiento y no la calidad, qué
herramientas hacen falta y qué riesgos hay.

**Resumen:** sí se puede, pero de cada euro que gasta un jugador te llegan ~21-27 céntimos,
la mediana de un desarrollador que cobra es 1.440 $/año y el 85% gana menos de 100 $/mes.
Entrar cuesta 0 €, así que el experimento sale barato — pero es una lotería de cola larga.

## 🎮 [`coin-island/`](coin-island/) — el piloto

Juego pequeño y completo para entender cómo funciona Roblox por dentro: mundo 3D
multijugador, economía, tienda, guardado en la nube y dos productos de pago.
~700 líneas de Luau comentadas en español.

Todo se genera **por código** (el mapa y la interfaz incluidos), así que el juego entero
vive en git en vez de dentro de un binario de Studio.

👉 **Empieza por [`coin-island/README.md`](coin-island/README.md)**, que lleva la guía paso
a paso desde instalar Studio hasta publicar y activar los pases de pago.

---

## Puesta en marcha rápida

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1   # descarga rojo + stylua en ./tools
cd coin-island
..\tools\rojo.exe serve                              # y conecta desde Studio
```

Requisitos: Windows, VS Code y Roblox Studio (<https://create.roblox.com/>).
Las extensiones recomendadas de VS Code se sugieren solas al abrir la carpeta.
