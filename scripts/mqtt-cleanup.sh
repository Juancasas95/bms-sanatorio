#!/bin/sh

set -eu

MQTT_HOST="${MQTT_HOST:-bms-mosquitto}"
MQTT_PORT="${MQTT_PORT:-1883}"

echo "============================================================"
echo "BMS MQTT COMMAND CLEANUP"
echo "============================================================"
echo "Broker: ${MQTT_HOST}:${MQTT_PORT}"
echo

# ============================================================
# 1. ESPERAR MOSQUITTO
# ============================================================

echo "Esperando broker MQTT..."

attempt=0
max_attempts=30

while ! mosquitto_pub \
    -h "${MQTT_HOST}" \
    -p "${MQTT_PORT}" \
    -t "bms/system/cleanup/probe" \
    -n \
    >/dev/null 2>&1
do
    attempt=$((attempt + 1))

    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "ERROR: Mosquitto no respondió después de ${max_attempts} intentos."
        exit 1
    fi

    sleep 1
done

echo "Mosquitto disponible."
echo

# ============================================================
# 2. ELIMINAR RETAINED DE ESCRITURA
# ============================================================

echo "Limpiando retained de comandos /write..."

mosquitto_sub \
    -h "${MQTT_HOST}" \
    -p "${MQTT_PORT}" \
    -t 'bms/+/+/+/write' \
    --retained-only \
    --remove-retained \
    -W 2 \
    >/dev/null 2>&1 \
    || true

# ============================================================
# 3. ELIMINAR COMANDO DE DIAGNÓSTICO
# ============================================================

echo "Limpiando retained de diagnóstico..."

mosquitto_sub \
    -h "${MQTT_HOST}" \
    -p "${MQTT_PORT}" \
    -t 'bms/diagnostico/comando' \
    --retained-only \
    --remove-retained \
    -W 2 \
    >/dev/null 2>&1 \
    || true

echo
echo "MQTT COMMAND CLEANUP OK"
