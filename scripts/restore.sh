#!/usr/bin/env bash

# ============================================================
# BMS SANATORIO - RESTORE
# ============================================================
#
# Modos:
#
#   --check
#       Valida backup y entorno.
#       NO modifica el BMS.
#
#   --restore
#       Restaura los datos persistentes.
#
# IMPORTANTE:
#
# - El código y flows.json provienen de Git.
# - Este script restaura únicamente datos/runtime persistentes.
# - Los servicios quedan DETENIDOS al finalizar.
# - Si ocurre un error durante la restauración, se intenta
#   recuperar automáticamente el estado anterior.
#
# Uso:
#
#   ./scripts/restore.sh BACKUP.tar.gz --check
#
#   ./scripts/restore.sh BACKUP.tar.gz --restore
#
# ============================================================

set -Eeuo pipefail


# ============================================================
# ESTADO GLOBAL
# ============================================================

ROLLBACK_ARMED=false
ROLLBACK_IN_PROGRESS=false
RESTORE_SUCCESS=false
MOSQUITTO_PRESERVED=false

TMP_DIR=""
ROLLBACK_ROOT=""

declare -a PRESERVED_PATHS=()


# ============================================================
# FUNCIONES GENERALES
# ============================================================

info() {

    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}


cleanup() {

    if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}


