# BMS Changelog

Registro de versiones de la plataforma BMS.

---

## Core v0.9.0

Baseline funcional previa al endurecimiento para Core v1.0.

Esta versión representa el primer estado estable del núcleo BMS
utilizado como punto de partida para la evolución hacia una
plataforma reutilizable y desplegable en múltiples instalaciones.

### Arquitectura

La plataforma se encuentra dividida en los siguientes módulos:

- Startup
- Scheduler
- Device Manager
- Acquisition Engine
- MQTT Publisher
- MQTT Explorer
- Modbus Writer
- Alarm Engine
- Notification Engine
- Pruebas
- Laboratorio

### Configuración

- Configuración de gateways mediante JSON.
- Configuración de dispositivos mediante JSON.
- Drivers independientes por modelo de equipo.
- Carga automática de drivers durante el arranque.
- Resolución dinámica de dispositivos.
- Resolución dinámica de gateways.
- Resolución dinámica de drivers.

### Acquisition Engine

- Adquisición Modbus TCP.
- Soporte para múltiples gateways.
- Scan configurable por variable.
- Variables habilitadas mediante read=true.
- Decodificación de tipos:

  - bool
  - uint16
  - int16
  - uint32
  - int32
  - float

- Soporte inicial de bitmask.
- Multiplicador configurable.
- Cantidad de decimales configurable.
- Publicación individual de mediciones.

### MQTT

Convención de publicación:

bms/<gateway>/<device>/<point>

- Publicación de valores mediante MQTT.
- Integración con FUXA.
- Valores retained para recuperación del último estado conocido.

### Modbus Writer

Convención de escritura:

bms/<gateway>/<device>/<variable>/write

- Recepción de comandos mediante MQTT.
- Resolución de dispositivo.
- Resolución de gateway.
- Resolución de driver.
- Resolución de variable.
- Escritura habilitada explícitamente mediante write=true.
- Validación básica de tipos antes de escritura Modbus.

### Alarm Engine

- Filtrado de variables configuradas como alarmas.
- Soporte inicial para alarmas binarias.
- Detección de transición NORMAL -> ACTIVE.
- Detección de transición ACTIVE -> CLEARED.
- Prevención de notificaciones repetidas mientras el estado no cambia.
- Generación de alarma al iniciar el BMS si la primera lectura está activa.
- Cálculo de duración de alarma.
- Severidades:

  - CRITICAL
  - WARNING
  - INFO

### Notification Engine

- Objeto de alarma normalizado.
- Formateo independiente del Alarm Engine.
- Routing por severidad.
- Integración inicial con WhatsApp.
- Integración inicial con Email.
- Soporte estructural previsto para nuevos canales de notificación.

### FUXA

- Interfaz gráfica desacoplada del Acquisition Engine.
- Lectura de variables mediante MQTT.
- Escritura de variables mediante MQTT.

### Control de versiones y seguridad

- Repositorio Git.
- Backup remoto en GitHub.
- Runtime de WhatsApp excluido del repositorio.
- Credenciales de Node-RED excluidas del repositorio.
- Logs y datos runtime excluidos mediante .gitignore.

---

## Objetivos para Core v1.0.0

### Startup

- Startup determinista.
- Validación completa de gateways, devices y drivers.
- Activación del Scheduler únicamente cuando el sistema esté READY.

### Health Engine

- Estado de comunicación por dispositivo.
- Heartbeat de PLC.
- HeartBitCounter.
- Detección de PLC congelado.
- Detección de dispositivo offline.
- Última comunicación válida.
- Calidad de datos.

Estados previstos:

- GOOD
- STALE
- BAD
- OFFLINE

### Modbus Writer

- Rangos min/max.
- Validaciones adicionales.
- Readback posterior a escritura.
- Confirmación de escritura.
- Registro de comandos.
- Preparación para auditoría.

### Alarm Engine

- Alarmas de comunicación.
- Persistencia de estados.
- Retardos de activación y restablecimiento.
- ACK de alarmas.
- Event log persistente.

### Notification Engine

- Destinatarios configurables.
- Eliminación de destinatarios hardcodeados.
- Registro de intentos de envío.
- Control de errores por canal.
- Canales independientes.

### FUXA

- Roles de usuario.
- Perfil de visualización.
- Perfil operador/mantenimiento.
- Perfil administrador.
- Restricción de comandos.
- Pantalla de estado general del BMS.

### Plataforma

- Backup y restore probado.
- Instalación repetible.
- Separación entre Core, configuración de sitio y secrets.
- Documentación de instalación.
- Prueba de despliegue en un entorno limpio.

---

## Fuera de Core v1.0.0

La adquisición y almacenamiento de históricos se implementará
posteriormente, una vez estabilizado el núcleo.

Objetivo posterior:

Core v1.1.0

- Base de datos histórica.
- Tendencias.
- Análisis temporal.
- Reportes.
- Histórico de variables de proceso.
