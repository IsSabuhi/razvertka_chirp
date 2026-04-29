# shellcheck shell=bash
# razvertka-backup.sh — бэкап БД ChirpStack
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
