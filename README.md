# Razvertka USPD Components

Главная рабочая папка: `razvertka_uspd_components`.

`install.sh` — основной файл: задаёт пути, подключает модули из `scripts/lib/razvertka-*.sh` и вызывает `scripts/components/*` при установке пакетов.

- полный стек (`v3` или `v4`);
- установка отдельных компонентов;
- миграция `v3 -> ChirpStack 4.11`;
- бэкап, статус, выборочное удаление (неинтерактивные флаги см. `--help`).

Дополнительные имена-обёртки (эквиваленты `install.sh` с флагом): `scripts/backup-databases.sh`, `scripts/show-install-status.sh`, `scripts/remove-stack.sh`, `scripts/upgrade-v3-to-v4.sh`.

## Точка входа

```bash
cd /path/to/razvertka_uspd_components
sudo ./install.sh
```

Неинтерактивные примеры:

```bash
# Полная установка v3
sudo ./install.sh --v3 --arch amd64

# Полная установка v4 (используется ветка 4.17)
sudo ./install.sh --v4 --arch amd64

# Установка отдельного компонента
sudo ./install.sh --component deps
sudo ./install.sh --component postgresql --chirp-version v4
sudo ./install.sh --component chirpstack --chirp-version v3 --arch arm64

# Миграция v3 -> 4.11
sudo ./install.sh --upgrade --arch amd64 --backup-dir /var/backups/chirpstack

# Удаление
sudo ./install.sh --remove
```

## Флаги

- `--v3` / `--v4` / `--full` / `--upgrade` / `--backup` / `--status` / `--remove` — выбрать один режим.
- `--component <deps|mosquitto|redis|postgresql|chirpstack|zabbix>` — установить один компонент.
- `--chirp-version <v3|v4>` — обязателен для `postgresql|chirpstack|zabbix`.
- `--arch auto|amd64|arm64` — архитектура пакетов.
- `--backup-dir <path>` — каталог для бэкапа БД при `--upgrade`.
- `--yes` — авто-подтверждение в вопросах удаления.
- `--skip-migrator-download` — не скачивать `chirpstack-v3-to-v4` автоматически.
- `--help` — справка.

## Актуальная структура

**Архитектура кода:** `install.sh` только задаёт пути, подключает `scripts/lib/razvertka-*.sh` (логика) и для установки .deb вызывает `scripts/components/*.sh`.

| Модуль `scripts/lib/` | Назначение |
|----------------------|------------|
| `razvertka-common.sh` | Пакеты, arch, PostgreSQL, `ask_yes_no` |
| `razvertka-migrator.sh` | Поиск/загрузка `chirpstack-v3-to-v4` |
| `razvertka-install-fns.sh` | Вызовы `scripts/components/*` |
| `razvertka-backup.sh` | Бэкап БД |
| `razvertka-status.sh` | `--status` |
| `razvertka-migration.sh` | Миграция v3 → 4.11 |
| `razvertka-remove.sh` | Удаление / `--only-chirp` |
| `razvertka-run.sh` | `run_v3`/`v4`, меню компонентов |

```text
razvertka_uspd_components/
├── install.sh
├── README.md
├── tools/                    # при необходимости: chirpstack-v3-to-v4
├── scripts/
│   ├── backup-databases.sh   # → install.sh --backup
│   ├── show-install-status.sh
│   ├── remove-stack.sh
│   ├── upgrade-v3-to-v4.sh
│   ├── lib/
│   │   ├── razvertka-common.sh
│   │   ├── razvertka-migrator.sh
│   │   ├── razvertka-install-fns.sh
│   │   ├── razvertka-backup.sh
│   │   ├── razvertka-status.sh
│   │   ├── razvertka-migration.sh
│   │   ├── razvertka-remove.sh
│   │   └── razvertka-run.sh
│   └── components/           # установка пакетов (dpkg, конфиги)
│       ├── install-deps.sh
│       ├── install-mosquitto.sh
│       ├── install-redis.sh
│       ├── install-postgresql.sh
│       ├── install-chirpstack.sh
│       └── install-zabbix.sh
├── chirpstackv3/
│   ├── amd/
│   │   ├── chirpstack-gateway-bridge_*.deb
│   │   ├── chirpstack-network-server_*.deb
│   │   └── chirpstack-application-server_*.deb
│   └── arm/
│       ├── chirpstack-gateway-bridge_*.deb
│       ├── chirpstack-network-server_*.deb
│       └── chirpstack-application-server_*.deb
├── chirpstackv4/
│   ├── chirpstackv4_11/
│   │   ├── amd/chirpstack_*.deb
│   │   └── arm/chirpstack_*.deb
│   └── chirpstackv4_17/
│       ├── amd/
│       │   ├── chirpstack_*.deb
│       │   └── chirpstack-gateway-bridge_*.deb
│       └── arm/
│           ├── chirpstack_*.deb
│           └── chirpstack-gateway-bridge_*.deb
└── zabbix/
    ├── zabbix-agent2_*.deb
    ├── zabbix-release_*.deb
    └── zabbix_agent2.conf
```

## Откуда берутся пакеты

- **v3 установка:** `chirpstackv3/amd|arm` + `zabbix/`.
- **v4 установка:** `chirpstackv4/chirpstackv4_17/amd|arm` + `zabbix/`.
- **миграция v3 -> 4.11:**
  - gateway-bridge: `chirpstackv4/chirpstackv4_17/amd|arm`
  - core `chirpstack`: `chirpstackv4/chirpstackv4_11/amd|arm`
  - zabbix: `zabbix/`

## Миграция v3 -> 4.11

Сценарий `--upgrade`:
- проверяет наличие установленного v3;
- останавливает сервисы v3;
- делает бэкап `lora_as` и `lora_ns`;
- ставит/проверяет ChirpStack 4.11;
- **по умолчанию** пересоздаёт пустую БД PostgreSQL `chirpstack` (v4), чтобы убрать конфликты `idx_user_email` и следы прошлых попыток;
- поднимает `chirpstack` до появления схемы (таблица `public.user`), останавливает, затем очищает данные во всех `public` таблицах, **кроме** имён с `migration` (служебные миграции не трогаем) — иначе мигратор падает с `отношение "user" не существует`;
- запускает `chirpstack-v3-to-v4` (доп. флаги — по версии бинарника; смотри `tools/chirpstack-v3-to-v4 -h`);
- поднимает `chirpstack` и `chirpstack-gateway-bridge`.

**Какой бинарник используется:** скрипт сам выставляет `CHIRPSTACK_MIGRATOR_BIN`, если в `tools/` есть `chirpstack-v3-to-v4` или другой файл по маске `chirpstack-v3-to-v4*` (ручной `export` не нужен). Иначе: переменная окружения `CHIRPSTACK_MIGRATOR_BIN`, затем скачивание с GitHub, в последнюю очередь — `chirpstack-v3-to-v4` из `PATH`.

Отключить пересоздание БД `chirpstack` (если в v4 уже лежат нужные данные — редко):

```bash
sudo ./install.sh --upgrade --skip-clear-v4-db
```

Дополнительно к пересозданию БД можно передать мигратору `--drop-tenants-and-users`: `sudo ./install.sh --upgrade --migrator-drop-tenants-and-users`.

Примечание: флаг `--update-existing` есть не во всех сборках `chirpstack-v3-to-v4`.

## Перед запуском

- Пакеты лежат в правильных папках (`amd`/`arm`).
- Проверена архитектура целевого хоста (`amd64`/`arm64`).
- Проверен `zabbix/zabbix_agent2.conf`.
- Запуск только от root: `sudo ./install.sh`.
