# ⚡ SuperLite OS

Ultra-lightweight Alpine Linux desktop with LabWC Wayland compositor. Boots from USB, runs entirely in RAM. ~400MB ISO, ~1.5GB installed.

## Features

- **Alpine Linux edge** — minimal, musl-based, openrc init
- **LabWC Wayland** — tiling/floating compositor (openbox-like)
- **Waybar** — modern status bar with workspaces, clock, system tray
- **Foot** — fast Wayland-native terminal
- **PipeWire** — audio stack with PulseAudio compatibility
- **NetworkManager** — WiFi + wired networking
- **Auto-login** — boots straight to desktop
- **Dual boot** — UEFI (GRUB) + Legacy BIOS (syslinux)
- **Rufus & Ventoy** — compatible with both tools

## Included Software

| Category | Apps |
|----------|------|
| Terminal | Foot |
| File Manager | PCManFM |
| Text Editor | Micro, Neovim |
| Browser | Firefox |
| Launcher | Tofi (rofi-style) |
| Notifications | Mako |
| Audio | PipeWire + WirePlumber |
| Screenshot | Grim + Slurp |

## Quick Start

### Build

```bash
# Install build dependencies (Debian/Ubuntu)
sudo apt install squashfs-tools xorriso mtools dosfstools \
    wget ca-certificates syslinux

# Build ISO
make build
# or
sudo ./build.sh
```

### Boot

**USB (dd mode):**
```bash
sudo dd if=superlite-os-*.iso of=/dev/sdX bs=4M status=progress
```

**Rufus:** Select ISO → ISO mode or DD mode → Write

**Ventoy:** Copy ISO to Ventoy USB drive, boot from it

**QEMU:**
```bash
make test-qemu
# or with UEFI:
make test-qemu-efi
```

## Keybindings

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Foot) |
| `Super+d` | App Launcher (Tofi) |
| `Super+e` | File Manager |
| `Super+q` | Close window |
| `Super+f` | Toggle maximize |
| `Super+Space` | Toggle floating |
| `Super+1-4` | Switch workspace |
| `Super+l` | Lock screen |
| `Print` | Screenshot |
| `Alt+Print` | Area screenshot |
| Right-click desktop | App menu |

## Architecture

```
superlite-os/
├── build.sh                    # Main build script
├── alpine/
│   ├── configs/
│   │   ├── packages.list       # All Alpine packages
│   │   └── repositories        # Alpine edge repos
│   └── scripts/
│       ├── setup-rootfs.sh     # Rootfs configuration (runs in chroot)
│       └── make-iso.sh         # ISO generation (UEFI + Legacy hybrid)
├── dotfiles/                   # Desktop config files
│   └── .config/
│       ├── labwc/              # Window manager config
│       ├── waybar/             # Status bar config
│       ├── foot/               # Terminal config
│       ├── mako/               # Notifications config
│       ├── tofi/               # App launcher config
│       └── scripts/            # Utility scripts
├── iso/                        # ISO boot structure
│   ├── boot/grub/              # GRUB (UEFI)
│   ├── boot/syslinux/          # Syslinux (Legacy BIOS)
│   └── EFI/BOOT/               # EFI boot binary
├── Makefile                    # Build targets
└── tests/                      # Build tests
```

## Build Process

1. Downloads Alpine minirootfs (x86_64)
2. Creates chroot rootfs
3. Installs packages via `apk`
4. Applies LabWC + Waybar + desktop dotfiles
5. Enables services (seatd, dbus, NetworkManager)
6. Compresses rootfs to squashfs
7. Generates hybrid ISO with dual boot:
   - **Legacy BIOS:** syslinux/isolinux with MBR
   - **UEFI:** GRUB EFI binary
8. Result: ISO works with dd, Rufus (ISO+DD), and Ventoy

## Customization

**Change packages:** Edit `alpine/configs/packages.list`

**Change dotfiles:** Edit files in `dotfiles/.config/`

**Change boot menu:** Edit `iso/boot/grub/grub.cfg` or `iso/boot/syslinux/isolinux.cfg`

**Add wallpaper:** Place image as `dotfiles/.config/labwc/wallpaper.png`

## Requirements

### Build Host
- Linux (Debian/Ubuntu recommended)
- Root access (for chroot)
- ~2GB free disk space
- Internet connection

### Runtime
- x86_64 CPU
- 512MB RAM minimum (1GB+ recommended)
- USB drive or Ventoy

## License

MIT
