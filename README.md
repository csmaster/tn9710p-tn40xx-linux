# TN9710P 10GbE — working driver setup for Linux kernel 7.0

Getting a **Tehuti TN9710P** (PCI `1fc9:4027`, Marvell **MV88X3310** PHY) NIC to
**10 GbE link-up** on Ubuntu kernel **7.0.0-22-generic**, using a patched
out-of-tree `tn40xx` driver installed via **DKMS**.

> Status: **WORKING** — `enp36s0`, `Speed: 10000Mb/s`, `Link detected: yes`,
> auto-binds on boot, DKMS auto-rebuilds on kernel updates.

This repo exists as a personal rebuild/recovery backup. The Tehuti driver is GPL;
the PHY firmware blob was extracted from the vendor's Windows driver (see
[Firmware provenance](#firmware-provenance)).

---

## TL;DR — install on a fresh machine

```bash
git clone <this-repo> TehutiSetup
cd TehutiSetup
sudo bash scripts/install-dkms.sh     # builds + installs via DKMS, sets up boot
sudo modprobe tn40xx                   # load now (or just reboot)
ip -br link                            # find the new 10G interface (e.g. enp36s0)
ethtool enp36s0 | grep -E 'Speed|Link detected'
```

If DKMS isn't usable: `sudo bash scripts/install-manual.sh` (must re-run after each
kernel update).

---

## The card

| | |
|---|---|
| Marketing name | TN9710P 10GBase-T / NBASE-T |
| PCI ID | `1fc9:4027` (subsys `1fc9:3015`) |
| PHY | Marvell **MV88X3310** rev A1 (MDIO ID `2B09AB`) |
| MAC driver | Tehuti `tn40xx` (out-of-tree vendor v0.3.6.16.1-IOI) |
| PCI addr (this box) | `0000:24:00.0` |
| Speeds | 100M / 1G / 2.5G / 5G / 10G baseT |

---

## Why the stock/mainline driver doesn't work

- The **mainline** `tn40xx` (in kernel 7.0) only binds `0x4022` (QT2025) and
  `0x4025` (AQR105) — **not `0x4027`** (our Marvell variant).
- Mainline `marvell10g` (phylib) does **not** upload PHY firmware; it assumes the
  PHY booted from onboard flash. This board reads `srom 0x0` — **flashless** — so
  the PHY sits in bootloader mode and **must** be host-loaded over MDIO.
- Only the **vendor** `tn40xx` driver does that MDIO firmware upload. Hence this
  out-of-tree build is the only working path.

---

## The three bugs that had to be fixed

Each one masked the next, so they were found in order.

### 1. `EXTRA_CFLAGS` ignored on kernel 7.0 → device never probed
The vendor Makefile passes PHY selection via `EXTRA_CFLAGS`, which modern kbuild
ignores. Result: `-DPHY_MV88X3310` was dropped, the `0x4027` PCI ID (guarded by
`#ifdef PHY_MV88X3310`) was compiled out, the module loaded but **never probed**
the card (`Supported phys :` was blank).

**Fix** (`Makefile`): add `ccflags-y += $(EXTRA_CFLAGS)` just before `obj-m`, and
always build with **`make MV88X3310=YES`**.

### 2. PHY firmware was byte-swapped → PHY rejected the upload
Symptom:
```
tn40xx: MV88X3310 initdata not applied. Expected bit 4 to be 1, read 0x004B
```
The firmware `.hdr` was extracted from the Windows `.sys` as a raw byte stream,
but the vendor driver expects the words in the **opposite byte order**:
- it does `swab16()` on every word before clocking it to the PHY, and
- its checksum invariant is `phy_initdata[4] == swab16(~byte_sum_of_payload)`.

For the raw blob, `phy_initdata[4] = 0xb9d0` but `swab16(~byte_sum) = 0xd0b9` —
**exactly a byte swap**. So every uploaded word was reversed and the PHY's internal
checksum failed (`bit 4` never set).

**Fix:** 16-bit byte-swap the whole `.hdr`, then regenerate the C header:
```bash
dd if=x3310fw_A.hdr of=x3310fw_0_3_3_0_9374.hdr conv=swab   # swap each byte pair
bash mvidtoh.sh x3310fw_0_3_3_0_9374.hdr MV88X3310 MV88X3310_phy.h
```
(See `scripts/fix-firmware.sh`.) After this:
```
tn40xx: MV88X3310 initdata applied
tn40xx: MV88X3310 I/D version is 0.3.4.0
```

