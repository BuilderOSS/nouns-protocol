# Default values
network ?= holesky
deployerAccountName := $(shell grep '^DEPLOYER_ACCOUNT_NAME=' .env | cut -d '=' -f2)
deployerAddress := $(shell grep '^DEPLOYER_ADDRESS=' .env | cut -d '=' -f2)
export NETWORK=${network}

# Validate network parameter against supported networks
define validate_network
	@if [ -z "${network}" ]; then echo "Error: network is required"; exit 1; fi
	@case "${network}" in mainnet|sepolia|base|base_sepolia|optimism|optimism_sepolia) ;; *) echo "Error: network must be one of: mainnet, sepolia, base, base_sepolia, optimism, optimism_sepolia"; exit 1;; esac
endef

# Default target
.PHONY: all
all: clean install build

# Clean the cache and output directories
.PHONY: clean
clean:
	rm -rf cache out

# Install dependencies using forge
.PHONY: install
install:
	forge install

# Build the project using forge
.PHONY: build
build:
	forge build

# Compile the project using forge
.PHONY: compile
compile:
	forge compile

# Format the Solidity files using forge fmt
.PHONY: fmt
fmt:
	forge fmt --root .

# make simulate network=holesky
.PHONY: simulate
simulate:
	$(validate_network)
	@if [ -z "${deployerAccountName}" ]; then echo "Error: deployerAccountName is required"; exit 1; fi
	@if [ -z "${deployerAddress}" ]; then echo "Error: deployerAddress is required"; exit 1; fi
	forge script Deploy --rpc-url "${network}" --account "${deployerAccountName}" --sender "${deployerAddress}" 
# make deploy network=holesky
.PHONY: deploy
deploy:
	$(validate_network)
	@if [ -z "${deployerAccountName}" ]; then echo "Error: deployerAccountName is required"; exit 1; fi
	@if [ -z "${deployerAddress}" ]; then echo "Error: deployerAddress is required"; exit 1; fi
	forge script Deploy --rpc-url "${network}" --account "${deployerAccountName}" --sender "${deployerAddress}" --broadcast --verify

# make deploy-with-key network=holesky
# Deploys using PRIVATE_KEY from .env instead of an imported Foundry keystore account.
# The resulting CREATE3Factory address is independent of which key you use (see README),
# so anyone can run this with their own funded wallet.
.PHONY: deploy-with-key
deploy-with-key:
	$(validate_network)
	@set -a && . ./.env && set +a && \
	if [ -z "$$PRIVATE_KEY" ]; then echo "Error: PRIVATE_KEY is required in .env"; exit 1; fi && \
	forge script Deploy --rpc-url "${network}" --private-key "$$PRIVATE_KEY" --broadcast --verify

# make predict network=holesky
# Simulates the deployment without broadcasting or spending gas, so anyone can
# confirm the CREATE3Factory address before deploying for real.
.PHONY: predict
predict:
	$(validate_network)
	forge script Deploy --rpc-url "${network}"
