#!/usr/bin/env bash
# Единая точка входа для развёртывания ChirpStack + Zabbix Agent2.
# Запуск: sudo ./install.sh  (из каталога репозитория или по полному пути)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_V3="${SCRIPT_DIR}/chirpstackv3"
DIR_V4="${SCRIPT_DIR}/chirpstackv4/chirpstackv4_17"
COMPONENTS_DIR="${SCRIPT_DIR}/scripts/components"
DIR_ZABBIX="${SCRIPT_DIR}/zabbix"
# Ядро ChirpStack 4.11.x для миграции v3→v4.
DIR_V411="${SCRIPT_DIR}/chirpstackv4/chirpstackv4_11"
BACKUP_DIR_DEFAULT="/var/backups/chirpstack-migration"
ARCH_OVERRIDE=""
ACTION=""
AUTO_YES=0
BACKUP_DIR_OVERRIDE=""
# Версия релиза утилиты https://github.com/chirpstack/chirpstack-v3-to-v4 (тег v4.0.11 → 4.0.11)
CHIRPSTACK_MIGRATOR_VER="${CHIRPSTACK_MIGRATOR_VER:-4.0.11}"
SKIP_MIGRATOR_DOWNLOAD="${SKIP_MIGRATOR_DOWNLOAD:-0}"
# Перед миграцией данных передать мигратору --drop-tenants-and-users (очищает пользователей/тенантов в БД v4; только если понятна потеря данных).
CHIRPSTACK_MIGRATOR_DROP_TENANTS_AND_USERS="${CHIRPSTACK_MIGRATOR_DROP_TENANTS_AND_USERS:-0}"
# Перед мигратором пересоздать пустую БД chirpstack (v4), чтобы не было конфликтов idx_user_email / частичного переноса.
CHIRPSTACK_MIGRATION_CLEAR_V4_DB="${CHIRPSTACK_MIGRATION_CLEAR_V4_DB:-1}"

COMPONENT_INSTALL_DEPS="${COMPONENTS_DIR}/install-deps.sh"
COMPONENT_INSTALL_MOSQUITTO="${COMPONENTS_DIR}/install-mosquitto.sh"
COMPONENT_INSTALL_REDIS="${COMPONENTS_DIR}/install-redis.sh"
COMPONENT_INSTALL_POSTGRESQL="${COMPONENTS_DIR}/install-postgresql.sh"
COMPONENT_INSTALL_CHIRPSTACK="${COMPONENTS_DIR}/install-chirpstack.sh"
COMPONENT_INSTALL_ZABBIX="${COMPONENTS_DIR}/install-zabbix.sh"

# Локальный мигратор в tools/: без ручного export — подставляем CHIRPSTACK_MIGRATOR_BIN сами.
_tools_m_dir="${SCRIPT_DIR}/tools"
if [[ -z "${CHIRPSTACK_MIGRATOR_BIN:-}" ]]; then
  _m_found=""
  if [[ -f "${_tools_m_dir}/chirpstack-v3-to-v4" ]]; then
    _m_found="${_tools_m_dir}/chirpstack-v3-to-v4"
  else
    shopt -s nullglob
    for _f in "${_tools_m_dir}"/chirpstack-v3-to-v4*; do
      [[ -f "$_f" ]] || continue
      _m_found="${_f}"
      break
    done
    shopt -u nullglob
  fi
  if [[ -n "${_m_found}" ]]; then
    [[ -x "${_m_found}" ]] || chmod +x "${_m_found}" 2>/dev/null || true
    export CHIRPSTACK_MIGRATOR_BIN="${_m_found}"
  fi
fi

