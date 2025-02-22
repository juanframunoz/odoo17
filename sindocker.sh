#!/bin/bash

# Preguntar el dominio al usuario
echo "Introduce el dominio para Odoo (sin www, ejemplo: midominio.com):"
read DOMAIN

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar dependencias necesarias
echo "Instalando dependencias necesarias..."
sudo apt install -y python3 python3-pip python3-venv git nginx certbot python3-certbot-nginx postgresql postgresql-contrib ufw

# Configurar firewall
echo "Configurando firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Crear usuario para Odoo
echo "Creando usuario Odoo..."
sudo useradd -m -d /opt/odoo -U -r -s /bin/bash odoo

# Configurar PostgreSQL
echo "Configurando PostgreSQL..."
sudo -u postgres createuser -s odoo

# Clonar Odoo 17
echo "Clonando Odoo 17..."
sudo git clone https://www.github.com/odoo/odoo --depth 1 --branch 17.0 /opt/odoo

# Crear directorio para módulos personalizados
echo "Creando directorio para módulos personalizados..."
sudo mkdir -p /opt/odoo/custom_addons
sudo chown -R odoo:odoo /opt/odoo/custom_addons

# Configurar entorno virtual y dependencias
echo "Configurando entorno virtual y dependencias..."
sudo -u odoo python3 -m venv /opt/odoo/venv
source /opt/odoo/venv/bin/activate
pip install -r /opt/odoo/requirements.txt
deactivate

# Crear el servicio de systemd para Odoo
echo "Creando servicio de systemd para Odoo..."
sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOL
[Unit]
Description=Odoo
After=network.target

[Service]
Type=simple
User=odoo
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/odoo-bin --addons-path=/opt/odoo/addons,/opt/odoo/custom_addons --db-filter=${DOMAIN}
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Recargar daemon y habilitar Odoo
sudo systemctl daemon-reload
sudo systemctl enable --now odoo

# Configurar Nginx
echo "Configurando Nginx..."
sudo tee /etc/nginx/sites-available/odoo > /dev/null <<EOL
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://${DOMAIN}\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;

    access_log /var/log/nginx/odoo_access.log;
    error_log /var/log/nginx/odoo_error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
    }
    
    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_pass http://127.0.0.1:8069;
    }
}
EOL

# Habilitar configuración y reiniciar Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

# Configurar Certbot para HTTPS
echo "Obteniendo certificado SSL con Certbot..."
sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m admin@${DOMAIN}

# Habilitar redirección automática de SSL
echo "Habilitando redirección automática a HTTPS..."
sudo certbot renew --dry-run

# Finalización
echo "Instalación completada. Odoo está funcionando en https://${DOMAIN}"
