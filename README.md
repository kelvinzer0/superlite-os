# SuperLite OS

**Alpine Linux + LabWC Wayland** — Minimal, fast, beautiful.

> Uses Alpine's native `mkimage.sh` for building. No Yocto. No bitbake. No initramfs hacking. Just works.

## Features

- 🚀 **Alpine Linux edge** — minimal, musl-based
- 🪟 **LabWC (Wayland)** — OpenBox-style tiling for Wayland
- 🎨 **WhiteSur-Light theme** — macOS-inspired aesthetics
- 📦 **~300MB ISO** — full desktop in a tiny package
- 💻 **UEFI + Legacy BIOS** — hybrid boot via GRUB/syslinux
- 🔌 **Rufus + Ventoy** — ISO and DD mode compatible

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
qemu-system-x86_64 \
    -cdrom output/alpine-superlite-*.iso \
    -m 2G \
    -enable-kvm \
    -boot d
```

## How It Works

```
build.sh
  └─ Alpine mkimage.sh
       ├─ mkimg.superlite.sh      ← profile (packages, kernel, cmdline)
       └─ genapkovl-superlite.sh   ← overlay (config, services, dotfiles)
            └─ dotfiles/            ← LabWC, Waybar, Foot, Mako configs
```

**3 files. That's it.**

| File | What it does |
|------|-------------|
| `aports/scripts/mkimg.superlite.sh` | Alpine profile — defines packages, kernel flavor, boot params |
| `aports/scripts/genapkovl-superlite.sh` | Generates overlay tarball — hostname, network, services, users, dotfiles |
| `build.sh` | Entry point — sets up environment and calls mkimage.sh |

Alpine's mkimage handles everything: kernel, initramfs, squashfs, ISO generation, hybrid boot. No custom init scripts needed.

## Project Structure

```
superlite-os/
├── build.sh                          # Main build script
├── aports/
│   └── scripts/
│       ├── mkimg.superlite.sh        # Alpine profile
│       └── genapkovl-superlite.sh    # Overlay generator
├── alpine/
│   ├── configs/
│   │   ├── packages.list             # Package reference
│   │   └── repositories              # APK repos
│   ├── packages/
│   │   └── themes/                   # WhiteSur, Haiku, OhSnap
│   └── scripts/
│       ├── install-themes.sh         # Theme installer
│       └── compress-firmware.sh      # Firmware optimizer
├── dotfiles/                         # User configs
│   ├── .config/labwc/               # Window manager
│   ├── .config/waybar/              # Status bar
│   ├── .config/foot/                # Terminal
│   ├── .config/mako/                # Notifications
│   └── .config/tofi/                # App launcher
├── iso/superlite/                    # ISO metadata
└── .github/workflows/build.yml       # CI (Docker-based)
```

## Customization

### Add packages

Edit `aports/scripts/mkimg.superlite.sh`:

```bash
apks="$apks your-package-name"
```

### Change dotfiles

Edit files in `dotfiles/` — they're copied to `/etc/skel/` and `/root/` automatically.

### Change boot params

Edit `mkimg.superlite.sh`:

```bash
kernel_cmdline="unionfs_size=1G console=tty0"
```

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
