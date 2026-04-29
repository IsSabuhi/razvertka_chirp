#!/usr/bin/env bash
# Единая точка входа: ChirpStack + Zabbix Agent2. Код: scripts/lib/razvertka-*.sh; ярлыки: scripts/backup-databases.sh и т.д.
# Запуск: sudo ./install.sh

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
# Только вместе с --remove: снять пакеты одной ветки ChirpStack (v3: NS+AS, опц. GWB; v4: core+GWB).
REMOVE_CHIRP_ONLY="${REMOVE_CHIRP_ONLY:-}"
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

LIB="${SCRIPT_DIR}/scripts/lib"
source "${LIB}/razvertka-common.sh"
source "${LIB}/razvertka-migrator.sh"
source "${LIB}/razvertka-install-fns.sh"
source "${LIB}/razvertka-backup.sh"
source "${LIB}/razvertka-status.sh"
source "${LIB}/razvertka-chirpstack-v4-secret.sh"
source "${LIB}/razvertka-migration.sh"
source "${LIB}/razvertka-remove.sh"
source "${LIB}/razvertka-restart.sh"
source "${LIB}/razvertka-run.sh"

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

  Реализация: каталог scripts/lib/ (модули razvertka-*.sh). Те же режимы можно вызвать
  через scripts/backup-databases.sh, show-install-status.sh, remove-stack.sh, upgrade-v3-to-v4.sh, restart-services.sh (обёртки).

Режимы:
  --v3           Установка ChirpStack v3
  --v4           Установка ChirpStack v4
  --full         Полная установка (с выбором версии ChirpStack в интерактиве)
  --component X  Установка отдельного компонента: deps|mosquitto|redis|postgresql|chirpstack|zabbix
  --chirp-version V  Версия для --component (там, где нужно): v3|v4
  --upgrade      Миграция v3 -> 4.11 (ядро: chirpstackv4/chirpstackv4_11, bridge: chirpstackv4/chirpstackv4_17/amd|arm)
  --backup       Сделать pg_dump БД: lora_as, lora_ns, chirpstack (всё, что есть в PostgreSQL)
  --status       Показать, какие пакеты/сервисы/БД по этому стеку обнаружены
  --remove       Выборочное удаление компонентов
  --only-chirp v3|v4  Вместе с --remove: только пакеты v3 (NS+AS) или только v4 (chirpstack+GWB); без --remove — ошибка
                      (v3+GWB снимается, только если пакет chirpstack (v4) не установлен — GWB тогда общий)
  --restart-services Упорядоченный перезапуск postgres/redis/mosquitto/ChirpStack/zabbix

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
  sudo ./install.sh --remove --only-chirp v3
  sudo ./install.sh --remove --only-chirp v4 --yes
  sudo ./install.sh --status
  sudo ./install.sh --restart-services
EOF
}

parse_args() {
  local chirp_version_for_component=""
  local component_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --v3|--v4|--full|--upgrade|--backup|--status|--remove|--restart-services)
        [[ -n "$ACTION" ]] && die "Укажите только один режим (--v3|--v4|--full|--upgrade|--backup|--status|--restart-services|--remove|--component)."
        ACTION="${1#--}"
        shift
        ;;
      --component)
        shift
        [[ $# -gt 0 ]] || die "После --component нужно указать значение."
        [[ -n "$ACTION" ]] && die "Укажите только один режим (--v3|--v4|--full|--upgrade|--backup|--status|--restart-services|--remove|--component)."
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
      --only-chirp)
        shift
        [[ $# -gt 0 ]] || die "После --only-chirp укажите: v3 или v4."
        case "$1" in
          v3|v4) REMOVE_CHIRP_ONLY="$1" ;;
          *) die "После --only-chirp ожидается v3 или v4, получено: $1" ;;
        esac
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
  if [[ -n "$REMOVE_CHIRP_ONLY" && -n "$ACTION" && "$ACTION" != "remove" ]]; then
    die "Опция --only-chirp v3|v4 сочетается только с режимом --remove, не с --${ACTION}."
  fi
  if [[ -n "$REMOVE_CHIRP_ONLY" && -z "$ACTION" ]]; then
    die "С --only-chirp v3|v4 используйте: sudo $0 --remove --only-chirp v3|v4"
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
      status) show_install_status ;;
      restart-services) restart_stack_services ;;
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
    "Показать, что установлено (пакеты, сервисы, БД)"
    "Перезапуск служб стека (PostgreSQL, Redis, Mosquitto, ChirpStack, Zabbix)"
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
        show_install_status
        break
        ;;
      7)
        restart_stack_services
        break
        ;;
      8)
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
