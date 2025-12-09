#!/bin/sh

REPO="sms2gram"
SCRIPT="sms2gram.sh"
SMSD="01-sms2gram.sh"
SMS_DIR="/opt/etc/ndm/sms.d"
TMP_DIR="/tmp"
OPT_DIR="/opt"
SMS2GRAM_DIR="/opt/root/sms2gram"

if ! opkg list-installed | grep -q "^curl" || ! opkg list-installed | grep -q "^jq"; then
  opkg update && opkg install curl jq
  echo ""
fi

mkdir -p "$SMS2GRAM_DIR"
curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SCRIPT" --output "$TMP_DIR/$SCRIPT"
mv "$TMP_DIR/$SCRIPT" "$SMS2GRAM_DIR/$SCRIPT"
chmod +x "$SMS2GRAM_DIR/$SCRIPT"
ln -sf "$SMS2GRAM_DIR/$SCRIPT" "$OPT_DIR/bin/sms2gram"

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SMSD" --output "$TMP_DIR/$SMSD"
mv "$TMP_DIR/$SMSD" "$SMS2GRAM_DIR/$SMSD"
chmod +x "$SMS2GRAM_DIR/$SMSD"
ln -sf "$SMS2GRAM_DIR/$SMSD" "$SMS_DIR/$SMSD"
"$SMS2GRAM_DIR/$SCRIPT"