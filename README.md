# btusb patch — MediaTek Bluetooth USB 04ca:3807 (MT7921) not working on Linux

**Fix for MediaTek Bluetooth adapter `04ca:3807` not recognized by the Linux kernel.**

This repository provides an out-of-tree kernel module that patches `btusb` to add the missing USB ID entry for the MediaTek MT7921 Bluetooth adapter (`04ca:3807`). The device is not listed in the upstream `btusb` driver table and remains unrecognized on recent kernel versions.

Includes automatic recompilation via a **pacman hook** after every kernel update.

---

## The problem

If you have a MediaTek Bluetooth adapter with USB ID `04ca:3807` and Bluetooth does not work on Linux, you are likely hitting this bug:

```
$ lsusb
Bus 001 Device 004: ID 04ca:3807 Lite-On Technology Corp.

$ dmesg | grep -i bluetooth
# nothing — device not recognized by btusb
```

The device ID `0x04ca 0x3807` is missing from the `btusb` driver's USB ID table in the official kernel tree. As of kernel 7.x, this entry has still **not been merged upstream**.

**Affected hardware:** laptops and desktops with MediaTek MT7921 Bluetooth (USB form factor), commonly found in ASUS, Lenovo, HP, and Acer models shipping with AMD or Intel platforms.

**Affected distros:** any Linux distro running a kernel without this entry — Arch Linux, Manjaro, CachyOS, EndeavourOS, Ubuntu, Fedora, and others.

---

## The fix

The missing entry is added to `btusb.c`:

```c
/* MediaTek MT7921 */
{ USB_DEVICE(0x04ca, 0x3807), .driver_info = BTUSB_MEDIATEK |
  BTUSB_WIDEBAND_SPEECH },
```

The patched module replaces the system's original `btusb.ko`. A pacman hook ensures the patch is automatically reapplied on every kernel update.

---

## Supported kernels

| Kernel flavor | Headers package | Source repository |
|---|---|---|
| `linux-cachyos` / `linux-cachyos-rc` | `linux-cachyos-headers` | CachyOS/linux |
| `linux-zen` | `linux-zen-headers` | zen-kernel/zen-kernel |
| `linux-lqx` | `linux-lqx-headers` | zen-kernel/zen-kernel |
| `linux-hardened` | `linux-hardened-headers` | anthraxx/linux-hardened |
| `linux-lts` | `linux-lts-headers` | gregkh/linux |
| `linux-rt` / `linux-rt-lts` | `linux-rt-headers` | gregkh/linux |
| `linux` (Arch mainline) | `linux-headers` | torvalds/linux |

If a flavor-specific tag is not available, the script automatically falls back to `torvalds/linux` or `gregkh/linux`.

---

## Requirements

- Arch Linux or derivative (pacman-based)
- Kernel headers installed (see table above)
- `curl`, `zstd`, `make`, `gcc` or `clang`

---

## Manual installation

```bash
git clone https://github.com/waldaldo/mediatek-fix.git
cd mediatek-fix

# Compile and install (requires root)
sudo ./apply-patch.sh
```

The script:
1. Detects the running kernel and flavor via `uname -r`
2. Verifies kernel headers are installed
3. Downloads internal Bluetooth subsystem headers from the matching kernel source repository
4. Compiles the module against the running kernel
5. Backs up the original module as `btusb.<ext>.orig` (extension matches the system's compression: `.ko.zst`, `.ko.xz`, `.ko.gz`, or `.ko`)
6. Installs the patched module and restarts `bluetooth.service`

---

## Pacman hook (automatic recompilation)

Install the hook so the patch is reapplied automatically on every kernel update:

```bash
# Copy sources to the standard path
sudo mkdir -p /usr/local/src/btusb-patch
sudo cp btusb.c compat.h /usr/local/src/btusb-patch/

# Install the build script
sudo cp install-btusb-patch.sh /usr/local/bin/install-btusb-patch
sudo chmod +x /usr/local/bin/install-btusb-patch

# Install the pacman hook
sudo mkdir -p /etc/pacman.d/hooks
sudo cp btusb-patch.hook /etc/pacman.d/hooks/
```

After this, every time a supported `*-headers` package is upgraded, pacman will automatically run `install-btusb-patch`.

> **Note:** The pacman hook is Arch-specific. On Debian/Ubuntu, Fedora, or other distros, run `sudo install-btusb-patch` manually after each kernel update, or add an equivalent trigger using your distro's package manager hooks (e.g. a dpkg post-install script or a dnf plugin).

---

## Project structure

```
mediatek-fix/
├── btusb.c                  # Patched btusb driver
├── compat.h                 # Compatibility shims across kernel versions
├── Makefile                 # Out-of-tree module build
├── apply-patch.sh           # Manual installation script
├── install-btusb-patch.sh   # Script called by the pacman hook
└── btusb-patch.hook         # Pacman hook definition
```

The headers `btintel.h`, `btbcm.h`, `btrtl.h`, and `btmtk.h` are downloaded at build time from the matching kernel source repository and are not included in this repo.

---

## Restore the original module

```bash
KVER=$(uname -r)
DEST="/lib/modules/${KVER}/kernel/drivers/bluetooth"

# Detect the extension used during install
for ext in ko.zst ko.xz ko.gz ko; do
    [[ -f "${DEST}/btusb.${ext}.orig" ]] && ORIG_EXT="$ext" && break
done

sudo cp "${DEST}/btusb.${ORIG_EXT}.orig" "${DEST}/btusb.${ORIG_EXT}"
sudo depmod -a
sudo systemctl restart bluetooth
```

---

## Related searches

- `04ca:3807` bluetooth not working linux
- MediaTek MT7921 bluetooth linux fix
- btusb missing USB ID 04ca 3807
- Bluetooth adapter not recognized Arch Linux
- btusb out-of-tree module patch kernel 6.x 7.x
- MediaTek bluetooth `lsusb` shows device but not connected
- `hciconfig` no devices found MediaTek
- Lite-On Technology Corp bluetooth linux driver
