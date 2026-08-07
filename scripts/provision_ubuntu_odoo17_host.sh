#!/usr/bin/env bash
set -Eeuo pipefail

# Provisiona un host Ubuntu 24.04 para Odoo 17 sobre Docker.
# No instala Odoo: prepara y protege el sistema e instala Docker Engine.
#
# Uso desde un usuario administrador con clave SSH ya configurada:
#   sudo bash provision_ubuntu_odoo17_host.sh
#
# Antes de ejecutarlo:
# - Instalar Ubuntu Server 24.04 LTS usando todo el disco, sin LVM ni LUKS.
# - Crear un usuario administrador (por ejemplo, juanfra).
# - Instalar OpenSSH Server.
# - Copiar una clave pública con ssh-copy-id y comprobar el acceso.

readonly TARGET_UBUNTU="24.04"
readonly TARGET_TIMEZONE="Europe/Madrid"
readonly SSH_HARDENING_FILE="/etc/ssh/sshd_config.d/99-security.conf"
readonly FAIL2BAN_JAIL_FILE="/etc/fail2ban/jail.d/sshd.local"
readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
readonly DOCKER_SOURCE="/etc/apt/sources.list.d/docker.sources"

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

if [[ ${EUID} -ne 0 ]]; then
    die "Ejecuta este script con sudo."
fi

if [[ ! -r /etc/os-release ]]; then
    die "No se puede identificar el sistema operativo."
fi

# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == "ubuntu" ]] || die "Este script solo admite Ubuntu."
[[ ${VERSION_ID:-} == "${TARGET_UBUNTU}" ]] || \
    die "Se requiere Ubuntu ${TARGET_UBUNTU}; detectado: ${VERSION_ID:-desconocido}."

ADMIN_USER="${SUDO_USER:-}"
if [[ -z ${ADMIN_USER} || ${ADMIN_USER} == "root" ]]; then
    die "Ejecuta el script con sudo desde el usuario administrador, no como root directo."
fi

id "${ADMIN_USER}" >/dev/null 2>&1 || die "No existe el usuario ${ADMIN_USER}."
id -nG "${ADMIN_USER}" | tr ' ' '\n' | grep -qx sudo || \
    die "El usuario ${ADMIN_USER} no pertenece al grupo sudo."

ADMIN_HOME="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)"
AUTHORIZED_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"
if [[ ! -s ${AUTHORIZED_KEYS} ]]; then
    die "Falta ${AUTHORIZED_KEYS}. Copia y prueba primero una clave SSH con ssh-copy-id."
fi

export DEBIAN_FRONTEND=noninteractive

log "Actualizando Ubuntu"
apt-get update
apt-get full-upgrade -y

log "Instalando herramientas base y el agente de Hetzner/KVM"
apt-get install -y \
    ca-certificates \
    curl \
    fail2ban \
    locales \
    qemu-guest-agent \
    ufw

systemctl start qemu-guest-agent || true

log "Configurando idioma y zona horaria"
locale-gen es_ES.UTF-8 en_US.UTF-8
update-locale LANG=es_ES.UTF-8
timedatectl set-timezone "${TARGET_TIMEZONE}"

log "Protegiendo SSH"
install -d -m 0755 /etc/ssh/sshd_config.d
cat >"${SSH_HARDENING_FILE}" <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
EOF
chmod 0644 "${SSH_HARDENING_FILE}"
/usr/sbin/sshd -t
systemctl enable ssh
systemctl reload ssh

log "Configurando firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log "Configurando Fail2Ban para SSH"
install -d -m 0755 /etc/fail2ban/jail.d
cat >"${FAIL2BAN_JAIL_FILE}" <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
chmod 0644 "${FAIL2BAN_JAIL_FILE}"
systemctl enable fail2ban
systemctl restart fail2ban

log "Instalando Docker Engine desde el repositorio oficial"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${DOCKER_KEYRING}"
chmod a+r "${DOCKER_KEYRING}"

ARCHITECTURE="$(dpkg --print-architecture)"
cat >"${DOCKER_SOURCE}" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCHITECTURE}
Signed-By: ${DOCKER_KEYRING}
EOF
chmod 0644 "${DOCKER_SOURCE}"

apt-get update
apt-get install -y \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin
systemctl enable --now docker

log "Validando servicios"
/usr/sbin/sshd -t
systemctl is-active --quiet ssh
systemctl is-active --quiet fail2ban
systemctl is-active --quiet qemu-guest-agent
systemctl is-active --quiet docker
fail2ban-client status sshd >/dev/null
docker version >/dev/null
docker compose version >/dev/null

printf '\nPreparación terminada correctamente.\n'
printf 'Usuario administrador: %s\n' "${ADMIN_USER}"
printf 'Puertos públicos permitidos: 22, 80 y 443.\n'
printf 'Odoo y PostgreSQL deberán publicarse solo en redes internas o 127.0.0.1.\n'
printf 'No se ha añadido %s al grupo docker; usa sudo docker.\n' "${ADMIN_USER}"

if [[ -f /var/run/reboot-required ]]; then
    printf '\nHay un reinicio pendiente. Comprueba antes otra sesión SSH y ejecuta: sudo reboot\n'
fi
