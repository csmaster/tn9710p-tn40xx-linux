#!/bin/bash
#
# fix-firmware.sh — reproduce the PHY-firmware fix from a RAW extraction.
#
# Background: the MV88X3310 PHY firmware was extracted from the Windows driver
# (.sys) as a raw byte stream. The vendor Linux driver expects the .hdr words in
# the OPPOSITE byte order (it applies swab16() per word on upload, and its
# checksum invariant is phy_initdata[4] == swab16(~byte_sum)). A raw extraction
# is therefore byte-swapped and the PHY rejects it:
#     "MV88X3310 initdata not applied. Expected bit 4 to be 1, read 0x004B"
#
# The fix is a 16-bit byte swap of the whole .hdr (swap each byte pair), then
# regenerate the C header with mvidtoh.sh.
#
# Usage:  bash fix-firmware.sh  <raw_input.hdr>  <driver_src_dir>
#
# NOTE: the raw .hdr blobs are NOT shipped in this repo (the firmware is already baked
# into driver/.../MV88X3310_phy.h, so you normally never need this script). You only
# need it to regenerate MV88X3310_phy.h from scratch. Obtain a raw blob by extracting
# 184456 bytes from the Tehuti Windows driver TN40xxmp_64.sys at offset 0xabd20
# (variant A) or 0xd8db0 (variant B), e.g.:
#   dd if=TN40xxmp_64.sys of=x3310fw_A.hdr bs=1 skip=$((0xabd20)) count=184456
# Then:
#   bash fix-firmware.sh x3310fw_A.hdr ../driver/tn40xx-0.3.6.16.1
#
set -e
RAW="${1:?need raw .hdr input}"
DRV="${2:?need driver source dir}"
OUT="$DRV/x3310fw_0_3_3_0_9374.hdr"

echo "Byte-swapping $RAW -> $OUT (dd conv=swab swaps each byte pair)"
dd if="$RAW" of="$OUT" conv=swab status=none

echo "Regenerating $DRV/MV88X3310_phy.h"
( cd "$DRV" && chmod +x mvidtoh.sh && bash mvidtoh.sh x3310fw_0_3_3_0_9374.hdr MV88X3310 MV88X3310_phy.h )

echo "First firmware words (should be 0x68d0, 0x0200, 0x0000 — driver swab16's them back to 0xd068,0x0002,0x0000):"
sed -n '6,8p' "$DRV/MV88X3310_phy.h"
echo "Done. Now rebuild:  make MV88X3310=YES"
