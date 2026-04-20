# v1.26 +KrioLabTermoNew +decode_piezus_alz3720 +KrioLabTermoNew(T-patch)
# Эта строка импортирует модуль client из пакета paho.mqtt и присваивает ему псевдоним mqtt_client. Модуль paho.mqtt.client предоставляет функциональность для работы с протоколом MQTT
import platform
from paho.mqtt import client as mqtt_client
import traceback

from typing import List, Dict
# Эта строка импортирует модуль json, который предоставляет функции для работы с данными в формате JSON
import json

# Эта строка импортирует модуль base64, который предоставляет функции для кодирования и декодирования данных в формате Base64
import base64

# Модуль time позволяет получать текущее время, задерживать выполнение программы на определенное время, а также работать с временными метками и интервалами времени.
import time

# Модуль struct позволяет упаковывать и распаковывать данные в бинарном формате, а также выполнять преобразования между различными типами данных
import struct

# Модуль urllib позволяет выполнять различные операции, такие как открытие URL-адресов, чтение данных из сети и отправку HTTP-запросов.
import urllib

# Модуль math содержит функции для работы с числами, такие как вычисление тригонометрических функций, логарифмов, степеней, округления и других математических операций.
import math

# Модуль os позволяет выполнять различные операции с файлами и директориями, управлять переменными окружения, запускать команды в командной строке и многое другое.
import os

# Модуль для подключения к модбас устройства по TCP
from pymodbus.client import ModbusTcpClient as ModbusClient
from pymodbus.transaction import ModbusRtuFramer, ModbusBinaryFramer

import struct
import sys, os
# import mraa
import threading
import math
# import numpy as np
from datetime import datetime, timezone
import csv
import binascii
import socket
import re

with open(f"cfg/{str(platform.uname()[1])}/DeviceList.json", "r+") as f:
    DeviceList = json.load(f)

LoraWanDevice = []
ModbusDevice = []
BaseStation = {}
DeviceSetting = {}
ExternalMqttConf = {}
log_file = 'sensor_logs.csv'

#for x in DeviceList["devices"].filter(lambda x: x.get('type') == 'BS'):
 #   BaseStation[x.get('devEui')] = x.get('mqttName')

# for Device in DeviceList["devices"]:
#     DeviceSetting[Device["devEui"]] = Device
#     ExternalMqttConf.update({"object_code": Device["object_code"], "uspd_code": Device["uspd_code"]})
#     if Device["moxaip"] == "":
#         LoraWanDevice.append(Device["devEui"])
#     else:
#         ModbusDevice.append(Device["devEui"])
# print(f"Устройств LoraWaN записано для работы {len(LoraWanDevice)}")
# print(f"Устройств Modbus записано для работы {len(ModbusDevice)}")
# print(f"Номер УСПД {ExternalMqttConf['uspd_code']} код рокса {ExternalMqttConf['object_code']}")


ChangeTimeDeviceList = 0
def DeviceRead():
    global ChangeTimeDeviceList
    global DeviceSetting
    global ModbusDevice
    with open(f"cfg/{str(platform.uname()[1])}/DeviceList.json", "r") as f:
        DeviceList = json.load(f)
        DeviceSetting.clear()
        LoraWanDevice.clear()
        ModbusDevice.clear()
        for Device in DeviceList["devices"]:
            DeviceSetting[Device["devEui"]] = Device
            ExternalMqttConf.update({"object_code": Device["object_code"], "uspd_code": Device["uspd_code"]})
            if Device["moxaip"] == "":
                LoraWanDevice.append(Device["devEui"])
            else:
                ModbusDevice.append(Device["devEui"])
            ChangeTimeDeviceList = os.path.getctime(f"cfg/{str(platform.uname()[1])}/DeviceList.json")
        print(f"Устройств LoraWaN записано для работы {len(LoraWanDevice)}")
        print(f"Устройств Modbus записано для работы {len(ModbusDevice)}")
        print(f"Номер УСПД {ExternalMqttConf['uspd_code']} код рокса {ExternalMqttConf['object_code']}")
DeviceRead()


if not os.path.isfile(log_file):
    with open(log_file, mode='w', newline='') as file:
        writer = csv.writer(file)
        # Записываем заголовки
        writer.writerow(['timestamp', 'topic', 'data'])

def JsonDumbStat(data):
  sensorquant =  "Ubat" "," + "Pbat"
  return sensorquant


# Функция формирования топика
def set_topic(Setting_Object, target):
    type = Setting_Object.get("type") # Тип устройства  
    Name = Setting_Object.get("MqttName") # Имя в MQTT/ Код скважины
    ID = Setting_Object.get("object_id") # Код строения
    OCode = Setting_Object.get("object_code") # Код рокса
    UCode = Setting_Object.get("uspd_code") # Номер успд
    return  f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/{target}" # == /Gorizont/ObjectX/000001/USPD001/TK/001_BH001/from_device/measure



GatewayOnline = True
broker = "localhost"
port = 1883
DownMqttClient = (
    mqtt_client.Client()
)  # Создаем экземпляр клиента mqtt для дальнейшего обмена сообщениями с mqtt сервером
DownMqttClient.connect(broker, port)  # Подключаемся к брокеру mqtt
DownMqttClient.loop_start()  # Запускаем внешний цикл для обмена сообщениями с mqtt в отдельном потоке

DeviceList2 = {}



def UsterRead():
    global DeviceList2
    if os.path.isfile(f"cfg/{str(platform.uname()[1])}/JustifyValues.json"):
        with open(f"cfg/{str(platform.uname()[1])}/JustifyValues.json", "r+") as f:
            DeviceList2 = json.load(f)
            DeviceList2 = DeviceList2.get("justify")
            if os.path.isfile(f"cfg/{str(platform.uname()[1])}/NeedUpdate"):
                os.remove(f"cfg/{str(platform.uname()[1])}/NeedUpdate")
UsterRead()

