# Manual de Backup Cifrado y Gestión de Claves
## BMS Sanatorio

**Versión:** 1.0  
**Fecha:** 2026-10-05  
**Estado:** Procedimiento de backup y cifrado validado.  
**Ámbito:** Servidor BMS basado en Docker, Node-RED, FUXA, Mosquitto y Nginx.

## 1. Objetivo

Este manual documenta cómo:

1. Generar un backup consistente del BMS.
2. Cifrarlo con `age`.
3. Administrar correctamente la clave pública y la clave privada.
4. Verificar que el backup cifrado puede recuperarse.
5. Guardar el backup de forma segura en un almacenamiento externo.
6. Evitar que backups o claves privadas terminen accidentalmente en Git.

El objetivo es poder recuperar el BMS aunque se pierda completamente la VM o el servidor actual.

## 2. Concepto general

El sistema de recuperación se divide en dos partes.

### Git / GitHub

Guarda el software y la configuración reproducible:

- `config/`
- `drivers/`
- `docker/`
- `nginx/`
- `scripts/`
- `nodered/flows.json`
- `nodered/settings.js`
- `nodered/package.json`
- `nodered/package-lock.json`
- configuración versionada de Mosquitto
- Dockerfile y parches de FUXA

Git permite reconstruir la plataforma.

### Backup

Guarda el estado persistente que Git no reconstruye:

- configuración y proyecto interno de FUXA
- usuarios de FUXA
- API keys de FUXA
- alarmas y scheduler de FUXA
- históricos/bases de FUXA
- imágenes de FUXA
- configuración runtime necesaria de Node-RED
- datos persistentes de Mosquitto
- manifest del backup

**Git no reemplaza al backup y el backup no reemplaza a Git.**

## 3. Rutas utilizadas

Proyecto BMS:

```text
/home/juancasas/bms-sanatorio
```

Script de backup:

```text
/home/juancasas/bms-sanatorio/scripts/backup.sh
```

Backups locales:

```text
/home/juancasas/bms-sanatorio/backups/
```

Clave pública de cifrado:

```text
/home/juancasas/bms-sanatorio/config/backup-age-recipient.txt
```

Clave privada de recuperación, sólo durante generación/prueba:

```text
/home/juancasas/bms-recovery.key
```

> La clave privada NO debe permanecer de forma permanente en el servidor BMS.

## 4. Software necesario

Verificar:

```bash
age --version
age-keygen --version
```

Versión validada durante la puesta en marcha:

```text
1.2.1
```

## 5. Generación inicial del par de claves

Este procedimiento se realiza una sola vez, salvo que se decida rotar las claves.

En el servidor BMS:

```bash
cd /home/juancasas/bms-sanatorio

umask 077

age-keygen -o /home/juancasas/bms-recovery.key

age-keygen -y /home/juancasas/bms-recovery.key   > config/backup-age-recipient.txt

chmod 600 /home/juancasas/bms-recovery.key
chmod 644 config/backup-age-recipient.txt
```

La clave pública puede verificarse con:

```bash
cat config/backup-age-recipient.txt
```

Debe comenzar con:

```text
age1...
```

### Regla de seguridad

La clave pública:
- puede estar en el servidor;
- puede estar en Git;
- sirve para cifrar;
- no permite descifrar backups.

La clave privada:
- permite descifrar todos los backups creados con esa clave pública;
- no debe subirse a Git;
- no debe enviarse por correo sin protección;
- no debe guardarse en el mismo servidor como copia permanente;
- debe conservarse en un lugar seguro externo al BMS.

## 6. Copiar la clave privada a una PC de recuperación

Desde una PC Windows, en PowerShell:

```powershell
scp juancasas@IP_DEL_BMS:/home/juancasas/bms-recovery.key "$env:USERPROFILE\Downloads\bms-recovery.key"
```

Verificar que exista:

```powershell
Get-Item "$env:USERPROFILE\Downloads\bms-recovery.key"
```

