#!/usr/bin/env bash
set -Eeuo pipefail

# Configura cuatro deploy keys de solo lectura para los repositorios privados
# usados por sync_odoo17_addons.sh. No genera ni sustituye claves.

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

command -v git >/dev/null || die "Git no está instalado."
command -v ssh >/dev/null || die "OpenSSH Client no está instalado."

readonly SSH_DIR="/root/.ssh"
readonly CONFIG_DIR="${SSH_DIR}/config.d"
readonly CONFIG_FILE="${CONFIG_DIR}/odoo17-github.conf"
readonly KNOWN_HOSTS="${SSH_DIR}/known_hosts"
readonly INCLUDE_LINE="Include /root/.ssh/config.d/*"

# Clave Ed25519 oficial publicada por GitHub:
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
readonly GITHUB_ED25519_KEY="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

KEY_SPECS=(
    "github-odoo-apps|${SSH_DIR}/odoo17-odoo-apps|juanframunoz/odoo-apps.git"
    "github-terminados|${SSH_DIR}/odoo17-terminados|juanframunoz/terminados.git"
    "github-sin-inventariar|${SSH_DIR}/odoo17-sin-inventariar|juanframunoz/sin_inventariar.git"
    "github-fd-activity-sidebar|${SSH_DIR}/odoo17-fd-activity-sidebar|juanframunoz/fd_activity_sidebar.git"
)

install -d -m 0700 "${SSH_DIR}" "${CONFIG_DIR}"

for spec in "${KEY_SPECS[@]}"; do
    IFS='|' read -r alias identity_file repository <<<"${spec}"
    [[ -f ${identity_file} ]] || die "Falta la clave privada ${identity_file}."
    [[ -f ${identity_file}.pub ]] || die "Falta la clave pública ${identity_file}.pub."
    chmod 0600 "${identity_file}"
    chmod 0644 "${identity_file}.pub"
done

touch "${KNOWN_HOSTS}"
chmod 0600 "${KNOWN_HOSTS}"
if ! grep -qxF "${GITHUB_ED25519_KEY}" "${KNOWN_HOSTS}"; then
    printf '%s\n' "${GITHUB_ED25519_KEY}" >>"${KNOWN_HOSTS}"
fi

if [[ ! -e ${SSH_DIR}/config ]]; then
    printf '%s\n' "${INCLUDE_LINE}" >"${SSH_DIR}/config"
elif ! grep -qxF "${INCLUDE_LINE}" "${SSH_DIR}/config"; then
    printf '\n%s\n' "${INCLUDE_LINE}" >>"${SSH_DIR}/config"
fi
chmod 0600 "${SSH_DIR}/config"

{
    for spec in "${KEY_SPECS[@]}"; do
        IFS='|' read -r alias identity_file repository <<<"${spec}"
        printf 'Host %s\n' "${alias}"
        printf '    HostName github.com\n'
        printf '    User git\n'
        printf '    IdentityFile %s\n' "${identity_file}"
        printf '    IdentitiesOnly yes\n'
        printf '    StrictHostKeyChecking yes\n'
        printf '    UserKnownHostsFile %s\n\n' "${KNOWN_HOSTS}"
    done
} >"${CONFIG_FILE}"
chmod 0600 "${CONFIG_FILE}"

log "Verificando acceso de solo lectura"
export GIT_TERMINAL_PROMPT=0
for spec in "${KEY_SPECS[@]}"; do
    IFS='|' read -r alias identity_file repository <<<"${spec}"
    url="git@${alias}:${repository}"
    git ls-remote "${url}" HEAD >/dev/null || die "Sin acceso de lectura a ${repository}."
    printf '  OK  %s\n' "${repository}"
done

log "Deploy keys configuradas y verificadas"
