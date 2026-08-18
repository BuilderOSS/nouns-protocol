# ⌐◨-◨

# Nouns Builder Protocol V3

**Nouns Builder** is a protocol for creating and managing Nouns-style DAOs with on-chain governance, token auctions, and treasury management.

Version 3 introduces updatable proposals, signed proposal sponsorship, deterministic cross-chain deployments, and enhanced governance features.

## Overview

Nouns Builder enables the creation of builder DAOs with:

- **Generative NFT Tokens**: ERC-721 governance tokens with customizable on-chain metadata
- **English Auctions**: Continuous daily auctions for token distribution
- **DAO Governance**: Upgradeable Governor contracts with proposal lifecycle management
- **Treasury Management**: Timelock-controlled treasury for executing passed proposals
- **Metadata Rendering**: Flexible on-chain and off-chain metadata support
- **Minter Extensions**: Pluggable minting strategies (merkle claims, ERC-721 redemption)

## Architecture

### Core Contracts

- **Manager** (`src/manager/`): Factory contract for deploying and upgrading DAOs
  - Deploys Token, Auction, Governor, Treasury, and MetadataRenderer
  - Manages upgrade paths and version registration
  - Supports deterministic CREATE3 deployments via DAOFactory

- **Token** (`src/token/`): ERC-721 governance token with voting power
  - Generative on-chain properties and metadata
  - Vote delegation and historical vote tracking
  - Flexible founder allocation with vesting

- **Auction** (`src/auction/`): English auction house for token distribution
  - Daily token auctions with configurable duration and reserve price
  - Optional builder rewards
  - Pausable with upgrade support

- **Governor** (`src/governance/governor/`): On-chain governance with updatable proposals
  - Proposal creation with signatures (ERC-1271 compatible)
  - Updatable proposal lifecycle: `Updatable → Pending → Active → Succeeded/Defeated`
  - Configurable voting parameters (delay, period, threshold, quorum)
  - Vote delegation and signature-based voting

- **Treasury** (`src/governance/treasury/`): Timelock-controlled treasury
  - Queues and executes proposals after delay
  - ETH and token management
  - Veto support

- **MetadataRenderer** (`src/token/metadata/`): On-chain metadata generation
  - Layer-based generative artwork
  - IPFS support for off-chain storage
  - Customizable traits and properties

### Deployment Infrastructure

- **Deployers** (`src/deployers/`): L2 migration deployer for cross-chain DAO setup via OP Stack messaging
- **Factory** (`src/factory/`): Canonical CREATE3-based factory for deterministic cross-chain DAO deployments

### Extensions

- **Minters** (`src/minters/`):
  - Merkle-based allowlist minting
  - ERC-721 token redemption

## V3 Features

### Updatable Proposals

Proposals can be edited during a configurable update window before voting begins:

- **Updatable Period**: Configurable window (0-24 weeks, default: 1 day) after proposal creation
- **Update Methods**:
  - `updateProposal()`: For unsigned proposals or proposers who met threshold independently
  - `updateProposalBySigs()`: For signed proposals with fresh signer set
- **Identity Management**: Proposal updates create new IDs with replacement tracking

### Signed Proposals

Multiple signers can sponsor proposals together:

- **ERC-1271 Compatible**: Supports both EOA and smart contract signatures
- **Flexible Sponsorship**: Up to 16 signers, combined threshold validation
- **Nonce-based Replay Protection**: Per-signer nonces with deadline expiry

### Deterministic Deployments

Cross-chain deployment support with CREATE3:

- **Manager.deployDeterministic()**: Deploy DAOs with predictable addresses across chains
- **DAOFactory**: Canonical CREATE3 factory ensures consistent DAO addresses regardless of Manager address
- **L2 Migration**: Deploy and seed DAOs on OP Stack L2s via cross-domain messaging
- **Migration Support**: Legacy `deploy()` remains for backward compatibility

### Enhanced Governance

- **Configurable Update Period**: Set `proposalUpdatablePeriod` during DAO deployment
- **Vote Signature Updates**: Unified `bytes signature` API with nonce management
- **Proposal Lifecycle Helpers**: Query replacement chains and signer sets
- **EAS Integration**: Off-chain proposal candidates via Ethereum Attestation Service

## Installation

```bash
# Clone the repository
git clone https://github.com/BuilderOSS/nouns-protocol.git
cd nouns-protocol

# Install dependencies
yarn install

# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Development

### Build

```bash
yarn build
```

### Test

```bash
# Run all tests
yarn test

# Run unit tests only
yarn test:unit

# Run fork tests only
yarn test:fork

