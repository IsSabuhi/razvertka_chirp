# shellcheck shell=bash
# razvertka-install-fns.sh — вызовы scripts/components/*
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
