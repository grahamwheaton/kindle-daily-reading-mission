#!/bin/sh

OUT=/mnt/us/rupert-diag-main
ROOT=/var/main-root-readonly
mkdir -p "$OUT" "$ROOT"

mount > "$OUT/diagnostics-mounts.txt" 2>&1
cat /proc/partitions > "$OUT/partitions.txt" 2>&1

if ! mount -o ro /dev/mmcblk0p1 "$ROOT" > "$OUT/mount-main.txt" 2>&1; then
    echo 'Unable to mount main root read-only' >> "$OUT/mount-main.txt"
    sync
    exit 0
fi

(
    echo '=== normal root identity ==='
    cat "$ROOT/etc/prettyversion.txt" 2>/dev/null
    cat "$ROOT/etc/version.txt" 2>/dev/null
    echo '=== cron paths ==='
    find "$ROOT/etc" -maxdepth 3 -iname '*cron*' -print 2>/dev/null
    echo '=== init paths ==='
    find "$ROOT/etc" -maxdepth 3 \( -iname '*cron*' -o -iname '*framework*' -o -iname '*power*' -o -iname '*wifi*' \) -print 2>/dev/null
) > "$OUT/layout.txt" 2>&1

(
    for FILE in "$ROOT/etc/crontab" "$ROOT/etc/crontab/root" "$ROOT/etc/init.d/cron" "$ROOT/etc/rc5.d/S90cron"; do
        echo "===== $FILE ====="
        if [ -d "$FILE" ]; then
            ls -la "$FILE"
        elif [ -f "$FILE" ]; then
            ls -l "$FILE"
            cat "$FILE"
        else
            echo missing
        fi
    done
) > "$OUT/cron.txt" 2>&1

(
    echo '=== normal-root tools ==='
    for TOOL in curl wget openssl lipc-set-prop lipc-get-prop lipc-wait-event dbus-send crond sha256sum busybox; do
        find "$ROOT/bin" "$ROOT/sbin" "$ROOT/usr/bin" "$ROOT/usr/sbin" -maxdepth 1 -name "$TOOL" -print 2>/dev/null
    done
    echo '=== SSL and CA files ==='
    find "$ROOT/etc" "$ROOT/usr" -maxdepth 5 \( -iname '*cacert*' -o -iname '*ca-bundle*' -o -iname 'cert.pem' \) -print 2>/dev/null | head -100
) > "$OUT/tools.txt" 2>&1

(
    echo '=== curl version from normal firmware ==='
    chroot "$ROOT" /usr/bin/curl -V 2>&1
    echo '=== wget version/help from normal firmware ==='
    chroot "$ROOT" /usr/bin/wget --version 2>&1 || chroot "$ROOT" /usr/bin/wget --help 2>&1 | head -40
    echo '=== OpenSSL version from normal firmware ==='
    chroot "$ROOT" /usr/bin/openssl version -a 2>&1
    echo '=== curl configuration ==='
    for FILE in "$ROOT/etc/curlrc" "$ROOT/root/.curlrc" "$ROOT/etc/ssl/openssl.cnf"; do
        if [ -f "$FILE" ]; then
            echo "===== $FILE ====="
            cat "$FILE"
        fi
    done
    echo '=== likely certificate stores ==='
    find "$ROOT/etc" "$ROOT/usr" -maxdepth 6 -type f \( -iname '*.pem' -o -iname '*.crt' -o -iname 'cacerts' \) -print 2>/dev/null | head -200
) > "$OUT/network-tools.txt" 2>&1

(
    echo '=== USBNetwork system hooks ==='
    find "$ROOT/etc" "$ROOT/usr" -maxdepth 5 -iname '*usbnet*' -print 2>/dev/null
    echo '=== USBNetwork launcher content ==='
    for FILE in "$ROOT/usr/local/bin/usbnetwork" "$ROOT/etc/init.d/usbnetwork"; do
        [ -f "$FILE" ] && { echo "===== $FILE ====="; cat "$FILE"; }
    done
) > "$OUT/usbnetwork-hooks.txt" 2>&1

(
    echo '=== powerd LIPC references ==='
    grep -R 'lipc-wait-event\|rtcWakeup\|resuming' "$ROOT/etc" 2>/dev/null | head -200
) > "$OUT/power-events.txt" 2>&1

umount "$ROOT" > "$OUT/unmount-main.txt" 2>&1
sync
exit 0
