#!/bin/bash

# Preguntar el dominio al usuario
echo "Por favor, ingrese el dominio para Odoo (ejemplo: fichar.me o https://fichar.me):"
read INPUT_DOMAIN

# Si el usuario no incluye el protocolo, se añade HTTPS por defecto
if [[ "$INPUT_DOMAIN" != http*://* ]]; then
    DOMAIN="https://$INPUT_DOMAIN"
else
    DOMAIN="$INPUT_DOMAIN"
fi

# Extraer solo el hostname (quitando el protocolo)
HOSTNAME="${DOMAIN#*://}"

echo "Usando DOMAIN (con protocolo): $DOMAIN"
echo "Usando HOSTNAME: $HOSTNAME"

# Variables de directorios y puertos
ODOO_DIR="/opt/odoo"
ODOO_PORT="8069"
ODOO_DB_PORT="5432"
ODOO_VOLUME_DIR="/var/lib/docker/volumes/odoo"

# Actualizar el sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependencias (Docker, Nginx, Docker Compose, Certbot, etc.)
if ! command -v docker &> /dev/null; then
    echo "⚠️ Docker no está instalado. Instalándolo ahora..."
    sudo apt install -y docker.io
fi

if ! command -v nginx &> /dev/null; then
    echo "⚠️ Nginx no está instalado. Instalándolo ahora..."
    sudo apt install -y nginx
fi

if ! command -v docker-compose &> /dev/null; then
    echo "⚠️ Docker Compose no está instalado. Instalándolo ahora..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

sudo apt install -y curl git unzip python3-pip certbot

# Detener y deshabilitar Nginx del host para evitar conflictos con Certbot
sudo systemctl stop nginx
sudo systemctl disable nginx

# Crear directorios necesarios
sudo mkdir -p $ODOO_DIR
sudo mkdir -p $ODOO_DIR/extra-addons
sudo mkdir -p $ODOO_VOLUME_DIR/filestore

# Configurar permisos (asegurando que el filestore sea propiedad del usuario que ejecuta Odoo, UID 101)
sudo chown -R 101:101 $ODOO_DIR
sudo chown -R 101:101 $ODOO_VOLUME_DIR
sudo chmod -R 775 $ODOO_VOLUME_DIR

# Crear archivo de configuración personalizado para Odoo
cat <<'EOF' | sudo tee $ODOO_DIR/odoo.conf
[options]
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
db_name = odoo
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/var/lib/odoo/.local/share/Odoo/addons/17.0
proxy_mode = True
admin_passwd = admin
EOF

# Crear archivo docker-compose.yml
cat <<'EOF' | sudo tee $ODOO_DIR/docker-compose.yml
services:
  db:
    image: postgres:15
    container_name: postgres_db
    restart: always
    environment:
      POSTGRES_DB: odoo
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: odoo
    volumes:
      - /var/lib/docker/volumes/odoo/pgdata:/var/lib/postgresql/data

  odoo:
    image: odoo:17
    container_name: odoo17
    restart: always
    depends_on:
      - db
    volumes:
      - /var/lib/docker/volumes/odoo/filestore:/var/lib/odoo/filestore
      # Se monta extra-addons aunque esté vacío; se puede comentar si no se utiliza.
      - /opt/odoo/extra-addons:/mnt/extra-addons
      - /opt/odoo/odoo.conf:/etc/odoo/odoo.conf:ro
    environment:
      - DB_HOST=db
      - DB_PORT=5432
      - DB_USER=odoo
      - DB_PASSWORD=odoo
      - PROXY_MODE=True
    ports:
      - "8069:8069"

  nginx:
    image: nginx:latest
    container_name: nginx_odoo
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/odoo/nginx.conf:/etc/nginx/nginx.conf:ro
      - /var/lib/docker/volumes/odoo/filestore:/var/lib/odoo/filestore:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

# Crear archivo de configuración de Nginx
cat <<'EOF' | sudo tee $ODOO_DIR/nginx.conf
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    sendfile on;
    gzip on;
    gzip_types text/css application/javascript image/svg+xml;
    client_max_body_size 100M;

    server {
        listen 80;
        server_name DOMAIN_PLACEHOLDER;

        location / {
            return 301 https://$host$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name DOMAIN_PLACEHOLDER;

        ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

        add_header X-Frame-Options SAMEORIGIN;
        add_header Content-Security-Policy "frame-ancestors 'self';" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        # Se utiliza proxy inverso para pasar todas las solicitudes a Odoo,
        # permitiendo que Odoo sirva sus activos de forma segura.
        location / {
            proxy_pass http://odoo:8069;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
        }
    }
}
EOF

# Reemplazar DOMAIN_PLACEHOLDER por el hostname real en nginx.conf
sudo sed -i "s/DOMAIN_PLACEHOLDER/$HOSTNAME/g" $ODOO_DIR/nginx.conf

# Iniciar los contenedores (bajamos todo si es una instalación nueva)
cd $ODOO_DIR
docker-compose down -v
docker-compose up -d

# Esperar unos segundos para que se inicien los contenedores y la base de datos
sleep 10

# Forzar la inicialización del módulo base en Odoo (esto creará las tablas necesarias)
docker exec -it odoo17 odoo -d odoo -i base --stop-after-init

# Reiniciar el contenedor de Odoo
docker-compose start odoo

# Actualizar el parámetro web.base.url en la base de datos para que use HTTPS
docker exec -it postgres_db psql -U odoo -d odoo -c "INSERT INTO ir_config_parameter(key, value) VALUES ('web.base.url', '$DOMAIN') ON CONFLICT (key) DO UPDATE SET value = '$DOMAIN';"

# Generar certificados SSL (usando Certbot standalone)
if ! sudo certbot certificates | grep -q "$HOSTNAME"; then
    echo "No se encontró certificado SSL para $HOSTNAME. Generando certificado..."
    docker-compose stop nginx
    sudo certbot certonly --standalone -d $HOSTNAME --non-interactive --agree-tos --email admin@$HOSTNAME
    docker-compose start nginx
else
    echo "✅ Certificado SSL ya existente para $HOSTNAME, no es necesario regenerarlo."
fi

# Verificar y generar ssl-dhparams.pem si es necesario
if [ ! -s /etc/letsencrypt/ssl-dhparams.pem ] || [ $(stat -c%s /etc/letsencrypt/ssl-dhparams.pem) -lt 100 ]; then
    echo "Generando DH parameters de 2048 bits..."
    sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

# Configurar renovación automática de certificados
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -

# Verificar estado de los contenedores
echo "⌛ Verificando que los contenedores estén corriendo..."
docker ps

echo "🚀 Odoo 17 instalado correctamente con Nginx y Let's Encrypt en Ubuntu 22.04."
echo "Accede a: $DOMAIN"
