#!/bin/sh
printf "\033c"
set -e

echo "Устанавливаю репозиторий"
mkdir -p /opt/etc/opkg
echo "src/gz sms2gram https://spatiumstas.github.io/sms2gram/all" > /opt/etc/opkg/sms2gram.conf

echo "Начинаю установку"
echo ""
opkg update && opkg install sms2gram