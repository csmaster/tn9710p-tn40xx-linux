#!/bin/bash
#
# install-manual.sh — NON-DKMS fallback. Builds and installs the module once for
# the *running* kernel only. Use install-dkms.sh instead unless DKMS is unavailable.
# You must re-run this after every kernel update.
#
#     sudo bash scripts/install-manual.sh
#
set -e

VER=0.3.6.16.1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRCDIR="$REPO_ROOT/driver/tn40xx-$VER"
KVER=$(uname -r)
TEHUTI_DIR=/lib/modules/$KVER/kernel/drivers/net/ethernet/tehuti

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root:  sudo bash $0   (or: pkexec bash $0)"
    exit 1
fi

echo "=== Build (MV88X3310=YES is mandatory) ==="
cd "$SRCDIR"
chmod +x mvidtoh.sh
make clean MV88X3310=YES KVERSION="$KVER" || true
make MV88X3310=YES KVERSION="$KVER"

echo "=== Install ==="
mkdir -p "$TEHUTI_DIR"
[[ -f "$TEHUTI_DIR/tn40xx.ko.zst" ]] && \
    mv "$TEHUTI_DIR/tn40xx.ko.zst" "$TEHUTI_DIR/tn40xx.ko.zst.mainline-disabled" || true
install -m 644 tn40xx.ko "$TEHUTI_DIR/tn40xx.ko"

cat > /etc/modprobe.d/blacklist-marvell10g.conf <<'EOF'
blacklist marvell10g
EOF
echo tn40xx > /etc/modules-load.d/tn40xx.conf

depmod -a "$KVER"
update-initramfs -u

echo "=== DONE ==="
modinfo tn40xx | grep -E '^filename|^version'
modinfo tn40xx | grep -q 4027 && echo "0x4027 alias: OK" || echo "0x4027 alias: MISSING (!)"
