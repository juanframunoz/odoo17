#!/usr/bin/env bash
set -Eeuo pipefail

readonly STACK_DIR="${STACK_DIR:-/opt/odoo17}"
readonly DATABASE="${DATABASE:-electrothermotruck}"
readonly COMPOSE_FILE="${STACK_DIR}/compose.yaml"
readonly ENV_FILE="${STACK_DIR}/.env"
readonly CONFIG_FILE="/etc/odoo/odoo.conf"
readonly TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="${STACK_DIR}/backups/pre-modules-${TIMESTAMP}"

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

[[ -f ${COMPOSE_FILE} ]] || die "No existe ${COMPOSE_FILE}."
[[ -f ${ENV_FILE} ]] || die "No existe ${ENV_FILE}."

compose() {
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

restart_odoo() {
    compose up -d odoo >/dev/null 2>&1 || true
}

trap restart_odoo EXIT

install -d -m 0700 "${BACKUP_DIR}"

log "Comprobando servicios"
compose ps
compose exec -T db pg_isready -U odoo -d "${DATABASE}" >/dev/null ||
    die "PostgreSQL no responde o no existe la base ${DATABASE}."

log "Verificando dependencias de los addons"
compose exec -T odoo python3 -c \
    'import cssselect, requests, PIL, pytesseract, pdf2image' ||
    die "Faltan dependencias Python en la imagen de Odoo."
compose exec -T odoo sh -c \
    'command -v tesseract >/dev/null && command -v pdftoppm >/dev/null' ||
    die "Faltan Tesseract o Poppler en la imagen de Odoo."

log "Creando copia de seguridad"
compose exec -T db pg_dump -U odoo -d "${DATABASE}" -Fc >"${BACKUP_DIR}/${DATABASE}.dump"
pg_restore_test="$(compose exec -T db pg_restore --list <"${BACKUP_DIR}/${DATABASE}.dump" | head -n 1 || true)"
[[ -n ${pg_restore_test} ]] || die "La copia PostgreSQL no es válida."

if [[ -d ${STACK_DIR}/odoo-data/filestore/${DATABASE} ]]; then
    tar -C "${STACK_DIR}/odoo-data/filestore"         -czf "${BACKUP_DIR}/${DATABASE}-filestore.tar.gz"         "${DATABASE}"
fi

cp -a "${COMPOSE_FILE}" "${ENV_FILE}" "${BACKUP_DIR}/"
cp -a "${STACK_DIR}/config/odoo.conf" "${BACKUP_DIR}/odoo.conf"
[[ ! -f ${STACK_DIR}/addons-git.lock ]] ||
    cp -a "${STACK_DIR}/addons-git.lock" "${BACKUP_DIR}/"

log "Deteniendo Odoo"
compose stop odoo

install_group() {
    local group_name="$1"
    local modules="$2"
    local log_file="${BACKUP_DIR}/install-${group_name}.log"

    log "Instalando bloque ${group_name}"
    compose run --rm --no-deps odoo         odoo         -c "${CONFIG_FILE}"         -d "${DATABASE}"         -i "${modules}"         --without-demo=all         --stop-after-init         --no-http         2>&1 | tee "${log_file}"
}

install_group "oca-foundation"     "date_range,date_range_account,account_tax_balance,auditlog,web_calendar_slot_duration,resource_booking,l10n_es_aeat,l10n_es_aeat_mod111,l10n_es_aeat_mod115,l10n_es_aeat_mod130,l10n_es_aeat_mod190,l10n_es_aeat_mod303,l10n_es_aeat_mod347,l10n_es_aeat_mod390"

install_group "interface"     "muk_web_appsbar,muk_web_chatter,muk_web_colors,muk_web_dialog,muk_web_theme,fd_activity_sidebar"

install_group "reception-sales"     "sale_reception_flow,sale_reception_flow_v1,sale_ai_assistant,sale_chapaypintura,fd_sugerencias_recambios_rapidapi,fd_sale_multi_offer,whatsapp_mail_messaging,fd_vehicle_maintenance_reminders"

install_group "purchase-ocr"     "fd_albaranes_compra_ai,fd_ocr_facturas_de_compra,fd_facturas_albaranes_ai"

install_group "booking-workshop"     "fd_booking,fd_booking_mechanics,fd_workshop_time_control,fd_booking_workshop,fd_booking_voice_ai"

log "Iniciando Odoo"
compose up -d odoo
trap - EXIT

for attempt in $(seq 1 30); do
    if curl --fail --silent --max-time 5 http://127.0.0.1:8069/web/login >/dev/null; then
        break
    fi
    if [[ ${attempt} -eq 30 ]]; then
        compose logs --tail 150 odoo
        die "Odoo no respondió después de instalar los módulos."
    fi
    sleep 2
done

log "Verificando estados"
readonly EXPECTED_MODULES="account_tax_balance,auditlog,date_range,date_range_account,fd_activity_sidebar,fd_albaranes_compra_ai,fd_booking,fd_booking_mechanics,fd_booking_voice_ai,fd_booking_workshop,fd_facturas_albaranes_ai,fd_ocr_facturas_de_compra,fd_sale_multi_offer,fd_sugerencias_recambios_rapidapi,fd_vehicle_maintenance_reminders,fd_workshop_time_control,l10n_es_aeat,l10n_es_aeat_mod111,l10n_es_aeat_mod115,l10n_es_aeat_mod130,l10n_es_aeat_mod190,l10n_es_aeat_mod303,l10n_es_aeat_mod347,l10n_es_aeat_mod390,muk_web_appsbar,muk_web_chatter,muk_web_colors,muk_web_dialog,muk_web_theme,resource_booking,sale_ai_assistant,sale_chapaypintura,sale_reception_flow,sale_reception_flow_v1,web_calendar_slot_duration,whatsapp_mail_messaging"

query_names="'$(printf '%s' "${EXPECTED_MODULES}" | sed "s/,/','/g")'"
states="$(compose exec -T db psql -U odoo -d "${DATABASE}" -Atc     "SELECT name || '|' || state || '|' || COALESCE(latest_version, '')
     FROM ir_module_module
     WHERE name IN (${query_names})
     ORDER BY name;")"
printf '%s\n' "${states}"

not_installed="$(printf '%s\n' "${states}" | awk -F'|' '$2 != "installed" {print}')"
installed_count="$(printf '%s\n' "${states}" | awk -F'|' '$2 == "installed" {count++} END {print count+0}')"

[[ -z ${not_installed} ]] ||
    die "Hay módulos que no quedaron instalados: ${not_installed}"
[[ ${installed_count} -eq 36 ]] ||
    die "Se esperaban 36 módulos instalados y se encontraron ${installed_count}."

log "Resultado"
compose ps
printf '\nInstalación terminada: 36 módulos instalados.\n'
printf 'Copia y logs: %s\n' "${BACKUP_DIR}"
