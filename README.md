# Razvertka

Скрипт для развёртывания LoRaWAN-стека (ChirpStack + Zabbix Agent2) и запуска прикладного сервиса `LoraMes`.

## Что делает скрипт

- Устанавливает и настраивает ChirpStack v3 или v4.
- Настраивает сопутствующие сервисы: PostgreSQL, Mosquitto, Redis.
- Ставит и настраивает Zabbix Agent2.
- Поддерживает миграцию `v3 -> ChirpStack 4.11.x` (пакеты 4.11 лежат в `amd/` или `arm/` рядом с остальными).
- Поддерживает выборочное удаление компонентов.

## Точка входа

Главный скрипт запуска: `install.sh`.

Запуск:

```bash
cd /path/to/razvertka
sudo ./install.sh
```

Неинтерактивный запуск (через флаги):

```bash
# Установка v4 под amd64
sudo ./install.sh --v4 --arch amd64

# Миграция v3 -> 4.11 (положите chirpstack 4.11 в arm/ или amd/)
sudo ./install.sh --upgrade --arch arm64 --backup-dir /var/backups/chirpstack

# Удаление в режиме флагов (вопросы останутся, если не добавлять --yes)
sudo ./install.sh --remove
```

Доступные флаги:

- `--v3` / `--v4` / `--upgrade` / `--remove` — выбрать один режим.
- `--arch auto|amd64|arm64` — архитектура пакетов.
- `--backup-dir <path>` — путь для бэкапа БД при `--upgrade`.
- `--yes` — автоматически отвечать `yes` на подтверждения.
- `--help` — краткая справка.

Доступные сценарии через меню:

- Установка ChirpStack v3.
- Установка ChirpStack v4.
- Миграция v3 -> ChirpStack 4.11 + данные.
- Выборочное удаление компонентов.

## Строгая структура репозитория

Ниже структура, которой нужно придерживаться.

```text
razvertka/
├── install.sh
├── chirpstackv3&zabbix - install/
│   ├── fast_razvertka.sh
│   ├── zabbix_agent2.conf
│   ├── zabbix-agent2_*.deb
│   ├── zabbix-release_*.deb
│   ├── chirpv3x64/
│   │   ├── chirpstack-gateway-bridge_*.deb
│   │   ├── chirpstack-network-server_*.deb
│   │   └── chirpstack-application-server_*.deb
│   └── chirpv3ARM/
│       ├── chirpstack-gateway-bridge_*.deb
│       ├── chirpstack-network-server_*.deb
│       └── chirpstack-application-server_*.deb
├── chirpstackv4&zabbix - install/
│   ├── fast_razvertkav4.sh
│   ├── zabbix_agent2.conf
│   ├── zabbix-agent2_*.deb
│   ├── zabbix-release_*.deb
│   ├── amd/
│   │   ├── chirpstack_*.deb
│   │   └── chirpstack-gateway-bridge_*.deb
│   └── arm/
│       ├── chirpstack_*.deb
│       └── chirpstack-gateway-bridge_*.deb
└── LoraMes/
    ├── Lora.py
    ├── start.sh
    ├── LoraMes.service
    ├── cfg/
    │   └── <hostname>/
    │       └── DeviceList.json
    ├── paho/
    ├── pymodbus/
    └── pyModbusTCP/
```

## Важно про `.deb` пакеты

Скрипты `fast_razvertka.sh` и `fast_razvertkav4.sh` устанавливают пакеты по шаблонам из текущего каталога (например `dpkg -i chirpstack_*.deb`).

Это значит:

- Для **v3** скрипт копирует `.deb` из `chirpv3x64` / `chirpv3ARM` в корень каталога установки v3 (как раньше).
- Для **v4** и для **миграции v3→4.11** пакеты ChirpStack берутся **напрямую** из подкаталога `amd` или `arm` (копирование в корень не требуется); `install.sh` передаёт путь через переменную `CHIRPSTACK_DEB_DIR`.
- Zabbix Agent2: `zabbix-agent2_*.deb` может лежать в **корне** `chirpstackv4&zabbix - install/` или в том же `amd`/`arm`.

