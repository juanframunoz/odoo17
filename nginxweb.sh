#!/bin/bash

# Solicitar el dominio al usuario
echo "Introduce el dominio en el que quieres instalar Odoo (ej: fichar.me):"
read -r DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Error: No has ingresado un dominio. Saliendo..."
    exit 1
fi

# Actualizar el sistema e instalar Nginx y Certbot
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx

# Crear configuración de Nginx para el dominio
echo "Configurando Nginx para el dominio $DOMAIN..."
cat <<EOF | sudo tee /etc/nginx/sites-available/odoo
server {
    listen 80;
    server_name mkt.odoo.uno;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name mkt.odoo.uno;

    ssl_certificate /etc/letsencrypt/live/mkt.odoo.uno/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mkt.odoo.uno/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Add Headers for Odoo proxy mode
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Client-IP $remote_addr;
    proxy_set_header HTTP_X_FORWARDED_HOST $remote_addr;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";

    # Logging
    access_log  /var/log/nginx/odoo-access.log;
    error_log   /var/log/nginx/odoo-error.log;

    # Increase proxy buffer size
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;
    proxy_read_timeout 900s;
    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;

    # Force timeouts if the backend dies
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
    
    # Enable data compression
    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/css text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
    gzip_vary on;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 64k;
    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_redirect http:// https://;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 2d;
        proxy_pass http://127.0.0.1:8069;
        add_header Cache-Control "public, no-transform";
    }

    # Cache static data in memory for 60 mins
    location ~ /[a-zA-Z0-9_-]*/static/ {
        proxy_cache_valid 200 302 60m;
        proxy_cache_valid 404 1m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://127.0.0.1:8069;
    }
}

EOF

# Activar la configuración y reiniciar Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Obtener certificado SSL con Let's Encrypt
sudo certbot --nginx -d $DOMAIN --agree-tos --redirect --email sistemas@odoo.uno

# Configurar renovación automática del certificado
echo "Configurando renovación automática del certificado SSL..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

# Finalización
echo "Instalación completada. Odoo ahora está disponible en https://$DOMAIN"
