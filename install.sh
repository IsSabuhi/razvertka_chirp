#!/usr/bin/env bash
# Единая точка входа для развёртывания ChirpStack + Zabbix Agent2.
# Запуск: sudo ./install.sh  (из каталога репозитория или по полному пути)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_V3="${SCRIPT_DIR}/chirpstackv3&zabbix_install"
DIR_V4="${SCRIPT_DIR}/chirpstackv4&zabbix_install"
# Ядро ChirpStack 4.11.x для миграции v3→v4 (отдельно от amd/arm с «текущей» v4).
DIR_V411="${SCRIPT_DIR}/chirpstackv4.11.1_install"
BACKUP_DIR_DEFAULT="/var/backups/chirpstack-migration"
ARCH_OVERRIDE=""
ACTION=""
AUTO_YES=0
BACKUP_DIR_OVERRIDE=""

die() {
  echo "Ошибка: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "Запустите скрипт от root: sudo $0"
}

check_v3_packages() {
  local ok=0
  shopt -s nullglob
  local gwb=( "${DIR_V3}"/chirpstack-gateway-bridge_*.deb )
  local ns=( "${DIR_V3}"/chirpstack-network-server_*.deb )
  local as=( "${DIR_V3}"/chirpstack-application-server_*.deb )
  local zab=( "${DIR_V3}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#ns[@]} -ge 1 ]]  || { echo "  Нет: chirpstack-network-server_*.deb"; ok=1; }
  [[ ${#as[@]} -ge 1 ]]  || { echo "  Нет: chirpstack-application-server_*.deb"; ok=1; }
  [[ ${#zab[@]} -ge 1 ]] || { echo "  Нет: zabbix-agent2_*.deb"; ok=1; }
  return "$ok"
}

# $1 — подкаталог с .deb для ChirpStack: amd или arm (без копирования в корень).
check_v4_packages() {
  local sub="${1:?}"
  local p="${DIR_V4}/${sub}"
  local ok=0
  [[ -d "$p" ]] || { echo "  Нет каталога: $p"; return 1; }
  shopt -s nullglob
  local gwb=( "${p}"/chirpstack-gateway-bridge_*.deb )
  local cs=( "${p}"/chirpstack_*.deb )
  local zab_root=( "${DIR_V4}"/zabbix-agent2_*.deb )
  local zab_sub=( "${p}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: ${sub}/chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#cs[@]} -ge 1 ]]  || { echo "  Нет: ${sub}/chirpstack_*.deb"; ok=1; }
  if [[ ${#zab_root[@]} -ge 1 ]] || [[ ${#zab_sub[@]} -ge 1 ]]; then
    :
  else
    echo "  Нет: zabbix-agent2_*.deb (в корне v4 или в ${sub}/)"
    ok=1
  fi
  return "$ok"
}

detect_host_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unknown" ;;
  esac
}

choose_arch() {
  if [[ -n "$ARCH_OVERRIDE" ]]; then
    case "$ARCH_OVERRIDE" in
      amd64|arm64)
        echo "$ARCH_OVERRIDE"
        return 0
        ;;
      auto)
        ARCH_OVERRIDE="$(detect_host_arch)"
        [[ "$ARCH_OVERRIDE" == "unknown" ]] && die "Не удалось определить архитектуру хоста автоматически."
        echo "$ARCH_OVERRIDE"
        return 0
        ;;
      *)
        die "Неверное значение --arch: $ARCH_OVERRIDE (допустимо: auto|amd64|arm64)"
        ;;
    esac
  fi

  local default_arch
  default_arch="$(detect_host_arch)"
  local answer
  echo "Выбор архитектуры пакетов:" >&2
  echo "  1) auto (${default_arch})" >&2
  echo "  2) amd64" >&2
  echo "  3) arm64" >&2
  read -r -p "Введите номер [1]: " answer
  answer="${answer:-1}"
  case "$answer" in
    1)
      [[ "$default_arch" == "unknown" ]] && die "Не удалось определить архитектуру хоста. Выберите amd64 или arm64 вручную."
      echo "$default_arch"
      ;;
    2) echo "amd64" ;;
    3) echo "arm64" ;;
    *) die "Неверный выбор архитектуры: $answer" ;;
  esac
}

# Подкаталог с deb пакетами v4: amd или arm (chirpstackv4&zabbix_install/amd|arm).
v4_chirp_deb_subdir() {
  local arch
  arch="$(choose_arch)"
  case "$arch" in
    amd64) echo "amd" ;;
    arm64) echo "arm" ;;
    *) die "Неподдерживаемая архитектура для v4: $arch" ;;
  esac
}

