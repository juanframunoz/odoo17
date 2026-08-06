#!/usr/bin/env bash
set -Eeuo pipefail

# Descarga desde Git las versiones seleccionadas de los addons de Odoo 17 y
# publica solo los módulos necesarios en /opt/odoo17/addons.
#
# Los repositorios privados de juanframunoz requieren una clave SSH de GitHub.
# Puede indicarse explícitamente con:
#   GITHUB_DEPLOY_KEY=/root/.ssh/id_ed25519_github_odoo17 \
#     sudo -E bash scripts/sync_odoo17_addons.sh

readonly STACK_DIR="${STACK_DIR:-/opt/odoo17}"
readonly ADDONS_DIR="${ADDONS_DIR:-${STACK_DIR}/addons}"
readonly LOCK_FILE="${LOCK_FILE:-${STACK_DIR}/addons-git.lock}"
readonly BOOKING_REF="${BOOKING_REF:-booking-workshop-integration}"
readonly FACTURAS_ALBARANES_REF="${FACTURAS_ALBARANES_REF:-agent/facturas-albaranes-ocr-reading}"

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

for command_name in git rsync python3; do
    command -v "${command_name}" >/dev/null || die "Falta el comando ${command_name}."
done

export GIT_TERMINAL_PROMPT=0
if [[ -n ${GITHUB_DEPLOY_KEY:-} ]]; then
    [[ -r ${GITHUB_DEPLOY_KEY} ]] || die "No se puede leer GITHUB_DEPLOY_KEY=${GITHUB_DEPLOY_KEY}."
    export GIT_SSH_COMMAND="ssh -i ${GITHUB_DEPLOY_KEY} -o IdentitiesOnly=yes"
fi

install -d -m 0750 "${STACK_DIR}" "${ADDONS_DIR}"
TEMP_ROOT="$(mktemp -d "${STACK_DIR}/.addons-sync.XXXXXX")"
trap 'rm -rf -- "${TEMP_ROOT}"' EXIT

# Formato: identificador|repositorio|rama|módulos separados por comas
# Las ramas de los PR se mantienen explícitas hasta validarlas y fusionarlas.
SOURCE_SPECS=(
    "fd-core|git@github.com:juanframunoz/odoo-apps.git|17.0|fd_activity_sidebar,fd_albaranes_compra_ai,fd_booking,fd_ocr_albaranes_de_compra,fd_ocr_facturas_de_compra"
    "fd-booking-workshop|git@github.com:juanframunoz/odoo-apps.git|${BOOKING_REF}|fd_booking_mechanics,fd_booking_workshop,fd_workshop_time_control"
    "fd-facturas-albaranes|git@github.com:juanframunoz/odoo-apps.git|${FACTURAS_ALBARANES_REF}|fd_facturas_albaranes_ai"
    "fd-finished|git@github.com:juanframunoz/terminados.git|main|fd_sugerencias_recambios_rapidapi,fd_whatsapp,sale_ai_assistant,sale_chapaypintura,sale_reception_flow,sale_reception_flow_v1"
    "fd-uninventoried|git@github.com:juanframunoz/sin_inventariar.git|main|fd_sale_multi_offer"
    "oca-account-financial-reporting|https://github.com/OCA/account-financial-reporting.git|17.0|account_tax_balance"
    "oca-server-tools|https://github.com/OCA/server-tools.git|17.0|auditlog"
    "oca-server-ux|https://github.com/OCA/server-ux.git|17.0|date_range,date_range_account"
    "oca-l10n-spain|https://github.com/OCA/l10n-spain.git|17.0|l10n_es_aeat,l10n_es_aeat_mod111,l10n_es_aeat_mod115,l10n_es_aeat_mod130,l10n_es_aeat_mod190,l10n_es_aeat_mod303,l10n_es_aeat_mod347,l10n_es_aeat_mod390"
    "oca-calendar|https://github.com/OCA/calendar.git|17.0|resource_booking"
    "oca-web|https://github.com/OCA/web.git|17.0|web_calendar_slot_duration"
    "muk-odoo-modules|https://github.com/muk-it/odoo-modules.git|17.0|muk_web_appsbar,muk_web_chatter,muk_web_colors,muk_web_dialog,muk_web_theme"
)

