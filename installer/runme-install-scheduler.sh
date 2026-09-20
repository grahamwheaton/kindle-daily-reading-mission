#!/bin/sh

# Runs from the K4 diagnostics jailbreak hook and installs the approved daily
# mission checker into the normal root filesystem.

OUT=/mnt/us/rupert-mission
STAGE=/mnt/us/rupert-stage
ROOT=/var/rupert-main-root
CRONTAB="$ROOT/etc/crontab/root"
MARKER='# RUPERT_DAILY_MISSION'
LOG="$OUT/scheduler-install.log"

mkdir -p "$OUT" "$ROOT"
echo "scheduler install started: $(date)" > "$LOG"

if [ ! -f "$STAGE/rupert-sync.sh" ]; then
    echo 'sync script missing; no changes made' >> "$LOG"
    exit 0
fi

if ! mount /dev/mmcblk0p1 "$ROOT" >> "$LOG" 2>&1; then
    echo 'could not mount normal root; no changes made' >> "$LOG"
    exit 0
fi

if [ ! -f "$OUT/root-crontab.original" ]; then
    cp "$CRONTAB" "$OUT/root-crontab.original"
fi

mkdir -p "$ROOT/usr/local/rupert"
cp "$STAGE/rupert-sync.sh" "$ROOT/usr/local/rupert/sync.sh"
chmod 755 "$ROOT/usr/local/rupert/sync.sh"

grep -v "$MARKER" "$CRONTAB" > /tmp/rupert-root-crontab
echo "*/5 * * * * /usr/local/rupert/sync.sh $MARKER" >> /tmp/rupert-root-crontab
cat /tmp/rupert-root-crontab > "$CRONTAB"
chmod 644 "$CRONTAB"

sync
umount "$ROOT" >> "$LOG" 2>&1
echo "scheduler install completed: $(date)" >> "$LOG"
sync
exit 0
