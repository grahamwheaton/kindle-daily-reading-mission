#!/bin/sh

# Runs from the K4 diagnostics jailbreak hook. It installs a modern curl in a
# dedicated directory and a one-shot normal-boot HTTPS test. It does not replace
# any Amazon binaries.

OUT=/mnt/us/rupert-mission
STAGE=/mnt/us/rupert-stage
ROOT=/var/rupert-main-root
LOG="$OUT/install-test.log"

mkdir -p "$OUT" "$ROOT"
echo "install started: $(date)" > "$LOG"

if [ ! -f "$STAGE/curl" ] || [ ! -f "$STAGE/cacert.pem" ]; then
    echo 'payload missing; no changes made' >> "$LOG"
    exit 0
fi

if ! mount /dev/mmcblk0p1 "$ROOT" >> "$LOG" 2>&1; then
    echo 'could not mount normal root; no changes made' >> "$LOG"
    exit 0
fi

mkdir -p "$ROOT/usr/local/rupert"
cp "$STAGE/curl" "$ROOT/usr/local/rupert/curl"
cp "$STAGE/cacert.pem" "$ROOT/usr/local/rupert/cacert.pem"
chmod 755 "$ROOT/usr/local/rupert/curl"
chmod 644 "$ROOT/usr/local/rupert/cacert.pem"

cat > "$ROOT/etc/init.d/rupert-fetch-test" <<'NORMAL_BOOT_TEST'
#!/bin/sh

case "$1" in
    stop) exit 0 ;;
esac

(
    OUT=/mnt/us/rupert-mission
    CURL=/usr/local/rupert/curl
    CA=/usr/local/rupert/cacert.pem
    URL='https://raw.githubusercontent.com/grahamwheaton/rupert-reading-missions/master/published/date.txt'
    mkdir -p "$OUT"
    exec > "$OUT/https-test.log" 2>&1
    echo "normal-boot test started: $(date)"
    "$CURL" -V
    /usr/bin/lipc-set-prop com.lab126.wifid enable 1 >/dev/null 2>&1 || true

    WAIT=0
    while [ "$WAIT" -lt 180 ]; do
        STATE=$(/usr/bin/lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
        echo "wifi after ${WAIT}s: $STATE"
        echo "$STATE" | grep -q CONNECTED && break
        sleep 5
        WAIT=$((WAIT + 5))
    done

    rm -f "$OUT/date-test.txt"
    if "$CURL" --proto '=https' --tlsv1.2 --fail --show-error --location \
        --connect-timeout 30 --max-time 90 --cacert "$CA" \
        -o "$OUT/date-test.txt" "$URL"; then
        echo 'HTTPS_FETCH_OK'
        cat "$OUT/date-test.txt"
    else
        STATUS=$?
        echo "HTTPS_FETCH_FAILED status=$STATUS"
    fi

    # This is deliberately one-shot. Leave the downloader installed, but
    # remove the boot hook whether the network test succeeds or fails.
    mntroot rw
    rm -f /etc/rc5.d/S99rupert-fetch-test /etc/init.d/rupert-fetch-test
    sync
    mntroot ro
) &

exit 0
NORMAL_BOOT_TEST

chmod 755 "$ROOT/etc/init.d/rupert-fetch-test"
ln -sf ../init.d/rupert-fetch-test "$ROOT/etc/rc5.d/S99rupert-fetch-test"
sync
umount "$ROOT" >> "$LOG" 2>&1
echo "install completed: $(date)" >> "$LOG"
sync
exit 0