die() {
  echo "Ошибка: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "Запустите скрипт от root: sudo $0"
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

download_migrator_to_tools() {
  local tools_dir="${SCRIPT_DIR}/tools"
  local ver="$CHIRPSTACK_MIGRATOR_VER"
  local tag="v${ver}"
  local mach uarch tarball url tmpdir candidate target
  command -v curl >/dev/null 2>&1 || {
    echo "Для авто-загрузки мигратора нужен curl." >&2
    return 1
  }
  mach="$(uname -m)"
  case "$mach" in
    x86_64) uarch="amd64" ;;
    aarch64) uarch="arm64" ;;
    armv7l) uarch="armv7" ;;
    *)
      echo "Авто-загрузка мигратора: неизвестная архитектура $mach" >&2
      return 1
      ;;
  esac
  tarball="chirpstack-v3-to-v4_${ver}_linux_${uarch}.tar.gz"
  url="https://github.com/chirpstack/chirpstack-v3-to-v4/releases/download/${tag}/${tarball}"
  target="${tools_dir}/chirpstack-v3-to-v4"
  mkdir -p "$tools_dir"
  tmpdir="$(mktemp -d)"
  echo ">>> Скачиваем утилиту миграции (${tarball})..." >&2
  if ! curl -fsSL "$url" -o "${tmpdir}/${tarball}"; then
    rm -rf "$tmpdir"
    echo "Не удалось скачать: $url" >&2
    return 1
  fi
  tar -xzf "${tmpdir}/${tarball}" -C "$tmpdir"
  candidate="$(find "$tmpdir" -type f \( -name 'chirpstack-v3-to-v4' -o -name 'chirpstack-v3-to-v4_*' \) ! -name '*.tar.gz' 2>/dev/null | head -1)"
  if [[ -z "$candidate" ]]; then
    candidate="$(find "$tmpdir" -maxdepth 4 -type f -perm -111 ! -name '*.tar.gz' 2>/dev/null | head -1)"
  fi
  if [[ -z "$candidate" || ! -f "$candidate" ]]; then
    rm -rf "$tmpdir"
    echo "В архиве не найден исполняемый файл мигратора." >&2
    return 1
  fi
  cp -f "$candidate" "$target"
  chmod +x "$target"
  rm -rf "$tmpdir"
  echo ">>> Мигратор сохранён: $target" >&2
  return 0
}

