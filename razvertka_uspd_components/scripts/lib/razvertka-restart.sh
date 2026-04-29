# shellcheck shell=bash
# razvertka-restart.sh — упорядоченный перезапуск служб стека

restart_stack_services() {
  echo ">>> Перезапуск служб (PostgreSQL → Redis → Mosquitto → gateway → ChirpStack → Zabbix)…"
  local u
  for u in postgresql redis-server mosquitto chirpstack-gateway-bridge; do
    if systemctl cat "$u" &>/dev/null || systemctl cat "${u}.service" &>/dev/null; then
      systemctl restart "$u" && echo "  $u: ok" || echo "  $u: ошибка (см. journalctl)" >&2
    fi
  done

  if dpkg -s chirpstack >/dev/null 2>&1; then
    systemctl restart chirpstack && echo "  chirpstack (v4): ok" || echo "  chirpstack: ошибка" >&2
  fi
  if dpkg -s chirpstack-network-server >/dev/null 2>&1; then
    systemctl restart chirpstack-network-server chirpstack-application-server && echo "  chirpstack NS/AS (v3): ok" || true
  fi

  if systemctl cat zabbix-agent2 &>/dev/null || systemctl cat zabbix-agent2.service &>/dev/null; then
    systemctl restart zabbix-agent2 && echo "  zabbix-agent2: ok" || true
  fi

  echo ">>> Перезапуск завершён."
}
