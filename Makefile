.PHONY: build clean test-qemu help

ISO_NAME := $(shell date +%Y%m%d)
BUILD_DIR := build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the SuperLite OS ISO
	sudo ./build.sh --verbose

build-noefi: ## Build Legacy BIOS only
	sudo ./build.sh --no-efi --verbose

clean: ## Remove build artifacts
	sudo rm -rf $(BUILD_DIR) *.iso

test-qemu: ## Test ISO in QEMU
	qemu-system-x86_64 -m 2048 -cdrom superlite-os-*.iso -boot d -vga virtio

test-qemu-efi: ## Test UEFI boot in QEMU
	qemu-system-x86_64 -m 2048 \
		-bios /usr/share/OVMF/OVMF_CODE.fd \
		-cdrom superlite-os-*.iso -boot d -vga virtio

test-ventoy: ## Test with Ventoy (create a disk image first)
	qemu-img create -f qcow2 /tmp/ventoy-test.qcow2 4G
	qemu-system-x86_64 -m 2048 \
		-drive file=/tmp/ventoy-test.qcow2,format=qcow2 \
		-cdrom superlite-os-*.iso -boot d -vga virtio

push: ## Push to GitHub
	git add -A && git commit -m "build: $(ISO_NAME)" && git push

upload: ## Create GitHub release with ISO
	gh release create "v$(ISO_NAME)" superlite-os-*.iso \
		--title "SuperLite OS $(ISO_NAME)" \
		--notes "Alpine Linux + LabWC Wayland Desktop"
