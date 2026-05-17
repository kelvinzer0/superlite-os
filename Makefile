.PHONY: help build build-all build-install build-parted docker docker-all docker-install docker-parted setup clean validate push release

TAG     := latest
DATE    := $(shell date +%Y%m%d)
ISO_DIR := output

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Set up Alpine build environment
	./build.sh --setup-only

# ── Desktop ISO (default) ────────────────────────────────────────────────────
build: ## Build desktop ISO (requires Alpine)
	sudo ./build.sh --variant superlite --tag $(TAG)

docker: ## Build desktop ISO inside Docker
	./build.sh --docker --variant superlite --tag $(TAG)

# ── Installation ISO ─────────────────────────────────────────────────────────
build-install: ## Build installation ISO (requires Alpine)
	sudo ./build.sh --variant superlite-install --tag $(TAG)

docker-install: ## Build installation ISO inside Docker
	./build.sh --docker --variant superlite-install --tag $(TAG)

# ── Partition Manager ISO ────────────────────────────────────────────────────
build-parted: ## Build partition manager ISO (requires Alpine)
	sudo ./build.sh --variant superlite-parted --tag $(TAG)

docker-parted: ## Build partition manager ISO inside Docker
	./build.sh --docker --variant superlite-parted --tag $(TAG)

# ── All ISOs ─────────────────────────────────────────────────────────────────
build-all: ## Build all 3 ISOs (requires Alpine)
	sudo ./build.sh --all --tag $(TAG)

docker-all: ## Build all 3 ISOs inside Docker
	./build.sh --docker --all --tag $(TAG)

# ── Utilities ────────────────────────────────────────────────────────────────
clean: ## Remove build artifacts
	rm -rf $(ISO_DIR) *.iso

validate: ## Validate project structure
	bash tests/validate-build.sh

push: ## Push to GitHub
	git add -A && git commit -m "build: $(DATE)" && git push

release: ## Create GitHub release with ISOs
	gh release create "v$(DATE)" $(ISO_DIR)/**/*.iso \
		--title "SuperLite OS $(DATE)" \
		--notes "Alpine Linux + LabWC Wayland Desktop"
