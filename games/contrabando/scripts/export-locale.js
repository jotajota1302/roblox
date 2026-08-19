#!/usr/bin/env node
// Saca de Strings.luau el CSV que pide el portal de localizacion de Roblox.
//
//     node scripts/export-locale.js            -> escribe build/locale-en.csv
//     node scripts/export-locale.js --check    -> solo valida, no escribe
//
// COMO SE USA LO QUE SALE. Creator Dashboard -> tu experiencia -> Localization
// -> Upload CSV. Se sube UNA vez; luego se activan los idiomas y Roblox rellena
// las columnas con traduccion automatica. Las claves no se tocan nunca: son lo
// que empareja cada fila con el texto del juego.
//
// POR QUE ES UN SCRIPT Y NO SE HACE A MANO: la tabla ya tiene ~190 filas y el
// CSV tiene reglas de comillas propias. Y sobre todo, aqui se caza lo que Luau
// no puede cazar -- una clave repetida en una tabla de Lua NO da error, la
// segunda pisa a la primera en silencio. Eso solo se ve leyendo el fichero.
//
// NO SUBE NADA. Tocar la ficha publica del juego es una decision, no un efecto
// secundario de correr un script.

const fs = require("fs");
const path = require("path");

const RAIZ = path.join(__dirname, "..");
const FUENTE = path.join(RAIZ, "src", "shared", "Strings.luau");
const SALIDA = path.join(RAIZ, "build", "locale-en.csv");

const soloComprobar = process.argv.includes("--check");

// ---------------------------------------------------------------- extraer
//
// Se lee el fichero, no se ejecuta: no hay Luau fuera de Roblox. Basta con
// quedarse dentro del bloque `local TEXTOS = { ... }` y coger las lineas que
// tienen forma de `CLAVE = "texto",`.
const fuente = fs.readFileSync(FUENTE, "utf8");
const inicio = fuente.indexOf("local TEXTOS");
const fin = fuente.indexOf("\nStrings.TEXTOS = TEXTOS");
if (inicio === -1 || fin === -1 || fin < inicio) {
  console.error("No encuentro el bloque TEXTOS en " + FUENTE);
  process.exit(1);
}
const bloque = fuente.slice(inicio, fin);

const filas = [];
const repetidas = [];
const vistas = new Map();

for (const linea of bloque.split("\n")) {
  // Los comentarios llevan texto entrecomillado a menudo ("Cargar", "GUARIDA"),
  // asi que se descartan antes de mirar nada.
  if (/^\s*--/.test(linea)) continue;
  const m = linea.match(/^\s*([A-Z][A-Za-z0-9_]*)\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*$/);
  if (!m) continue;
  const [, clave, crudo] = m;
  // Solo hay dos escapes en juego: \n en la tarjeta del garaje y \" si algun dia
  // hace falta. Deshacerlos aqui deja el CSV con el texto tal cual se lee.
  const texto = crudo.replace(/\\n/g, "\n").replace(/\\"/g, '"');
  if (vistas.has(clave)) {
    repetidas.push(clave);
  }
  vistas.set(clave, texto);
  filas.push({ clave, texto });
}

// ------------------------------------------------------------- comprobar
const problemas = [];

if (repetidas.length) {
  problemas.push(
    "claves repetidas (la segunda pisa a la primera SIN AVISAR en Lua): " + repetidas.join(", ")
  );
}

for (const { clave, texto } of filas) {
  if (texto.trim() === "") {
    problemas.push(clave + " esta vacia");
  }
  if (/%[sdf]/.test(texto)) {
    problemas.push(clave + ' usa string.format ("%s"/"%d"): eso no se puede traducir');
  }
  for (const hueco of texto.match(/\{[^}]*\}/g) || []) {
    if (!/^\{[A-Za-z0-9_]+\}$/.test(hueco)) {
      problemas.push(clave + " tiene un parametro mal escrito: " + hueco);
    }
  }
}

if (problemas.length) {
  console.error("PROBLEMAS:\n  · " + problemas.join("\n  · "));
  process.exit(1);
}

// ------------------------------------------------------------------- csv
function celda(valor) {
  // Regla del CSV: se entrecomilla si hay coma, comillas o salto de linea, y las
  // comillas de dentro se duplican.
  if (/[",\n]/.test(valor)) {
    return '"' + valor.replace(/"/g, '""') + '"';
  }
  return valor;
}

// El "Context" y el "Example" los usa quien traduce para saber de que va la
// frase. El contexto sale del prefijo de la clave, que es justamente por lo que
// las claves llevan prefijo.
const CONTEXTO = {
  HUD: "Status panel",
  MISSION: "Current objective line",
  ACTION: "On-screen controls",
  COMPASS: "Compass",
  PICKER: "Route picker",
  ROUTE: "Routes",
  GOAL: "Milestones",
  RIDE: "Vehicles",
  SIZE: "Item sizes",
  GOODS: "Goods",
  RARITY: "Item rarity",
  SKILL: "Skills",
  MENU: "Side menu",
  GATE: "Yard gate",
  GARAGE: "Workshop garage",
  STOCK: "Warehouse dock",
  OFFICE: "Warehouse office",
  NAMEPLATE: "Player nameplates",
  THIEF: "Thieves",
  SIGN: "World signs",
  PROMPT: "World interaction prompts",
  SHOWROOM: "Vehicle showroom",
  CARGO: "Delivery messages",
  BACKPACK: "Carried cargo label",
  CONTACT: "Contacts",
  DECOY: "Decoy",
  HEAT: "Heat and pursuit",
  CHASE: "Heat and pursuit",
  ROBBED: "Heat and pursuit",
  WAREHOUSE: "Warehouse",
  DENY: "Refusal messages",
};

const lineas = ["Key,Source,Context,Example,en"];
for (const { clave, texto } of filas) {
  const contexto = CONTEXTO[clave.split("_")[0]] || "Game";
  // El ejemplo: la frase con los huecos rellenos de algo plausible, para que
  // quien traduce vea la forma final y no una plantilla.
  const ejemplo = texto.replace(/\{([A-Za-z0-9_]+)\}/g, (_, nombre) =>
    /nivel|coste|precio|monedas|items|cuantas|tope|ritmo|metros|segundos|total|hechas|actual|peldano|capacidad|velocidad|maximo|huecos|fichadas|guaridas|contactos|multiplicador/.test(
      nombre
    )
      ? "3"
      : "..."
  );
  lineas.push(
    [celda(clave), celda(texto), celda(contexto), celda(ejemplo), celda(texto)].join(",")
  );
}

console.log(filas.length + " textos, sin problemas");

if (soloComprobar) {
  process.exit(0);
}

fs.mkdirSync(path.dirname(SALIDA), { recursive: true });
fs.writeFileSync(SALIDA, lineas.join("\n") + "\n", "utf8");
console.log("escrito " + path.relative(RAIZ, SALIDA));
