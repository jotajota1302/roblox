#!/usr/bin/env node
/**
 * banco.js — corre las pruebas PURAS sin abrir Roblox Studio.
 *
 * POR QUE EXISTE. Hasta hoy la bateria pura vivia dentro de Studio: se lanzaba por
 * MCP con `require(...TestRunner).run()`, y eso significaba que verificar un cambio
 * costaba abrir Studio, esperar a que cargara el place, y gastar una llamada del MCP
 * --que le pide permiso al usuario cada vez--. En la practica se traducia en que
 * `verificar.ps1` daba "TODO OK" habiendo comprobado formato, simbolos y compilacion,
 * pero NINGUNA de las 1.250 pruebas. El paso 4 del script lo decia con todas las
 * letras: "lo que NO se puede comprobar aqui".
 *
 * Si se puede. Los modulos de `shared/` son puros por diseno --esa es la regla de la
 * casa-- y lo unico que les hace falta de Roblox son cuatro tipos de datos: Vector3,
 * Color3, CFrame y Random. `tools/luau.exe` ejecuta Luau de verdad; el resto es
 * darle esos cuatro tipos y un arbol de modulos que responda a `script.Parent`.
 *
 * COMO. El CLI de Luau no tiene `io`, asi que no puede leer los .luau del disco: los
 * embebe ESTE script. Cada modulo se envuelve en `function(script) ... end` dentro de
 * un fichero generado, y `require` se sombrea con un local que devuelve el modulo ya
 * construido. Al ser funciones del mismo fichero, capturan Vector3 y compania como
 * upvalues sin tocar `setfenv`.
 *
 * LO QUE ESTO NO SUSTITUYE: las sondas del mundo (`SelfCheck`) siguen necesitando una
 * partida de verdad. Aqui se comprueban las reglas; alli, que el mundo las cumple.
 * Y "que se vea bien" no lo dice ninguna de las dos.
 *
 *   node scripts/banco.js            todas las suites
 *   node scripts/banco.js Grid       solo una (o varias, separadas por espacios)
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const JUEGO = path.resolve(__dirname, "..");
const SHARED = path.join(JUEGO, "src", "shared");
const LUAU = path.resolve(JUEGO, "..", "..", "tools", "luau.exe");

function envolver(clave, fichero) {
	const src = fs.readFileSync(fichero, "utf8");
	return `FUENTES["${clave}"] = function(script)\n${src}\nend\n`;
}

const partes = [
	fs.readFileSync(path.join(__dirname, "banco", "prologo.luau"), "utf8"),
	"\nlocal FUENTES: any = {}\n",
];

for (const f of fs.readdirSync(SHARED).sort()) {
	if (f.endsWith(".luau")) partes.push(envolver(f.slice(0, -5), path.join(SHARED, f)));
}
const tests = path.join(SHARED, "tests");
for (const f of fs.readdirSync(tests).sort()) {
	if (f.endsWith(".luau")) partes.push(envolver("tests/" + f.slice(0, -5), path.join(tests, f)));
}

// Y el unico modulo de servidor que pide una prueba pura: `Destinations`, que es puro
// de verdad --solo depende de Config, Grid y Perimeter-- aunque viva en `server/`
// porque es el servidor quien sortea los destinos al arrancar.
partes.push(envolver("server/Destinations", path.join(JUEGO, "src", "server", "Destinations.luau")));

partes.push(fs.readFileSync(path.join(__dirname, "banco", "epilogo.luau"), "utf8"));

const generado = path.join(os.tmpdir(), "contrabando-banco.luau");
fs.writeFileSync(generado, partes.join(""));

if (!fs.existsSync(LUAU)) {
	console.error("falta tools/luau.exe -- ejecuta setup.ps1");
	process.exit(2);
}

const r = spawnSync(LUAU, [generado, ...process.argv.slice(2)], { stdio: "inherit" });
// El arnes revienta con `error` si algo falla, asi que el codigo de salida de Luau ya
// distingue verde de rojo y este script solo tiene que propagarlo.
process.exit(r.status === 0 ? 0 : 1);
