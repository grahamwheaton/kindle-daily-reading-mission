#!/bin/sh

# Root-run, allowlisted updater. The remote manifest must carry a valid
# RSA/SHA-256 signature from the offline project key, and everything else is
# checked against that manifest. Remote data never supplies commands or
# destination paths: the paths below are the only places anything is written.
#
# An update is one signed bundle. Its digest is in the signed manifest, so the
# bundle needs no signature of its own, and what it contains is decided here:
#
#   runtime/      -> /usr/local/rupert        (system partition, briefly rw)
#   documents/    -> /mnt/us/documents
#   state/        -> /mnt/us/rupert-mission
#   plugin/       -> /mnt/us/koreader/plugins/rupertdash.koplugin  (replaced whole)
#
# Older manifests named three files instead, and are still installed that way,
# so a device can be updated from either.

BASE='https://raw.githubusercontent.com/grahamwheaton/rupert-reading-missions/master/published/device'
RUNTIME=/usr/local/rupert
SELF="$RUNTIME/device-update.sh"
STATE=/mnt/us/rupert-mission
DOCUMENTS=/mnt/us/documents
PLUGIN=/mnt/us/koreader/plugins/rupertdash.koplugin
CURL="$RUNTIME/curl"
CA="$RUNTIME/cacert.pem"
PUB="$RUNTIME/device-update-public.pem"
LOG="$STATE/update.log"
WORK=/var/tmp/rupert-device-update
LOCK=/var/tmp/rupert-device-update.lock

# Run from a tmpfs copy: an update may replace this script, and a running copy
# holds the file open, which stops the system partition going back to read-only.
case "$0" in
    /var/tmp/rupert-update-run.*) rm -f "$0" ;;
    *)
        RUN=/var/tmp/rupert-update-run.$$
        cp "$SELF" "$RUN" 2>/dev/null && exec /bin/sh "$RUN" "$@"
        ;;
esac

mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rm -rf "$WORK"; rmdir "$LOCK" 2>/dev/null' EXIT
rm -rf "$WORK"
mkdir -p "$WORK" "$STATE"

log() { echo "$(date) $*" >> "$LOG"; }
fetch() {
    "$CURL" --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 180 --cacert "$CA" -o "$1" "$2"
}
digest() { /usr/bin/openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'; }
field() { sed -n "s/^$1=//p" "$WORK/manifest.txt" | head -1; }
valid_hash() { echo "$1" | grep -q '^[0-9A-Fa-f]\{64\}$'; }
lower() { echo "$1" | tr A-F a-f; }

[ -x "$CURL" ] && [ -f "$CA" ] && [ -f "$PUB" ] || { log 'updater prerequisites missing'; exit 0; }
fetch "$WORK/manifest.txt" "$BASE/manifest.txt" >> "$LOG" 2>&1 || { log 'manifest download failed'; exit 0; }
fetch "$WORK/manifest.sig" "$BASE/manifest.sig" >> "$LOG" 2>&1 || { log 'manifest signature download failed'; exit 0; }

if ! /usr/bin/openssl dgst -sha256 -verify "$PUB" -signature "$WORK/manifest.sig" "$WORK/manifest.txt" >> "$LOG" 2>&1; then
    log 'manifest signature rejected'
    exit 0
fi

MANIFEST_HASH=$(digest "$WORK/manifest.txt")
[ "$MANIFEST_HASH" = "$(cat "$STATE/last-device-manifest.sha256" 2>/dev/null)" ] && exit 0

VERSION=$(field version)

install_bundle() {
    BUNDLE_HASH=$(field bundle_sha256)
    valid_hash "$BUNDLE_HASH" || return 1

    fetch "$WORK/bundle.tar" "$BASE/bundle.tar" >> "$LOG" 2>&1 || {
        log 'bundle download failed'
        return 2
    }
    [ "$(digest "$WORK/bundle.tar")" = "$(lower "$BUNDLE_HASH")" ] || {
        log 'bundle hash rejected'
        return 2
    }

    # A signed bundle is still checked for paths that would escape its own
    # directories: absolute paths, or anything walking upwards.
    if tar -tf "$WORK/bundle.tar" 2>/dev/null | grep -q -e '^/' -e '\.\.'; then
        log 'bundle rejected: it contains paths outside itself'
        return 2
    fi

    mkdir -p "$WORK/bundle"
    tar -xf "$WORK/bundle.tar" -C "$WORK/bundle" 2>> "$LOG" || {
        log 'bundle rejected: it would not unpack'
        return 2
    }

    if [ -d "$WORK/bundle/documents" ]; then
        for FILE in "$WORK/bundle/documents"/*; do
            [ -f "$FILE" ] && cp "$FILE" "$DOCUMENTS/${FILE##*/}"
        done
    fi
    if [ -d "$WORK/bundle/state" ]; then
        for FILE in "$WORK/bundle/state"/*; do
            [ -f "$FILE" ] && cp "$FILE" "$STATE/${FILE##*/}" && chmod 755 "$STATE/${FILE##*/}"
        done
    fi
    if [ -d "$WORK/bundle/plugin" ]; then
        # Whole directory at a time: a half-replaced plugin will not load.
        rm -rf "$PLUGIN.new"
        mkdir -p "$PLUGIN.new"
        cp "$WORK/bundle/plugin"/* "$PLUGIN.new"/ 2>/dev/null
        if [ -f "$PLUGIN.new/main.lua" ]; then
            rm -rf "$PLUGIN.old"
            [ -d "$PLUGIN" ] && mv "$PLUGIN" "$PLUGIN.old"
            mv "$PLUGIN.new" "$PLUGIN"
            rm -rf "$PLUGIN.old"
        else
            log 'plugin rejected: no main.lua in the bundle'
            rm -rf "$PLUGIN.new"
        fi
    fi
    if [ -d "$WORK/bundle/runtime" ]; then
        mntroot rw >> "$LOG" 2>&1
        for FILE in "$WORK/bundle/runtime"/*; do
            [ -f "$FILE" ] || continue
            NAME=${FILE##*/}
            cp "$FILE" "$RUNTIME/$NAME.new" && chmod 755 "$RUNTIME/$NAME.new" \
                && mv -f "$RUNTIME/$NAME.new" "$RUNTIME/$NAME"
        done
        sync
        mntroot ro >> "$LOG" 2>&1
    fi
    return 0
}

