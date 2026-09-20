#!/bin/sh
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
CONFIG_FILE="$SMS2GRAM_DIR/config.conf"
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
  echo "1. Отправить тестовое сообщение"
  echo "2. Параметры"
  echo "3. Показать конфиг"
  echo "4. Показать логи"
  printf "\n99. Обновить скрипт\n"
  echo "00. Выход"
  echo ""
}

main_menu() {
  while true; do
    print_menu
    if ! read -r -p "Выберите действие: " choice; then
      echo ""
      exit 0
    fi
    echo ""
    choice=$(echo "$choice" | tr -d '\032' | tr -d '[A-Z]')

    if [ -z "$choice" ]; then
      continue
    fi
    case "$choice" in
    1) send_test_message ;;
    2) settings_menu ;;
    3) show_config ;;
    4) show_logs ;;
    99) script_update "interactive" ;;
    00) exit 0 ;;
    *)
      echo "Неверный выбор. Попробуйте снова."
      sleep 1
      ;;
    esac
  done
}

print_message() {
  message="$1"
  color="${2:-$NC}"
  border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
  sleep 2
}

exit_function() {
  echo ""
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  exec "$SMS2GRAM_DIR/$SCRIPT"
}

get_config_raw() {
  local key="$1"
  grep "^$key=" "$CONFIG_FILE" 2>/dev/null | head -n 1 | cut -d '=' -f2-
}

get_config_value() {
  local key="$1"
  get_config_raw "$key" | sed 's/^"//;s/"$//'
}

append_config_line() {
  local line="$1"
  [ -f "$CONFIG_FILE" ] || : >"$CONFIG_FILE"

  if [ -s "$CONFIG_FILE" ]; then
    local last_char
    last_char=$(tail -c 1 "$CONFIG_FILE" 2>/dev/null)
    [ -n "$last_char" ] && printf '\n' >>"$CONFIG_FILE"
  fi

  printf '%s\n' "$line" >>"$CONFIG_FILE"
}

set_config_value() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
  else
    append_config_line "$key=\"$value\""
  fi
}

toggle_boolean_option() {
  local key="$1"
  local current_value
  current_value=$(get_config_value "$key")

  case "$current_value" in
    true | false) ;;
    *) current_value="false" ;;
  esac

  if [ "$current_value" = "true" ]; then
    if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s/^$key=.*/$key=false/" "$CONFIG_FILE"
    else
      append_config_line "$key=false"
    fi
  else
    if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s/^$key=.*/$key=true/" "$CONFIG_FILE"
    else
      append_config_line "$key=true"
    fi
  fi
}

set_config_number() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
  else
    append_config_line "$key=$value"
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
  mkdir -p "$SMS2GRAM_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Файл конфигурации не найден. Переустановите пакет $REPO" "$RED"
    return 1
  fi

  if [ ! -f "$SMS2GRAM_DIR/$SMSD" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/$SMSD" --output "$SMS2GRAM_DIR/$SMSD"
    chmod +x "$SMS2GRAM_DIR/$SMSD"
    ln -sf "$SMS2GRAM_DIR/$SMSD" "$PATH_SMSD"
  fi

  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
}

setup_telegram_settings() {
  check_config
  current_token=$(get_config_value "BOT_TOKEN")
  current_chat=$(get_config_value "CHAT_ID")
  current_proxy_interface=$(get_config_value "PROXY_INTERFACE")
  current_proxy_url=$(get_config_value "PROXY_URL")
  echo "00. Назад"

  read -p "Введите токен бота Telegram (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_token=""
  elif [ -n "$value" ]; then
    current_token="$value"
  fi

  read -p "Введите ID пользователя/чата Telegram (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_chat=""
  elif [ -n "$value" ]; then
    current_chat="$value"
  fi

  read -p "Введите прокси-интерфейс, например nwg0 (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_proxy_interface=""
  elif [ -n "$value" ]; then
    current_proxy_interface="$value"
  fi

  read -p "Введите прокси-ссылку, например socks5://127.0.0.1:1080 (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_proxy_url=""
  elif [ -n "$value" ]; then
    current_proxy_url="$value"
  fi

  set_config_value "BOT_TOKEN" "$current_token"
  set_config_value "CHAT_ID" "$current_chat"
  set_config_value "PROXY_INTERFACE" "$current_proxy_interface"
  set_config_value "PROXY_URL" "$current_proxy_url"
  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  print_message "Параметры Telegram обновлены" "$GREEN"
}