def on_message(client, userdata, msg):
    global ChangeTimeDeviceList
    global DeviceSetting
    if msg.topic.endswith("/event/status") and msg.topic.startswith("application"):  # топик для получения статуса
        rx_json = json.loads(msg.payload)
        rx_devType = rx_json["applicationName"]
        rx_devEUI = base64.b64decode(rx_json["devEUI"])
        print("<<<" ,rx_devEUI.hex().upper() )
        if os.path.getctime(f"cfg/{str(platform.uname()[1])}/DeviceList.json") > ChangeTimeDeviceList:
            print("Обновление DeviceList")
            DeviceRead()
        NewPacket_id = rx_devEUI.hex().upper()
        if NewPacket_id in DeviceSetting:
            OneDevSet = DeviceSetting[NewPacket_id]
        try:
            if OneDevSet["moxaname"].lower() == "kriolab":
                NewPacket_id = rx_devEUI.hex().upper()
                # сохраняем значение Pbat для криолабов 
                # в отдельном ключе словаря, т.к. в коде ниже StatusDict[NewPacket_id] периодически очищается
                if 'krioPbats' not in StatusDict:
                    StatusDict['krioPbats'] = {}
                if NewPacket_id not in StatusDict['krioPbats']: 
                    StatusDict['krioPbats'][NewPacket_id] = {}
                if NewPacket_id in DeviceSetting:
                    OneDevSet = DeviceSetting[NewPacket_id]
                else:
                    print(f"У меня в DeviceList нету устройства {NewPacket_id}")
                if OneDevSet["type"] == "TK":

                    # сохраняем /обновляем значение Pbat в StatusDict
                    StatusDict['krioPbats'][NewPacket_id].update({'Pbat':int(rx_json['batteryLevel'])})
                    print(f"{NewPacket_id} StatusDict['krioPbats'][NewPacket_id]['Pbat']: {StatusDict['krioPbats'][NewPacket_id]['Pbat']}")

                    #
                    # Pbat из чирпа будет отправлен в мктт вместе с измерениями, если в пакете косы не будет своих данных о батарейке
                    #
                    # type = OneDevSet.get("type")
                    # Name = OneDevSet.get("MqttName")
                    # ID = OneDevSet.get("object_id")
                    # OCode = OneDevSet.get("object_code")
                    # UCode = OneDevSet.get("uspd_code")
                    # jsonstring2 = json.dumps({'Pbat':rx_json['batteryLevel']})
                    # snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                    # MQTTClient.publish(snd_topic_stat, jsonstring2)

        except Exception:
            traceback.print_exc()

    if msg.topic.endswith("/event/up") and msg.topic.startswith("application"):
        try:
            global DeviceList2
            rx_json = json.loads(msg.payload)
            rx_devEUI = base64.b64decode(rx_json["devEUI"])
            rx_data = base64.b64decode(rx_json["data"])
            rx_readable = " ".join(format(x,'02x') for x in rx_data)
            NewPacket_id = rx_devEUI.hex().upper()
            print("<<<" ,rx_devEUI.hex().upper())
            if os.path.getctime(f"cfg/{str(platform.uname()[1])}/DeviceList.json") > ChangeTimeDeviceList:
                print("Обновление DeviceList")
                DeviceRead()
            if NewPacket_id in DeviceSetting:
                OneDevSet = DeviceSetting[NewPacket_id]
                if OneDevSet["type"] == "TK":
                    Quantity = OneDevSet["q_a"]
                    print(f"Пакет от термокосы {OneDevSet}, {rx_readable}")
                elif OneDevSet["type"] == "INC":
                    print(f"Пакет от инклинометра {OneDevSet}, {rx_readable}")
                elif OneDevSet["type"] == "TZ":
                    print(f"Пакет от тензометра {OneDevSet}, {rx_readable}")
                elif OneDevSet["type"] == "PZ":
                    print(f"Пакет от пьезометра {OneDevSet}, {rx_readable}")
                elif OneDevSet["type"] == "TG":
                    print(f"Пакет от гидрометра {OneDevSet}, {rx_readable}")
            else:
                print(f"У меня в DeviceList нету устройства {NewPacket_id}")
                # Узнаем, новый ли это пакет или нет
             # Получаю настройки периода опроса датчика
            setting_time = OneDevSet.get("registers")
            if len(setting_time) == 0:
                setting_time = 240
            else:
                [setting_time] = OneDevSet.get("registers")
            if NewPacket_id not in WaitPacket:
                WaitPacket[NewPacket_id] = {"rx_time": time.time()}
                StatusDict[NewPacket_id] = {}
                rxInfo = rx_json.get("rxInfo")
                SignalLevel[NewPacket_id] = {
                    "rssi": rxInfo[0].get("rssi") if rxInfo else None,
                    "loRaSNR": rxInfo[0].get("loRaSNR") if rxInfo else None,
                    "deviceName": rx_json.get("deviceName"),
                    "SINR": rxInfo[0].get("loRaSNR") if rxInfo else None
                }
            else:
               if time.time() - WaitPacket[NewPacket_id]["rx_time"] > (int(setting_time) - 10) * 60:
                   WaitPacket[NewPacket_id] = {"rx_time": time.time()}
                   StatusDict[NewPacket_id] = {}
                   rxInfo = rx_json.get("rxInfo")
                   SignalLevel[NewPacket_id] = {
                       "rssi": rxInfo[0].get("rssi") if rxInfo else None,
                       "loRaSNR": rxInfo[0].get("loRaSNR") if rxInfo else None,
                       "deviceName": rx_json.get("deviceName"),
                       "SINR": rxInfo[0].get("loRaSNR") if rxInfo else None
                   }
            if NewPacket_id not in SendTime:
                SendTime[NewPacket_id] = [time.time()]
            if os.path.isfile(f"cfg/{str(platform.uname()[1])}/NeedUpdate"):
                UsterRead()
            if NewPacket_id not in StatusDict:
                WaitPacket[NewPacket_id] = {"rx_time": time.time()}
                StatusDict[NewPacket_id] = {}
                TimeDict[NewPacket_id] = []
    
            if rx_data[0] in [0x11, 0x06, 0x05, 0x1a, 0x01]:
                if (time.time() - SendTime[NewPacket_id][-1]) < (int(setting_time) - 10) * 60 or (time.time() - SendTime[NewPacket_id][-1]) > (int(setting_time) + 10) * 60:
                    if OneDevSet["moxaname"] == "Gorizont":
                        if OneDevSet["type"] in ["INC", "PZ", "TG", "TZ"]:
                            TimePacketDown(NewPacket_id, OneDevSet, msg)
                        elif OneDevSet["type"] == "TK" and NewPacket_id != "07293314052DFB1F":
                            First_sensor = rx_data.hex()[2:4]
                            if  int(First_sensor, 16) == 1:
                                TimePacketDown(NewPacket_id, OneDevSet, msg)
                    elif OneDevSet["moxaname"] == "Gorizont2":
                        if OneDevSet["type"] in ["INC", "TZ", "PZ", "TG"]:
                            TimePacketDown(NewPacket_id, OneDevSet, msg)
                        elif OneDevSet["type"] == "TK":
                            First_sensor = rx_data.hex()[2:4]
                            if  int(First_sensor, 16) == 1:
                                TimePacketDown(NewPacket_id, OneDevSet, msg)

            if OneDevSet["moxaname"] == "Gorizont":
                if (
                    OneDevSet["type"] == "INC"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Инклинометры
                    try:
                        IncliPacket(rx_json, rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TK"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Термокосы
                    try:
                        TermoPacket(rx_data, NewPacket_id, OneDevSet, rx_json)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TZ"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Инклинометр
                    try:
                        TenzoPacket(rx_data,rx_json, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "PZ"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04       
                ):
                    try:
                        PiezPacket(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TG"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04       
                ):
                    try:
                        GidPacket(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                if (
                rx_json["objectJSON"] == '{"pkt":"03","settings":"устройство запрашивает метку времени в формате id_pkt+UTS(4 bytes)"}'):
                    TimePacketUp(rx_data, NewPacket_id, msg)
                elif rx_data[0] == 0x14 or rx_data[0] == 0x15 or rx_data[0] == 0x16 or rx_data[0] == 0x04:
                    print ('<<<', rx_readable)
                elif rx_data[0] == 0x03:
                    TimePacketUp(rx_data, NewPacket_id, msg)

            
            elif OneDevSet["moxaname"] == "Gorizont2":
                if (
                    OneDevSet["type"] == "INC"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Инклинометры
                    try:
                        IncliPacket2(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TK"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Термокосы
                    try:
                        TermoPacket(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TZ"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04
                ):  # Инклинометр
                    try:
                        TenzoPacket(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "PZ"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04       
                ):
                    try:
                        PiezPacket(rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif (
                    OneDevSet["type"] == "TG"
                    and rx_data[0] != 0x03
                    and rx_data[0] != 0x14
                    and rx_data[0] != 0x15
                    and rx_data[0] != 0x16
                    and rx_data[0] != 0x04       
                ):
                    try:
                        GidPacket2(rx_json, rx_data, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                if (
                rx_json["objectJSON"] == '{"pkt":"03","settings":"устройство запрашивает метку времени в формате id_pkt+UTS(4 bytes)"}'):
                    TimePacketUp(rx_data, NewPacket_id, msg)
                elif rx_data[0] == 0x14 or rx_data[0] == 0x15 or rx_data[0] == 0x16 or rx_data[0] == 0x04:
                    print ('<<<', rx_readable)
                elif rx_data[0] == 0x03:
                    TimePacketUp(rx_data, NewPacket_id, msg)

            elif OneDevSet["moxaname"] == "Zetlab":
                if OneDevSet["type"] == "TK":
                    try:
                        ZetlabTermo(rx_json, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif OneDevSet["type"] == "TTK":
                    try:
                        ZetlabTermo2(rx_json, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
                elif OneDevSet["type"] == "INC":
                    try:
                        ZetlabIncli(rx_json, NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
            elif OneDevSet["moxaname"] == "Vega":
                try:
                    TermoPacketLora(rx_data, NewPacket_id, Quantity, msg, OneDevSet)
                except Exception:
                    traceback.print_exc()
            elif OneDevSet["moxaname"].lower() == "kriolab" and len(rx_json['data']) > 5:
                if OneDevSet["type"] == "TK":
                    try:
                        # KrioLabTermoOFF(rx_json, rx_json['data'], NewPacket_id, OneDevSet)
                        KrioLabTermoNew(rx_json, rx_json['data'], NewPacket_id, OneDevSet)
                    except Exception:
                        traceback.print_exc()
            elif OneDevSet["moxaname"].lower() == "vclass":
                if OneDevSet["type"] == "PZ":
                    try:
                        if rx_json.get('fPort') == 1:
                            decode_piezus_alz3720(rx_json, rx_data, NewPacket_id, OneDevSet)
                        else:
                            print(f"пакет не требует обработки (fPort={rx_json.get('fPort')})")
                    except Exception:
                        traceback.print_exc()
        except Exception:
            traceback.print_exc()
    if msg.topic.endswith("conn") and msg.topic.startswith("gateway"):
        try:
            rx_json = json.loads(msg.payload)
            rx_devEUI = base64.b64decode(rx_json["gatewayID"])
            NewPacket_id = rx_devEUI.hex().upper()
            print("<<<" ,rx_devEUI.hex().upper()," Статус БС")
            if os.path.getctime(f"cfg/{str(platform.uname()[1])}/DeviceList.json") > ChangeTimeDeviceList:
                print("Обновление DeviceList")
                DeviceRead()
            if NewPacket_id in DeviceSetting:
                OneDevSet = DeviceSetting[NewPacket_id]
                BaseStationStatus(rx_json, NewPacket_id, OneDevSet)
            else:
                print("Базовой станции нету в списке")
        except Exception as e:
            traceback.print_exc()
            print(f"Ошибка чтения статуса БС -- {e}")


                


InputDict = {}
StatusDict = {}
TimeDict = {}
SignalLevel = {}
SentSettings = {}
WaitPacket = {}
SendTime = {}


def on_connect(
    client, userdata, flags, rc
):  # Функция проверяет соединение с mqtt брокером
    if rc == 0:
        print("Connect OK")
    else:
        print("Connect Error")


def save_data(X,Y, DevEui):
        # Загрузить JSON-файл
       with open(f"cfg/{str(platform.uname()[1])}/ConfList.json", "r+") as fh:
            config = json.load(fh)
            # Найти и обновить данные датчика
            for dev in config["devices"]:
                if dev["devEui"] == DevEui:
                    dev["LastMessX"] = round(X,4)
                    dev["LastMessY"] = round(Y, 4)
                    break
            # Перезаписать JSON-файл
            fh.seek(0)
            json.dump(config, fh, indent=4)
            fh.truncate()


# def func_routed(f_x, f_y, angle=0):
#     new_f_x = f_x * np.cos(np.deg2rad(angle)) + f_y * np.sin(np.deg2rad(angle))
#     new_f_y = f_y * np.cos(np.deg2rad(angle)) - f_x * np.sin(np.deg2rad(angle))
#     return new_f_x, new_f_y
def BaseStationStatus(rx_json, ID_Object, Setting_Object):
    Status =  rx_json["state"]
    if Status.upper() == "ONLINE":
        statmesbs = 0
    else:
        statmesbs = 1
    type = Setting_Object.get("type")
    Name = Setting_Object.get("MqttName")
    ID = Setting_Object.get("object_id")
    OCode = Setting_Object.get("object_code")
    UCode = Setting_Object.get("uspd_code")
    BaseStation[ID_Object] = {}
    BaseStation[ID_Object].update({"Defect": statmesbs, "snd_topic" : f"/Gorizont/{OCode}/USPD/{UCode}/bs_{Name}/measure"})

    

def deg2rad(degrees):
    """Переводит градусы в радианы."""
    return degrees * math.pi / 180

def func_routed(f_x, f_y, angle=0):
    """Вращает вектор (f_x, f_y) на заданный угол."""
    rad_angle = deg2rad(angle)
    new_f_x = f_x * math.cos(rad_angle) + f_y * math.sin(rad_angle)
    new_f_y = f_y * math.cos(rad_angle) - f_x * math.sin(rad_angle)
    return new_f_x, new_f_y

def hex_convert(data):
    hex_string = format(int(data), '02x')
    return hex_string

def SplitZetData(ZetJs):
    str = ZetJs["objectJSON"]
    ZetDataJS = str.replace("\"", "")
    Zet = ZetDataJS.replace("{", "")
    ZetDataJson = Zet.replace("}", "")
    b = (ZetDataJson.split(","))
    SplitData = []
    for i in b:
        SplitData.append(i.split(":"))
    return SplitData

def byte_to_int8(byte_value):
            # Преобразуем байт в целое число
            if byte_value > 127:  # Если байт больше 127, делаем его знаковым
                return byte_value - 256
            return byte_value

def reverse_hex(hex_str): 
    return ''.join(reversed([hex_str[i:i+2] for i in range(0, len(hex_str), 2)])) 

def calc_depth(n):
    if n <= 11:
        return int((n - 1) / 2 * 100)
    elif n <= 16:
        return int((n - 6) * 100)
    else:
        return int((10 + (n - 16) * 2) * 100) 
    
def JsonDumbTerm2(data, First_sensor, Last_sensor):
    sensorquant = "Time"
    zero_deph = calc_depth(First_sensor)
    for i in range(int(First_sensor),int(Last_sensor + 1)):
        deph = calc_depth(i)
        sensorquant += str(","f"{deph - zero_deph}")
    return sensorquant
    
# Функция разбора пакетов пьезометра
def PiezPacket(DataP, ID_Object, Setting_Object):
    if DataP[0] == 0x1B:
        arr_meas_time = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 1])
        TimeHex = int.from_bytes(arr_meas_time, "big")
        meas_time_arr = bytearray()
        Temp_arr = bytearray()
        Pressure_arr = bytearray()
        for i in range(0, 4):  # сортируем данные пьезометра
            meas_time_arr.append(DataP[i + 1])
            Temp_arr.append(DataP[i + 5])
            Pressure_arr.append(DataP[i + 9])
        TimeHex = int.from_bytes(meas_time_arr, "big")
        Temp_arr2 = int.from_bytes(Temp_arr, "big")
        Pressure_arr2 = int.from_bytes(Pressure_arr, "big")
        Pressure = 222.35 + Pressure_arr2 / 10000
        print(Pressure)

        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"H": round(Pressure, 3)})
        # Если пришел статусный пакет, то вызываем функцию статусных пакетов
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
        # Если посылка полная, проверяем статус отправки статусов
    if len(WaitPacket[ID_Object]) == 17:
        if (
            WaitPacket[ID_Object]["SentStatusS"] == None
            and WaitPacket[ID_Object]["SentStatusV"] == None
        ):
            print("Статусные пакеты Пьезометра еще не были отправлены")
        else:
            print(f"Пакет измерений пьезометра {ID_Object} готов к отправке")
            if (
                WaitPacket[ID_Object]["Time"]
                and WaitPacket[ID_Object]["H"] != None
            ):
                print(f"Пакет пьезометра {ID_Object} готов к отправке")
                type = Setting_Object.get("type")
                Name = Setting_Object.get("MqttName")
                ID = Setting_Object.get("object_id")
                OCode = Setting_Object.get("object_code")
                UCode = Setting_Object.get("uspd_code")
                snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Time": None, "H": None})})
                MQTTClient.publish(snd_topic_mes, jsonstring1)
                print(">>>", ID_Object, jsonstring1)
                WaitPacket.pop(ID_Object)
                SendTime[ID_Object] = [time.time()]

    else:
        print(f"{ID_Object} не хватает статусных пакетов")
        print(f"{WaitPacket[ID_Object]}")
        print(f"{len(WaitPacket[ID_Object])}")


def decode_piezus_alz3720(rx_json, rx_data, ID_Object, Setting_Object):


    # (id + time + battery + status) - здесь у меня 7 байт (1, 4, 1, 1)
    if len(rx_data) < 16:
        # raise ValueError("Слишком короткий пакет")
        print("Слишком короткий пакет")
        return

    result = {}

    # разбор заголовка
    result["id"] = rx_data[0]
    result["time"] = struct.unpack_from("<I", rx_data, 1)[0]  # little-endian uint32
    result["battery_voltage"] = rx_data[5] * 0.1  
    common_status = rx_data[6]
    batlow = ((common_status & 0b00000010) >> 1) ^ 1
    print(batlow)
    #result["status"] = {
    #    "sensor": bool(common_status & 0b00000001),
    #    "battery": bool(common_status & 0b00000010),
    #    "external_power": bool(common_status & 0b00000100),
    #    "battery_power": bool(common_status & 0b00001000),
    #    "time_set": bool(common_status & 0b00010000),
    #    "memory_ok": bool(common_status & 0b00100000),
    #    "device_ok": bool(common_status & 0b01000000),
    #    "after_boot": bool(common_status & 0b10000000),
    #}
    #status_dev = format(common_status, '08b')
    
   # print(result["status"])
   # offset = 7
   # while offset + 9 <= len(rx_data):
    pressure = struct.unpack_from("<f", rx_data, 7)[0]
    t_sensor = struct.unpack_from("<f", rx_data, 11)[0]
    t_ksi = struct.unpack_from("<b", rx_data, 15)[0]
   # offset += 9

    Type = Setting_Object.get("type")
    Name = Setting_Object.get("MqttName")
    ID = Setting_Object.get("object_id")
    OCode = Setting_Object.get("object_code")
    UCode = Setting_Object.get("uspd_code")
    snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{Type}/{ID}_{Name}/from_device/status"
    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{Type}/{ID}_{Name}/from_device/measure"
    snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{Type}/{ID}_{Name}/from_device/status_ext"
    json_mesure = json.dumps({"Time": result["time"], "H": round(pressure,2), "T": round(t_sensor, 2)})

    json_status = json.dumps({"Status": common_status, "BT": round(t_ksi,2), "RSSI": rx_json['rxInfo'][0]['rssi'], 
                              'SINR': rx_json['rxInfo'][0].get('loRaSNR') or rx_json['rxInfo'][0].get('snr'), 
                              "Ubat": round(result["battery_voltage"],2), "BatLow": batlow})
    json_status_ext = json.dumps({'DevEUI' : ID_Object})
    MQTTClient.publish(snd_topic_mes, json_mesure)
    MQTTClient.publish(snd_topic_stat, json_status)
    MQTTClient.publish(snd_topic_stat_ext, json_status_ext)
    print(">>>", ID_Object, json_mesure)
    print(">>>", ID_Object, json_status)



def KrioLabTermoNew(rx_json, rx_data, ID_Object, Setting_Object):

    wp_local = WaitPacket
    sd_local = StatusDict


    def ib(b):
        return int.from_bytes(b, byteorder='big', signed=False)
    def ibs(b):
        return int.from_bytes(b, byteorder='big', signed=True)
    def hr(ba):
        if isinstance(ba, bytes):
            return list(format(x,'02x') for x in ba)
        else:
            return str(ba)
    def resetWP():
        wp_local[ID_Object] = {"rx_time": time.time()}
    
    packet = base64.b64decode(rx_json.get('data') or '') or [0]
    if packet[0] not in [0x34, 0x87, 0x88]:
        return

    packet_time = rx_json.get('publishedAt') or rx_json.get('time')
    
    try:
        packet_time_timestamp = int(datetime.fromisoformat(packet_time[0:19]).timestamp())
        if not wp_local[ID_Object].get('Time'):
            resetWP()
            wp_local[ID_Object].update({'Time': packet_time_timestamp})
            if len(rx_json.get('rxInfo') or []):
                rssi = list(map(lambda x: x.get('rssi') or 0, rx_json['rxInfo']))
                sinr = list(map(lambda x: x.get('snr') or x.get('loRaSNR') or 0, rx_json['rxInfo']))
                wp_local[ID_Object].update({
                    'RSSI': int(sum(rssi)/len(rssi)),
                    'SINR': int(sum(sinr)/len(sinr))
                })
    except:
        print(f'{ID_Object} no time in chirp packet {rx_json}')
        print(traceback.print_exc())
        resetWP()
        return

    # print(f'{ID_Object} получен пакет: {" ".join(hr(packet))}')
    #  /// rx_json: {rx_json}

    if packet[0] in [0x34, 0x87]:
        offset = 8 if packet[0] == 0x87 else 0
        total_packets = packet[3] if packet[0] == 0x87 else 1
        data_len = packet[14 + offset]
        wp_local[ID_Object].update({
                                    'number_of_packet': total_packets, 
                                    'packet_id':        packet[1:3] if packet[0] == 0x87 else b'',
                                    # packet_payload_array - массив с замерами, длина массива - общее кол-во пакетов,
                                    # будет заполняться по мере поступления пакетов, а когда заполнится - будет парсинг и пуш
                                    'packet_payload_array': [packet[15+offset:]] + [None] * (total_packets - 1), #15+offset+data_len
                                    'raw_packet_array': [packet] + [None] * (total_packets - 1),
                                    # общая длина
                                    'total_len': ib(packet[4:6]) if packet[0] == 0x87 else data_len,
                                    'extend_data_flags': packet[7 + offset],
                                    'SerialNumber': ib(packet[9+offset:13+offset]),
                                    'SerialNumberLogger': ib(packet[5+offset:7+offset]),
                                    'FirmwareVersion': float(str(ib(packet[3+offset:4+offset])) + '.' + str(ib(packet[4+offset:5+offset]))),
                                    'Defect': 0, # потом заменит на 1, если будет признак ошибки в доп.данных, но 0 это по умолчанию (ошибок нет)
                                    # 'Error': 0,
                                })
        
        # print(f'{ID_Object} начало сбора {wp_local[ID_Object]}')

    # пакет 88 с номером пакета
    elif packet[0] == 0x88:
        # проверка идентификатора пакета
        if wp_local[ID_Object].get('packet_id') != packet[1:3]:
            print(f'{ID_Object} чужой идентификатор пакета {" ".join(hr(packet)[1:3])}')
            resetWP()
            return
        else:
            data_len = packet[4]
            # packet[3] - порядковый номер пакета в общей посылке
            # помещаем замеры в соответствующий элемент массива packet_payload_array
            wp_local[ID_Object]['packet_payload_array'][packet[3]] = packet[5:] #5+data_len
            wp_local[ID_Object]['raw_packet_array'][packet[3]] = packet

    # все пакеты собраны в packet_payload_array
    if None not in (wp_local[ID_Object].get('packet_payload_array') or [None]):
        full_payload = b''.join(wp_local[ID_Object]['packet_payload_array'])
        # print(f'{ID_Object} все пакеты собраны {wp_local[ID_Object]} /// всего байт во всех пакетах {wp_local[ID_Object]["total_len"]} /// длина всех измерений {len(full_payload)} /// измерения вместе с доп.данными {" ".join(hr(full_payload))}')

        if wp_local[ID_Object]['extend_data_flags']:

            extend_data_flags = format(wp_local[ID_Object]['extend_data_flags'], '08b')
            extend_data_packets = bytearray()
            ext_map = {'memoryInfo':[4,4], 'deviceState': [5,4], 'logConfig': [6,2], 'timestamp': [7,4] }
            for x in ext_map.keys():
                if extend_data_flags[ext_map[x][0]] == '1':
                    ext_map[x].append(full_payload[-ext_map[x][1]:])
                    extend_data_packets = ext_map[x][2] + extend_data_packets
                    full_payload = full_payload[0:-ext_map[x][1]]

            wp_local[ID_Object].update({'ext_data': extend_data_packets, 'extend_data_flags_bin': extend_data_flags})

        if len(full_payload) % 2 != 0:
            print(f'{ID_Object} ОШИБКА /// нечетное количество байт в замерах {len(full_payload)}')
            resetWP()
            return
        else:

            # отрезает датчики с конца, если в девлисте указан q_a
            # заодно предусмотрен вариант с запятой (вырезает с N до M, если в девлисте "N,M")
                        # варианты для q_a:
                        # N = с 1 по N (если N > длины косы L, то с 1 по L)
                        # N,M = с N по M (если M > длины косы L, то с N по L)
                        # N, = с N до конца длины косы L
                        # ,M = с 1 по M (если M > длины косы L, то с 1 по L)
            q = ((Setting_Object.get('q_a') or '1,') + ',').split(',')
            if int(len(full_payload)/2) != int(q[0] or '0') and len(q) == 2:
                print(f"{ID_Object} ПРЕДУПРЕЖДЕНИЕ /// кол-во сенсоров ({int(len(full_payload)/2)}) будет усечено до значения в девлисте ({q[0]})")
            if len(q) > 2:
                print(f"{ID_Object} ПРЕДУПРЕЖДЕНИЕ /// кол-во сенсоров ({int(len(full_payload)/2)}) будет выбрано в диапазоне {','.join(q)}")

            if wp_local[ID_Object]['extend_data_flags']:
                # print(f'{ID_Object} /// флаги доп.данных: {extend_data_flags} /// доп.данные {" ".join(hr(extend_data_packets))} /// данные измерений {" ".join(hr(full_payload))}')

                # bit        7           6 5 4       3               2               1           0
                # положение флагов в байте доп.данных
                # name   SavedDataFlag Reserved MemoryInfoFlag DeviceStateFlag LogConfigFlag TimeStampFlag

                # положение блоков доп.данных в конце пакета
                # timestamp logConfig deviceState memoryInfo
                if extend_data_flags[7] == '1':
                    # TimeStampFlag
                    ext_val = ext_map['timestamp'][2]
                    if extend_data_flags[0] == '1':
                        # SavedData
                        print(f'{ID_Object} накопленные данные: Time {wp_local[ID_Object]["Time"]} смещение {ibs(ext_val)}')
                        wp_local[ID_Object]['Time'] = wp_local[ID_Object]['Time'] + ibs(ext_val)
                    else:
                        # No SavedData
                        print(f'{ID_Object} Time {wp_local[ID_Object]["Time"]} new Time from device {ib(ext_val)} + 946684800 = {ib(ext_val) + 946684800}')
                        wp_local[ID_Object]['Time'] = ib(ext_val) + 946684800
                        
                if extend_data_flags[6] == '1':
                    # logConfig
                    ext_val = ext_map['logConfig'][2]
                    wp_local[ID_Object]['MeasurePeriod'] = str(ext_val[0]) + ' ' + ['sec','min','hrs','day','mon'][ext_val[1]]

                if extend_data_flags[5] == '1':
                    # deviceState
                    ext_val = ext_map['deviceState'][2]
                    wp_local[ID_Object].update({
                        'Pbat'  : int(ext_val[0]/1.27),
                        'Error' : ext_val[2],
                        'T'     : ibs(ext_val[3:4]),
                        'Defect': 1 if ext_val[2] !=0 else 0
                    })

                    if ext_val[1]:
                        wp_local[ID_Object].update({'RSSI_device': -ext_val[1]})

                if extend_data_flags[4] == '1':
                    # memoryInfo
                    ext_val = ext_map['memoryInfo'][2]
                    wp_local[ID_Object]['MemInfo'] = str(ib(ext_val[0:2])) + ' kb total / ' + str(ib(ext_val[2:4])) + ' kb used'

            if len(q) > 2: # 'n,m,'
                full_payload = full_payload[(int(q[0] or '1')-1)*2:(int(q[1] or '0'))*2 or len(full_payload)]
            else:
                # отрежет, только если q_a не пустой
                if int(q[0]): full_payload = full_payload[0:int(q[0])*2]

            for x in range(0,len(full_payload),2):
                wp_local[ID_Object].update({f'Sensor{int(x/2+1)}': ibs(full_payload[x:x+2])/100})

            # не из девлиста, длина по факту
            wp_local[ID_Object].update({'Quantity':int(len(full_payload)/2)})

            # если нет уровня батарейки Pbat в доп.данных пакета
            if not wp_local[ID_Object].get('Pbat'):
                # если есть уровень батарейки Pbat от чирпа, сохраненный в StatusDict из последнего статусного пакета
                if ((sd_local.get('krioPbats') or {}).get(ID_Object) or {}).get('Pbat'):
                    # print(f"{ID_Object} Pbat из StatusDict['krioPbats'] {sd_local['krioPbats'][ID_Object]['Pbat']}")
                    wp_local[ID_Object].update({'Pbat': sd_local['krioPbats'][ID_Object]['Pbat']})
            else:
                # print(f"{ID_Object} Pbat из доп.данных {wp_local[ID_Object]['Pbat']}")
                pass

            # print(f'{ID_Object} все собрано {wp_local[ID_Object]}')
            measure_json = {key: wp_local[ID_Object][key] for key in filter(lambda x: len(list(filter(lambda y: re.match(y, x), 
                                    ['^(Sensor\d+|T|Time|Quantity)$']))), wp_local[ID_Object].keys())}

            # хардкорно убрал нули в версии прошивки
            if wp_local[ID_Object].get("FirmwareVersion") == 0: del wp_local[ID_Object]["FirmwareVersion"]

            status_json = {key: wp_local[ID_Object][key] for key in filter(lambda x: len(list(filter(lambda y: re.match(y, x), 
                                    ['^(FirmwareVersion|Pbat|RSSI|SINR|Error|Defect|SerialNumber)$']))), wp_local[ID_Object].keys())}

            # справочно
            ext_json = {key: 
                        list(map(lambda x: ' '.join(hr(x)), wp_local[ID_Object][key])) if key in ['packet_payload_array','raw_packet_array'] 
                        else ' '.join(hr(wp_local[ID_Object][key])) if key in ['ext_data','packet_id'] else wp_local[ID_Object][key] 
                        for key in filter(lambda x: x not in (list(status_json.keys())+list(measure_json.keys())), wp_local[ID_Object].keys())}

            print(f'{ID_Object} =========== MQTT push ============= /// measure: {measure_json} /// status: {status_json} /// ext_info: {ext_json}')

            resetWP()

            type = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
            MQTTClient.publish(snd_topic_mes, json.dumps(measure_json))
            MQTTClient.publish(snd_topic_stat, json.dumps(status_json))
            MQTTClient.publish(snd_topic_stat_ext, json.dumps({'DevEUI' : ID_Object}))
            # ext_info
            MQTTClient.publish(f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/ext_info", json.dumps(ext_json))

    return


def KrioLabTermoOFF(rx_json, rx_data, ID_Object, Setting_Object):
    rx_data = base64.b64decode(rx_data) 
    rx_data = rx_data.hex()
    #Записываем количество датчиков в WaitPacket
    Quantity = int(Setting_Object["q_a"])
    #Записываем информацию о количестве датчиков и серийном номере
    WaitPacket[ID_Object].update({"Quantity": Quantity})
    StatusDict[ID_Object].update({'SerialNumber': (Setting_Object.get('serial_number'))}) 
    #Определяем количество пакетов, задаём значение для DataFlag и добавляем в WaitPacket
    if rx_data[0:2] == '87':
        WaitPacket[ID_Object].update({'nubmer_of_packets':int(rx_data[6:8])})
        WaitPacket[ID_Object].update({'DataFlag': bin(int(rx_data[30:32], 16))[2:].zfill(8)})
        StatusDict[ID_Object].update({"FirmwareVersion" :  float(str(int(rx_data[22:24])) + "." + str(int(rx_data[24:26], 16)))})
    elif rx_data[0:2] == '34':
        WaitPacket[ID_Object].update({'nubmer_of_packets':1})
        WaitPacket[ID_Object].update({'DataFlag': bin(int(rx_data[14:16], 16))[2:].zfill(8)})
        StatusDict[ID_Object].update({"FirmwareVersion" :  float(str(int(rx_data[6:8])) + "." + str(int(rx_data[8:10], 16)))})
    if StatusDict[ID_Object]["FirmwareVersion"] >= 1.18:
        #Определяем сколько доп. данных в конце пакета
        DataFlagLen =  (int(WaitPacket[ID_Object]['DataFlag'][7]) + int(WaitPacket[ID_Object]['DataFlag'][5]) + int(WaitPacket[ID_Object]['DataFlag'][4])) * 8 + int(WaitPacket[ID_Object]['DataFlag'][6]) * 4 
        print(ID_Object, DataFlagLen, WaitPacket[ID_Object]['DataFlag'])
        #Создаём пустую переменную. Этот костыль для дальнейшенго кода
        score_packet = ''
        #Создаём пустые сенсоры, чтобы в дальнейшем заполнить
        if "Sensor1" not in WaitPacket[ID_Object]:
            for j in range(1, Quantity + 1):
                WaitPacket[ID_Object].update({f"Sensor{j}": None})
        #Заполняем данные, если один пакет всего
        if WaitPacket[ID_Object]['nubmer_of_packets'] == 1:
            print(ID_Object, '1 пакет от термокосы')
            score_packet = rx_data[30:len(rx_data)]
            for i in range(0, Quantity):
                if f"Sensor{i + 1}" in WaitPacket[ID_Object]:
                    try:
                        b = int(score_packet[i*4:i*4+4], 16)
                        if b >= 0x8000:
                            b -= 0x10000                    
                        WaitPacket[ID_Object].update({f"Sensor{i + 1}": b / 100})
                        print(ID_Object, f"Sensor{i + 1}", b / 100)
                    except ValueError:
                        print(ID_Object, 'Некорректный пакет: ', rx_data)
        #Заполняем данные, если несколько пакетов
        else:
            if "packet_1" not in WaitPacket[ID_Object]:
                for j in range(1, WaitPacket[ID_Object]['nubmer_of_packets'] + 1):
                    WaitPacket[ID_Object].update({f"packet_{j}": None})
            packet_in_queue = int(rx_data[6:8])
            if  packet_in_queue == WaitPacket[ID_Object]['nubmer_of_packets']:
                WaitPacket[ID_Object].update({"packet_1": rx_data[46:100]})
            elif packet_in_queue != WaitPacket[ID_Object]['nubmer_of_packets']:
                WaitPacket[ID_Object].update({f"packet_{packet_in_queue + 1}": rx_data[10:len(rx_data)]})
            try:
                for i in range(1, WaitPacket[ID_Object]['nubmer_of_packets'] + 1):
                    score_packet += WaitPacket[ID_Object][f'packet_{i}']
            except TypeError:
                print(ID_Object, 'Пришли не все пакеты!')
            if Quantity * 4 <= len(score_packet):
                for i in range(0, Quantity):
                    b = int(score_packet[i*4:i*4+4], 16)
                    if b >= 0x8000:
                        b -= 0x10000
                    WaitPacket[ID_Object].update({f"Sensor{i + 1}": b / 100})
            print(ID_Object, WaitPacket[ID_Object]['DataFlag'], WaitPacket[ID_Object])
        if int(rx_data[0:2]) == 34 or int(rx_data[0:2]) == (87 + WaitPacket[ID_Object]['nubmer_of_packets'] - 1):
            DataFlafInfo = score_packet[-int(DataFlagLen):]
        #Записываем время пакета, добавляем в WaitPacket
            print(ID_Object, score_packet)
            if score_packet and int(WaitPacket[ID_Object]['DataFlag'][7]):
                if int(WaitPacket[ID_Object]['DataFlag'][0]) == 0:
                    final_time = int(DataFlafInfo[:8], 16) + 946684800
                    WaitPacket[ID_Object].update({"Time": final_time})
                elif int(WaitPacket[ID_Object]['DataFlag'][0]) == 1:
                    final_time = int(DataFlafInfo[:8], 16) - 0x100000000 + int(time.time())
                    WaitPacket[ID_Object].update({"Time": final_time})
            else:
                time_string = rx_json["publishedAt"]
                time_part = time_string[:23]
                time_object = datetime.fromisoformat(time_part).replace(tzinfo=timezone.utc)
                unix_time = time_object.timestamp()
                if int(WaitPacket[ID_Object]['DataFlag'][0]) == 0:
                    WaitPacket[ID_Object].update({"Time": int(unix_time)})
                elif int(WaitPacket[ID_Object]['DataFlag'][0]) == 1:
                    final_time = int(unix_time) - 0x100000000 + int(time.time())
                    WaitPacket[ID_Object].update({"Time": final_time})
            #Записываем информацию о состоянии устройства, добавляем в WaitPacket
            if score_packet and int(WaitPacket[ID_Object]['DataFlag'][5]):
                start_point_period = int(WaitPacket[ID_Object]['DataFlag'][4]) * 8
                status_info = DataFlafInfo[-start_point_period -8: -start_point_period]
                baterry_level = int(status_info[0:2], 16) / 1.27
                error = int(status_info[4:6], 16)
                temp = int(status_info[6:8], 16)
                StatusDict[ID_Object].update({"T": temp})
                if int(error) != 0:
                    StatusDict[ID_Object].update({"Defect": 1})
                else:
                    StatusDict[ID_Object].update({"Defect": 0})
                StatusDict[ID_Object].update({"Error": error})
                StatusDict[ID_Object].update({"Pbat": int(baterry_level)})
                StatusDict[ID_Object].update({"RSSI": rx_json['rxInfo'][0]['rssi']})
                StatusDict[ID_Object].update({"SINR": rx_json['rxInfo'][0]['loRaSNR']})
                StatusDict[ID_Object].update({'SerialNumber': int(Setting_Object.get('serial_number'))})
                jsonstring2 = json.dumps({key: StatusDict[ID_Object][key] for key in StatusDict[ID_Object]})
                snd_topic_stat = set_topic(Setting_Object, target="status")
                print(ID_Object, jsonstring2)
                MQTTClient.publish(snd_topic_stat, jsonstring2)
                StatusDict.pop(ID_Object)
            else:
                StatusDict[ID_Object].update({"RSSI": rx_json['rxInfo'][0]['rssi']})
                StatusDict[ID_Object].update({"SINR": rx_json['rxInfo'][0]['loRaSNR']})
                StatusDict[ID_Object].update({'SerialNumber': int(Setting_Object.get('serial_number'))})
                jsonstring2 = json.dumps({key: StatusDict[ID_Object][key] for key in StatusDict[ID_Object]})
                snd_topic_stat = set_topic(Setting_Object, target="status")
                print(ID_Object, jsonstring2)
                MQTTClient.publish(snd_topic_stat, jsonstring2)
                StatusDict.pop(ID_Object)
        if None not in WaitPacket[ID_Object].values():
            type_tk = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type_tk}/{ID}_{Name}/from_device/measure"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type_tk}/{ID}_{Name}/from_device/status_ext"
            jsonstring = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm(WaitPacket[ID_Object]))})
            jsonstring3 = json.dumps({'DevEUI' : ID_Object})
            print(ID_Object, jsonstring, jsonstring3)
            MQTTClient.publish(snd_topic_mes, jsonstring)
            MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
            WaitPacket.pop(ID_Object)
    else:
        time_string = rx_json["publishedAt"]
        time_part = time_string[:23]
        time_object = datetime.fromisoformat(time_part).replace(tzinfo=timezone.utc)
        unix_time = time_object.timestamp()
        if (rx_data[0:2] == '87' and rx_data[30:32] == '00') or (rx_data[0:2] == '34' and rx_data[14:16] == '00'):
            WaitPacket[ID_Object].update({"Time": int(unix_time)})
            WaitPacket[ID_Object].update({'SavedData': 'No'})
        elif (rx_data[0:2] == '87' and rx_data[30:32] == '89') or (rx_data[0:2] == '34' and rx_data[14:16] == '89'):
            WaitPacket[ID_Object].update({"SavedData": 'Yes'})
            print(ID_Object, 'Накопленные данные!')
        print(ID_Object, WaitPacket[ID_Object].get('SavedData'))
        if int(rx_data[0:2]) - WaitPacket[ID_Object]['nubmer_of_packets'] + 1 == 87 and WaitPacket[ID_Object].get('SavedData') == 'Yes':
            saved_time = int(rx_data[-16:-8], 16) - 0x100000000 + int(time.time())
            WaitPacket[ID_Object].update({"Time": saved_time})
        WaitPacket[ID_Object].update({"Quantity": Quantity})
        StatusDict[ID_Object].update({'SerialNumber': int(Setting_Object.get('serial_number'))}) 
        StatusDict[ID_Object].update({'RSSI': rx_json['rxInfo'][0]['rssi']})   
        StatusDict[ID_Object].update({'SINR': rx_json['rxInfo'][0]['loRaSNR']})
        if "Sensor1" not in WaitPacket[ID_Object]:
            for j in range(1, Quantity + 1):
                WaitPacket[ID_Object].update({f"Sensor{j}": None})
        if WaitPacket[ID_Object]['nubmer_of_packets'] == 1:
            print(ID_Object, '1 пакет от термокосы')
            usefull_data = rx_data[30:len(rx_data)]
            for i in range(0, Quantity):
                if f"Sensor{i + 1}" in WaitPacket[ID_Object]:
                    try:
                        b = int(usefull_data[i*4:i*4+4], 16)
                        if b >= 0x8000:
                            b -= 0x10000                    
                        WaitPacket[ID_Object].update({f"Sensor{i + 1}": b / 100})
                    except ValueError:
                        print(ID_Object, 'Некорректный пакет: ', rx_data)
        else:
            if "packet_1" not in WaitPacket[ID_Object]:
                for j in range(1, WaitPacket[ID_Object]['nubmer_of_packets'] + 1):
                    WaitPacket[ID_Object].update({f"packet_{j}": None})
            packet_in_queue = int(rx_data[6:8])
            if  packet_in_queue == WaitPacket[ID_Object]['nubmer_of_packets']:
                WaitPacket[ID_Object].update({"packet_1": rx_data[46:100]})
            elif packet_in_queue != WaitPacket[ID_Object]['nubmer_of_packets'] and WaitPacket[ID_Object]['SavedData'] != 'Yes':
                WaitPacket[ID_Object].update({f"packet_{packet_in_queue + 1}": rx_data[10:len(rx_data)]})
            elif packet_in_queue != WaitPacket[ID_Object]['nubmer_of_packets'] and WaitPacket[ID_Object]['SavedData'] == 'Yes':
                WaitPacket[ID_Object].update({f"packet_{packet_in_queue + 1}": rx_data[10:len(rx_data) - 16]})
            score_packet = ''
            try:
                for i in range(1, WaitPacket[ID_Object]['nubmer_of_packets'] + 1):
                    score_packet += WaitPacket[ID_Object][f'packet_{i}']
            except TypeError:
                print(ID_Object, 'Пришли не все пакеты!')
            print(ID_Object, score_packet, WaitPacket[ID_Object])
            if Quantity * 4 <= len(score_packet):
                for i in range(0, Quantity):
                    b = int(score_packet[i*4:i*4+4], 16)
                    if b >= 0x8000:
                        b -= 0x10000
                    WaitPacket[ID_Object].update({f"Sensor{i + 1}": b / 100})
            print(ID_Object, WaitPacket[ID_Object])
        if None not in WaitPacket[ID_Object].values():

            # удялаем ключ с нулем в версии прошивки
            if StatusDict[ID_Object].get("FirmwareVersion") == 0: del StatusDict[ID_Object]["FirmwareVersion"]

            type = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
            jsonstring = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm(WaitPacket[ID_Object]))})
            jsonstring2 = json.dumps({key: StatusDict[ID_Object][key] for key in StatusDict[ID_Object]})
            jsonstring3 = json.dumps({'DevEUI' : ID_Object})
            print(ID_Object, jsonstring, jsonstring2, jsonstring3)
            MQTTClient.publish(snd_topic_mes, jsonstring)
            MQTTClient.publish(snd_topic_stat, jsonstring2)
            MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
            WaitPacket.pop(ID_Object)
            StatusDict.pop(ID_Object)


