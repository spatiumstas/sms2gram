#!/bin/sh

source /opt/root/sms2gram/config.sh
export LD_LIBRARY_PATH=/lib:/usr/lib:$LD_LIBRARY_PATH
INTERFACE_ID="$interface_id"
MESSAGE_ID="$message_id"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
SMS2GRAM_DIR="/opt/root/sms2gram"
SCRIPT="sms2gram.sh"
PATH_IFIPCHANGED="/opt/etc/ndm/ifipchanged.d/01-sms2gram.sh"
SCRIPT_VERSION="v1.2.1"
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/spatiumstas/sms2gram/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')

if [ "${DEBUG:-0}" = "1" ]; then
  exec 19> $LOG_FILE
  BASH_XTRACEFD=19
  set -x
fi

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

mark_sms_read() {
  ndmc -c sms "$INTERFACE_ID" read "$MESSAGE_ID"
}

delete_sms() {
  ndmc -c sms "$INTERFACE_ID" delete "$MESSAGE_ID"
}

check_symbolic_link() {
  if [ ! -f "$PATH_IFIPCHANGED" ]; then
    ln -s $PATH_SMSD $PATH_IFIPCHANGED
  fi
}

internet_checker() {
  if ! ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    error "Нет доступа к интернету. Проверьте подключение."
  fi

  if ! ping -c 2 -W 2 api.telegram.org >/dev/null 2>&1; then
    error "Нет доступа к api.telegram.org"
  fi
}

clean_log() {
  local max_size=524288

  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi

  local current_size=$(wc -c <"$LOG_FILE")
  if [ $current_size -gt $max_size ]; then
    sed -i '1,100d' "$LOG_FILE"
    log "Лог-файл был обрезан на первые 100 строк."
  fi
}

