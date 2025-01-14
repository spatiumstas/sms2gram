#!/bin/sh

source /opt/root/sms2gram/config.sh

INTERFACE_ID="$interface_id"
MESSAGE_ID="$message_id"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
PATH_IFIPCHANGED="/opt/etc/ndm/ifipchanged.d/01-sms2gram.sh"
REPO="spatiumstas/sms2gram"
LOCAL_VERSION="v1.1.1"
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE"
}

get_sms_data() {
  ndmc -c sms "$INTERFACE_ID" list id "$MESSAGE_ID" 2>/dev/null
}

get_model() {
  ndmc -c show version | grep "description" | awk -F": " '{print $2}' 2>/dev/null
}

check_symbolic_link() {
  if [ ! -f "$PATH_IFIPCHANGED" ]; then
    ln -s $PATH_SMSD $PATH_IFIPCHANGED
  fi
}

internet_checker() {
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    error "Нет доступа к интернету. Проверьте подключение."
    return
  fi
}

clean_log() {
  local log_file="$1"
  local max_size=524288
  local current_size=$(wc -c <"$log_file")

  if [ $current_size -gt $max_size ]; then
    sed -i '1,100d' "$log_file"
    log "Лог-файл был обрезан на первые 100 строк."
  fi
}

parse_sms() {
  local sms_data="$1"
  echo "$sms_data" | awk '
        BEGIN { sender=""; timestamp=""; text=""; in_text_section=0 }
        /from:/ { sender=$2 }
        /timestamp:/ { timestamp=substr($0, index($0,$2)) }
        /text:/ {
            text=substr($0, index($0,$2))
            in_text_section=1
            next
        }
        /^[[:space:]]+/ {
            if (in_text_section) text=text " " $0
        }
        END {
            gsub(/[[:space:]]+/, " ", text)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
            printf "{\"sender\":\"%s\", \"timestamp\":\"%s\", \"text\":\"%s\"}\n", sender, timestamp, gensub(/\"/, "\\\"", "g", text)
        }'
}

send_to_telegram() {
  local sender="$1"
  local timestamp="$2"
  local text="$3"
  local escaped_text
  internet_checker
  escaped_text=$(echo "$text" | sed 's/"/\\"/g; s/\*/\\*/g; s/_/\\_/g; s/`/\\`/g; s/\[/\\[/g; s/\]/\\]/g; s/\\/\\\\/g')

  local message
  if [ -z "$sender" ] && [ -z "$timestamp" ]; then
    message="$escaped_text"
  else
    local model
    model=$(get_model)
    if [ -z "$model" ]; then
      model="[Unknown Model]"
    else
      model="«$model»"
    fi
    message=$(printf "%s\n\n**Сообщение от:** %s\n**Дата:** %s\n\n**Текст:** %s" \
      "$model" "$sender" "$timestamp" "$escaped_text")
  fi

  local payload
  payload=$(printf '{"chat_id":%s,"parse_mode":"Markdown","text":"%s"}' "$CHAT_ID" "$message")

  local response
  response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$payload")

  if echo "$response" | grep -q '"ok":true'; then
    log "Сообщение успешно отправлено."
    return 0
  else
    error "Ошибка отправки в Telegram: $response"
    return 1
  fi
}

save_pending_message() {
  local sms_json="$1"
  local text

  if ! echo "$sms_json" | jq empty 2>/dev/null; then
    error "Ошибка: Некорректный JSON: $sms_json"
    return
  fi

  text=$(echo "$sms_json" | jq -r '.text')

  if [ -z "$text" ]; then
    error "Пустое сообщение не будет сохранено в очередь."
    return
  fi

  if [ ! -f "$PENDING_FILE" ]; then
    echo "[]" >"$PENDING_FILE"
  fi

  if ! jq empty "$PENDING_FILE" 2>/dev/null; then
    error "Файл очереди повреждён. Перезаписываем с новым сообщением."
    echo "[$sms_json]" >"$PENDING_FILE"
    return
  fi

  local current_queue
  current_queue=$(cat "$PENDING_FILE")

  local updated_queue
  updated_queue=$(echo "$current_queue" | jq ". + [$sms_json]")

  if [ $? -eq 0 ]; then
    echo "$updated_queue" >"$PENDING_FILE"
    log "Сообщение сохранено в очередь: $sms_json"
  else
    error "Ошибка обновления очереди сообщений."
  fi
}

send_pending_messages() {
  if [ ! -f "$PENDING_FILE" ]; then
    return
  fi

  local pending
  pending=$(cat "$PENDING_FILE")

  echo "$pending" | jq -c '.[]' | while read -r message; do
    local sender text timestamp
    sender=$(echo "$message" | jq -r '.sender')
    text=$(echo "$message" | jq -r '.text')
    timestamp=$(echo "$message" | jq -r '.timestamp')

    log "Отправка сохранённого сообщения от $sender ($timestamp)..."
    if send_to_telegram "$sender" "$timestamp" "$text"; then
      log "Сохранённое сообщение отправлено."
      pending=$(echo "$pending" | jq "del(.[] | select(.sender==\"$sender\" and .text==\"$text\" and .timestamp==\"$timestamp\"))")
      echo "$pending" >"$PENDING_FILE"
    else
      log "Не удалось отправить сообщение от $sender."
    fi
  done

  if [ "$(echo "$pending" | jq length)" -eq 0 ]; then
    echo "[]" >"$PENDING_FILE"
    log "Очередь сообщений очищена."
  fi
}

main() {
  clean_log "$LOG_FILE"
  check_symbolic_link
  log "Запуск скрипта. INTERFACE_ID=$INTERFACE_ID, MESSAGE_ID=$MESSAGE_ID"

  if [ "$1" = "hook" ]; then
    if [ -z "$INTERFACE_ID" ] && [ -z "$MESSAGE_ID" ]; then
      send_pending_messages
      return
    fi
  fi

  send_pending_messages
  if [ $# -gt 1 ]; then
    local CUSTOM_MESSAGE="$2"
    if send_to_telegram "" "" "$CUSTOM_MESSAGE"; then
      log "Тестовое сообщение успешно отправлено."
    else
      log "Не удалось отправить тестовое сообщение."
    fi
    return
  fi

  if [ -z "$INTERFACE_ID" ] || [ -z "$MESSAGE_ID" ]; then
    error "Не получены переменные interface_id или message_id."
    return
  fi

  local sms_data
  sms_data=$(get_sms_data)
  if [ -z "$sms_data" ]; then
    error "Не удалось получить данные SMS с ID $MESSAGE_ID."
    return
  fi

  local sms_json
  sms_json=$(parse_sms "$sms_data")
  if [ -z "$sms_json" ]; then
    error "Ошибка парсинга SMS."
    return
  fi

  local sender text timestamp
  sender=$(echo "$sms_json" | jq -r '.sender')
  text=$(echo "$sms_json" | jq -r '.text')
  timestamp=$(echo "$sms_json" | jq -r '.timestamp')

  log "Получено сообщение от $sender: $text"

  if ! send_to_telegram "$sender" "$timestamp" "$text"; then
    save_pending_message "$sms_json"
  fi
}

check_update() {
  local local_num=$(echo "${LOCAL_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + $3}')
  local remote_num=$(echo "${REMOTE_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + ($3 == "" ? 0 : $3)}')

  if [ "$remote_num" -gt "$local_num" ]; then
    log "Доступна новая версия: $REMOTE_VERSION. Обновляюсь..."
    sms2gram "script_update"
  fi
}

main "$@"
check_update
