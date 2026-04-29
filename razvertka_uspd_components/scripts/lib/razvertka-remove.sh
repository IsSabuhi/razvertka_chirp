# shellcheck shell=bash
# razvertka-remove.sh — --remove, зависит от common (ask, postgres_terminate)
purge_if_installed() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get purge -y "$pkg"
  fi
}

# Только v3: остановить NS/AS (и GWB, если нет v4) — вызывать до DROP БД, чтобы не было сессий к lora_*
stop_chirpstack_v3_services() {
  local have_v4=0
  dpkg -s chirpstack >/dev/null 2>&1 && have_v4=1
  echo ">>> Останавливаем сервисы ChirpStack v3 (network / application)…"
  systemctl stop chirpstack-network-server chirpstack-application-server 2>/dev/null || true
  if [[ "$have_v4" -eq 0 ]]; then
    systemctl stop chirpstack-gateway-bridge 2>/dev/null || true
  fi
}

purge_chirpstack_v3_debs() {
  local have_v4=0
  dpkg -s chirpstack >/dev/null 2>&1 && have_v4=1
  purge_if_installed "chirpstack-network-server"
  purge_if_installed "chirpstack-application-server"
  if [[ "$have_v4" -eq 0 ]]; then
    purge_if_installed "chirpstack-gateway-bridge"
  else
    echo ">>> Пакет chirpstack (v4) остаётся — gateway-bridge не снимаем (общий пакет)."
  fi
}

stop_chirpstack_v4_services() {
  echo ">>> Останавливаем chirpstack и chirpstack-gateway-bridge…"
  systemctl stop chirpstack chirpstack-gateway-bridge 2>/dev/null || true
}

purge_chirpstack_v4_debs() {
  purge_if_installed "chirpstack"
  purge_if_installed "chirpstack-gateway-bridge"
}

remove_stack_chirp_only() {
  local which="${1:?}"
  case "$which" in
    v3)
      if ! dpkg -s chirpstack-network-server >/dev/null 2>&1 && ! dpkg -s chirpstack-application-server >/dev/null 2>&1; then
        echo "Пакеты ChirpStack v3 (network / application) не найдены — снимать нечего."
        return 0
      fi
      ;;
    v4)
      if ! dpkg -s chirpstack >/dev/null 2>&1; then
        echo "Пакет chirpstack (v4) не установлен — снимать нечего."
        return 0
      fi
      ;;
  esac
  echo "ВНИМАНИЕ: снимаются только пакеты ChirpStack $which; остальной стек (Zabbix, Mosquitto, ост. ветка Chirp) не трогается."
  if ! ask_yes_no "Продолжить?"; then
    echo "Отменено."
    return 0
  fi
  if [[ "$which" == "v3" ]]; then
    # Сначала остановка и БД, потом purge — иначе postrm/хвосты держат сессии к lora_*.
    stop_chirpstack_v3_services
    if ask_yes_no "Удалить в PostgreSQL БД lora_as и lora_ns и роли lora_as, lora_ns? (БД chirpstack (v4) не трогаем)"; then
      echo ">>> Завершаем сессии, DROP БД и ролей v3"
      postgres_terminate_backends_chirp_dbs lora_as lora_ns
      sudo -u postgres psql -v ON_ERROR_STOP=1 <<'EOF'
DROP DATABASE IF EXISTS lora_as;
DROP DATABASE IF EXISTS lora_ns;
DROP ROLE IF EXISTS lora_as;
DROP ROLE IF EXISTS lora_ns;
EOF
    fi
    purge_chirpstack_v3_debs
  else
    stop_chirpstack_v4_services
    if ask_yes_no "Удалить в PostgreSQL БД chirpstack и роль chirpstack? (БД lora_* (v3) не трогаем)"; then
      echo ">>> Завершаем сессии, DROP БД и роли v4"
      postgres_terminate_backends_chirp_dbs chirpstack
      sudo -u postgres psql -v ON_ERROR_STOP=1 <<'EOF'
DROP DATABASE IF EXISTS chirpstack;
DROP ROLE IF EXISTS chirpstack;
EOF
    fi
    purge_chirpstack_v4_debs
  fi
  echo ">>> Снятие пакетов ChirpStack $which завершено."
}

remove_stack() {
  if [[ "${REMOVE_CHIRP_ONLY}" == "v3" ]]; then
    remove_stack_chirp_only "v3"
    return
  fi
  if [[ "${REMOVE_CHIRP_ONLY}" == "v4" ]]; then
    remove_stack_chirp_only "v4"
    return
  fi

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
    echo ">>> Удаляем сессии, БД и роли PostgreSQL (если существуют)"
    postgres_terminate_backends_chirp_dbs chirpstack lora_as lora_ns
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<'EOF'
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