# Generate coverage report
yarn test:coverage
```

### Format & Lint

```bash
# Format code
yarn format

# Check formatting and run linters
yarn lint
```

### Storage Layout Verification

```bash
# Check storage layout (ensures no collisions during upgrades)
yarn storage-inspect:check

# Generate storage layout snapshots
yarn storage-inspect:generate
```

## Deployment

### Environment Setup

Create a `.env` file (see `.env.example`):

```bash
NETWORK=mainnet
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_key
DEPLOY_SALT=your_deployment_salt
```

### Deploy a New DAO

```bash
yarn deploy:dao
```

Governance parameters are configured via `GovParams` in the deployment script:

- `timelockDelay`: Time delay to execute queued transactions (default: 2 days)
- `votingDelay`: Time delay before voting starts (default: 2 days)
- `votingPeriod`: Duration of voting period (default: 2 days)
- `proposalThresholdBps`: Basis points of supply required to create proposals (default: 50 = 0.5%)
- `quorumThresholdBps`: Basis points of supply required for quorum (default: 1000 = 10%)
- `vetoer`: Address authorized to veto proposals (default: address(0) = no vetoer)
- `proposalUpdatablePeriod`: Time proposals are editable after creation (default: 1 day, range: 0-24 weeks)

### Deploy V3 Implementations

```bash
# Deploy new V3 implementations for existing Manager
yarn prepare:v3-upgrade

# Deploy new V3 Manager and implementations
yarn deploy:v3-new
```

### Upgrade Existing DAOs

See the [Upgrade Runbook](./docs/upgrade-runbook.md) for detailed upgrade procedures.

## Documentation

Comprehensive documentation is available in the [`docs/`](./docs) directory:

### Deployment & Operations

- [Deployment Workflows](./docs/deployment-workflows.md): Command reference, network configuration, and deployment patterns
- [Upgrade Runbook](./docs/upgrade-runbook.md): Step-by-step upgrade procedures for implementations and DAOs
- [Manager Ownership Runbook](./docs/manager-ownership-runbook.md): Manager ownership transfer and verification

### Governor & Proposals

- [Governor Architecture](./docs/governor-architecture.md): Design overview of updatable proposals and signature flows
- [Governor Proposal Lifecycle](./docs/governor-proposal-lifecycle.md): Detailed state machine and lifecycle reference
- [EAS Proposal Candidates Schema](./docs/eas-proposal-candidates-schema.md): Off-chain proposal candidate attestations

### Audit & Security

- [V3 Audit Readiness](./docs/v3-audit-readiness.md): Comprehensive audit checklist and security review
- [Internal Security Audit](./docs/internal-security-audit.md): Internal audit findings and resolutions

## Testing

The protocol includes comprehensive test coverage:

- **630 Unit Tests**: Core functionality and edge cases
- **39 Fork Tests**: Integration tests against live networks
- **Coverage**: Critical paths and upgrade scenarios

```bash
# Run all tests with verbose output
forge test -vvv

# Run specific test file
forge test --match-path test/Gov.t.sol -vvv

# Run specific test function
forge test --match-test testPropose -vvv
```

## Security

### Audits

- Internal security audit completed with 100% finding implementation rate
- See [Internal Security Audit](./docs/internal-security-audit.md) for details

### Bug Bounty

Report security vulnerabilities responsibly. Contact details TBD.

### Upgrades

All core contracts are upgradeable via UUPS proxy pattern:

- Upgrade authorization requires Manager registration
- Storage layout preservation enforced via testing
- Version tracking via `VersionedContract` base

## Addresses

Contract addresses for deployed instances are tracked in `addresses/*.json`:

- Network-specific deployment manifests
- Manager ownership and configuration
- Builder rewards recipient tracking

Use helper scripts to verify configuration:

```bash
# Check Manager ownership across chains
yarn addresses:check-manager-owner

# Verify builder rewards configuration
yarn addresses:check-builder-rewards

# Check upgrade status for deployed DAOs
yarn upgrade:check-status
```

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass: `yarn test`
2. Code is formatted: `yarn format`
3. Linting passes: `yarn lint`
4. Storage layouts are verified: `yarn storage-inspect:check`

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Resources

- **GitHub**: [BuilderOSS/nouns-protocol](https://github.com/BuilderOSS/nouns-protocol)
- **Package**: [@buildeross/nouns-protocol](https://www.npmjs.com/package/@buildeross/nouns-protocol)
- **Nouns Builder**: [nouns.build](https://nouns.build)

---

Built with ⌐◨-◨ by the Nouns Builder community
