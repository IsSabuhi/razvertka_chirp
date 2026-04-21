# Razvertka

Скрипт для развёртывания LoRaWAN-стека (ChirpStack + Zabbix Agent2) и запуска прикладного сервиса `LoraMes`.

## Что делает скрипт

- Устанавливает и настраивает ChirpStack v3 или v4.
- Настраивает сопутствующие сервисы: PostgreSQL, Mosquitto, Redis.
- Ставит и настраивает Zabbix Agent2.
- Поддерживает миграцию `v3 -> ChirpStack 4.11.x`: ядро из каталога `chirpstackv4.11.1_install/`, bridge — из `chirpstackv4&zabbix_install/amd|arm/`.
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

# Миграция v3 -> 4.11 (пакеты уже в репозитории, см. структуру ниже)
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
├── chirpstackv3&zabbix_install/
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
├── chirpstackv4&zabbix_install/
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
├── chirpstackv4.11.1_install/
│   ├── chirpstack_*_linux_amd64.deb
│   └── chirpstack_*_linux_arm64.deb
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

В репозитории уже зафиксированы каталоги и имена; `install.sh` читает их как есть (ничего перекладывать пользователю не нужно).

- **v3:** `install.sh` копирует `.deb` из `chirpv3x64` / `chirpv3ARM` в корень `chirpstackv3&zabbix_install/`, затем запускается `fast_razvertka.sh`.
- **v4 (обычная установка):** пакеты под архитектуру берутся из `chirpstackv4&zabbix_install/amd` или `arm`; передаётся `CHIRPSTACK_DEB_DIR=amd|arm`.
- **Миграция v3→4.11:** `chirpstack-gateway-bridge_*.deb` из `amd`/`arm`, пакет ядра `chirpstack_*.deb` — из `chirpstackv4.11.1_install/` (отдельно от «текущей» v4 в amd/arm). В `fast_razvertkav4.sh` используются `CHIRPSTACK_GATEWAY_DEB_DIR` и `CHIRPSTACK_CORE_DEB_DIR`.
- **Zabbix:** `zabbix-agent2_*.deb` в корне `chirpstackv4&zabbix_install/` или рядом с пакетами ChirpStack.

## Как обновлять версии пакетов

### ChirpStack v3

1. Обновить `.deb` в `chirpstackv3&zabbix_install/chirpv3x64` или `chirpv3ARM`.
2. Запустить `install.sh`, выбрать установку v3 и архитектуру пакетов.

### ChirpStack v4

1. Обновить `.deb` в `chirpstackv4&zabbix_install/amd` или `arm`.
2. Запустить `install.sh`, выбрать установку v4 и архитектуру пакетов.

### Zabbix Agent2

- Обновить `zabbix-agent2_*.deb` и при необходимости `zabbix_agent2.conf` в папках v3/v4.

## Миграция с v3 на ChirpStack 4.11

Через `install.sh` — пункт миграции или `sudo ./install.sh --upgrade`.

Используются **готовые** каталоги репозитория:

- `chirpstackv4&zabbix_install/amd/` или `arm/` — **только** `chirpstack-gateway-bridge_*.deb` (и при необходимости zabbix там же);
- `chirpstackv4.11.1_install/` — пакет ядра `chirpstack_*_linux_amd64.deb` или `chirpstack_*_linux_arm64.deb` (версия 4.11.x, в имени есть `4.11`);
- `zabbix-agent2_*.deb` — обычно в корне `chirpstackv4&zabbix_install/`.

Так в `amd`/`arm` может лежать актуальная полная v4 (например 4.17) для обычной установки, а для миграции ядро берётся отдельно из `chirpstackv4.11.1_install/`.

Сценарий:

- проверяет стек v3;
- если `chirpstack` уже **4.11.x**, шаг `fast_razvertkav4.sh` **пропускается**;
- иначе — `fast_razvertkav4.sh` с `CHIRPSTACK_GATEWAY_DEB_DIR=amd|arm` и `CHIRPSTACK_CORE_DEB_DIR=<каталог 4.11.1>`;
- останавливает v3, бэкап БД;
- запускает `chirpstack-v3-to-v4` (в `PATH` или `tools/chirpstack-v3-to-v4`).

После миграции при необходимости обновите `chirpstack` до новой v4 из `amd`/`arm`.

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