## Как обновлять версии пакетов

### ChirpStack v3

1. Положить новые `.deb` в `chirpstackv3&zabbix - install/chirpv3x64` или `chirpv3ARM`.
2. Запустить `install.sh`, выбрать установку v3 и архитектуру пакетов.

### ChirpStack v4

1. Положить новые `.deb` в `chirpstackv4&zabbix - install/amd` или `arm`.
2. Запустить `install.sh`, выбрать установку v4 и архитектуру пакетов.

### Zabbix Agent2

- Обновить `zabbix-agent2_*.deb` и при необходимости `zabbix_agent2.conf` в папках v3/v4.

## Миграция с v3 на ChirpStack 4.11

Через `install.sh` выберите пункт миграции v3 → 4.11 или запустите `sudo ./install.sh --upgrade`.

Положите пакеты **ChirpStack 4.11.x** в каталог архитектуры, который выберет скрипт:

- `chirpstackv4&zabbix - install/amd/` — для amd64;
- `chirpstackv4&zabbix - install/arm/` — для arm64.

В каталоге должны быть как минимум:

- `chirpstack_*.deb` (в имени файла должно быть **`4.11`** — так проверяет скрипт);
- `chirpstack-gateway-bridge_*.deb`.

`zabbix-agent2_*.deb` — в корне `chirpstackv4&zabbix - install/` или в том же `amd`/`arm`.

В папке `amd`/`arm` не держите одновременно два разных `chirpstack_*.deb` (например 4.11 и 4.17), иначе `dpkg` может установить не то.

Сценарий делает:

- проверку, что установлен только стек v3;
- если пакет `chirpstack` уже **4.11.x**, полная установка `fast_razvertkav4.sh` **пропускается** (остаётся миграция);
- иначе — `fast_razvertkav4.sh` с `CHIRPSTACK_DEB_DIR=amd|arm` (зависимости, PostgreSQL, конфиги, установка 4.11 из этой папки);
- остановку сервисов v3, бэкап БД `lora_as` / `lora_ns`;
- запуск миграции через утилиту `chirpstack-v3-to-v4` (в `PATH` или `tools/chirpstack-v3-to-v4`).

После успешной миграции при необходимости обновите `chirpstack` до более новой v4 уже из папок `amd`/`arm`.

## Выборочное удаление

Через `install.sh` доступно удаление по компонентам:

- пакеты ChirpStack (v3/v4, gateway-bridge);
- Zabbix Agent2;
- Mosquitto;
- Redis;
- отдельно: БД/роли PostgreSQL;
- отдельно: остаточные каталоги/данные.

Используйте осторожно на серверах, где PostgreSQL/Mosquitto/Redis используются другими сервисами.

## LoraMes: важное ограничение

В `LoraMes/start.sh` и `LoraMes/LoraMes.service` путь к рабочей директории сейчас жёстко зашит (`/home/smzis/Messs`).

Это текущая логика проекта. Если запуск делается на другом сервере/пути, эти файлы нужно адаптировать вручную.

## Рекомендации по эксплуатации

- Выполнять установку на чистой или заранее подготовленной Debian/Ubuntu-системе.
- Всегда запускать через `sudo`.
- Перед обновлением `v3 -> v4` проверять свободное место под бэкап БД.
- Перед удалением БД убеждаться, что они не используются другими сервисами.

## Краткий чек-лист перед запуском

- Нужные `.deb` лежат в правильной архитектурной папке (`chirpv3x64/chirpv3ARM` или `amd/arm`).
- Проверена архитектура целевого сервера (`amd64` / `arm64`).
- Подготовлены/проверены `zabbix_agent2.conf`.
- Скрипт запускается от root: `sudo ./install.sh`.
