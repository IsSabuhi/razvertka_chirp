# shellcheck shell=bash
# razvertka-status.sh — --status / пункт меню
# Одна строка: пакет dpkg + версия или «нет».
print_pkg_status_line() {
  local pkg="${1:?}" label="${2:-$1}"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    local ver
    ver="$(dpkg -s "$pkg" 2>/dev/null | sed -n 's/^Version: //p' | head -1)"
    echo "  $label: установлен (версия: $ver)"
  else
    echo "  $label: нет"
  fi
}

# Состояние unit-файла
systemd_unit_state() {
  local u="${1:?}"
  if ! systemctl cat "$u" &>/dev/null && ! systemctl cat "${u}.service" &>/dev/null; then
    echo "  $u: — (нет unit)"
    return
  fi
  local st en
  st="$(systemctl is-active "$u" 2>&1 | head -1 | tr -d '\r')"
  en="$(systemctl is-enabled "$u" 2>&1 | head -1 | tr -d '\r')"
  echo "  $u: $st | $en"
}

# Обзор: пакеты, сервисы, БД.
show_install_status() {
  local cs
  cs="$(detect_installed_chirpstack)"
  echo "=== Установленные компоненты (razvertka) ==="
  echo
  echo "--- ChirpStack (ветка по пакетам) ---"
  case "$cs" in
    v3) echo "  Детекция: v3 (установлен chirpstack-network-server)" ;;
    v4) echo "  Детекция: v4 (установлен пакет chirpstack)" ;;
    *) echo "  Детекция: пакеты ChirpStack v3/v4 не найдены" ;;
  esac
  print_pkg_status_line chirpstack-network-server
  print_pkg_status_line chirpstack-application-server
  print_pkg_status_line chirpstack
  print_pkg_status_line chirpstack-gateway-bridge
  if [[ "$cs" == "v4" ]] && command -v chirpstack >/dev/null 2>&1; then
    echo "  Бинарь chirpstack: $(chirpstack --version 2>/dev/null | head -1 | tr -d '\r' || echo '?')"
  fi
  echo
  echo "--- Сопутствующие пакеты ---"
  print_pkg_status_line zabbix-agent2
  print_pkg_status_line mosquitto
  print_pkg_status_line mosquitto-clients
  print_pkg_status_line redis-server
  print_pkg_status_line redis-tools
  if dpkg -s postgresql >/dev/null 2>&1; then
    print_pkg_status_line postgresql
  else
    local pgpkg=""
    pgpkg="$(dpkg -l 'postgresql-[0-9]*' 2>/dev/null | awk '/^ii/ {print $2; exit}')"
    if [[ -n "$pgpkg" ]]; then
      print_pkg_status_line "$pgpkg" "postgresql (сервер, $pgpkg)"
    else
      echo "  postgresql: нет (ожидается postgresql или postgresql-NN)"
    fi
  fi
  echo
  echo "--- Сервисы (active / enabled) ---"
  systemd_unit_state chirpstack
  systemd_unit_state chirpstack-gateway-bridge
  systemd_unit_state chirpstack-network-server
  systemd_unit_state chirpstack-application-server
  systemd_unit_state zabbix-agent2
  systemd_unit_state mosquitto
  systemd_unit_state redis-server
  systemd_unit_state postgresql
  echo
  echo "--- БД PostgreSQL (lora_as, lora_ns, chirpstack) ---"
  if sudo -u postgres psql -d postgres -c "SELECT 1" >/dev/null 2>&1; then
    for db in lora_as lora_ns chirpstack; do
      if postgres_db_exists "$db"; then
        echo "  $db: есть"
      else
        echo "  $db: нет"
      fi
    done
  else
    echo "  (нет доступа к PostgreSQL от postgres или кластер не поднят)"
  fi
  echo
  echo "=== конец ==="
}
