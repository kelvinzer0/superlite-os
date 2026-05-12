"""SuperLite OS Builder - Assembles complete bootable system"""

import os
import sys
import json
import shutil
import subprocess
import argparse
from dataclasses import dataclass
from typing import Optional

from ..drivers.dump import DriverDump
from ..drivers.crosschain import CrossChainBuilder, BuildConfig


@dataclass
class SuperLiteBuilder:
    """
    Main build orchestrator for SuperLite OS.

    Usage:
        python -m superlite.build --target iso
        python -m superlite.build --target img --size 4096
        python -m superlite.build --dump-drivers  # Just dump drivers
    """

    workspace: str = None
    target: str = "iso"  # iso | img | both
    image_size_mb: int = 2048
    include_drivers: bool = True
    driver_dump_dir: str = None

    def __post_init__(self):
        self.workspace = self.workspace or os.path.expanduser("~/.superlite/build")
        self.driver_dump_dir = self.driver_dump_dir or os.path.expanduser("~/.superlite/driver-dump")

    def build(self) -> str:
        """Run the full build pipeline."""
        print("=" * 60)
        print("  SuperLite OS Builder")
        print(f"  Target: {self.target} | Size: {self.image_size_mb}MB")
        print("=" * 60)

        # Step 1: Dump drivers if needed
        if self.include_drivers:
            self._dump_drivers()

        # Step 2: Cross-chain build
        config = BuildConfig(
            output_size_mb=self.image_size_mb,
        )
        builder = CrossChainBuilder(config, self.workspace)

        driver_dir = self.driver_dump_dir if self.include_drivers else None
        image = builder.build(driver_dump_dir=driver_dir)

        if not image:
            print("[Build] Failed!")
            return ""

        # Step 3: Generate ISO if requested
        if self.target in ("iso", "both"):
            iso_path = self._generate_iso(image)
            print(f"[Build] ISO: {iso_path}")

        if self.target in ("img", "both"):
            print(f"[Build] Image: {image}")

        print("[Build] Complete!")
        return image

    def _dump_drivers(self):
        """Dump host drivers for cross-chain injection."""
        if os.path.isdir(self.driver_dump_dir):
            manifest = os.path.join(self.driver_dump_dir, "manifest.json")
            if os.path.isfile(manifest):
                print(f"[Build] Using existing driver dump: {self.driver_dump_dir}")
                return

        print("[Build] Dumping host drivers...")
        dumper = DriverDump(self.driver_dump_dir)
        dumper.dump_all(include_firmware=True)

    def _generate_iso(self, image_path: str) -> str:
        """Generate bootable ISO from image."""
        iso_dir = os.path.join(self.workspace, "iso")
        os.makedirs(iso_dir, exist_ok=True)

        # Check for xorriso
        if not shutil.which("xorriso"):
            print("[Build] xorriso not found, skipping ISO generation")
            print("[Build] Install with: apt install xorriso")
            return ""

        iso_path = os.path.join(self.workspace, "superlite-os.iso")

        # Simple ISO generation
        cmd = [
            "xorriso", "-as", "mkisofs",
            "-o", iso_path,
            "-isohybrid-mbr", "/usr/lib/ISOLINUX/isohdpfx.bin",
            "-c", "boot.cat",
            "-b", "boot/grub/stage2",
            "-no-emul-boot",
            "-boot-load-size", "4",
            "-boot-info-table",
            iso_dir,
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if result.returncode == 0:
                return iso_path
            else:
                print(f"[Build] ISO generation failed: {result.stderr}")
                return ""
        except FileNotFoundError:
            print("[Build] xorriso not available")
            return ""


def main():
    parser = argparse.ArgumentParser(description="SuperLite OS Builder")
    parser.add_argument("--target", choices=["iso", "img", "both"], default="iso",
                       help="Build target (default: iso)")
    parser.add_argument("--size", type=int, default=2048,
                       help="Image size in MB (default: 2048)")
    parser.add_argument("--no-drivers", action="store_true",
                       help="Skip driver dump/injection")
    parser.add_argument("--dump-only", action="store_true",
                       help="Only dump drivers, don't build")
    parser.add_argument("--workspace", type=str,
                       help="Build workspace directory")

    args = parser.parse_args()

    if args.dump_only:
        dumper = DriverDump()
        dumper.dump_all()
        return

    builder = SuperLiteBuilder(
        workspace=args.workspace,
        target=args.target,
        image_size_mb=args.size,
        include_drivers=not args.no_drivers,
    )

    builder.build()


if __name__ == "__main__":
    main()
