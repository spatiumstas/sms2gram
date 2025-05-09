# Установка:

1. В `SSH` ввести команду
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/sms2gram/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. В скрипте выбрать настройку

- Ручной запуска скрипта через `sms2gram` или `/opt/root/sms2gram/sms2gram.sh`

# Подключение Telegram

1. Получаем и копируем `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
2. Создаём своего бота через [BotFather](https://t.me/BotFather) и копируем его `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

3. Вставляем в сервис
<img src="https://github.com/user-attachments/assets/f21f5093-2152-481c-ae8d-6a9fccfcfc3f" alt="" width="700">

4. Проверяем отправкой тестовым сообщением. Если на модеме нет sms, отправится тестовое.
<img src="https://github.com/user-attachments/assets/bdf799a2-3b3b-4fc6-b19a-a0f8a99e1bd7" alt="" width="900">

# Работа сервиса
- При получении сообщения срабатывает хук `/opt/root/sms2gram/01-sms2gram.sh`
- Если сообщение не было отправлено (например нет интернета), оно добавляется в очередь `/opt/root/sms2gram/pending_messages.json`. Очередь проверяется при каждой отправке сообщения или смене соединения
- Просмотр логов `cat /opt/root/sms2gram/log.txt`
- Для ручной отправки сообщения:
````shell
interface_id=UsbQmi0 message_id=nv-1 /opt/etc/ndm/sms.d/01-sms2gram.sh
````
Где `interface_id` - интерфейс модема, `message_id` - ID сообщения выбранный из вывода `sms UsbQmi0 list` в CLI или `ndmc -c sms UsbQmi0 list` в терминале
