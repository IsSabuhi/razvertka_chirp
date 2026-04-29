# shellcheck shell=bash
# razvertka-migration.sh — v3->v4.11, зависит от install-fns, migrator, backup
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
