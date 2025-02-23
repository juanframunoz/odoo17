#!/bin/bash

# Solicitar el dominio al usuario
echo "Introduce el dominio en el que quieres instalar Odoo (ej: fichar.me):"
read -r DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Error: No has ingresado un dominio. Saliendo..."
    exit 1
fi

# Verificar si docker-compose.yml existe antes de intentar detener contenedores
if [ -f "docker-compose.yml" ]; then
    echo "Deteniendo todos los contenedores en ejecución..."
    docker-compose down --remove-orphans
else
    echo "No se encontró docker-compose.yml, creando uno nuevo..."
fi

# Crear estructura de directorios
mkdir -p ~/odoo/
mkdir -p ~/odoo/nginx/conf.d ~/odoo/certbot/www ~/odoo/certbot/conf ~/odoo/custom_addons
cd ~/odoo || exit

# Crear archivo docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.1'

services:
  web:
    image: odoo:17.0
    depends_on:
      - db
    expose:
      - "8069"
    volumes:
      - odoo-data:/var/lib/odoo
      - ./custom_addons:/mnt/extra-addons
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - postgres-data:/var/lib/postgresql/data

  nginx:
    image: nginx:latest
    depends_on:
      - web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    restart: always

  certbot:
    image: certbot/certbot
    depends_on:
      - nginx
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 12h & wait $${!}; done'"

volumes:
  odoo-data:
  postgres-data:
EOF

# Crear configuración de Nginx
cat <<EOF > nginx/conf.d/odoo.conf
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://web:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;

        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Content-Type-Options "nosniff";
    }

    location /longpolling {
        proxy_pass http://web:8072;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /web/static/ {
        alias /var/lib/odoo/addons/web/static/;
        expires 30d;
        access_log off;
    }
}
EOF

# Levantar los contenedores
echo "Levantando los contenedores..."
docker-compose up -d

# Esperar unos segundos para que Nginx esté completamente activo
sleep 10

# Verificar que Nginx esté corriendo
docker ps | grep nginx

# Generar certificado SSL con Certbot
echo "Generando certificado SSL..."
docker run --rm -v $(pwd)/certbot/conf:/etc/letsencrypt \
             -v $(pwd)/certbot/www:/var/www/certbot \
             certbot/certbot certonly --webroot -w /var/www/certbot \
             -d $DOMAIN --email tu-email@ejemplo.com --agree-tos --no-eff-email

# Reiniciar Nginx para aplicar los cambios
echo "Reiniciando Nginx..."
docker-compose restart nginx

# Configuración final
echo "Instalación completada. Odoo ahora está disponible en https://$DOMAIN"