### 3. `register_netdev` failed `-EINVAL` (ethtool coalesce)
```
WARNING: net/ethtool/common.c:924  ethtool_check_ops
tn40xx: register_netdev failed
... probe ... failed with error -22
```
Since kernel 5.7, a driver that provides `.set_coalesce` **must** also declare
`.supported_coalesce_params`. The vendor driver didn't.

**Fix** (`tn40.c`, in `bdx_ethtool_ops`):
```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 7, 0)
    .supported_coalesce_params = ETHTOOL_COALESCE_USECS |
                                 ETHTOOL_COALESCE_MAX_FRAMES,
#endif
```

> Earlier kernel-7.0 compat work (DMA API, `eth_hw_addr_set`, `strscpy`,
> `skb_frag`, ethtool link_ksettings, NAPI signature, etc.) lives in `compat.h`
> and the patched `tn40.c` / `tn40.h` / `*_phy_Linux.c` already in `driver/`.

---

## What's in this repo

```
TehutiSetup/
├── README.md                         ← this file
├── driver/tn40xx-0.3.6.16.1/         ← full patched source (builds as-is)
│   ├── dkms.conf                     ← DKMS config (MV88X3310=YES + KVERSION)
│   ├── Makefile                      ← patched (ccflags-y)
│   ├── tn40.c / tn40.h / compat.h    ← patched for kernel 7.0
│   └── MV88X3310_phy.c/.h            ← .h = byte-swap-corrected firmware (this is what
│                                        gets compiled in; the raw .hdr blobs are NOT shipped)
└── scripts/
    ├── install-dkms.sh               ← recommended installer (survives kernel updates)
    ├── install-manual.sh             ← one-kernel fallback (no DKMS)
    └── fix-firmware.sh               ← regenerate the .h from a raw .hdr (if you supply one)
```

> Note: the raw `x3310fw_*.hdr` blobs are intentionally **not** included. The firmware
> is already baked into `MV88X3310_phy.h`, so the driver builds as-is. You only need a
> `.hdr` + `fix-firmware.sh` if you ever want to regenerate the header from scratch.

---

## Rebuilding after a kernel update

With DKMS (`install-dkms.sh`) this is **automatic** — `AUTOINSTALL=yes` rebuilds
the module when a new kernel is installed. Verify any time with:
```bash
dkms status
```
Manual installs must re-run `scripts/install-manual.sh` after each kernel change.

---

## Verifying it works

```bash
dmesg | grep -iE 'tn40|MV88X3310'        # expect "initdata applied" + "I/D version is 0.3.4.0"
ls -l /sys/bus/pci/devices/0000:24:00.0/driver   # -> .../drivers/tn40xx
ip -br link                               # new 10G iface
ethtool <iface> | grep -E 'Speed|Link detected'
```

---

## Firmware provenance

See [`PROVENANCE.md`](PROVENANCE.md) for exact sources, SHA256 hashes, and step-by-step
reproduction of the firmware header from the Windows driver.

`MV88X3310_phy.h` (and the raw `x3310fw_*.hdr` blobs, not shipped here) derive from the
Marvell MV88X3310 firmware embedded in the Tehuti Windows driver `TN40xxmp_64.sys`
(v4.4.405.158), at file offset `0xabd20` (variant A) / `0xd8db0` (variant B), 184456
bytes each. To regenerate the raw blob: extract those bytes from the `.sys`, then run
`scripts/fix-firmware.sh` (it byte-swaps and produces `MV88X3310_phy.h`).

---

## Environment notes

- This machine has no GUI polkit agent and `sudo` has no TTY for automation; root
  scripts were run with `pkexec`. On a normal terminal `sudo bash <script>` is fine.
- Built/tested on Ubuntu 26.04, kernel `7.0.0-22-generic`, x86_64, Secure Boot **off**
  (DKMS auto-signs with a MOK; with Secure Boot on you'd need to enroll the key).

---

## License

- **Driver source, patches, install scripts and docs** — **GPL-2.0-or-later**, matching
  the upstream Tehuti `tn40xx` driver (it declares `MODULE_LICENSE("GPL")` and the
  "version 2 … or (at your option) any later version" header). Full text in
  [`LICENSE`](LICENSE).
- **PHY firmware** (`driver/tn40xx-0.3.6.16.1/MV88X3310_phy.h`) — **NOT** covered by the
  GPL. It is proprietary firmware owned by Tehuti / Marvell, included here only to operate
  owned hardware. See [`PROVENANCE.md`](PROVENANCE.md); redistribution may be restricted.

The GPL covers the code in this repo; it does not grant any rights to the firmware blob.
