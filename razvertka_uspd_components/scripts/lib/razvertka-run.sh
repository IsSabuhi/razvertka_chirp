# shellcheck shell=bash
# razvertka-run.sh — run_v3/v4, меню компонентов; зависит от install-fns и common
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
