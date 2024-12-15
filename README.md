# Установка:

1. Из SSH ввести команду
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/sms2gram/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. В скрипте выбрать установку

- Ручной запуска скрипта через `sms2gram` или `/opt/sms2gram.sh`

# Подключение Telegram

1. Получаем ID своего аккаунта через [userinfobot](https://t.me/userinfobot)
2. Создаём своего бота через [BotFather](https://t.me/BotFather)
3. Копируем полученный `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="900">

4. Вставляем в скрипт
<img src="https://github.com/user-attachments/assets/f21f5093-2152-481c-ae8d-6a9fccfcfc3f" alt="" width="700">

5. Если всё задано корректно, тестовое сообщение успешно отправится
<img src="https://github.com/user-attachments/assets/8ffeb6bc-b8f9-46cc-9dbc-434e5fffd8ee" alt="" width="600">
<img src="https://github.com/user-attachments/assets/ded26060-6ca1-479a-b8ec-b319dd4033e2" alt="" width="350">
