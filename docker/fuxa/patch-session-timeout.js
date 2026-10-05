const fs = require("fs");
const path = require("path");

const distDir = "/usr/src/app/FUXA/client/dist";

const mainFile = fs
    .readdirSync(distDir)
    .find(file => /^main\..*\.js$/.test(file));

if (!mainFile) {
    throw new Error("No se encontró main.*.js de FUXA");
}

const filePath = path.join(distDir, mainFile);

let source = fs.readFileSync(filePath, "utf8");

console.log("Parcheando timeout de sesión:", filePath);


// ======================================================
// FUXA 1.3.4
//
// Original:
// heartbeatInterval = 3e5
// 300000 ms = 5 minutos
//
// BMS:
// heartbeatInterval = 9e5
// 900000 ms = 15 minutos
// ======================================================

const original =
    "heartbeatInterval=3e5;server;heartbeatSubscription;activity=!1;constructor";

const patched =
    "heartbeatInterval=9e5;server;heartbeatSubscription;activity=!1;constructor";


const originalCount =
    source.split(original).length - 1;

const patchedCount =
    source.split(patched).length - 1;


console.log(
    "Heartbeat original 5 min:",
    originalCount
);

console.log(
    "Heartbeat parcheado 15 min:",
    patchedCount
);


// Ya estaba parcheado
if (originalCount === 0 && patchedCount === 1) {

    console.log(
        "Timeout de sesión ya estaba parcheado."
    );

    process.exit(0);
}


// Seguridad
if (originalCount !== 1) {

    throw new Error(
        `Parche inseguro: esperaba 1 heartbeat de 5 min y encontró ${originalCount}`
    );
}


// Aplicar
source = source.replace(
    original,
    patched
);


// Validación final
const finalOriginal =
    source.split(original).length - 1;

const finalPatched =
    source.split(patched).length - 1;


if (
    finalOriginal !== 0 ||
    finalPatched !== 1
) {

    throw new Error(
        "Falló la validación del parche de timeout."
    );
}


fs.writeFileSync(
    filePath,
    source,
    "utf8"
);


console.log(
    "Timeout FUXA cambiado correctamente: 5 min -> 15 min."
);