setup_vk_settings() {
  check_config
  current_token=$(get_config_value "VK_TOKEN")
  current_chat=$(get_config_value "VK_CHAT_ID")
  echo "00. Назад"

  read -p "Введите токен бота ВКонтакте (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_token=""
  elif [ -n "$value" ]; then
    current_token="$value"
  fi

  read -p "Введите ID пользователя/чата ВКонтакте (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_chat=""
  elif [ -n "$value" ]; then
    current_chat="$value"
  fi

  set_config_value "VK_TOKEN" "$current_token"
  set_config_value "VK_CHAT_ID" "$current_chat"
  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  print_message "Параметры ВКонтакте обновлены" "$GREEN"
}

setup_ntfy_settings() {
  check_config
  current_url=$(get_config_value "NTFY_URL")
  echo "00. Назад"
  read -p "Введите URL ntfy (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_url=""
  elif [ -n "$value" ]; then
    current_url="$value"
  fi
  set_config_value "NTFY_URL" "$current_url"
  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  print_message "Параметры ntfy обновлены" "$GREEN"
}

setup_sms_forward_settings() {
  check_config
  current_number=$(get_config_value "SMS_FORWARD_TO")
  echo "00. Назад"
  read -p "Введите номер для SMS-переадресации (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_number=""
  elif [ -n "$value" ]; then
    current_number="$value"
  fi
  set_config_value "SMS_FORWARD_TO" "$current_number"
  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  print_message "Параметры SMS-переадресации обновлены" "$GREEN"
}

setup_filter_settings() {
  check_config
  while true; do
    printf "\033c"
    printf "Чёрные и белые списки:\n\n"
    printf "1. Чёрный список отправителей: %s\n" "$(get_config_value "BLACK_LIST")"
    printf "2. Белый список отправителей: %s\n" "$(get_config_value "WHITE_LIST")"
    printf "3. Чёрный список фраз в тексте: %s\n" "$(get_config_value "TEXT_BLACK_LIST")"
    printf "4. Белый список фраз в тексте: %s\n" "$(get_config_value "TEXT_WHITE_LIST")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр: " setting_choice
    echo ""

    case "$setting_choice" in
      00) return 0 ;;
      1) update_config_value "Черный список отправителей через запятую (Enter = оставить, '-' = очистить): " "BLACK_LIST" ;;
      2) update_config_value "Белый список отправителей через запятую (Enter = оставить, '-' = очистить): " "WHITE_LIST" ;;
      3) update_config_value "Черный список фраз в тексте (через запятую; Enter = оставить, '-' = очистить): " "TEXT_BLACK_LIST" ;;
      4) update_config_value "Белый список фраз в тексте (через запятую; Enter = оставить, '-' = очистить): " "TEXT_WHITE_LIST" ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac

    dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  done
}

setup_command_settings() {
  check_config
  while true; do
    printf "\033c"
    printf "Команды и перезагрузка:\n\n"
    printf "1. Разрешить отправку AT-команд из SMS: %s\n" "$(get_config_value "AT_COMMANDS_ENABLED")"
    printf "2. Выполнение CLI-команд из SMS: %s\n" "$(get_config_value "CLI_COMMANDS_ENABLED")"
    printf "3. Фраза для перезагрузки устройства: %s\n" "$(get_config_value "REBOOT_KEY")"
    printf "4. Действие при недоступности SIM-карты: %s\n" "$(get_config_value "REBOOT_SIM_IF_INVALID")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр: " setting_choice
    echo ""

    case "$setting_choice" in
      00) return 0 ;;
      1) toggle_boolean_option "AT_COMMANDS_ENABLED" ;;
      2)
        read -p "Выполнение CLI-команд из SMS (0 - выключено, 1 - выполнить, 2 - выполнить и сохранить конфигурацию): " value
        case "$value" in
          0 | 1 | 2) set_config_number "CLI_COMMANDS_ENABLED" "$value" ;;
          "") ;;
          *) print_message "Допустимы значения 0, 1 или 2" "$RED" ;;
        esac
        ;;
      3) update_config_value "Каким словом в SMS перезагружать устройство? (Enter = оставить, '-' = очистить): " "REBOOT_KEY" ;;
      4)
        read -p "Что перезагружать при недоступности SIM-карты? (0 - ничего, 1 - модем, 2 - роутер): " value
        case "$value" in
          0 | 1 | 2) set_config_number "REBOOT_SIM_IF_INVALID" "$value" ;;
          "") ;;
          *) print_message "Допустимы значения 0, 1 или 2" "$RED" ;;
        esac
        ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac

    dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  done
}

