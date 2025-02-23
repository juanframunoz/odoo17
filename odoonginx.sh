#!/bin/bash

# Variables
DOMAIN="tudominio.com"  # Cambia esto por tu dominio
ODOO_DIR="$HOME/odoo17"

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar Docker y Docker Compose
echo "Instalando Docker y Docker Compose..."
sudo apt install docker.io docker-compose -y

# Iniciar y habilitar Docker
echo "Iniciando y habilitando Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Crear directorio para Odoo
echo "Creando directorio para Odoo..."
mkdir -p "$ODOO_DIR" && cd "$ODOO_DIR"

# Crear directorio para addons personalizados
echo "Creando directorio para addons personalizados..."
mkdir -p custom_addons

# Crear archivo docker-compose.yml
echo "Creando archivo docker-compose.yml..."
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
      - ./custom_addons:/mnt/extra-addons
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

# Iniciar Odoo con Docker Compose
echo "Iniciando Odoo 17 con Docker Compose..."
docker-compose up -d

# Instalar Nginx
echo "Instalando Nginx..."
sudo apt install nginx -y

# Configurar Nginx como proxy inverso
echo "Configurando Nginx como proxy inverso..."
sudo bash -c "cat > /etc/nginx/sites-available/$DOMAIN <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL"

# Habilitar el sitio en Nginx
echo "Habilitando el sitio en Nginx..."
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Instalar Certbot para SSL
echo "Instalando Certbot para SSL..."
sudo apt install certbot python3-certbot-nginx -y

# Obtener certificado SSL
echo "Obteniendo certificado SSL para $DOMAIN..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

# Recargar Nginx para aplicar SSL
echo "Recargando Nginx para aplicar SSL..."
sudo systemctl reload nginx

# Mostrar mensaje final
echo "¡Odoo 17, Nginx y SSL se han configurado correctamente!"
echo "Accede a Odoo en: https://$DOMAIN"
echo "Recuerda activar e instalar los módulos de localización española desde la interfaz de Odoo."
