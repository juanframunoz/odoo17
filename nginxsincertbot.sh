#!/bin/bash

# Solicitar el dominio al usuario
echo "Introduce el dominio donde se servirá Odoo (ej. odoo.midominio.com):"
read DOMAIN

# Definir variables de configuración
DIR_ODOO=~/odoo17
NGINX_CONF=nginx.conf
COMPOSE_FILE=docker-compose.yml

# Verificar si Docker y Docker Compose están instalados
if ! command -v docker &> /dev/null; then
    echo "Docker no está instalado. Instalándolo..."
    sudo apt update && sudo apt install -y docker.io
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose no está instalado. Instalándolo..."
    sudo apt install -y docker-compose
fi

# Verificar si ya existen los volúmenes antes de crearlos
docker volume inspect odoo-data &> /dev/null || docker volume create odoo-data
docker volume inspect postgres-data &> /dev/null || docker volume create postgres-data

# Crear directorio de instalación si no existe
if [ ! -d "$DIR_ODOO" ]; then
    mkdir -p $DIR_ODOO
fi
cd $DIR_ODOO

# Crear docker-compose.yml
cat <<EOL > $COMPOSE_FILE
version: '3.1'

services:
  db:
    image: postgres:15
    container_name: odoo17_bd_1
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - postgres-data:/var/lib/postgresql/data
    restart: always
    ports:
      - "5432:5432"

  odoo:
    image: odoo:17.0
    container_name: odoo17_web_1
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    volumes:
      - odoo-data:/var/lib/odoo
      - ./custom_addons:/mnt/extra-addons
      - ./logs/odoo:/var/log/odoo
    restart: always
    expose:
      - 8069
    user: "1000:1000"  # Asegurar que Odoo corre como usuario correcto

  nginx:
    image: nginx:latest
    container_name: odoo_nginx
    depends_on:
      - odoo
    volumes:
      - ./$NGINX_CONF:/etc/nginx/nginx.conf:ro
      - ./logs/nginx:/var/log/nginx
      - odoo-data:/var/lib/odoo
    ports:
      - "80:80"
    restart: always

volumes:
  odoo-data:
  postgres-data:
EOL

# Crear configuración de Nginx
cat <<EOL > $NGINX_CONF
worker_processes auto;
events { worker_connections 1024; }
http {
    server {
        listen 80;
        server_name $DOMAIN;

        location / {
            proxy_pass http://odoo:8069;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_hide_header X-Frame-Options;
            add_header X-Frame-Options "ALLOW-FROM http://$DOMAIN";
            add_header Content-Security-Policy "frame-ancestors 'self' http://$DOMAIN";
            proxy_buffering off;
        }

        location /web/static/ {
            alias /var/lib/odoo/addons/17.0/web/static/;
            expires 30d;
            add_header Cache-Control "public, max-age=2592000";
            add_header X-Frame-Options "ALLOW-FROM http://$DOMAIN";
        }

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;
    }
}
EOL

# Asignar permisos dentro de los contenedores
docker-compose up -d
sleep 5  # Esperar a que los contenedores arranquen

docker exec -u root odoo17_web_1 chown -R 1000:1000 /var/lib/odoo /mnt/extra-addons /var/log/odoo
docker exec -u root odoo17_bd_1 chown -R 999:999 /var/lib/postgresql/data

echo "Odoo está configurado y accesible en http://$DOMAIN"
