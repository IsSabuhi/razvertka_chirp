#!/usr/bin/env bash
set -euo pipefail

echo ">>> Установка и запуск Mosquitto..."
apt-get update
apt-get install -y mosquitto mosquitto-clients
systemctl enable mosquitto
systemctl restart mosquitto
