#!/usr/bin/env bash

# ======================================================
# BMS SANATORIO - BACKUP
# ======================================================
#
# Backup consistente del estado persistente que
# no puede reconstruirse únicamente desde Git.
#
# Incluye:
#
#   FUXA
#     - appdata
#     - db
#     - images
#
#   Node-RED
#     - configuración runtime relevante
#     - credenciales si existen
#
#   Mosquitto
#     - data/
#
# Además:
#     - manifest
#     - validación tar.gz
#     - checksum SHA-256
#
# ======================================================

set -Eeuo pipefail


# ======================================================
# 1. RUTAS
# ======================================================

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

PROJECT_ROOT="$(
    cd "${SCRIPT_DIR}/.."
    pwd
)"

COMPOSE_FILE="${PROJECT_ROOT}/docker/docker-compose.yml"

BACKUP_DIR="${PROJECT_ROOT}/backups"

AGE_RECIPIENT_FILE="${PROJECT_ROOT}/config/backup-age-recipient.txt"


# ======================================================
# 2. TIMESTAMP
# ======================================================

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

BACKUP_NAME="bms-backup-${TIMESTAMP}"

ARCHIVE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

ENCRYPTED_ARCHIVE="${ARCHIVE}.age"

CHECKSUM="${ENCRYPTED_ARCHIVE}.sha256"

TMP_DIR="$(mktemp -d)"

MANIFEST="${TMP_DIR}/manifest.txt"


# ======================================================
# 3. ESTADO
# ======================================================

BACKUP_OK=false

RUNNING_SERVICES=()


# ======================================================
# 4. LIMPIEZA / RECUPERACIÓN
# ======================================================

