#!/bin/sh

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m'
USERNAME="spatiumstas"
USER="root"
REPO="sms2gram"
MAIN_NAME="sms2gram.sh"
TMP_DIR="/tmp"
OPT_DIR="/opt"

SMS2GRAM_DIR="/opt/root/sms2gram"
SMSD="01-sms2gram.sh"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
CONFIG_FILE="/opt/root/sms2gram/config.sh"

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
  printf "by ${USERNAME}\n"
  printf "${NC}"
  echo ""
  echo "1. Настроить"
  echo "2. Отправить тестовое сообщение"
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
    mkdir -p $SMS2GRAM_DIR
    cat <<EOL >"$CONFIG_FILE"
LOG_FILE="/opt/root/sms2gram/log.txt"
PENDING_FILE="/opt/root/sms2gram/pending_messages.json"

BOT_TOKEN=""
CHAT_ID=""

EOL
  fi
  if [ ! -f "$PATH_SMSD" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/$SMSD" --output $PATH_SMSD
    chmod +x $PATH_SMSD
  fi
  read -p "Введите токен бота Telegram: " BOT_TOKEN
  BOT_TOKEN=$(echo "$BOT_TOKEN" | sed 's/^[ \t]*//;s/[ \t]*$//')

  read -p "Введите ID пользователя/чата Telegram: " CHAT_ID
  CHAT_ID=$(echo "$CHAT_ID" | sed 's/^[ \t]*//;s/[ \t]*$//')

  sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=\"$BOT_TOKEN\"|" "$CONFIG_FILE"
  sed -i "s|^CHAT_ID=.*|CHAT_ID=\"$CHAT_ID\"|" "$CONFIG_FILE"
  dos2unix "$CONFIG_FILE"

  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
  exit_function
}

remove_script() {
  echo "Удаляю директорию $SMS2GRAM_DIR..."
  rm -r "$SMS2GRAM_DIR" 2>/dev/null
  wait
  echo "Удаляю файл $PATH_SMSD..."
  rm -r "$PATH_SMSD" 2>/dev/null
  wait

  print_message "Успешно удалено" "$GREEN"
  exit_function
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
    opkg update && opkg install curl jq
    wait
    echo ""
  fi
}

test_message_send() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Выполните настройку скрипта" "$RED"
    exit_function
  fi

  interfaces_list=$(ndmc -c show interface | grep -A 4 -E "Usb" | grep "id:" | awk '{print NR ") " $2}')

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
    interface_id="$selected_interface" message_id="$get_message_id" $PATH_SMSD
  else
    print_message "На модеме $selected_interface нет SMS для отправки. Отправляю тестовое" "$CYAN"
    $PATH_SMSD "" "Тестовое сообщение от SMS2GRAM"
  fi
  echo ""
  exit_function
}

script_update() {
  BRANCH="$1"
  packages_checker
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$MAIN_NAME" --output $TMP_DIR/$MAIN_NAME
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SMSD" --output $PATH_SMSD
  chmod +x $PATH_SMSD

  if [ -f "$TMP_DIR/$MAIN_NAME" ]; then
    mv "$TMP_DIR/$MAIN_NAME" "$OPT_DIR/$MAIN_NAME"
    chmod +x $OPT_DIR/$MAIN_NAME
    cd $OPT_DIR/bin
    ln -sf $OPT_DIR/$MAIN_NAME $OPT_DIR/bin/sms2gram
    if [ "$BRANCH" = "dev" ]; then
      print_message "Скрипт успешно обновлён на $BRANCH ветку..." "$GREEN"
      sleep 1
    else
      print_message "Скрипт успешно обновлён" "$GREEN"
      sleep 1
    fi
    $OPT_DIR/$MAIN_NAME
  else
    print_message "Ошибка при скачивании скрипта" "$RED"
  fi
}

if [ "$1" = "script_update" ]; then
  script_update "main"
else
  main_menu
fi