def ZetlabTermo(ZetJs, ID_Object, Setting_Object):
    if "objectJSON" in ZetJs:
        Quantity = int(Setting_Object["q_a"])
        ZetDataM = ZetJs["objectJSON"]
        ZetData = json.loads(ZetDataM)
        if "Pbat" not in StatusDict[ID_Object]:
            StatusDict[ID_Object].update({"Pbat": None}) 
        if "Ubat" not in StatusDict[ID_Object]:
            StatusDict[ID_Object].update({"Ubat": None})
        if "Sensor1" not in WaitPacket[ID_Object]:
            for j in range(1, Quantity + 1):
                WaitPacket[ID_Object].update({f"Sensor{j}": None})
        if "analogInput" in ZetData:
            if "254" in ZetData["analogInput"]:
                WaitPacket[ID_Object].update({"Ubat": ZetData["analogInput"]["254"]})
            if "253" in ZetData["analogInput"]:
                WaitPacket[ID_Object].update({"T": ZetData["analogInput"]["253"]})
            try:
                for i in ZetData["analogInput"]:
                    br = int(i) + 1   
                    if f"Sensor{br}" in WaitPacket[ID_Object]:
                        WaitPacket[ID_Object].update({f"Sensor{br}": ZetData["analogInput"][i]})
            except Exception as e:
                print(f"Ошибка сбора данных с сенсор {br}, --- {e}")
        WaitPacket[ID_Object].update({"Quantity": Quantity})
        time_string = ZetJs["publishedAt"]
        time_string_formatted = time_string[:-4] + 'Z'
        time_string_formatted = time_string_formatted.replace("Z", "")
        date_part, time_part = time_string_formatted.split("T")
        time_part = time_part[:12]
        time_string_proper = f"{date_part}T{time_part}"
        time_object = datetime.fromisoformat(time_string_proper).replace(tzinfo=timezone.utc)
        unix_time = time_object.timestamp()
        WaitPacket[ID_Object].update({"Time": int(unix_time)})
        WaitPacket[ID_Object].update({'RSSI': ZetJs['rxInfo'][0]['rssi']})   
        WaitPacket[ID_Object].update({'SINR': ZetJs['rxInfo'][0]['loRaSNR']})
        if "digitalInput" in ZetData:
            if "250" in ZetData["digitalInput"]:
                try:
                    if int(ZetData["digitalInput"]["250"]) != 0:
                        WaitPacket[ID_Object].update({"Defect": "1"})
                        type = Setting_Object.get("type")
                        Name = Setting_Object.get("MqttName")
                        ID = Setting_Object.get("object_id")
                        OCode = Setting_Object.get("object_code")
                        UCode = Setting_Object.get("uspd_code")
                        snd_topic_status_err = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                        jsonstatus = json.dumps({"Defect": "1", "Error": ZetData["digitalInput"]["250"]})
                        MQTTClient.publish(snd_topic_status_err, jsonstatus)
                except Exception:
                    traceback.print_exc()
            else:
                WaitPacket[ID_Object].update({"Defect": 0})
                WaitPacket[ID_Object].update({"Error": 0})
        if "temperatureSensor" in ZetData:
            WaitPacket[ID_Object].update({"T": ZetData["temperatureSensor"]["253"]})
    if "batteryLevel" in ZetJs:
        WaitPacket[ID_Object].update({"Pbat": ZetJs["batteryLevel"]})
    if None not in WaitPacket[ID_Object].values():
        if len(WaitPacket[ID_Object]) >= 4 + Quantity:
            type = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
            jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm(WaitPacket[ID_Object]))})
            jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Ubat": None, "SINR": None, "RSSI": None,"Defect": None, "Pbat": None, "Error": None})})
            jsonstring3 = json.dumps({'DevEUI' : ID_Object})
            print(jsonstring1)
            print(jsonstring2)
            MQTTClient.publish(snd_topic_mes, jsonstring1)
            MQTTClient.publish(snd_topic_stat, jsonstring2)
            MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
            WaitPacket.pop(ID_Object)
    else:
        print(WaitPacket[ID_Object])

 

