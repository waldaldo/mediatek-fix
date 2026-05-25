# btusb patch — Lite-On / MediaTek Bluetooth 04ca:3807 (MT7922) not working on Linux

**Fix for Lite-On Bluetooth adapter `04ca:3807` (MediaTek MT7922) not recognized by the Linux kernel.**

This repository provides an out-of-tree kernel module that patches `btusb` to add the missing USB ID entry for the Lite-On USB Bluetooth adapter `04ca:3807`, which uses a MediaTek MT7922 chip. The device is not listed in the upstream `btusb` driver table and remains unrecognized on recent kernel versions.

Includes automatic recompilation via a **pacman hook** after every kernel update.

---

## The problem

If you have a Bluetooth adapter with USB ID `04ca:3807` (shown as **Lite-On Technology Corp.** in `lsusb`) and Bluetooth does not work on Linux, you are likely hitting this bug:

```
$ lsusb
Bus 001 Device 004: ID 04ca:3807 Lite-On Technology Corp.

$ dmesg | grep -i bluetooth
# nothing — device not recognized by btusb
```

The device ID `0x04ca 0x3807` is missing from the `btusb` driver's USB ID table in the official kernel tree. As of kernel 7.x, this entry has still **not been merged upstream**.

**Affected hardware:** laptops and desktops with a Lite-On USB Bluetooth adapter (MediaTek MT7922 chip), commonly found in ASUS, Lenovo, HP, and Acer models shipping with AMD or Intel platforms.

**Affected distros:** any Linux distro running a kernel without this entry — Arch Linux, Manjaro, CachyOS, EndeavourOS, Ubuntu, Fedora, and others.

---

## The fix

The missing entry is added to `btusb.c`:

```c
/* Lite-On / MediaTek MT7922 */
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

- Any Linux distribution
- Root access (`sudo`)
- Kernel headers installed (see table above)
- `curl`, `zstd`, `make`, `gcc` or `clang` (or a full LLVM toolchain for LLVM-built kernels)

> **Pacman hook:** automatic recompilation is Arch-specific. On Debian/Ubuntu, Fedora, or other distros, run `sudo ./install-btusb-patch.sh` manually after each kernel update, or wire up an equivalent trigger via your distro's package manager hooks.

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

## Restore the original module (automated)

```bash
sudo ./uninstall-btusb-patch.sh
```

The script locates the backup created during installation (`btusb.<ext>.orig`), restores it, runs `depmod`, reloads the module, and restarts the bluetooth service.

---

## Project structure

```
mediatek-fix/
├── btusb.c                     # Patched btusb driver
├── compat.h                    # Compatibility shims across kernel versions
├── Makefile                    # Out-of-tree module build
├── apply-patch.sh              # Manual installation entry point
├── install-btusb-patch.sh      # Core install script (also called by pacman hook)
├── uninstall-btusb-patch.sh    # Restore the original module from backup
└── btusb-patch.hook            # Pacman hook definition
```

The headers `btintel.h`, `btbcm.h`, `btrtl.h`, and `btmtk.h` are downloaded at build time from the matching kernel source repository and are not included in this repo.


---

## Related searches

- `04ca:3807` bluetooth not working linux
- Lite-On Technology Corp bluetooth linux
- Lite-On 04ca 3807 bluetooth not recognized
- MediaTek MT7922 bluetooth linux fix
- MediaTek MT7922A bluetooth linux fix
- btusb missing USB ID 04ca 3807
- Bluetooth adapter not recognized Arch Linux
- btusb out-of-tree module patch kernel 6.x 7.x
- Lite-On bluetooth `lsusb` shows device but not connected
- `hciconfig` no devices found Lite-On MediaTek
- 04ca:3807 btusb driver_info BTUSB_MEDIATEK
