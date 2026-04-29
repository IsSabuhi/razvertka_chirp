#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
DIR_V3="${2:-}"
DIR_V4="${3:-}"
ARCH_SUBDIR="${4:-}"

if [[ "$VERSION" != "v3" && "$VERSION" != "v4" ]]; then
  echo "Ошибка: usage install-chirpstack.sh v3|v4 <DIR_V3_BASE> <DIR_V4_BASE> <amd|arm>" >&2
  exit 1
fi

if [[ "$VERSION" == "v3" ]]; then
  shopt -s nullglob
  GWB=( "${DIR_V3}/${ARCH_SUBDIR}"/chirpstack-gateway-bridge_*.deb )
  NS=( "${DIR_V3}/${ARCH_SUBDIR}"/chirpstack-network-server_*.deb )
  AS=( "${DIR_V3}/${ARCH_SUBDIR}"/chirpstack-application-server_*.deb )
  shopt -u nullglob
  [[ ${#GWB[@]} -ge 1 && ${#NS[@]} -ge 1 && ${#AS[@]} -ge 1 ]] || {
    echo "Ошибка: не найдены .deb пакеты ChirpStack v3 в ${DIR_V3}/${ARCH_SUBDIR}" >&2
    exit 1
  }
  echo ">>> Установка ChirpStack v3 (только пакеты)..."
  dpkg -i "${GWB[@]}"
  dpkg -i "${NS[@]}"
  dpkg -i "${AS[@]}"

  echo ">>> Настройка конфигурации ChirpStack v3..."
  NS_TOML="/etc/chirpstack-network-server/chirpstack-network-server.toml"
  AS_TOML="/etc/chirpstack-application-server/chirpstack-application-server.toml"
  GB_TOML="/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml"

  if [[ -f "$GB_TOML" ]]; then
    sed -i 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=2/' "$GB_TOML"
    sed -i 's/^[[:space:]]*log_to_syslog[[:space:]]*=.*/log_to_syslog=true/' "$GB_TOML"
    sed -i 's/marshaler="[^"]*"/marshaler="json"/' "$GB_TOML"
  fi

  if [[ -f "$NS_TOML" ]]; then
    sed -i 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=2/' "$NS_TOML"
    sed -i 's/^[[:space:]]*log_to_syslog[[:space:]]*=.*/log_to_syslog=true/' "$NS_TOML"
    sed -i 's|dsn[[:space:]]*=[[:space:]]*"[^"]*"|dsn="postgres://lora_ns:lora_ns@localhost/lora_ns?sslmode=disable"|' "$NS_TOML"
  fi
  if [[ -f "$AS_TOML" ]]; then
    sed -i 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=2/' "$AS_TOML"
    sed -i 's/^[[:space:]]*log_to_syslog[[:space:]]*=.*/log_to_syslog=true/' "$AS_TOML"
    sed -i 's/marshaler="[^"]*"/marshaler="json"/' "$AS_TOML"
    sed -i 's|dsn[[:space:]]*=[[:space:]]*"[^"]*"|dsn="postgres://lora_as:lora_as@localhost/lora_as?sslmode=disable"|' "$AS_TOML"
    if command -v openssl >/dev/null 2>&1; then
      JWT_SECRET="$(openssl rand -base64 32 | tr -d '\n')"
      if grep -Eq '^[[:space:]]*jwt_secret[[:space:]]*=' "$AS_TOML"; then
        sed -i "s|^[[:space:]]*jwt_secret[[:space:]]*=.*|jwt_secret=\"${JWT_SECRET}\"|" "$AS_TOML"
      else
        # Для v3 jwt_secret должен быть в секции external_api.
        if grep -Eq '^[[:space:]]*\[application_server\.external_api\]' "$AS_TOML"; then
          sed -i "/^[[:space:]]*\[application_server\.external_api\]/a jwt_secret=\"${JWT_SECRET}\"" "$AS_TOML"
        else
          printf '\n[application_server.external_api]\njwt_secret="%s"\n' "$JWT_SECRET" >> "$AS_TOML"
        fi
      fi
    fi
  fi

  MOSQUITTO_CONF="/etc/mosquitto/mosquitto.conf"
  if [[ -f "$MOSQUITTO_CONF" ]]; then
    grep -Fxq "listener 1883" "$MOSQUITTO_CONF" || echo "listener 1883" >> "$MOSQUITTO_CONF"
    grep -Fxq "allow_anonymous true" "$MOSQUITTO_CONF" || echo "allow_anonymous true" >> "$MOSQUITTO_CONF"
  fi

  systemctl enable mosquitto redis-server postgresql
  systemctl restart mosquitto redis-server
  systemctl enable chirpstack-gateway-bridge chirpstack-network-server chirpstack-application-server
  systemctl restart chirpstack-gateway-bridge chirpstack-network-server chirpstack-application-server
else
  shopt -s nullglob
  GWB=( "${DIR_V4}/${ARCH_SUBDIR}"/chirpstack-gateway-bridge_*.deb )
  CS=( "${DIR_V4}/${ARCH_SUBDIR}"/chirpstack_*.deb )
  shopt -u nullglob
  [[ ${#GWB[@]} -ge 1 && ${#CS[@]} -ge 1 ]] || {
    echo "Ошибка: не найдены .deb пакеты ChirpStack v4 в ${DIR_V4}/${ARCH_SUBDIR}" >&2
    exit 1
  }
  echo ">>> Установка ChirpStack v4 (только пакеты)..."
  dpkg -i "${GWB[@]}"
  dpkg -i "${CS[@]}"
  systemctl enable chirpstack-gateway-bridge chirpstack
  systemctl restart chirpstack-gateway-bridge chirpstack
fi