def IncliPacket2(DataP, ID_Object, Setting_Object):
    global DeviceList2
    arr_meas_time = bytearray()
    ang_x_arr = bytearray()
    ang_y_arr = bytearray()
    if DataP[0] == 0x01:
        ang_x_arr = bytearray()
        ang_y_arr = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 2])
        for i in range(0, 4):
            ang_x_arr.append(DataP[9 - i])
            ang_y_arr.append(DataP[13 - i])
        TimeHex = int.from_bytes(arr_meas_time, "big")
        [ang_x] = struct.unpack("f", ang_x_arr)
        [ang_y] = struct.unpack("f", ang_y_arr)
        Mx = ang_x
        My = ang_y
        if len(str(Setting_Object["q_a"])) != 0:
            Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
        else:
            Mes_angle = func_routed(Mx, My, angle=0)
        Dx = Mes_angle[0]
        Dy = Mes_angle[1]
        if DeviceList2.get(ID_Object):
            ustX = DeviceList2[ID_Object].get("X") or 0
            ustY = DeviceList2[ID_Object].get("Y") or 0
        else:
            ustX = 0
            ustY = 0
        MesX = Dx / 3600
        MesY = Dy / 3600
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
        WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
        WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
        WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
        # Вызов статусного разбора пакета
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
        # Проверяем размер посылки
    if DataP[0] == 0x01 and len(WaitPacket[ID_Object]) >= 16:
        # Проверяем статус и время статусных пакетов
        if (
            WaitPacket[ID_Object]["SentStatusS"] == None
            and WaitPacket[ID_Object]["SentStatusV"] == None
            or time.time() - WaitPacket[ID_Object]["Time0x13"]
            or time.time() - WaitPacket[ID_Object]["Time0x12"] > 900
        ):
            print("Статусные пакеты Инклинометра еще не были отправлены")
        else:
            print(f"Пакет измерений Инклинометра {ID_Object} готов к отправке")
    if (
        DataP[0] == 0x01
        and WaitPacket[ID_Object]["Time"] != None
        and WaitPacket[ID_Object]["X"] != None
        and WaitPacket[ID_Object]["Y"] != None
    ):
        print(f"Пакет инклинометра {ID_Object} готов к отправке")
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        # Публикуем и удаляем пакет
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
        MQTTClient.publish(snd_topic_mes, jsonstring2)
        print(WaitPacket[ID_Object])
        if DataP[1] > 1:
            try:
                ang_x_arr = bytearray()
                ang_y_arr = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[16:20])
                for i in range(0, 4):
                    ang_x_arr.append(DataP[23 - i])
                    ang_y_arr.append(DataP[27 - i])
                [ang_x] = struct.unpack("f", ang_x_arr)
                [ang_y] = struct.unpack("f", ang_y_arr)
                Mx = ang_x
                My = ang_y
                if len(str(Setting_Object["q_a"])) != 0:
                    Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
                else:
                    Mes_angle = func_routed(Mx, My, angle=0)
                Dx = Mes_angle[0]
                Dy = Mes_angle[1]
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("X") or 0
                    ustY = DeviceList2[ID_Object].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                MesX = Dx / 3600
                MesY = Dy / 3600
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
                WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
                WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
                WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
                jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2)
            except Exception as e:
                traceback.print_exc()
        if DataP[1] > 2:
            try:
                ang_x_arr = bytearray()
                ang_y_arr = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[16:20])
                for i in range(0, 4):
                    ang_x_arr.append(DataP[37 - i])
                    ang_y_arr.append(DataP[41 - i])
                [ang_x] = struct.unpack("f", ang_x_arr)
                [ang_y] = struct.unpack("f", ang_y_arr)
                Mx = ang_x
                My = ang_y
                if len(str(Setting_Object["q_a"])) != 0:
                    Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
                else:
                    Mes_angle = func_routed(Mx, My, angle=0)
                Dx = Mes_angle[0]
                Dy = Mes_angle[1]
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("X") or 0
                    ustY = DeviceList2[ID_Object].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                MesX = Dx / 3600
                MesY = Dy / 3600
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
                WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
                WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
                WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
                jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2)
            except Exception as e:
                traceback.print_exc()
        WaitPacket.pop(ID_Object)    
        SendTime[ID_Object] = [time.time()]
       
def ZetlabTermo2(ZetJs, ID_Object, Setting_Object):
    if "objectJSON" in ZetJs:
        qaa = Setting_Object["q_a"].split(',') if ',' in Setting_Object["q_a"] else Setting_Object["q_a"]
        if type(qaa) == list:
            Quantity = int(qaa[0])
            First_sensor = int(qaa[1])
        else:
            First_sensor = 1
            Quantity = int(qaa)
        ZetDataM = ZetJs["objectJSON"]
        ZetData = json.loads(ZetDataM)
        if "Pbat" not in StatusDict[ID_Object]:
            StatusDict[ID_Object].update({"Pbat": None}) 
        if "Ubat" not in StatusDict[ID_Object]:
            StatusDict[ID_Object].update({"Ubat": None})
        if "analogInput" in ZetData:
            if "254" in ZetData["analogInput"]:
                StatusDict[ID_Object].update({"Ubat": ZetData["analogInput"]["254"]})
            if "253" in ZetData["analogInput"]:
                WaitPacket[ID_Object].update({"T": ZetData["analogInput"]["253"]})
        if "0" not in WaitPacket[ID_Object]:
            for j in range(First_sensor, Quantity + 1):
                deph = calc_depth(j)
                ZeroDeph = calc_depth(First_sensor)
                WaitPacket[ID_Object].update({f"{deph - ZeroDeph}": None})
        for i in ZetData["analogInput"]:
            br = int(i) + 1
            ZeroDeph = calc_depth(First_sensor)
            deph = calc_depth(br)
            print(f"{deph-ZeroDeph}")
            if f"{deph-ZeroDeph}" in WaitPacket[ID_Object]:
                WaitPacket[ID_Object].update({f"{deph-ZeroDeph}": ZetData["analogInput"][i]})
        WaitPacket[ID_Object].update({"Quantity": Quantity})
        time_string = ZetJs["publishedAt"]
        time_string_formatted = time_string[:-4] + 'Z'
        time_string_formatted = time_string_formatted.replace("Z", "")
        date_part, time_part = time_string_formatted.split("T")
        time_part = time_part[:12]
        time_string_proper = f"{date_part}T{time_part}"
        time_object = datetime.fromisoformat(time_string_proper).replace(tzinfo=timezone.utc)
        unix_time = time_object.timestamp()
        WaitPacket[ID_Object].update({"Time": int(unix_time)})
        if "digitalInput" in ZetData:
            if "0" in ZetData["digitalInput"]:
                try:
                    WaitPacket[ID_Object].update({"ErrTK": ZetData["digitalInput"]["0"]})
                except:
                    WaitPacket[ID_Object].update({"ErrTK": 1})
                WaitPacket[ID_Object].update({"Defect": 1})
            else:
                WaitPacket[ID_Object].update({"Defect": 0})
        if "temperatureSensor" in ZetData:
            WaitPacket[ID_Object].update({"T": ZetData["temperatureSensor"]["253"]})
    if "batteryLevel" in ZetJs:
        StatusDict[ID_Object].update({"Pbat": ZetJs["batteryLevel"]})
    if None not in StatusDict[ID_Object].values():
        if len(StatusDict[ID_Object]) == 2:
            typetk = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{typetk}/{ID}_{Name}/from_device/status"
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{typetk}/{ID}_{Name}/from_device/measure"
            jsonstring1 = json.dumps({key: StatusDict[ID_Object][key] for key in StatusDict[ID_Object] if key in (JsonDumbStat(StatusDict[ID_Object]))})
            MQTTClient.publish(snd_topic_stat, jsonstring1)
            StatusDict.pop(ID_Object)
            print(jsonstring1)

    else:
        print(StatusDict[ID_Object])
    if None not in WaitPacket[ID_Object].values():
        if len(WaitPacket[ID_Object]) >= 4 + Quantity - First_sensor:
            typetk = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{typetk}/{ID}_{Name}/from_device/status"
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{typetk}/{ID}_{Name}/from_device/measure"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{typetk}/{ID}_{Name}/from_device/status"
            jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm2(WaitPacket[ID_Object], First_sensor , Quantity))})
            jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"ErrTK": None,"Defect": None})})
            jsonstring3 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"DevEUI": str(ID_Object)})})
            print(jsonstring1)
            print(jsonstring2)
            MQTTClient.publish(snd_topic_mes, jsonstring1)
            MQTTClient.publish(snd_topic_stat, jsonstring2)
            MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
            WaitPacket.pop(ID_Object)
            print(jsonstring2)
    else:
        print(WaitPacket[ID_Object])

def ZetlabIncli(ZetJs, ID_Object, Setting_Object):
    global DeviceList2
    if "objectJSON" in ZetJs:
        ZetDataM = ZetJs["objectJSON"]
        ZetData = json.loads(ZetDataM)
        Ubat = (ZetData["analogInput"]["254"])
        Pbat = (ZetData["temperatureSensor"]["253"])
        SensorXx = (ZetData["gpsLocation"]["0"]['latitude'])
        SensorYy = (ZetData["gpsLocation"]["0"]['longitude'])
        SensorX = float(SensorXx)
        SensorY = float(SensorYy)
        if "Pbat" not in StatusDict[ID_Object]:
            StatusDict[ID_Object].update({"Pbat": None})
        WaitPacket[ID_Object].update({"Ubat": Ubat})
        if "0" in ZetData["digitalInput"]:
            try:
                WaitPacket[ID_Object].update({"Error": ZetData["digitalInput"]["0"]})
            except:
                traceback.print_exc()
            WaitPacket[ID_Object].update({"Defect": 1})
        else:
            WaitPacket[ID_Object].update({"Defect": 0})
            WaitPacket[ID_Object].update({"Error": 0})
        time_string = ZetJs["publishedAt"]
        time_string_formatted = time_string[:-4] + 'Z'
        time_string_formatted = time_string_formatted.replace("Z", "")
        date_part, time_part = time_string_formatted.split("T")
        time_part = time_part[:12]
        time_string_proper = f"{date_part}T{time_part}"
        time_object = datetime.fromisoformat(time_string_proper).replace(tzinfo=timezone.utc)
        unix_time = time_object.timestamp()
        WaitPacket[ID_Object].update({"Time": int(unix_time)})
        WaitPacket[ID_Object].update({"X": SensorX })
        WaitPacket[ID_Object].update({"Y": SensorY})
        WaitPacket[ID_Object].update({"T": Pbat})
        WaitPacket[ID_Object].update({'RSSI': ZetJs['rxInfo'][0]['rssi']})   
        WaitPacket[ID_Object].update({'SINR': ZetJs['rxInfo'][0]['loRaSNR']})
        Dx = SensorX *3600
        Dy = SensorY *3600
        if DeviceList2.get(ID_Object):
            ustX = DeviceList2[ID_Object].get("X") or 0
            ustY = DeviceList2[ID_Object].get("Y") or 0
        else:
            ustX = 0
            ustY = 0
        WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
        WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})

    if "batteryLevel" in ZetJs:
        StatusDict[ID_Object].update({"Pbat": ZetJs["batteryLevel"]})
    if None not in StatusDict[ID_Object].values():
        if len(StatusDict[ID_Object]) >= 4:
            if len(WaitPacket[ID_Object]) >=5:
                type = Setting_Object.get("type")
                Name = Setting_Object.get("MqttName")
                ID = Setting_Object.get("object_id")
                OCode = Setting_Object.get("object_code")
                UCode = Setting_Object.get("uspd_code")
                snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                jsonstring1 = json.dumps({key: StatusDict[ID_Object][key] for key in StatusDict[ID_Object] if key in ({"Ubat": None, "Pbat": None})})
                MQTTClient.publish(snd_topic_stat, jsonstring1)
                StatusDict.pop(ID_Object)
            
    if None not in WaitPacket[ID_Object].values():
        if len(WaitPacket[ID_Object]) >=7:
            type = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
            snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
            snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
            jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"RSSI": None, "SINR": None,  "Defect": None, "Ubat": None, "Error": None})})
            jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
            jsonstring3 = json.dumps({'DevEUI' : ID_Object})
            MQTTClient.publish(snd_topic_stat, jsonstring2)
            MQTTClient.publish(snd_topic_mes, jsonstring1)
            MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
            print(jsonstring1)
            print(jsonstring3)
            print(jsonstring2)
            WaitPacket.pop(ID_Object)
    

def TermoPacket(DataP, ID_Object, Setting_Object, rx_json):
    count = -2
    First_sensor = DataP.hex()[2:4]
    Last_sensor = DataP.hex()[4:6]
    Quantity = int(Setting_Object["q_a"])
    if DataP[0] == 0x05:
        arr_meas_time = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 3])
        TimeHex = int.from_bytes(arr_meas_time, "big")
    if DataP[0] == 0x05:
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"Quantity": Quantity})
        WaitPacket[ID_Object].update({"First_device": int(First_sensor, 16)})
        WaitPacket[ID_Object].update({"Last_device": int(Last_sensor, 16)})
        # Создаем ключи под измерения сенсоров, если их нет
        if "Sensor1" not in WaitPacket[ID_Object]:
            for j in range(1, Quantity + 1):
                WaitPacket[ID_Object].update({f"Sensor{j}": None})
                # Разбираем пакет на измерения
        if int(First_sensor, 16) <= int(Last_sensor, 16):
            for i in range(int(First_sensor, 16), int(Last_sensor, 16) + 1):
                count += 2
                first_step = 7 + count
                next_step = 9 + count
                Tk_Data = DataP[
                    first_step:next_step
                ]  # \x05\ t\ x10e\  x1b\  x9d\  x18\  xfe\xfe\ xfe\xec\ xfe\xdf\ xfe\xc6\ xfe\xbf\ xfe\xc0\ xfe\xc0\ xfe\xc6
                if Tk_Data:
                    TK_Data_Bytes_big = int.from_bytes(Tk_Data, "big", signed=True) / 100
                    if f"Sensor{i}" in WaitPacket[ID_Object]:
                        if WaitPacket[ID_Object][f"Sensor{i}"] == None:
                            WaitPacket[ID_Object].update({f"Sensor{i}": str(TK_Data_Bytes_big)})
                            print(f"Показания устройства  Сенсор - {i} записан")
                        else:
                            print(f"Показания сенсора  {i} уже был добавлен в пакет")
                else:
                    print(f"{Tk_Data}, измерения нету в пакете")
        else:
            for i in range(int(First_sensor, 16), int(Last_sensor, 16)- 1 ,-1):
                count += 2
                first_step = 7 + count
                next_step = 9 + count
                Tk_Data = DataP[
                    first_step:next_step
                ]  # \x05\ t\ x10e\  x1b\  x9d\  x18\  xfe\xfe\ xfe\xec\ xfe\xdf\ xfe\xc6\ xfe\xbf\ xfe\xc0\ xfe\xc0\ xfe\xc6
                if Tk_Data:
                    TK_Data_Bytes_big = int.from_bytes(Tk_Data, "big", signed=True) / 100
                    if f"Sensor{i}" in WaitPacket[ID_Object]:
                        if WaitPacket[ID_Object][f"Sensor{i}"] == None:
                            WaitPacket[ID_Object].update({f"Sensor{i}": str(TK_Data_Bytes_big)})
                            print(f"Показания устройства  Сенсор - {i} записан")
                        else:
                            print(f"Показания сенсора  {i} уже был добавлен в пакет")
                else:
                    print(f"{Tk_Data}, измерения нету в пакете")
                # Проверяем запись измерения
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
    if DataP[0] == 0x02:
        [Ubat] = struct.unpack(">f", DataP[1:5])
        if DataP[7] == 0:
            WaitPacket[ID_Object].update({"Defect": 0})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        else:
            WaitPacket[ID_Object].update({"Defect": 1})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        FM_ver = float(DataP[21]) + float(DataP[22] / 100)
        WaitPacket[ID_Object].update({"FirmwareVersion": FM_ver })
        WaitPacket[ID_Object].update({"Ubat": round(Ubat, 2)})
        WaitPacket[ID_Object].update({"Pbat": DataP[5]})
        WaitPacket[ID_Object].update({'RSSI': rx_json['rxInfo'][0]['rssi']})   
        WaitPacket[ID_Object].update({'SINR': rx_json['rxInfo'][0]['loRaSNR']})
        WaitPacket[ID_Object].update({"SerialNumber": struct.unpack(">I", DataP[13:17])[0]})
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        jsonstring_ext = json.dumps({"DevEUI": str(ID_Object)})
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Pbat": None, "SINR": None, "RSSI": None, "Defect": None, "Error": None, "FirmwareVersion": None, "SerialNumber": None})})
        MQTTClient.publish(snd_topic_stat, jsonstring2)
        MQTTClient.publish(snd_topic_stat_ext, jsonstring_ext)
        print(jsonstring2)
    if None not in WaitPacket[ID_Object].values() and DataP[0] == 0x05:
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        # Заполняем по порядку все измерения и публикуем. Потом удаляем пакет.
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm(WaitPacket[ID_Object]))})
        MQTTClient.publish(snd_topic_mes, jsonstring2)
        printTopic =  str(WaitPacket[ID_Object]["Time"]) , str(Quantity)
        print(">>>", ID_Object, jsonstring2)
        WaitPacket.pop(ID_Object)
        SendTime[ID_Object].append(time.time())
 
    # Проверяем размер, посылки. Если все хорошо, то проверяем отправку статусных пакетов
    # if (
    #     len(WaitPacket[ID_Object]) == Quantity + 4 + 11
    #     and None not in WaitPacket[ID_Object].values()
    # ):
    #     if (
    #         WaitPacket[ID_Object]["SentStatusS"] == None
    #         and WaitPacket[ID_Object]["SentStatusV"] == None
    #     ):
    #         print("Статусные пакеты еще не были отправлены")
    #     else:
    #         print(" 11 статусных и", Quantity, "измерительных готов к отправке.")
            # Готовим измеренеия к отправке


