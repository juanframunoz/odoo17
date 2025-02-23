#!/bin/bash

# Solicita el dominio al usuario
read -p "Ingrese el dominio para Odoo (ej. odoo17.ejemplo.com): " DOMAIN

# Define la ruta del archivo de configuración de Nginx
NGINX_CONF="/etc/nginx/sites-available/odoo"

# Instalar dependencias necesarias
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx

# Sobrescribir el archivo de configuración de Odoo en Nginx
echo "Sobrescribiendo configuración de Nginx para Odoo..."

cat <<EOF | sudo tee $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirigir HTTP a HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # Configuración SSL (Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # Configuración de Odoo
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;

        # WebSockets
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_http_version 1.1;
        proxy_read_timeout 720s;
        proxy_connect_timeout 720s;
        proxy_send_timeout 720s;
    }

    # WebSockets específicos para Odoo
    location /websocket {
        proxy_pass http://127.0.0.1:8072;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_http_version 1.1;
    }

    # Seguridad: bloquea acceso a archivos sensibles
    location ~* /\.(git|env|htaccess|htpasswd) {
        deny all;
    }

    # Protección contra ataques en iframes
    add_header X-Frame-Options SAMEORIGIN;

    # Seguridad contra ataques de contenido mixto y XSS
    add_header Content-Security-Policy "default-src 'self' https: blob: data: 'unsafe-inline' 'unsafe-eval';" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # CORS
    add_header Access-Control-Allow-Origin "https://$DOMAIN";
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE";
    add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization";
    add_header Access-Control-Allow-Credentials true;
    add_header Set-Cookie "SameSite=None; Secure";
}
EOF

# Crear un enlace simbólico en "sites-enabled"
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/odoo

# Verificar configuración de Nginx
echo "Verificando configuración de Nginx..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Configuración válida. Reiniciando Nginx..."
    sudo systemctl restart nginx
else
    echo "❌ Error en la configuración de Nginx. Revisa el archivo $NGINX_CONF"
    exit 1
fi

# Solicitar y configurar el certificado SSL con Let's Encrypt
echo "Obteniendo certificado SSL con Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN --agree-tos --redirect --non-interactive --email admin@$DOMAIN

# Recargar Nginx después de la instalación del certificado SSL
sudo systemctl reload nginx

# Verificar si Odoo está en ejecución
echo "Verificando que Odoo está en ejecución..."
if systemctl is-active --quiet odoo; then
    echo "✅ Odoo está en ejecución."
else
    echo "❌ Odoo no está en ejecución. Iniciándolo..."
    sudo systemctl start odoo
    sudo systemctl enable odoo
fi

echo "✅ Configuración completada con éxito para Odoo en $DOMAIN"
