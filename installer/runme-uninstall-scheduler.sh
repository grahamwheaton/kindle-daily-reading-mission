#!/bin/sh

OUT=/mnt/us/rupert-mission
ROOT=/var/rupert-main-root
CRONTAB="$ROOT/etc/crontab/root"
MARKER='# RUPERT_DAILY_MISSION'
LOG="$OUT/scheduler-uninstall.log"

mkdir -p "$OUT" "$ROOT"
echo "scheduler uninstall started: $(date)" > "$LOG"
mount /dev/mmcblk0p1 "$ROOT" >> "$LOG" 2>&1 || exit 0
grep -v "$MARKER" "$CRONTAB" > /tmp/rupert-root-crontab
cat /tmp/rupert-root-crontab > "$CRONTAB"
rm -f "$ROOT/usr/local/rupert/sync.sh"
sync
umount "$ROOT" >> "$LOG" 2>&1
echo "scheduler uninstall completed: $(date)" >> "$LOG"
sync
exit 0
