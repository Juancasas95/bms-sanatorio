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

console.log("Parcheando:", filePath);


// ======================================================
// PARCHE BMS - FUXA 1.3.4
//
// Problema:
// En modo Roles, permissionRoles puede ser undefined.
// FUXA intenta ejecutar:
//
//     u.show
//     u.enabled
//
// provocando:
//
// Cannot read properties of undefined (reading 'show')
//
// Solución:
// usar optional chaining exclusivamente dentro del
// bloque AuthService.checkPermission().
// ======================================================

const original =
    'if(u.show&&u.show.length&&(O.show=K.some(U=>u.show.includes(U)),ie.show=!1),u.enabled&&u.enabled.length&&(O.enabled=K.some(U=>u.enabled.includes(U)),ie.enabled=!1),ie.show&&ie.enabled)return ie';

const patched =
    'if(u?.show?.length&&(O.show=K.some(U=>u.show.includes(U)),ie.show=!1),u?.enabled?.length&&(O.enabled=K.some(U=>u.enabled.includes(U)),ie.enabled=!1),ie.show&&ie.enabled)return ie';


const originalCount =
    source.split(original).length - 1;

const patchedCount =
    source.split(patched).length - 1;


console.log(
    "Bloque original encontrado:",
    originalCount
);

console.log(
    "Bloque ya parcheado encontrado:",
    patchedCount
);


// ======================================================
// VALIDACIONES DE SEGURIDAD
// ======================================================

if (patchedCount === 1 && originalCount === 0) {

    console.log(
        "El parche ya estaba aplicado."
    );

    process.exit(0);
}


if (originalCount !== 1) {

    throw new Error(
        `Parche inseguro: esperaba exactamente 1 bloque AuthService original y encontró ${originalCount}`
    );
}


// ======================================================
// APLICAR PARCHE
// ======================================================

source =
    source.replace(
        original,
        patched
    );


// ======================================================
// VERIFICAR RESULTADO
// ======================================================

const finalOriginalCount =
    source.split(original).length - 1;

const finalPatchedCount =
    source.split(patched).length - 1;


if (
    finalOriginalCount !== 0 ||
    finalPatchedCount !== 1
) {

    throw new Error(
        "La validación posterior al parche falló."
    );
}


fs.writeFileSync(
    filePath,
    source,
    "utf8"
);


console.log(
    "Parche FUXA Roles aplicado correctamente."
);

console.log(
    "Original restante:",
    finalOriginalCount
);

console.log(
    "Parche aplicado:",
    finalPatchedCount
);
