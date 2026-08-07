# Odoo 17

Automatización reproducible para preparar y desplegar Odoo 17 sobre Ubuntu 24.04 LTS y Docker.

## Preparación del servidor

El script [`scripts/provision_ubuntu_odoo17_host.sh`](scripts/provision_ubuntu_odoo17_host.sh) configura:

- actualizaciones de Ubuntu;
- idioma español y zona horaria de Madrid;
- QEMU Guest Agent;
- SSH mediante clave, sin contraseña ni acceso remoto de `root`;
- UFW con los puertos 22, 80 y 443;
- Fail2Ban para SSH;
- Docker Engine y Docker Compose desde el repositorio oficial;
- validaciones finales de los servicios.

## Requisitos previos

Antes de ejecutarlo:

1. Instalar Ubuntu Server 24.04 LTS usando todo el disco.
2. Crear un usuario administrador con `sudo`.
3. Instalar OpenSSH Server.
4. Copiar y comprobar una clave SSH con `ssh-copy-id`.
5. Mantener una segunda sesión SSH abierta durante la primera ejecución.

La instalación mediante ISO, la recuperación mediante Rescue y la gestión de contraseñas permanecen manuales para evitar borrados o bloqueos accidentales.

## Preparar el host

```bash
git clone https://github.com/juanframunoz/odoo17.git
cd odoo17
sudo bash scripts/provision_ubuntu_odoo17_host.sh
```

## Desplegar Odoo 17

El script [`scripts/deploy_odoo17.sh`](scripts/deploy_odoo17.sh) crea una instalación nueva con:

- Odoo 17 y PostgreSQL 15 en contenedores separados;
- PostgreSQL sin puertos públicos;
- Odoo enlazado únicamente a `127.0.0.1`;
- volúmenes persistentes bajo `/opt/odoo17`;
- secretos aleatorios conservados con permisos restrictivos;
- Nginx, HTTPS y renovación mediante Let's Encrypt;
- dominio `electrothermotruck.mecanicos.uno`;
- correo de certificados `soporte@mecanicos.uno`.

```bash
sudo bash scripts/deploy_odoo17.sh
```

Tras el despliegue debe crearse una base de datos nueva llamada `electrothermotruck`.

Después de crearla, se debe cerrar el gestor público y fijar el filtro:

```bash
sudo bash scripts/lock_odoo17_database.sh electrothermotruck
```

El script de despliegue conserva cualquier configuración de Odoo ya existente en ejecuciones posteriores.

## Descargar los addons desde Git

[`scripts/sync_odoo17_addons.sh`](scripts/sync_odoo17_addons.sh) descarga las últimas revisiones de las ramas Odoo 17 seleccionadas y publica únicamente los módulos requeridos. Incluye OCA, MuK y los repositorios de Factor Digital, entre ellos `sale_reception_flow`, `sale_reception_flow_v1`, `fd_facturas_albaranes_ai` y `fd_booking_voice_ai`.

Los repositorios privados usan una deploy key independiente y de solo lectura para:

- `juanframunoz/odoo-apps`;
- `juanframunoz/terminados`;
- `juanframunoz/sin_inventariar`;
- `juanframunoz/fd_activity_sidebar`.

Las claves privadas no se guardan en el repositorio. Después de generar las cuatro claves y añadir sus partes públicas como deploy keys sin permiso de escritura, ejecute:

```bash
sudo apt-get update
sudo apt-get install -y git rsync
sudo bash scripts/configure_github_deploy_keys.sh
sudo bash scripts/sync_odoo17_addons.sh
```

El configurador asigna una identidad distinta a cada repositorio y fija la clave Ed25519 oficial de `github.com` con comprobación estricta del host.

El proceso primero clona y valida todos los repositorios. Solo después actualiza `/opt/odoo17/addons`. Rechaza manifiestos que no sean de Odoo 17 y versiones Factor Digital anteriores a las auditadas.

Cada ejecución genera `/opt/odoo17/addons-git.lock`, que registra repositorio, rama y commit exacto. De este modo se descargan las versiones más recientes disponibles, pero queda constancia precisa de lo instalado.

La selección instala 34 módulos adicionales. Se excluyen expresamente `fd_whatsapp` y `fd_ocr_albaranes_de_compra`; `fd_albaranes_compra_ai` sí forma parte de la instalación y conserva sus tareas programadas.

Para aplicar el nuevo código:

```bash
sudo docker compose \
  --env-file /opt/odoo17/.env \
  -f /opt/odoo17/compose.yaml \
  restart odoo
```

Después se debe actualizar la lista de aplicaciones y probar los módulos en una base de ensayo antes de instalarlos en producción. Las ramas de PR se mantienen fijadas explícitamente hasta que sus cambios estén validados y fusionados.

Los scripts son idempotentes y no reinician el servidor automáticamente.

## Seguridad

Odoo y PostgreSQL no se exponen directamente a Internet. Los contenedores usan una red interna y Odoo se publica exclusivamente a través de Nginx en los puertos 80 y 443. No deben publicarse los puertos 5432, 8069, 8071 ni 8072 en interfaces públicas.