resolve_migrator_binary() {
  # Приоритет: явный путь → файлы в ./tools → скачивание → команда из PATH.
  local tools_dir="${SCRIPT_DIR}/tools"
  local p_default="${tools_dir}/chirpstack-v3-to-v4"
  local f cand

  if [[ -n "${CHIRPSTACK_MIGRATOR_BIN:-}" ]]; then
    if [[ -x "${CHIRPSTACK_MIGRATOR_BIN}" ]]; then
      echo "${CHIRPSTACK_MIGRATOR_BIN}"
      return 0
    fi
    die "CHIRPSTACK_MIGRATOR_BIN задан, но не исполняемый файл: ${CHIRPSTACK_MIGRATOR_BIN}"
  fi

  mkdir -p "$tools_dir"

  if [[ -f "$p_default" ]] && [[ ! -x "$p_default" ]]; then
    chmod +x "$p_default" 2>/dev/null || true
  fi
  if [[ -x "$p_default" ]]; then
    echo "$p_default"
    return 0
  fi

  shopt -s nullglob
  for f in "${tools_dir}"/chirpstack-v3-to-v4*; do
    [[ -f "$f" ]] || continue
    [[ -x "$f" ]] || chmod +x "$f" 2>/dev/null || true
    if [[ -x "$f" ]]; then
      shopt -u nullglob
      echo "$f"
      return 0
    fi
  done
  shopt -u nullglob

  if [[ "$SKIP_MIGRATOR_DOWNLOAD" == "1" ]]; then
    return 1
  fi
  if download_migrator_to_tools && [[ -x "$p_default" ]]; then
    echo "$p_default"
    return 0
  fi

  cand="$(command -v chirpstack-v3-to-v4 2>/dev/null || true)"
  if [[ -n "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  return 1
}

run_v3() {
  [[ -d "$DIR_V3" ]] || die "Каталог не найден: $DIR_V3"
  local deb_sub
  deb_sub="$(prepare_v3_packages)"
  echo "Проверка .deb v3 в: ${DIR_V3}/${deb_sub}"
  if ! check_v3_packages "$deb_sub"; then
    die "Не найдены обязательные .deb в каталоге установки v3."
  fi
  install_dependencies_component
  install_postgresql_component "v3"
  install_chirpstack_component "v3"
  install_zabbix_component "v3"
}

run_v4() {
  [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
  local deb_sub
  deb_sub="$(v4_chirp_deb_subdir)"
  echo "Проверка .deb v4 в: ${DIR_V4}/${deb_sub} (zabbix — в zabbix/)"
  if ! check_v4_packages "$deb_sub"; then
    die "Не найдены обязательные .deb для v4."
  fi
  install_dependencies_component
  install_postgresql_component "v4"
  install_chirpstack_component "v4"
  install_zabbix_component "v4"
}

install_dependencies_component() {
  [[ -x "$COMPONENT_INSTALL_DEPS" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_DEPS"
  bash "$COMPONENT_INSTALL_DEPS"
}

install_mosquitto_component() {
  [[ -x "$COMPONENT_INSTALL_MOSQUITTO" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_MOSQUITTO"
  bash "$COMPONENT_INSTALL_MOSQUITTO"
}

install_redis_component() {
  [[ -x "$COMPONENT_INSTALL_REDIS" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_REDIS"
  bash "$COMPONENT_INSTALL_REDIS"
}

install_postgresql_component() {
  local version="${1:-}"
  [[ "$version" == "v3" || "$version" == "v4" ]] || die "Внутренняя ошибка: install_postgresql_component(version=$version)"
  [[ -x "$COMPONENT_INSTALL_POSTGRESQL" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_POSTGRESQL"
  bash "$COMPONENT_INSTALL_POSTGRESQL" "$version"
}

install_chirpstack_component() {
  local version="${1:-}"
  [[ "$version" == "v3" || "$version" == "v4" ]] || die "Внутренняя ошибка: install_chirpstack_component(version=$version)"
  [[ -x "$COMPONENT_INSTALL_CHIRPSTACK" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_CHIRPSTACK"

  if [[ "$version" == "v3" ]]; then
    [[ -d "$DIR_V3" ]] || die "Каталог не найден: $DIR_V3"
    local deb_sub
    deb_sub="$(prepare_v3_packages)"
    echo "Проверка .deb v3 в: ${DIR_V3}/${deb_sub}"
    check_v3_packages "$deb_sub" || die "Не найдены обязательные .deb для v3."
    bash "$COMPONENT_INSTALL_CHIRPSTACK" "v3" "$DIR_V3" "$DIR_V4" "$deb_sub"
  else
    [[ -d "$DIR_V4" ]] || die "Каталог не найден: $DIR_V4"
    local deb_sub
    deb_sub="$(v4_chirp_deb_subdir)"
    echo "Проверка .deb v4 в: ${DIR_V4}/${deb_sub}"
    check_v4_packages "$deb_sub" || die "Не найдены обязательные .deb для v4."
    bash "$COMPONENT_INSTALL_CHIRPSTACK" "v4" "$DIR_V3" "$DIR_V4" "$deb_sub"
  fi
}

install_zabbix_component() {
  local version="${1:-}"
  [[ "$version" == "v3" || "$version" == "v4" ]] || die "Внутренняя ошибка: install_zabbix_component(version=$version)"
  [[ -x "$COMPONENT_INSTALL_ZABBIX" ]] || die "Не найден компонентный скрипт: $COMPONENT_INSTALL_ZABBIX"

  local deb_sub=""
  if [[ "$version" == "v4" ]]; then
    deb_sub="$(v4_chirp_deb_subdir)"
  fi
  bash "$COMPONENT_INSTALL_ZABBIX" "$version" "$DIR_V3" "$DIR_ZABBIX" "$deb_sub"
}

choose_chirp_version() {
  local answer default="2"
  echo "Выберите версию ChirpStack для установки:" >&2
  echo "  1) v3" >&2
  echo "  2) v4" >&2
  read -r -p "Введите номер версии (1=v3, 2=v4) [${default}]: " answer
  answer="${answer:-$default}"
  case "$answer" in
    1) echo "v3" ;;
    2) echo "v4" ;;
    *) die "Неверный выбор версии ChirpStack: $answer" ;;
  esac
}

run_full_stack_with_version_choice() {
  local version="$1"
  case "$version" in
    v3) run_v3 ;;
    v4) run_v4 ;;
    *) die "Неверная версия для полного стека: $version" ;;
  esac
}

run_component_install_menu() {
  local component version
  PS3="Выберите компонент для установки: "
  local items=(
    "Зависимости (mosquitto + redis + postgresql + openssl)"
    "Mosquitto"
    "Redis"
    "PostgreSQL (+ роли/БД под выбранную версию ChirpStack)"
    "ChirpStack (только пакеты и сервисы)"
    "Zabbix Agent2"
    "Назад"
  )
  select component in "${items[@]}"; do
    case "$REPLY" in
      1) install_dependencies_component; break ;;
      2) install_mosquitto_component; break ;;
      3) install_redis_component; break ;;
      4)
        version="$(choose_chirp_version)"
        install_postgresql_component "$version"
        break
        ;;
      5)
        version="$(choose_chirp_version)"
        install_chirpstack_component "$version"
        break
        ;;
      6)
        version="$(choose_chirp_version)"
        install_zabbix_component "$version"
        break
        ;;
      7) return 0 ;;
      *) echo "Неверный выбор: $REPLY" ;;
    esac
  done
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