cleanup() {

    local exit_code=$?


    echo
    echo "========================================"
    echo "RESTAURANDO SERVICIOS"
    echo "========================================"


    if (
        ((${#RUNNING_SERVICES[@]} > 0))
    ); then

        docker compose \
            -f "${COMPOSE_FILE}" \
            start \
            "${RUNNING_SERVICES[@]}" \
            >/dev/null

    fi


    # --------------------------------------------------
    # SI FALLÓ, ELIMINAR ARCHIVOS INCOMPLETOS
    # --------------------------------------------------

    if (
        [[ "${BACKUP_OK}" != "true" ]]
    ); then

        rm -f \
            "${ARCHIVE}" \
            "${ENCRYPTED_ARCHIVE}" \
            "${CHECKSUM}"
    fi


    rm -rf "${TMP_DIR}"


    if (
        [[ "${BACKUP_OK}" == "true" ]]
    ); then

        echo
        echo "Servicios restaurados."
        echo "Backup finalizado correctamente."

    else

        echo
        echo "Servicios restaurados."
        echo "El backup NO terminó correctamente."
        echo "Los archivos incompletos fueron eliminados."
    fi


    exit "${exit_code}"
}


trap cleanup EXIT


# ======================================================
# 5. VALIDACIONES
# ======================================================

echo "========================================"
echo "BMS BACKUP"
echo "========================================"

echo
echo "Proyecto:"
echo "${PROJECT_ROOT}"


if (
    [[ ! -f "${COMPOSE_FILE}" ]]
); then

    echo "ERROR: no existe ${COMPOSE_FILE}"
    exit 1
fi


mkdir -p "${BACKUP_DIR}"


# ======================================================
# 5A. VALIDAR DIRECTORIO DE BACKUP
# ======================================================

echo
echo "Validando directorio de backup..."


WRITE_TEST="${BACKUP_DIR}/.bms-backup-write-test.$$"


if ! touch "${WRITE_TEST}" 2>/dev/null; then

    echo "ERROR:"
    echo "El directorio de backup no es escribible:"
    echo "${BACKUP_DIR}"
    echo
    echo "Propietario/permisos actuales:"

    stat \
        -c '%A | %a | %U:%G | UID=%u GID=%g | %n' \
        "${BACKUP_DIR}" \
        2>/dev/null \
        || true

    exit 1

fi


rm -f "${WRITE_TEST}"


echo "BACKUP DIR OK"


# ======================================================
# 5B. VALIDAR AGE
# ======================================================

echo
echo "Validando cifrado age..."


if ! command -v age >/dev/null 2>&1; then

    echo "ERROR: age no está instalado."
    exit 1

fi


if [[ ! -f "${AGE_RECIPIENT_FILE}" ]]; then

    echo "ERROR: no existe la clave pública de backup:"
    echo "${AGE_RECIPIENT_FILE}"
    exit 1

fi


AGE_RECIPIENT="$(
    tr -d '\r\n' \
        < "${AGE_RECIPIENT_FILE}"
)"


if [[ -z "${AGE_RECIPIENT}" ]]; then

    echo "ERROR: backup-age-recipient.txt está vacío."
    exit 1

fi


if ! printf 'BMS AGE TEST' \
    | age \
        -r "${AGE_RECIPIENT}" \
        >/dev/null 2>&1
then

    echo "ERROR: recipient age inválido."
    exit 1

fi


echo "AGE OK"


# ======================================================
# 5C. VALIDAR GIT
# ======================================================

echo
echo "Validando estado Git..."


if ! git \
    -C "${PROJECT_ROOT}" \
    rev-parse \
    --is-inside-work-tree \
    >/dev/null 2>&1
then

    echo "ERROR: el proyecto no es un repositorio Git."
    exit 1

fi


GIT_STATUS="$(
    git \
        -C "${PROJECT_ROOT}" \
        status \
        --short
)"


ALLOW_DIRTY="${BMS_BACKUP_ALLOW_DIRTY:-false}"


if [[ -n "${GIT_STATUS}" ]]; then

    echo
    echo "Repositorio Git con cambios:"
    echo
    printf '%s\n' "${GIT_STATUS}"
    echo

    if [[ "${ALLOW_DIRTY}" != "true" ]]; then

        echo "ERROR:"
        echo "El backup normal requiere un repositorio Git limpio."
        echo
        echo "Para una prueba excepcional puede utilizarse:"
        echo
        echo "BMS_BACKUP_ALLOW_DIRTY=true ./scripts/backup.sh"

        exit 1

    fi

    echo "AVISO:"
    echo "Se permitió backup con Git sucio mediante override."

else

    echo "Git status: CLEAN"

fi


# ======================================================
# 6. SERVICIOS ACTIVOS
# ======================================================

echo
echo "Detectando servicios activos..."


mapfile -t CURRENT_RUNNING < <(
    docker compose \
        -f "${COMPOSE_FILE}" \
        ps \
        --services \
        --filter status=running
)


for service in \
    mosquitto \
    nodered \
    fuxa \
    nginx

do

    for running in "${CURRENT_RUNNING[@]}"

    do

        if (
            [[ "${service}" == "${running}" ]]
        ); then

            RUNNING_SERVICES+=(
                "${service}"
            )
        fi

    done

done


echo
echo "Servicios activos antes del backup:"


if (
    ((${#RUNNING_SERVICES[@]} == 0))
); then

    echo "  ninguno"

else

    printf '  %s\n' "${RUNNING_SERVICES[@]}"

fi


# ======================================================
# 7. MANIFEST
# ======================================================

{
    echo "BMS SANATORIO - BACKUP MANIFEST"

    echo
    echo "Fecha:"
    date --iso-8601=seconds

    echo
    echo "Hostname:"
    hostname

    echo
    echo "Git commit:"
    git -C "${PROJECT_ROOT}" rev-parse HEAD

    echo
    echo "Git branch:"
    git -C "${PROJECT_ROOT}" branch --show-current

    echo
    echo "Git status:"

    if [[ -z "${GIT_STATUS}" ]]; then
        echo "CLEAN"
    else
        printf '%s\n' "${GIT_STATUS}"
    fi

    echo
    echo "Docker:"
    docker --version

    echo
    echo "Docker Compose:"
    docker compose version

    echo
    echo "Imágenes:"
    docker compose \
        -f "${COMPOSE_FILE}" \
        images

    echo
    echo "Servicios activos antes del backup:"
    printf '%s\n' "${RUNNING_SERVICES[@]}"

} > "${MANIFEST}"


# ======================================================
# 8. DETENER SERVICIOS
# ======================================================

if (
    ((${#RUNNING_SERVICES[@]} > 0))
); then

    echo
    echo "Deteniendo temporalmente servicios..."

    docker compose \
        -f "${COMPOSE_FILE}" \
        stop \
        "${RUNNING_SERVICES[@]}"

fi


# ======================================================
# 9. PREPARAR MOSQUITTO
# ======================================================
#
# mosquitto.db pertenece normalmente a:
#
#     UID 1883
#     GID 1883
#     permisos 600
#
# Por eso el usuario del host no puede leerlo.
#
# Usamos temporalmente la MISMA imagen de Mosquitto
# ejecutada como root para copiar los datos a TMP_DIR.
#
# NO modificamos permisos del archivo original.
#
# ======================================================

echo
echo "Preparando datos persistentes de Mosquitto..."


mkdir -p \
    "${TMP_DIR}/mosquitto/data"


HOST_UID="$(id -u)"
HOST_GID="$(id -g)"


docker run \
    --rm \
    --user 0:0 \
    -v "${PROJECT_ROOT}/mosquitto/data:/source:ro" \
    -v "${TMP_DIR}/mosquitto/data:/destination" \
    eclipse-mosquitto:2.0 \
    sh -c "
        cp -a /source/. /destination/ &&
        chown -R ${HOST_UID}:${HOST_GID} /destination
    "


# ======================================================
# 10. NODE-RED OPCIONAL
# ======================================================
#
# Runtime que no se reconstruye únicamente desde Git.
#
# whatsapp-api contiene las sesiones de autenticación
# de Baileys utilizadas por WhatsApp QR.
#
# IMPORTANTE:
#   - se incluye dentro del backup CIFRADO
#   - NO debe versionarse en Git
#   - node_modules NO se respalda
#
# ======================================================

NODE_RED_PATHS=()


for path in \
    nodered/.config.nodes.json \
    nodered/.config.runtime.json \
    nodered/.config.users.json \
    nodered/flows_cred.json \
    nodered/whatsapp-api

do

    if (
        [[ -e "${PROJECT_ROOT}/${path}" ]] ||
        [[ -L "${PROJECT_ROOT}/${path}" ]]
    ); then

        NODE_RED_PATHS+=(
            "${path}"
        )
    fi

done


# ======================================================
# 11. CREAR BACKUP
# ======================================================

echo
echo "Creando:"
echo "${ARCHIVE}"


cd "${PROJECT_ROOT}"


tar \
    -czf "${ARCHIVE}" \
    fuxa/appdata \
    fuxa/db \
    fuxa/images \
    "${NODE_RED_PATHS[@]}" \
    -C "${TMP_DIR}" \
    mosquitto/data \
    manifest.txt


# ======================================================
# 12. VALIDAR ARCHIVO
# ======================================================

echo
echo "Verificando integridad del archivo..."


tar \
    -tzf "${ARCHIVE}" \
    >/dev/null


# ======================================================
# 13. CIFRAR BACKUP
# ======================================================

echo
echo "Cifrando backup con age..."


age \
    -r "${AGE_RECIPIENT}" \
    -o "${ENCRYPTED_ARCHIVE}" \
    "${ARCHIVE}"


if [[ ! -s "${ENCRYPTED_ARCHIVE}" ]]; then

    echo "ERROR: el archivo cifrado está vacío."
    exit 1

fi


echo "CIFRADO OK"


# ======================================================
# 14. CHECKSUM PORTABLE
# ======================================================

echo
echo "Generando SHA-256 portable..."


(
    cd "${BACKUP_DIR}"

    sha256sum \
        "$(basename "${ENCRYPTED_ARCHIVE}")" \
        > "$(basename "${CHECKSUM}")"
)


echo "Verificando SHA-256..."


(
    cd "${BACKUP_DIR}"

    sha256sum \
        -c "$(basename "${CHECKSUM}")"
)


# ======================================================
# 15. ELIMINAR BACKUP SIN CIFRAR
# ======================================================

rm -f "${ARCHIVE}"


if [[ -e "${ARCHIVE}" ]]; then

    echo "ERROR: no se pudo eliminar el backup sin cifrar."
    exit 1

fi


echo "Backup sin cifrar eliminado."


# ======================================================
# 16. RESULTADO
# ======================================================

BACKUP_OK=true


echo
echo "========================================"
echo "BACKUP OK"
echo "========================================"

echo
echo "Archivo cifrado:"
echo "${ENCRYPTED_ARCHIVE}"

echo
echo "Checksum:"
echo "${CHECKSUM}"

echo
echo "Tamaño:"
du -h "${ENCRYPTED_ARCHIVE}" |
    cut -f1

echo
echo "SHA-256:"
cat "${CHECKSUM}"

echo
echo "IMPORTANTE:"
echo "El backup sin cifrar NO permanece almacenado."
echo "La clave privada de recuperación NO debe existir en este servidor."
