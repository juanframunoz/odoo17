#!/bin/bash

# Formulario para solicitar la master password
echo "-----------------------------------------"
echo "Configuración inicial de Odoo"
echo "-----------------------------------------"
read -sp "Introduce la master password para Odoo: " master_password
echo ""

if [ -z "$master_password" ]; then
    echo "La master password no puede estar vacía. Inténtalo de nuevo."
    exit 1
fi

# Actualización del sistema
echo "Actualizando el sistema..."
apt update && apt upgrade -y

# Instalación de dependencias necesarias
echo "Instalando dependencias necesarias..."
apt install -y git python3-pip build-essential wget python3-dev python3-venv python3-wheel \
libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools libjpeg-dev libpq-dev \
libxml2-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev libssl-dev libffi-dev

# Instalación de PostgreSQL
echo "Instalando PostgreSQL..."
apt install -y postgresql postgresql-server-dev-all

# Configuración de PostgreSQL
echo "Configurando PostgreSQL..."
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser --pwprompt odoo

# Instalación de wkhtmltopdf
echo "Instalando wkhtmltopdf..."
apt install -y wkhtmltopdf

# Instalación de Node.js y lessc
echo "Instalando Node.js y lessc..."
apt install -y nodejs npm
npm install -g less less-plugin-clean-css

# Clonación del repositorio de Odoo 16
echo "Clonando el repositorio de Odoo 16..."
git clone https://www.github.com/odoo/odoo --branch 16.0 --depth 1 /opt/odoo

# Creación de un entorno virtual de Python
echo "Creando un entorno virtual de Python..."
cd /opt/odoo
python3 -m venv odoo-venv
source odoo-venv/bin/activate

# Instalación de las dependencias de Python
echo "Instalando dependencias de Python..."
pip3 install wheel
pip3 install -r requirements.txt
deactivate

# Creación del usuario odoo
echo "Creando el usuario odoo..."
adduser --system --home=/opt/odoo --group odoo

# Configuración de los permisos y creación de carpetas necesarias
echo "Configurando permisos y creando carpetas necesarias..."
mkdir /opt/odoo/extra-addons
chown -R odoo:odoo /opt/odoo
chmod -R 755 /opt/odoo

# Creación de la carpeta .local para el usuario odoo
echo "Creando y configurando la carpeta .local para odoo..."
sudo mkdir -p /opt/odoo/.local
sudo chown -R odoo:odoo /opt/odoo/.local

# Configuración del archivo odoo.conf
echo "Configurando el archivo odoo.conf..."
cat <<EOF > /etc/odoo.conf
[options]
admin_passwd = $master_password
db_host = False
db_port = False
db_user = odoo
db_password = odoo
addons_path = /opt/odoo/addons,/opt/odoo/extra-addons
logfile = /var/log/odoo/odoo.log
xmlrpc_interface = 0.0.0.0
EOF
chown odoo: /etc/odoo.conf
chmod 640 /etc/odoo.conf

# Creación del servicio de Odoo
echo "Creando el servicio de Odoo..."
cat <<EOF > /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=https://www.odoo.com
After=network.target postgresql.service

[Service]
User=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo-bin -c /etc/odoo.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar el servicio de Odoo
echo "Habilitando y iniciando el servicio de Odoo..."
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

# Verificación del estado del servicio
echo "Verificando el estado del servicio de Odoo..."
systemctl status odoo

# Apertura del puerto 8069 en el firewall (opcional)
echo "Abriendo el puerto 8069 en el firewall..."
ufw allow 8069/tcp

# Reiniciar Odoo
sudo systemctl restart odoo

echo "-----------------------------------------"
echo "¡Instalación de Odoo 16 completada con éxito!"

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
