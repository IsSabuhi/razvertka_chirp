#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ "$VERSION" != "v3" && "$VERSION" != "v4" ]]; then
  echo "Ошибка: usage install-postgresql.sh v3|v4" >&2
  exit 1
fi

echo ">>> Установка PostgreSQL..."
apt-get update
apt-get install -y postgresql postgresql-contrib
systemctl enable postgresql
systemctl restart postgresql

if [[ "$VERSION" == "v3" ]]; then
  echo ">>> Создание ролей/БД для ChirpStack v3..."
  sudo -u postgres psql <<'EOF'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lora_ns') THEN
        CREATE ROLE lora_ns LOGIN PASSWORD 'lora_ns';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lora_as') THEN
        CREATE ROLE lora_as LOGIN PASSWORD 'lora_as';
    END IF;
END
$$;
SELECT 'CREATE DATABASE lora_ns OWNER lora_ns'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'lora_ns')\gexec
SELECT 'CREATE DATABASE lora_as OWNER lora_as'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'lora_as')\gexec
\c lora_as
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
EOF
else
  echo ">>> Создание роли/БД для ChirpStack v4..."
  sudo -u postgres psql <<'EOF'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'chirpstack') THEN
        CREATE ROLE chirpstack LOGIN PASSWORD 'chirpstack';
    END IF;
END
$$;
SELECT 'CREATE DATABASE chirpstack OWNER chirpstack'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'chirpstack')\gexec
\c chirpstack
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
EOF
fi
