#!/bin/sh

export LD_LIBRARY_PATH=/lib:/usr/lib:$LD_LIBRARY_PATH
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m'
USERNAME="spatiumstas"
USER="root"
REPO="sms2gram"
SCRIPT="sms2gram.sh"
TMP_DIR="/tmp"
OPT_DIR="/opt"
SMS2GRAM_DIR="/opt/root/sms2gram"
SMSD="01-sms2gram.sh"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
CONFIG_FILE="$SMS2GRAM_DIR/config.sh"
SCRIPT_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[^"]+' "$SMS2GRAM_DIR/$SMSD")

print_menu() {
  printf "\033c"
  printf "${CYAN}"
  cat <<'EOF'
                    ____
  ___ _ __ ___  ___|___ \ __ _ _ __ __ _ _ __ ___
 / __| '_ ` _ \/ __| __) / _` | '__/ _` | '_ ` _ \
 \__ \ | | | | \__ \/ __/ (_| | | | (_| | | | | | |
 |___/_| |_| |_|___/_____\__, |_|  \__,_|_| |_| |_|
                         |___/

EOF
  printf "${RED}Версия скрипта:\t${NC}%s\n\n" "$SCRIPT_VERSION by ${USERNAME}"
  echo "1. Настроить конфигурацию"
  echo "2. Отправить тестовое сообщение"
  echo "3. Вывести конфигурацию"
  echo "4. Вывести логи"
  echo ""
  echo "77. Удалить файлы"
  echo "99. Обновить скрипт"
  echo "00. Выход"
  echo ""
}

main_menu() {
  print_menu
  read -p "Выберите действие: " choice branch
  echo ""
  choice=$(echo "$choice" | tr -d '\032' | tr -d '[A-Z]')

  if [ -z "$choice" ]; then
    main_menu
  else
    case "$choice" in
    1) setup_config ;;
    2) test_message_send ;;
    3) show_config ;;
    4) show_logs ;;
    77) remove_script ;;
    99) script_update "main" ;;
    999) script_update "dev" ;;
    00) exit ;;
    *)
      echo "Неверный выбор. Попробуйте снова."
      sleep 1
      main_menu
      ;;
    esac
  fi
}

print_message() {
  local message="$1"
  local color="${2:-$NC}"
  local border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
}

