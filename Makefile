.PHONY: help build docker setup clean validate push release

TAG     := latest
DATE    := $(shell date +%Y%m%d)
ISO_DIR := output

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Set up Alpine build environment
	./build.sh --setup-only

build: ## Build ISO natively (requires Alpine)
	sudo ./build.sh --tag $(TAG)

docker: ## Build ISO inside Docker (recommended)
	./build.sh --docker --tag $(TAG)

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
