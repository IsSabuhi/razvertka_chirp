#!/usr/bin/env bash
# Единая точка входа для развёртывания ChirpStack + Zabbix Agent2.
# Запуск: sudo ./install.sh  (из каталога репозитория или по полному пути)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_V3="${SCRIPT_DIR}/chirpstackv3&zabbix - install"
DIR_V4="${SCRIPT_DIR}/chirpstackv4&zabbix - install"
BACKUP_DIR_DEFAULT="/var/backups/chirpstack-migration"

die() {
  echo "Ошибка: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "Запустите скрипт от root: sudo $0"
}

check_v3_packages() {
  local ok=1
  shopt -s nullglob
  local gwb=( "${DIR_V3}"/chirpstack-gateway-bridge_*.deb )
  local ns=( "${DIR_V3}"/chirpstack-network-server_*.deb )
  local as=( "${DIR_V3}"/chirpstack-application-server_*.deb )
  local zab=( "${DIR_V3}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: chirpstack-gateway-bridge_*.deb"; ok=0; }
  [[ ${#ns[@]} -ge 1 ]]  || { echo "  Нет: chirpstack-network-server_*.deb"; ok=0; }
  [[ ${#as[@]} -ge 1 ]]  || { echo "  Нет: chirpstack-application-server_*.deb"; ok=0; }
  [[ ${#zab[@]} -ge 1 ]] || { echo "  Нет: zabbix-agent2_*.deb"; ok=0; }
  return "$ok"
}

check_v4_packages() {
  local ok=1
  shopt -s nullglob
  local gwb=( "${DIR_V4}"/chirpstack-gateway-bridge_*.deb )
  local cs=( "${DIR_V4}"/chirpstack_*.deb )
  local zab=( "${DIR_V4}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: chirpstack-gateway-bridge_*.deb"; ok=0; }
  [[ ${#cs[@]} -ge 1 ]]  || { echo "  Нет: chirpstack_*.deb"; ok=0; }
  [[ ${#zab[@]} -ge 1 ]] || { echo "  Нет: zabbix-agent2_*.deb"; ok=0; }
  return "$ok"
}

run_v3() {
  [[ -d "$DIR_V3" ]] || die "Каталог не найден: $DIR_V3"
  echo "Проверка .deb в: $DIR_V3"
  if ! check_v3_packages; then
    die "Положите недостающие пакеты в каталог выше и повторите."
  fi
  echo
  echo ">>> Запуск установки ChirpStack v3 (fast_razvertka.sh)..."
  ( cd "$DIR_V3" && bash ./fast_razvertka.sh )
}

run_v4() {
  [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
  echo "Проверка .deb в: $DIR_V4"
  if ! check_v4_packages; then
    die "Положите недостающие пакеты в каталог выше и повторите."
  fi
  echo
  echo ">>> Запуск установки ChirpStack v4 (fast_razvertkav4.sh)..."
  ( cd "$DIR_V4" && bash ./fast_razvertkav4.sh )
}

detect_installed_chirpstack() {
  if dpkg -l 2>/dev/null | awk '{print $2}' | rg -q '^chirpstack-network-server$'; then
    echo "v3"
    return 0
  fi
  if dpkg -l 2>/dev/null | awk '{print $2}' | rg -q '^chirpstack$'; then
    echo "v4"
    return 0
  fi
  echo "none"
}

backup_v3_databases() {
  local backup_dir="$1"
  mkdir -p "$backup_dir"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local as_dump="${backup_dir}/lora_as_${ts}.sql"
  local ns_dump="${backup_dir}/lora_ns_${ts}.sql"

  echo ">>> Делаем бэкап БД v3 в: $backup_dir"
  sudo -u postgres pg_dump lora_as >"$as_dump"
  sudo -u postgres pg_dump lora_ns >"$ns_dump"
  echo "Бэкап создан:"
  echo "  - $as_dump"
  echo "  - $ns_dump"
}

run_v3_to_v4_migration() {
  local dsn_v4="postgres://chirpstack:chirpstack@localhost/chirpstack?sslmode=disable"
  local dsn_as="postgres://lora_as:lora_as@localhost/lora_as?sslmode=disable"
  local dsn_ns="postgres://lora_ns:lora_ns@localhost/lora_ns?sslmode=disable"

  command -v chirpstack >/dev/null 2>&1 || die "Команда 'chirpstack' не найдена после установки v4."

  echo ">>> Запуск миграции данных v3 -> v4"
  echo "DSN v4 : $dsn_v4"
  echo "DSN AS : $dsn_as"
  echo "DSN NS : $dsn_ns"

  # Поддерживаем наиболее частые варианты CLI между сборками.
  if chirpstack migrate from-v3 \
    --postgres-dsn "$dsn_v4" \
    --application-server-dsn "$dsn_as" \
    --network-server-dsn "$dsn_ns"; then
    return 0
  fi

  if chirpstack migrate \
    --postgres-dsn "$dsn_v4" \
    --application-server-dsn "$dsn_as" \
    --network-server-dsn "$dsn_ns"; then
    return 0
  fi

  die "Не удалось автоматически выполнить миграцию.
Проверьте формат команды в вашей версии: chirpstack --help / chirpstack migrate --help
Бэкап БД уже сохранён, можно повторить миграцию вручную."
}

upgrade_v3_to_v4() {
  [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
  echo "Проверка .deb для обновления в: $DIR_V4"
  if ! check_v4_packages; then
    die "Положите недостающие v4-пакеты в каталог выше и повторите."
  fi

  local detected
  detected="$(detect_installed_chirpstack)"
  if [[ "$detected" != "v3" ]]; then
    die "Сценарий обновления применим только при установленном ChirpStack v3 (обнаружено: $detected)."
  fi

  read -r -p "Каталог для бэкапов БД [${BACKUP_DIR_DEFAULT}]: " backup_dir
  backup_dir="${backup_dir:-$BACKUP_DIR_DEFAULT}"

  echo ">>> Останавливаем сервисы v3 перед миграцией"
  systemctl stop chirpstack-network-server chirpstack-application-server chirpstack-gateway-bridge || true

  backup_v3_databases "$backup_dir"

  echo ">>> Устанавливаем/обновляем до ChirpStack v4"
  ( cd "$DIR_V4" && bash ./fast_razvertkav4.sh )

  run_v3_to_v4_migration

  echo ">>> Обновление и миграция v3 -> v4 завершены."
}

ask_yes_no() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N]: " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

purge_if_installed() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get purge -y "$pkg"
  fi
}

remove_stack() {
  echo "ВНИМАНИЕ: этот режим удаляет ChirpStack и Zabbix Agent2."
  if ! ask_yes_no "Продолжить удаление?"; then
    echo "Удаление отменено."
    return 0
  fi

  echo ">>> Остановка сервисов"
  systemctl stop \
    chirpstack \
    chirpstack-network-server \
    chirpstack-application-server \
    chirpstack-gateway-bridge \
    zabbix-agent2 \
    mosquitto \
    redis-server 2>/dev/null || true

  echo ">>> Удаляем пакеты ChirpStack и Zabbix Agent2"
  local app_pkgs=(
    chirpstack
    chirpstack-network-server
    chirpstack-application-server
    chirpstack-gateway-bridge
    zabbix-agent2
  )
  local pkg
  for pkg in "${app_pkgs[@]}"; do
    purge_if_installed "$pkg"
  done

  if ask_yes_no "Удалить также Mosquitto/Redis?"; then
    for pkg in mosquitto mosquitto-clients redis-server redis-tools; do
      purge_if_installed "$pkg"
    done
  fi

  if ask_yes_no "Удалить БД ChirpStack (chirpstack, lora_as, lora_ns) и роли?"; then
    echo ">>> Удаляем БД и роли PostgreSQL (если существуют)"
    sudo -u postgres psql <<'EOF'
DROP DATABASE IF EXISTS chirpstack;
DROP DATABASE IF EXISTS lora_as;
DROP DATABASE IF EXISTS lora_ns;
DROP ROLE IF EXISTS chirpstack;
DROP ROLE IF EXISTS lora_as;
DROP ROLE IF EXISTS lora_ns;
EOF
  fi

  if ask_yes_no "Удалить остаточные каталоги /etc/chirpstack* и /var/lib/chirpstack*?"; then
    rm -rf /etc/chirpstack /etc/chirpstack-network-server /etc/chirpstack-application-server /etc/chirpstack-gateway-bridge
    rm -rf /var/lib/chirpstack /var/lib/chirpstack-network-server /var/lib/chirpstack-application-server /var/lib/chirpstack-gateway-bridge
  fi

  echo ">>> Удаление завершено."
}

show_menu() {
  cat << 'EOF'

razvertka — установка стека LoRaWAN (ChirpStack + Zabbix Agent2)
Конфиги Zabbix: zabbix_agent2.conf в соответствующем подкаталоге.
Сервис LoraMes и пути в unit-файле здесь не меняются.

EOF
}

main() {
  need_root
  show_menu

  PS3="Введите номер пункта и нажмите Enter: "
  local options=(
    "ChirpStack v3 + зависимости + Zabbix Agent2"
    "ChirpStack v4 + зависимости + Zabbix Agent2"
    "Обновление v3 -> v4 + миграция"
    "Удаление (ChirpStack/Zabbix, опционально БД и данные)"
    "Выход"
  )
  select _ in "${options[@]}"; do
    case $REPLY in
      1)
        run_v3
        break
        ;;
      2)
        run_v4
        break
        ;;
      3)
        upgrade_v3_to_v4
        break
        ;;
      4)
        remove_stack
        break
        ;;
      5)
        echo "Выход."
        exit 0
        ;;
      *)
        echo "Неверный выбор: $REPLY"
        ;;
    esac
  done
}

main "$@"
