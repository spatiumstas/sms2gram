#!/bin/sh

source /opt/root/sms2gram/config.sh

INTERFACE_ID="$interface_id"
MESSAGE_ID="$message_id"

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
  ndmc -c show version | grep "model" | awk -F": " '{print $2}' 2>/dev/null
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
  local model
  local message
  model=$(get_model)

  if [ -z "$text" ]; then
    error "Пустое сообщение, отправка невозможна."
    return 1
  fi

  if [ -z "$model" ]; then
    model="[Unknown Model]"
  else
    model="«$model»"
  fi

  escaped_text=$(echo "$text" | sed 's/"/\\"/g')
  message=$(printf "%s\n\n<b>Сообщение от:</b> %s\n<b>Дата:</b> %s\n\n<b>Текст:</b> %s" \
    "$model" "$sender" "$timestamp" "$escaped_text")

  local payload
  payload=$(printf '{"chat_id":%s,"parse_mode":"HTML","text":"%s"}' "$CHAT_ID" "$message")
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
  local updated_pending="[]"

  echo "$pending" | jq -c '.[]' | while read -r message; do
    local sender text timestamp
    sender=$(echo "$message" | jq -r '.sender')
    text=$(echo "$message" | jq -r '.text')
    timestamp=$(echo "$message" | jq -r '.timestamp')

    log "Отправка сохранённого сообщения от $sender ($timestamp)..."
    if send_to_telegram "$sender" "$timestamp" "$text"; then
      log "Сохранённое сообщение отправлено."
    else
      updated_pending=$(echo "$updated_pending" | jq ". += [$message]")
    fi
  done

  echo "$updated_pending" >"$PENDING_FILE"
}

main() {
  log "Запуск скрипта. INTERFACE_ID=$INTERFACE_ID, MESSAGE_ID=$MESSAGE_ID"

  send_pending_messages

  if [ -z "$INTERFACE_ID" ] || [ -z "$MESSAGE_ID" ]; then
    error "Не получены переменные окружения interface_id или message_id."
    exit 1
  fi

  local sms_data
  sms_data=$(get_sms_data)
  if [ -z "$sms_data" ]; then
    error "Не удалось получить данные SMS с ID $MESSAGE_ID."
    exit 1
  fi

  local sms_json
  sms_json=$(parse_sms "$sms_data")
  if [ -z "$sms_json" ]; then
    error "Ошибка парсинга SMS."
    exit 1
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

main "$@"
