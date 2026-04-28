#!/usr/bin/env bash
set -euo pipefail

echo ">>> Установка зависимостей (mosquitto, redis, postgresql, openssl)..."
apt-get update
apt-get install -y mosquitto mosquitto-clients redis-server redis-tools postgresql postgresql-contrib openssl
