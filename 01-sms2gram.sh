#!/bin/sh

source /opt/root/sms2gram/config.sh
export LD_LIBRARY_PATH=/lib:/usr/lib:$LD_LIBRARY_PATH
INTERFACE_ID="$interface_id"
IP_ID="$id"
MESSAGE_ID="$message_id"
PATH_SMSD="/opt/etc/ndm/sms.d/01-sms2gram.sh"
SMS2GRAM_DIR="/opt/root/sms2gram"
SCRIPT="sms2gram.sh"
PATH_IFIPCHANGED="/opt/etc/ndm/ifipchanged.d/01-sms2gram.sh"
SCRIPT_VERSION="v1.4"
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/spatiumstas/sms2gram/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
MODEM_PATTERN="UsbQmi[0-9]*|UsbLte[0-9]*"

if [ "${DEBUG:-0}" = "1" ]; then
  exec 19>$LOG_FILE
  BASH_XTRACEFD=19
  set -x
fi

rci() {
  local endpoint="$1"
  local body="${2:-}"
  if [ -n "$body" ]; then
    curl -s --header "Content-Type: application/json" --request POST --data "$body" http://localhost:79/rci/
  else
    curl -s "http://localhost:79/rci/$endpoint"
  fi
}

log() {
  local message="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
  echo "$message" | tee -a "$LOG_FILE"
  logger -p notice -t sms2gram "$*"
}

error() {
  local message="$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*"
  echo "$message" | tee -a "$LOG_FILE"
  logger -p err -t sms2gram "$*"
}

get_sms_data() {
  ndmc -c sms "$INTERFACE_ID" list id "$MESSAGE_ID" 2>/dev/null
}

