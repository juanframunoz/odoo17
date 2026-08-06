#!/usr/bin/env bash
set -Eeuo pipefail

# Cierra el gestor público de bases y limita Odoo a una base concreta.
# Uso:
#   sudo bash lock_odoo17_database.sh [nombre_base]

readonly STACK_DIR="${STACK_DIR:-/opt/odoo17}"
readonly DB_NAME="${1:-electrothermotruck}"
readonly ODOO_CONFIG="${STACK_DIR}/config/odoo.conf"
readonly ENV_FILE="${STACK_DIR}/.env"
readonly COMPOSE_FILE="${STACK_DIR}/compose.yaml"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "Ejecuta este script con sudo."
[[ ${DB_NAME} =~ ^[A-Za-z0-9_.-]+$ ]] || die "Nombre de base no válido."
[[ -f ${ODOO_CONFIG} ]] || die "No existe ${ODOO_CONFIG}."
[[ -f ${ENV_FILE} ]] || die "No existe ${ENV_FILE}."
[[ -f ${COMPOSE_FILE} ]] || die "No existe ${COMPOSE_FILE}."

if grep -q '^list_db = ' "${ODOO_CONFIG}"; then
    sed -i 's/^list_db = .*/list_db = False/' "${ODOO_CONFIG}"
else
    printf 'list_db = False\n' >>"${ODOO_CONFIG}"
fi

if grep -q '^dbfilter = ' "${ODOO_CONFIG}"; then
    sed -i "s/^dbfilter = .*/dbfilter = ^${DB_NAME}\\$/" "${ODOO_CONFIG}"
else
    printf 'dbfilter = ^%s$\n' "${DB_NAME}" >>"${ODOO_CONFIG}"
fi

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" restart odoo

for attempt in {1..24}; do
    if curl --fail --silent --max-time 5 http://127.0.0.1:8069/web/login >/dev/null; then
        break
    fi
    [[ ${attempt} -lt 24 ]] || die "Odoo no respondió tras el reinicio."
    sleep 5
done

grep -E '^(list_db|dbfilter) =' "${ODOO_CONFIG}"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps
printf '\nGestor de bases cerrado para: %s\n' "${DB_NAME}"
