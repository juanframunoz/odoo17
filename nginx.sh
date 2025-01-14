#!/bin/bash

echo "Configurar Nginx y Let's Encrypt para Odoo"
echo "-----------------------------------------"

# Solicitar dominio y correo electrónico
read -p "Introduce tu dominio (ejemplo: tu-dominio.com): " dominio
read -p "Introduce tu correo electrónico (para Let's Encrypt): " email

if [ -z "$dominio" ] || [ -z "$email" ]; then
    echo "El dominio y el correo electrónico son obligatorios. Inténtalo de nuevo."
    exit 1
fi

# Instalar Nginx
echo "Instalando Nginx..."
sudo apt update && sudo apt install -y nginx

# Crear archivo de configuración de Nginx para HTTP
echo "Configurando Nginx para el dominio $dominio (HTTP)..."
sudo bash -c "cat > /etc/nginx/sites-available/$dominio <<'EOF'
server {
    listen 80;
    server_name www.$dominio $dominio;

    # Redirigir www a sin www
    if (\$host = www.$dominio) {
        return 301 http://$dominio\$request_uri;
    }

    # Pasar tráfico a Odoo en HTTP
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF"

# Crear enlace simbólico y recargar Nginx
if [ -L /etc/nginx/sites-enabled/$dominio ]; then
    echo "El enlace simbólico ya existe. Reemplazando..."
    sudo rm /etc/nginx/sites-enabled/$dominio
fi
sudo ln -s /etc/nginx/sites-available/$dominio /etc/nginx/sites-enabled/

echo "Verificando configuración de Nginx..."
sudo nginx -t

if [ $? -ne 0 ]; then
    echo "Error en la configuración de Nginx. Verifica el archivo de configuración."
    exit 1
fi

sudo systemctl reload nginx

# Instalar Certbot
echo "Instalando Certbot para Let's Encrypt..."
sudo apt install -y certbot python3-certbot-nginx

# Generar certificado SSL
echo "Generando certificados SSL para $dominio..."
sudo certbot --nginx -d $dominio -d www.$dominio --email $email --agree-tos --non-interactive --redirect

if [ $? -ne 0 ]; then
    echo "Error al generar el certificado SSL. Verifica tu dominio y correo electrónico."
    exit 1
fi

# Verificar renovación automática
echo "Verificando renovación automática del certificado..."
sudo certbot renew --dry-run

echo "-----------------------------------------"
echo "¡Configuración completada con éxito!"
echo "Tu sitio está disponible en https://$dominio"

# si aparece error ejecutar c>>sudo certbot --nginx -d dominio.com --email hola@2pz.org --agree-tos --non-interactive --redirect
