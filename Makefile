# =============================================================================
# Makefile — Universal build entry point
# Works from: WSL, macOS, Linux, Windows (Git Bash or WSL)
#
# Usage:
#   make release VERSION=1.2.3           # build all platforms + publish release
#   make release VERSION=1.2.3 PLATFORMS=macos-only
#   make release VERSION=1.2.3 PLATFORMS=windows-only
#   make release VERSION=1.2.3 PLATFORMS=linux-only
#   make release VERSION=1.2.3 PUBLISH=false   # build but don't publish
#
#   make build-local   # build for the current machine only (no CI)
#   make dev           # start Vite dev server (frontend only)
#   make check         # TypeScript check + bash script syntax
#   make install-deps  # install frontend npm deps
# =============================================================================

VERSION   ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | awk -F. '{print $$1"."$$2"."$$3+1}')
PLATFORMS ?= all
PUBLISH   ?= true
APP_DIR   := dev-setup-app

# Detect OS for local build command
UNAME := $(shell uname -s 2>/dev/null || echo Windows)

.PHONY: release build-local dev check install-deps clean help

# ─── Default target ──────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Dev Setup App — Build System"
	@echo ""
	@echo "  ┌─ Cloud builds (any machine → all platforms) ──────────────────┐"
	@echo "  │  make release VERSION=1.2.3                                   │"
	@echo "  │  make release VERSION=1.2.3 PLATFORMS=macos-only              │"
	@echo "  │  make release VERSION=1.2.3 PLATFORMS=windows-only            │"
	@echo "  │  make release VERSION=1.2.3 PLATFORMS=linux-only              │"
	@echo "  │  make release VERSION=1.2.3 PUBLISH=false  (build, no release)│"
	@echo "  └───────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  ┌─ Local builds (current machine only) ─────────────────────────┐"
	@echo "  │  make build-local                                              │"
	@echo "  └───────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  ┌─ Development ──────────────────────────────────────────────────┐"
	@echo "  │  make dev          Start frontend dev server                  │"
	@echo "  │  make check        TypeScript + bash syntax check             │"
	@echo "  │  make install-deps Install npm dependencies                   │"
	@echo "  └───────────────────────────────────────────────────────────────┘"
	@echo ""

# ─── Cloud release (works from anywhere) ─────────────────────────────────────
release:
	@echo "  Triggering cross-platform build for v$(VERSION) ($(PLATFORMS))..."
	@bash $(APP_DIR)/scripts/build/release.sh $(VERSION) $(PLATFORMS) \
		$(if $(filter false,$(PUBLISH)),--no-release,)

# ─── Local build (current machine only) ──────────────────────────────────────
build-local:
ifeq ($(UNAME),Darwin)
	@echo "  Building for macOS..."
	@bash $(APP_DIR)/scripts/build/build-mac.sh
else ifeq ($(UNAME),Linux)
	@echo "  Building for Linux (WSL/Ubuntu)..."
	@bash $(APP_DIR)/scripts/build/build-wsl.sh
else
	@echo "  Building for Windows..."
	@powershell -ExecutionPolicy Bypass -File $(APP_DIR)/scripts/build/build-windows.ps1
endif

# ─── Frontend dev server ──────────────────────────────────────────────────────
dev:
	@cd $(APP_DIR) && npm run dev

# ─── Checks ──────────────────────────────────────────────────────────────────
check:
	@echo "  Running TypeScript check..."
	@cd $(APP_DIR) && npx tsc --noEmit
	@echo "  ✓ TypeScript: no errors"
	@echo "  Running bash script syntax check..."
	@for f in $(APP_DIR)/scripts/macos/*.sh $(APP_DIR)/scripts/build/*.sh; do \
		bash -n "$$f" && echo "  ✓ $$f" || echo "  ✗ $$f"; \
	done

# ─── Install deps ────────────────────────────────────────────────────────────
install-deps:
	@cd $(APP_DIR) && npm ci

# ─── Clean ───────────────────────────────────────────────────────────────────
clean:
	@rm -rf $(APP_DIR)/dist $(APP_DIR)/src-tauri/target
	@echo "  ✓ Cleaned dist and Rust target"
