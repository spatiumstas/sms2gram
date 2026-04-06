#!/bin/sh

SYSTEM_LD_LIBRARY_PATH="/lib:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
OPKG_LD_LIBRARY_PATH="/opt/lib:/opt/usr/lib:/lib:/usr/lib"
export LD_LIBRARY_PATH="$OPKG_LD_LIBRARY_PATH"
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
                       ___                           
   _________ ___  ____|__ \____ __________ _____ ___ 
  / ___/ __ `__ \/ ___/_/ / __ `/ ___/ __ `/ __ `__ \
 (__  ) / / / / (__  ) __/ /_/ / /  / /_/ / / / / / /
/____/_/ /_/ /_/____/____|__, /_/   \__,_/_/ /_/ /_/ 
                        /____/                       
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
    2) send_test_message ;;
    3) show_config ;;
    4) show_logs ;;
    99) script_update ;;
    00) exit 0 ;;
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
  echo ""
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
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
  update_config_value "Введите токен бота ВКонтакте (пусто — без изменений, '-' — очистить): " "VK_TOKEN"
  update_config_value "Введите ID пользователя/чата ВКонтакте (пусто — без изменений, '-' — очистить): " "VK_CHAT_ID"
  update_config_value "Введите номер для SMS-переадресации (пусто — без изменений, '-' — очистить): " "SMS_FORWARD_TO"
  update_config_value "Введите прокси-интерфейс, например nwg0 (пусто — без изменений, '-' — очистить): " "PROXY_INTERFACE"
  update_config_value "Введите прокси-ссылку, например socks5:// (пусто — без изменений, '-' — очистить): " "PROXY_URL"
  update_config_value "Помечать сообщение прочитанным после отправки? (1 - да, 0 - нет): " "MARK_READ_MESSAGE_AFTER_SEND"
  update_config_value "Удалять сообщение после отправки? (1 - да, 0 - нет): " "DELETE_MESSAGE_AFTER_SEND"
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
  exit_function
}

packages_checker() {
  local packages="$1"
  local flag="$2"
  local missing=""
  local installed
  installed=$(opkg list-installed 2>/dev/null)

  for pkg in $packages; do
    if ! echo "$installed" | grep -q "^$pkg "; then
      missing="$missing $pkg"
    fi
  done

  if [ -n "$missing" ]; then
    print_message "Устанавливаем:$missing" "$GREEN"
    opkg update >/dev/null 2>&1
    opkg install $missing $flag
    echo ""
  fi
}

send_test_message() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Выполните настройку скрипта" "$RED"
    exit_function
  fi

  print_message "Отправляю тестовое сообщение" "$CYAN"
  "$SMS2GRAM_DIR/$SMSD" "" "Тестовое сообщение от SMS2GRAM"
  exit_function
}

script_update() {
  packages_checker "curl jq ca-certificates wget-ssl"

  if opkg update && opkg install "$REPO"; then
    print_message "Пакет обновлён" "$GREEN"
  else
    print_message "Не удалось обновить пакет. Выполните обновление вручную." "$RED"
  fi
  sleep 1
  exec "$SMS2GRAM_DIR/$SCRIPT"
}

if [ "$1" = "script_update" ]; then
  script_update
else
  main_menu
fi
