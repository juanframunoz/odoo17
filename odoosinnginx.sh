#!/bin/bash

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
admin_passwd = odoo
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

echo "Instalación y configuración de Odoo 16 completada."
