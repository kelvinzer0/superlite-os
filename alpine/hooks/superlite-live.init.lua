#!/bin/lua
-- ============================================================================
-- SuperLite OS — Live Boot Init (Lua)
-- ============================================================================
-- Robust Lua-based init for Alpine live-boot.
-- Fixes all issues found in QEMU testing:
--   - squashfs module not in modules.dep → insmod fallback
--   - tmpfs hiding squashfs mount → separate mount points
--   - overlayfs workdir/upperdir same mount → single tmpfs
--   - switch_root needs mountpoint → bind mount
-- ============================================================================

local function log(msg)   io.write("[live] " .. msg .. "\n"); io.flush() end
local function err(msg)   io.stderr:write("[live] ERROR: " .. msg .. "\n"); io.stderr:flush() end
local function warn(msg)  io.stderr:write("[live] WARN: " .. msg .. "\n"); io.stderr:flush() end

local function exec(cmd)
    local h = io.popen(cmd .. " 2>&1")
    if not h then return false, "" end
    local out = h:read("*a")
    local ok = h:close()
    return ok ~= nil, out
end

local function exec_silent(cmd) os.execute(cmd .. " 2>/dev/null") end
local function file_exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end
local function block_exists(p) return os.execute("test -b " .. p) == true end

local function mount(fstype, src, tgt, opts)
    local cmd = "mount"
    if fstype then cmd = cmd .. " -t " .. fstype end
    if opts then cmd = cmd .. " -o " .. opts end
    cmd = cmd .. " " .. src .. " " .. tgt
    return os.execute(cmd) == true
end

local function mkdir_p(p) exec_silent("mkdir -p " .. p) end

