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


# ======================================================
# 2. TIMESTAMP
# ======================================================

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

BACKUP_NAME="bms-backup-${TIMESTAMP}"

ARCHIVE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

CHECKSUM="${ARCHIVE}.sha256"

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
    git -C "${PROJECT_ROOT}" status --short

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

NODE_RED_FILES=()


for file in \
    nodered/.config.nodes.json \
    nodered/.config.runtime.json \
    nodered/.config.users.json \
    nodered/flows_cred.json

do

    if (
        [[ -f "${PROJECT_ROOT}/${file}" ]]
    ); then

        NODE_RED_FILES+=(
            "${file}"
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
    "${NODE_RED_FILES[@]}" \
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
# 13. CHECKSUM
# ======================================================

echo
echo "Generando SHA-256..."


sha256sum "${ARCHIVE}" \
    > "${CHECKSUM}"


# ======================================================
# 14. RESULTADO
# ======================================================

BACKUP_OK=true


echo
echo "========================================"
echo "BACKUP OK"
echo "========================================"

echo
echo "Archivo:"
echo "${ARCHIVE}"

echo
echo "Checksum:"
echo "${CHECKSUM}"

echo
echo "Tamaño:"
du -h "${ARCHIVE}" |
    cut -f1

echo
echo "SHA-256:"
cat "${CHECKSUM}"