# Есть ли БД в кластере PostgreSQL (имена фиксированы: lora_as, lora_ns, chirpstack)
postgres_db_exists() {
  local name="${1:?}"
  local r
  r="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$name'" 2>/dev/null || true)"
  [[ "$r" == "1" ]]
}

# Бэкап всех известных БД ChirpStack: lora_as, lora_ns (v3), chirpstack (v4) — что есть.
run_database_backup() {
  local backup_dir=""
  if [[ -n "$BACKUP_DIR_OVERRIDE" ]]; then
    backup_dir="$BACKUP_DIR_OVERRIDE"
    echo "Каталог для бэкапов БД: $backup_dir"
  elif [[ "$AUTO_YES" -eq 1 ]]; then
    backup_dir="$BACKUP_DIR_DEFAULT"
    echo "Каталог для бэкапов БД: $backup_dir"
  else
    read -r -p "Каталог для бэкапов БД [${BACKUP_DIR_DEFAULT}]: " backup_dir
    backup_dir="${backup_dir:-$BACKUP_DIR_DEFAULT}"
  fi
  mkdir -p "$backup_dir"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local any=0
  echo ">>> Создаём SQL-дампы в: $backup_dir"
  for db in lora_as lora_ns chirpstack; do
    if postgres_db_exists "$db"; then
      local f="${backup_dir}/${db}_${ts}.sql"
      echo ">>> pg_dump: $db"
      sudo -u postgres pg_dump "$db" >"$f"
      echo "  - $f"
      any=1
    fi
  done
  if [[ "$any" -eq 0 ]]; then
    die "В PostgreSQL нет баз lora_as, lora_ns или chirpstack. Нечего бэкапить."
  fi
  echo ">>> Бэкап завершён."
}

# Пустая БД chirpstack (v4) без старых пользователей/следов прошлой миграции.
recreate_chirpstack_v4_database_for_migration() {
  echo ">>> Останавливаем ChirpStack 4.11 перед пересозданием БД..."
  systemctl stop chirpstack chirpstack-gateway-bridge 2>/dev/null || true
  echo ">>> Пересоздаём пустую БД «chirpstack» для миграции v3 -> v4..."
  sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'chirpstack' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS chirpstack;
DO $migr$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chirpstack') THEN
    CREATE ROLE chirpstack LOGIN PASSWORD 'chirpstack';
  END IF;
END
$migr$;
CREATE DATABASE chirpstack OWNER chirpstack;
\c chirpstack
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
SQL
  echo ">>> БД «chirpstack» очищена (новая пустая база с расширениями)."
}

# Есть ли уже схема 4.11 (таблица user)
v4_chirpstack_user_table_exists() {
  local r
  r="$(sudo -u postgres psql -d chirpstack -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user' LIMIT 1" 2>/dev/null || true)"
  [[ "$r" == "1" ]]
}

