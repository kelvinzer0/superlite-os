.PHONY: build clean push upload help

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

push: ## Push to GitHub
	git add -A && git commit -m "build: $(ISO_NAME)" && git push

upload: ## Create GitHub release with ISO
	gh release create "v$(ISO_NAME)" superlite-os-*.iso \
		--title "SuperLite OS $(ISO_NAME)" \
		--notes "Alpine Linux + LabWC Wayland Desktop"
