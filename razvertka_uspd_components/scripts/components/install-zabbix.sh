#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
DIR_V3="${2:-}"
DIR_ZABBIX="${3:-}"
ARCH_SUBDIR="${4:-}"

if [[ "$VERSION" != "v3" && "$VERSION" != "v4" ]]; then
  echo "Ошибка: usage install-zabbix.sh v3|v4 <DIR_V3_BASE> <DIR_ZABBIX> <amd|arm>" >&2
  exit 1
fi

CFG=""
shopt -s nullglob
Z_DEBS=()

if [[ "$VERSION" == "v3" ]]; then
  CFG="${DIR_ZABBIX}/zabbix_agent2.conf"
  Z_DEBS=( "${DIR_ZABBIX}"/zabbix-agent2_*.deb )
else
  CFG="${DIR_ZABBIX}/zabbix_agent2.conf"
  Z_DEBS=( "${DIR_ZABBIX}"/zabbix-agent2_*.deb )
fi
shopt -u nullglob

[[ -f "$CFG" ]] || {
  echo "Ошибка: не найден конфиг Zabbix: $CFG" >&2
  exit 1
}
[[ ${#Z_DEBS[@]} -ge 1 ]] || {
  echo "Ошибка: не найден zabbix-agent2_*.deb для ${VERSION}" >&2
  exit 1
}

echo ">>> Установка Zabbix Agent2..."
dpkg -i "${Z_DEBS[@]}"
install -m 0644 "$CFG" /etc/zabbix/zabbix_agent2.conf
systemctl daemon-reload
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
