# Provenance — driver source & PHY firmware

This repo does **not** redistribute Tehuti's proprietary Windows driver binaries
(`.sys`/`.cat`/`.inf`) or the standalone raw firmware blob. Instead, this file records
exactly where the inputs came from and how to reproduce the firmware header, so the
result is verifiable and rebuildable without shipping anyone else's binaries.

## 1. Linux driver source (`driver/tn40xx-0.3.6.16.1/`)

- Base: Tehuti `tn40xx` Linux driver **v0.3.6.16.1** (from Tehuti's 4.4.405.158 release).
- The full **patched** source is committed in this repo (patched for Linux kernel 7.0 —
  see README "the three bugs"), so no external download is needed to rebuild.

## 2. PHY firmware (`driver/tn40xx-0.3.6.16.1/MV88X3310_phy.h`)

The Marvell MV88X3310 firmware is extracted from the Tehuti **Windows** driver, then
byte-swapped and converted to a C header (`MV88X3310_phy.h`). The raw `.hdr` blobs are
not committed; `MV88X3310_phy.h` already contains the firmware as a `u16` array.

- Source binary: `TN40xxmp_64.sys` (Tehuti Windows driver), inside the cabinet below.
- Obtained from the **Microsoft Update Catalog**:
  - Search: <https://www.catalog.update.microsoft.com/Search.aspx?q=TN9710p>
  - Package: **TehutiNetworks - Net - 8/28/2018 12:00:00 AM - 4.4.405.159**
    (Drivers / Networking; "Windows Server 2016 and Later Servicing Drivers")
  - UpdateID: `6af2840b-13b3-448a-8fdb-92215b62dd93`
  - Cabinet: `d33e3a57-7303-4a9c-ae33-8aa95aa5a534_01441e73c627c4720185b9662a8f18002380b56a.cab`
    (the GUID `_`-suffix is the cab's SHA1)
  - `.cab` SHA1  : `01441e73c627c4720185b9662a8f18002380b56a`
  - `.cab` SHA256: `b679449c46bcbe23d389e7e1333625055c70f5c965fec9a917ab97fe05261306`
  - Verified: the catalog-listed base64 hashes decode exactly to the above.
- Extracted `TN40xxmp_64.sys`:
  - size 1093000 bytes
  - SHA256: `10ed26a0cc0018c2f1900bfe3f534bacdc76258cade0baf913f32ab46a6b13c1`
- (32-bit `TN40xxmp_32.sys`, not used: SHA256
  `9453a6f9b88b9b09aa4e5b26956541737b8d95c18fcfb948409c2821db2984bf`)

### Reproduce the firmware header

```bash
# 1. unpack the cab (Linux: cabextract; or expand.exe on Windows)
cabextract d33e3a57-...cab            # -> TN40xxmp_64.sys

# 2. carve the firmware blob (variant A; 184456 bytes at offset 0xabd20)
dd if=TN40xxmp_64.sys of=x3310fw_A.hdr bs=1 skip=$((0xabd20)) count=184456
#    (variant B lives at offset 0xd8db0 — alternate board revision)

# 3. byte-swap + generate the C header (see scripts/fix-firmware.sh)
bash scripts/fix-firmware.sh x3310fw_A.hdr driver/tn40xx-0.3.6.16.1
#    -> driver/tn40xx-0.3.6.16.1/MV88X3310_phy.h
```

Both blobs begin with the bytes `d0 68 00 02 00 00 00 10` (firmware magic), which you can
use to confirm you carved the right region.

## Licensing note

The driver is GPL, but the **firmware** (whether as a `.hdr`, as `MV88X3310_phy.h`, or
inside the `.sys`) remains the property of Tehuti/Marvell. Extracted here for personal
use to drive owned hardware.