prepare_v3_packages() {
  local arch src
  arch="$(choose_arch)"
  case "$arch" in
    amd64) src="${DIR_V3}/chirpv3x64" ;;
    arm64) src="${DIR_V3}/chirpv3ARM" ;;
    *) die "Неподдерживаемая архитектура для v3: $arch" ;;
  esac
  [[ -d "$src" ]] || die "Каталог с пакетами не найден: $src"
  echo ">>> Подготовка пакетов v3 из: $src"
  cp -f "${src}"/chirpstack-gateway-bridge_*.deb "$DIR_V3"/
  cp -f "${src}"/chirpstack-network-server_*.deb "$DIR_V3"/
  cp -f "${src}"/chirpstack-application-server_*.deb "$DIR_V3"/
}

# Миграция v3→4.11: bridge в DIR_V4/amd|arm, ядро chirpstack — в DIR_V411 (chirpstackv4.11.1_install).
check_v411_migration_packages() {
  local sub="${1:?}"
  local p="${DIR_V4}/${sub}"
  local ok=0
  [[ -d "$p" ]] || { echo "  Нет каталога: $p"; return 1; }
  [[ -d "$DIR_V411" ]] || { echo "  Нет каталога: $DIR_V411"; return 1; }
  shopt -s nullglob
  local gwb=( "${p}"/chirpstack-gateway-bridge_*.deb )
  local cs=()
  case "$sub" in
    amd) cs=( "${DIR_V411}"/chirpstack_*_linux_amd64.deb ) ;;
    arm) cs=( "${DIR_V411}"/chirpstack_*_linux_arm64.deb ) ;;
    *) echo "  Внутренняя ошибка: sub=$sub"; return 1 ;;
  esac
  local zab_root=( "${DIR_V4}"/zabbix-agent2_*.deb )
  local zab_sub=( "${p}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: ${sub}/chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#cs[@]} -ge 1 ]]  || {
    echo "  Нет пакета ядра в ${DIR_V411} (нужен chirpstack_*_linux_amd64.deb или chirpstack_*_linux_arm64.deb)"
    ok=1
  }
  if [[ ${#zab_root[@]} -ge 1 ]] || [[ ${#zab_sub[@]} -ge 1 ]]; then
    :
  else
    echo "  Нет: zabbix-agent2_*.deb (в корне v4 или в ${sub}/)"
    ok=1
  fi
  if [[ "$ok" -eq 0 ]]; then
    local f
    for f in "${cs[@]}"; do
      case "$f" in
        *4.11*) ;;
        *)
          echo "  Для миграции нужен пакет ядра 4.11.x (в имени должно быть 4.11): $f"
          ok=1
          ;;
      esac
    done
  fi
  return "$ok"
}

chirpstack_dpkg_version() {
  if ! dpkg -s chirpstack >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  dpkg-query -W -f='${Version}' chirpstack 2>/dev/null || echo ""
}

run_v3() {
  [[ -d "$DIR_V3" ]] || die "Каталог не найден: $DIR_V3"
  prepare_v3_packages
  echo "Проверка .deb в: $DIR_V3"
  if ! check_v3_packages; then
    die "Не найдены обязательные .deb в каталоге установки v3."
  fi
  echo
  echo ">>> Запуск установки ChirpStack v3 (fast_razvertka.sh)..."
  ( cd "$DIR_V3" && bash ./fast_razvertka.sh )
}