setup_runtime_settings() {
  check_config
  while true; do
    printf "\033c"
    printf "Обработка сообщений и обновления:\n\n"
    printf "1. Помечать сообщение прочитанным после отправки: %s\n" "$(get_config_value "MARK_READ_MESSAGE_AFTER_SEND")"
    printf "2. Удалять сообщение после отправки: %s\n" "$(get_config_value "DELETE_MESSAGE_AFTER_SEND")"
    printf "3. Автоматически обновлять sms2gram: %s\n" "$(get_config_value "AUTO_UPDATE")"
    printf "4. Включить отладку: %s\n" "$(get_config_value "DEBUG")"
    printf "5. RCI-токен: %s\n" "$(get_config_value "RCI_TOKEN")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр: " setting_choice
    echo ""

    case "$setting_choice" in
      00) return 0 ;;
      1) toggle_boolean_option "MARK_READ_MESSAGE_AFTER_SEND" ;;
      2) toggle_boolean_option "DELETE_MESSAGE_AFTER_SEND" ;;
      3) toggle_boolean_option "AUTO_UPDATE" ;;
      4) toggle_boolean_option "DEBUG" ;;
      5) update_config_value "Введите RCI токен (Enter = оставить, '-' = очистить): " "RCI_TOKEN" ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac

    dos2unix "$CONFIG_FILE" >/dev/null 2>&1
  done
}

settings_menu() {
  check_config
  while true; do
    printf "\033c"
    printf "Параметры sms2gram:\n\n"
    echo "1. Telegram"
    echo "2. ВКонтакте"
    echo "3. ntfy"
    echo "4. SMS-переадресация"
    echo "5. Чёрные и белые списки"
    echo "6. Команды и перезагрузка"
    echo "7. Обработка сообщений, обновления и RCI-токен"
    echo "00. Назад"
    echo ""
    read -p "Выберите действие: " action
    echo ""

    case "$action" in
      1) setup_telegram_settings ;;
      2) setup_vk_settings ;;
      3) setup_ntfy_settings ;;
      4) setup_sms_forward_settings ;;
      5) setup_filter_settings ;;
      6) setup_command_settings ;;
      7) setup_runtime_settings ;;
      00) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

check_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Не выполнена начальная конфигурация" "$RED"
    exit_function
  fi
}

show_config() {
  check_config
  printf "${GREEN}"
  cat "$CONFIG_FILE"
  printf "${NC}\n"
  exit_function
}

show_logs() {
  check_config
  if [ -f "$LOG" ]; then
    cat "$LOG"
  else
    echo "Лог-файл пока не создан"
  fi
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
  local mode="${1:-interactive}"
  packages_checker "curl jq ca-certificates wget-ssl"

  if opkg update && opkg install "$REPO"; then
    if [ "$mode" = "silent" ]; then
      logger -p notice -t sms2gram "Пакет обновлён в silent-режиме"
      exit 0
    fi
    print_message "Пакет обновлён" "$GREEN"
    sleep 1
    exec "$SMS2GRAM_DIR/$SCRIPT"
  else
    if [ "$mode" = "silent" ]; then
      logger -p err -t sms2gram "Ошибка при обновлении пакета"
      exit 1
    else
      print_message "Не удалось обновить пакет. Выполните обновление вручную." "$RED"
    fi
  fi
}

if [ "$1" = "script_update" ]; then
  script_update "$2"
else
  setup_config
  main_menu
fi
