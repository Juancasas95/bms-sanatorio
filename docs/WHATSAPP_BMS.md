# BMS SANATORIO - INTEGRACIÓN WHATSAPP

## 1. Objetivo

Este documento describe la integración de WhatsApp con el sistema BMS del
Sanatorio, incluyendo:

- WhatsApp QR mediante Baileys.
- WhatsApp Cloud API de Meta.
- funcionamiento detrás del proxy institucional.
- modificaciones necesarias en node-red-contrib-whatsapp-api.
- configuración de Node-RED.
- política de alarmas.
- múltiples destinatarios.
- backup y restauración de la sesión QR.
- procedimiento de recuperación.

La finalidad es que la integración pueda reconstruirse desde Git y que la
sesión QR pueda recuperarse desde el backup cifrado.

---

## 2. Arquitectura general

El Notification Engine de Node-RED recibe eventos normalizados de alarma.

Flujo conceptual:

    Alarm Engine
        |
        v
    Alarm Formatter
        |
        v
    Severity / routing
        |
        +--> WhatsApp QR / Baileys
        |
        +--> WhatsApp Cloud API
        |
        +--> Email
        |
        +--> Telegram (previsto)

Los canales realmente utilizados dependen de dos condiciones:

    política según severidad
            AND
    canal habilitado en system.json

---

## 3. Política de severidades

Política definida:

### CRITICAL

    WhatsApp : SI
    Email    : SI
    Telegram : SI, si se habilita

### WARNING

    WhatsApp : NO
    Email    : SI
    Telegram : NO

### INFO

    WhatsApp : NO
    Email    : SI
    Telegram : NO

La misma política se aplica a:

    ACTIVE
    CLEARED

Por lo tanto, una alarma CRITICAL genera también notificación WhatsApp cuando
se restablece.

---

## 4. WhatsApp QR / Baileys

### Emisor

Se utiliza la cuenta WhatsApp Business vinculada mediante QR al nodo:

    node-red-contrib-whatsapp-api

Versión validada:

    0.1.2

La configuración del nodo WhatsApp se encuentra en flows.json.

Los destinatarios NO deben quedar codificados dentro de la lógica.

Se obtienen de:

    system.json

Ruta lógica:

    notifications.whatsapp.qr.recipients

Ejemplo conceptual:

    "qr": {
        "enabled": true,
        "recipients": [
            {
                "name": "Guardia",
                "phone": "598XXXXXXXX"
            }
        ]
    }

Los números se almacenan:

- en formato internacional.
- sin signo +.
- sin espacios.
- sin @s.whatsapp.net.

El Function:

    Prepare Whatsapp QR

agrega:

    @s.whatsapp.net

y genera un mensaje independiente por cada destinatario configurado.

Estado:

    soporte multi-destinatario IMPLEMENTADO

La validación funcional con más de un teléfono debe registrarse
separadamente cuando se realice.

---

## 5. WhatsApp Cloud API

Además del canal QR existe una integración separada con:

    Meta WhatsApp Cloud API

Este canal permite realizar pruebas con la infraestructura oficial de Meta.

La configuración no sensible se obtiene desde:

    system.json

Ruta:

    notifications.whatsapp.cloud

Incluye, entre otros:

- enabled
- environment
- apiVersion
- phoneNumberId
- recipients

El token Bearer NO debe almacenarse en system.json ni versionarse en Git.

Debe permanecer en las credenciales del nodo HTTP Request de Node-RED.

### Prueba validada

Se verificó comunicación correcta con Meta utilizando:

    hello_world

El mensaje fue aceptado por la API y recibido físicamente.

### Templates de alarmas

Se crearon los templates:

    bms_alarm_active
    bms_alarm_cleared

Estos templates deben estar aprobados y disponibles para el idioma configurado
antes de utilizarse en producción.

La creación o envío a revisión no debe interpretarse automáticamente como
aprobación.

---

## 6. Restricción de red encontrada

Durante la migración/operación sobre la Raspberry se detectó que Node-RED no
podía acceder directamente a los servicios de WhatsApp Web.

Síntomas observados:

- timeout contra web.whatsapp.com.
- errores WebSocket de Baileys.
- imposibilidad de establecer la sesión correctamente.

La red institucional requiere salida mediante proxy.

Proxy utilizado durante las pruebas:

    http://10.0.1.32:8080

