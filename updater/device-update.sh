#!/bin/sh

# Root-run, allowlisted updater. The remote manifest must have a valid RSA/SHA-256
# signature from the offline project key. Remote data never supplies commands or
# destination paths.

BASE='https://raw.githubusercontent.com/grahamwheaton/rupert-reading-missions/master/published/device'
RUNTIME=/usr/local/rupert
STATE=/mnt/us/rupert-mission
DOCUMENTS=/mnt/us/documents
CURL="$RUNTIME/curl"
CA="$RUNTIME/cacert.pem"
PUB="$RUNTIME/device-update-public.pem"
LOG="$STATE/update.log"
WORK=/tmp/rupert-device-update
LOCK=/tmp/rupert-device-update.lock

mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rm -rf "$WORK"; rmdir "$LOCK" 2>/dev/null' EXIT
rm -rf "$WORK"
mkdir -p "$WORK" "$STATE"

log() { echo "$(date) $*" >> "$LOG"; }
fetch() {
    "$CURL" --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 90 --cacert "$CA" -o "$1" "$2"
}
digest() { /usr/bin/openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'; }
field() { sed -n "s/^$1=//p" "$WORK/manifest.txt" | head -1; }
valid_hash() { echo "$1" | grep -q '^[0-9A-Fa-f]\{64\}$'; }

[ -x "$CURL" ] && [ -f "$CA" ] && [ -f "$PUB" ] || { log 'updater prerequisites missing'; exit 0; }
fetch "$WORK/manifest.txt" "$BASE/manifest.txt" >> "$LOG" 2>&1 || { log 'manifest download failed'; exit 0; }
fetch "$WORK/manifest.sig" "$BASE/manifest.sig" >> "$LOG" 2>&1 || { log 'manifest signature download failed'; exit 0; }

if ! /usr/bin/openssl dgst -sha256 -verify "$PUB" -signature "$WORK/manifest.sig" "$WORK/manifest.txt" >> "$LOG" 2>&1; then
    log 'manifest signature rejected'
    exit 0
fi

MANIFEST_HASH=$(digest "$WORK/manifest.txt")
[ "$MANIFEST_HASH" = "$(cat "$STATE/last-device-manifest.sha256" 2>/dev/null)" ] && exit 0

LAUNCHER_HASH=$(field launcher_sha256)
SYNC_HASH=$(field sync_sha256)
OPEN_HASH=$(field open_current_sha256)
valid_hash "$LAUNCHER_HASH" && valid_hash "$SYNC_HASH" && valid_hash "$OPEN_HASH" || {
    log 'manifest contains an invalid hash'
    exit 0
}

fetch "$WORK/RupertsReader.azw2" "$BASE/RupertsReader.azw2" >> "$LOG" 2>&1 || exit 0
fetch "$WORK/rupert-sync.sh" "$BASE/rupert-sync.sh" >> "$LOG" 2>&1 || exit 0
fetch "$WORK/open-current.sh" "$BASE/open-current.sh" >> "$LOG" 2>&1 || exit 0

[ "$(digest "$WORK/RupertsReader.azw2")" = "$(echo "$LAUNCHER_HASH" | tr A-F a-f)" ] || { log 'launcher hash rejected'; exit 0; }
[ "$(digest "$WORK/rupert-sync.sh")" = "$(echo "$SYNC_HASH" | tr A-F a-f)" ] || { log 'sync hash rejected'; exit 0; }
[ "$(digest "$WORK/open-current.sh")" = "$(echo "$OPEN_HASH" | tr A-F a-f)" ] || { log 'open helper hash rejected'; exit 0; }

chmod 755 "$WORK/rupert-sync.sh" "$WORK/open-current.sh"
mv -f "$WORK/RupertsReader.azw2" "$DOCUMENTS/RupertsReader.azw2"
mv -f "$WORK/open-current.sh" "$STATE/open-current.sh"

mntroot rw
cp "$WORK/rupert-sync.sh" "$RUNTIME/sync.sh.new"
chmod 755 "$RUNTIME/sync.sh.new"
mv -f "$RUNTIME/sync.sh.new" "$RUNTIME/sync.sh"
sync
mntroot ro

echo "$MANIFEST_HASH" > "$STATE/last-device-manifest.sha256"
log "installed signed device manifest $(field version)"
dbus-send --system /default com.lab126.powerd.resuming int32:1 >/dev/null 2>&1 || true
exit 0
