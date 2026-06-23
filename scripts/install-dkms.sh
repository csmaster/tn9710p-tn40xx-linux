#!/bin/bash
#
# install-dkms.sh — install the patched Tehuti tn40xx driver via DKMS.
# Run on a fresh machine after `git clone` of this repo:
#     sudo bash scripts/install-dkms.sh
#
# DKMS auto-rebuilds the module on every future kernel update, so this is the
# recommended install method. See README.md for the full story.
#
set -e

VER=0.3.6.16.1
PKG=tn40xx
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRCDIR="$REPO_ROOT/driver/$PKG-$VER"
DST="/usr/src/$PKG-$VER"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root:  sudo bash $0   (or: pkexec bash $0)"
    exit 1
fi

command -v dkms >/dev/null || { echo "Installing dkms..."; apt-get update && apt-get install -y dkms; }

echo "=== 1. Stage source -> $DST ==="
[[ -d "$SRCDIR" ]] || { echo "ERROR: $SRCDIR not found (run from a clean clone)"; exit 1; }
rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRCDIR"/. "$DST"/
chmod +x "$DST"/mvidtoh.sh
# strip any build artifacts that may have been committed
rm -f "$DST"/*.ko "$DST"/*.o "$DST"/.*.cmd "$DST"/*.mod "$DST"/*.mod.c "$DST"/*.mod.o \
      "$DST"/Module.symvers "$DST"/modules.order 2>/dev/null || true
rm -rf "$DST"/.tmp_versions 2>/dev/null || true

echo "=== 2. dkms add / build / install ==="
dkms remove -m $PKG -v $VER --all 2>/dev/null || true
dkms add -m $PKG -v $VER
dkms build -m $PKG -v $VER
dkms install -m $PKG -v $VER --force

echo "=== 3. Keep mainline tn40xx out of the way (lacks 0x4027 + name clash) ==="
KVER=$(uname -r)
TEHUTI_DIR=/lib/modules/$KVER/kernel/drivers/net/ethernet/tehuti
if [[ -f "$TEHUTI_DIR/tn40xx.ko.zst" ]]; then
    mv "$TEHUTI_DIR/tn40xx.ko.zst" "$TEHUTI_DIR/tn40xx.ko.zst.mainline-disabled"
    echo "  disabled mainline tn40xx.ko.zst"
fi
rm -f "$TEHUTI_DIR/tn40xx.ko"   # remove any old manual copy

echo "=== 4. Blacklist marvell10g (phylib PHY driver; not used by this raw-MDIO driver) ==="
cat > /etc/modprobe.d/blacklist-marvell10g.conf <<'EOF'
# TN9710P: out-of-tree tn40xx host-loads MV88X3310 firmware via raw MDIO; keep marvell10g away
blacklist marvell10g
EOF

echo "=== 5. Load at boot + rebuild initramfs ==="
echo $PKG > /etc/modules-load.d/$PKG.conf
depmod -a "$KVER"
update-initramfs -u

echo ""
echo "=== DONE ==="
dkms status
modinfo $PKG | grep -E '^filename|^version'
modinfo $PKG | grep -q 4027 && echo "0x4027 alias: OK" || echo "0x4027 alias: MISSING (!)"
echo ""
echo "Load now without reboot:  sudo modprobe $PKG"
echo "Then check:               ip -br link ; ethtool <iface>"
