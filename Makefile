# Nouns Builder Protocol - Safe Treasury V2
# Storage layout and verification utilities

.PHONY: update-storage-layout verify-storage-layout test-upgrade help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

update-storage-layout: ## Update storage layout baseline files
	@echo "Updating storage layout baselines..."
	@forge inspect src/manager/Manager.sol:Manager storage-layout > .storage-layout-manager.txt
	@forge inspect src/governance/treasury/Treasury.sol:Treasury storage-layout > .storage-layout-treasury.txt
	@forge inspect src/governance/governor/Governor.sol:Governor storage-layout > .storage-layout-governor.txt
	@echo "✓ Storage layouts updated"
	@echo ""
	@echo "⚠️  IMPORTANT: Review changes carefully before committing!"
	@echo "   - Ensure new storage slots are APPENDED, not inserted"
	@echo "   - Verify no slot collisions with inherited contracts"
	@echo "   - Test upgrade path on testnet fork"

verify-storage-layout: ## Verify storage layouts match baselines
	@echo "Verifying storage layouts..."
	@forge script script/VerifyStorageLayout.s.sol

test-upgrade: ## Test upgrade path on local fork
	@echo "Testing upgrade path..."
	@echo "TODO: Implement upgrade testing script"

clean: ## Clean build artifacts
	@forge clean
	@rm -rf cache out

build: ## Build contracts
	@forge build

test: ## Run tests
	@forge test -vvv

coverage: ## Generate coverage report
	@forge coverage

snapshot: ## Generate gas snapshot
	@forge snapshot