parse_sms() {
  local sms_data="$1"
  local sender timestamp text

  sender=$(echo "$sms_data" | awk '/from:/ {print $2}')
  timestamp=$(echo "$sms_data" | awk '/timestamp:/ {print substr($0, index($0,$2))}')
  text=$(echo "$sms_data" | awk '
        BEGIN {text=""; in_text_section=0}
        /text:/ {
            text=substr($0, index($0,$2))
            in_text_section=1
            next
        }
        /^[[:space:]]+/ {
            if (in_text_section) {
                text=text " " $0
            }
            next
        }
        END {
            gsub(/[[:space:]]+/, " ", text)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
            print text
        }')

  jq -n --arg sender "$sender" --arg timestamp "$timestamp" --arg text "$text" \
    '{"sender": $sender, "timestamp": $timestamp, "text": $text}'
}

send_to_telegram() {
  local sender="$1"
  local timestamp="$2"
  local text="$3"
  local escaped_text
  local retry_count=0
  local max_retries=3
  local retry_delay=5

  if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
    error "Не настроены BOT_TOKEN/CHAT_ID в конфиге. Отправка в Telegram пропущена."
    return 2
  fi
  internet_checker

  escaped_text=$(echo "$text" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

  local message
  if [ -z "$sender" ] && [ -z "$timestamp" ]; then
    message="$escaped_text"
  else
    local model
    model=$(get_model)
    model=${model:-"[Unknown Model]"}
    message=$(printf "%s\n\n<b>Сообщение от:</b> %s\n<b>Дата:</b> %s\n\n<b>Текст:</b> %s" \
      "$model" "$sender" "$timestamp" "$escaped_text")
  fi

  local chat_id="${CHAT_ID%%_*}"
  local topic_id="${CHAT_ID#*_}"

  if [ "$chat_id" = "$CHAT_ID" ]; then
    topic_id=""
  fi

  local payload
  if [ -n "$topic_id" ]; then
    payload=$(jq -n --arg text "$message" --argjson chat_id "$chat_id" --argjson topic_id "$topic_id" \
      '{chat_id: $chat_id, message_thread_id: $topic_id, parse_mode: "HTML", text: $text}')
  else
    payload=$(jq -n --arg text "$message" --argjson chat_id "$CHAT_ID" \
      '{chat_id: $chat_id, parse_mode: "HTML", text: $text}')
  fi

  while [ $retry_count -lt $max_retries ]; do
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      -H "Content-Type: application/json" \
      -d "$payload")

    if echo "$response" | grep -q '"ok":true'; then
      log "Сообщение успешно отправлено."
      if [ "$MARK_READ_MESSAGE_AFTER_SEND" = "1" ] && [ -n "$INTERFACE_ID" ] && [ -n "$MESSAGE_ID" ]; then
        mark_sms_read
      fi
      return 0
    else
      error "Ошибка отправки в Telegram: $response"
      retry_count=$((retry_count + 1))
      if [ $retry_count -lt $max_retries ]; then
        log "Повторная попытка отправки через $retry_delay секунд... (попытка $retry_count из $max_retries)"
        sleep $retry_delay
      fi
    fi
  done

  return 1
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

  if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
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
  updated_queue=$(echo "$current_queue" | jq --argjson msg "$sms_json" '. + [$msg]')

  if [ $? -eq 0 ]; then
    echo "$updated_queue" >"$PENDING_FILE"
    log "Сообщение сохранено в очередь: $sms_json"
  else
    error "Ошибка обновления очереди сообщений."
  fi
}

send_pending_messages() {
  if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
    return
  fi
  if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
    echo "[]" >"$PENDING_FILE"
    return
  fi

  local pending
  pending=$(cat "$PENDING_FILE")

  if [ "$(echo "$pending" | jq length)" -eq 0 ]; then
    return
  fi

  echo "$pending" | jq -c '.[]' | while read -r message; do
    local sender text timestamp
    sender=$(echo "$message" | jq -r '.sender')
    text=$(echo "$message" | jq -r '.text')
    timestamp=$(echo "$message" | jq -r '.timestamp')

    log "Отправка сохранённого сообщения от $sender ($timestamp)..."
    if send_to_telegram "$sender" "$timestamp" "$text"; then
      log "Сохранённое сообщение отправлено."
      pending=$(echo "$pending" | jq --arg s "$sender" --arg t "$text" --arg ts "$timestamp" \
        'del(.[] | select(.sender == $s and .text == $t and .timestamp == $ts))')
      echo "$pending" >"$PENDING_FILE"
    else
      log "Не удалось отправить сообщение от $sender."
    fi
  done

  if [ "$(echo "$pending" | jq length)" -eq 0 ]; then
    echo "[]" >"$PENDING_FILE"
  fi
}

main() {
  clean_log
  check_symbolic_link
  if [ -n "$INTERFACE_ID" ] && [ -n "$MESSAGE_ID" ]; then
    log "Запуск скрипта. INTERFACE_ID=$INTERFACE_ID, MESSAGE_ID=$MESSAGE_ID"
  fi

  if [ "$1" = "hook" ]; then
    if [ -z "$INTERFACE_ID" ] && [ -z "$MESSAGE_ID" ]; then
      send_pending_messages
      return
    fi
  fi

  send_pending_messages
  if [ $# -gt 1 ]; then
    local CUSTOM_MESSAGE="$2"
    log "Отправка кастомного сообщения: $CUSTOM_MESSAGE"
    send_to_telegram "" "" "$CUSTOM_MESSAGE"
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

  if ! echo "$sms_json" | jq empty 2>/dev/null; then
    error "Ошибка: Некорректный JSON в sms_json: $sms_json"
    return
  fi

  local sender text timestamp
  sender=$(echo "$sms_json" | jq -r '.sender')
  text=$(echo "$sms_json" | jq -r '.text')
  timestamp=$(echo "$sms_json" | jq -r '.timestamp')

  if [ -n "${BLACK_LIST:-}" ]; then
    if echo "$BLACK_LIST" \
      | tr ',' '\n' \
      | sed 's/^[ \t]*//;s/[ \t]*$//' \
      | grep -Fx -- "$sender" >/dev/null 2>&1; then
      log "Отправитель $sender в чёрном списке. Удаляю SMS и пропускаю отправку в Telegram."
      delete_sms
      return
    fi
  fi

  if [ -n "${REBOOT_KEY:-}" ] && echo "$text" | grep -Fqi -- "$REBOOT_KEY"; then
    log "Обнаружено слово "$text". Удаляю SMS и ухожу в перезагрузку."
    delete_sms
    ndmc -c system reboot
    return
  fi

  log "Получено сообщение от $sender: $text"

  if ! send_to_telegram "$sender" "$timestamp" "$text"; then
    if [ -n "${BOT_TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ]; then
      save_pending_message "$sms_json"
    fi
  fi

  if [ "${DEBUG:-0}" = "1" ]; then
    exec 19>&-
  fi
}

check_update() {
  local local_num=$(echo "${SCRIPT_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + $3}')
  local remote_num=$(echo "${REMOTE_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + ($3 == "" ? 0 : $3)}')

  if [ "$remote_num" -gt "$local_num" ]; then
    log "Доступна новая версия: $REMOTE_VERSION. Обновляюсь..."
    "$SMS2GRAM_DIR/$SCRIPT" "script_update"
  fi
}

main "$@"
check_update