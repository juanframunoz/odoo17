# Odoo 17

Automatización reproducible para preparar servidores Ubuntu 24.04 LTS destinados a Odoo 17 sobre Docker.

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

## Uso

```bash
git clone https://github.com/juanframunoz/odoo17.git
cd odoo17
sudo bash scripts/provision_ubuntu_odoo17_host.sh
```

El script es idempotente y no reinicia el servidor automáticamente.

## Seguridad

Odoo y PostgreSQL no deben exponerse directamente a Internet. Los contenedores se configurarán en una red interna y Odoo se publicará únicamente a través de Nginx en los puertos 80 y 443.