Se comprobó:

    HTTPS mediante proxy : OK
    WebSocket mediante proxy : OK

---

## 7. Variables de entorno de Node-RED

docker-compose.yml configura el acceso al proxy mediante variables de entorno.

Entre ellas:

    HTTP_PROXY
    HTTPS_PROXY
    NODE_USE_ENV_PROXY

También se utiliza NO_PROXY para destinos internos que no deben atravesar el
proxy.

Estas variables forman parte de la configuración reproducible del contenedor.

---

## 8. Problema específico de Baileys

Configurar HTTP_PROXY y HTTPS_PROXY no fue suficiente.

Se identificaron dos rutas de comunicación dentro del bundle utilizado por
node-red-contrib-whatsapp-api que requerían un agente de proxy explícito.

### 8.1 Consulta de versión WhatsApp Web

Baileys consulta:

    https://web.whatsapp.com/sw.js

La llamada utiliza Axios.

Sin adaptación:

    timeout

Solución:

    HttpsProxyAgent

configurado como:

    httpsAgent

y además:

    proxy: false

para evitar que Axios procese nuevamente la configuración de proxy.

### 8.2 WebSocket de WhatsApp

La conexión WebSocket de Baileys también necesitó un agente explícito.

Se configuró:

    agent
    fetchAgent

utilizando:

    HttpsProxyAgent

Resultado:

    WebSocket conectado correctamente.

Después de aplicar ambos cambios, WhatsApp QR pudo conectarse y enviar alarmas
reales.

---

## 9. Dependencia adicional

Se agregó:

    https-proxy-agent

Versión instalada durante la implementación:

    9.1.0

La dependencia figura en:

    nodered/package.json
    nodered/package-lock.json

No debe instalarse manualmente después de una restauración si se utiliza el
lockfile del proyecto.

---

## 10. Parche reproducible

Modificar manualmente node_modules no es una solución reproducible.

Por este motivo se creó:

    nodered/scripts/patch-whatsapp-proxy.js

El script modifica el bundle instalado de:

    node-red-contrib-whatsapp-api 0.1.2

y aplica las dos correcciones:

1. Axios / sw.js mediante HttpsProxyAgent.
2. WebSocket Baileys mediante agent y fetchAgent.

El script:

- verifica la versión del paquete.
- falla si encuentra una versión desconocida.
- detecta si el parche ya está aplicado.
- es idempotente.
- no duplica código.

---

## 11. Ejecución automática del parche

nodered/package.json contiene:

    "postinstall": "node scripts/patch-whatsapp-proxy.js"

Por lo tanto:

    npm ci

realiza:

    instalación de dependencias
            |
            v
    ejecución de postinstall
            |
            v
    patch-whatsapp-proxy.js
            |
            v
    bundle preparado para proxy institucional

Esto evita depender de modificaciones manuales después de una reinstalación.

---

## 12. Archivos que NO deben versionarse

No deben subirse a Git:

    nodered/node_modules/

Tampoco deben versionarse:

- sesiones de WhatsApp.
- tokens de Meta.
- contraseñas SMTP.
- secretos JWT.
- credenciales privadas.

node_modules debe reconstruirse mediante:

    npm ci

---

## 13. Sesión WhatsApp QR

La sesión Baileys se almacena dentro de:

    nodered/whatsapp-api/

Se observaron directorios del tipo:

    nodered/whatsapp-api/<config-id>/auth/

La carpeta auth contiene estado y credenciales necesarias para mantener la
vinculación QR.

Esta información:

    NO se reconstruye desde Git.

Por ese motivo debe considerarse dato persistente.

---

## 14. Backup de WhatsApp QR

scripts/backup.sh fue ampliado para incluir:

    nodered/whatsapp-api/

dentro del backup cifrado con age.

No se respalda:

    nodered/node_modules/

La recuperación completa de WhatsApp QR requiere:

    Git
      +
    dependencias npm
      +
    parche reproducible
      +
    sesión QR del backup cifrado

---

## 15. Restore de WhatsApp QR

scripts/restore.sh fue ampliado para restaurar:

    nodered/whatsapp-api/

La restauración:

- sólo reemplaza la sesión actual si el backup contiene whatsapp-api.
- mantiene compatibilidad con backups antiguos.
- restaura propietario UID/GID.
- valida el propietario después del restore.

