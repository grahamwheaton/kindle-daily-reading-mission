#!/bin/sh

STATE=/mnt/us/rupert-mission
BACKUP="$STATE/bootstrap-backup"
ROOT=/var/rupert-main-root
LOG="$STATE/bootstrap-uninstall.log"
CRONTAB="$ROOT/etc/crontab/root"
MARKER='# RUPERT_DAILY_MISSION'

mkdir -p "$STATE" "$ROOT"
echo "uninstall started: $(date)" > "$LOG"
mount /dev/mmcblk0p1 "$ROOT" >> "$LOG" 2>&1 || exit 0

grep -v "$MARKER" "$CRONTAB" > /tmp/rupert-root-crontab
cat /tmp/rupert-root-crontab > "$CRONTAB"

if [ -f "$BACKUP/main-root/json_simple-1.1.jar" ]; then
    cp "$BACKUP/main-root/json_simple-1.1.jar" "$ROOT/opt/amazon/ebook/lib/json_simple-1.1.jar"
fi
if [ -f "$BACKUP/var-local/developer.keystore" ]; then
    cp "$BACKUP/var-local/developer.keystore" /var/local/java/keystore/developer.keystore
fi

rm -f "$ROOT/usr/local/rupert/device-update.sh" \
      "$ROOT/usr/local/rupert/device-update-public.pem" \
      "$ROOT/usr/local/rupert/sync.sh"
rm -f /mnt/us/documents/RupertsReader.azw2 "$STATE/open-current.sh"

sync
umount "$ROOT" >> "$LOG" 2>&1
echo "uninstall completed: $(date)" >> "$LOG"
sync
exit 0
