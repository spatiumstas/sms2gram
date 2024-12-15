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
                       ___
   _________ ___  ____|__ \ ____ __________ _____ ___
  / ___/ __ `__ \/ ___/_/ // __ `/ ___/ __ `/ __ `__ \
 (__  ) / / / / (__  ) __// /_/ / /  / /_/ / / / / / /
/____/_/ /_/ /_/____/____/\__, /_/   \__,_/_/ /_/ /_/
                         /____/
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
    88) script_update "dev" ;;
    99) script_update "main" ;;
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
  local message=$1
  local color=${2:-$NC}
  local border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
  sleep 1
}

clear_config() {
  sed -i 's|^BOT_TOKEN=.*|BOT_TOKEN=""|' "$CONFIG_FILE"
  sed -i 's|^CHAT_ID=.*|CHAT_ID=""|' "$CONFIG_FILE"

  print_message "Конфигурация очищена в $CONFIG_FILE" "$GREEN"
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

download_file() {
  local url="$1"
  local path="$2"
  local filename=$(basename "$path")
  echo "Скачиваю файл $filename..."

  if ! curl -s -f -o "$path" "$url"; then
    print_message "Ошибка при скачивании файла $filename. Возможно, файл не найден" "$RED"
    read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
    main_menu
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

  read -p "Введите токен бота Telegram: " BOT_TOKEN
  BOT_TOKEN=$(echo "$BOT_TOKEN" | sed 's/^[ \t]*//;s/[ \t]*$//')

  read -p "Введите ID чата Telegram: " CHAT_ID
  CHAT_ID=$(echo "$CHAT_ID" | sed 's/^[ \t]*//;s/[ \t]*$//')

  sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=\"$BOT_TOKEN\"|" "$CONFIG_FILE"
  sed -i "s|^CHAT_ID=.*|CHAT_ID=\"$CHAT_ID\"|" "$CONFIG_FILE"
  dos2unix "$CONFIG_FILE"

  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

remove_script() {
  echo "Удаляю директорию $SMS2GRAM_DIR..."
  rm -r "$SMS2GRAM_DIR" 2>/dev/null
  wait
  echo "Удаляю файл $PATH_SMSD..."
  rm -r "$PATH_SMSD" 2>/dev/null
  wait

  print_message "Успешно удалено" "$GREEN"
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
    opkg update && opkg install curl jq
    wait
    echo ""
  fi
}

test_message_send() {
  interfaces_list=$(ndmc -c show interface | grep -A 4 -E "UsbLte|UsbQmi" | grep "id:" | awk '{print NR ") " $2}')
  echo "$interfaces_list"
  echo ""
  read -p "Выберите интерфейс для тестового сообщения: " choices
  echo ""

  if [ -z "$choices" ]; then
    echo "Ошибка: Вы не выбрали интерфейсы."
    return
  fi

  interfaces=""
  for choice in $choices; do
    interface=$(echo "$interfaces_list" | awk -v choice="$choice" 'NR == choice {print $2}')
    if [ -n "$interface" ]; then
      interfaces="$interfaces $interface"
    else
      echo "Ошибка: Интерфейс с номером $choice не найден."
    fi
  done

  if [ -n "$interfaces" ]; then
    interfaces=$(echo "$interfaces" | sed 's/^[ \t]*//;s/[ \t]*$//')
  else
    echo "Ошибка: Не выбраны интерфейсы."
    return
  fi
  selected_interface=$(echo "$interfaces" | awk '{print $1}')
  echo "Выбран интерфейс: $selected_interface"

  nv_value=$(ndmc -c sms "$selected_interface" list | grep -o "nv-[0-9]\+" | head -n 1)

  if [ -n "$nv_value" ]; then
    echo ""
    interface_id="$selected_interface" message_id="$nv_value" $PATH_SMSD
    print_message "Сообщение отправлено" "$GREEN"
  else
    print_message "На модеме $selected_interface нет SMS для отправки" "$RED"
  fi
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

script_update() {
  BRANCH="$1"
  packages_checker
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$MAIN_NAME" --output $TMP_DIR/$MAIN_NAME
  curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SMSD" --output $PATH_SMSD
  chmod +x $PATH_SMSD

  if [ -f "$TMP_DIR/$MAIN_NAME" ]; then
    mv "$TMP_DIR/$MAIN_NAME" "$OPT_DIR/$MAIN_NAME"
    chmod +x $OPT_DIR/$MAIN_NAME
    cd $OPT_DIR/bin
    ln -sf $OPT_DIR/$MAIN_NAME $OPT_DIR/bin/sms2gram
    if [ "$BRANCH" = "dev" ]; then
      print_message "Скрипт успешно обновлён на $BRANCH ветку..." "$GREEN"
      sleep 2
    else
      print_message "Скрипт успешно обновлён" "$GREEN"
      sleep 2
    fi
    $OPT_DIR/$MAIN_NAME
  else
    print_message "Ошибка при скачивании скрипта" "$RED"
  fi
}

main_menu
