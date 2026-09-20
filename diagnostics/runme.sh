#!/bin/sh

OUT=/mnt/us/rupert-diag
mkdir -p "$OUT"

date > "$OUT/date.txt" 2>&1
cat /proc/version > "$OUT/version.txt" 2>&1

(
    echo '=== filter ==='
    iptables -L -n -v
    echo '=== nat ==='
    iptables -t nat -L -n -v
    echo '=== rules ==='
    iptables -S
) > "$OUT/iptables.txt" 2>&1

netstat -ltnp > "$OUT/listening.txt" 2>&1
ps > "$OUT/processes.txt" 2>&1
dmesg > "$OUT/dmesg.txt" 2>&1
cp /var/log/messages "$OUT/messages.txt" 2>/dev/null || true

cp /etc/crontab/root "$OUT/crontab-root.txt" 2>/dev/null || true
ls -la /etc/crontab > "$OUT/crontab-dir.txt" 2>&1

(
    echo '=== commands ==='
    for TOOL in curl wget openssl lipc-set-prop lipc-get-prop lipc-wait-event dbus-send crond sha256sum; do
        command -v "$TOOL" 2>/dev/null || echo "missing: $TOOL"
    done
    echo '=== usbnetwork binaries ==='
    ls -la /mnt/us/usbnet/bin 2>/dev/null
    echo '=== curl versions ==='
    curl -V 2>&1
    LD_LIBRARY_PATH=/mnt/us/usbnet/lib /mnt/us/usbnet/bin/curl -V 2>&1
    echo '=== wget version ==='
    wget --version 2>&1
) > "$OUT/tools.txt" 2>&1

(
    echo '=== system CA paths ==='
    ls -la /etc/ssl /etc/ssl/certs 2>&1
    echo '=== usbnetwork CA paths ==='
    find /mnt/us/usbnet -iname '*ca*' -o -iname '*cert*' 2>/dev/null | head -100
) > "$OUT/certificates.txt" 2>&1

(
    echo '=== interfaces ==='
    ifconfig -a
    echo '=== routes ==='
    route -n
) > "$OUT/network.txt" 2>&1

(
    echo '=== usbnetwork config (non-secret settings only) ==='
    grep -E '^(HOST_IP|KINDLE_IP|K3_WIFI|K3_WIFI_SSHD_ONLY|USE_OPENSSH|USE_VOLUMD|QUIET_DROPBEAR|TWEAK_MAC_ADDRESS)=' /mnt/us/usbnet/etc/config 2>/dev/null
    echo '=== host key files ==='
    ls -l /mnt/us/usbnet/etc/*host_key 2>/dev/null
    echo '=== run state ==='
    ls -la /mnt/us/usbnet/run 2>/dev/null
) > "$OUT/usbnetwork.txt" 2>&1

sync
exit 0
