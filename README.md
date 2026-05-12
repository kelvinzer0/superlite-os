# SuperLite OS

Ultra-lightweight Linux distribution untuk bootable flashdisk. Custom desktop environment berbasis Python + GTK4, hanya dengan 4 aplikasi inti: Terminal, File Manager, Text Editor, Chrome Browser.

## Arsitektur

```
superlite-os/
├── core/                  # Desktop Environment
│   ├── session/           # Session manager (entry point)
│   ├── wm/                # Window Manager (tiling + floating)
│   ├── panel/             # Taskbar & system tray
│   ├── launcher/          # App launcher (dmenu-style)
│   └── theme/             # Theming engine
├── apps/                  # Built-in applications
│   ├── terminal/          # Terminal emulator (GTK4 VTE)
│   ├── filemanager/       # File manager
│   ├── texteditor/        # Text editor
│   └── browser/           # Chrome launcher
├── drivers/               # Driver & bootable tools
│   ├── dump/              # Host driver dump utility
│   ├── crosschain/        # Cross-chain bootable builder
│   └── firmware/          # Firmware extraction
├── build/                 # Build system
│   ├── builder.py         # Main build orchestrator
│   ├── configs/           # System configs (default.json)
│   └── scripts/           # Build scripts
├── build-and-run.sh       # ⚡ Full pipeline: dump → build → QEMU + noVNC
├── demo.sh                # Quick demo (Xvfb mode, no disk image)
├── assets/                # Themes, icons, wallpapers
└── utils/                 # Shared utilities
```

## Quick Start

### Option 1: Demo Mode (Xvfb, no disk image)
```bash
# Install deps
apt install python3-gi gir1.2-gtk-4.0 openbox x11vnc novnc websockify cloudflared

# Run demo
./demo.sh
```

### Option 2: Full Build + QEMU (bootable disk image)
```bash
# Install deps
apt install debootstrap xorriso qemu-system-x86 python3-gi gir1.2-gtk-4.0 \
    openbox x11vnc novnc websockify
# cloudflared: https://github.com/cloudflare/cloudflared/releases

# Build + run
sudo ./build-and-run.sh
```

### Option 3: Manual Build
```bash
# 1. Dump host drivers
python3 -c "from drivers.dump import DriverDump; DriverDump().dump_all()"

# 2. Build rootfs
sudo debootstrap --arch amd64 --variant=minbase \
    --include systemd,systemd-sysv,dbus,xorg,openbox,xinit,python3-gi,gir1.2-gtk-4.0 \
    bookworm ~/.superlite/build/rootfs http://deb.debian.org/debian

# 3. Copy SuperLite DE into rootfs
cp -r core apps assets ~/.superlite/build/rootfs/usr/share/superlite/

# 4. Configure auto-boot (see build-and-run.sh for full config)

# 5. Build disk image
python3 -m superlite.build --target iso

# 6. Run with QEMU
qemu-system-x86_64 -m 512 -hda ~/.superlite/build/superlite-os.img -vnc :0
```

## Boot Flow

```
BIOS/UEFI → GRUB → Linux Kernel → systemd
  → getty@tty1 (auto-login root)
  → startx
  → xinitrc
    → openbox (Window Manager)
    → SuperLite DE (Python GTK4)
      → Panel (taskbar + systray)
      → Window Manager (tiling/floating)
      → App Launcher
```

## Default Keybindings

| Key | Action |
|-----|--------|
| `Super+Return` | App Launcher |
| `Super+q` | Close window |
| `Super+j/k` | Focus next/prev |
| `Super+f` | Toggle maximize |
| `Super+m` | Minimize |
| `Super+space` | Toggle floating |
| `Super+1-4` | Switch workspace |
| `Super+e` | File Manager |
| `Super+n` | Text Editor |
| `Super+b` | Browser |

## Configuration

Config file: `build/configs/default.json` (copied to `/etc/superlite/config.json`)

```json
{
  "wm": { "gap": 4, "layout": "tiling", "keybindings": {...} },
  "panel": { "position": "top", "height": 36 },
  "theme": { "name": "midnight", "bg": "#0f0f23", "accent": "#e94560" },
  "terminal": { "font": "Monospace 11" },
  "editor": { "font": "Monospace 13", "tab_width": 4 }
}
```

## Requirements

- Python 3.10+
- PyGObject (GTK4)
- libgtk-4-dev
- debootstrap (build time)
- xorriso (ISO generation)
- QEMU (testing)

## Driver Dump (Cross-Chain)

Dump host hardware drivers untuk di-embed ke bootable image:

```bash
python3 -m superlite.drivers.dump
# Output: ~/.superlite/driver-dump/
#   ├── manifest.json
#   ├── modules/ (*.ko files)
#   └── firmware/ (firmware blobs)
```

Supports: GPU, network, storage, USB, input, audio, bluetooth, WiFi, virtual.

## License

MIT
