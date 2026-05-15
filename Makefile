.PHONY: help setup build clean validate iso push upload

MACHINE  := superlite-x86_64
DISTRO   := superlite
IMAGE    := superlite-os-image
DATE     := $(shell date +%Y%m%d)
ISO_NAME := superlite-os-$(DATE).iso

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Set up Yocto build environment (Poky + layers)
	./build.sh --setup-only

build: ## Full build: Yocto image + ISO
	sudo ./build.sh --verbose

build-image: ## Build Yocto image only (no ISO)
	cd build && source poky/oe-init-build-env build && bitbake $(IMAGE)

iso: ## Build ISO from existing Yocto image
	bash meta-superlite/recipes-apps/superlite-live/superlite-live/superlite-boot.sh \
		--build-dir build --output $(ISO_NAME)

clean: ## Remove build artifacts
	rm -rf build/tmp* build/sstate-cache build/cache *.iso

clean-all: ## Remove entire build directory (including Poky)
	rm -rf build *.iso

validate: ## Validate build output
	bash tests/validate-build.sh

push: ## Push to GitHub
	git add -A && git commit -m "build: $(DATE)" && git push

upload: ## Create GitHub release with ISO
	gh release create "v$(DATE)" $(ISO_NAME) \
		--title "SuperLite OS $(DATE)" \
		--notes "Yocto-built Alpine Linux + LabWC Wayland Desktop"

bitbake: ## Run arbitrary bitbake command (usage: make bitbake ARGS="core-image-minimal")
	cd build && source poky/oe-init-build-env build && bitbake $(ARGS)

shell: ## Open devshell in Yocto build environment
	cd build && source poky/oe-init-build-env build && exec bash