def TimePacketUp(DataP, ID_Object, msg):
    time_sync = int(time.time())
    time_sync_arr = bytearray()
    time_sync_arr.append(3)
    time_bytes = time_sync.to_bytes(4, byteorder="big")
    for i in range(0,4):
        time_sync_arr.append(time_bytes[i])
    if len(DataP) != 1:
        print("Время ап")
        for i in range(0,4):
            time_sync_arr.append(DataP[i + 1])
    time_sync_arr_hex = time_sync_arr.hex()
    sendArr = base64.b64encode(time_sync_arr)
    print(time_sync_arr_hex)
    sendArrB64 = sendArr.decode("ascii")
    print(sendArrB64)
    SettingsDict = {
        "confirmed": False,
        "fPort": 60,
        "data": sendArrB64,
    }
    SettingsJson = json.dumps(SettingsDict)
    array_from_topic = msg.topic.split("/")
    topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
    print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
    DownMqttClient.publish(topic_for_settings, SettingsJson)


def TimePacketDown(ID_Object, Setting_Object, msg):
    setting_time = Setting_Object.get("registers")
    if len(setting_time) == 0:
        setting_time = 240
    else:
        setting_time = int(setting_time[0])
    timesd_2bytes = f"{int(hex(setting_time), 16):04x}"  # timesd_2bytes = '00f0'
    print(timesd_2bytes)
    tx_data = bytes.fromhex(f"04{timesd_2bytes}0009{timesd_2bytes}0909003C000000000000000000{timesd_2bytes}")
    sendArrB64 = base64.b64encode(tx_data)
    sendArrB64str = sendArrB64.decode('ascii')
    SettingsDict = {"confirmed": False, "fPort": 60, "data": sendArrB64str}
    SettingsJson = json.dumps(SettingsDict)
    array_from_topic = msg.topic.split("/")
    topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
    # топик для синхронизации времени
    print(topic_for_settings)
    print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
    DownMqttClient.publish(topic_for_settings, SettingsJson)
    SentSettings[ID_Object] = False

def StatusPacket(DataP, ID_Object, Setting_Object):
    Ubat_arr = bytearray()
    if DataP[0] == 0x13:
        for i in range(1, 5):
            Ubat_arr.append(DataP[5 - i])
        [Ubat] = struct.unpack("f", Ubat_arr)
        Pbat = round(((Ubat - 3.0) / (3.6 - 3.0)) * 100.0)
        WaitPacket[ID_Object].update({"Ubat": round(Ubat, 3)})
        WaitPacket[ID_Object].update({"Pbat": Pbat})
        WaitPacket[ID_Object].update({"SentStatusV": None})
        WaitPacket[ID_Object].update({"Time0x12": time.time()})
        WaitPacket[ID_Object].update({"RSSI": str(SignalLevel[ID_Object]["rssi"])})
        WaitPacket[ID_Object].update({"SINR": str(SignalLevel[ID_Object]["loRaSNR"])})
        WaitPacket[ID_Object].update({"DevEUI": ID_Object.lower()})
    if DataP[0] == 0x12:
        FM_ver = float(DataP[5]) + float(DataP[6] / 100)
        WaitPacket[ID_Object].update({"FirmwareVersion": FM_ver})
        WaitPacket[ID_Object].update({"Time0x13": time.time()})
        WaitPacket[ID_Object].update({"SentStatusS": None})
        if FM_ver >= 4.42:
            def byte_to_int8(byte_value):
                # Преобразуем байт в целое число
                if byte_value > 127:  # Если байт больше 127, делаем его знаковым
                    return byte_value - 256
                return byte_value
            WaitPacket[ID_Object].update({"T": byte_to_int8(DataP[2])})
            print(WaitPacket[ID_Object]["T"])
        if DataP[1] == 0 or DataP[1] == 30:
            WaitPacket[ID_Object].update({"Defect": "0"})
            WaitPacket[ID_Object].update({"Status": "1"})
            WaitPacket[ID_Object].update({"Error": 0})
            
        else:
            WaitPacket[ID_Object].update({"Defect": "1"})
            WaitPacket[ID_Object].update({"Status": "0"})
            WaitPacket[ID_Object].update({"Error": DataP[1]})
            # Создаем топик под 13й пакет
    if DataP[0] == 0x13:
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        DeviceName = Setting_Object.get("serial_number")
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        snd_topic_stat2 = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        WaitPacket[ID_Object].update({"DeviceName": DeviceName})
        # Создаем топик под 12й пакет
    if DataP[0] == 0x12:
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        DeviceName = Setting_Object.get("serial_number")
        snd_topic_stat2 = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        WaitPacket[ID_Object].update({"SerialNumber": DeviceName})
        # Если пришли оба пакета статуса, собираем их на отправку
    if (
        "SentStatusV" in WaitPacket[ID_Object]
        and "SentStatusS" in WaitPacket[ID_Object]
    ):  
        res_stat = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({ "Defect": None , "Pbat": None , "Status": None, "Error": None, "Ubat": None, "RSSI": None, "SINR": None, "SerialNumber" : None, "FirmwareVersion": None})})
        res_stat2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"DevEUI": None})})
        MQTTClient.publish(snd_topic_stat2, res_stat2)
        # Публикуем статус, и записываем флаг для пакетов измерения, что статусные пакеты ранее были отправлены
        MQTTClient.publish(snd_topic_stat, res_stat)
        MQTTClient.publish(snd_topic_stat2, res_stat2)
        WaitPacket[ID_Object].update({"SentStatusV": True})
        WaitPacket[ID_Object].update({"SentStatusS": True})


def TermoPacketLora(rx_data,ID_Object,Quantity, msg, Setting_Object): 
    print(rx_data.hex()) 
    bytes_to_find = bytes([0x0d]) 
    index = rx_data.find(bytes_to_find) 
    SensorNum = {0:0,2:1,3:5,4:9,5:13,6:17,7:21,8:25,9:29,10:33} 
    type = rx_data[0]
    if rx_data[0] == 0x0b:
        index = 6
    elif rx_data[0] == 0x0a:
        index = 20
    if index != -1 and rx_data[0] != 0xc3: 
        print(f"Последовательность найдена начиная с позиции: {index}") 
        mesure = rx_data[index:] 
        mesure.hex() 
        type = mesure[0] 
        LenPckt = mesure[1]
        BiteLen = 8 
        BitAddr = - 9
        if LenPckt >= 45:
            print("Длина не верна")
        else:
            if rx_data[0] == 0x0a or rx_data[0] == 0x0b:
                if "Sensor1" not in WaitPacket[ID_Object]: 
                    for j in range(1, int(Quantity) + 1): 
                        WaitPacket[ID_Object].update({f"Sensor{j}": None}) 
                    for i in range(1, 5): 
                        WaitPacket[ID_Object].update({f"Status{i}": None}) 
                    WaitPacket[ID_Object].update({f"Time": None})
                    WaitPacket[ID_Object].update({f"Defect": None})
                    WaitPacket[ID_Object].update({"Quantity": Quantity})
                for i in range(1, LenPckt%8 + 1): 
                    BitAddr+= 9 
                    head = mesure[2+BitAddr] 
                    binary_num = format(head, '08b') 
                    FuncNum = (binary_num[:4]) 
                    FuncNumDec = int(FuncNum, 2)
                    if FuncNumDec >  10:
                        print("Адрес регистра не верен")
                    else:
                        BitNum = binary_num[4:] 
                        BitNumDec = int(BitNum, 2) 
                        BiteLen = 8 - BitNumDec 
                        data = mesure[3+BitAddr:11+BitAddr - BiteLen] 
                        TK_Data_Bytes_big = int.from_bytes(data, "big")
                        if TK_Data_Bytes_big and TK_Data_Bytes_big != 111494685545288:
                            mask_16bit = 0xFFFF 
                            registers = [] 
                            def twos_complement(value, bits=16): 
                                if value & (1 << (bits - 1)): 
                                    value -= 1 << bits 
                                return value 
                            for i in range(4): 
                                register = (TK_Data_Bytes_big >> (16 * (3 - i))) & mask_16bit 
                                register_signed = twos_complement(register) 
                                registers.append(register_signed) 
                            if FuncNumDec == 1 or FuncNumDec == 10:
                                if FuncNumDec == 1:
                                    for i, reg in enumerate(registers, 1): 
                                        print(f'Register {i}: {reg}') 
                                        CompleteMessure = reg 
                                        WaitPacket[ID_Object].update({f"Status{i}": CompleteMessure}) 
                                if FuncNumDec == 10:
                                    for i, reg in enumerate(registers, 1): 
                                        print(f'Register {i}: {reg}') 
                                        CompleteMessure = reg
                                        if i == 1:
                                            if reg != 0:
                                                WaitPacket[ID_Object].update({"Defect": 0})
                                                WaitPacket[ID_Object].update({"Status" : 1})
                                                break
                                            if reg <= 0:
                                                WaitPacket[ID_Object].update({"Defect": 1})
                                                WaitPacket[ID_Object].update({"Status" : 0})
                                                break
                            else:      
                                for i, reg in enumerate(registers, SensorNum[FuncNumDec]): 
                                    print(f'Register {i}: {reg / 100}') 
                                    CompleteMessure = reg / 100 
                                    if f"Sensor{i}" in WaitPacket[ID_Object]: 
                                        WaitPacket[ID_Object].update({f"Sensor{i}": CompleteMessure}) 
    if rx_data[0] == 0x0a or rx_data[0] == 10:
        hex_str = rx_data[2:6].hex()
        reversed_bytes = bytes.fromhex(hex_str)[::-1]
        timestamp = int.from_bytes(reversed_bytes, byteorder='big', signed=False)
        print(f"{timestamp} ЭТО МОЕ ТЕКУЩЕЕ ВРЕМЯ В ПАКЕТЕ Я ЕГО ОТПРАВЛЮ НАВЕРХ!!!")
        WaitPacket[ID_Object].update({f"Time": int(timestamp)})
        if time.time() - timestamp > 18000 or time.time() - timestamp < -18000:
            SettingsDict = {
                "confirmed": False,
                "fPort": 3,
                "data": "ADEAAQIQAAEC",
            }
            SettingsJson = json.dumps(SettingsDict)
            array_from_topic = msg.topic.split("/")
            topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
            print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
    if rx_data[0] == 0xff or rx_data[0] == 255: 
        hex_str = rx_data[1:5].hex()
        reversed_bytes = bytes.fromhex(hex_str)[::-1] 
        # Преобразуем из байт в целочисленное значение 
        timestamp = int.from_bytes(reversed_bytes, byteorder='big', signed=False) 
        # Преобразуем Unix Timestamp в читаемый формат UTC 
        utc_time = time.gmtime(timestamp) 
        print(timestamp) 
        # Выводим время в UTC 
        formatted_time = time.strftime('%Y-%m-%d %H:%M:%S', utc_time)
        print(formatted_time)
        CorrectTime = int(time.time()) - timestamp 
        if CorrectTime < -18000: 
            print(CorrectTime) 
            hex_num = hex(CorrectTime & (1 << 32) - 1) 
            print(hex_num[2:])   
            reversed_hex = reverse_hex(hex_num[2:]) 
            final_hex = "ff" + reversed_hex 
            lenHex = 18 - len(final_hex) 
            final_hex = final_hex + "f" * lenHex 
            print(final_hex)    
            print(len(final_hex)) 
            byte_data = bytes.fromhex(final_hex) 
            base64_str = base64.b64encode(byte_data) 
            sendArrB64 = base64_str.decode("ascii") 
            print(sendArrB64)
            SettingsDict = {
                "confirmed": False,
                "fPort": 4,
                "data": sendArrB64,
            }
            SettingsJson = json.dumps(SettingsDict)
            array_from_topic = msg.topic.split("/")
            topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
            print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
            DownMqttClient.publish(topic_for_settings, SettingsJson)
        if CorrectTime > 18000: 
            print(CorrectTime) 
            hex_num =hex(CorrectTime) 
            print(hex_num[2:]) 
            reversed_hex = reverse_hex(hex_num[2:]) 
            final_hex = "ff" + reversed_hex 
            lenHex = 18 - len(final_hex) 
            final_hex = final_hex + "0" * lenHex 
            print(final_hex)   
            byte_data = bytes.fromhex(final_hex) 
            base64_str = base64.b64encode(byte_data) 
            sendArrB64 = base64_str.decode("ascii") 
            print(sendArrB64)
            SettingsDict = {
                "confirmed": False,
                "fPort": 4,
                "data": sendArrB64,
            }
            SettingsJson = json.dumps(SettingsDict)
            array_from_topic = msg.topic.split("/")
            topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
            print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
            DownMqttClient.publish(topic_for_settings, SettingsJson)

    if None not in WaitPacket[ID_Object].values() and "Sensor1" in WaitPacket[ID_Object]: 
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        DeviceName = Setting_Object.get("serial_number")
        WaitPacket[ID_Object].update({f"SerialNumber": DeviceName}) 
        WaitPacket[ID_Object].update({f"DevEUI": ID_Object.lower()}) 
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        snd_topic_stat_ext = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTerm(WaitPacket[ID_Object]))})
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Defect": None, "SerialNumber": None, "Status": None})})
        jsonstring3 = json.dumps({'DevEUI' : ID_Object})
        MQTTClient.publish(snd_topic_mes, jsonstring1)
        MQTTClient.publish(snd_topic_stat, jsonstring2)
        MQTTClient.publish(snd_topic_stat_ext, jsonstring3)
        WaitPacket.pop(ID_Object)
        if time.time() - SendTime[ID_Object][-1] <= 7200:
            SettingsDict = {
                "confirmed": False,
                "fPort": 3,
                "data": "ADEAAQIQAAEC",
            }
            SettingsJson = json.dumps(SettingsDict)
            array_from_topic = msg.topic.split("/")
            topic_for_settings = f"{array_from_topic[0]}/{array_from_topic[1]}/{array_from_topic[2]}/{array_from_topic[3]}/command/down"
            print(f"отправка новых настроек {SettingsDict} на устройство {ID_Object}")
            #DownMqttClient.publish(topic_for_settings, SettingsJson)
        SendTime[ID_Object] = [time.time()]


