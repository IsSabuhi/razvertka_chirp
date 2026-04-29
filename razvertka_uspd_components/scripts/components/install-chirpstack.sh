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

  echo ">>> Настройка DSN для ChirpStack v3 (lora_ns / lora_as)..."
  NS_TOML="/etc/chirpstack-network-server/chirpstack-network-server.toml"
  AS_TOML="/etc/chirpstack-application-server/chirpstack-application-server.toml"
  if [[ -f "$NS_TOML" ]]; then
    sed -i 's|dsn[[:space:]]*=[[:space:]]*"[^"]*"|dsn="postgres://lora_ns:lora_ns@localhost/lora_ns?sslmode=disable"|' "$NS_TOML"
  fi
  if [[ -f "$AS_TOML" ]]; then
    sed -i 's|dsn[[:space:]]*=[[:space:]]*"[^"]*"|dsn="postgres://lora_as:lora_as@localhost/lora_as?sslmode=disable"|' "$AS_TOML"
    if command -v openssl >/dev/null 2>&1; then
      JWT_SECRET="$(openssl rand -base64 32 | tr -d '\n')"
      if rg -n '^[[:space:]]*jwt_secret[[:space:]]*=' "$AS_TOML" >/dev/null 2>&1; then
        sed -i "s|^[[:space:]]*jwt_secret[[:space:]]*=.*|jwt_secret=\"${JWT_SECRET}\"|" "$AS_TOML"
      else
        printf '\njwt_secret="%s"\n' "$JWT_SECRET" >> "$AS_TOML"
      fi
    fi
  fi

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
