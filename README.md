# Возможности

- Отправка полученного SMS в Telegram/ВКонтакте/другой номер с модема NDIS/QMI
- Для модема CdcEthernet/HiLink требуется пакет `smstools3`
- Удаление SMS после отправки
- Перезагрузка роутера/модема при недоступности SIM-карты
- Перезагрузка роутера при получении заданной фразы в сообщении (SMS удаляется, не отправляется уведомление)
- Удаление сообщения от заданных отправителей/текста, например RSCHS/MCHS (не отправляется уведомление)
- Отправка сообщений только из белого списка отправителя/текста (остальные удаляются)
- Отправка AT команд на модем через SMS, например `AT+EGMREXT=0,7`. Ответ команды придёт в выбранное уведомление
- Если сообщение не было отправлено (например нет интернета), добавляется в очередь `/opt/root/sms2gram/pending_messages.json`. Проверяется при каждой отправке сообщения/смене соединения
- Управление текстовой конфигурацией через web-интерфейс в пакете [web4static](https://github.com/spatiumstas/web4static)
- Мультичат Telegram задаётся через нижнее подчёркивание `-123123123_100`
- Для ВКонтакте используется `peer_id` (личные сообщения/беседа)
- Просмотр логов `cat /opt/var/log/sms2gram.log` или журнале KeeneticOS
- Для ручной отправки сообщения:

````shell
interface_id=UsbQmi0 message_id=nv-1 /opt/etc/ndm/sms.d/01-sms2gram.sh
````
Где `interface_id` - интерфейс модема, `message_id` - ID сообщения выбранный из вывода `ndmc -c sms UsbQmi0 list`

# Автоустановка

```shell
opkg update && opkg install curl ca-certificates wget-ssl && curl -fsSL https://raw.githubusercontent.com/spatiumstas/sms2gram/main/install.sh | sh
```

### Ручная установка

1. Установите необходимые зависимости
   ```
   opkg update && opkg install ca-certificates wget-ssl && opkg remove wget-nossl
   ```
2. Установите opkg-репозиторий в систему
   ```
   mkdir -p /opt/etc/opkg
   echo "src/gz sms2gram https://spatiumstas.github.io/sms2gram/all" > /opt/etc/opkg/sms2gram.conf
   ```

3. Установите пакет
   ```
   opkg update && opkg install sms2gram
   ```  

# Настройка:

### Подключение Telegram:

- Получаем и копируем `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
- Создаём своего бота через [BotFather](https://t.me/BotFather) и копируем его `token`. Указываем его при настройке конфигурации

   <img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

### Подключение ВКонтакте:

- Создайте токен с правами `messages` и сохраните его в `VK_TOKEN`
   <img src="https://github.com/user-attachments/assets/d921ab0b-0d1d-4a3d-aac6-d078ec356ae5" />

- Укажите получателя в `VK_CHAT_ID`: `user_id`/`chat_id`

### Переадресация SMS на номер:

- В конфигурации укажите `SMS_FORWARD_TO` (например `+78005553535`)
> Полученное сообщение будет переадресовано на указанный номер, если ваш модем это поддерживает

##  Удаление

#### Пакета
```
opkg remove sms2gram
```
#### Репозитория
```
rm /opt/etc/opkg/sms2gram.conf
```