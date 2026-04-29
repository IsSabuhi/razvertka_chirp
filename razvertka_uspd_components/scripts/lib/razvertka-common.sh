# shellcheck shell=bash
# razvertka-common.sh — пакеты, arch, postgres, ask; source из install.sh (уже заданы SCRIPT_DIR, DIR_V3, DIR_V4, ...).
die() {
  echo "Ошибка: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "Запустите скрипт от root: sudo $0"
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
check_v3_packages() {
  local sub="${1:?}"
  local p="${DIR_V3}/${sub}"
  local ok=0
  [[ -d "$p" ]] || { echo "  Нет каталога: $p"; return 1; }
  shopt -s nullglob
  local gwb=( "${p}"/chirpstack-gateway-bridge_*.deb )
  local ns=( "${p}"/chirpstack-network-server_*.deb )
  local as=( "${p}"/chirpstack-application-server_*.deb )
  local zab=( "${DIR_ZABBIX}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: ${sub}/chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#ns[@]} -ge 1 ]]  || { echo "  Нет: ${sub}/chirpstack-network-server_*.deb"; ok=1; }
  [[ ${#as[@]} -ge 1 ]]  || { echo "  Нет: ${sub}/chirpstack-application-server_*.deb"; ok=1; }
  [[ ${#zab[@]} -ge 1 ]] || { echo "  Нет: zabbix/zabbix-agent2_*.deb"; ok=1; }
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
  local zab_root=( "${DIR_ZABBIX}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: ${sub}/chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#cs[@]} -ge 1 ]]  || { echo "  Нет: ${sub}/chirpstack_*.deb"; ok=1; }
  if [[ ${#zab_root[@]} -ge 1 ]]; then
    :
  else
    echo "  Нет: zabbix/zabbix-agent2_*.deb"
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

# Подкаталог с deb пакетами v4: amd или arm (chirpstackv4/chirpstackv4_17/amd|arm).
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
  local arch
  arch="$(choose_arch)"
  case "$arch" in
    amd64) echo "amd" ;;
    arm64) echo "arm" ;;
    *) die "Неподдерживаемая архитектура для v3: $arch" ;;
  esac
}

# Миграция v3→4.11: bridge в DIR_V4/amd|arm, ядро chirpstack — в DIR_V411 (chirpstackv4/chirpstackv4_11).
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
    amd) cs=( "${DIR_V411}/amd"/chirpstack_*_linux_amd64.deb ) ;;
    arm) cs=( "${DIR_V411}/arm"/chirpstack_*_linux_arm64.deb ) ;;
    *) echo "  Внутренняя ошибка: sub=$sub"; return 1 ;;
  esac
  local zab_root=( "${DIR_ZABBIX}"/zabbix-agent2_*.deb )
  shopt -u nullglob
  [[ ${#gwb[@]} -ge 1 ]] || { echo "  Нет: ${sub}/chirpstack-gateway-bridge_*.deb"; ok=1; }
  [[ ${#cs[@]} -ge 1 ]]  || {
    echo "  Нет пакета ядра в ${DIR_V411}/${sub} (нужен chirpstack_*_linux_amd64.deb или chirpstack_*_linux_arm64.deb)"
    ok=1
  }
  if [[ ${#zab_root[@]} -ge 1 ]]; then
    :
  else
    echo "  Нет: zabbix/zabbix-agent2_*.deb"
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

# Есть ли БД в кластере PostgreSQL (имена фиксированы: lora_as, lora_ns, chirpstack)
postgres_db_exists() {
  local name="${1:?}"
  local r
  r="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$name'" 2>/dev/null || true)"
  [[ "$r" == "1" ]]
}

# Перед DROP DATABASE: разорвать все сессии к этим БД (подключение к postgres)
postgres_terminate_backends_chirp_dbs() {
  local d
  for d in "$@"; do
    echo ">>> Завершаем сессии к БД «$d»"
    sudo -u postgres psql -d postgres -q -c \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$d' AND pid <> pg_backend_pid();" \
      2>/dev/null || true
  done
}
