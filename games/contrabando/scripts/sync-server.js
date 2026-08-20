// sync-server.js — mete el codigo en Studio SIN plugin, SIN Connect y SIN reabrir nada.
//
// POR QUE EXISTE. El ciclo de trabajo era: editar, matar Studio, borrar el .lock,
// reabrir el .rbxl y que JJ aprobara el dialogo. Lo dijo en una linea el 20/08 --"no
// puedo estar aprobando el connect todo el rato"-- y tenia razon: cada cambio de una
// linea le costaba un dialogo y perder la partida que estuviera jugando.
//
// Rojo ya resuelve esto, pero su plugin exige un Connect a mano cada vez que Studio
// arranca, y su API HTTP habla msgpack, que no merece reimplementarse en Luau. Asi
// que esto sirve lo mismo en JSON plano: un GET y ya.
//
// Al otro lado, `scripts/sync.luau` lo lee con HttpService y escribe cada `Source` en
// su instancia. La correspondencia fichero -> instancia NO se inventa: sale del
// sourcemap que genera el propio Rojo, asi que es exactamente la que usaria el plugin.
//
// Uso:  node scripts/sync-server.js        (se queda escuchando en el 34873)

const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const PUERTO = 34873;
const raiz = path.resolve(__dirname, "..");
const rojo = path.resolve(raiz, "..", "..", "tools", "rojo.exe");

// El sourcemap se regenera en cada peticion: un fichero nuevo no puede quedarse fuera
// porque el mapa sea de hace media hora. Cuesta milisegundos.
function sourcemap() {
	const salida = path.join(raiz, "sourcemap.json");
	execFileSync(rojo, ["sourcemap", "default.project.json", "--output", salida], { cwd: raiz });
	return JSON.parse(fs.readFileSync(salida, "utf8"));
}

// Aplana el arbol a una lista de { ruta, codigo }, donde `ruta` es el camino dentro
// del datamodel ("ReplicatedStorage/Shared/Config"). Se salta el nodo raiz, que es el
// propio DataModel y no tiene Source.
function recoger(nodo, camino, fuera) {
	const aqui = camino ? `${camino}/${nodo.name}` : nodo.name;
	const fichero = (nodo.filePaths || []).find((f) => f.endsWith(".luau"));
	if (fichero) {
		const abs = path.join(raiz, fichero);
		if (fs.existsSync(abs)) {
			// La CLASE viaja con el modulo para que el otro lado pueda CREARLO si no
			// existe. Sin esto, un fichero nuevo obligaba a recompilar el place y
			// reabrir Studio -- justo lo que este servidor venia a evitar.
			fuera.push({ ruta: aqui, clase: nodo.className || "ModuleScript", codigo: fs.readFileSync(abs, "utf8") });
		}
	}
	for (const hijo of nodo.children || []) {
		recoger(hijo, aqui, fuera);
	}
	return fuera;
}

http.createServer((req, res) => {
	if (!req.url.startsWith("/arbol")) {
		res.writeHead(404).end();
		return;
	}
	try {
		const arbol = sourcemap();
		const lista = [];
		for (const hijo of arbol.children || []) {
			recoger(hijo, "", lista);
		}
		const cuerpo = JSON.stringify(lista);
		res.writeHead(200, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(cuerpo) });
		res.end(cuerpo);
		console.log(`[sync] servidos ${lista.length} modulos`);
	} catch (e) {
		res.writeHead(500).end(String(e));
		console.error("[sync] fallo:", e.message);
	}
}).listen(PUERTO, "127.0.0.1", () => {
	console.log(`[sync] escuchando en http://127.0.0.1:${PUERTO}/arbol`);
	console.log("[sync] en Studio: ejecutar scripts/sync.luau desde el MCP (datamodel Edit)");
});
