.PHONY: help build build-legacy build-install build-parted docker docker-legacy docker-install docker-parted setup clean validate push release

TAG     := latest
DATE    := $(shell date +%Y%m%d)
ISO_DIR := output

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Set up Alpine build environment
	./build.sh --setup-only

# ── Unified ISO (default) ────────────────────────────────────────────────────
build: ## Build unified ISO — 1 ISO, boot menu (requires Alpine)
	sudo ./build.sh --variant superlite-unified --tag $(TAG)

docker: ## Build unified ISO inside Docker
	./build.sh --docker --variant superlite-unified --tag $(TAG)

# ── Legacy standalone ISOs ───────────────────────────────────────────────────
build-legacy: ## Build desktop-only ISO
	sudo ./build.sh --variant superlite --tag $(TAG)

docker-legacy: ## Build desktop-only ISO in Docker
	./build.sh --docker --variant superlite --tag $(TAG)

build-install: ## Build install-only ISO
	sudo ./build.sh --variant superlite-install --tag $(TAG)

docker-install: ## Build install-only ISO in Docker
	./build.sh --docker --variant superlite-install --tag $(TAG)

build-parted: ## Build partition-manager-only ISO
	sudo ./build.sh --variant superlite-parted --tag $(TAG)

docker-parted: ## Build partition-manager-only ISO in Docker
	./build.sh --docker --variant superlite-parted --tag $(TAG)

# ── Utilities ────────────────────────────────────────────────────────────────
clean: ## Remove build artifacts
	rm -rf $(ISO_DIR) *.iso

validate: ## Validate project structure
	bash tests/validate-build.sh

push: ## Push to GitHub
	git add -A && git commit -m "build: $(DATE)" && git push

release: ## Create GitHub release with ISO
	gh release create "v$(DATE)" $(ISO_DIR)/*.iso \
		--title "SuperLite OS $(DATE)" \
		--notes "Alpine Linux + LabWC Wayland Desktop"
