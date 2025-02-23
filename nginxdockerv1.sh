#!/bin/bash

# Preguntar el dominio
read -p "Ingrese el dominio para Odoo (ejemplo: odoo.midominio.com): " DOMAIN

# Verificar si el dominio no está vacío
if [[ -z "$DOMAIN" ]]; then
    echo "⚠️ Error: Debes ingresar un dominio válido."
    exit 1
fi

# Actualizar paquetes e instalar Nginx si no está instalado
echo "🔄 Instalando Nginx..."
sudo apt update && sudo apt install -y nginx

# Configurar el bloque de servidor para Nginx
NGINX_CONF="/etc/nginx/sites-available/odoo"

echo "⚙️ Configurando Nginx..."
sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    # Redirigir tráfico HTTP a HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # Configuración SSL (Certbot configurará los certificados)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Configurar proxy para Odoo
    location / {
        proxy_pass http://localhost:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;

        # Permitir frames solo desde el mismo dominio
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Content-Type-Options "nosniff";
    }

    # Manejo de archivos estáticos
    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_pass http://localhost:8069;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
        expires 30d;
        access_log off;
    }
}
EOL

# Habilitar la configuración de Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/

# Verificar y recargar Nginx
echo "🔄 Reiniciando Nginx..."
sudo nginx -t && sudo systemctl restart nginx

# Instalar Certbot y configurar SSL
echo "🔑 Instalando Certbot para Let's Encrypt..."
sudo apt install -y certbot python3-certbot-nginx

echo "🚀 Configurando certificados SSL con Let's Encrypt..."
sudo certbot --nginx --non-interactive --agree-tos --redirect -m admin@$DOMAIN -d $DOMAIN

# Configurar renovación automática de certificados
echo "🔄 Configurando renovación automática de certificados..."
echo "0 3 * * * root certbot renew --quiet && systemctl restart nginx" | sudo tee /etc/cron.d/certbot-renew

echo "✅ Instalación y configuración completada. Odoo ahora está accesible en: https://$DOMAIN"
