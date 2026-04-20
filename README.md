# Razvertka

Скрипт для развёртывания LoRaWAN-стека (ChirpStack + Zabbix Agent2) и запуска прикладного сервиса `LoraMes`.

## Что делает скрипт

- Устанавливает и настраивает ChirpStack v3 или v4.
- Настраивает сопутствующие сервисы: PostgreSQL, Mosquitto, Redis.
- Ставит и настраивает Zabbix Agent2.
- Поддерживает обновление `v3 -> v4` с миграцией данных.
- Поддерживает выборочное удаление компонентов.

## Точка входа

Главный скрипт запуска: `install.sh`.

Запуск:

```bash
cd /path/to/razvertka
sudo ./install.sh
```

Доступные сценарии через меню:

- Установка ChirpStack v3.
- Установка ChirpStack v4.
- Обновление ChirpStack `v3 -> v4` + миграция.
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

- Перед запуском установки нужные `.deb` должны лежать **рядом** с `fast_...sh` (в корне соответствующей папки).
- Подкаталоги `chirpv3x64`, `chirpv3ARM`, `amd`, `arm` используются как хранилище версий по архитектурам.
- Перед установкой скопируйте нужные файлы из архитектурной папки в корень:
  - `chirpstackv3&zabbix - install/` для v3.
  - `chirpstackv4&zabbix - install/` для v4.

Пример для v4 AMD64:

```bash
cd "chirpstackv4&zabbix - install"
cp amd/chirpstack_*.deb .
cp amd/chirpstack-gateway-bridge_*.deb .
```

## Как обновлять версии пакетов

### ChirpStack v3

1. Положить новые `.deb` в `chirpstackv3&zabbix - install/chirpv3x64` или `chirpv3ARM`.
2. Скопировать нужный набор в корень `chirpstackv3&zabbix - install/`.
3. Запустить `install.sh` и выбрать установку v3.

### ChirpStack v4

1. Положить новые `.deb` в `chirpstackv4&zabbix - install/amd` или `arm`.
2. Скопировать нужный набор в корень `chirpstackv4&zabbix - install/`.
3. Запустить `install.sh` и выбрать установку v4.

### Zabbix Agent2

- Обновить `zabbix-agent2_*.deb` и при необходимости `zabbix_agent2.conf` в папках v3/v4.

## Обновление с v3 на v4

Через `install.sh` выберите пункт `Обновление v3 -> v4 + миграция`.

Сценарий делает:

- остановку сервисов v3;
- бэкап БД v3 (`lora_as`, `lora_ns`);
- установку v4;
- попытку запуска миграции через `chirpstack migrate`.

Если формат команды миграции в вашей версии отличается, скрипт остановится с подсказкой, а бэкап останется.

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

- Нужные `.deb` лежат в правильной папке и скопированы в корень папки установки.
- Проверена архитектура целевого сервера (`amd64` / `arm64`).
- Подготовлены/проверены `zabbix_agent2.conf`.
- Скрипт запускается от root: `sudo ./install.sh`.
