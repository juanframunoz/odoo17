#!/bin/bash

# Preguntar el dominio al usuario
read -p "Ingrese el dominio para Odoo (ejemplo: odoo.midominio.com): " DOMAIN

# Verificar que el dominio no esté vacío
if [[ -z "$DOMAIN" ]]; then
    echo "⚠️ Error: Debe ingresar un dominio válido."
    exit 1
fi

# Preguntar las contraseñas al usuario
read -s -p "Ingrese la contraseña para Odoo (Base de datos): " ODOO_PASSWORD
echo ""
read -s -p "Ingrese la contraseña para PostgreSQL: " POSTGRES_PASSWORD
echo ""

# Verificar que las contraseñas no estén vacías
if [[ -z "$ODOO_PASSWORD" || -z "$POSTGRES_PASSWORD" ]]; then
    echo "⚠️ Error: No puede dejar las contraseñas vacías."
    exit 1
fi

# Definir variables
ODOO_VERSION="17.0"
ODOO_DIR="/opt/odoo17-docker"
POSTGRES_DIR="/opt/pg-data"

# Instalar Docker y Docker Compose si no están instalados
echo "🔄 Instalando Docker y Docker Compose..."
sudo apt update && sudo apt install -y docker.io docker-compose

# Crear directorios para Odoo, PostgreSQL y Certbot
mkdir -p $ODOO_DIR $POSTGRES_DIR $ODOO_DIR/nginx-webroot

# Crear el archivo docker-compose.yml
echo "⚙️ Creando configuración de Docker Compose..."
cat <<EOF > $ODOO_DIR/docker-compose.yml
version: '3.1'

services:
  db:
    image: postgres:15
    container_name: odoo_db
    restart: always
    environment:
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: odoo
    volumes:
      - $POSTGRES_DIR:/var/lib/postgresql/data

  odoo:
    image: odoo:$ODOO_VERSION
    container_name: odoo_server
    depends_on:
      - db
    ports:
      - "8069:8069"
    environment:
      HOST: db
      USER: odoo
      PASSWORD: $POSTGRES_PASSWORD
    volumes:
      - $ODOO_DIR/odoo-web-data:/var/lib/odoo
      - $ODOO_DIR/addons:/mnt/extra-addons

  nginx:
    image: nginx:latest
    container_name: odoo_nginx
    depends_on:
      - odoo
    volumes:
      - $ODOO_DIR/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - $ODOO_DIR/nginx-webroot:/var/www/html
    ports:
      - "80:80"
      - "443:443"
    restart: always

  certbot:
    image: certbot/certbot
    container_name: odoo_certbot
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt
      - $ODOO_DIR/nginx-webroot:/var/www/html
    entrypoint: ["/bin/sh", "-c", "trap exit TERM; while :; do certbot renew --webroot -w /var/www/html; sleep 12h & wait \$${!}; done"]
EOF

# Crear configuración de Nginx
echo "⚙️ Configurando Nginx..."
cat <<EOF > $ODOO_DIR/nginx.conf
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://odoo:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Content-Type-Options "nosniff";
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_pass http://odoo:8069;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
        expires 30d;
        access_log off;
    }
}
EOF

# Iniciar contenedores de Odoo, PostgreSQL y Nginx
echo "🚀 Iniciando Odoo, PostgreSQL y Nginx con Docker Compose..."
cd $ODOO_DIR
docker-compose up -d

# Instalar Certbot y obtener certificado SSL
echo "🔑 Instalando Certbot y generando certificado SSL..."
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v $ODOO_DIR/nginx-webroot:/var/www/html certbot/certbot certonly --webroot -w /var/www/html --email admin@$DOMAIN --agree-tos --no-eff-email -d $DOMAIN

# Reiniciar Nginx para aplicar el certificado SSL
echo "🔄 Reiniciando Nginx..."
docker-compose restart nginx

# Configurar la renovación automática de SSL
echo "🔄 Configurando renovación automática de certificados..."
echo "0 3 * * * root docker-compose run --rm certbot renew && docker-compose restart nginx" | sudo tee /etc/cron.d/certbot-renew

# Verificar que los contenedores están corriendo
docker ps

echo "✅ Instalación completada. Accede a Odoo en: https://$DOMAIN"
