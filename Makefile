.DEFAULT_GOAL := help

TIMEOUT_CMD := $(shell command -v timeout >/dev/null 2>&1 && echo "timeout 90s" || echo "")

.PHONY: help lint lint-strict smoke smoke-selftest ci lint-tools

HZ_SMOKE_STRICT ?= 0

help: ## Show available targets
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_\-]+:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint-tools:
	@missing=0; \
	for tool in shellcheck shfmt; do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Hint: $$tool not found. CI installs tools via .github/scripts/install_ci_tools.sh"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -eq 1 ]; then \
		echo ""; \
	fi

lint: ## Run CI-aligned non-strict lint checks
	@$(MAKE) --no-print-directory lint-tools
	@bash scripts/lint.sh

lint-strict: ## Run strict lint checks (CI-like tooling required)
	@$(MAKE) --no-print-directory lint-tools
	@bash scripts/lint.sh --strict

smoke: ## Run the CI-safe smoke test entrypoint
	@HZ_CI_SMOKE=1 HZ_SMOKE_STRICT=$(HZ_SMOKE_STRICT) $(TIMEOUT_CMD) bash tests/smoke.sh

smoke-selftest: ## Run smoke self-test mode
	@HZ_SMOKE_SELFTEST=1 bash tests/smoke.sh

ci: ## Run lint-strict and smoke (fail fast)
	@$(MAKE) --no-print-directory lint-strict
	@$(MAKE) --no-print-directory smoke
