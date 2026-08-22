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

// TRES ENFOQUES DE CADA COSA, NO UNO.
//
// El CTR es el cuello de botella del proyecto y es lo primero que vamos a medir, y con
// una sola imagen no hay nada que comparar: si sale bajo, no se sabe si el problema es
// el juego o el cartel. Con tres se puede cambiar la portada sin tocar el juego y ver si
// el numero se mueve, que es la unica forma barata de saberlo.
//
// Los tres cuentan la MISMA historia desde distinto sitio -- el vehiculo, el botin y la
// cara-- porque en Roblox no se sabe de antemano cual gana: las caras expresivas suelen
// funcionar muy bien, y a la vez un objeto dorado enorme es lo que mas se lee a 150 px.
const PIEZAS = [
  {
    id: "icono-a",
    ratio: "1:1",
    seed: 23,
    // EL VEHICULO. Una sola idea grande, que a 150 px no cabe una escena.
    //
    // Y EL TECHO SE LLENA CON ALGO, que es la unica forma de vaciarlo: las dos primeras
    // versiones salieron con barra de luces azul y roja --una ambulancia con cajas, o
    // sea lo contrario de lo que el juego dice-- y PROHIBIRLA no funciono. En estos
    // modelos un negativo a menudo refuerza lo que niega. Lo que funciono fue darle al
    // techo una lona atada: se describe lo que se quiere ver, no lo que no.
    prompt:
      "Square game icon. A battered red civilian cargo van at a low three-quarter front " +
      "angle, speeding toward the viewer down a night street, body tilted with motion. " +
      "A glowing golden crate sits among cardboard boxes in its open cargo bed, spilling " +
      "warm light. On top of the van, a folded canvas tarp is strapped down flat across " +
      "the whole roof with rope, covering it completely. Close behind, a masked thief on " +
      "a motorbike gives chase, headlight glaring. The van fills most of the frame.",
  },
  {
    id: "icono-b",
    ratio: "1:1",
    seed: 51,
    // EL BOTIN. Lo que mas se lee a tamano pequeno es un objeto grande y brillante, y
    // ademas dice de que va el juego sin explicar nada: esto vale mucho y alguien lo
    // quiere. Las manos cuentan el conflicto entero sin necesidad de una escena.
    prompt:
      "Square game icon, extreme close-up. A big glowing golden wooden crate held tight " +
      "by a pair of blocky cartoon hands, filling most of the frame. From the edges of " +
      "the frame, two other pairs of gloved hands in black grab at the crate, trying to " +
      "pull it away. Golden light bursts from the crate seams. Dark blurred night street " +
      "far behind, out of focus.",
  },
  {
    id: "icono-c",
    ratio: "1:1",
    seed: 88,
    // LA CARA. En Roblox las caras expresivas rinden muy bien en la cuadricula: una
    // expresion se lee a cualquier tamano y cuenta la emocion del juego --el susto de
    // que te alcancen-- que es justo lo que ni el vehiculo ni el botin dicen.
    prompt:
      "Square game icon. Close-up of a blocky Roblox-style character driving a van at " +
      "night, gripping the wheel, eyes wide with alarm, glancing at the rear-view mirror. " +
      "Reflected in the mirror: the glaring headlight of a masked thief on a motorbike " +
      "right behind. Warm golden light from cargo glows behind the driver's shoulder. " +
      "Face fills the upper half of the frame.",
  },
  {
    id: "miniatura-a",
    ratio: "16:9",
    seed: 7,
    // LA PERSECUCION, de lado: cuenta el juego entero de un vistazo -- llevas algo
    // valioso, te persiguen, y la ciudad es el tablero.
    prompt:
      "Wide cinematic game thumbnail. A red delivery van loaded with cardboard boxes and a " +
      "glowing golden crate races down a wide city avenue at night. Two masked thieves on " +
      "motorbikes chase close behind it, reaching for the cargo. Searchlight beams sweep " +
      "the street from the rooftops. Blocky stylized city buildings on both sides, wet " +
      "asphalt reflecting the lights. Sense of speed and chase, motion blur on the road.",
  },
  {
    id: "miniatura-b",
    ratio: "16:9",
    seed: 34,
    // EL MOMENTO DEL ROBO. La anterior ensena la persecucion; esta ensena lo que se
    // juega en ella. Un instante concreto se recuerda mejor que una situacion.
    prompt:
      "Wide cinematic game thumbnail. Action moment: a masked thief on a motorbike pulls " +
      "alongside a speeding red cargo van and rips a glowing golden crate out of its open " +
      "back, both hands on it, cardboard boxes tumbling onto the road. The van driver " +
      "leans out of the window shouting. Night city avenue, streaks of light, sparks on " +
      "the asphalt, strong motion blur.",
  },
  {
    id: "miniatura-c",
    ratio: "16:9",
    seed: 60,
    // LA CIUDAD COMO TABLERO. Las dos anteriores son primeros planos; esta ensena que
    // hay un MAPA que recorrer y decisiones que tomar, que es la otra mitad del juego y
    // lo que hace que alguien piense que hay algo que aprender aqui.
    prompt:
      "Wide cinematic game thumbnail, high angle looking down over a stylized blocky night " +
      "city with a grid of lit streets and a big roundabout. A tiny red van glows as it " +
      "races along one avenue leaving a bright light trail behind it; three motorbike " +
      "headlights converge on it from different streets. Warehouse district on one side, " +
      "tall buildings on the other, everything lit in deep blue with warm orange streets.",
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
      // Semilla por pieza: regenerar una no mueve a las demas.
      seed: pieza.seed,
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
