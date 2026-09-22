#!/bin/sh

# Reports finished missions to a private GitHub repository, so the streak the
# Kindle shows can be seen off-device and the daily job can adapt to what was
# actually read.
#
# The dashboard records a completion per mission in $COMPLETED; this uploads
# any that have no matching .sent marker and is safe to run as often as the
# sync does. Nothing here decides the streak: the device does that from its own
# records, so a failed upload never changes what Rupert sees.
#
# The token lives only on the device, is never committed, and must be scoped to
# this one private repository with contents:write. Anyone holding the Kindle can
# read it, so it must not be able to reach the repository the missions are
# published from.

RUNTIME=/usr/local/rupert
STATE=/mnt/us/rupert-mission
COMPLETED="$STATE/completed"
TOKEN_FILE="$RUNTIME/github-token"
REPO_FILE="$RUNTIME/github-repo"
LOG="$STATE/report.log"
LOG_MAX_BYTES=16384
CURL="$RUNTIME/curl"
CA="$RUNTIME/cacert.pem"
BODY=/var/tmp/rupert-report-body.json
RESPONSE=/var/tmp/rupert-report-response.json

log() {
    echo "$(date) $*" >> "$LOG"
}

[ -f "$TOKEN_FILE" ] && [ -f "$REPO_FILE" ] || exit 0
[ -x "$CURL" ] && [ -f "$CA" ] || exit 0
[ -d "$COMPLETED" ] || exit 0

TOKEN=$(cat "$TOKEN_FILE")
REPO=$(cat "$REPO_FILE")
[ -n "$TOKEN" ] && [ -n "$REPO" ] || exit 0

if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt "$LOG_MAX_BYTES" ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
fi

for RECORD in "$COMPLETED"/*.json; do
    [ -f "$RECORD" ] || continue
    NAME=${RECORD##*/}
    ID=${NAME%.json}
    [ -f "$COMPLETED/$ID.sent" ] && continue

    CONTENT=$(openssl base64 -A < "$RECORD" 2>/dev/null)
    [ -n "$CONTENT" ] || continue
    printf '{"message":"mission %s finished","content":"%s"}' "$ID" "$CONTENT" > "$BODY"

    CODE=$("$CURL" --proto '=https' --tlsv1.2 --silent --location \
        --connect-timeout 20 --max-time 60 --cacert "$CA" \
        --output "$RESPONSE" --write-out '%{http_code}' \
        -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: rupert-kindle" \
        -d @"$BODY" \
        "https://api.github.com/repos/$REPO/contents/completions/$NAME")

    case "$CODE" in
        200|201)
            touch "$COMPLETED/$ID.sent"
            log "reported $ID"
            ;;
        422)
            # Already there from an earlier run whose marker did not survive.
            touch "$COMPLETED/$ID.sent"
            log "already reported $ID"
            ;;
        401|403)
            log "report rejected ($CODE): check the token and its scope"
            break
            ;;
        *)
            log "report failed for $ID ($CODE)"
            ;;
    esac
done

rm -f "$BODY" "$RESPONSE"
exit 0