run_v4() {
  [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
  local deb_sub
  deb_sub="$(v4_chirp_deb_subdir)"
  echo "Проверка .deb в: ${DIR_V4}/${deb_sub} (zabbix — в корне v4 или в ${deb_sub}/)"
  if ! check_v4_packages "$deb_sub"; then
    die "Не найдены обязательные .deb для v4."
  fi
  echo
  echo ">>> Запуск установки ChirpStack v4 (fast_razvertkav4.sh, CHIRPSTACK_DEB_DIR=${deb_sub})..."
  ( cd "$DIR_V4" && CHIRPSTACK_DEB_DIR="$deb_sub" bash ./fast_razvertkav4.sh )
}

detect_installed_chirpstack() {
  if dpkg -s chirpstack-network-server >/dev/null 2>&1; then
    echo "v3"
    return 0
  fi
  if dpkg -s chirpstack >/dev/null 2>&1; then
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
  local migrator=""
  local cs_version_output=""
  local cs_major=""
  local cs_minor=""

  command -v chirpstack >/dev/null 2>&1 || die "Команда 'chirpstack' не найдена после установки v4."

  cs_version_output="$(chirpstack --version 2>/dev/null || true)"
  if [[ "$cs_version_output" =~ ([0-9]+)\.([0-9]+)\.[0-9]+ ]]; then
    cs_major="${BASH_REMATCH[1]}"
    cs_minor="${BASH_REMATCH[2]}"
  fi

  if [[ "$cs_major" != "4" || "$cs_minor" != "11" ]]; then
    die "Для миграции v3 -> v4 требуется ChirpStack 4.11.x.
Сейчас установлено: ${cs_version_output:-не удалось определить версию}.
Положите в архитектурную папку пакет chirpstack 4.11.x, выполните миграцию, затем обновитесь до актуальной v4."
  fi

  if command -v chirpstack-v3-to-v4 >/dev/null 2>&1; then
    migrator="chirpstack-v3-to-v4"
  elif [[ -x "${SCRIPT_DIR}/tools/chirpstack-v3-to-v4" ]]; then
    migrator="${SCRIPT_DIR}/tools/chirpstack-v3-to-v4"
  else
    die "Не найден инструмент миграции chirpstack-v3-to-v4.
Установите/положите бинарник в PATH или в ${SCRIPT_DIR}/tools/chirpstack-v3-to-v4"
  fi

  echo ">>> Запуск миграции данных v3 -> v4 через: $migrator"
  "$migrator" \
    --as-config-file /etc/chirpstack-application-server/chirpstack-application-server.toml \
    --ns-config-file /etc/chirpstack-network-server/chirpstack-network-server.toml \
    --cs-config-file /etc/chirpstack/chirpstack.toml
}

upgrade_v3_to_v4() {
  [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
  [[ -d "$DIR_V411" ]] || die "Каталог не найден: $DIR_V411 (ядро ChirpStack 4.11 для миграции)."

  local detected
  detected="$(detect_installed_chirpstack)"
  if [[ "$detected" != "v3" ]]; then
    die "Сценарий миграции v3 -> 4.11 применим только при установленном ChirpStack v3 (обнаружено: $detected)."
  fi

  local cs_ver
  cs_ver="$(chirpstack_dpkg_version)"
  if [[ -n "$cs_ver" ]] && [[ ! "$cs_ver" =~ ^4\.11\. ]]; then
    die "Уже установлен пакет chirpstack версии «$cs_ver».
Для этого сценария нужна только 4.11.x. Удалите или замените пакет chirpstack вручную, затем повторите."
  fi

  local deb_sub
  deb_sub="$(v4_chirp_deb_subdir)"
  echo "Проверка пакетов миграции (ChirpStack 4.11.x) в: ${DIR_V4}/${deb_sub}"
  if ! check_v411_migration_packages "$deb_sub"; then
    die "Проверьте пакеты: gateway в ${DIR_V4}/${deb_sub}/, ядро 4.11 в ${DIR_V411}/, zabbix в корне v4 или в ${deb_sub}/."
  fi

  if [[ -n "$BACKUP_DIR_OVERRIDE" ]]; then
    backup_dir="$BACKUP_DIR_OVERRIDE"
    echo "Каталог для бэкапов БД: $backup_dir"
  else
    read -r -p "Каталог для бэкапов БД [${BACKUP_DIR_DEFAULT}]: " backup_dir
    backup_dir="${backup_dir:-$BACKUP_DIR_DEFAULT}"
  fi

  echo ">>> Останавливаем сервисы v3 перед миграцией"
  systemctl stop chirpstack-network-server chirpstack-application-server chirpstack-gateway-bridge || true

  backup_v3_databases "$backup_dir"

  cs_ver="$(chirpstack_dpkg_version)"
  if [[ -z "$cs_ver" ]] || [[ ! "$cs_ver" =~ ^4\.11\. ]]; then
    echo ">>> Установка ChirpStack 4.11 и окружения (bridge из ${deb_sub}/, ядро из chirpstackv4.11.1_install/)..."
    (
      cd "$DIR_V4" && \
        CHIRPSTACK_GATEWAY_DEB_DIR="$deb_sub" \
        CHIRPSTACK_CORE_DEB_DIR="$DIR_V411" \
        bash ./fast_razvertkav4.sh
    )
  else
    echo ">>> ChirpStack 4.11.x уже установлен ($cs_ver), шаг fast_razvertkav4.sh пропущен."
  fi

  run_v3_to_v4_migration

  echo ">>> Миграция v3 -> ChirpStack 4.11 завершена."
}

ask_yes_no() {
  local prompt="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    echo "$prompt [y/N]: y"
    return 0
  fi
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
  echo "ВНИМАНИЕ: этот режим удаляет выбранные компоненты."
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

  if ask_yes_no "Удалить пакет chirpstack (v4 core)?"; then
    purge_if_installed "chirpstack"
  fi
  if ask_yes_no "Удалить пакет chirpstack-network-server (v3)?"; then
    purge_if_installed "chirpstack-network-server"
  fi
  if ask_yes_no "Удалить пакет chirpstack-application-server (v3)?"; then
    purge_if_installed "chirpstack-application-server"
  fi
  if ask_yes_no "Удалить пакет chirpstack-gateway-bridge?"; then
    purge_if_installed "chirpstack-gateway-bridge"
  fi
  if ask_yes_no "Удалить пакет zabbix-agent2?"; then
    purge_if_installed "zabbix-agent2"
  fi
  if ask_yes_no "Удалить пакет mosquitto?"; then
    purge_if_installed "mosquitto"
  fi
  if ask_yes_no "Удалить пакет mosquitto-clients?"; then
    purge_if_installed "mosquitto-clients"
  fi
  if ask_yes_no "Удалить пакет redis-server?"; then
    purge_if_installed "redis-server"
  fi
  if ask_yes_no "Удалить пакет redis-tools?"; then
    purge_if_installed "redis-tools"
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

  if ask_yes_no "Удалить остаточные каталоги ChirpStack (/etc/chirpstack* и /var/lib/chirpstack*)?"; then
    rm -rf /etc/chirpstack /etc/chirpstack-network-server /etc/chirpstack-application-server /etc/chirpstack-gateway-bridge
    rm -rf /var/lib/chirpstack /var/lib/chirpstack-network-server /var/lib/chirpstack-application-server /var/lib/chirpstack-gateway-bridge
  fi
  if ask_yes_no "Удалить конфиг/логи Zabbix Agent2 (/etc/zabbix и /var/log/zabbix)?"; then
    rm -rf /etc/zabbix /var/log/zabbix
  fi
  if ask_yes_no "Удалить конфиги/данные Mosquitto (/etc/mosquitto и /var/lib/mosquitto)?"; then
    rm -rf /etc/mosquitto /var/lib/mosquitto
  fi
  if ask_yes_no "Удалить данные Redis (/var/lib/redis и /etc/redis)?"; then
    rm -rf /var/lib/redis /etc/redis
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

show_help() {
  cat <<'EOF'
Использование:
  sudo ./install.sh [опции]

Режимы:
  --v3           Установка ChirpStack v3
  --v4           Установка ChirpStack v4
  --upgrade      Миграция v3 -> 4.11 (ядро: chirpstackv4.11.1_install/, bridge: amd|arm)
  --remove       Выборочное удаление компонентов

Опции:
  --arch VALUE   auto|amd64|arm64
  --backup-dir   Каталог для бэкапа БД (для --upgrade)
  --yes          Авто-ответ "yes" на вопросы подтверждения
  -h, --help     Показать справку

Примеры:
  sudo ./install.sh --v4 --arch amd64
  sudo ./install.sh --upgrade --arch arm64 --backup-dir /var/backups/chirpstack
  sudo ./install.sh --remove
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --v3|--v4|--upgrade|--remove)
        [[ -n "$ACTION" ]] && die "Укажите только один режим (--v3|--v4|--upgrade|--remove)."
        ACTION="${1#--}"
        shift
        ;;
      --arch)
        shift
        [[ $# -gt 0 ]] || die "После --arch нужно указать значение."
        ARCH_OVERRIDE="$1"
        shift
        ;;
      --backup-dir)
        shift
        [[ $# -gt 0 ]] || die "После --backup-dir нужно указать путь."
        BACKUP_DIR_OVERRIDE="$1"
        shift
        ;;
      --yes)
        AUTO_YES=1
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        die "Неизвестный аргумент: $1 (используйте --help)."
        ;;
    esac
  done
}

main() {
  need_root
  parse_args "$@"

  if [[ -n "$ACTION" ]]; then
    case "$ACTION" in
      v3) run_v3 ;;
      v4) run_v4 ;;
      upgrade) upgrade_v3_to_v4 ;;
      remove) remove_stack ;;
      *) die "Неизвестный режим: $ACTION" ;;
    esac
    exit 0
  fi

  show_menu

  PS3="Введите номер пункта и нажмите Enter: "
  local options=(
    "ChirpStack v3 + зависимости + Zabbix Agent2"
    "ChirpStack v4 + зависимости + Zabbix Agent2"
    "Миграция v3 -> ChirpStack 4.11 + данные"
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
