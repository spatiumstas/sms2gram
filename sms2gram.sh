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
LOG="/opt/var/log/sms2gram.log"
SMSD="01-sms2gram.sh"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
CONFIG_FILE="$SMS2GRAM_DIR/config.sh"
SCRIPT_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[^"]+' "$SMS2GRAM_DIR/$SMSD")
SMS2GRAM_REPO_FILE="/opt/etc/opkg/sms2gram.conf"

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

update_config_value() {
  local prompt="$1"
  local key="$2"
  local value
  local key_exists=0

  if grep -q "^$key=" "$CONFIG_FILE"; then
    key_exists=1
  fi

  read -p "$prompt" value
  value=$(echo "$value" | sed 's/^[ \t]*//;s/[ \t]*$//')

  if [ "$value" = "-" ]; then
    if [ "$key_exists" -eq 1 ]; then
      sed -i "s|^$key=.*|$key=\"\"|" "$CONFIG_FILE"
    else
      echo "$key=\"\"" >>"$CONFIG_FILE"
    fi
    return
  fi

  if [ -n "$value" ]; then
    if [ "$key_exists" -eq 1 ]; then
      sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
    else
      echo "$key=\"$value\"" >>"$CONFIG_FILE"
    fi
  elif [ "$key_exists" -eq 0 ]; then
    echo "$key=\"\"" >>"$CONFIG_FILE"
  fi
}

setup_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Конфигурационный файл не найден: $CONFIG_FILE. Переустановите пакет" "$RED"
    exit_function
  fi
  if [ ! -f "$SMS2GRAM_DIR/$SMSD" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/$SMSD" --output "$SMS2GRAM_DIR/$SMSD"
    chmod +x "$SMS2GRAM_DIR/$SMSD"
    ln -sf "$SMS2GRAM_DIR/$SMSD" "$PATH_SMSD"
  fi

  update_config_value "Введите токен бота Telegram (пусто — без изменений, '-' — очистить): " "BOT_TOKEN"
  update_config_value "Введите ID пользователя/чата Telegram (пусто — без изменений, '-' — очистить): " "CHAT_ID"
  update_config_value "Введите токен бота VK (пусто — без изменений, '-' — очистить): " "VK_TOKEN"
  update_config_value "Введите ID пользователя/чата ВКонтакте (пусто — без изменений, '-' — очистить): " "VK_CHAT_ID"
  update_config_value "Введите номер для SMS-переадресации (пусто — без изменений, '-' — очистить): " "SMS_FORWARD_TO"
  update_config_value "Введите прокси-интерфейс, например nwg0 (пусто — без изменений, '-' — очистить): " "PROXY_INTERFACE"
  update_config_value "Помечать сообщение прочитанным после успешной отправки? (1 - да, 0 - нет): " "MARK_READ_MESSAGE_AFTER_SEND"
  update_config_value "Удалять сообщение после успешной отправки? (1 - да, 0 - нет): " "DELETE_MESSAGE_AFTER_SEND"
  update_config_value "Каким словом в SMS перезагружать устройство? (пусто — без изменений, '-' — очистить): " "REBOOT_KEY"
  update_config_value "Черный список отправителей через запятую (пусто — без изменений, '-' — очистить): " "BLACK_LIST"
  update_config_value "Белый список отправителей через запятую (пусто — без изменений, '-' — очистить): " "WHITE_LIST"
  update_config_value "Черный список фраз в тексте (через запятую; пусто — без изменений, '-' — очистить): " "TEXT_BLACK_LIST"
  update_config_value "Белый список фраз в тексте (через запятую; пусто — без изменений, '-' — очистить): " "TEXT_WHITE_LIST"
  update_config_value "Разрешить отправку AT-команд из SMS? (1 - да, 0 - нет): " "AT_COMMANDS_ENABLED"
  update_config_value "Что перезагружать при недоступности SIM-карты? (2 - роутер, 1 - модем, 0 - ничего): " "REBOOT_SIM_IF_INVALID"
  update_config_value "Включить отладку? (1 - да, 0 - нет): " "DEBUG"

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
  cat "$LOG"
  echo ""
  exit_function
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
    opkg update && opkg install curl jq
    echo ""
  fi
}

is_ipk_installed() {
  [ -n "$(opkg status "$REPO" 2>/dev/null)" ]
}

ensure_ipk_repo_file() {
  if [ -f "$SMS2GRAM_REPO_FILE" ]; then
    return 0
  fi
  print_message "Добавляю репозиторий для установки через OPKG..."
  mkdir -p /opt/etc/opkg
  echo "src/gz $REPO https://spatiumstas.github.io/$REPO/all" >"$SMS2GRAM_REPO_FILE"
}

migrate_to_ipk_if_needed() {
  if is_ipk_installed; then
    return
  fi

  ensure_ipk_repo_file || return
  print_message "Устанавливаю пакет через OPKG..."
  opkg update && opkg install "$REPO"
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

script_update() {
  BRANCH="$1"
  packages_checker

  if is_ipk_installed; then
    ensure_ipk_repo_file
    if opkg update && opkg install "$REPO"; then
      print_message "Пакет обновлён через OPKG" "$GREEN"
    else
      print_message "Не удалось обновить пакет через OPKG" "$RED"
    fi
    sleep 1
    exec "$SMS2GRAM_DIR/$SCRIPT"
    return
  fi

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
    exec "$SMS2GRAM_DIR/$SCRIPT"
  else
    print_message "Ошибка при скачивании скрипта" "$RED"
    exit_function
  fi
}

if [ "$1" = "script_update" ]; then
  script_update "main"
else
  migrate_to_ipk_if_needed
  main_menu
fi
