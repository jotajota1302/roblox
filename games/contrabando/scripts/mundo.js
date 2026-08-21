#!/usr/bin/env node
/**
 * mundo.js — construye la ciudad en memoria y le pasa las sondas, sin Studio.
 *
 * Hermano de `banco.js`. Aquel corre las reglas (los modulos puros); este corre el
 * MAPA: ejecuta `MapBuilder.buildCiudad` contra un `Instance` de mentira y mide lo
 * que sale -- cuantas piezas, si algo del mapa pisa el carril, si alguna manzana se
 * queda vacia, y si hay caras coplanares (el parpadeo, que es el defecto que este
 * mapa lleva pagando desde que existe).
 *
 * POR QUE HACE FALTA. `MapBuilder` es el fichero que mas fallos ha dado, y todos de
 * la misma familia: no revientan, se VEN. Un edificio sobre la calzada, un solar sin
 * nada dentro, dos losas a la misma cota. Mirarlo costaba abrir Studio y jugar; aqui
 * cuesta dos segundos, y por eso se puede mirar en cada cambio.
 *
 * LO QUE NO SUSTITUYE: `SelfCheck`. Alli hay raycasts, suelo de verdad, pathfinding y
 * todo lo que `CityBuilder` planta encima del mapa. Esto comprueba lo que el mapa
 * DICE que planta; SelfCheck, el mundo que sale.
 *
 * No entra en `verificar.ps1` a proposito: depende de un `Instance` simulado y por
 * tanto es mas fragil que los otros pasos. Se lanza a mano al tocar el mapa.
 *
 *   node scripts/mundo.js
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const JUEGO = path.resolve(__dirname, "..");
const SHARED = path.join(JUEGO, "src", "shared");
const BANCO = path.join(__dirname, "banco");
const LUAU = path.resolve(JUEGO, "..", "..", "tools", "luau.exe");

function envolver(clave, fichero) {
	return `FUENTES["${clave}"] = function(script)\n${fs.readFileSync(fichero, "utf8")}\nend\n`;
}

const partes = [
	fs.readFileSync(path.join(BANCO, "prologo.luau"), "utf8"),
	fs.readFileSync(path.join(BANCO, "instancias.luau"), "utf8"),
	"\nlocal FUENTES: any = {}\n",
];

for (const f of fs.readdirSync(SHARED).sort()) {
	if (f.endsWith(".luau")) partes.push(envolver(f.slice(0, -5), path.join(SHARED, f)));
}
// Los tres modulos de servidor que construyen o deciden el mapa. No hace falta mas:
// lo que planta `CityBuilder` encima necesita raycasts, y eso es cosa de SelfCheck.
for (const nombre of ["MapBuilder", "StreetProps", "Destinations"]) {
	partes.push(envolver("server/" + nombre, path.join(JUEGO, "src", "server", nombre + ".luau")));
}

partes.push(fs.readFileSync(path.join(BANCO, "mundo.luau"), "utf8"));

const generado = path.join(os.tmpdir(), "contrabando-mundo.luau");
fs.writeFileSync(generado, partes.join(""));

if (!fs.existsSync(LUAU)) {
	console.error("falta tools/luau.exe -- ejecuta setup.ps1");
	process.exit(2);
}
const r = spawnSync(LUAU, [generado], { stdio: "inherit" });
process.exit(r.status === 0 ? 0 : 1);