def IncliPacket(rx_json, DataP, ID_Object, Setting_Object):
    global DeviceList2
    arr_meas_time = bytearray()
    ang_x_arr = bytearray()
    ang_y_arr = bytearray()
    if DataP[0] == 0x11:
        ang_x_arr = bytearray()
        ang_y_arr = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 1])
        for i in range(0, 4):
            ang_x_arr.append(DataP[8 - i])
            ang_y_arr.append(DataP[12 - i])
        TimeHex = int.from_bytes(arr_meas_time, "big")
        [ang_x] = struct.unpack("f", ang_x_arr)
        [ang_y] = struct.unpack("f", ang_y_arr)
        Mx = ang_x
        My = ang_y
        if len(str(Setting_Object["q_a"])) != 0:
            Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
        else:
            Mes_angle = func_routed(Mx, My, angle=0)
        Dx = Mes_angle[0]
        Dy = Mes_angle[1]
        if DeviceList2.get(ID_Object):
            ustX = DeviceList2[ID_Object].get("X") or 0
            ustY = DeviceList2[ID_Object].get("Y") or 0
        else:
            ustX = 0
            ustY = 0
        MesX = Dx / 3600
        MesY = Dy / 3600
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
        WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
        WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
        WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
        # Вызов статусного разбора пакета
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
        # Проверяем размер посылки
    if DataP[0] == 0x11 and len(WaitPacket[ID_Object]) >= 16:
        # Проверяем статус и время статусных пакетов
        if (
            WaitPacket[ID_Object]["SentStatusS"] == None
            and WaitPacket[ID_Object]["SentStatusV"] == None
            or time.time() - WaitPacket[ID_Object]["Time0x13"]
            or time.time() - WaitPacket[ID_Object]["Time0x12"] > 900
        ):
            print("Статусные пакеты Инклинометра еще не были отправлены")
        else:
            print(f"Пакет измерений Инклинометра {ID_Object} готов к отправке")
    if (
        DataP[0] == 0x11
        and WaitPacket[ID_Object]["Time"] != None
        and WaitPacket[ID_Object]["X"] != None
        and WaitPacket[ID_Object]["Y"] != None
    ):
        print(f"Пакет инклинометра {ID_Object} готов к отправке")
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        # Публикуем и удаляем пакет
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
        MQTTClient.publish(snd_topic_mes, jsonstring2)
        print(WaitPacket[ID_Object])
        WaitPacket.pop(ID_Object)
        SendTime[ID_Object] = [time.time()]
    if DataP[0] == 0x02:
        [Ubat] = struct.unpack(">f", DataP[1:5])
        if DataP[7] == 0:
            WaitPacket[ID_Object].update({"Defect": 0})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        else:
            WaitPacket[ID_Object].update({"Defect": 1})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        FM_ver = float(DataP[21]) + float(DataP[22] / 100)
        Ubat = float(Ubat) / 2
        WaitPacket[ID_Object].update({"FirmwareVersion": FM_ver })
        WaitPacket[ID_Object].update({"Ubat": round(Ubat, 2)})
        WaitPacket[ID_Object].update({"Pbat": DataP[5]})
        WaitPacket[ID_Object].update({'RSSI': rx_json['rxInfo'][0]['rssi']})   
        WaitPacket[ID_Object].update({'SINR': rx_json['rxInfo'][0]['loRaSNR']})
        WaitPacket[ID_Object].update({"SerialNumber": struct.unpack(">I", DataP[13:17])[0]})
        WaitPacket[ID_Object].update({"T": byte_to_int8(DataP[25])})
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        snd_topic_stat2 = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Pbat": None, "SINR": None, "RSSI": None, "Defect": None, "Error": None, "FirmwareVersion": None, "Ubat": None, "SerialNumber": None})})
        jsonstring_ext = json.dumps({"DevEUI": str(ID_Object)})
        MQTTClient.publish(snd_topic_stat, jsonstring2)
        MQTTClient.publish(snd_topic_stat2, jsonstring_ext)
        print(jsonstring2)
    if DataP[0] == 0x01:
        ang_x_arr = bytearray()
        ang_y_arr = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 2])
        for i in range(0, 4):
            ang_x_arr.append(DataP[9 - i])
            ang_y_arr.append(DataP[13 - i])
        TimeHex = int.from_bytes(arr_meas_time, "big")
        [ang_x] = struct.unpack("f", ang_x_arr)
        [ang_y] = struct.unpack("f", ang_y_arr)
        Mx = ang_x
        My = ang_y
        if len(str(Setting_Object["q_a"])) != 0:
            Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
        else:
            Mes_angle = func_routed(Mx, My, angle=0)
        Dx = Mes_angle[0]
        Dy = Mes_angle[1]
        if DeviceList2.get(ID_Object):
            ustX = DeviceList2[ID_Object].get("X") or 0
            ustY = DeviceList2[ID_Object].get("Y") or 0
        else:
            ustX = 0
            ustY = 0
        MesX = Dx / 3600
        MesY = Dy / 3600
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
        WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
        WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
        WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
        print(f"Пакет инклинометра {ID_Object} готов к отправке")
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        # Публикуем и удаляем пакет
        jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
        MQTTClient.publish(snd_topic_mes, jsonstring1)
        print(WaitPacket[ID_Object])
        print(jsonstring1)
        if DataP[1] > 1:
            try:
                ang_x_arr = bytearray()
                ang_y_arr = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[16:20])
                for i in range(0, 4):
                    ang_x_arr.append(DataP[23 - i])
                    ang_y_arr.append(DataP[27 - i])
                [ang_x] = struct.unpack("f", ang_x_arr)
                [ang_y] = struct.unpack("f", ang_y_arr)
                Mx = ang_x
                My = ang_y
                if len(str(Setting_Object["q_a"])) != 0:
                    Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
                else:
                    Mes_angle = func_routed(Mx, My, angle=0)
                Dx = Mes_angle[0]
                Dy = Mes_angle[1]
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("X") or 0
                    ustY = DeviceList2[ID_Object].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                MesX = Dx / 3600
                MesY = Dy / 3600
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
                WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
                WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
                WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
                jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2)
            except Exception as e:
                traceback.print_exc()
        if DataP[1] > 2:
            try:
                ang_x_arr = bytearray()
                ang_y_arr = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[30:34])
                for i in range(0, 4):
                    ang_x_arr.append(DataP[37 - i])
                    ang_y_arr.append(DataP[41 - i])
                [ang_x] = struct.unpack("f", ang_x_arr)
                [ang_y] = struct.unpack("f", ang_y_arr)
                Mx = ang_x
                My = ang_y
                if len(str(Setting_Object["q_a"])) != 0:
                    Mes_angle = func_routed(Mx, My, angle=int(Setting_Object["q_a"]))
                else:
                    Mes_angle = func_routed(Mx, My, angle=0)
                Dx = Mes_angle[0]
                Dy = Mes_angle[1]
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("X") or 0
                    ustY = DeviceList2[ID_Object].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                MesX = Dx / 3600
                MesY = Dy / 3600
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"X": round(MesX, ndigits=4)})
                WaitPacket[ID_Object].update({"Y": round(MesY, ndigits=4)})
                WaitPacket[ID_Object].update({"dX": int(Dx + ustX)})
                WaitPacket[ID_Object].update({"dY": int(Dy + ustY)})
                jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbInc(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring1)
                print(jsonstring1)
            except Exception as e:
                traceback.print_exc()
        WaitPacket.pop(ID_Object)    
        SendTime[ID_Object] = [time.time()]


def TenzoPacket(DataP, rx_json, ID_Object, Setting_Object):
    global DeviceList2
    arr_meas_time = bytearray()
    ang_x_arr = bytearray()
    ang_y_arr = bytearray()
    time_arr = bytearray()
    if DataP[0] == 0x06 or DataP == 0x1A or DataP == 0x1B:
        ang06 = bytearray()
        angTemp = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 1])
        for i in range(0, 4):
            ang06.append(DataP[9 - i])
            angTemp.append(DataP[13 - i])
        [TimeHex] = struct.unpack(">i", DataP[2:6])
        [ang_x] = struct.unpack("f", ang06)
        [Temp] = struct.unpack("f", angTemp)
        if DeviceList2.get(ID_Object):
            ustX = DeviceList2[ID_Object].get("ME") or 0
        else:
            ustX = 0
        Dx = ang_x + ustX
        if ID_Object == "07293314052C635B":
            WaitPacket[ID_Object].update({"Time": int(time.time())})
        else:
            WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"ME": round(ang_x, 4)})
        WaitPacket[ID_Object].update({"T": round(Temp, 2)})
        WaitPacket[ID_Object].update({"dX": int(Dx)})
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        # Публикуем и удаляем пакет
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTenz(WaitPacket[ID_Object]))})
        MQTTClient.publish(snd_topic_mes, jsonstring2)
        print(jsonstring2)
        if DataP[1] > 1:
            try:
                ang06 = bytearray()
                angTemp = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[16:20])
                for i in range(0, 4):
                    ang06.append(DataP[23 - i])
                    angTemp.append(DataP[27 - i])
                [ang_x] = struct.unpack("f", ang06)
                [Temp] = struct.unpack("f", angTemp)
                Dx = ang_x + ustX
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"ME": round(ang_x, 4)})
                WaitPacket[ID_Object].update({"T": round(Temp, 2)})
                WaitPacket[ID_Object].update({"dX": int(Dx)})
                jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTenz(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2)
            except Exception as e:
                traceback.print_exc()
        if DataP[1] > 2:
            try:
                ang06 = bytearray()
                angTemp = bytearray()
                [TimeHex] = struct.unpack(">i", DataP[30:34])
                for i in range(0, 4):
                    ang06.append(DataP[37 - i])
                    angTemp.append(DataP[41 - i])
                [ang_x] = struct.unpack("f", ang06)
                [Temp] = struct.unpack("f", angTemp)
                Dx = ang_x + ustX
                WaitPacket[ID_Object].update({"Time": TimeHex})
                WaitPacket[ID_Object].update({"ME": round(ang_x, 4)})
                WaitPacket[ID_Object].update({"T": round(Temp, 2)})
                WaitPacket[ID_Object].update({"dX": int(Dx)})
                jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in (JsonDumbTenz(WaitPacket[ID_Object]))})
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2)
            except Exception as e:
                traceback.print_exc()
        WaitPacket.pop(ID_Object)    
        SendTime[ID_Object] = [time.time()]
    if DataP[0] == 2:
        Pbat = DataP[5]
        Error = DataP[7]
        FM_ver = f"{DataP[21]}." + f"{DataP[22]}"
        StatusDict[ID_Object].update({"FirmwareVersion": FM_ver })
        if Error == 0 or Error == 30:
            StatusDict[ID_Object].update({"Error": "0"})
        else:
            StatusDict[ID_Object].update({"Error": Error})
        Ubat = DataP[1:5]
        [Ubat] = struct.unpack(">f", Ubat)
        if DataP[21] == 1:
            Ubat = Ubat / 2
        else:
            Ubat = Ubat
        StatusDict[ID_Object].update({"Ubat": round(Ubat, 2)})
        StatusDict[ID_Object].update({"Pbat": Pbat})
        StatusDict[ID_Object].update({'RSSI': rx_json['rxInfo'][0]['rssi']})   
        StatusDict[ID_Object].update({'SINR': rx_json['rxInfo'][0]['loRaSNR']}) 
        if Error == 0 or Error == 30:
            StatusDict[ID_Object].update({"Defect": 0})
            StatusDict[ID_Object].update({"Status": 1})
            Error = 0
        else:
            StatusDict[ID_Object].update({"Defect": 1})
            StatusDict[ID_Object].update({"Status": 0})
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        snd_topic_stat2 = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status_ext"
        StatusDict[ID_Object].update({"SerialNumber": struct.unpack(">I", DataP[13:17])[0]})
        StatusDict[ID_Object].update({"DevEUI": ID_Object.lower()})
        jsonstring1 = json.dumps({key:  StatusDict[ID_Object][key] for key in  StatusDict[ID_Object] if key in ({"SerialNumber" : None, "Defect": None , "Pbat": None , "FirmwareVersion": None, "Status": None, "Error": None, "Ubat": None, "RSSI": None, "SINR": None})})
        jsonstring3 = json.dumps({"DevEUI" : ID_Object.lower()})
        MQTTClient.publish(snd_topic_stat, jsonstring1)
        MQTTClient.publish(snd_topic_stat2, jsonstring3)
        StatusDict.pop(ID_Object)


def GidPacket(DataP, ID_Object, Setting_Object):
    if DataP[0] == 0x1A:
        arr_meas_time = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 1])
    if DataP[0] == 0x1A:
        TimeHex = int.from_bytes(arr_meas_time, "big")
        meas_time_arr = bytearray()
        Temp_arr = bytearray()
        Humidity_arr = bytearray()
        for i in range(0, 4):  # сортируем данные гидрометра
            Temp_arr.append(DataP[8 - i])
            Humidity_arr.append(DataP[12 - i])
        [Temp] = struct.unpack("f", Temp_arr)
        [Humidity] = struct.unpack("f", Humidity_arr)
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"T": round(Temp, 2)})
        WaitPacket[ID_Object].update({"F": int(Humidity)})
        # Я разделил статусные пакеты по устройствам, поэтому если тип пакета 12 или 13, то скрипт вызовет функцию статусного пакета
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
        # Если длина пакета равна 14, то проверяем была ли отправка статусов, если да, то собираем пакет измерений к публикации на сервере
    if DataP[0] == 0x1A:
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Time": None, "T": None, "F": None})})
        MQTTClient.publish(snd_topic_mes, jsonstring1)
        print(jsonstring1)
        # print(">>>", ID_Object, str(WaitPacket[ID_Object]["Time"]), str(WaitPacket[ID_Object]["Temp"]),  str(WaitPacket[ID_Object]["Humidity"]))
        WaitPacket.pop(ID_Object)
        SendTime[ID_Object] = [time.time()]



def GidPacket2(rx_json, DataP, ID_Object, Setting_Object):
    if DataP[0] == 0x1A:
        arr_meas_time = bytearray()
        for t in range(0, 4):
            arr_meas_time.append(DataP[t + 1])
    if DataP[0] == 0x1A:
        TimeHex = int.from_bytes(arr_meas_time, "big")
        meas_time_arr = bytearray()
        Temp_arr = bytearray()
        Humidity_arr = bytearray()
        for i in range(0, 4):  # сортируем данные гидрометра
            Temp_arr.append(DataP[8 - i])
            Humidity_arr.append(DataP[12 - i])
        [Temp] = struct.unpack("f", Temp_arr)
        [Humidity] = struct.unpack("f", Humidity_arr)
        WaitPacket[ID_Object].update({"Time": TimeHex})
        WaitPacket[ID_Object].update({"F": round(Temp, 2)})
        WaitPacket[ID_Object].update({"T": round(Humidity,2)})
        # Я разделил статусные пакеты по устройствам, поэтому если тип пакета 12 или 13, то скрипт вызовет функцию статусного пакета
    if DataP[0] == 0x13 or DataP[0] == 0x12:
        StatusPacket(DataP, ID_Object, Setting_Object)
    if DataP[0] == 0x02:
        [Ubat] = struct.unpack(">f", DataP[1:5])
        if DataP[7] == 0:
            WaitPacket[ID_Object].update({"Defect": 0})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        else:
            WaitPacket[ID_Object].update({"Defect": 1})
            WaitPacket[ID_Object].update({"Error": DataP[7]})
        FM_ver = float(DataP[-5]) + float(DataP[-4] / 100)
        WaitPacket[ID_Object].update({"FirmwareVersion": FM_ver })
        WaitPacket[ID_Object].update({"Ubat": Ubat})
        WaitPacket[ID_Object].update({"Pbat": DataP[5]})
        WaitPacket[ID_Object].update({'RSSI': rx_json['rxInfo'][0]['rssi']})   
        WaitPacket[ID_Object].update({'SINR': rx_json['rxInfo'][0]['loRaSNR']})
        WaitPacket[ID_Object].update({"SerialNumber": struct.unpack(">I", DataP[13:17])[0]})
        # Если длина пакета равна 14, то проверяем была ли отправка статусов, если да, то собираем пакет измерений к публикации на сервере
    if DataP[0] == 0x1A:
        type = Setting_Object.get("type")
        Name = Setting_Object.get("MqttName")
        ID = Setting_Object.get("object_id")
        OCode = Setting_Object.get("object_code")
        UCode = Setting_Object.get("uspd_code")
        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
        jsonstring1 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Time": None, "T": None, "F": None})})
        jsonstring2 = json.dumps({key: WaitPacket[ID_Object][key] for key in WaitPacket[ID_Object] if key in ({"Pbat": None, "SINR": None, "RSSI": None, "Defect": None, "Error": None, "FirmwareVersion": None, "Ubat": None, "SerialNumber": None})})
        MQTTClient.publish(snd_topic_mes, jsonstring1)
        MQTTClient.publish(snd_topic_stat, jsonstring2)
        print(snd_topic_mes, jsonstring1)
        print(snd_topic_stat, jsonstring2)
        # print(">>>", ID_Object, str(WaitPacket[ID_Object]["Time"]), str(WaitPacket[ID_Object]["Temp"]),  str(WaitPacket[ID_Object]["Humidity"]))
        WaitPacket.pop(ID_Object)
        SendTime[ID_Object] = [time.time()]


def decode(high_bytes, low_bytes):
        to_bytes = struct.pack(">HH", high_bytes, low_bytes)
        float_res = struct.unpack(">f", to_bytes)
        return float_res[0]


def JsonDumbInc(data):
  sensorquant = "Time" "," + "X" "," + "Y" "," + "dX" "," + "dY" "," + "T"
  return sensorquant


def JsonDumbTenz(data):
  sensorquant = "Time" "," + "ME" "," + "T" "," + "dX"
  return sensorquant


def JsonDumbTerm (data):
  sensorquant = "Time" "," + "Quantity"
  for i in range(1, int(data["Quantity"]) + 1):
    sensorquant += str(","f"Sensor{i}")
  return sensorquant


