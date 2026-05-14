# PLAN.md — SuperLite OS Build Fix

> Source: http://bashupload.app/cr00qk.txt
> Status: **Belum dimulai**
> Date: 2026-05-15

---

## Masalah dari Log Build

```
[iso] WARNING: squashfs module missing in initrd
[iso] WARNING: nls_iso8859_1 module missing in initrd
cttyhack: applet not found
/bin/sh: can't access tty; job control turned off
RESULT: FAILED — 1 critical error(s)
```

---

## Task 1 🔴 — Fix `cttyhack: applet not found` (CRITICAL)

**Root Cause:** Wrapper `/bin/cttyhack` dibuat di rootfs tapi tidak masuk ke initramfs.

### 1.1 — Edit `alpine/scripts/make-iso.sh` (~baris 89)

Tambahkan **SEBELUM** blok `if [[ -f "$IRD_DIR/bin/busybox" ]]; then`:

```sh
# Pastikan busybox.static ada di initramfs sebagai fallback
# karena busybox dinamis Alpine mungkin tidak punya semua applet
if [[ ! -f "$IRD_DIR/bin/busybox" ]]; then
    # Coba copy busybox.static sebagai pengganti
    for bb_src in \
        "${ROOTFS}/bin/busybox.static" \
        "${ROOTFS}/usr/bin/busybox" \
        "${ROOTFS}/bin/busybox"; do
        if [[ -f "$bb_src" ]]; then
            cp "$bb_src" "$IRD_DIR/bin/busybox"
            chmod +x "$IRD_DIR/bin/busybox"
            log "Copied $(basename $bb_src) as busybox to initramfs"
            break
        fi
    done
fi

# Jika busybox di initramfs tidak punya cttyhack, inject busybox.static
if [[ -f "${ROOTFS}/bin/busybox.static" ]]; then
    cp "${ROOTFS}/bin/busybox.static" "$IRD_DIR/bin/busybox.static" 2>/dev/null || true
    # Buat symlink cttyhack → busybox.static
    for applet in cttyhack setsid findmnt; do
        if [[ ! -e "$IRD_DIR/bin/$applet" ]]; then
            ln -sf /bin/busybox.static "$IRD_DIR/bin/$applet"
            log "Linked $applet → busybox.static in initramfs"
        fi
    done
fi
```

### 1.2 — Edit `alpine/hooks/live-boot` (~baris 36)

Tambah fallback setelah `binpath=$(command -v "$bin" 2>/dev/null)`:

```sh
# Fallback: cari di rootfs Alpine (untuk cttyhack yang tidak ada di host Ubuntu)
if [ -z "$binpath" ]; then
    for rootfs_path in \
        "${ROOTFS:-/}/bin/$bin" \
        "${ROOTFS:-/}/usr/bin/$bin" \
        "${ROOTFS:-/}/sbin/$bin"; do
        [ -f "$rootfs_path" ] && binpath="$rootfs_path" && break
    done
fi
```

---

## Task 2 🟡 — Fix Module Copy (squashfs, nls_iso8859_1)

**Root Cause:** Module disalin ke flat `kernel/` tapi ada di subfolder deep. Script gagal karena struktur direktori hilang.

### 2.1 — Edit `alpine/scripts/make-iso.sh` (~baris 100-120)

Ganti blok `for mod in squashfs loop ...` dengan versi yang pertahankan struktur direktori:

```sh
for mod in squashfs loop isofs sr_mod usb-storage sd_mod nls_cp437 nls_iso8859_1; do
    if ! find "$IRD_DIR/lib/modules/$KVER_IRD" \
         \( -name "${mod}.ko*" -o -name "${mod//_/-}.ko*" \) 2>/dev/null | grep -q .; then
        log "WARNING: $mod module missing in initrd — copying from rootfs..."
        KVER_ROOT=$(ls "${ROOTFS}/lib/modules/" 2>/dev/null | head -1 || echo "")
        if [[ -n "$KVER_ROOT" ]]; then
            # Cari modul di rootfs dan pertahankan struktur path relatifnya
            while IFS= read -r -d '' mod_file; do
                # Ambil path relatif dari lib/modules/$KVER_ROOT/
                rel_path="${mod_file#${ROOTFS}/lib/modules/$KVER_ROOT/}"
                dest_dir="$IRD_DIR/lib/modules/$KVER_IRD/$(dirname "$rel_path")"
                mkdir -p "$dest_dir"
                cp "$mod_file" "$dest_dir/" 2>/dev/null && \
                    log "  Copied $mod → $(dirname $rel_path)/"
            done < <(find "${ROOTFS}/lib/modules/$KVER_ROOT" \
                \( -name "${mod}.ko*" -o -name "${mod//_/-}.ko*" \) \
                -print0 2>/dev/null)
        fi
    fi
done

# Regenerate modules.dep SETELAH semua modul disalin
if command -v depmod >/dev/null 2>&1 && [[ -n "$KVER_IRD" ]]; then
    log "Regenerating modules.dep in initramfs..."
    depmod -a -b "$IRD_DIR" "$KVER_IRD" 2>/dev/null || true
fi
```

---

## Task 3 🟡 — Fix Kernel Boot Parameters

**Root Cause:** `boot=live` adalah konvensi Debian live-boot, bukan Alpine. Alpine pakai `alpine_dev`.

### 3.1 — Edit `alpine/scripts/make-iso.sh`

Tambah `alpine_dev=cdrom:iso9660` di **3 tempat**:

1. GRUB config — `menuentry "SuperLite OS (Live)"`
2. GRUB config — `menuentry "SuperLite OS (Live — Safe Mode)"`
3. Syslinux config — `LABEL superlite` dan `LABEL safe`

```diff
- linux /boot/vmlinuz-lts boot=live console=ttyS0,115200 loglevel=7
+ linux /boot/vmlinuz-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 loglevel=7
```

---

## Task 4 🟢 — Buat Disk Installer (file baru)

### 4.1 — Buat `alpine/scripts/superlite-install.sh`

Fitur: scan disk → pilih target → detect UEFI/BIOS → auto partisi → format → extract squashfs → setup fstab → install bootloader → cleanup.

Script lengkap ada di source: http://bashupload.app/cr00qk.txt (bagian "Masalah 4").

---

## Ringkasan File

| File | Action | Task |
|------|--------|------|
| `alpine/scripts/make-iso.sh` | Edit (3 bagian) | 1.1, 2.1, 3.1 |
| `alpine/hooks/live-boot` | Edit (1 bagian) | 1.2 |
| `alpine/scripts/superlite-install.sh` | **Buat baru** | 4.1 |

---

## Execution Order

```
Task 1 (Critical) ──→ Task 2 ──→ Task 3 ──→ Task 4
```

**Quick fix paling penting:** Task 1 — tanpa ini, boot GAGAL.
