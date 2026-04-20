#!/bin/bash

set -e  # Остановка при ошибках

ensure_line_in_file() {
    local line="$1"
    local file="$2"
    if ! grep -Fxq "$line" "$file" 2>/dev/null; then
        echo "$line" | sudo tee -a "$file" >/dev/null
    fi
}

echo "Обновление системы и установка зависимостей..."
apt-get update
apt-get install -y mosquitto mosquitto-clients redis-server redis-tools postgresql postgresql-contrib openssl gpg curl

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
-- ChirpStack v4 использует единую БД вместо раздельных в v3
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chirpstack') THEN
        CREATE ROLE chirpstack LOGIN PASSWORD 'chirpstack';
    END IF;
END
\$\$;
SELECT 'CREATE DATABASE chirpstack OWNER chirpstack'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'chirpstack')\gexec
\\c chirpstack
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
EOF

echo "Установка ChirpStack v4 из локальных .deb файлов..."
# ВАЖНО: Для v4 нужны только два пакета:
# • chirpstack_4.x.x_amd64.deb (объединяет NS+AS+API)
# • chirpstack-gateway-bridge_4.x.x_amd64.deb (для шлюзов)
dpkg -i chirpstack-gateway-bridge_*.deb
dpkg -i chirpstack_*.deb

echo "Конфигурация chirpstack-gateway-bridge..."
GB_TOML="/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml"
[ -f "$GB_TOML" ] && cp "$GB_TOML" "${GB_TOML}.backup.$(date +%Y%m%d_%H%M%S)"

# Базовые настройки логирования и MQTT тем для RU864
sudo sed -i 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=2/' "$GB_TOML"
sudo sed -i 's/^[[:space:]]*log_to_syslog[[:space:]]*=.*/log_to_syslog=true/' "$GB_TOML"
sudo sed -i 's|event_topic_template="[^"]*"|event_topic_template="ru864/gateway/{{ .GatewayID }}/event/{{ .EventType }}"|' "$GB_TOML"
sudo sed -i 's|command_topic_template="[^"]*"|command_topic_template="ru864/gateway/{{ .GatewayID }}/command/#"|' "$GB_TOML"
sudo sed -i 's|state_topic_template="[^"]*"|state_topic_template="ru864/gateway/{{ .GatewayID }}/state/{{ .StateType }}"|' "$GB_TOML"
sudo sed -i 's|server = "tcp://[^"]*"|server = "tcp://localhost:1883"|' "$GB_TOML"

echo "Конфигурация ChirpStack v4 (основной файл)..."
TOML="/etc/chirpstack/chirpstack.toml"
[ -f "$TOML" ] && cp "$TOML" "${TOML}.backup.$(date +%Y%m%d_%H%M%S)"

# [general] секция
sudo sed -i 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=2/' "$TOML"
sudo sed -i 's/^[[:space:]]*log_to_syslog[[:space:]]*=.*/log_to_syslog=true/' "$TOML"

# PostgreSQL DSN (единая БД для v4)
sudo sed -i 's|dsn="[^"]*"|dsn="postgres://chirpstack:chirpstack@localhost/chirpstack?sslmode=disable"|' "$TOML"

# Secret key для JWT
SECRET=$(openssl rand -base64 32)
sudo sed -i "s|secret = \"[^\"]*\"|secret = \"$SECRET\"|" "$TOML"

# API bind (разрешаем внешние подключения)
sudo sed -i 's/bind = "127.0.0.1:8080"/bind = "0.0.0.0:8080"/' "$TOML"

# MQTT integration
sudo sed -i 's|server = "tcp://[^"]*"|server = "tcp://localhost:1883"|' "$TOML"
sudo sed -i 's/json = false/json = true/' "$TOML"

# Включаем только RU864 регион
sudo sed -i '/enabled_regions = \[/,/\]/c\enabled_regions = [\n  "ru864",\n]' "$TOML"

echo "Настройка региона RU864-870 для ChirpStack v4..."
REGION_FILE="/etc/chirpstack/region_ru864.toml"

# Создаём файл региона с нуля (в v4 регионы вынесены в отдельные файлы)
cat > "$REGION_FILE" << 'EOF'
[[regions]]
name = "ru864"
common_name = "RU864"

[regions.gateway]
force_gws_private = false

[regions.gateway.backend]
enabled = "mqtt"

[regions.gateway.backend.mqtt]
event_topic = "ru864/gateway/+/event/+"
command_topic = "ru864/gateway/{{ gateway_id }}/command/{{ command }}"
server = "tcp://localhost:1883"
clean_session = true

# Основные каналы RU864 (864.0 - 865.0 МГц, шаг 200 кГц)
[[regions.gateway.channels]]
frequency = 864000000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

[[regions.gateway.channels]]
frequency = 864200000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

[[regions.gateway.channels]]
frequency = 864400000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

[[regions.gateway.channels]]
frequency = 864600000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

[[regions.gateway.channels]]
frequency = 864800000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

[[regions.gateway.channels]]
frequency = 865000000
bandwidth = 125000
modulation = "LORA"
spreading_factors = [7, 8, 9, 10, 11, 12]

# FSK канал (опционально, для совместимости)
[[regions.gateway.channels]]
frequency = 864000000
bandwidth = 125000
modulation = "FSK"
datarate = 50000

[regions.network]
installation_margin = 10
rx_window = 0
rx1_delay = 1
rx1_dr_offset = 0
rx2_dr = 0
rx2_frequency = 869000000
downlink_tx_power = 20
adr_disabled = false
min_dr = 0
max_dr = 7

# Дополнительные каналы RU864 (промежуточные частоты)
[[regions.network.extra_channels]]
frequency = 864100000
min_dr = 0
max_dr = 7

[[regions.network.extra_channels]]
frequency = 864300000
min_dr = 0
max_dr = 7

[[regions.network.extra_channels]]
frequency = 864500000
min_dr = 0
max_dr = 7

[[regions.network.extra_channels]]
frequency = 864700000
min_dr = 0
max_dr = 7

[[regions.network.extra_channels]]
frequency = 864900000
min_dr = 0
max_dr = 7
EOF

echo "Настройка Mosquitto..."
MOSQUITTO_CONF="/etc/mosquitto/mosquitto.conf"
ensure_line_in_file "listener 1883" "$MOSQUITTO_CONF"
ensure_line_in_file "allow_anonymous true" "$MOSQUITTO_CONF"

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

echo "Включение и запуск сервисов ChirpStack v4..."
# В v4: chirpstack (основной) + chirpstack-gateway-bridge (для шлюзов)
systemctl enable chirpstack chirpstack-gateway-bridge mosquitto redis-server postgresql
systemctl start chirpstack chirpstack-gateway-bridge mosquitto redis-server

echo "Установка завершена!"

