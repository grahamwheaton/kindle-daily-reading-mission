#!/bin/sh

# One-time K4S/4.1.4 bootstrap, executed by the established diagnostics
# jailbreak hook. Installs the official MKK legacy payload, the signed updater,
# and the manually launched Rupert Reader. It does not enable kiosk auto-start.

STAGE=/mnt/us/rupert-bootstrap
STATE=/mnt/us/rupert-mission
BACKUP="$STATE/bootstrap-backup"
ROOT=/var/rupert-main-root
LOG="$STATE/bootstrap.log"
CRONTAB="$ROOT/etc/crontab/root"
MARKER='# RUPERT_DAILY_MISSION'

mkdir -p "$STATE" "$BACKUP" "$ROOT"
echo "bootstrap started: $(date)" > "$LOG"

for FILE in curl cacert.pem developer.keystore json_simple-1.1.jar \
    device-update-public.pem device-update.sh rupert-sync.sh open-current.sh \
    RupertsReader.azw2 launcher.properties; do
    [ -f "$STAGE/$FILE" ] || { echo "missing $FILE; no changes made" >> "$LOG"; exit 0; }
done

if ! mount /dev/mmcblk0p1 "$ROOT" >> "$LOG" 2>&1; then
    echo 'normal root mount failed; no changes made' >> "$LOG"
    exit 0
fi

mkdir -p "$BACKUP/main-root" "$BACKUP/var-local" "$ROOT/usr/local/rupert"
[ -f "$BACKUP/main-root/json_simple-1.1.jar" ] || \
    cp "$ROOT/opt/amazon/ebook/lib/json_simple-1.1.jar" "$BACKUP/main-root/json_simple-1.1.jar" 2>/dev/null || true
[ -f "$BACKUP/var-local/developer.keystore" ] || \
    cp /var/local/java/keystore/developer.keystore "$BACKUP/var-local/developer.keystore" 2>/dev/null || true
[ -f "$BACKUP/root-crontab.before-launcher" ] || cp "$CRONTAB" "$BACKUP/root-crontab.before-launcher"

# Official legacy MKK result: permission gateway plus current developer certs.
mkdir -p /var/local/java/keystore
cp "$STAGE/developer.keystore" /var/local/java/keystore/developer.keystore
chmod 644 /var/local/java/keystore/developer.keystore
cp "$STAGE/json_simple-1.1.jar" "$ROOT/opt/amazon/ebook/lib/json_simple-1.1.jar"
chmod 664 "$ROOT/opt/amazon/ebook/lib/json_simple-1.1.jar"

# Isolated runtime; no Amazon downloader or certificate files are replaced.
cp "$STAGE/curl" "$ROOT/usr/local/rupert/curl"
cp "$STAGE/cacert.pem" "$ROOT/usr/local/rupert/cacert.pem"
cp "$STAGE/device-update-public.pem" "$ROOT/usr/local/rupert/device-update-public.pem"
cp "$STAGE/device-update.sh" "$ROOT/usr/local/rupert/device-update.sh"
cp "$STAGE/rupert-sync.sh" "$ROOT/usr/local/rupert/sync.sh"
chmod 755 "$ROOT/usr/local/rupert/curl" "$ROOT/usr/local/rupert/device-update.sh" "$ROOT/usr/local/rupert/sync.sh"
chmod 644 "$ROOT/usr/local/rupert/cacert.pem" "$ROOT/usr/local/rupert/device-update-public.pem"

grep -v "$MARKER" "$CRONTAB" > /tmp/rupert-root-crontab
echo "*/5 * * * * /usr/local/rupert/sync.sh $MARKER" >> /tmp/rupert-root-crontab
cat /tmp/rupert-root-crontab > "$CRONTAB"
chmod 644 "$CRONTAB"

mkdir -p "$STATE/archive"
cp "$STAGE/open-current.sh" "$STATE/open-current.sh"
cp "$STAGE/launcher.properties" "$STATE/launcher.properties"
chmod 755 "$STATE/open-current.sh"
cp "$STAGE/RupertsReader.azw2" /mnt/us/documents/RupertsReader.azw2
if [ -f "/mnt/us/documents/Today's Reading Mission.mobi" ] && [ ! -f /mnt/us/documents/RupertsMission.mobi ]; then
    cp "/mnt/us/documents/Today's Reading Mission.mobi" /mnt/us/documents/RupertsMission.mobi
fi

sync
umount "$ROOT" >> "$LOG" 2>&1
echo "bootstrap completed: $(date)" >> "$LOG"
sync
exit 0
