# SuperLite OS — Kernel Options

## Current State
Initramfs saat ini tidak include kernel — pakai kernel host yang boot.
Ini berat karena kernel distro biasanya 5-10MB dengan banyak driver yang nggak perlu.

## Opsi Kernel (dari teringan ke berat)

### 1. Custom Minimal Kernel (Paling Ringan) ⭐
```bash
# Compile kernel dengan config minimal
make tinyconfig        # Base minimal (~500KB)
# Tambahin cuma yang perlu:
# - ext4, vfat (filesystem)
# - ahci, nvme, sd_mod (storage)
# - xhci_hcd, usbhid (USB)
# - evdev (input)
# - framebuffer console (display)
# Hasil: ~1-2MB bzImage vs 5-10MB distro kernel
```

### 2. linux-tiny Patchset
- Patchset yang strip kernel ke minimum
- Disable printk, debug, unused features
- Bisa dapat kernel < 1MB

### 3. Alpine Linux Kernel
- Sudah dioptimasi untuk size
- ~3-4MB dengan module support
- Stable, well-tested

### 4. Buildroot Kernel
- Auto-generate minimal kernel config
- Cocok untuk embedded/flashdisk
- Termasuk initramfs integration

## Rekomendasi untuk SuperLite

Pakai opsi **1 (Custom Minimal)** atau **3 (Alpine kernel)**:

### Alpine Kernel (Praktis)
```bash
# Download Alpine kernel + modules
ALPINE_VER=3.21
curl -L "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main/x86_64/linux-lts-${version}.apk"
```

### Custom Kernel (Paling Ringan)
```bash
# Minimal config untuk SuperLite
CONFIG_BASE_SMALL=y
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
# Hapus: debug, printk, proc, sysfs yang nggak perlu
# Include: ext4, vfat, ahci, nvme, xhci, fbcon
```
