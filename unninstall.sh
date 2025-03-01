#!/bin/bash
set -e

echo "⏳ Eliminando instalación anterior de Odoo, Docker y Nginx..."

# Detener y eliminar contenedores
echo "🛑 Deteniendo y eliminando contenedores..."
cd /opt/odoo || exit
docker-compose down -v

echo "🗑️ Eliminando imágenes de Odoo, Postgres y Nginx..."
docker rm -f $(docker ps -aq)
docker rmi -f $(docker images -q odoo postgres nginx)
docker volume prune -f -y
docker network prune -f -y

echo "🗑️ Eliminando volúmenes de Odoo..."
docker volume rm $(docker volume ls -q | grep odoo)

# Detener servicios
echo "🛑 Deteniendo servicios de Docker y Nginx..."
sudo systemctl stop docker
sudo systemctl disable docker
sudo systemctl stop nginx
sudo systemctl disable nginx

# Eliminar archivos y directorios de Docker y Nginx
echo "🗑️ Eliminando archivos de Docker y Nginx..."
sudo rm -rf /opt/odoo
sudo rm -rf /var/lib/docker
sudo rm -rf /var/run/docker.sock
sudo rm -rf /run/docker
sudo rm -rf /sys/fs/cgroup/*/docker
sudo rm -rf /etc/docker
sudo rm -rf /etc/nginx
sudo rm -rf /var/lib/nginx
sudo rm -rf /var/log/nginx
sudo rm -rf /usr/share/nginx
sudo rm -rf /usr/lib/nginx
sudo rm -rf /usr/sbin/nginx
sudo rm -rf /etc/default/nginx
sudo rm -rf /etc/init.d/nginx
sudo rm -rf /etc/logrotate.d/nginx
sudo rm -rf /etc/ufw/applications.d/nginx

# No eliminamos Certbot ni Let's Encrypt
echo "🛠️ Eliminando paquetes de Docker y Nginx sin afectar Certbot..."
sudo apt remove --purge -y docker.io docker-compose nginx
sudo apt autoremove -y

# Verificar si quedan procesos activos
echo "🔍 Verificando si hay procesos activos de Docker o Nginx..."
ps aux | grep docker || true
ps aux | grep nginx || true

# (Opcional) Reiniciar para limpiar configuraciones residuales
echo "✅ Eliminación completada. Si es necesario, reinicia el sistema."
# sudo reboot
