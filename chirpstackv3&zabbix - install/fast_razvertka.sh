#!/bin/bash

set -e  # Остановка при ошибках

echo "Обновление системы и установка зависимостей..."
apt-get update
apt-get install -y mosquitto mosquitto-clients redis-server redis-tools postgresql openssl

echo "=== Настройка системы логирования ==="

# Проверка прав (на случай запуска без sudo)
if [[ $EUID -ne 0 ]]; then
    echo "Для настройки journald требуются права root"
    exit 1
fi

# --- journald ---
echo "→ Настройка journald..."
JOURNALD_CONF="/etc/systemd/journald.conf"
[ -f "$JOURNALD_CONF" ] && cp "$JOURNALD_CONF" "${JOURNALD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

cat > "$JOURNALD_CONF" << 'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=10G
SystemMaxFileSize=200M
MaxRetentionSec=6months
EOF

systemctl restart systemd-journald
journalctl --rotate
journalctl --vacuum-time=6months 2>/dev/null || true

# --- logrotate ---
echo "=== Настройка глобального logrotate ==="

LOGROTATE_CONF="/etc/logrotate.conf"

# Бэкап
[ -f "$LOGROTATE_CONF" ] && cp "$LOGROTATE_CONF" "${LOGROTATE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

# Проверяем, есть ли нужные глобальные директивы, и добавляем только отсутствующие
for directive in "weekly" "rotate 4" "compress" "delaycompress" "missingok" "notifempty" "create" "su root adm"; do
    if ! grep -q "^$directive" "$LOGROTATE_CONF" 2>/dev/null; then
        echo "→ Добавляем: $directive"
        echo "$directive" >> "$LOGROTATE_CONF"
    fi
done

# Убеждаемся, что есть включение /etc/logrotate.d/
if ! grep -q "^include /etc/logrotate.d" "$LOGROTATE_CONF" 2>/dev/null; then
    echo "include /etc/logrotate.d" >> "$LOGROTATE_CONF"
fi

echo "Логирование настроено"

echo "Настройка PostgreSQL..."
sudo -u postgres psql <<EOF
CREATE ROLE lora_ns LOGIN PASSWORD 'lora_ns';
CREATE DATABASE lora_ns OWNER lora_ns;
CREATE ROLE lora_as LOGIN PASSWORD 'lora_as';
CREATE DATABASE lora_as OWNER lora_as;
\\c lora_as
CREATE EXTENSION pg_trgm;
CREATE EXTENSION hstore;
EOF

echo "Установка ChirpStack из локальных .deb файлов..."
dpkg -i chirpstack-gateway-bridge_*.deb
dpkg -i chirpstack-network-server_*.deb
dpkg -i chirpstack-application-server_*.deb

echo "Конфигурация chirpstack-gateway-bridge..."
TOML="/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml"
sudo sed -i '0,/^$/{s/^$/[general]\nlog_level=2\nlog_to_syslog=true\n/}' "$TOML"
sudo sed -i 's/marshaler="[^"]*"/marshaler="json"/' "$TOML"

echo "Конфигурация chirpstack-network-server (RU864-870)..."
TOML="/etc/chirpstack-network-server/chirpstack-network-server.toml"
sudo sed -i '0,/^$/{s/^$/[general]\nlog_level=2\nlog_to_syslog=true\n/}' "$TOML"
sudo sed -i 's!dsn="[^"]*"!dsn="postgres://lora_ns:lora_ns@localhost/lora_ns?sslmode=disable"!' "$TOML"
sudo sed -i 's/name="EU868"/name="RU_864_870"/' "$TOML"
sudo sed -i 's/frequency=867/frequency=864/' "$TOML"
sudo sed -i '/net_id="000000"/a device_session_ttl="438000h0m0s"' "$TOML"
sudo sed -i '/\[network_server.network_settings\]/a \ \ \ \ downlink_tx_power=20' "$TOML"

echo "Конфигурация chirpstack-application-server..."
TOML="/etc/chirpstack-application-server/chirpstack-application-server.toml"
sudo sed -i '0,/^$/{s/^$/[general]\nlog_level=2\nlog_to_syslog=true\n/}' "$TOML"
sudo sed -i 's!dsn="[^"]*"!dsn="postgres://lora_as:lora_as@localhost/lora_as?sslmode=disable"!' "$TOML"
sudo sed -i 's/marshaler="[^"]*"/marshaler="json"/' "$TOML"
SECRET=$(openssl rand -base64 32)
sudo sed -i "s!jwt_secret=\"[^\"]*\"!jwt_secret=\"$SECRET\"!" "$TOML"

echo "Настройка Mosquitto..."
echo "listener 1883" | sudo tee -a /etc/mosquitto/mosquitto.conf
echo "allow_anonymous true" | sudo tee -a /etc/mosquitto/mosquitto.conf

echo "Установка Zabbix Agent2 из локального .deb..."
dpkg -i zabbix-agent2_6.4.9-1+debian12_amd64.deb
cp zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf
systemctl daemon-reload
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
echo "Zabbix Agent2 установлен. Лог:"
tail -f /var/log/zabbix/zabbix_agent2.log &
ZABBIX_PID=$!
sleep 5 
kill $ZABBIX_PID 2>/dev/null || true

echo "Включение и запуск сервисов ChirpStack..."
systemctl enable chirpstack-gateway-bridge chirpstack-network-server chirpstack-application-server mosquitto redis-server postgresql
systemctl start chirpstack-gateway-bridge chirpstack-network-server chirpstack-application-server mosquitto redis-server

echo "Установка завершена!"