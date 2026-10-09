"use strict";

// ============================================================
// BMS SANATORIO
// PATCH node-red-contrib-whatsapp-api 0.1.2
// ============================================================
//
// Motivo:
//
// La red del sanatorio no permite a Baileys acceder
// directamente a Internet.
//
// El acceso debe realizarse mediante:
//
//   HTTP_PROXY
//   HTTPS_PROXY
//
// Baileys no aplica automáticamente estas variables en:
//
//   1. WebSocket de WhatsApp Web
//   2. Consulta de:
//        https://web.whatsapp.com/sw.js
//
// Este script modifica el bundle instalado de
// node-red-contrib-whatsapp-api para utilizar:
//
//   HttpsProxyAgent
//
// El script es:
//
//   - reproducible
//   - idempotente
//   - específico para versión 0.1.2
//
// Se ejecuta automáticamente mediante npm postinstall.
//
// ============================================================

const fs =
    require("fs");

const path =
    require("path");


// ============================================================
// RUTAS
// ============================================================

const projectDir =
    path.resolve(
        __dirname,
        ".."
    );


const packageDir =
    path.join(
        projectDir,
        "node_modules",
        "node-red-contrib-whatsapp-api"
    );


const packageJsonPath =
    path.join(
        packageDir,
        "package.json"
    );


const targetFile =
    path.join(
        packageDir,
        "dist",
        "nodes",
        "whatsapp-api.js"
    );


// ============================================================
// VALIDAR PAQUETE
// ============================================================

if (!fs.existsSync(packageJsonPath)) {

    console.error(
        "ERROR: node-red-contrib-whatsapp-api no está instalado."
    );

    process.exit(1);
}


if (!fs.existsSync(targetFile)) {

    console.error(
        "ERROR: no existe el bundle de WhatsApp:"
    );

    console.error(
        targetFile
    );

    process.exit(1);
}


const packageInfo =
    JSON.parse(
        fs.readFileSync(
            packageJsonPath,
            "utf8"
        )
    );


if (packageInfo.version !== "0.1.2") {

    console.error(
        "ERROR: versión de node-red-contrib-whatsapp-api no soportada:"
    );

    console.error(
        packageInfo.version
    );

    console.error(
        "El parche fue validado únicamente para 0.1.2."
    );

    process.exit(1);
}


// ============================================================
// LEER BUNDLE
// ============================================================

let source =
    fs.readFileSync(
        targetFile,
        "utf8"
    );


let changed =
    false;


// ============================================================
// PATCH 1
//
// fetchLatestWaWebVersion
//
// Axios debe utilizar explícitamente HttpsProxyAgent.
// proxy:false evita que Axios intente procesar el proxy
// nuevamente por su propia lógica.
// ============================================================

const originalVersionFetch = `var fetchLatestWaWebVersion = async (options) => {
  try {
    const { data } = await axios_default.get("https://web.whatsapp.com/sw.js", {
      ...options,
      responseType: "json"
    });`;


const patchedVersionFetch = `var fetchLatestWaWebVersion = async (options) => {
  try {
    const { HttpsProxyAgent } = require("https-proxy-agent");

    const proxyUrl =
      process.env.HTTPS_PROXY ||
      process.env.HTTP_PROXY;

    const requestOptions = {
      ...options,
      responseType: "json"
    };

    if (proxyUrl) {
      requestOptions.httpsAgent = new HttpsProxyAgent(proxyUrl);
      requestOptions.proxy = false;
    }

    const { data } = await axios_default.get(
      "https://web.whatsapp.com/sw.js",
      requestOptions
    );`;


if (source.includes(patchedVersionFetch)) {

    console.log(
        "WhatsApp proxy patch: sw.js YA APLICADO"
    );

}
else if (source.includes(originalVersionFetch)) {

    source =
        source.replace(
            originalVersionFetch,
            patchedVersionFetch
        );

    changed =
        true;

    console.log(
        "WhatsApp proxy patch: sw.js APLICADO"
    );

}
else {

    console.error(
        "ERROR: no se encontró el bloque esperado de fetchLatestWaWebVersion."
    );

    console.error(
        "El bundle puede haber cambiado."
    );

    process.exit(1);
}


// ============================================================
// PATCH 2
//
// defaultSocketFactory
//
// Baileys necesita un agente de proxy explícito para
// establecer el WebSocket con WhatsApp.
// ============================================================

const originalSocketFactory = `async function defaultSocketFactory(options) {
  const version2 = await resolveWaWebVersion();
  return lib_default({
    auth: options.auth,
    browser: Browsers.macOS("Node-RED"),
    markOnlineOnConnect: false,
    printQRInTerminal: false,
    syncFullHistory: false,
    ...version2 ? { version: version2 } : {}
  });
}`;


const patchedSocketFactory = `async function defaultSocketFactory(options) {
  const version2 = await resolveWaWebVersion();

  const { HttpsProxyAgent } = require("https-proxy-agent");

  const proxyUrl =
    process.env.HTTPS_PROXY ||
    process.env.HTTP_PROXY;

  const proxyAgent =
    proxyUrl
      ? new HttpsProxyAgent(proxyUrl)
      : undefined;

  return lib_default({
    auth: options.auth,
    browser: Browsers.macOS("Node-RED"),
    markOnlineOnConnect: false,
    printQRInTerminal: false,
    syncFullHistory: false,

    ...(proxyAgent
      ? {
          agent: proxyAgent,
          fetchAgent: proxyAgent
        }
      : {}),

    ...version2 ? { version: version2 } : {}
  });
}`;


if (source.includes(patchedSocketFactory)) {

    console.log(
        "WhatsApp proxy patch: WebSocket YA APLICADO"
    );

}
else if (source.includes(originalSocketFactory)) {

    source =
        source.replace(
            originalSocketFactory,
            patchedSocketFactory
        );

    changed =
        true;

    console.log(
        "WhatsApp proxy patch: WebSocket APLICADO"
    );

}
else {

    console.error(
        "ERROR: no se encontró el bloque esperado de defaultSocketFactory."
    );

    console.error(
        "El bundle puede haber cambiado."
    );

    process.exit(1);
}


// ============================================================
// ESCRIBIR RESULTADO
// ============================================================

if (changed) {

    fs.writeFileSync(
        targetFile,
        source,
        "utf8"
    );

    console.log(
        "WhatsApp proxy patch: COMPLETADO"
    );

}
else {

    console.log(
        "WhatsApp proxy patch: no fue necesario modificar archivos."
    );
}
