#!/bin/bash
set -e

echo "⏳ Eliminando instalación anterior de Odoo y Docker..."

# Detener y eliminar contenedores
echo "🛑 Deteniendo y eliminando contenedores..."
cd /opt/odoo
docker-compose down -v

echo "🗑️ Eliminando imágenes de Odoo, Postgres y Nginx..."
docker rm -f $(docker ps -aq)
docker rmi -f $(docker images -q odoo postgres nginx)
docker volume prune -f
docker network prune -f

echo "🗑️ Eliminando volúmenes de Odoo..."
docker volume rm $(docker volume ls -q | grep odoo)

# Eliminar directorios
echo "🗑️ Eliminando directorios de configuración..."
sudo rm -rf /opt/odoo
sudo rm -rf /var/lib/docker/volumes/odoo

# No eliminamos Certbot ni Let's Encrypt
echo "🛠️ Eliminando paquetes de Docker y Nginx sin afectar Certbot..."
sudo apt remove --purge -y docker.io docker-compose nginx
sudo apt autoremove -y

# Verificar si quedan procesos activos
echo "🔍 Verificando si hay procesos activos de Docker o Nginx..."
ps aux | grep docker
ps aux | grep nginx

# (Opcional) Reiniciar para limpiar configuraciones residuales
echo "✅ Eliminación completada. Si es necesario, reinicia el sistema."
# sudo reboot
