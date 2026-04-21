# Razvertka

Скрипт для развёртывания LoRaWAN-стека (ChirpStack + Zabbix Agent2) и запуска прикладного сервиса `LoraMes`.

## Что делает скрипт

- Устанавливает и настраивает ChirpStack v3 или v4.
- Настраивает сопутствующие сервисы: PostgreSQL, Mosquitto, Redis.
- Ставит и настраивает Zabbix Agent2.
- Поддерживает миграцию `v3 -> ChirpStack 4.11.x` (отдельные пакеты в `chirp411-amd` / `chirp411-arm`).
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

# Миграция v3 -> 4.11 (пакеты 4.11 в chirp411-amd или chirp411-arm)
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
│   ├── arm/
│   │   ├── chirpstack_*.deb
│   │   └── chirpstack-gateway-bridge_*.deb
│   ├── chirp411-amd/
│   │   ├── chirpstack_4.11.*.deb
│   │   └── chirpstack-gateway-bridge_*.deb
│   └── chirp411-arm/
│       ├── chirpstack_4.11.*.deb
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

- Перед запуском установки нужные `.deb` должны лежать **рядом** с `fast_...sh` (в корне соответствующей папки).
- Подкаталоги `chirpv3x64`, `chirpv3ARM`, `amd`, `arm` используются как хранилище версий по архитектурам.
- В `install.sh` есть выбор архитектуры (`auto` / `amd64` / `arm64`), после выбора скрипт сам подготавливает `.deb` из нужной подпапки.

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

Перед этим положите **только** пакеты **ChirpStack 4.11.x** в каталог архитектуры:

- `chirpstackv4&zabbix - install/chirp411-amd/` — для amd64;
- `chirpstackv4&zabbix - install/chirp411-arm/` — для arm64.

В каталоге должны быть как минимум:

- `chirpstack_*.deb` (имя файла должно содержать `4.11`);
- `chirpstack-gateway-bridge_*.deb`.

`zabbix-agent2_*.deb` может лежать в корне `chirpstackv4&zabbix - install/` или копируется из `amd`/`arm` при подготовке.

Сценарий делает:

- проверку, что установлен только стек v3;
- если пакет `chirpstack` уже **4.11.x**, полная установка `fast_razvertkav4.sh` **пропускается** (остаётся миграция);
- иначе — подготовка `.deb` из `chirp411-*`, затем `fast_razvertkav4.sh` (зависимости, PostgreSQL, конфиги, установка 4.11);
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
