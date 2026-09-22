#!/bin/sh

# Installs Rupert's sleep screen in the two places the Kindle can show one:
#
#   1. KOReader's sleep screen, used when the Kindle sleeps with the dashboard
#      or a mission open. Just a file under /mnt/us; the plugin points
#      KOReader at it.
#   2. The Kindle framework's own screensavers, used when he has left KOReader
#      and the device sleeps at the Home screen. These live on the system
#      partition, so the originals are copied to /mnt/us first and the
#      partition is put back to read-only afterwards.
#
# Usage: rupert-screensaver.sh install <image.png>
#        rupert-screensaver.sh restore

STATE=/mnt/us/rupert-mission
SLEEP_IMAGE="$STATE/sleep.png"
FRAMEWORK_DIR=/opt/amazon/screen_saver/600x800
BACKUP="$STATE/screensaver-backup"

fail() {
    echo "$*" >&2
    exit 1
}

leave_readonly() {
    mntroot ro >/dev/null 2>&1
}

install_image() {
    SOURCE="$1"
    [ -f "$SOURCE" ] || fail "no such image: $SOURCE"
    [ -d "$FRAMEWORK_DIR" ] || fail "no framework screensavers at $FRAMEWORK_DIR"

    mkdir -p "$STATE"
    cp "$SOURCE" "$SLEEP_IMAGE" || fail "could not write $SLEEP_IMAGE"
    echo "KOReader sleep screen: $SLEEP_IMAGE"

    # Back up once. Running install twice must not overwrite the originals
    # with our own image.
    if [ ! -d "$BACKUP" ]; then
        mkdir -p "$BACKUP" || fail "could not create $BACKUP"
        cp "$FRAMEWORK_DIR"/*.png "$BACKUP"/ || fail "could not back up the originals"
        echo "original screensavers backed up to $BACKUP"
    else
        echo "originals already backed up in $BACKUP"
    fi

    mntroot rw >/dev/null 2>&1 || fail "could not make the system partition writable"
    trap leave_readonly EXIT
    for TARGET in "$FRAMEWORK_DIR"/*.png; do
        cp "$SOURCE" "$TARGET" || fail "could not replace $TARGET"
    done
    echo "replaced $(ls "$FRAMEWORK_DIR"/*.png | wc -l) framework screensavers"
}

restore_originals() {
    [ -d "$BACKUP" ] || fail "no backup at $BACKUP"
    mntroot rw >/dev/null 2>&1 || fail "could not make the system partition writable"
    trap leave_readonly EXIT
    cp "$BACKUP"/*.png "$FRAMEWORK_DIR"/ || fail "could not restore the originals"
    echo "restored the original screensavers"
}

case "$1" in
    install) install_image "$2" ;;
    restore) restore_originals ;;
    *) fail "usage: $0 install <image.png> | $0 restore" ;;
esac

exit 0
