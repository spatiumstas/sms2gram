#!/bin/sh

REPO="sms2gram"
SCRIPT="sms2gram.sh"
SMSD="01-sms2gram.sh"
SMS_DIR="/opt/etc/ndm/sms.d"
TMP_DIR="/tmp"
OPT_DIR="/opt"

url() {
  PART1="aHR0cHM6Ly9sb2c"
  PART2="uc3BhdGl1bS5rZWVuZXRpYy5wcm8="
  PART3="${PART1}${PART2}"
  URL=$(echo "$PART3" | base64 -d)
  echo "${URL}"
}

if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
  opkg update && opkg install curl jq
  wait
  echo ""
fi

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SCRIPT" --output $TMP_DIR/$SCRIPT
mv "$TMP_DIR/$SCRIPT" "$OPT_DIR/$SCRIPT"
chmod +x $OPT_DIR/$SCRIPT
cd $OPT_DIR/bin
ln -sf $OPT_DIR/$SCRIPT $OPT_DIR/bin/sms2gram

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SMSD" --output $TMP_DIR/$SMSD
mv "$TMP_DIR/$SMSD" "$SMS_DIR/$SMSD"
chmod +x $SMS_DIR/$SMSD

URL=$(url)
JSON_DATA="{\"script_update\": \"sms2gram_install\"}"
curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$URL" -o /dev/null -s
$OPT_DIR/$SCRIPT
