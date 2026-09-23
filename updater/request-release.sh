#!/bin/sh
# One-time setup on your computer: gh auth login
# Releases still run in the private signing repository; no signing key is local.
set -eu
if ! command -v gh >/dev/null 2>&1; then
    echo "Install GitHub CLI (gh) and run gh auth login once." >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "Run gh auth login once to connect your GitHub account." >&2
    exit 1
fi
case "${1-}" in
    ""|*[!0-9]*) if [ -n "${1-}" ]; then
        echo "Version must be a number." >&2
        exit 1
    fi ;;
esac
gh workflow run publish-device-update.yml \
    --repo grahamwheaton/rupert-device-signing \
    --field "version=${1-}"
echo "Signed release queued. Check: https://github.com/grahamwheaton/rupert-device-signing/actions"