get_model() {
  rci "show/version" | grep -o '"description": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

set_header() {
  local iface="${1:-$INTERFACE_ID}"
  local model modem_description
  model=$(get_model)
  model=${model:-"[Unknown Model]"}
  modem_description=$(get_modem_description "$iface")
  if [ -n "$modem_description" ]; then
    printf "%s | %s" "$model" "$modem_description"
  else
    printf "%s" "$model"
  fi
}

is_at_command() {
  local text="$1"
  echo "$text" | grep -Eiq '^[[:space:]]*at'
}

send_at_command() {
  local iface="$1"
  local text="$2"
  local output=""
  local reply
    local cmd
  if [ "${AT_COMMANDS_ENABLED:-0}" != "1" ]; then
    return 1
  fi

  cmd=$(printf '%s' "$text" | sed 's/^[[:space:]]*//')
  log "Получена AT-команда: $cmd"
  output=$(ndmc -c interface "$iface" tty send "$cmd" 2>&1 | tr -d '\r' | sed 's/\[K//g')
  local header
  header=$(set_header "$iface")

  reply=$(printf "%s\n\nAT-команда: %s\nИнтерфейс: %s\nОтвет модема:\n\n%s" "$header" "$cmd" "$iface" "$output")
  send_to_telegram "" "" "$reply" "$iface"
  return 0
}

get_modem_description() {
  local iface="${1:-$INTERFACE_ID}"
  if [ -z "$iface" ]; then
    echo ""
    return
  fi
  rci "show/interface/$iface" | grep -o '"description": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_sim_status() {
  local result=""
  local attempts=0
  local max_attempts=5

  while [ $attempts -lt $max_attempts ] && [ -z "$result" ]; do
    attempts=$((attempts + 1))
    result=$(rci "show/interface/$IP_ID" | jq -r '.sim // empty' | head -n1)
    if [ -z "$result" ] && [ $attempts -lt $max_attempts ]; then
      sleep 5
    fi
  done
  result=$(printf '%s' "$result" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "$result"
}

mark_sms_read() {
  rci "" "[{\"sms\":{\"read\":[{\"interface\":\"$INTERFACE_ID\",\"id\":\"$MESSAGE_ID\"}]}}]" >/dev/null 2>&1
}

delete_sms() {
  rci "" "[{\"sms\":{\"delete\":[{\"interface\":\"$INTERFACE_ID\",\"id\":\"$MESSAGE_ID\"}]}}]" >/dev/null 2>&1
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

check_sim_card() {
  if [ "${REBOOT_SIM_IF_INVALID:-0}" = "0" ] || [ -z "$IP_ID" ]; then
    return
  fi

  local sim_status=$(get_sim_status)
  if printf '%s' "$sim_status" | grep -Eq '^(NOT_INSERTED|INVALID)$'; then

    if [ "${REBOOT_SIM_IF_INVALID:-0}" = "1" ]; then
      error "Статус SIM-карты $sim_status. Перезагружаю модем..."
      rci "" "[{\"interface\":{\"usb\":{\"power-cycle\":{\"pause\":2000}},\"name\":\"$IP_ID\"}}]" >/dev/null 2>&1
    elif [ "${REBOOT_SIM_IF_INVALID:-0}" = "2" ]; then
      error "Статус SIM-карты $sim_status. Перезагружаю роутер..."
      rci "" "[{\"system\":{\"reboot\":{}}}]" >/dev/null 2>&1
    fi
    exit
  fi
}

check_black_list() {
  local sender="$1"
  local normalized

  normalized=$(printf '%s' "$BLACK_LIST" |
    tr ',' '\n' |
    sed 's/^[ \t]*//;s/[ \t]*$//' |
    sed '/^$/d')

  if [ -z "$normalized" ]; then
    return
  fi

  if printf '%s\n' "$normalized" | grep -Fx -- "$sender" >/dev/null 2>&1; then
    log "Отправитель $sender в чёрном списке. Удаляю SMS и пропускаю отправку в Telegram."
    delete_sms
    exit
  fi
}

check_white_list() {
  local sender="$1"
  local normalized

  normalized=$(printf '%s' "$WHITE_LIST" |
    tr ',' '\n' |
    sed 's/^[ \t]*//;s/[ \t]*$//' |
    sed '/^$/d')

  if [ -z "$normalized" ]; then
    return
  fi

  if ! printf '%s\n' "$normalized" | grep -Fx -- "$sender" >/dev/null 2>&1; then
    log "Отправитель $sender не в белом списке. Пропускаю отправку в Telegram."
    exit
  fi
}

check_text_black_list() {
  local text="$1"
  local normalized

  normalized=$(printf '%s' "$TEXT_BLACK_LIST" |
    tr ',' '\n' |
    sed 's/^[ \t]*//;s/[ \t]*$//' |
    sed '/^$/d')

  if [ -z "$normalized" ]; then
    return
  fi

  while IFS= read -r pattern; do
    if echo "$text" | grep -Fqi -- "$pattern"; then
      log "Текст сообщения соответствует чёрному списку по шаблону '$pattern'. Удаляю SMS и пропускаю отправку в Telegram."
      delete_sms
      exit
    fi
  done <<EOF
$normalized
EOF
}

check_reboot_key() {
  local text="$1"

  if [ -n "${REBOOT_KEY:-}" ] && echo "$text" | grep -Fqi -- "$REBOOT_KEY"; then
    log "Обнаружено слово "$text". Удаляю SMS и ухожу в перезагрузку."
    delete_sms
    rci "" "[{\"system\":{\"reboot\":{}}}]" >/dev/null 2>&1
    exit
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
  local iface="$4"
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
    local header
    header=$(set_header "$iface")
    message=$(printf "%s\n\n<b>Сообщение от:</b> %s\n<b>Дата:</b> %s\n\n<b>Текст:</b> %s" \
      "$header" "$sender" "$timestamp" "$escaped_text")
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

    if [ -z "$response" ]; then
      error "Ошибка отправки в Telegram: Пустой ответ, выполните обновление всех пакетов или переустановите Entware"
      return 1
    fi

    if echo "$response" | grep -q '"ok":true'; then
      log "Сообщение успешно отправлено."
      if [ "$MARK_READ_MESSAGE_AFTER_SEND" = "1" ] && [ -n "$INTERFACE_ID" ] && [ -n "$MESSAGE_ID" ]; then
        mark_sms_read
      fi
      if [ "$DELETE_MESSAGE_AFTER_SEND" = "1" ] && [ -n "$INTERFACE_ID" ] && [ -n "$MESSAGE_ID" ]; then
        delete_sms
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

  sms_json=$(echo "$sms_json" | jq --arg iface "$INTERFACE_ID" '. + {interface: $iface}')
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
    local sender text timestamp iface
    sender=$(echo "$message" | jq -r '.sender')
    text=$(echo "$message" | jq -r '.text')
    timestamp=$(echo "$message" | jq -r '.timestamp')
    iface=$(echo "$message" | jq -r '.interface')

    log "Отправка сохранённого сообщения от $sender ($timestamp)..."
    if send_to_telegram "$sender" "$timestamp" "$text" "$iface"; then
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
  local sms_data
  local sms_json
  local sender text timestamp
  clean_log
  check_symbolic_link

  if [ -n "$INTERFACE_ID" ] && [ -n "$MESSAGE_ID" ]; then
    log "Запуск скрипта. INTERFACE_ID=$INTERFACE_ID, MESSAGE_ID=$MESSAGE_ID"
  fi

  send_pending_messages
  if [ $# -gt 1 ]; then
    local CUSTOM_MESSAGE="$2"
    send_to_telegram "" "" "$CUSTOM_MESSAGE"
    return
  fi

  if ! echo "$IP_ID" | grep -qE "$MODEM_PATTERN" && ! echo "$INTERFACE_ID" | grep -qE "$MODEM_PATTERN"; then
    return
  fi

  check_sim_card
  if [ -z "$INTERFACE_ID" ] || [ -z "$MESSAGE_ID" ]; then
    return
  fi

  sms_data=$(get_sms_data)
  if [ -z "$sms_data" ]; then
    error "Не удалось получить данные SMS с ID $MESSAGE_ID."
    return
  fi

  sms_json=$(parse_sms "$sms_data")
  if [ -z "$sms_json" ]; then
    error "Ошибка парсинга SMS."
    return
  fi

  sender=$(echo "$sms_json" | jq -r '.sender')
  text=$(echo "$sms_json" | jq -r '.text')
  timestamp=$(echo "$sms_json" | jq -r '.timestamp')

  if is_at_command "$text"; then
    if send_at_command "$INTERFACE_ID" "$text"; then
      if [ "${DEBUG:-0}" = "1" ]; then
        exec 19>&-
      fi
      return
    fi
  fi

  if [ -z "$text" ]; then
    error "Получено пустое или несуществующее сообщение"
    return
  fi

  log "Получено сообщение от $sender: $text"

  check_black_list "$sender"
  check_white_list "$sender"
  check_text_black_list "$text"
  check_reboot_key "$text"

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
