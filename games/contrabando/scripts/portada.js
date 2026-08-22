/**
 * portada.js — genera el icono y la miniatura del juego con MiniMax image-01.
 *
 * POR QUE ESTO Y NO CUBE 3D. El icono y la miniatura son 2D y son MARKETING: deciden el
 * CTR en el Discover, que es el cuello de botella real del proyecto (RESEARCH.md §5).
 * Cube 3D sirve para lo que va DENTRO del juego; esto es lo que se ve antes de entrar.
 *
 * QUE HAY QUE SABER PARA QUE SALGAN BIEN:
 *   · el icono se ve a menudo a MENOS DE 150 px en la cuadricula. Todo lo que no se lea
 *     a ese tamano sobra: una silueta, dos colores fuertes y nada mas.
 *   · sin texto en la imagen. El texto se anade en el portal, y ademas Roblox lo recorta.
 *   · saturado y con contraste alto, no bonito. Compite contra cien miniaturas a la vez.
 *
 * Uso:  node scripts/portada.js [--force]
 * Sale en: assets/portada/
 *
 * La clave vive en rpg-narrativo/.env y NO se copia aqui: se lee de alli en cada
 * ejecucion. Es el mismo pipeline del RPG narrativo, que CLAUDE.md declara transferible.
 */

const fs = require("fs");
const path = require("path");

const RAIZ = path.resolve(__dirname, "..");
const ENV = path.resolve(RAIZ, "../../../rpg-narrativo/.env");
const OUT_DIR = path.join(RAIZ, "assets", "portada");

function leerEnv(fichero) {
  const env = {};
  if (!fs.existsSync(fichero)) return env;
  for (const linea of fs.readFileSync(fichero, "utf8").split(/\r?\n/)) {
    const m = linea.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return env;
}

const env = leerEnv(ENV);
if (!env.MINIMAX_API_KEY) {
  console.error("No encuentro MINIMAX_API_KEY en " + ENV);
  process.exit(1);
}

// EL ESTILO, COMPARTIDO. Va aparte del prompt de cada pieza para que las dos imagenes
// se parezcan entre si: en la cuadricula se ven el icono y la miniatura del mismo juego
// una al lado de la otra, y si no casan parecen de dos juegos distintos.
const ESTILO =
  " Bold stylized 3D game art in the style of a Roblox promotional image. Chunky simple " +
  "shapes, thick outlines, highly saturated colors, strong rim light, high contrast, " +
  "dramatic lighting. Clean and readable at small size. No text, no letters, no logos, " +
  "no watermarks, no UI.";

const PIEZAS = [
  {
    id: "icono",
    ratio: "1:1",
    // UNA SOLA IDEA Y GRANDE. A 150 px no cabe una escena: cabe una cosa. La furgoneta
    // huyendo con algo valioso, y el peligro insinuado por quien viene detras.
    //
    // Y EL TECHO SE LLENA CON ALGO, que es la unica forma de vaciarlo.
    //
    // La primera version pedia "un haz de foco policial detras" y el modelo lo entendio
    // como una BARRA DE LUCES azul y roja encima de la furgoneta: una ambulancia con
    // cajas, o sea lo contrario de lo que el juego dice -- que la policia es de lo que
    // HUYES, no lo que eres.
    //
    // La segunda version lo PROHIBIA explicito ("no light bar, no emergency lights, not
    // a police vehicle") y salio otra vez con las luces puestas. En estos modelos un
    // negativo a menudo refuerza lo que niega: nombrar la barra de luces la invoca,
    // diga lo que diga la frase alrededor.
    //
    // Lo que funciona es no mencionarla y DARLE AL TECHO OTRA COSA que ocupe su sitio:
    // una lona atada. Se describe lo que se quiere ver, no lo que no.
    prompt:
      "Square game icon. A battered red civilian cargo van at a low three-quarter front " +
      "angle, speeding toward the viewer down a night street, body tilted with motion. " +
      "A glowing golden crate sits among cardboard boxes in its open cargo bed, spilling " +
      "warm light. On top of the van, a folded canvas tarp is strapped down flat across " +
      "the whole roof with rope, covering it completely. Close behind, a masked thief on " +
      "a motorbike gives chase, headlight glaring. The van fills most of the frame.",
  },
  {
    id: "miniatura",
    ratio: "16:9",
    // AQUI SI CABE UNA ESCENA, y tiene que contar el juego entero de un vistazo: llevas
    // algo valioso, te persiguen, y la ciudad es el tablero.
    prompt:
      "Wide cinematic game thumbnail. A red delivery van loaded with cardboard boxes and a " +
      "glowing golden crate races down a wide city avenue at night. Two masked thieves on " +
      "motorbikes chase close behind it, reaching for the cargo. Searchlight beams sweep " +
      "the street from the rooftops. Blocky stylized city buildings on both sides, wet " +
      "asphalt reflecting the lights. Sense of speed and chase, motion blur on the road.",
  },
];

const force = process.argv.includes("--force");

async function generar(pieza) {
  const res = await fetch("https://api.minimax.io/v1/image_generation", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.MINIMAX_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "image-01",
      prompt: pieza.prompt + ESTILO,
      aspect_ratio: pieza.ratio,
      response_format: "url",
      // Semilla fija: si hay que regenerar una, la otra no cambia debajo.
      seed: 23,
    }),
  });
  const data = await res.json();
  const url = data.data && data.data.image_urls && data.data.image_urls[0];
  if (!url) throw new Error(JSON.stringify(data.base_resp || data).slice(0, 200));
  const img = await fetch(url);
  if (!img.ok) throw new Error(`descarga HTTP ${img.status}`);
  const destino = path.join(OUT_DIR, pieza.id + ".jpg");
  fs.writeFileSync(destino, Buffer.from(await img.arrayBuffer()));
  return destino;
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  let hechas = 0;
  let fallos = 0;
  for (const pieza of PIEZAS) {
    const fichero = path.join(OUT_DIR, pieza.id + ".jpg");
    if (!force && fs.existsSync(fichero)) {
      console.log("ya estaba:", pieza.id);
      continue;
    }
    try {
      const destino = await generar(pieza);
      hechas++;
      console.log("ok       ", pieza.id, "->", path.relative(RAIZ, destino));
    } catch (e) {
      fallos++;
      console.error("FALLO    ", pieza.id, "-", e.message);
    }
  }
  console.log(`\n${hechas} generadas, ${fallos} fallidas`);
  process.exit(fallos ? 1 : 0);
})();