# Мигратор v3->v4 требует, чтобы в БД chirpstack уже существовали таблицы (chirpstack 4.11 накатывает схему при первом старте).
# После пустой БД: поднять сервис, дождаться таблицы user, остановить, очистить сиды, не трогая служебные таблицы *migration*.
chirpstack_bootstrap_v4_schema_for_migrator() {
  local do_strip_seeds="${1:-0}"
  echo ">>> Создаём схему ChirpStack 4.11: первый запуск сервиса (миграции SQL)…"
  systemctl start mosquitto redis-server 2>/dev/null || true
  systemctl start postgresql 2>/dev/null || true
  systemctl start chirpstack
  local i=0
  while [[ $i -lt 120 ]]; do
    if v4_chirpstack_user_table_exists; then
      echo ">>> Схема готова (public.user существует)."
      break
    fi
    if ! systemctl is-active --quiet chirpstack; then
      systemctl stop chirpstack 2>/dev/null || true
      die "Сервис chirpstack остановился до готовности схемы. Смотрите: journalctl -u chirpstack -n 80"
    fi
    sleep 1
    i=$((i + 1))
  done
  if ! v4_chirpstack_user_table_exists; then
    systemctl stop chirpstack 2>/dev/null || true
    die "Таймаут: за 120 с не появилась public.user. Проверьте dsn в /etc/chirpstack/chirpstack.toml, PostgreSQL и: journalctl -u chirpstack -n 80"
  fi
  systemctl stop chirpstack 2>/dev/null || true

  if [[ "$do_strip_seeds" == "1" ]]; then
    echo ">>> Очищаем тестовые/дефолтные данные (таблицы *migration* не трогаем)…"
    sudo -u postgres psql -d chirpstack -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  q   text;
  t   text;
  agg text;
BEGIN
  SELECT coalesce(
    string_agg('public.' || format('%I', tablename), ', ' ORDER BY tablename),
    ''
  ) INTO agg
  FROM pg_tables
  WHERE schemaname = 'public'
    AND lower(tablename) NOT LIKE '%migration%';
  IF coalesce(agg, '') = '' THEN
    RAISE NOTICE 'Нет таблиц для TRUNCATE';
    RETURN;
  END IF;
  q := 'TRUNCATE ' || agg || ' RESTART IDENTITY CASCADE';
  RAISE NOTICE '%', q;
  EXECUTE q;
END $$;
SQL
  fi
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

  migrator="$(resolve_migrator_binary)" || die "Не найден инструмент миграции chirpstack-v3-to-v4.
Если есть интернет и curl: повторите запуск — скрипт скачает релиз ${CHIRPSTACK_MIGRATOR_VER} с GitHub в ${SCRIPT_DIR}/tools/.
Без сети: скачайте .tar.gz с https://github.com/chirpstack/chirpstack-v3-to-v4/releases , распакуйте бинарник в ${SCRIPT_DIR}/tools/chirpstack-v3-to-v4
Офлайн без авто-скачивания: export SKIP_MIGRATOR_DOWNLOAD=1 и положите бинарник вручную."

  echo ">>> Запуск миграции данных v3 -> v4 через: $migrator"
  # Флаг --update-existing есть не во всех сборках chirpstack-v3-to-v4; не используем.
  local migrator_extra=()
  if [[ "${CHIRPSTACK_MIGRATOR_DROP_TENANTS_AND_USERS}" == "1" ]]; then
    echo ">>> ВНИМАНИЕ: мигратор запускается с --drop-tenants-and-users (в БД v4 будут удалены существующие tenants/users перед переносом)."
    migrator_extra+=(--drop-tenants-and-users)
  fi
  "$migrator" \
    --as-config-file /etc/chirpstack-application-server/chirpstack-application-server.toml \
    --ns-config-file /etc/chirpstack-network-server/chirpstack-network-server.toml \
    --cs-config-file /etc/chirpstack/chirpstack.toml \
    "${migrator_extra[@]}"
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
    echo ">>> Установка окружения для 4.11 (зависимости + БД + пакеты)..."
    install_dependencies_component
    install_postgresql_component "v4"
    shopt -s nullglob
    local gwb=( "${DIR_V4}/${deb_sub}"/chirpstack-gateway-bridge_*.deb )
    local core=()
    case "$deb_sub" in
      amd) core=( "${DIR_V411}/amd"/chirpstack_*.deb ) ;;
      arm) core=( "${DIR_V411}/arm"/chirpstack_*.deb ) ;;
      *) die "Внутренняя ошибка: неизвестный subdir для миграции: $deb_sub" ;;
    esac
    shopt -u nullglob
    [[ ${#gwb[@]} -ge 1 ]] || die "Не найден chirpstack-gateway-bridge_*.deb в ${DIR_V4}/${deb_sub}"
    [[ ${#core[@]} -ge 1 ]] || die "Не найден chirpstack_*.deb в ${DIR_V411}/${deb_sub}"
    dpkg -i "${gwb[@]}"
    dpkg -i "${core[@]}"
    systemctl enable chirpstack chirpstack-gateway-bridge
    systemctl restart chirpstack chirpstack-gateway-bridge
  else
    echo ">>> ChirpStack 4.11.x уже установлен ($cs_ver), шаг fast_razvertkav4.sh пропущен."
  fi

  if [[ "${CHIRPSTACK_MIGRATION_CLEAR_V4_DB}" == "1" ]]; then
    recreate_chirpstack_v4_database_for_migration
    chirpstack_bootstrap_v4_schema_for_migrator 1
  else
    echo ">>> CHIRPSTACK_MIGRATION_CLEAR_V4_DB=0 — пересоздание БД «chirpstack» пропущено. Останавливаем сервисы 4.11 перед мигратором."
    systemctl stop chirpstack chirpstack-gateway-bridge 2>/dev/null || true
    if ! v4_chirpstack_user_table_exists; then
      echo ">>> Схема 4.11 в БД не найдена, создаём (первый старт chirpstack)…"
      chirpstack_bootstrap_v4_schema_for_migrator 0
    fi
  fi

  run_v3_to_v4_migration

  echo ">>> Запуск сервисов ChirpStack 4.11..."
  systemctl start chirpstack chirpstack-gateway-bridge
  systemctl is-active --quiet chirpstack && echo "chirpstack: active" || true

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
  --full         Полная установка (с выбором версии ChirpStack в интерактиве)
  --component X  Установка отдельного компонента: deps|mosquitto|redis|postgresql|chirpstack|zabbix
  --chirp-version V  Версия для --component (там, где нужно): v3|v4
  --upgrade      Миграция v3 -> 4.11 (ядро: chirpstackv4/chirpstackv4_11, bridge: chirpstackv4/chirpstackv4_17/amd|arm)
  --backup       Сделать pg_dump БД: lora_as, lora_ns, chirpstack (всё, что есть в PostgreSQL)
  --remove       Выборочное удаление компонентов

Опции:
  --arch VALUE   auto|amd64|arm64
  --backup-dir   Каталог для бэкапа БД (для --upgrade и --backup)
  --yes          Авто-ответ "yes" на вопросы подтверждения
  --skip-migrator-download  Не скачивать chirpstack-v3-to-v4 с GitHub (нужен локальный tools/chirpstack-v3-to-v4)
  --migrator-drop-tenants-and-users  Передать мигратору --drop-tenants-and-users (см. справку chirpstack-v3-to-v4 -h)
  --skip-clear-v4-db         Не пересоздавать пустую БД «chirpstack» перед миграцией (по умолчанию БД очищается)
  -h, --help     Показать справку

Переменные окружения:
  CHIRPSTACK_MIGRATOR_VER   Версия релиза мигратора на GitHub (по умолчанию 4.0.11)
  SKIP_MIGRATOR_DOWNLOAD=1  То же, что --skip-migrator-download
  CHIRPSTACK_MIGRATOR_DROP_TENANTS_AND_USERS=1  То же, что --migrator-drop-tenants-and-users
  CHIRPSTACK_MIGRATOR_BIN     Явный путь к мигратору (если не задан — берётся из tools/ автоматически)
  CHIRPSTACK_MIGRATION_CLEAR_V4_DB=0  То же, что --skip-clear-v4-db

Примеры:
  sudo ./install.sh --v4 --arch amd64
  sudo ./install.sh --upgrade --arch arm64 --backup-dir /var/backups/chirpstack
  sudo ./install.sh --backup --backup-dir /var/backups/chirpstack
  sudo ./install.sh --remove
EOF
}

parse_args() {
  local chirp_version_for_component=""
  local component_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --v3|--v4|--full|--upgrade|--backup|--remove)
        [[ -n "$ACTION" ]] && die "Укажите только один режим (--v3|--v4|--full|--upgrade|--backup|--remove|--component)."
        ACTION="${1#--}"
        shift
        ;;
      --component)
        shift
        [[ $# -gt 0 ]] || die "После --component нужно указать значение."
        [[ -n "$ACTION" ]] && die "Укажите только один режим (--v3|--v4|--full|--upgrade|--remove|--component)."
        ACTION="component"
        component_name="$1"
        shift
        ;;
      --chirp-version)
        shift
        [[ $# -gt 0 ]] || die "После --chirp-version нужно указать значение (v3|v4)."
        chirp_version_for_component="$1"
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
      --skip-migrator-download)
        SKIP_MIGRATOR_DOWNLOAD=1
        shift
        ;;
      --migrator-drop-tenants-and-users)
        CHIRPSTACK_MIGRATOR_DROP_TENANTS_AND_USERS=1
        shift
        ;;
      --skip-clear-v4-db)
        CHIRPSTACK_MIGRATION_CLEAR_V4_DB=0
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

  if [[ "$ACTION" == "component" ]]; then
    case "$component_name" in
      deps) ACTION="component:deps" ;;
      mosquitto) ACTION="component:mosquitto" ;;
      redis) ACTION="component:redis" ;;
      postgresql|chirpstack|zabbix)
        [[ "$chirp_version_for_component" == "v3" || "$chirp_version_for_component" == "v4" ]] || \
          die "Для --component ${component_name} укажите --chirp-version v3|v4."
        ACTION="component:${component_name}:${chirp_version_for_component}"
        ;;
      *)
        die "Неизвестный компонент: ${component_name} (допустимо: deps|mosquitto|redis|postgresql|chirpstack|zabbix)."
        ;;
    esac
  fi
}