def TermoMOXA(Device, slave, address,port, ConnectCount, listen_reg):
    from pymodbus.client import ModbusTcpClient as ModbusClient
    from pymodbus.transaction import ModbusRtuFramer, ModbusBinaryFramer
    tk_raw_values = {"Time": int(time.time()), "Quantity" : Device["q_a"]}
    client = ModbusClient(host=address, port=port, framer=ModbusRtuFramer)
    while listen_reg is None and ConnectCount < 5:
        try:
            if client.connect():
                for i in range(1, int(Device["q_a"]) + 1):
                    listen_reg = client.read_holding_registers(int(Device["registers"][i], 16), 1, int(slave)).registers
                    to_bytes = struct.pack(">H", listen_reg[0])
                    [decoded_measure] = struct.unpack(">h", to_bytes)
                    tk_raw_values.update({f"Sensor{i}": decoded_measure / 100})
                if len(tk_raw_values) != int(Device["q_a"]) + 2:
                    print(len(tk_raw_values))
                else:
                    print(" готов к отправке.")
                    print(tk_raw_values)
                    # Готовим измеренеия к отправке
                    type = "TK"
                    ID = Device.get("object_id")
                    Name = Device.get("MqttName")
                    OCode = Device.get("object_code")
                    UCode = Device.get("uspd_code")
                    tk_raw_values.update({"LogicalNumber" : slave})
                    tk_raw_values.update({"Defect" : 0})
                    tk_raw_values.update({"Status" : 1})
                    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                    snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                    jsonstring2 = json.dumps({key: tk_raw_values[key] for key in tk_raw_values if key in (JsonDumbTerm(tk_raw_values))})
                    jsonstring1 = json.dumps({key: tk_raw_values[key] for key in tk_raw_values if key in ({"LogicalNumber": None, "Defect": None, "Defect": None, "Status": None})})
                    MQTTClient.publish(snd_topic_mes, jsonstring2)
                    MQTTClient.publish(snd_topic_stat, jsonstring1)
                    client.close()
                    time.sleep(2.3)
            else:
              print(f"Не удалось подключиться к преобразователю {address}")
              ConnectCount += 1 
              client.close()
              time.sleep(1)
        except Exception:
            traceback.print_exc()
            print(f"Ошибка при работе Modbus {address, slave}")
            client.close()
            time.sleep(1)
        if listen_reg is None:
            print(f"Не удалось получить данные Modbus {address} после 5 попыток, {address, slave}")
            break
    

def inclinomMOXA(Device, slave, address,port, ConnectCount, listen_reg, ID_Object):
    from pymodbus.client import ModbusTcpClient as ModbusClient
    from pymodbus.transaction import ModbusRtuFramer, ModbusBinaryFramer
    global DeviceList2
    inc_raw_values = {}
    x = bytearray()
    y = bytearray()
    client = ModbusClient(host=address, port=port, framer=ModbusRtuFramer)
    while listen_reg is None and ConnectCount < 5:
        try:
            if client.connect():
                registr = [0,1,2,3]
                for i in range(3):
                    try:
                        listen_reg = client.read_holding_registers(registr[0], len(registr), int(slave))
                        for i in (struct.pack("<H",listen_reg.registers[1] )): #Старший
                            y.append(i)
                        for i in (struct.pack("<H",listen_reg.registers[0])): #Младший
                            y.append(i)
                        for i in (struct.pack("<H",listen_reg.registers[3] )): #Старший
                            x.append(i)
                        for i in (struct.pack("<H",listen_reg.registers[2] )): #Младший
                            x.append(i)
                    except Exception:
                        traceback.print_exc()
                        time.sleep(1)
                        continue
                    else:
                        break
                y_decoded = struct.unpack("i", y) 
                x_decoded = struct.unpack("i", x)
                if len(str(Device["q_a"])) != 0:
                    decoded_mes = func_routed(float(x_decoded[0]), float(y_decoded[0]), angle=int(Device["q_a"]))
                else:
                    decoded_mes = func_routed(float(x_decoded[0]), float(y_decoded[0]), angle=0)
                print(f"x_decoded: {x_decoded}")
                print(f"y_decoded: {y_decoded}")
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("X") or 0
                    ustY = DeviceList2[ID_Object].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                    print(2)
                print(ustX)
                print(ustY)
                print(decoded_mes[0])
                print(decoded_mes[1])
                x_decoded = decoded_mes[0]
                y_decoded = decoded_mes[1]
                messureX = decoded_mes[0] / 1000 / 3600
                messureY = decoded_mes[1] / 1000 / 3600
                messuredX = decoded_mes[0] / 1000 + ustX
                messuredY = decoded_mes[1] / 1000 + ustY
                inc_raw_values.update({"Time": int(time.time())})
                inc_raw_values.update({"X": round(messureX, 4)})
                inc_raw_values.update({"Y": round(messureY, 4)})
                inc_raw_values.update({"dX": int(messuredX)})
                inc_raw_values.update({"dY": int(messuredY)})
                jsonstring2 = json.dumps({key: inc_raw_values[key] for key in inc_raw_values if key in (JsonDumbInc(inc_raw_values))})
                if len(inc_raw_values) != 5:
                    print(len(inc_raw_values))
                else:
                    print(" готов к отправке.")
                    # Готовим измеренеия к отправке
                    type = "INC"
                    ID = Device.get("object_id")
                    Name = Device.get("MqttName")
                    OCode = Device.get("object_code")
                    UCode = Device.get("uspd_code")
                    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                    print(jsonstring2)
                    print(snd_topic_mes)
                    MQTTClient.publish(snd_topic_mes, jsonstring2, qos=2)
                    client.close()
                    time.sleep(2.3)
            else:
              print(f"Не удалось подключиться к преобразователю {address}")
              ConnectCount += 1 
              client.close()
              time.sleep(1)
        except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)
        if listen_reg is None:
            client.close()
            print(f"Не удалось получить данные Modbus {address} после 5 попыток, {address, slave}")


def AccelerMOXA(Device, slave, address, port, ConnectCount, listen_reg,ID_Object ):
    Acc_raw_values = {}
    DataAcceller = []
    x = bytearray()
    y = bytearray()
    client = ModbusClient(host=address, port=port, framer=ModbusRtuFramer)
    while listen_reg is None:
        try:
            ConnectCount += 1
            print(f"Try connect to {address} Moxa, Slave:{slave}")
            if ConnectCount !=5:
                registr = Device["registers"]
                listen_reg = client.read_holding_registers(registr[0], len(registr), slave)
                for i in (struct.pack("<H",listen_reg.registers[1] )): #Старший
                    y.append(i)
                for i in (struct.pack("<H",listen_reg.registers[0])): #Младший
                    y.append(i)
                for i in (struct.pack("<H",listen_reg.registers[3] )): #Старший
                    x.append(i)
                for i in (struct.pack("<H",listen_reg.registers[2] )): #Младший
                    x.append(i)
                for j in DeviceList2["devices"]:
                    if j["devEui"] == ID_Object:
                        ustX = j["UsterX"]
                        ustY = j["UsterY"]
                        break
                    else: 
                        ustX = 0
                        ustY = 0
                y_decoded = struct.unpack("i", y) 
                x_decoded = struct.unpack("i", x)
                x_decoded = x_decoded[0] + ustX
                y_decoded = y_decoded[0] + ustY
                print(f"x_decoded: {x_decoded}")
                print(f"y_decoded: {y_decoded}")
                messureX = x_decoded / 1000 / 3600
                messureY = y_decoded / 1000 / 3600
                messuredX = x_decoded / 1000
                messuredY = y_decoded / 1000
                Acc_raw_values.update({"Time": int(time.time())})
                Acc_raw_values.update({"X": round(messureX, 6)})
                Acc_raw_values.update({"Y": round(messureY, 6)})
                Acc_raw_values.update({"dX": int(messuredX)})
                Acc_raw_values.update({"dY": int(messuredY)})
                jsonstring2 = json.dumps({key: Acc_raw_values[key] for key in Acc_raw_values if key in (JsonDumbInc(Acc_raw_values))})
                if len(Acc_raw_values) != 5:
                    print(len(Acc_raw_values))
                else:
                    print(" готов к отправке.")
                    # Готовим измеренеия к отправке
                    type = "ACC"
                    Name = Device.get("name")
                    ID = Device.get("id")
                    OCode = Device.get("object_id")
                    UCode = Device.get("uspd")
                    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                    # MQTTClient.publish(snd_topic_mes, res_mes)
                    print(jsonstring2)
                    print(snd_topic_mes)
                    MQTTClient.publish(snd_topic_mes, jsonstring2)
                    client.close()
                    time.sleep(2.3)
            else:
                print(f"Host {address} не доступен")
        except:
            break


def TenzoMOXA(Device, slave, address,port, ConnectCount, listen_reg, ID_Object):
    from pymodbus.client import ModbusTcpClient as ModbusClient
    from pymodbus.transaction import ModbusRtuFramer, ModbusBinaryFramer
    global DeviceList2
    TZ_raw_values = {}
    x = bytearray()
    y = bytearray()
    client = ModbusClient(host=address, port=port, framer=ModbusRtuFramer)
    while listen_reg is None and ConnectCount < 5:
        try:
            if client.connect():
                registr = [0,1,2,3]
                for i in range(3):
                    try:
                        listen_reg = client.read_holding_registers(registr[0], len(registr), int(slave)).registers
                        # Объединяем два 16-битных числа в одно 32-битное
                        temperature32 = (listen_reg[0] << 16) | listen_reg[1]
                        # Преобразование значений в градусы
                        temperature = temperature32 / 1000.0
                        print('Температура: {} градусов'.format(temperature))
                        # Объединяем два 16-битных числа в одно 32-битное
                        pressure32 = (listen_reg[2] << 16) | listen_reg[3]
                        # Преобразование значений в градусы
                        pressure = pressure32 / 1000.0
                        print('Давление: {} '.format(pressure))
                    except Exception:
                        traceback.print_exc()
                        continue
                    else:
                        break
                if DeviceList2.get(ID_Object):
                    ustX = DeviceList2[ID_Object].get("ME") or 0
                else:
                    ustX = 0
                Dx = pressure + ustX
                TZ_raw_values.update({"Time": int(time.time())})
                TZ_raw_values.update({"ME": round(pressure, 4)})
                TZ_raw_values.update({"T": round(temperature, 2)})
                TZ_raw_values.update({"dX": int(Dx)})
                jsonstring2 = json.dumps({key: TZ_raw_values[key] for key in TZ_raw_values if key in (JsonDumbTenz(TZ_raw_values))})
                if len(TZ_raw_values) != 4:
                    print(len(TZ_raw_values))
                else:
                    print(" готов к отправке.")
                    # Готовим измеренеия к отправке
                    type = "TZ"
                    ID = Device.get("object_id")
                    Name = Device.get("MqttName")
                    OCode = Device.get("object_code")
                    UCode = Device.get("uspd_code")
                    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                    jsonstring2 = json.dumps({key: TZ_raw_values[key] for key in TZ_raw_values if key in (JsonDumbTenz(TZ_raw_values))})
                    MQTTClient.publish(snd_topic_mes, jsonstring2)
                    print(jsonstring2)
                    print(snd_topic_mes)
                    client.close()
                    time.sleep(2.3)
            else:
              print(f"Не удалось подключиться к преобразователю {address}")
              ConnectCount += 1 
              client.close()
              time.sleep(1)
        except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)
        if listen_reg is None:
            client.close()
            print(f"Не удалось получить данные Modbus {address} после 5 попыток, {address, slave}")


def HydromZet(Setting_Object, slave, address, port, ConnectCount, listen_reg, ID_Object):
    from pyModbusTCP.client import ModbusClient
    client = ModbusClient(
        host=address,
        port=502,
        unit_id= int(slave),
        timeout=30.0,
        debug=False,
        auto_open=False,
        auto_close=False,
    )
    try:
        if client.open():
            hg_result_measures = {}
            hg_raw_values = []
            hg_raw_stat = {"Defect": 0}
            redisters = [
            20,
            21,
            58,
            59,
            96,
            97
            ]
            for j in redisters:
                print(j)
                hg_raw_value = client.read_holding_registers(j, 1)
                print(hg_raw_value)
                hg_raw_values.append(hg_raw_value[0])
                if len(hg_raw_values) == len(redisters):
                    humidity = round(
                        decode(hg_raw_values[1], hg_raw_values[0]), 2
                    )  # относительная влажность.
                    temperature = round(
                        decode(hg_raw_values[3], hg_raw_values[2]), 2
                    )  # температура окружающей среды.
                    pressure = round(
                        decode(hg_raw_values[5], hg_raw_values[4]), 2
                    )  # атмосферное давление.
                    print(f"Humidity: {humidity}")
                    print(f"Temperature: {temperature}")
                    print(f"Pressure: {pressure}")
                    hg_result_measures.update({"Time": int(time.time())})
                    hg_result_measures.update({"F": (humidity)})
                    hg_result_measures.update({"T": (temperature)})
                    print(hg_result_measures)
                    if len(hg_result_measures) != 3:
                        print(len(hg_result_measures))
                    else:
                        print(" готов к отправке.")
                        type = Setting_Object.get("type")
                        Name = Setting_Object.get("MqttName")
                        ID = Setting_Object.get("object_id")
                        OCode = Setting_Object.get("object_code")
                        UCode = Setting_Object.get("uspd_code")
                        snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                        snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                        jsonstring2 = json.dumps({key: hg_result_measures[key] for key in hg_result_measures if key in ({"Time": None, "F": None, "T": None})})
                        jsonstring1 = json.dumps({key: hg_raw_stat[key] for key in hg_raw_stat if key in ({"Defect": 0})})
                        # Заполняем по порядку все измерения и публикуем. Потом удаляем пакет.
                        print(jsonstring2)
                        MQTTClient.publish(snd_topic_stat, jsonstring1)
                        MQTTClient.publish(snd_topic_mes, jsonstring2)
                        client.close()
                        time.sleep(0.5)
                        time.sleep(2.3)

        else:
            type = Setting_Object.get("type")
            Name = Setting_Object.get("MqttName")
            ID = Setting_Object.get("object_id")
            OCode = Setting_Object.get("object_code")
            UCode = Setting_Object.get("uspd_code")
            snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
            jsonstring1 = json.dumps({"Defect": 1})
            MQTTClient.publish(snd_topic_stat, jsonstring1)
    except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)
    

def TermoZet(Device, slave, address):
    from pyModbusTCP.client import ModbusClient as ModbusZetlabClient
    qaa = Device["q_a"].split(',') if ',' in Device["q_a"] else [Device["q_a"],Device["q_a"]]
    tk_raw_values = {"Time": int(time.time()), "Quantity": int(qaa[1])   }
    client = ModbusZetlabClient(
        host=address,
        port=502,
        unit_id=int(slave),
        timeout=30.0,
        debug=False,
        auto_open=False,
        auto_close=False,
    )
    try:
        if client.open():
            for i in range(0, int(qaa[1])):
                tk_index =  int(qaa[0]) - int(qaa[1]) + i
                tk_raw_measure = client.read_holding_registers(int(Device[ "registers"][tk_index + 1], 16), 1)
                result_measure = []
                result_measure.append(tk_raw_measure[0])
                print(f"{i}: {result_measure[0]}")
                to_bytes = struct.pack(">H", result_measure[0])
                [decoded_measure] = struct.unpack(">h", to_bytes)
                tk_raw_values.update({f"Sensor{i + 1}": decoded_measure / 100})
            if len(tk_raw_values) != int(qaa[1]) + 2:
                print(len(tk_raw_values))
            else:
                print(" готов к отправке.")
                # Готовим измеренеия к отправке
                type = Device.get("type")
                Name = Device.get("MqttName")
                ID = Device.get("object_id")
                OCode = Device.get("object_code")
                UCode = Device.get("uspd_code")
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                # Заполняем по порядку все измерения и публикуем. Потом удаляем пакет.
                jsonstring2 = json.dumps({key: tk_raw_values[key] for key in tk_raw_values if key in (JsonDumbTerm(tk_raw_values))})
                jsonstring1 = json.dumps({"Defect" : 0})
                MQTTClient.publish(snd_topic_stat, jsonstring1)
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2,snd_topic_mes)
                client.close()
                time.sleep(2.3)
                print()
                
        else:
            print(f"Host {address} не доступен")
            client.close()
    except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)

def inclinomZet(Device, slave, address):
    global DeviceList2
    from pyModbusTCP.client import ModbusClient as ModbusZetlabClient
    inc_raw_values = []
    client = ModbusZetlabClient(
        host=address,
        port=502,
        unit_id=int(slave),
        timeout=30.0,
        debug=False,
        auto_open=False,
        auto_close=False,
    ) 
    try:
        if client.open():
            registr = Device["registers"]
            Xreg = [registr[0], registr[1]]
            Yreg = [registr[2], registr[3]]
            print(Xreg)
            print(Yreg)
            x_high = client.read_holding_registers(int(registr[1]), 1)
            # В struct pack/unpack передавать сначала 21 потом 20 регистр.
            x_low = client.read_holding_registers(
                int(registr[0]), 1
            )  # В struct pack/unpack передавать сначала 21 потом 20 регистр.
            y_high = client.read_holding_registers(
                int(registr[3]), 1
            )  # В struct pack/unpack передавать сначала 21 потом 20 регистр.
            y_low = client.read_holding_registers(
                int(registr[2]), 1
            )  # В struct pack/unpack передавать сначала 21 потом 20 регистр.
            # y_full = client.read_holding_registers(Yreg, 2)
            x_decoded = decode(x_high[0], x_low[0])
            y_decoded = decode(y_high[0], y_low[0])
            print(f"x_decoded: {x_decoded}")
            print(f"y_decoded: {y_decoded}")
            inc_raw_values.append(x_decoded)
            inc_raw_values.append(y_decoded)
            if len(inc_raw_values) != 2:
                print(len(inc_raw_values))
            else:
                print(" готов к отправке.")
                # Готовим измеренеия к отправке
                type = Device.get("type")
                Name = Device.get("MqttName")
                ID = Device.get("object_id")
                OCode = Device.get("object_code")
                UCode = Device.get("uspd_code")
                snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"

                Dx = x_decoded *3600
                Dy = y_decoded *3600
                if DeviceList2.get(Device["devEui"]):
                    ustX = DeviceList2[Device["devEui"]].get("X") or 0
                    ustY = DeviceList2[Device["devEui"]].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0

                # Заполняем по порядку все измерения и публикуем. Потом удаляем пакет.
                jsonstring2 = json.dumps({"Time": int(time.time()), "X": inc_raw_values[0], "Y": inc_raw_values[1], "dX": int(Dx + ustX), "dY": int(Dy + ustY)})
                jsonstring1 = json.dumps({"Defect" : 0})
                MQTTClient.publish(snd_topic_stat, jsonstring1)
                MQTTClient.publish(snd_topic_mes, jsonstring2)
                print(jsonstring2 , snd_topic_mes)
                client.close()
                time.sleep(2.3)


        else:
            print(f"Host {address} не доступен")
            client.close()
    except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)