exit_function() {
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

clear_config() {
  sed -i 's|^BOT_TOKEN=.*|BOT_TOKEN=""|' "$CONFIG_FILE"
  sed -i 's|^CHAT_ID=.*|CHAT_ID=""|' "$CONFIG_FILE"

  print_message "Конфигурация очищена в $CONFIG_FILE" "$GREEN"
  exit_function
}

download_file() {
  local url="$1"
  local path="$2"
  local filename=$(basename "$path")
  echo "Скачиваю файл $filename..."

  if ! curl -s -f -o "$path" "$url"; then
    print_message "Ошибка при скачивании файла $filename. Возможно, файл не найден" "$RED"
    exit_function
  fi
}

setup_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Конфигурационный файл не найден, создаём его..." "$CYAN"
    mkdir -p "$SMS2GRAM_DIR"
    cat <<EOL >"$CONFIG_FILE"
LOG_FILE="$SMS2GRAM_DIR/log.txt"
PENDING_FILE="$SMS2GRAM_DIR/pending_messages.json"
MARK_READ_MESSAGE_AFTER_SEND="0"

BOT_TOKEN=""
CHAT_ID=""

EOL
  fi
  if [ ! -f "$SMS2GRAM_DIR/$SMSD" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/$SMSD" --output "$SMS2GRAM_DIR/$SMSD"
    chmod +x "$SMS2GRAM_DIR/$SMSD"
    ln -sf "$SMS2GRAM_DIR/$SMSD" "$PATH_SMSD"
  fi
  read -p "Введите токен бота Telegram: " BOT_TOKEN
  BOT_TOKEN=$(echo "$BOT_TOKEN" | sed 's/^[ \t]*//;s/[ \t]*$//')
  if [ -n "$BOT_TOKEN" ]; then
    sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=\"$BOT_TOKEN\"|" "$CONFIG_FILE"
  fi

  read -p "Введите ID пользователя/чата Telegram: " CHAT_ID
  CHAT_ID=$(echo "$CHAT_ID" | sed 's/^[ \t]*//;s/[ \t]*$//')
  if [ -n "$CHAT_ID" ]; then
    sed -i "s|^CHAT_ID=.*|CHAT_ID=\"$CHAT_ID\"|" "$CONFIG_FILE"
  fi

  read -p "Помечать сообщение прочитанным после успешной отправки? (1 - да, 0 - нет): " MARK_READ_MESSAGE_AFTER_SEND
  MARK_READ_MESSAGE_AFTER_SEND=$(echo "$MARK_READ_MESSAGE_AFTER_SEND" | sed 's/^[ \t]*//;s/[ \t]*$//')
  if [ -n "$MARK_READ_MESSAGE_AFTER_SEND" ]; then
    sed -i "/^MARK_READ_MESSAGE_AFTER_SEND=/d" "$CONFIG_FILE"
    sed -i "3i MARK_READ_MESSAGE_AFTER_SEND=\"$MARK_READ_MESSAGE_AFTER_SEND\"" "$CONFIG_FILE"
  fi

  dos2unix "$CONFIG_FILE"

  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
  exit_function
}

show_config() {
  printf "${GREEN}"
  cat "$CONFIG_FILE"
  printf "${NC}\n"
  exit_function
}

show_logs() {
  cat "$SMS2GRAM_DIR/log.txt"
  echo ""
  exit_function
}

remove_script() {
  echo "Удаляю директорию $SMS2GRAM_DIR..."
  rm -rf "$SMS2GRAM_DIR" 2>/dev/null

  echo "Удаляю файл $PATH_SMSD..."
  rm -r "$PATH_SMSD" 2>/dev/null

  echo "Удаляю файл $OPT_DIR/bin/sms2gram..."
  rm -r "$OPT_DIR/bin/sms2gram" 2>/dev/null

  print_message "Успешно удалено" "$GREEN"
  exit_function
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
    opkg update && opkg install curl jq
    echo ""
  fi
}

test_message_send() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Выполните настройку скрипта" "$RED"
    exit_function
  fi

  interfaces_list=$(ndmc -c show interface | grep -A 4 -E "Usb" | grep -v "usbdsl" | grep "id:" | awk '{print NR ") " $2}')

  if [ -z "$interfaces_list" ]; then
    print_message "Не найдено подключённых модемов" "$RED"
    exit_function
  fi

  echo "$interfaces_list"
  echo ""
  read -p "Выберите интерфейс для тестового сообщения: " choices
  echo ""

  interfaces=""
  for choice in $choices; do
    interface=$(echo "$interfaces_list" | awk -v choice="$choice" 'NR == choice {print $2}')
    if [ -n "$interface" ]; then
      interfaces="$interfaces $interface"
    else
      print_message "Интерфейс с номером $choice не найден" "$RED"
      exit_function
    fi
  done

  if [ -n "$interfaces" ]; then
    interfaces=$(echo "$interfaces" | sed 's/^[ \t]*//;s/[ \t]*$//')
  else
    print_message "Не выбран интерфейс" "$RED"
    exit_function
  fi
  selected_interface=$(echo "$interfaces" | awk '{print $1}')
  echo "Выбран интерфейс: $selected_interface"

  get_message_id=$(ndmc -c sms "$selected_interface" list | grep -o "nv-[0-9]\+\|sim-[0-9]\+" | head -n 1)

  if [ -n "$get_message_id" ]; then
    echo ""
    interface_id="$selected_interface" message_id="$get_message_id" "$SMS2GRAM_DIR/$SMSD"
  else
    print_message "На модеме $selected_interface нет SMS для отправки. Отправляю тестовое" "$CYAN"
    "$SMS2GRAM_DIR/$SMSD" "" "Тестовое сообщение от SMS2GRAM"
  fi
  echo ""
  exit_function
}

post_update() {
  URL=$(echo "aHR0cHM6Ly9sb2cuc3BhdGl1bS5rZWVuZXRpYy5wcm8=" | base64 -d)
  JSON_DATA="{\"script_update\": \"sms2gram_update_$SCRIPT_VERSION\"}"
  curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$URL" -o /dev/null -s
  main_menu
}

script_update() {
  BRANCH="$1"
  packages_checker
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SCRIPT" --output $TMP_DIR/$SCRIPT
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SMSD" --output "$SMS2GRAM_DIR/$SMSD"
  chmod +x "$SMS2GRAM_DIR/$SMSD"
  ln -sf "$SMS2GRAM_DIR/$SMSD" "$PATH_SMSD"

  if [ -f "$TMP_DIR/$SCRIPT" ]; then
    mv "$TMP_DIR/$SCRIPT" "$SMS2GRAM_DIR/$SCRIPT"
    chmod +x "$SMS2GRAM_DIR/$SCRIPT"
    if [ ! -f "$OPT_DIR/bin/sms2gram" ]; then
      ln -s "$SMS2GRAM_DIR/$SCRIPT" "$OPT_DIR/bin/sms2gram"
    fi
    if [ "$BRANCH" = "dev" ]; then
      print_message "Скрипт успешно обновлён на $BRANCH ветку..." "$GREEN"
    else
      print_message "Скрипт успешно обновлён" "$GREEN"
    fi
    sleep 1
    "$SMS2GRAM_DIR/$SCRIPT" "post_update"
  else
    print_message "Ошибка при скачивании скрипта" "$RED"
    exit_function
  fi
}

if [ "$1" = "script_update" ]; then
  script_update "main"
elif [ "$1" = "post_update" ]; then
  post_update
else
  main_menu
fi