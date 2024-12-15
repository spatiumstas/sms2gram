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

<img src="https://github.com/user-attachments/assets/7834751c-ccdb-4874-8d2c-0ef744ef16d8" alt="" width="900">

4. Вставляем в скрипт
<img src="https://github.com/user-attachments/assets/c473a27a-a39b-4062-88ba-466863bc86dd" alt="" width="700">

5. Если всё задано корректно, тестовое сообщение успешно отправится
<img src="https://github.com/user-attachments/assets/3731fa2e-20d6-4dd2-b451-71b62414c5d4" alt="" width="600">
<img src="https://github.com/user-attachments/assets/67c8f0a9-4747-4812-b694-fbecd08761e8" alt="" width="350">
