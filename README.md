# SuperLite OS

[![Build SuperLite OS ISO](https://github.com/kelvinzer0/superlite-os/actions/workflows/build.yml/badge.svg)](https://github.com/kelvinzer0/superlite-os/actions/workflows/build.yml)

**Alpine Linux + LabWC Wayland** — Minimal, fast, beautiful.

> A lightweight Wayland desktop built on Alpine Linux using native `mkimage.sh`. No Yocto, no bitbake, no initramfs hacking. Just works.

## Features

- **Alpine Linux edge** — minimal, musl-based system
- **LabWC Wayland** — OpenBox-style window manager for Wayland
- **WhiteSur-Light theme** — macOS-inspired GTK theme with Haiku icons
- **~300MB ISO** — full desktop in a tiny package
- **UEFI + Legacy BIOS** — hybrid boot via GRUB/syslinux
- **Rufus + Ventoy** — ISO and DD mode compatible

## Quick Start

### Build (Docker — recommended)

```bash
./build.sh --docker
```

### Build (Alpine Linux native)

```bash
# On an Alpine system:
./build.sh

# Or just set up the environment:
./build.sh --setup-only
cd /root/aports/scripts
./mkimage.sh --profile superlite --arch x86_64 --outdir ~/iso/ --tag latest
```

### Run in QEMU

```bash
# Simple mode (serial console)
./run-qemu-simple.sh

# Full mode with options
./run-qemu.sh --memory 2G --gui

# Debug mode with tmux
./run-qemu-debug.sh
```

## How It Works

```
build.sh
  └─ Alpine mkimage.sh
       ├─ mkimg.superlite.sh      ← profile (packages, kernel, cmdline)
       └─ genapkovl-superlite.sh   ← overlay (config, services, dotfiles)
            ├─ alpine/configs/      ← packages.list, repositories
            └─ dotfiles/            ← LabWC, Waybar, Foot, Mako, GTK themes
```

| File | Purpose |
|------|---------|
| `aports/scripts/mkimg.superlite.sh` | Alpine profile — reads packages from `alpine/configs/packages.list` |
| `aports/scripts/genapkovl-superlite.sh` | Generates overlay — config, services, dotfiles, themes |
| `build.sh` | Entry point — sets up environment and calls mkimage.sh |

## Project Structure

```
superlite-os/
├── build.sh                              # Main build script
├── Makefile                              # Build commands
├── aports/
│   └── scripts/
│       ├── mkimg.superlite.sh            # Alpine profile
│       └── genapkovl-superlite.sh        # Overlay generator
├── alpine/
│   ├── configs/
│   │   ├── packages.list                 # Package list
│   │   └── repositories                  # APK repositories
│   └── scripts/
│       └── compress-firmware.sh          # Firmware optimizer
├── dotfiles/
│   ├── .config/
│   │   ├── labwc/                        # Window manager config
│   │   ├── waybar/                       # Status bar
│   │   ├── foot/                         # Terminal
│   │   ├── mako/                         # Notifications
│   │   ├── tofi/                         # App launcher
│   │   ├── gtk-3.0/                      # GTK3 theme settings
│   │   └── gtk-4.0/                      # GTK4 theme settings
│   └── usr/share/
│       ├── fonts/ohsnap/                 # OhSnap bitmap font
│       ├── icons/Haiku/                  # Haiku icon theme
│       └── themes/WhiteSur-Light/        # GTK theme
├── tests/
│   └── validate-build.sh                 # Build validation
├── run-qemu.sh                           # QEMU runner (full)
├── run-qemu-simple.sh                    # QEMU runner (simple)
├── run-qemu-debug.sh                     # QEMU debug with tmux
└── .github/workflows/build.yml           # CI/CD pipeline
```

## Customization

### Add packages

Edit `alpine/configs/packages.list`:

```
# Add your package under the appropriate section
your-package-name
```

### Change repositories

Edit `alpine/configs/repositories`:

```
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
```

### Change dotfiles

Edit files in `dotfiles/` — they're copied to `/etc/skel/` and `/root/` automatically during build.

### Change themes

Theme files are in `dotfiles/usr/share/`:
- **GTK theme**: `themes/WhiteSur-Light/`
- **Icons**: `icons/Haiku/`
- **Fonts**: `fonts/ohsnap/`

## Comparison

| | Yocto | Alpine mkimage |
|---|---|---|
| Build time | 2-6 hours | 5-15 minutes |
| Disk usage | 50GB+ | <1GB |
| Complexity | Layers, recipes, bitbake | 3 shell scripts |
| Initramfs | Custom hooks, Lua init | Alpine handles it |
| Learning curve | Steep | Copy this repo |

## License

MIT
