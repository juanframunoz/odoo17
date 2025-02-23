#!/bin/bash

# Solicitar el dominio al usuario
echo "Introduce el dominio en el que quieres instalar Odoo (ej: fichar.me):"
read -r DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Error: No has ingresado un dominio. Saliendo..."
    exit 1
fi

# Detener y eliminar todos los contenedores en ejecución
echo "Deteniendo todos los contenedores en ejecución..."
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

# Crear estructura de directorios
mkdir -p ~/odoo-docker/{nginx/conf.d,certbot/www,certbot/conf}
cd ~/odoo-docker || exit

# Crear archivo docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  odoo:
    image: odoo:17
    depends_on:
      - db
    ports:
      - "8070:8069"
    volumes:
      - odoo-data:/var/lib/odoo
      - ./config:/etc/odoo
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo

  db:
    image: postgres:13
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - POSTGRES_DB=postgres
    volumes:
      - db-data:/var/lib/postgresql/data

  nginx:
    image: nginx:latest
    depends_on:
      - odoo
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
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 12h & wait $${!}; done'"

volumes:
  odoo-data:
  db-data:
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
        proxy_pass http://odoo:8070;
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
        proxy_pass http://odoo:8072;
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

# Generar certificado SSL con Certbot
docker run --rm -v $(pwd)/certbot/conf:/etc/letsencrypt -v $(pwd)/certbot/www:/var/www/certbot certbot/certbot certonly --webroot -w /var/www/certbot -d $DOMAIN --email tu-email@ejemplo.com --agree-tos --no-eff-email

# Levantar los contenedores
docker-compose up -d

# Configuración final
echo "Instalación completada. Odoo ahora está disponible en https://$DOMAIN"