def AccelerZet(Device, slave, address):
    from pyModbusTCP.client import ModbusClient as ModbusZetlabClient
    acc_raw_values = []
    client = ModbusZetlabClient(
        host=address,
        port=502,
        unit_id=int(slave),
        timeout=30.0,
        debug=False,
        auto_open=False,
        auto_close=False
    ) 
    try:
        if client.open():
            for j in Device["registers"]:
                acc_raw_value = client.read_holding_registers(int(j), 1)
                if acc_raw_value == None:
                    print("\t\t\tNull received.")
                    continue
                acc_raw_values.append(acc_raw_value[0])
            if len(acc_raw_values) == len(Device["registers"]):
                x_y_z = []
                for j in range(len(acc_raw_values)):
                    if j not in [1, 7, 13]: # Индекс значения старшего байта замеров вибростойкости по x, y, z
                        continue
                        # print(f"high: {acc_raw_values[j]} low: {acc_raw_values[j-1]}")
                    decoded_value = decode(acc_raw_values[j], acc_raw_values[j-1])
                    x_y_z.append(decoded_value)
                print(
                f"decoded_x: {x_y_z[0]}",
                f"decoded_y: {x_y_z[1]}",
                f"decoded_z: {x_y_z[2]}",
                sep="\r\n",
                )
                if len(x_y_z) != 3:
                    print(len(x_y_z))
                else:
                    print(" готов к отправке.")
                    # Готовим измеренеия к отправке
                    type = Device.get("type")
                    Name = Device.get("MqttName")
                    ID = Device.get("object_id")
                    OCode = Device.get("object_code")
                    UCode = Device.get("uspd_code")
                    snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                    snd_topic_stat = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/status"
                    # Заполняем по порядку все измерения и публикуем. Потом удаляем пакет.
                    jsonstring2 = json.dumps({"Time": int(time.time()), "X": x_y_z[0], "Y": x_y_z[1], "Z": x_y_z[2]})
                    jsonstring1 = json.dumps({"Defect" : 0})
                    MQTTClient.publish(snd_topic_stat, jsonstring1)
                    MQTTClient.publish(snd_topic_mes, jsonstring2)
                    print(jsonstring2, snd_topic_mes)
                    client.close()
                    time.sleep(2.3)
    except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)


def PiezometrALZ(Device, slave, address,port, ConnectCount, listen_reg, ID_Object):
    from pymodbus.client import ModbusTcpClient as ModbusClient
    from pymodbus.transaction import ModbusRtuFramer, ModbusBinaryFramer
    x = bytearray()
    client = ModbusClient(host=address, port=port, framer=ModbusRtuFramer)
    while listen_reg is None and ConnectCount < 5:
        try:
            if client.connect():
                for i in range(3):
                    try:
                        listen_reg = client.read_input_registers(8,2,1).registers
                        print(listen_reg)
                        for i in (struct.pack("<H",listen_reg[1] )): #Старший
                            x.append(i)
                            print(x)
                        for i in (struct.pack("<H",listen_reg[0] )): #Младший
                            x.append(i)
                        [pressure] = struct.unpack("<f", x)
                    except Exception:
                        traceback.print_exc()
                        continue
                    else:
                        break
                jsonstring2 = json.dumps({"Time": int(time.time()), "H":round(pressure, 4)})
                # Готовим измеренеия к отправке
                type = "PZ"
                ID = Device.get("object_id")
                Name = Device.get("MqttName")
                OCode = Device.get("object_code")
                UCode = Device.get("uspd_code")
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                print(jsonstring2)
                print(snd_topic_mes)
                DownMqttClient.publish(snd_topic_mes, jsonstring2)
                client.close()
                time.sleep(2.3)
            else:
                print(f"Не удалось подключиться к преобразователю {address}")
                ConnectCount += 1 
                client.close()
                time.sleep(1)
        except Exception:
            traceback.print_exc()
            client.close()
            time.sleep(1)
            if listen_reg is None:
                client.close()
                print(f"Не удалось получить данные Modbus {address} после 5 попыток, {address, slave}")
                break

def try_connect(HOST, PORT):
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        client_socket.connect((HOST, PORT))
        return True
    except socket.error as e:
        print(f"Не удалось установить соединение: {e}")
        return False
    finally:
        client_socket.close()  # Не забудьте закрыть сокет

def IcnliDi(ConfigFile, Slave, Ip_address, Port, DevEUI):
        global DeviceList2
        host = Ip_address  # Адрес сервера 
        port = int(Port)  # Порт сервера 
        TIMEOUT = 5
        result = try_connect(host, port)
        if result:
            client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM) 
            client_socket.settimeout(TIMEOUT) 
            slave = int(Slave)
            Identity_byte = 119
            code_messege = 1
            len_num = 4
            Summ = slave + code_messege + len_num
            message = hex_convert(Identity_byte) + hex_convert(len_num) + hex_convert(slave) + hex_convert(code_messege) + hex_convert(Summ)
            data = bytes.fromhex(message)
            hex_data = message
            byte_data = binascii.unhexlify(hex_data)
            client_socket.connect((host, port)) 
            for i in range(3):
                try:
                    client_socket.sendall(byte_data)
                    time.sleep(1)
                    part = client_socket.recv(9)
                except Exception:
                    traceback.print_exc()
                    time.sleep(1)
                    continue
                else:
                    break
            if part and part[3] == 129 and part[2] == int(Slave):
                print(part)
                if part[4] == 16:
                    x = part.hex()[10:12] + "." + part.hex()[12:16]
                    x = float(x) / -1
                    dx = x * 3600
                   # print("X = " + str(float(x)))
                    #print("Dx = " + str(dx))
                else:
                    x = part.hex()[10:12] + "." + part.hex()[12:16]
                    x = float(x)
                    dx = x * 3600
                   # print(f"X = {float(x)}")
                   # print("Dx = " + str(dx))
            time.sleep(2)
            code_messege = 2
            Summ = slave + code_messege + len_num
            message = hex_convert(Identity_byte) + hex_convert(len_num) + hex_convert(slave) + hex_convert(code_messege) + hex_convert(Summ)
            hex_data = message
            byte_data = binascii.unhexlify(hex_data)
            part = b''
            # проверка контрольной суммы
            for i in range(3):
                try:
                    client_socket.sendall(byte_data)
                    time.sleep(1)
                    part = client_socket.recv(9)
                except Exception:
                    traceback.print_exc()
                    time.sleep(1)
                    continue
                else:
                    break
            client_socket.close()
            if part and part[3] == 130:
                print(part)
                if part[4] == 16:
                    y = part.hex()[10:12] + "." + part.hex()[12:16]
                    y = float(y) / -1
                    dy = y * 3600
                   # print("Y = " + str(y))
                   # print("Dy = " + str((dy)))
                else:
                    y = part.hex()[10:12] + "." + part.hex()[12:16]
                    y = float(y)
                    dy = y * 3600
                   # print(f"Y = {y}")
                   # print("Dy = " + str((dy)))
                time.sleep(2)
            if x and y:
                global DeviceList2
                if DeviceList2.get(DevEUI):
                    ustX = DeviceList2[DevEUI].get("X") or 0
                    ustY = DeviceList2[DevEUI].get("Y") or 0
                else:
                    ustX = 0
                    ustY = 0
                dx = dx + ustX
                dy = dy + ustY
                type = "INC"
                Name = ConfigFile.get("MqttName")
                ID = ConfigFile.get("object_id")
                OCode = ConfigFile.get("object_code")
                UCode = ConfigFile.get("uspd_code")
                snd_topic_mes = f"/Gorizont/{OCode}/{ID}/{UCode}/{type}/{ID}_{Name}/from_device/measure"
                jsonstring = json.dumps({"X": round(float(x), 4), "Y": round(float(y), 4), "dX": int(dx), "dY": int(dy), "Time": int(time.time())})
                DownMqttClient.publish(snd_topic_mes, jsonstring)
                print(snd_topic_mes)
                print(jsonstring)
        else:
            print(f"{Ip_address} не доступен")



start_time_uts = int(time.time())  # Время старта скрипта
topic_mes = "application/+/device/+/event/up"
topic_status = "application/+/device/+/event/status"
topic_stat = "gateway/+/event/#"
topic_gateway = "gateway/+/state/conn"
# topic_error = "Gorizong/MRY/+/"
InputDict = {}
StatusDict = {}
TimeDict = {}
SignalLevel = {}
SentSettings = {}
object_id_list = []
devEUIhex = ""
SendArr = []
SendArrB64str = "FADwAPAGABQ="

# Подключение к MQTT
try:
    ExtMQTTClient = mqtt_client.Client()
    ExtMQTTClient.connect(broker, port)
    ExtMQTTClient.loop_start()
    MQTTClient = mqtt_client.Client()
    MQTTClient.connect(broker, port)
    MQTTClient.on_connect = on_connect
    MQTTClient.subscribe(topic_gateway, qos=2)
    MQTTClient.subscribe(topic_mes, qos=2)
    MQTTClient.subscribe(topic_status, qos=2)
    MQTTClient.on_message = on_message
    MQTTClient.loop_start()
except Exception:
    traceback.print_exc()


def find(name, path):
    for root, dirs, files in os.walk(path):
        if name in files:
            return os.path.join(root, name)
        

def Status_15min():
    while True:
        uptime = int(time.time()) - start_time_uts
        #chirp = urllib.request.urlopen(f"http://{broker}:8080")
        OCodef = ExternalMqttConf["object_code"]
        UCodef = ExternalMqttConf["uspd_code"]
        #if chirp.status == 200:
        chirpstack_msg = "OK"
        GatewayST = "OK"
        # else:
        #     chirpstack_msg = "ERROR"
        #     GatewayST = "ERROR"

        snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/status/measure"
        snd_res = (
            str(f"Uptime:{uptime}")
            + "\n"
            + str(f"Gateway:{GatewayST}")
            + "\n"
            + str(f"Chirpstack:{chirpstack_msg}")
        )
        MQTTClient.publish(snd_top, snd_res)

        if chirpstack_msg == "ERROR" or GatewayST == "ERROR":
            snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/status/measure"
            snd_res = (
                str(f"Uptime:{uptime}")
                + "\n"
                + str(f"Gateway:{GatewayST}")
                + "\n"
                + str(f"Chirpstack:{chirpstack_msg}")
            )
            MQTTClient.publish(snd_top, snd_res)
        print(BaseStation)
        for base_state in BaseStation:
            MQTTClient.publish(BaseStation[base_state].get("snd_topic"), json.dumps({"Defect" : BaseStation[base_state].get("Defect")}), qos=2)
    
        time.sleep(900) # Приостановка на 15 минут (15*60 секунд)

def GpioStatus():
    gpio8 = mraa.Gpio(8)
    gpio9 = mraa.Gpio(9)
    prev_gpio_door = None
    prev_gpio_ups = None
    last_send_time_door = 0
    last_send_time_ups = 0
    send_interval = 900  # Интервал отправки в секундах (1 час)
    while True:
        try:
            if gpio8.read() == 0:
                gpio_door = "0"
            else:
                gpio_door = "1"
            # Отправляем данные о двери только если состояние изменилось или прошел 1 час
            OCodef = ExternalMqttConf["object_code"]
            UCodef = ExternalMqttConf["uspd_code"]
            if gpio_door != prev_gpio_door or time.time() - last_send_time_door >= send_interval:
                snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/door_open/measure"
                snd_res = json.dumps({"Time": int(time.time())} )
                snd_res = str(int(time.time())) + "\n" + str(gpio_door)
                MQTTClient.publish(snd_top, snd_res)
                prev_gpio_door = gpio_door
                last_send_time_door = time.time()
            # Бесперебойник
            if gpio9.read() == 1:
                gpio_ups = "0"
            else:
                gpio_ups = "1"
            # Отправляем данные о бесперебойнике только если состояние изменилось или прошел 1 час
            if gpio_ups != prev_gpio_ups or time.time() - last_send_time_ups >= send_interval:
                snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/ups_status/measure"
                snd_res = str(int(time.time())) + "\n" + str(gpio_ups)
                MQTTClient.publish(snd_top, snd_res)
                prev_gpio_ups = gpio_ups
                last_send_time_ups = time.time()
            time.sleep(10)
        except Exception as e:
            traceback.print_exc()
            time.sleep(900)
            continue

def GpioStatusNoMraa():
    while True:
        OCodef = ExternalMqttConf["object_code"]
        UCodef = ExternalMqttConf["uspd_code"]
        gpio_door = "0"
        snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/door_open/measure"
        snd_res = str(int(time.time())) + "\n" + str(gpio_door)
        MQTTClient.publish(snd_top, snd_res)
        gpio_ups = "0"
        snd_top = f"/Gorizont/{OCodef}/USPD/{UCodef}/ups_status/measure"
        snd_res = str(int(time.time())) + "\n" + str(gpio_ups)
        MQTTClient.publish(snd_top, snd_res)
        time.sleep(900)

def Measure_1_hours():
    global DeviceList2
    global ChangeTimeDeviceList
    global DeviceSetting
    global ModbusDevice
    while True:
        if os.path.isfile(f"cfg/{str(platform.uname()[1])}/NeedUpdate"):
            UsterRead()
        if os.path.getctime(f"cfg/{str(platform.uname()[1])}/DeviceList.json") > ChangeTimeDeviceList:
            print("Обновление DeviceList")
            DeviceRead()
        for devEui in ModbusDevice:
            if "MOXA_5450" in DeviceSetting[devEui]["moxaname"].upper():
                pass
                if DeviceSetting[devEui]["type"] == "INC":
                    try:
                        IcnliDi(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], devEui)
                    except Exception:
                        traceback.print_exc()
                        print(devEui, DeviceSetting[devEui]["MqttName"])
                if DeviceSetting[devEui]["type"] == "PZ":
                    try:
                        listen_reg = None
                        ConnectCount = 0
                        PiezometrALZ(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], ConnectCount, listen_reg, devEui)
                    except Exception:
                        traceback.print_exc()
                        print(devEui, DeviceSetting[devEui]["MqttName"])
            elif "MOXA" in DeviceSetting[devEui]["moxaname"].upper():
                if DeviceSetting[devEui]["type"] == "INC":
                    listen_reg = None
                    ConnectCount = 0
                    inclinomMOXA(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], ConnectCount, listen_reg, devEui)
                if DeviceSetting[devEui]["type"] == "TK":
                    listen_reg = None
                    ConnectCount = 0
                    TermoMOXA(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], ConnectCount, listen_reg)
                elif DeviceSetting[devEui]["type"] == "TZ":
                    listen_reg = None
                    ConnectCount = 0
                    TenzoMOXA(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], ConnectCount, listen_reg, devEui)
            elif "ZETLAB" in DeviceSetting[devEui]["moxaname"].upper():
                if DeviceSetting[devEui]["type"] == "TG":
                    listen_reg = None
                    ConnectCount = 0
                    HydromZet(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"], DeviceSetting[devEui]["port"], ConnectCount, listen_reg, devEui)
                elif DeviceSetting[devEui]["type"] == "INC":
                    listen_reg = None
                    ConnectCount = 0
                    inclinomZet(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"])
                elif DeviceSetting[devEui]["type"] == "TK":
                    TermoZet(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"])
                elif DeviceSetting[devEui]["type"] == "ACC":
                    AccelerZet(DeviceSetting[devEui], DeviceSetting[devEui]["slave"], DeviceSetting[devEui]["moxaip"])
        time.sleep(3600) # Остановка 60 * 60

try:
    thread1 = threading.Thread(target=Status_15min)
    thread1.start()
    print(f"Поток для  Статусов успд {'активен' if thread1.is_alive() else 'не активен'}")
    if len(ModbusDevice) != 0:
        print(f"Обнаружено {len(ModbusDevice)} Modbus устройств")
        thread2 = threading.Thread(target=Measure_1_hours)
        thread2.start()
        print(f"Поток для Модбас функции {'активен' if thread2.is_alive() else 'не активен'}")
except Exception:
    traceback.print_exc()

try:
    import mraa
    ThreadMRAA = threading.Thread(target=GpioStatus)
    ThreadMRAA.start()
    print(f"Поток для  Статусов успд MRAA {'активен' if ThreadMRAA.is_alive() else 'не активен'}")
except ImportError:
    print("Ошибка при импорте модуля mraa gpio")
    try:
        ThreadMRAA = threading.Thread(target=GpioStatusNoMraa)
        ThreadMRAA.start()
        print(f"Поток для  Статусов успд без модуля mraa gpio {'активен' if ThreadMRAA.is_alive() else 'не активен'}")    
    except Exception as e:
            print(f"Ошибка при вызове функции: {e}")
except Exception as e:
    print(f"Ошибка при вызове функции: {e}")