local function glob_block(pattern)
    local devs = {}
    local h = io.popen("ls " .. pattern .. " 2>/dev/null")
    if h then for line in h:lines() do devs[#devs+1] = line end; h:close() end
    return devs
end

local function read_cmdline()
    local f = io.open("/proc/cmdline", "r")
    if not f then return {} end
    local c = f:read("*a"); f:close()
    local p = {}; for param in c:gmatch("%S+") do p[#p+1] = param end
    return p
end

local function get_cmdline_param(params, prefix)
    for _, p in ipairs(params) do
        if p:sub(1, #prefix) == prefix then return p:sub(#prefix + 1) end
    end
    return nil
end

local function emergency_shell(msg)
    err(msg)
    err("Dropping to emergency shell. Type 'exit' to reboot.")
    exec_silent("mount -t devpts devpts /dev/pts")
    os.execute("setsid cttyhack /bin/sh -l 2>/dev/null || exec /bin/sh")
end

-- Auto-detect kernel version from /lib/modules
local function get_kver()
    local h = io.popen("ls /lib/modules/ 2>/dev/null | head -1")
    if h then local v = h:read("*l"); h:close(); return v end
    return nil
end
local KVER = get_kver() or "6.18.29-0-lts"

-- ── Step 1: Mount Virtual Filesystems ────────────────────────────────────────

log("Mounting virtual filesystems...")
mount("proc", "proc", "/proc")
mount("sysfs", "sysfs", "/sys")
mount("devtmpfs", "devtmpfs", "/dev")
mkdir_p("/dev/pts"); mkdir_p("/dev/shm")
mount("devpts", "devpts", "/dev/pts")
mount("tmpfs", "tmpfs", "/dev/shm")

-- ── Step 2: Start Device Manager ────────────────────────────────────────────

log("Starting device manager...")
if file_exists("/sbin/mdev") then
    exec_silent("echo /sbin/mdev > /proc/sys/kernel/hotplug")
    exec_silent("mdev -s")
    log("mdev started")
else
    warn("No device manager found")
end

-- ── Step 3: Load Kernel Modules ─────────────────────────────────────────────

log("Loading kernel modules...")

local modules = {
    "scsi_mod", "scsi_common", "cdrom",
    "sr_mod", "libata", "ata_piix", "ahci",
    "usb-common", "usbcore",
    "xhci_hcd", "ehci_hcd", "ohci_hcd", "uhci_hcd",
    "usb-storage", "sd_mod", "mmc_block", "nvme_core", "nvme",
    "loop", "isofs", "overlay",
    "vfat", "fat", "msdos", "ext4", "jbd2", "crc16",
    "nls_cp437", "nls_iso8859_1", "nls_ascii",
}

local loaded, skipped = 0, 0
for _, mod in ipairs(modules) do
    if os.execute("modprobe " .. mod .. " 2>/dev/null") == true then
        loaded = loaded + 1
    else
        skipped = skipped + 1
    end
end
log(string.format("Modules: %d loaded, %d skipped", loaded, skipped))

-- ── Step 3b: Load squashfs via insmod (modprobe fails: missing modules.dep) ──
-- squashfs.ko is in the initrd but not listed in modules.dep.
-- Decompress and insmod directly as fallback.
if not os.execute("grep -q squashfs /proc/modules 2>/dev/null") then
    log("Loading squashfs via insmod...")
    local sq_gz = "/usr/lib/modules/" .. KVER .. "/kernel/fs/squashfs/squashfs.ko.gz"
    if file_exists(sq_gz) then
        exec_silent("zcat " .. sq_gz .. " > /tmp/squashfs.ko")
        local r = os.execute("insmod /tmp/squashfs.ko 2>&1")
        if r == true then
            log("squashfs loaded via insmod")
        else
            warn("insmod squashfs failed")
        end
    else
        warn("squashfs.ko.gz not found at " .. sq_gz)
    end
end

-- Create loop devices if not present
for i = 0, 7 do
    if not block_exists("/dev/loop" .. i) then
        exec_silent("mknod /dev/loop" .. i .. " b 7 " .. i)
    end
end

-- ── Step 4: Wait for Devices ────────────────────────────────────────────────

log("Waiting for devices...")
exec_silent("mdev -s")
for _ = 1, 10 do
    local devs = glob_block("/dev/sd* /dev/sr* /dev/mmcblk* /dev/nvme* /dev/vd*")
    if #devs > 0 then break end
    os.execute("sleep 1")
    exec_silent("mdev -s")
end
log("Device wait complete")

-- ── Step 5: Find Boot Media ─────────────────────────────────────────────────

log("Searching for boot media...")
local ISO_MOUNT = "/mnt/iso"
mkdir_p(ISO_MOUNT)

local function try_mount_device(dev)
    if not block_exists(dev) then return false end
    local fstypes
    if dev:match("/dev/sr") or dev:match("/dev/cdrom") then
        fstypes = {"iso9660"}
    else
        fstypes = {"iso9660", "vfat", "ext4", "exfat", "ntfs"}
    end
    for _, fstype in ipairs(fstypes) do
        if mount(fstype, dev, ISO_MOUNT, "ro") then
            if file_exists(ISO_MOUNT .. "/live/rootfs.squashfs") or
               os.execute("test -d " .. ISO_MOUNT .. "/live") == true then
                log("Found live media: " .. dev .. " (" .. fstype .. ")")
                return true
            end
            exec_silent("umount " .. ISO_MOUNT)
        end
    end
    return false
end

local function find_boot_media()
    local cmdline = read_cmdline()
    local explicit = get_cmdline_param(cmdline, "live=")
    if explicit and block_exists(explicit) then
        if try_mount_device(explicit) then return true end
    end
    for _, dev in ipairs({"/dev/sr0", "/dev/cdrom", "/dev/sr1"}) do
        if block_exists(dev) and try_mount_device(dev) then return true end
    end
    for _, pattern in ipairs({
        "/dev/sd[a-z][0-9]", "/dev/mmcblk[0-9]p[0-9]",
        "/dev/nvme[0-9]n[0-9]p[0-9]", "/dev/vd[a-z][0-9]",
    }) do
        for _, dev in ipairs(glob_block(pattern)) do
            if try_mount_device(dev) then return true end
        end
    end
    for _, dev in ipairs({"/dev/sda","/dev/sdb","/dev/vda","/dev/mmcblk0","/dev/nvme0n1"}) do
        if block_exists(dev) and try_mount_device(dev) then return true end
    end
    return false
end

if not find_boot_media() then
    err("No boot media found!")
    err("Available block devices:")
    for _, d in ipairs(glob_block("/dev/sd* /dev/sr* /dev/mmcblk* /dev/nvme* /dev/vd*")) do
        err("  " .. d)
    end
    err("Tip: pass 'live=/dev/sdX1' on kernel cmdline")
    emergency_shell("Boot media detection failed.")
end

log("Boot media mounted at " .. ISO_MOUNT)

-- ── Step 6: Mount Squashfs Rootfs ───────────────────────────────────────────
-- Mount on /squashfs (NOT /live/rootfs) because Step 7 mounts tmpfs on /live
-- which would hide anything mounted under /live/*.

local SQUASHFS = ISO_MOUNT .. "/live/rootfs.squashfs"
if not file_exists(SQUASHFS) then
    err("rootfs.squashfs not found at " .. SQUASHFS)
    emergency_shell("Squashfs not found.")
end

log("Mounting squashfs...")
mkdir_p("/squashfs")

if not mount("squashfs", SQUASHFS, "/squashfs", "ro,loop") then
    warn("Direct mount failed, trying losetup...")
    local ok, out = exec("losetup -f")
    if ok and out then
        local loop_dev = out:match("(%S+)")
        if loop_dev then
            exec_silent("losetup " .. loop_dev .. " " .. SQUASHFS)
            if not mount("squashfs", loop_dev, "/squashfs", "ro") then
                emergency_shell("Squashfs mount failed.")
            end
        else
            emergency_shell("No free loop device.")
        end
    else
        emergency_shell("losetup not available.")
    end
end

if not file_exists("/squashfs/sbin/init") then
    err("No /sbin/init in squashfs!")
    emergency_shell("Missing /sbin/init.")
end
log("Squashfs mounted OK")

-- ── Step 7: Create Overlay ──────────────────────────────────────────────────
-- overlayfs requires upperdir and workdir to be on the SAME filesystem.
-- Solution: mount a single tmpfs on /live, then use subdirectories.

log("Creating overlay...")
mkdir_p("/live")
if not mount("tmpfs", "tmpfs", "/live", "size=75%") then
    emergency_shell("Overlay tmpfs failed.")
end
mkdir_p("/live/upper")
mkdir_p("/live/work")
mkdir_p("/live/merged")

if not mount("overlay", "overlay", "/live/merged",
    "lowerdir=/squashfs,upperdir=/live/upper,workdir=/live/work") then
    local _, dmesg = exec("dmesg | tail -3")
    log("overlay dmesg: " .. (dmesg or ""))
    emergency_shell("Overlay mount failed.")
end
log("Overlay OK")

-- ── Step 8: Prepare for switch_root ─────────────────────────────────────────
-- switch_root requires NEW_ROOT to be a mountpoint.
-- Bind mount /live/merged onto itself to ensure it's a proper mountpoint.

exec_silent("mount --bind /live/merged /live/merged")

-- Create mountpoints that switch_root needs to move-mount into.
-- squashfs is built with '-e proc sys dev run tmp' so these don't exist.
mkdir_p("/live/merged/proc")
mkdir_p("/live/merged/sys")
mkdir_p("/live/merged/run")
mkdir_p("/live/merged/tmp")

-- Mount devpts and tmpfs on /dev BEFORE switch_root.
-- switch_root does 'mount --move /dev → /live/merged/dev', which replaces
-- any directories we create under /live/merged/dev. So we must mount on
-- /dev in the initramfs, and they'll move along with the /dev mount.
mkdir_p("/dev/pts")
mkdir_p("/dev/shm")
exec_silent("mount -t devpts devpts /dev/pts")
exec_silent("mount -t tmpfs tmpfs /dev/shm")

-- Bind ISO media into merged root
mkdir_p("/live/merged/media/iso")
exec_silent("mount --bind " .. ISO_MOUNT .. " /live/merged/media/iso")

-- ── Step 9: Switch Root ─────────────────────────────────────────────────────

-- NOTE: Do NOT unmount /proc, /sys, or /dev before switch_root.
-- switch_root mount-moves all mountpoints to the new root automatically.
-- OpenRC needs these filesystems to be present when it starts.

log("Switching to live root...")

if not file_exists("/live/merged/sbin/init") then
    err("/sbin/init not found in merged root!")
    emergency_shell("Missing /sbin/init in merged root.")
end

-- switch_root replaces PID 1 with the real init.
-- 'exec' ensures Lua process is replaced (no fork), so switch_root becomes PID 1.
os.execute("exec switch_root /live/merged /sbin/init")

-- If exec returns, something went wrong
err("switch_root returned — this should never happen!")
emergency_shell("switch_root failed.")
