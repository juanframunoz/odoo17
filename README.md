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

Los scripts son idempotentes y no reinician el servidor automáticamente.

## Seguridad

Odoo y PostgreSQL no se exponen directamente a Internet. Los contenedores usan una red interna y Odoo se publica exclusivamente a través de Nginx en los puertos 80 y 443. No deben publicarse los puertos 5432, 8069, 8071 ni 8072 en interfaces públicas.