restore_previous_state() {

    if [[ "${ROLLBACK_ARMED}" != "true" ]]; then
        return 0
    fi

    if [[ "${ROLLBACK_IN_PROGRESS}" == "true" ]]; then
        return 0
    fi

    ROLLBACK_IN_PROGRESS=true
    ROLLBACK_ARMED=false

    trap - ERR

    set +e

    local rollback_failed=0

    echo
    echo "============================================================"
    echo "ROLLBACK AUTOMÁTICO"
    echo "============================================================"
    echo
    echo "La restauración no terminó correctamente."
    echo "Intentando recuperar el estado anterior..."
    echo


    # ========================================================
    # RESTAURAR PATHS NORMALES
    # ========================================================
    #
    # Sólo se modifica una ruta si previamente fue preservada.
    #
    # Esto evita borrar una ruta cuyo backup de rollback
    # nunca llegó a completarse.
    #
    # ========================================================

    local relative_path
    local rollback_path
    local destination_path


    for relative_path in "${PRESERVED_PATHS[@]}"; do

        rollback_path="${ROLLBACK_ROOT}/${relative_path}"
        destination_path="${PROJECT_ROOT}/${relative_path}"


        if [[ -e "${rollback_path}" || -L "${rollback_path}" ]]; then

            echo "Recuperando: ${relative_path}"


            if ! rm -rf "${destination_path}"; then

                echo "ERROR eliminando estado parcial: ${relative_path}"

                rollback_failed=1

                continue
            fi


            if ! mkdir -p "$(
                dirname "${destination_path}"
            )"; then

                echo "ERROR creando destino: ${relative_path}"

                rollback_failed=1

                continue
            fi


            if ! mv \
                "${rollback_path}" \
                "${destination_path}"
            then

                echo "ERROR restaurando: ${relative_path}"

                rollback_failed=1
            fi
        fi

    done


    # ========================================================
    # RESTAURAR MOSQUITTO
    # ========================================================
    #
    # mosquitto/data pertenece a UID/GID 1883.
    #
    # No se manipula directamente desde el usuario host.
    # Se utiliza la imagen oficial como root.
    #
    # ========================================================

    if [[ "${MOSQUITTO_PRESERVED}" == "true" ]]; then

        echo "Recuperando: mosquitto/data"


        mkdir -p \
            "${PROJECT_ROOT}/mosquitto/data"


        if ! docker run \
            --rm \
            --user 0:0 \
            -v "${ROLLBACK_ROOT}/mosquitto/data:/source:ro" \
            -v "${PROJECT_ROOT}/mosquitto/data:/destination" \
            eclipse-mosquitto:2.0 \
            sh -c '
                rm -rf /destination/* \
                       /destination/.[!.]* \
                       /destination/..?* \
                       2>/dev/null || true

                cp -a \
                    /source/. \
                    /destination/

                chown -R \
                    1883:1883 \
                    /destination

                if [ -f /destination/mosquitto.db ]; then

                    chmod \
                        600 \
                        /destination/mosquitto.db

                fi
            '
        then

            echo "ERROR restaurando: mosquitto/data"

            rollback_failed=1
        fi

    fi


    echo


    if [[ "${rollback_failed}" -eq 0 ]]; then

        echo "Rollback automático finalizado correctamente."

    else

        echo "ATENCIÓN:"
        echo "El rollback automático quedó INCOMPLETO."
        echo "NO iniciar el BMS hasta revisar los datos."

    fi


    echo
    echo "Los servicios permanecen DETENIDOS."

    echo
    echo "Rollback de seguridad:"
    echo "${ROLLBACK_ROOT}"


    ROLLBACK_IN_PROGRESS=false
}

fail() {

    local message="$1"

    echo
    echo "============================================================"
    echo "ERROR"
    echo "============================================================"
    echo "${message}"
    echo

    if [[ "${ROLLBACK_ARMED}" == "true" ]]; then
        restore_previous_state
    fi

    exit 1
}


on_error() {

    local exit_code=$?
    local line="$1"
    local command="$2"

    trap - ERR

    echo
    echo "============================================================"
    echo "ERROR INESPERADO"
    echo "============================================================"
    echo "Código: ${exit_code}"
    echo "Línea: ${line}"
    echo "Comando: ${command}"
    echo

    if [[ "${ROLLBACK_ARMED}" == "true" ]]; then
        restore_previous_state
    fi

    exit "${exit_code}"
}


trap cleanup EXIT
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR


# ============================================================
# ARGUMENTOS
# ============================================================

if [[ $# -ne 2 ]]; then

    echo "Uso:"
    echo
    echo "  $0 BACKUP.tar.gz --check"
    echo
    echo "  $0 BACKUP.tar.gz --restore"

    exit 1
fi


ARCHIVE_INPUT="$1"
MODE="$2"


case "${MODE}" in

    --check)
        ;;

    --restore)
        ;;

    *)
        fail "Modo inválido: ${MODE}"
        ;;

esac


# ============================================================
# RUTAS
# ============================================================

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"


PROJECT_ROOT="$(
    cd "${SCRIPT_DIR}/.."
    pwd
)"


COMPOSE_FILE="${PROJECT_ROOT}/docker/docker-compose.yml"
MQTT_CLEANUP="${PROJECT_ROOT}/scripts/mqtt-cleanup.sh"


if [[ ! -f "${ARCHIVE_INPUT}" ]]; then
    fail "No existe el backup: ${ARCHIVE_INPUT}"
fi


ARCHIVE="$(
    readlink -f "${ARCHIVE_INPUT}"
)"


if [[ ! -f "${COMPOSE_FILE}" ]]; then
    fail "No existe docker-compose.yml: ${COMPOSE_FILE}"
fi


if [[ ! -f "${MQTT_CLEANUP}" ]]; then
    fail "No existe mqtt-cleanup.sh: ${MQTT_CLEANUP}"
fi


TMP_DIR="$(
    mktemp -d
)"


LISTING="${TMP_DIR}/listing.txt"
MANIFEST_FILE="${TMP_DIR}/manifest.txt"


# ============================================================
# INFORMACIÓN
# ============================================================

info "BMS RESTORE"


echo "Proyecto:"
echo "${PROJECT_ROOT}"

echo
echo "Backup:"
echo "${ARCHIVE}"

echo
echo "Modo:"
echo "${MODE}"


# ============================================================
# VALIDAR HERRAMIENTAS
# ============================================================

info "VALIDANDO HERRAMIENTAS"


REQUIRED_COMMANDS=(

    docker
    tar
    grep
    sed
    stat
    readlink
    mktemp
    uname
    git

)


for command in "${REQUIRED_COMMANDS[@]}"; do

    if ! command -v "${command}" >/dev/null 2>&1; then
        fail "No se encuentra el comando requerido: ${command}"
    fi

done


docker info >/dev/null 2>&1 \
    || fail "Docker no está disponible"


docker image inspect \
    eclipse-mosquitto:2.0 \
    >/dev/null 2>&1 \
    || fail "No está disponible la imagen eclipse-mosquitto:2.0"


echo "HERRAMIENTAS OK"


# ============================================================
# VALIDAR DOCKER COMPOSE
# ============================================================

info "VALIDANDO DOCKER COMPOSE"


docker compose \
    -f "${COMPOSE_FILE}" \
    config \
    >/dev/null \
    || fail "docker-compose.yml inválido"


echo "COMPOSE OK"


# ============================================================
# VALIDAR TAR
# ============================================================

info "VALIDANDO BACKUP"


tar \
    -tzf "${ARCHIVE}" \
    > "${LISTING}" \
    || fail "El archivo TAR no es válido"


echo "TAR OK"


# ============================================================
# SEGURIDAD DE RUTAS
# ============================================================

if grep -Eq '(^/|(^|/)\.\.(/|$))' "${LISTING}"; then
    fail "El backup contiene rutas potencialmente inseguras"
fi


echo "RUTAS OK"


# ============================================================
# CONTENIDO OBLIGATORIO
# ============================================================

REQUIRED_PATHS=(

    "manifest.txt"

    "fuxa/appdata/"
    "fuxa/db/"
    "fuxa/images/"

    "mosquitto/data/"
    "mosquitto/data/mosquitto.db"

)


for required in "${REQUIRED_PATHS[@]}"; do

    if ! grep -Fxq "${required}" "${LISTING}"; then
        fail "Falta contenido obligatorio: ${required}"
    fi

done


echo "ESTRUCTURA OK"


# ============================================================
# MANIFEST
# ============================================================

tar \
    -xOzf "${ARCHIVE}" \
    manifest.txt \
    > "${MANIFEST_FILE}"


if [[ ! -s "${MANIFEST_FILE}" ]]; then
    fail "manifest.txt está vacío"
fi


info "MANIFEST DEL BACKUP"


cat "${MANIFEST_FILE}"


# ============================================================
# LEER VALORES DEL MANIFEST
# ============================================================
#
# El formato actual del manifest es:
#
#   Campo:
#   valor
#
# Ejemplo:
#
#   Git commit:
#   abc123...
#
# ============================================================

manifest_value() {

    local field="$1"

    awk \
        -v field="${field}:" \
        '
        $0 == field {
            if (getline > 0) {
                print
            }
            exit
        }
        ' \
        "${MANIFEST_FILE}"
}


SOURCE_HOST="$(
    manifest_value "Hostname"
)"


SOURCE_GIT_COMMIT="$(
    manifest_value "Git commit"
)"


SOURCE_GIT_BRANCH="$(
    manifest_value "Git branch"
)"


# ============================================================
# ENTORNO DESTINO
# ============================================================

HOST_UID="$(
    id -u
)"


HOST_GID="$(
    id -g
)"


DEST_ARCH="$(
    uname -m
)"


CURRENT_GIT_COMMIT="$(
    git \
        -C "${PROJECT_ROOT}" \
        rev-parse HEAD \
        2>/dev/null \
        || echo "NO_GIT"
)"


info "ENTORNO DESTINO"


echo "Hostname:"
hostname

echo
echo "Arquitectura:"
echo "${DEST_ARCH}"

echo
echo "Usuario:"
id

echo
echo "UID/GID destino:"
echo "${HOST_UID}:${HOST_GID}"

echo
echo "Git destino:"
echo "${CURRENT_GIT_COMMIT}"

echo
echo "Origen del backup:"
echo "Hostname: ${SOURCE_HOST:-DESCONOCIDO}"
echo "Git branch: ${SOURCE_GIT_BRANCH:-DESCONOCIDO}"
echo "Git commit: ${SOURCE_GIT_COMMIT:-DESCONOCIDO}"


if [[ \
    -n "${SOURCE_GIT_COMMIT}" && \
    "${SOURCE_GIT_COMMIT}" != "${CURRENT_GIT_COMMIT}" \
]]; then

    echo
    echo "AVISO:"
    echo "El commit registrado en el backup no coincide"
    echo "con el checkout Git actual."
    echo
    echo "Esto puede ser correcto durante una migración,"
    echo "pero debe quedar documentado."

fi


# ============================================================
# MODO CHECK
# ============================================================

if [[ "${MODE}" == "--check" ]]; then

    info "CHECK OK"

    echo "El backup pasó todas las validaciones."

    echo
    echo "NO se modificó ningún archivo."

    echo
    echo "Para restaurar:"
    echo
    echo "$0 \"${ARCHIVE}\" --restore"

    exit 0
fi


# ============================================================
# RESTORE REAL
# ============================================================

info "INICIANDO RESTAURACIÓN"


# ============================================================
# DETECTAR SERVICIOS ACTUALES
# ============================================================

mapfile -t RUNNING_SERVICES < <(

    docker compose \
        -f "${COMPOSE_FILE}" \
        ps \
        --services \
        --filter status=running \
    | sed '/^[[:space:]]*$/d'

)


CLEAN_RUNNING_SERVICES=()


for service in "${RUNNING_SERVICES[@]}"; do

    if [[ -n "${service//[[:space:]]/}" ]]; then

        CLEAN_RUNNING_SERVICES+=(
            "${service}"
        )

    fi

done


RUNNING_SERVICES=(
    "${CLEAN_RUNNING_SERVICES[@]}"
)


if ((${#RUNNING_SERVICES[@]} > 0)); then

    echo "Servicios activos encontrados:"

    printf '  %s\n' "${RUNNING_SERVICES[@]}"

    echo
    echo "Deteniendo servicios..."


    docker compose \
        -f "${COMPOSE_FILE}" \
        stop \
        "${RUNNING_SERVICES[@]}"

else

    echo "No hay servicios Compose activos."

fi


# ============================================================
# EXTRAER BACKUP A TEMPORAL
# ============================================================

info "EXTRAYENDO BACKUP"


tar \
    -xzf "${ARCHIVE}" \
    -C "${TMP_DIR}"


echo "Extracción temporal OK"


# ============================================================
# ROLLBACK DEL ESTADO ACTUAL
# ============================================================

TIMESTAMP="$(
    date '+%Y%m%d-%H%M%S'
)"


ROLLBACK_ROOT="${HOME}/bms-restore-rollback/${TIMESTAMP}"


mkdir -p "${ROLLBACK_ROOT}"


preserve_path() {

    local relative_path="$1"
    local source_path="${PROJECT_ROOT}/${relative_path}"
    local target_path="${ROLLBACK_ROOT}/${relative_path}"

    if [[ -e "${source_path}" || -L "${source_path}" ]]; then

        echo "Preservando: ${relative_path}"

        mkdir -p "$(
            dirname "${target_path}"
        )"

        mv \
            "${source_path}" \
            "${target_path}"

        PRESERVED_PATHS+=(
            "${relative_path}"
        )
    fi
}


preserve_mosquitto_data() {

    local source_path="${PROJECT_ROOT}/mosquitto/data"

    local rollback_parent="${ROLLBACK_ROOT}/mosquitto"


    if [[ ! -d "${source_path}" ]]; then

        return 0

    fi


    echo "Preservando: mosquitto/data"


    mkdir -p \
        "${rollback_parent}"


    docker run \
        --rm \
        --user 0:0 \
        -v "${source_path}:/source:ro" \
        -v "${rollback_parent}:/rollback" \
        eclipse-mosquitto:2.0 \
        sh -c '
            rm -rf \
                /rollback/data \
                2>/dev/null || true

            mkdir -p \
                /rollback/data

            cp -a \
                /source/. \
                /rollback/data/
        '


    MOSQUITTO_PRESERVED=true
}


info "PRESERVANDO ESTADO ANTERIOR"


# Desde este punto cualquier error debe intentar
# recuperar el estado anterior.
ROLLBACK_ARMED=true


preserve_path "fuxa/appdata"
preserve_path "fuxa/db"
preserve_path "fuxa/images"

preserve_path "nodered/.config.nodes.json"
preserve_path "nodered/.config.runtime.json"
preserve_path "nodered/.config.users.json"
preserve_path "nodered/flows_cred.json"

preserve_mosquitto_data


echo
echo "Rollback disponible en:"
echo "${ROLLBACK_ROOT}"


# ============================================================
# RESTAURAR FUXA
# ============================================================

info "RESTAURANDO FUXA"


mkdir -p "${PROJECT_ROOT}/fuxa"


cp -a \
    "${TMP_DIR}/fuxa/appdata" \
    "${PROJECT_ROOT}/fuxa/"


cp -a \
    "${TMP_DIR}/fuxa/db" \
    "${PROJECT_ROOT}/fuxa/"


cp -a \
    "${TMP_DIR}/fuxa/images" \
    "${PROJECT_ROOT}/fuxa/"


chown -R \
    "${HOST_UID}:${HOST_GID}" \
    "${PROJECT_ROOT}/fuxa/appdata" \
    "${PROJECT_ROOT}/fuxa/db" \
    "${PROJECT_ROOT}/fuxa/images"


echo "FUXA OK"


# ============================================================
# RESTAURAR NODE-RED
# ============================================================

info "RESTAURANDO NODE-RED"


mkdir -p "${PROJECT_ROOT}/nodered"


NODE_RED_FILES=(

    ".config.nodes.json"
    ".config.runtime.json"
    ".config.users.json"
    "flows_cred.json"

)


for file in "${NODE_RED_FILES[@]}"; do

    source_file="${TMP_DIR}/nodered/${file}"

    if [[ -f "${source_file}" ]]; then

        echo "Restaurando: ${file}"

        cp -a \
            "${source_file}" \
            "${PROJECT_ROOT}/nodered/${file}"

        chown \
            "${HOST_UID}:${HOST_GID}" \
            "${PROJECT_ROOT}/nodered/${file}"
    fi

done


echo "NODE-RED OK"


# ============================================================
# RESTAURAR MOSQUITTO
# ============================================================

info "RESTAURANDO MOSQUITTO"


mkdir -p \
    "${PROJECT_ROOT}/mosquitto/data"


docker run \
    --rm \
    --user 0:0 \
    -v "${TMP_DIR}/mosquitto/data:/source:ro" \
    -v "${PROJECT_ROOT}/mosquitto/data:/destination" \
    eclipse-mosquitto:2.0 \
    sh -c '
        rm -rf /destination/* \
               /destination/.[!.]* \
               /destination/..?* \
               2>/dev/null || true

        cp -a /source/. /destination/

        chown -R 1883:1883 /destination

        if [ -f /destination/mosquitto.db ]; then
            chmod 600 /destination/mosquitto.db
        fi
    '


echo "MOSQUITTO OK"


# ============================================================
# VALIDACIÓN POST-RESTORE
# ============================================================

info "VALIDANDO RESTAURACIÓN"


echo "FUXA:"


stat \
    -c '%A | %a | %U:%G | UID=%u GID=%g | %n' \
    "${PROJECT_ROOT}/fuxa/appdata" \
    "${PROJECT_ROOT}/fuxa/appdata/project.fuxap.db" \
    "${PROJECT_ROOT}/fuxa/db" \
    "${PROJECT_ROOT}/fuxa/images"


FUXA_UID="$(
    stat -c '%u' \
        "${PROJECT_ROOT}/fuxa/appdata/project.fuxap.db"
)"


FUXA_GID="$(
    stat -c '%g' \
        "${PROJECT_ROOT}/fuxa/appdata/project.fuxap.db"
)"


if [[ "${FUXA_UID}" != "${HOST_UID}" ]]; then
    fail "FUXA tiene UID incorrecto: ${FUXA_UID}"
fi


if [[ "${FUXA_GID}" != "${HOST_GID}" ]]; then
    fail "FUXA tiene GID incorrecto: ${FUXA_GID}"
fi


echo
echo "NODE-RED:"


for file in \
    "${PROJECT_ROOT}/nodered/.config.nodes.json" \
    "${PROJECT_ROOT}/nodered/.config.runtime.json" \
    "${PROJECT_ROOT}/nodered/.config.users.json" \
    "${PROJECT_ROOT}/nodered/flows_cred.json"

do

    if [[ -f "${file}" ]]; then

        stat \
            -c '%A | %a | %U:%G | UID=%u GID=%g | %n' \
            "${file}"


        FILE_UID="$(
            stat -c '%u' "${file}"
        )"


        FILE_GID="$(
            stat -c '%g' "${file}"
        )"


        if [[ "${FILE_UID}" != "${HOST_UID}" ]]; then
            fail "Node-RED tiene UID incorrecto: ${file}"
        fi


        if [[ "${FILE_GID}" != "${HOST_GID}" ]]; then
            fail "Node-RED tiene GID incorrecto: ${file}"
        fi
    fi

done


echo
echo "MOSQUITTO:"


stat \
    -c '%A | %a | %U:%G | UID=%u GID=%g | %n' \
    "${PROJECT_ROOT}/mosquitto/data" \
    "${PROJECT_ROOT}/mosquitto/data/mosquitto.db"


MOSQ_UID="$(
    stat -c '%u' \
        "${PROJECT_ROOT}/mosquitto/data/mosquitto.db"
)"


MOSQ_GID="$(
    stat -c '%g' \
        "${PROJECT_ROOT}/mosquitto/data/mosquitto.db"
)"


MOSQ_MODE="$(
    stat -c '%a' \
        "${PROJECT_ROOT}/mosquitto/data/mosquitto.db"
)"


if [[ "${MOSQ_UID}" != "1883" ]]; then
    fail "mosquitto.db tiene UID incorrecto: ${MOSQ_UID}"
fi


if [[ "${MOSQ_GID}" != "1883" ]]; then
    fail "mosquitto.db tiene GID incorrecto: ${MOSQ_GID}"
fi


if [[ "${MOSQ_MODE}" != "600" ]]; then
    fail "mosquitto.db tiene permisos incorrectos: ${MOSQ_MODE}"
fi


# ============================================================
# RESTORE COMPLETADO
# ============================================================

ROLLBACK_ARMED=false
RESTORE_SUCCESS=true


info "RESTORE DE DATOS OK"


echo "Los datos persistentes fueron restaurados correctamente."

echo
echo "Rollback:"
echo "${ROLLBACK_ROOT}"

echo
echo "IMPORTANTE:"
echo "Los servicios permanecen DETENIDOS."

echo
echo "NO iniciar Node-RED directamente."

echo
echo "ORDEN SEGURO POST-RESTORE:"
echo
echo "  1. Iniciar únicamente Mosquitto"
echo
echo "     docker compose -f docker/docker-compose.yml up -d mosquitto"
echo
echo "  2. Ejecutar scripts/mqtt-cleanup.sh"
echo "  3. Verificar que no existan retained /write"
echo "     ni bms/diagnostico/comando"
echo
echo "  4. Iniciar Node-RED"
echo "  5. Confirmar BMS READY"
echo "  6. Iniciar FUXA y Nginx"
echo "  7. Validar lectura, escritura y readback"

echo
echo "El código y flows.json NO fueron restaurados desde el backup."
echo "Deben provenir del checkout Git validado."

echo
echo "No utilizar renombrado de containers Docker"
echo "como mecanismo de rollback."
echo "Los labels de Docker Compose permanecen asociados."