Calcular SHA-256:

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\bms-recovery.key" -Algorithm SHA256
```

En el servidor:

```bash
sha256sum /home/juancasas/bms-recovery.key
```

Los dos hashes deben ser exactamente iguales.

Una vez confirmada la copia y terminadas las pruebas de recuperación, la clave privada debe retirarse del servidor.

## 7. Ejecutar un backup del BMS

Desde el servidor:

```bash
cd /home/juancasas/bms-sanatorio

./scripts/backup.sh
```

El script:

1. detecta qué servicios Docker están activos;
2. genera un manifest;
3. detiene temporalmente los servicios para obtener un snapshot consistente;
4. copia los datos persistentes;
5. maneja `mosquitto.db` sin modificar sus permisos originales;
6. crea el archivo `.tar.gz`;
7. valida el archivo;
8. genera SHA-256;
9. vuelve a iniciar los servicios que estaban funcionando;
10. elimina archivos incompletos si el backup falla.

Un backup correcto termina con:

```text
BACKUP OK
```

Ejemplo:

```text
backups/bms-backup-20261005-080954.tar.gz
```

## 8. Verificar el backup sin cifrar

Listar backups:

```bash
ls -lh backups/
```

Verificar checksums:

```bash
sha256sum -c backups/*.sha256
```

Verificar que el TAR pueda leerse:

```bash
LATEST="$(ls -1t backups/bms-backup-*.tar.gz | head -1)"

tar -tzf "$LATEST" >/dev/null   && echo "TAR OK"
```

## 9. Cifrar el último backup

Desde:

```bash
cd /home/juancasas/bms-sanatorio
```

Ejecutar:

```bash
LATEST="$(ls -1t backups/bms-backup-*.tar.gz | head -1)"

ENCRYPTED="${LATEST}.age"

age   -R config/backup-age-recipient.txt   -o "$ENCRYPTED"   "$LATEST"
```

Generar también el checksum del archivo cifrado:

```bash
sha256sum "$ENCRYPTED" > "${ENCRYPTED}.sha256"
```

## 10. Prueba de descifrado

Mientras la clave privada siga temporalmente en el servidor:

```bash
cd /home/juancasas/bms-sanatorio

LATEST="$(ls -1t backups/bms-backup-*.tar.gz | head -1)"

ENCRYPTED="${LATEST}.age"

DECRYPTED="/tmp/$(basename "${LATEST}").restored"

age   -d   -i /home/juancasas/bms-recovery.key   -o "$DECRYPTED"   "$ENCRYPTED"
```

Comparar SHA-256:

```bash
sha256sum "$LATEST"
sha256sum "$DECRYPTED"
```

Comparar bit por bit:

```bash
cmp -s "$LATEST" "$DECRYPTED"   && echo "PRUEBA OK - ARCHIVOS IDENTICOS"   || echo "ERROR - ARCHIVOS DIFERENTES"
```

Resultado requerido:

```text
PRUEBA OK - ARCHIVOS IDENTICOS
```

La prueba inicial del BMS fue validada correctamente de esta manera.

## 11. Eliminar el archivo temporal descifrado

Después de la prueba:

```bash
rm -f "$DECRYPTED"
```

## 12. Retirar la clave privada del servidor

Sólo después de:
- haber copiado la clave privada a un almacenamiento seguro;
- haber confirmado su SHA-256;
- haber realizado una prueba real de descifrado;
- haber confirmado `PRUEBA OK - ARCHIVOS IDENTICOS`.

Eliminar la copia del servidor:

```bash
rm -f /home/juancasas/bms-recovery.key
```

Comprobar:

```bash
test ! -f /home/juancasas/bms-recovery.key   && echo "CLAVE PRIVADA NO PRESENTE EN EL SERVIDOR"
```

> En SSD, almacenamiento virtualizado y sistemas con snapshots, `shred` no garantiza el borrado físico. La estrategia principal es evitar mantener la clave privada en el servidor.

## 13. Qué archivo debe salir del servidor

Para almacenamiento externo se debe utilizar:

```text
bms-backup-YYYYMMDD-HHMMSS.tar.gz.age
bms-backup-YYYYMMDD-HHMMSS.tar.gz.age.sha256
```

No se recomienda enviar el `.tar.gz` sin cifrar a almacenamiento externo.

## 14. Almacenamiento externo

El destino definitivo debe acordarse con TICS. Posibilidades:

- NAS institucional;
- servidor SFTP institucional;
- almacenamiento compatible con S3;
- Google Drive institucional;
- Dropbox/Box empresarial;
- sistema corporativo de backups.

La clave privada debe guardarse separada del almacenamiento de backups.

Idealmente existirán al menos dos copias controladas de la clave privada:
1. copia primaria administrada por TICS;
2. copia de contingencia offline o en gestor seguro institucional.

## 15. Verificar un backup descargado del almacenamiento externo

Antes de intentar descifrarlo:

```bash
sha256sum -c bms-backup-YYYYMMDD-HHMMSS.tar.gz.age.sha256
```

Debe devolver:

```text
OK
```

## 16. Descifrar un backup durante una recuperación

```bash
age   -d   -i /ruta/segura/bms-recovery.key   -o bms-backup-restored.tar.gz   bms-backup-YYYYMMDD-HHMMSS.tar.gz.age
```

Validar:

```bash
tar -tzf bms-backup-restored.tar.gz >/dev/null   && echo "BACKUP DESCIFRADO OK"
```

> No sobrescribir manualmente datos del BMS de producción. La restauración completa se realizará mediante `restore.sh`, correspondiente a la Fase 7C.

## 17. Git y backups

El repositorio ya ignora:

```gitignore
backups/
```

Comprobar:

```bash
git ls-files backups
```

La salida debe estar vacía.

Nunca forzar backups al repositorio.

## 18. Comprobaciones periódicas recomendadas

Después de cada backup:

```bash
ls -lh backups/
```

Verificar contenedores:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Periódicamente debe hacerse una prueba real de recuperación en una VM o entorno de prueba.

**Un backup que nunca fue restaurado debe considerarse no probado.**

## 19. Estrategia de retención propuesta

Pendiente de aprobación definitiva con TICS.

Propuesta inicial:

```text
7 backups diarios
4 backups semanales
12 backups mensuales
```

## 20. Procedimiento resumido de emergencia

```text
1. Provisionar nueva VM.
2. Instalar Docker y Git.
3. Clonar el repositorio BMS.
4. Obtener el último backup cifrado externo.
5. Verificar SHA-256.
6. Obtener la clave privada desde custodia segura.
7. Descifrar el backup.
8. Ejecutar el procedimiento de restore.
9. Levantar Docker Compose.
10. Validar Node-RED, Mosquitto, FUXA y Nginx.
11. Validar comunicaciones Modbus.
12. Validar alarmas e históricos.
13. Confirmar hora/NTP.
```

## 21. Reglas críticas

**Nunca:**
- subir `bms-recovery.key` a Git;
- guardar la clave privada dentro del repositorio;
- enviar backups sin cifrar a servicios externos;
- cambiar los permisos de `mosquitto.db` para facilitar un backup;
- asumir que un backup funciona sin haber probado una restauración;
- borrar la única copia de la clave privada.

**Siempre:**
- mantener Git actualizado;
- cifrar antes de sacar el backup del servidor;
- guardar checksum junto al backup cifrado;
- mantener la clave privada separada;
- probar periódicamente la recuperación;
- verificar fecha y hora del servidor;
- mantener documentado el procedimiento.

## 22. Estado actual del proyecto

Validado:
- creación de backup consistente;
- recuperación automática de servicios si el backup falla;
- manejo de permisos de Mosquitto;
- generación de claves `age`;
- copia externa de clave privada;
- comparación de SHA-256 de la clave;
- cifrado con clave pública;
- descifrado con clave privada;
- comparación SHA-256 del backup original/restaurado;
- comparación bit a bit con `cmp`;
- resultado validado: `PRUEBA OK - ARCHIVOS IDENTICOS`.

Pendiente:
- integrar cifrado directamente en `backup.sh`;
- eliminación automática del backup sin cifrar;
- automatizar subida a almacenamiento externo;
- definir política de retención definitiva;
- desarrollar `restore.sh`;
- ejecutar restauración completa en un entorno de prueba;
- documentar la migración a la VM definitiva de TICS.
