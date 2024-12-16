# Установка:

1. Из SSH ввести команду
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/sms2gram/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. В сервисе выбрать настройку

- Ручной запуска скрипта через `sms2gram` или `/opt/sms2gram.sh`

# Подключение Telegram

1. Получаем и копируем `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
2. Создаём своего бота через [BotFather](https://t.me/BotFather) и копируем его `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="900">

3. Вставляем в сервис
<img src="https://github.com/user-attachments/assets/f21f5093-2152-481c-ae8d-6a9fccfcfc3f" alt="" width="700">

4. Проверяем отправкой тестовым сообщением (на модеме должно быть хотя бы одно сообщение)
<img src="https://github.com/user-attachments/assets/8ffeb6bc-b8f9-46cc-9dbc-434e5fffd8ee" alt="" width="600"> 
<img src="https://github.com/user-attachments/assets/ded26060-6ca1-479a-b8ec-b319dd4033e2" alt="" width="350">

# Работа сервиса
- При получении сообщения срабатывает хук `/opt/etc/ndm/sms.d/01-sms2gram.sh`
- Если сообщение не было отправлено (например нет интернета), оно добавляется в очередь `/opt/root/sms2gram/pending_messages.json`. Очередь проверяется при каждой отправке сообщения
- Для ручной отправки сообщения:
````shell
interface_id=UsbQmi0 message_id=nv-1 /opt/etc/ndm/sms.d/01-sms2gram.sh
````
Где `interface_id` - интерфейс модема, `message_id` - ID сообщения выбранный из вывода `sms UsbQmi0 list` в CLI или `ndmc -c sms UsbQmi0 list` в терминале