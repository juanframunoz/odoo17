#!/usr/bin/env bash
set -Eeuo pipefail

# Despliega un Odoo 17 nuevo sobre Docker, PostgreSQL y Nginx.
# Uso:
#   sudo bash deploy_odoo17.sh

readonly DOMAIN="${DOMAIN:-electrothermotruck.mecanicos.uno}"
readonly LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-soporte@mecanicos.uno}"
readonly STACK_DIR="${STACK_DIR:-/opt/odoo17}"
readonly DB_NAME="${DB_NAME:-electrothermotruck}"
readonly COMPOSE_FILE="${STACK_DIR}/compose.yaml"
readonly ENV_FILE="${STACK_DIR}/.env"
readonly ODOO_CONFIG="${STACK_DIR}/config/odoo.conf"
readonly ODOO_DOCKERFILE="${STACK_DIR}/Dockerfile"
readonly NGINX_SITE="/etc/nginx/sites-available/${DOMAIN}"

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

command -v docker >/dev/null || die "Docker no está instalado."
docker compose version >/dev/null || die "Docker Compose no está instalado."

RESOLVED_IP="$(getent ahostsv4 "${DOMAIN}" | awk 'NR == 1 {print $1}')"
[[ -n ${RESOLVED_IP} ]] || die "El dominio ${DOMAIN} no resuelve por IPv4."

PUBLIC_IP="$(ip -4 route get 1.1.1.1 | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')"
[[ ${RESOLVED_IP} == "${PUBLIC_IP}" ]] || \
    die "${DOMAIN} resuelve a ${RESOLVED_IP}, pero el servidor usa ${PUBLIC_IP}."

log "Instalando Nginx y Certbot"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx openssl

log "Creando estructura persistente en ${STACK_DIR}"
install -d -m 0750 "${STACK_DIR}"
install -d -m 0750 \
    "${STACK_DIR}/addons" \
    "${STACK_DIR}/backups" \
    "${STACK_DIR}/config" \
    "${STACK_DIR}/odoo-data" \
    "${STACK_DIR}/postgresql"

# UID oficiales usados por las imágenes de Odoo y PostgreSQL.
chown -R 101:101 "${STACK_DIR}/addons" "${STACK_DIR}/odoo-data"
chown -R 999:999 "${STACK_DIR}/postgresql"

if [[ ! -f ${ENV_FILE} ]]; then
    POSTGRES_PASSWORD="$(openssl rand -hex 32)"
    ODOO_ADMIN_PASSWORD="$(openssl rand -hex 32)"
    cat >"${ENV_FILE}" <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
ODOO_ADMIN_PASSWORD=${ODOO_ADMIN_PASSWORD}
EOF
    chmod 0600 "${ENV_FILE}"
else
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
fi

[[ -n ${POSTGRES_PASSWORD:-} ]] || die "Falta POSTGRES_PASSWORD en ${ENV_FILE}."
[[ -n ${ODOO_ADMIN_PASSWORD:-} ]] || die "Falta ODOO_ADMIN_PASSWORD en ${ENV_FILE}."

if [[ ! -f ${ODOO_CONFIG} ]]; then
    log "Escribiendo configuración inicial de Odoo"
    cat >"${ODOO_CONFIG}" <<EOF
[options]
admin_passwd = ${ODOO_ADMIN_PASSWORD}
db_host = db
db_port = 5432
db_user = odoo
db_password = ${POSTGRES_PASSWORD}
db_maxconn = 32
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons
data_dir = /var/lib/odoo
proxy_mode = True
list_db = True
workers = 2
max_cron_threads = 1
limit_memory_soft = 536870912
limit_memory_hard = 671088640
limit_time_cpu = 120
limit_time_real = 240
log_level = info
EOF
    chown root:101 "${ODOO_CONFIG}"
    chmod 0640 "${ODOO_CONFIG}"
else
    log "Conservando la configuración existente de Odoo"
fi

log "Escribiendo imagen personalizada de Odoo"
cat >"${ODOO_DOCKERFILE}" <<'EOF'
FROM odoo:17.0

USER root
RUN apt-get update \\
    && apt-get install -y --no-install-recommends python3-cssselect \\
    && rm -rf /var/lib/apt/lists/*
USER odoo
EOF
chmod 0644 "${ODOO_DOCKERFILE}"

log "Escribiendo Docker Compose"
cat >"${COMPOSE_FILE}" <<'EOF'
services:
  db:
    image: postgres:15-bookworm
    restart: unless-stopped
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./postgresql:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - odoo_internal

  odoo:
    image: odoo17-custom:latest
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      HOST: db
      USER: odoo
      PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "127.0.0.1:8069:8069"
      - "127.0.0.1:8072:8072"
    volumes:
      - ./config/odoo.conf:/etc/odoo/odoo.conf:ro
      - ./odoo-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
    networks:
      - odoo_internal

networks:
  odoo_internal:
    driver: bridge
EOF
chmod 0640 "${COMPOSE_FILE}"

log "Validando e iniciando contenedores"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull db
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" build --pull odoo
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d

for attempt in {1..36}; do
    if curl --fail --silent --max-time 5 http://127.0.0.1:8069/web/login >/dev/null; then
        break
    fi
    if [[ ${attempt} -eq 36 ]]; then
        docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps
        docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" logs --tail=100 odoo
        die "Odoo no respondió en el tiempo esperado."
    fi
    sleep 5
done

log "Configurando Nginx"
cat >"${NGINX_SITE}" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream odoo_http {
    server 127.0.0.1:8069;
}

upstream odoo_websocket {
    server 127.0.0.1:8072;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    client_max_body_size 100m;
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    location /websocket {
        proxy_pass http://odoo_websocket;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://odoo_http;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    location ~* /web/static/ {
        proxy_pass http://odoo_http;
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
    }
}
EOF

ln -sfn "${NGINX_SITE}" "/etc/nginx/sites-enabled/${DOMAIN}"
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

log "Solicitando certificado TLS"
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "${LETSENCRYPT_EMAIL}" \
    -d "${DOMAIN}"

log "Validación final"
nginx -t
curl --fail --silent --show-error --max-time 15 "https://${DOMAIN}/web/login" >/dev/null
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps

printf '\nOdoo 17 está disponible en https://%s\n' "${DOMAIN}"
printf 'Crea una base de datos nueva con el nombre: %s\n' "${DB_NAME}"
printf 'La contraseña maestra de bases de datos está en %s (solo root).\n' "${ENV_FILE}"
