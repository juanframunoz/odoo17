#!/bin/bash

# Preguntar el dominio al usuario
echo "Por favor, ingrese el dominio para Odoo (ejemplo: odoo.tudominio.com):"
read DOMAIN

# Variables
ODOO_DIR="/opt/odoo"
ODOO_PORT="8069"
ODOO_DB_PORT="5432"
ODOO_VOLUME_DIR="/var/lib/docker/volumes/odoo/"

# Actualizar el sistema
sudo apt update && sudo apt upgrade -y

# Verificar e instalar dependencias
if ! command -v docker &> /dev/null; then
    echo "⚠️ Docker no está instalado. Instalándolo ahora..."
    sudo apt install -y docker.io
fi

if ! command -v nginx &> /dev/null; then
    echo "⚠️ Nginx no está instalado. Instalándolo ahora..."
    sudo apt install -y nginx
fi

if ! command -v docker-compose &> /dev/null; then
    echo "⚠️ Docker Compose no está instalado. Instalando la última versión..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

sudo apt install -y curl git unzip python3-pip certbot

# Crear directorios
sudo mkdir -p $ODOO_DIR/extra-addons
sudo mkdir -p $ODOO_VOLUME_DIR/filestore
sudo mkdir -p $ODOO_VOLUME_DIR/static

# Configurar permisos
sudo chown -R 1000:1000 $ODOO_DIR
sudo chown -R 1000:1000 $ODOO_VOLUME_DIR
sudo chmod -R 775 $ODOO_VOLUME_DIR

# Crear archivo docker-compose.yml
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
        server_name $DOMAIN;

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

        add_header X-Frame-Options SAMEORIGIN;
        add_header Content-Security-Policy "frame-ancestors 'self';" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        location /web/static/ {
            alias /usr/lib/python3/dist-packages/odoo/addons/web/static/;
            expires 90d;
            access_log off;
        }

        location /filestore/ {
            alias /var/lib/odoo/filestore/;
            expires 90d;
            access_log off;
        }

        location / {
            proxy_pass http://odoo:$ODOO_PORT;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_redirect off;
        }
    }
}
EOF


# Crear archivo de configuración de Nginx
cat <<EOF | sudo tee $ODOO_DIR/nginx.conf
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
        server_name $DOMAIN;

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

        add_header X-Frame-Options SAMEORIGIN;
        add_header Content-Security-Policy "frame-ancestors 'self';" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        location /web/static/ {
            alias /usr/lib/python3/dist-packages/odoo/addons/web/static/;
            expires 90d;
            access_log off;
        }

        location /filestore/ {
            alias /var/lib/odoo/filestore/;
            expires 90d;
            access_log off;
        }

        location / {
            proxy_pass http://odoo:$ODOO_PORT;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
        }
    }
}
EOF

# Iniciar los contenedores
cd $ODOO_DIR
docker-compose up -d

# Obtener certificado SSL solo si no existe
if ! sudo certbot certificates | grep -q "$DOMAIN"; then
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
else
    echo "✅ Certificado SSL ya existente para $DOMAIN, no es necesario regenerarlo."
fi

# Configurar renovación automática de certificados
(crontab -l ; echo "0 3 * * * certbot renew --quiet") | crontab -

# Verificar estado de los contenedores
echo "⌛ Verificando que los contenedores estén corriendo..."
docker ps

# Mensaje final
echo "🚀 Odoo 17 instalado correctamente con Nginx y Let's Encrypt en Ubuntu 22.04. Accede a: https://$DOMAIN"
