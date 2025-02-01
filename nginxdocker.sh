#!/bin/bash

# Solicitar dominio y correo electrónico
read -p "Introduce tu dominio (ejemplo: tudominio.com): " ODOO_DOMAIN
read -p "Introduce tu correo electrónico para Let's Encrypt: " EMAIL

# Configurar el firewall (ufw)
echo "Configurando el firewall..."
sudo apt install ufw -y
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw enable

# Instalar Certbot para obtener un certificado SSL
echo "Instalando Certbot..."
sudo apt install certbot python3-certbot-nginx -y

# Detener temporalmente el contenedor de Odoo para configurar SSL
echo "Deteniendo el contenedor de Odoo temporalmente..."
cd ~/odoo17
docker-compose down

# Configurar Nginx como proxy inverso para Odoo
echo "Instalando Nginx..."
sudo apt install nginx -y

# Crear un archivo de configuración de Nginx para Odoo
echo "Creando configuración de Nginx para Odoo..."
sudo bash -c "cat > /etc/nginx/sites-available/odoo <<EOL
server {
    listen 80;
    server_name $ODOO_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
EOL"

# Habilitar la configuración de Nginx
echo "Habilitando la configuración de Nginx..."
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default  # Eliminar configuración por defecto si existe

# Verificar la configuración de Nginx
echo "Verificando la configuración de Nginx..."
sudo nginx -t
if [ $? -ne 0 ]; then
    echo "Error en la configuración de Nginx. Por favor, revisa el archivo /etc/nginx/sites-available/odoo."
    exit 1
fi

# Reiniciar Nginx
echo "Reiniciando Nginx..."
sudo systemctl restart nginx

# Obtener un certificado SSL con Certbot
echo "Obteniendo un certificado SSL con Certbot..."
sudo certbot --nginx -d $ODOO_DOMAIN --non-interactive --agree-tos --email $EMAIL

# Crear archivo docker-compose.yml para Odoo 17
echo "Creando archivo docker-compose.yml para Odoo 17..."
cat <<EOL > docker-compose.yml
version: '3.1'
services:
  web:
    image: odoo:17.0
    depends_on:
      - db
    ports:
      - "127.0.0.1:8069:8069"
    volumes:
      - odoo-data:/var/lib/odoo
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  odoo-data:
  postgres-data:
EOL

# Reiniciar los contenedores de Odoo
echo "Reiniciando los contenedores de Odoo..."
docker-compose up -d

# Mostrar mensaje final
echo "¡Servidor protegido y SSL configurado correctamente!"
echo "Accede a Odoo en: https://$ODOO_DOMAIN"
