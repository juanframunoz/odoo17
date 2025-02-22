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
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        
        # Habilitar frames para el editor web de Odoo
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Content-Type-Options "nosniff";
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Servir archivos estáticos de Odoo
    location /web/static/ {
        alias /opt/odoo/custom/addons/web/static/;
        expires 30d;
        access_log off;
    }
}
EOF

# Activar la configuración y reiniciar Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Obtener certificado SSL con Let's Encrypt
sudo certbot --nginx -d $DOMAIN --agree-tos --redirect --email tu-email@ejemplo.com

# Configurar renovación automática del certificado
echo "Configurando renovación automática del certificado SSL..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

# Finalización
echo "Instalación completada. Odoo ahora está disponible en https://$DOMAIN"