main() {
  need_root
  parse_args "$@"

  if [[ -n "$ACTION" ]]; then
    case "$ACTION" in
      v3) run_v3 ;;
      v4) run_v4 ;;
      full)
        run_full_stack_with_version_choice "$(choose_chirp_version)"
        ;;
      component:deps) install_dependencies_component ;;
      component:mosquitto) install_mosquitto_component ;;
      component:redis) install_redis_component ;;
      component:postgresql:v3) install_postgresql_component "v3" ;;
      component:postgresql:v4) install_postgresql_component "v4" ;;
      component:chirpstack:v3) install_chirpstack_component "v3" ;;
      component:chirpstack:v4) install_chirpstack_component "v4" ;;
      component:zabbix:v3) install_zabbix_component "v3" ;;
      component:zabbix:v4) install_zabbix_component "v4" ;;
      upgrade) upgrade_v3_to_v4 ;;
      backup) run_database_backup ;;
      remove) remove_stack ;;
      *) die "Неизвестный режим: $ACTION" ;;
    esac
    exit 0
  fi

  show_menu

  PS3="Введите номер пункта и нажмите Enter: "
  local options=(
    "Полная установка стека (выбор версии ChirpStack)"
    "Установка отдельного компонента"
    "Миграция v3 -> ChirpStack 4.11 + данные"
    "Удаление (ChirpStack/Zabbix, опционально БД и данные)"
    "Бэкап БД PostgreSQL (lora_as, lora_ns, chirpstack — что есть)"
    "Выход"
  )
  select _ in "${options[@]}"; do
    case $REPLY in
      1)
        run_full_stack_with_version_choice "$(choose_chirp_version)"
        break
        ;;
      2)
        run_component_install_menu
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
        run_database_backup
        break
        ;;
      6)
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
