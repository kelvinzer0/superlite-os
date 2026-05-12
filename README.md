# SuperLite OS

Ultra-lightweight Linux distribution untuk bootable flashdisk. Custom desktop environment berbasis Python + GTK, hanya dengan 4 aplikasi inti: Terminal, File Manager, Chrome Browser, Text Editor.

## Arsitektur

```
superlite-os/
├── core/                  # Desktop Environment
│   ├── wm/                # Window Manager (tiling + floating)
│   ├── panel/             # Taskbar & system tray
│   ├── launcher/          # App launcher (dmenu-style)
│   └── session/           # Session & lifecycle manager
├── apps/                  # Built-in applications
│   ├── terminal/          # Terminal emulator
│   ├── filemanager/       # File manager
│   ├── texteditor/        # Text editor
│   └── browser/           # Chrome launcher
├── drivers/               # Driver & bootable tools
│   ├── dump/              # Driver dump utility
│   ├── crosschain/        # Cross-chain bootable builder
│   └── firmware/          # Firmware extraction
├── build/                 # Build system
│   ├── configs/           # System configs
│   ├── scripts/           # Build scripts
│   └── iso/               # ISO generation
├── assets/                # Themes, icons, wallpapers
├── utils/                 # Shared utilities
└── tests/                 # Unit tests
```

## Modular Architecture

Setiap komponen independen dan bisa di-test sendiri:

- **Core** → Desktop environment, window manager, panel
- **Apps** → Aplikasi yang bisa di-swap/extend
- **Drivers** → Driver dump & cross-chain bootable tools
- **Build** → Pipeline buat assemble ISO

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Run desktop environment (development mode)
python -m superlite.session

# Build bootable ISO
python -m superlite.build --target iso

# Driver dump (cross-chain)
python -m superlite.drivers.dump --device /dev/sdX
```

## Requirements

- Python 3.10+
- PyGObject (GTK4)
- libgtk-4-dev
- debootstrap (build time)
- xorriso (ISO generation)

## Boot Flow

```
BIOS/UEFI → GRUB → Linux Kernel → initramfs
  → superlite-session (Python DE)
    → Panel (taskbar + systray)
    → Window Manager (tiling/floating)
    → App Launcher
```

## License

MIT