declare -A EXPECTED_MINIMUMS=(
    [fd_activity_sidebar]="17.0.4.0.0"
    [fd_albaranes_compra_ai]="17.0.1.5.37"
    [fd_booking]="17.0.0.2.1"
    [fd_booking_mechanics]="17.0.1.7.7"
    [fd_booking_workshop]="17.0.1.0.23"
    [fd_ocr_albaranes_de_compra]="17.0.3.12.0"
    [fd_ocr_facturas_de_compra]="17.0.1.9.25"
    [fd_sale_multi_offer]="17.0.3.0.2"
    [fd_sugerencias_recambios_rapidapi]="17.0.4.3.8"
    [fd_whatsapp]="17.0.17.0.7"
    [fd_workshop_time_control]="17.0.1.12.2"
    [sale_ai_assistant]="17.0.2.4.6"
    [sale_chapaypintura]="17.0.1.0.17"
    [sale_reception_flow]="17.0.1.0.47"
    [sale_reception_flow_v1]="17.0.1.1.9"
    [fd_facturas_albaranes_ai]="17.0.1.1.4"
)

manifest_version() {
    python3 - "$1" <<'PY'
import ast
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    manifest = ast.literal_eval(manifest_file.read())
print(manifest.get("version", ""))
PY
}

version_at_least() {
    local actual="$1"
    local minimum="$2"
    [[ $(printf '%s\n%s\n' "${minimum}" "${actual}" | sort -V | head -n1) == "${minimum}" ]]
}

declare -A SEEN_MODULES=()
declare -A MODULE_SOURCES=()
declare -A MODULE_VERSIONS=()
LOCK_TEMP="${TEMP_ROOT}/addons-git.lock"
printf 'source\trepository\tref\tcommit\tmodules\n' >"${LOCK_TEMP}"

for spec in "${SOURCE_SPECS[@]}"; do
    IFS='|' read -r source_id repository ref modules_csv <<<"${spec}"
    checkout="${TEMP_ROOT}/${source_id}"

    log "Descargando ${source_id} (${ref})"
    git clone --quiet --depth 1 --single-branch --branch "${ref}" "${repository}" "${checkout}" || \
        die "No se pudo descargar ${repository} (${ref}). Comprueba la clave SSH de GitHub."
    commit="$(git -C "${checkout}" rev-parse HEAD)"

    IFS=',' read -ra modules <<<"${modules_csv}"
    for module in "${modules[@]}"; do
        [[ -z ${SEEN_MODULES[${module}]:-} ]] || die "El módulo ${module} está declarado más de una vez."
        SEEN_MODULES[${module}]=1

        source_module="${checkout}/${module}"
        manifest="${source_module}/__manifest__.py"
        [[ -f ${manifest} ]] || die "Falta ${module}/__manifest__.py en ${repository} (${ref})."

        version="$(manifest_version "${manifest}")"
        [[ ${version} == 17.0.* ]] || die "${module} no es para Odoo 17: versión ${version:-vacía}."
        if [[ -n ${EXPECTED_MINIMUMS[${module}]:-} ]]; then
            version_at_least "${version}" "${EXPECTED_MINIMUMS[${module}]}" || \
                die "${module} ${version} es anterior a ${EXPECTED_MINIMUMS[${module}]}."
        fi
        MODULE_SOURCES[${module}]="${source_module}"
        MODULE_VERSIONS[${module}]="${version}"
    done

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${source_id}" "${repository}" "${ref}" "${commit}" "${modules_csv}" >>"${LOCK_TEMP}"
done

# No se modifica el directorio definitivo hasta que todos los repositorios,
# ramas, manifiestos y versiones hayan sido validados correctamente.
log "Publicando módulos validados"
for module in "${!SEEN_MODULES[@]}"; do
    source_module="${MODULE_SOURCES[${module}]}"
    target_module="${ADDONS_DIR}/${module}"
    if [[ -L ${target_module} ]]; then
        rm -f -- "${target_module}"
    fi
    install -d -m 0755 "${target_module}"
    rsync -a --delete --exclude='.git' "${source_module}/" "${target_module}/"
    printf '  %-40s %s\n' "${module}" "${MODULE_VERSIONS[${module}]}"
done

install -m 0644 "${LOCK_TEMP}" "${LOCK_FILE}"
chown -R 101:101 "${ADDONS_DIR}"

log "Validación final"
for required_module in "${!SEEN_MODULES[@]}"; do
    [[ -f ${ADDONS_DIR}/${required_module}/__manifest__.py ]] || \
        die "No se publicó correctamente ${required_module}."
done

printf '\nSincronización terminada: %s módulos publicados.\n' "${#SEEN_MODULES[@]}"
printf 'Commits utilizados: %s\n' "${LOCK_FILE}"
printf 'Reinicia Odoo y actualiza la lista de aplicaciones antes de instalar módulos.\n'
