# ⚡ SuperLite OS

Ultra-lightweight Alpine Linux desktop with LabWC Wayland compositor. Boots from USB, runs entirely in RAM. ~400MB ISO, ~1.5GB installed.

**Now built with [Yocto Project](https://www.yoctoproject.org/) for reproducible, standardized builds.**

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
- **Yocto-based** — reproducible builds, standard layer structure

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

### Prerequisites (Debian/Ubuntu)

```bash
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect python3-git \
    python3-jinja2 python3-subunit zstd liblz4-tool file locales libacl1 \
    squashfs-tools xorriso mtools dosfstools

sudo locale-gen en_US.UTF-8
```

### Build

```bash
# Full build (Yocto image + ISO)
make build

# Or step by step:
make setup           # Clone Poky + configure layers
make build-image     # Build Yocto image
make iso             # Generate bootable ISO
```

### Boot

**USB (dd mode):**
```bash
sudo dd if=superlite-os-*.iso of=/dev/sdX bs=4M status=progress
```

**Rufus:** Select ISO → ISO mode or DD mode → Write

**Ventoy:** Copy ISO to Ventoy USB drive, boot from it

## Architecture

```
superlite-os/
├── build.sh                            # Yocto build orchestrator
├── Makefile                            # Build targets
├── meta-superlite/                     # ★ Yocto Layer
│   ├── conf/
│   │   ├── layer.conf                  # Layer metadata
│   │   ├── machine/
│   │   │   └── superlite-x86_64.conf   # Machine config (x86_64 live)
│   │   └── distro/
│   │       └── superlite.conf          # Distro config
│   ├── recipes-core/
│   │   ├── images/
│   │   │   └── superlite-os-image.bb   # Main image recipe
│   │   └── packagegroups/
│   │       ├── packagegroup-superlite-base.bb
│   │       ├── packagegroup-superlite-desktop.bb
│   │       ├── packagegroup-superlite-network.bb
│   │       └── packagegroup-superlite-apps.bb
│   ├── recipes-graphics/
│   │   ├── labwc/labwc.bb              # Wayland compositor
│   │   ├── waybar/waybar.bb            # Status bar
│   │   ├── foot/foot.bb                # Terminal
│   │   └── tofi/tofi.bb                # App launcher
│   ├── recipes-apps/
│   │   ├── superlite-live/             # Live-boot hooks + init
│   │   ├── superlite-dotfiles/         # Desktop config files
│   │   ├── superlite-hooks/            # System hooks
│   │   └── superlite-themes/           # External themes
│   ├── recipes-kernel/
│   │   └── linux-superlite/            # Custom kernel + config fragments
│   └── wic/
│       └── superlite-live.wks          # WIC kickstart (boot layout)
├── alpine/                             # Legacy Alpine-specific files
│   ├── configs/
│   ├── scripts/
│   ├── hooks/
│   └── packages/
├── dotfiles/                           # Desktop configuration
│   └── .config/
│       ├── labwc/                      # Window manager
│       ├── waybar/                     # Status bar
│       ├── foot/                       # Terminal
│       ├── mako/                       # Notifications
│       ├── tofi/                       # App launcher
│       └── scripts/                    # Utility scripts
├── iso/                                # ISO boot structure (legacy)
├── tests/
│   └── validate-build.sh              # Build validation
└── README.md
```

## Yocto Layer Structure

The project is organized as a standard Yocto layer (`meta-superlite`):

### Layer Configuration (`conf/layer.conf`)
- Defines layer metadata, dependencies, and compatibility
- Depends on: `core`, `openembedded-layer`, `wayland-layer`

### Machine Configuration (`conf/machine/superlite-x86_64.conf`)
- Target: x86_64 with UEFI + Legacy BIOS boot
- Kernel: `linux-superlite` (custom config with GPU, WiFi, live-boot)
- Root filesystem: squashfs-xz for live boot

### Distro Configuration (`conf/distro/superlite.conf`)
- Minimal feature set (Wayland, no X11)
- Size-optimized (`-Os`)
- musl-compatible (when using meta-alpine)

### Image Recipe (`recipes-core/images/superlite-os-image.bb`)
- Inherits `core-image` + `extrausers`
- Installs 4 package groups: base, desktop, network, apps
- Post-processing: auto-login, MOTD, fstab, NetworkManager, XDG env
- Strips binaries and removes docs for minimal footprint

### Package Groups
| Group | Contents |
|-------|----------|
| `packagegroup-superlite-base` | busybox, openrc, kernel, shell, utils, build tools |
| `packagegroup-superlite-desktop` | labwc, waybar, foot, mako, tofi, mesa, pipewire |
| `packagegroup-superlite-network` | NetworkManager, wpa-supplicant, bluez5, iptables |
| `packagegroup-superlite-apps` | pcmanfm, micro, neovim, firefox, grim, slurp |

### Custom Recipes
| Recipe | Description |
|--------|-------------|
| `labwc.bb` | Wayland compositor (meson build) |
| `waybar.bb` | Status bar (meson build) |
| `foot.bb` | Terminal emulator (meson build) |
| `tofi.bb` | App launcher (meson build) |
| `superlite-live.bb` | mkinitfs hooks, Lua live init, firmware compression |
| `superlite-dotfiles.bb` | Desktop config files (labwc, waybar, foot, etc.) |
| `superlite-hooks.bb` | System hooks and scripts |
| `superlite-themes.bb` | WhiteSur, Haiku, OhSnap themes |
| `linux-superlite.bb` | Custom kernel with config fragments |

### Kernel Config Fragments
| Fragment | Purpose |
|----------|---------|
| `superlite.cfg` | Base: modules, live-boot, USB, filesystem, networking |
| `gpu.cfg` | Intel i915, AMD amdgpu, virtio GPU |
| `wifi.cfg` | Intel, Atheros, Realtek, Broadcom, MediaTek |
| `live-boot.cfg` | Squashfs, overlayfs, loop devices, initramfs |

## Build Process (Yocto)

1. **Setup:** `make setup` clones Poky + meta-openembedded + meta-alpine
2. **Configure:** `build.sh` writes `bblayers.conf` + `local.conf`
3. **BitBake:** Builds all recipes in dependency order
4. **Image:** `superlite-os-image.bb` produces squashfs-xz rootfs
5. **ISO:** `superlite-boot.sh` creates hybrid ISO (UEFI + Legacy BIOS)
6. **Result:** ISO works with dd, Rufus (ISO+DD), and Ventoy

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

## Customization

**Change packages:** Edit `meta-superlite/recipes-core/packagegroups/*.bb`

**Change kernel config:** Add/modify fragments in `meta-superlite/recipes-kernel/linux-superlite/linux-superlite/`

**Change dotfiles:** Edit files in `dotfiles/.config/`

**Change boot menu:** Edit GRUB/syslinux configs in `superlite-boot.sh`

**Add wallpaper:** Place image as `dotfiles/.config/labwc/wallpaper.png`

**Add a new recipe:**
```bash
# Create recipe directory
mkdir -p meta-superlite/recipes-apps/my-app/my-app

# Create recipe file
cat > meta-superlite/recipes-apps/my-app/my-app.bb << 'EOF'
SUMMARY = "My custom app"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
# ... recipe content ...
EOF
```

## Requirements

### Build Host
- Linux (Debian/Ubuntu recommended)
- Root access (for chroot in legacy mode)
- ~50GB free disk space (Yocto builds)
- Internet connection
- `en_US.UTF-8` locale enabled

### Runtime
- x86_64 CPU
- 512MB RAM minimum (1GB+ recommended)
- USB drive or Ventoy

## Migration from Legacy Build

The legacy Alpine-specific build scripts are preserved in `alpine/`:

| Legacy | Yocto Equivalent |
|--------|------------------|
| `build.sh` (original) | `build.sh` (Yocto orchestrator) |
| `alpine/configs/packages.list` | `packagegroup-superlite-*.bb` |
| `alpine/scripts/setup-rootfs.sh` | `superlite-os-image.bb` (postprocess) |
| `alpine/scripts/make-iso.sh` | `superlite-boot.sh` |
| `alpine/hooks/*` | `superlite-live.bb` + `superlite-hooks.bb` |
| `Makefile` (original) | `Makefile` (updated targets) |

## License

MIT
