#!/usr/bin/env bash

set -euo pipefail

IFACE="${IFACE:-lo}"
PREFIX_LEN=104
PREFIX_ADDR="::7f00:0"
FIRST=1
LAST=15

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2
    exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
    echo "iproute2 is required. Install it with: apt-get install -y iproute2" >&2
    exit 1
fi

ip link set dev "$IFACE" up

addr_present() {
    ip -6 addr show dev "$IFACE" | grep -q "inet6 $1/"
}

add_addr() {
    local addr="$1"
    local cidr="$addr/$PREFIX_LEN"

    if addr_present "$addr"; then
        echo "= $cidr (already present)"
        return 0
    fi

    if ip -6 addr add "$cidr" dev "$IFACE" nodad 2>/dev/null; then
        echo "+ $cidr"
        return 0
    fi

    # Another process may have added it in the meantime
    if addr_present "$addr"; then
        echo "= $cidr (already present)"
        return 0
    fi

    echo "! $cidr (failed)" >&2
    return 1
}

failed=0

# Prefix address ::7f00:0/104
if ! add_addr "$PREFIX_ADDR"; then
    echo "  (prefix address could not be added; continuing)" >&2
fi

# Addresses ::7f00:1 - ::7f00:f
for i in $(seq "$FIRST" "$LAST"); do
    addr=$(printf '::7f00:%x' "$i")
    if ! add_addr "$addr"; then
        failed=$((failed + 1))
    fi
done

echo
echo "Current IPv6 addresses on $IFACE:"
ip -6 addr show dev "$IFACE" | awk '/inet6/ {print "  " $2}'

if (( failed > 0 )); then
    echo "Done with $failed failure(s)." >&2
    exit 1
fi

echo "Done."

if [[ "${1:-}" == "--persist" ]]; then
    install -m 0755 "$0" /usr/local/sbin/add-ipv6-loopback.sh

    cat > /etc/systemd/system/ipv6-loopback.service <<'EOF'
[Unit]
Description=Add ::7f00:1-::7f00:f IPv6 addresses to loopback
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/add-ipv6-loopback.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now ipv6-loopback.service
    echo "Persistent systemd unit installed and started: ipv6-loopback.service"
fi
