# shellcheck shell=bash
# razvertka-chirpstack-v4-secret.sh — [api].secret в /etc/chirpstack/chirpstack.toml
# При наличии v3: перенос jwt_secret из application-server.
# Иначе: openssl rand -base64 32 (старые JWT перестают работать; данные в БД не портятся).

configure_chirpstack_v4_api_secret() {
  local cs_toml="/etc/chirpstack/chirpstack.toml"
  local as_toml="/etc/chirpstack-application-server/chirpstack-application-server.toml"
  local api_secret=""
  local from_v3=0

  if [[ ! -f "$cs_toml" ]]; then
    echo ">>> Предупреждение: нет $cs_toml — пропуск настройки api.secret." >&2
    return 0
  fi

  if [[ -f "$as_toml" ]]; then
    api_secret="$(
      grep -E '^[[:space:]]*jwt_secret[[:space:]]*=' "$as_toml" 2>/dev/null | head -1 |
        sed -n 's/^[[:space:]]*jwt_secret[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p'
    )"
    if [[ -n "$api_secret" ]]; then
      from_v3=1
      echo ">>> ChirpStack v4: [api].secret взять из jwt_secret v3 (application-server), чтобы JWT после миграции подписывались тем же ключом."
    fi
  fi

  if [[ -z "$api_secret" ]]; then
    command -v openssl >/dev/null 2>&1 || {
      echo "Ошибка: нужен openssl для генерации api.secret." >&2
      return 1
    }
    api_secret="$(openssl rand -base64 32 | tr -d '\n')"
    echo ">>> ChirpStack v4: сгенерирован новый [api].secret (jwt_secret v3 не найден). Старые JWT/API-токены перестанут действовать; данные в PostgreSQL не меняются."
  fi

  if command -v python3 >/dev/null 2>&1; then
    export CHIRPSTACK_V4_API_SECRET_INLINE="$api_secret"
    python3 <<'PY'
import os
import re

path = "/etc/chirpstack/chirpstack.toml"
sec = os.environ.get("CHIRPSTACK_V4_API_SECRET_INLINE", "")


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')

line = ' secret = "' + esc(sec) + '"\n'

with open(path, encoding="utf-8") as f:
    lines = f.readlines()

replaced = False
for i, ln in enumerate(lines):
    if re.match(r"^[ \t]*secret[ \t]*=", ln):
        lines[i] = line
        replaced = True
        break

if not replaced:
    for i, ln in enumerate(lines):
        if ln.strip() == "[api]":
            lines.insert(i + 1, line)
            replaced = True
            break

if not replaced:
    lines.append("\n[api]\n")
    lines.append(line)

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PY
    unset CHIRPSTACK_V4_API_SECRET_INLINE
  else
    echo ">>> (python3 нет — подстановка через sed; при сложном секрете установите python3.)" >&2
    if grep -qE '^[[:space:]]*secret[[:space:]]*=' "$cs_toml"; then
      local esc="$api_secret"
      esc="${esc//\\/\\\\}"
      esc="${esc//|/\\|}"
      sed -i "s|^[[:space:]]*secret[[:space:]]*=.*|secret=\"${esc}\"|" "$cs_toml"
    else
      echo "Ошибка: в $cs_toml нет строки secret и нет python3." >&2
      return 1
    fi
  fi

  if [[ "$from_v3" -eq 0 ]]; then
    echo ">>> Подсказка: смена api.secret позже инвалидирует логины и API-токены; устройства LoRaWAN и записи в БД от этого не ломаются."
  fi
}