Si un backup antiguo no contiene whatsapp-api:

    la sesión existente NO se elimina.

---

## 16. Rollback de la sesión QR

Antes de reemplazar la sesión durante un restore, restore.sh utiliza:

    preserve_path "nodered/whatsapp-api"

La ruta entra en:

    PRESERVED_PATHS

Si el restore falla posteriormente, el mecanismo de rollback existente:

1. elimina el estado parcial.
2. recupera la carpeta preservada.
3. deja los servicios detenidos.

Por lo tanto, la sesión WhatsApp forma parte del mismo mecanismo de protección
utilizado para los demás datos persistentes de Node-RED.

---

## 17. Recuperación desde cero

Procedimiento conceptual:

    1. Clonar repositorio Git.

    2. Checkout de la versión correcta.

    3. Instalar dependencias Node-RED con npm ci.

    4. Verificar que postinstall aplique el parche WhatsApp.

    5. Descifrar el backup institucional.

    6. Ejecutar restore.sh --check.

    7. Ejecutar restore.sh --restore.

    8. Iniciar Mosquitto.

    9. Ejecutar mqtt-cleanup.sh.

   10. Verificar ausencia de retained peligrosos.

   11. Iniciar Node-RED.

   12. Confirmar BMS READY.

   13. Confirmar conexión de WhatsApp QR.

   14. Iniciar FUXA y Nginx.

   15. Probar una alarma CRITICAL controlada.

---

## 18. Verificación manual del parche

El parche puede verificarse manualmente con:

    docker exec bms-nodered \
      node /data/scripts/patch-whatsapp-proxy.js

Si ya está instalado correctamente debe informar:

    WhatsApp proxy patch: sw.js YA APLICADO
    WhatsApp proxy patch: WebSocket YA APLICADO
    WhatsApp proxy patch: no fue necesario modificar archivos.

---

## 19. Seguridad

No almacenar en Git:

- token permanente de Meta.
- contraseñas.
- credenciales SMTP.
- claves privadas.
- contenido de auth de Baileys.
- secretos de firma.
- archivos flows_cred.json en texto plano.

La sesión Baileys queda protegida mediante el backup cifrado con age.

La clave privada age debe mantenerse fuera del servidor BMS según el
procedimiento institucional de backup.

---

## 20. Limitaciones conocidas

### WhatsApp QR / Baileys

El canal QR depende de una implementación no oficial basada en WhatsApp Web.

Puede requerir nueva vinculación si:

- WhatsApp invalida la sesión.
- el dispositivo se desvincula.
- cambia el protocolo utilizado por WhatsApp.
- una futura versión de Baileys modifica internamente su implementación.

Por eso el parche valida específicamente:

    node-red-contrib-whatsapp-api 0.1.2

y debe revisarse antes de actualizar esa dependencia.

### WhatsApp Cloud

La API puede aceptar un mensaje sin que eso implique automáticamente entrega
o lectura.

Para disponer de estados completos:

    sent
    delivered
    read
    failed

se requiere integración mediante Webhook de Meta.

Actualmente el BMS no expone un endpoint público HTTPS para ese propósito.

---

## 21. Estado técnico actual

Validado:

- conexión WhatsApp QR.
- envío real de alarma por QR.
- acceso HTTPS a WhatsApp mediante proxy.
- acceso WebSocket mediante proxy.
- HttpsProxyAgent.
- parche Axios sw.js.
- parche WebSocket Baileys.
- ejecución idempotente del script de parche.
- WhatsApp Cloud hello_world.
- email.
- routing de severidades.
- generación de múltiples mensajes QR desde recipients[].
- sintaxis de backup.sh.
- sintaxis de restore.sh.

Pendiente de validación específica:

- envío QR simultáneo a dos o más destinatarios reales.
- restauración real de una sesión QR desde un backup nuevo.
- reconexión automática de la sesión QR después de dicha restauración.
- uso productivo de templates Meta una vez aprobados y disponibles.

---

## 22. Regla de mantenimiento

Antes de actualizar cualquiera de estos componentes:

    node-red-contrib-whatsapp-api
    Baileys
    https-proxy-agent
    Node.js
    Node-RED

debe comprobarse nuevamente:

    sw.js
    WebSocket
    proxy
    conexión QR
    envío de alarma
    persistencia de sesión

No actualizar estas dependencias directamente en producción sin una prueba
previa controlada.