install_named_files() {
    LAUNCHER_HASH=$(field launcher_sha256)
    SYNC_HASH=$(field sync_sha256)
    OPEN_HASH=$(field open_current_sha256)
    valid_hash "$LAUNCHER_HASH" && valid_hash "$SYNC_HASH" && valid_hash "$OPEN_HASH" || {
        log 'manifest contains an invalid hash'
        return 1
    }

    fetch "$WORK/RupertsReader.azw2" "$BASE/RupertsReader.azw2" >> "$LOG" 2>&1 || return 1
    fetch "$WORK/rupert-sync.sh" "$BASE/rupert-sync.sh" >> "$LOG" 2>&1 || return 1
    fetch "$WORK/open-current.sh" "$BASE/open-current.sh" >> "$LOG" 2>&1 || return 1

    [ "$(digest "$WORK/RupertsReader.azw2")" = "$(lower "$LAUNCHER_HASH")" ] || { log 'launcher hash rejected'; return 1; }
    [ "$(digest "$WORK/rupert-sync.sh")" = "$(lower "$SYNC_HASH")" ] || { log 'sync hash rejected'; return 1; }
    [ "$(digest "$WORK/open-current.sh")" = "$(lower "$OPEN_HASH")" ] || { log 'open helper hash rejected'; return 1; }

    chmod 755 "$WORK/rupert-sync.sh" "$WORK/open-current.sh"
    mv -f "$WORK/RupertsReader.azw2" "$DOCUMENTS/RupertsReader.azw2"
    mv -f "$WORK/open-current.sh" "$STATE/open-current.sh"

    mntroot rw >> "$LOG" 2>&1
    cp "$WORK/rupert-sync.sh" "$RUNTIME/sync.sh.new"
    chmod 755 "$RUNTIME/sync.sh.new"
    mv -f "$RUNTIME/sync.sh.new" "$RUNTIME/sync.sh"
    sync
    mntroot ro >> "$LOG" 2>&1
    return 0
}

install_bundle
case $? in
    0) INSTALLED=bundle ;;
    2) exit 0 ;;                       # the bundle was there but unusable
    *) install_named_files || exit 0   # an older manifest, named files
       INSTALLED=files ;;
esac

echo "$MANIFEST_HASH" > "$STATE/last-device-manifest.sha256"
log "installed signed device manifest $VERSION ($INSTALLED)"
dbus-send --system /default com.lab126.powerd.resuming int32:1 >/dev/null 2>&1 || true
exit 0
