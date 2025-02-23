#!/bin/bash

# Solicitar el dominio
read -p "Introduce tu dominio (con o sin www): " DOMAIN

# Verificar si el dominio comienza con www y redirigir a sin www
if [[ $DOMAIN == www.* ]]; then
    DOMAIN_WITHOUT_WWW=${DOMAIN#www.}
else
    DOMAIN_WITHOUT_WWW=$DOMAIN
fi

# Instalar Nginx
sudo apt update
sudo apt install -y nginx

# Crear configuración de Nginx para Odoo
NGINX_CONF="/etc/nginx/sites-available/odoo"
sudo tee $NGINX_CONF > /dev/null <<EOL
# Redirigir www a sin www y HTTP a HTTPS
server {
    listen 80;
    server_name www.$DOMAIN_WITHOUT_WWW $DOMAIN_WITHOUT_WWW;
    return 301 https://$DOMAIN_WITHOUT_WWW\$request_uri;
}

# Configuración principal para HTTPS
server {
    listen 443 ssl;
    server_name $DOMAIN_WITHOUT_WWW;

    # Certificados Let's Encrypt (se generarán más adelante)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_WITHOUT_WWW/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_WITHOUT_WWW/privkey.pem;

    # Configuración de seguridad SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Servir archivos estáticos de Odoo
    location /web/static/ {
        alias /var/lib/odoo/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Servir archivos estáticos de los módulos web y ecommerce
    location /website/static/ {
        alias /var/lib/odoo/addons/website/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
    location /ecommerce/static/ {
        alias /var/lib/odoo/addons/ecommerce/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Redirigir peticiones al contenedor de Odoo
    location / {
        proxy_pass http://localhost:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Permitir frames del mismo dominio
    add_header X-Frame-Options "SAMEORIGIN";
}
EOL

# Habilitar la configuración de Nginx
sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Instalar Certbot para Let's Encrypt
sudo apt install -y certbot python3-certbot-nginx

# Obtener certificado SSL
sudo certbot --nginx -d $DOMAIN_WITHOUT_WWW --redirect --non-interactive --agree-tos -m admin@$DOMAIN_WITHOUT_WWW

# Verificar permisos del usuario odoo dentro del contenedor
echo "Verificando permisos del usuario odoo en el contenedor..."
docker exec -u 0 -it odoo17_web_1 bash -c "chown -R odoo:odoo /var/lib/odoo /var/log/odoo"

# Reiniciar Nginx
sudo systemctl restart nginx

echo "¡Configuración completada!"
echo "Accede a tu Odoo en: https://$DOMAIN_WITHOUT_WWW"
