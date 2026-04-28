#!/usr/bin/env bash
set -euo pipefail

echo ">>> Установка и запуск Redis..."
apt-get update
apt-get install -y redis-server redis-tools
systemctl enable redis-server
systemctl restart redis-server
