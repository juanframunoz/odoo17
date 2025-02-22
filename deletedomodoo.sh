#!/bin/bash

# Definir el dominio
DOMAIN="odoo17.odoo.uno"

echo "========================"
echo "Eliminando certificado de $DOMAIN..."
echo "========================"

# Paso 1: Eliminar el certificado usando Certbot
sudo certbot delete --cert-name $DOMAIN

# Paso 2: Eliminar configuración de renovación
echo "Eliminando configuración de renovación..."
sudo rm -f /etc/letsencrypt/renewal/$DOMAIN.conf

# Paso 3: Eliminar archivos del certificado
echo "Eliminando archivos del certificado..."
sudo rm -rf /etc/letsencrypt/live/$DOMAIN
sudo rm -rf /etc/letsencrypt/archive/$DOMAIN

# Paso 4: Revisar y eliminar tareas programadas
echo "Revisando tareas programadas..."

# Verificar y eliminar tareas en cron
CRON_EXISTS=$(crontab -l | grep -i certbot)
if [ ! -z "$CRON_EXISTS" ]; then
    echo "Eliminando tareas de cron relacionadas con Certbot..."
    crontab -l | grep -v certbot | crontab -
else
    echo "No se encontraron tareas de cron relacionadas con Certbot."
fi

# Deshabilitar y detener el timer de systemd si existe
if systemctl list-timers | grep -q certbot; then
    echo "Deshabilitando certbot.timer..."
    sudo systemctl disable certbot.timer
    sudo systemctl stop certbot.timer
else
    echo "No se encontró certbot.timer en systemd."
fi

# Paso 5: Reiniciar el servidor web
echo "Reiniciando servicios web..."

# Verificar si Nginx está en uso y reiniciarlo
if systemctl is-active --quiet nginx; then
    echo "Reiniciando Nginx..."
    sudo systemctl reload nginx
fi

# Verificar si Apache está en uso y reiniciarlo
if systemctl is-active --quiet apache2; then
    echo "Reiniciando Apache..."
    sudo systemctl reload apache2
fi

echo "========================"
echo "Eliminación completada para $DOMAIN."
echo "========================"

