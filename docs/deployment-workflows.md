# Deployment Workflows

This doc covers the main deployment and maintenance commands in `package.json`.

## Supported Networks

Only these network aliases are supported in this workspace:

- `mainnet` (`1`)
- `sepolia` (`11155111`)
- `optimism` (`10`)
- `optimism_sepolia` (`11155420`)
- `base` (`8453`)
- `base_sepolia` (`84532`)

Deprecated networks `4` and `5` are removed.

## Required Env

Minimum env for deploy commands:

- `NETWORK` (must match one alias above)
- `PRIVATE_KEY`

Additional env for deterministic CREATE2-based deploy commands:

- `DEPLOY_SALT`

`DEPLOY_SALT` is a human-readable string label. The deployment scripts derive the CREATE2 salt with `keccak256(bytes(DEPLOY_SALT))`.

RPC aliases and explorer settings are configured in `foundry.toml` using:

- `[rpc_endpoints]`
- `[etherscan]`

Common env variables used by those sections:

- `MAINNET_RPC_URL`
- `SEPOLIA_RPC_URL`
- `OPTIMISM_RPC_URL`
- `OPTIMISM_SEPOLIA_RPC_URL`
- `BASE_RPC_URL`
- `BASE_SEPOLIA_RPC_URL`
- `ETHERSCAN_API_KEY`
- `OPTIMISTIC_ETHERSCAN_API_KEY`
- `BASESCAN_API_KEY`

## Main Deploy Commands

- `yarn deploy:v3-new`
  - Deploys a full fresh latest core stack (manager proxy + all impls).
  - Also deploys MerkleReserveMinter, ERC721RedeemMinter, and L2MigrationDeployer.
  - Uses CREATE2 salts derived from `DEPLOY_SALT`.
  - Requires `WETH`, `ProtocolRewards`, `BuilderRewardsRecipient`, and `CrossDomainMessenger` in `addresses/<chainid>.json`.
  - Output file: `deploys/<chainid>.version3_new.txt` (includes deploy salt for reference).

- `yarn deploy:v3-upgrade`
  - Deploy only new v3 upgrade impls for existing manager deployments.
  - Deploys: Token, MetadataRenderer, Auction, Treasury, Governor and Manager implementations via CREATE3 factory.
  - Uses CREATE3 salts derived from `DEPLOY_SALT` - same salts as `v3-new` for consistency.
  - Reuses existing implementation addresses from `addresses/<chainid>.json`.
  - Output file: `deploys/<chainid>.version3_upgrade.txt` (includes deploy salt for reference).
  - **IMPORTANT:** The new Manager implementation will have a new `builderRewardsRecipient` immutable value. To change this value, you must deploy a NEW Manager implementation with the desired value and upgrade to it.

- `yarn deploy:erc721-redeem-minter`
  - Deploys ERC721 redeem minter only.
  - Uses CREATE2 salts derived from `DEPLOY_SALT`.
  - Output file: `deploys/<chainid>.erc721_redeem_minter.txt`.

- `yarn deploy:dao`
  - Runs `DeployNewDAO.s.sol` deterministic DAO deployment flow.
  - Requires `DEPLOY_SALT`.
  - **Uses Manager's immutable implementation addresses** (`manager.tokenImpl()`, `manager.auctionImpl()`, etc.) to build `ImplementationParams`.
  - **For cross-chain identical DAO addresses:** Manager implementations must be at the same addresses on all chains, OR you must call `Manager.deployDeterministic()` directly with explicit matching `ImplementationParams`.
  - Prints the predicted token, metadata, auction, treasury, and governor addresses before broadcast.
  - Deterministic addresses depend on: deployer address, `DEPLOY_SALT`, and the implementation addresses (from Manager immutables or explicit params).
  - Legacy `Manager.deploy(...)` remains for backward compatibility, but new integrations should use deterministic deploy.
  - Intended for controlled deployment/testing flows.

## Cross-Chain Deterministic Deployments

### Overview

The Manager contract uses **DAOFactory** as a canonical deployer to enable **cross-chain deterministic DAO deployments**. DAOFactory is deployed via CREATE3 at a deterministic address on all chains, which then uses CREATE2 to deploy DAO proxies. This architecture enables DAOs to have identical addresses across multiple chains, even when Manager proxies are deployed at different addresses on each chain.

**Key Components:**

- **DAOFactory**: Canonical factory contract deployed via CREATE3 (bytecode-independent determinism)
  - Salt: `keccak256("NOUNS_BUILDER_DAO_FACTORY_V1")`
  - Deterministic address across all chains despite being bound to chain-specific Manager addresses
- **Manager**: References DAOFactory as an immutable for DAO deployments
  - Each Manager implementation is bound to a specific DAOFactory instance
  - DAOFactory address is set at Manager construction time

### How It Works

DAO addresses are calculated using the CREATE2 formula where DAOFactory acts as the deployer:

```
address = keccak256(0xff ++ DAO_FACTORY_ADDRESS ++ salt ++ keccak256(proxyCreationCode))
```

Where:

- `DAO_FACTORY_ADDRESS` = Address of DAOFactory contract (deterministic via CREATE3, same on all chains)
- `salt` = `keccak256(deployerWallet ++ DEPLOY_SALT ++ contractLabel)`
  - `deployerWallet`: The EOA/contract calling `Manager.deployDeterministic()`
  - `DEPLOY_SALT`: User-provided salt for namespacing
  - `contractLabel`: Contract-specific identifier ("TOKEN", "METADATA", etc.)
- `proxyCreationCode` = ERC1967Proxy bytecode + implementation address

**Deployment Flow:**

1. Manager validates implementations and DAOFactory exists
2. Manager calls `DAOFactory.deploy(salt, proxyCreationCode)` for each contract
3. DAOFactory uses CREATE2 to deploy ERC1967Proxy at deterministic address
4. DAOFactory validates deployment succeeded and returns proxy address
5. Manager initializes each proxy with DAO-specific parameters

### Requirements for Cross-Chain DAO Determinism

To achieve identical DAO addresses across chains when using `deployDeterministic()`, you must use:

1. **Same deployer address** (user wallet) on all chains
2. **Same `deploySalt`** value passed to `deployDeterministic()`
3. **Same implementation addresses** in `ImplementationParams` (Token, Metadata, Auction, Treasury, Governor)
4. **Same proxy bytecode** (ERC1967Proxy from the same compiler version)

**Important Notes:**

- **Manager proxy addresses CAN be different** on each chain without affecting DAO address determinism
- **Manager implementation addresses ARE NOW IDENTICAL** across chains (as of V3 with CREATE3)
- Previously (V2): Implementation addresses differed due to chain-specific constructor parameters
- Now (V3): CREATE3 ensures identical implementation addresses regardless of constructor differences
- The salt calculation uses the **deployer's wallet address**, NOT the Manager contract address
- DAO addresses depend on the `ImplementationParams` passed to `deployDeterministic()`, NOT the Manager's immutable implementation addresses

**IMPORTANT - What IS and IS NOT Deterministic:**

The system uses **CREATE3 factory** (`0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`) for bytecode-independent deterministic deployments. CREATE3 enables identical addresses across chains even when constructor arguments differ.

**CREATE3 vs CREATE2:**

- **CREATE2**: Address depends on bytecode → different constructor args = different addresses
- **CREATE3**: Address depends only on salt and deployer → same address regardless of bytecode differences

**✅ Fully Deterministic Across Chains (as of V3 with CREATE3):**

- **Manager proxy** (via CREATE2 with all-zero bootstrap implementation and atomic initialization)
- **All implementations** (via CREATE3):
  - Token implementation
  - MetadataRenderer implementation
  - MerklePropertyIPFS implementation
  - Auction implementation
  - Treasury implementation
  - Governor implementation
  - Manager implementation
- **All minters** (via CREATE3):
  - MerkleReserveMinter
  - ERC721RedeemMinter

**Important:** Even though these contracts have chain-specific constructor parameters (e.g., `protocolRewards`, `builderRewardsRecipient`), CREATE3 ensures they deploy to **identical addresses** on all chains when using the same `DEPLOY_SALT`.

**Manager Implementation Design:** The Manager implementation has `builderRewardsRecipient` as an immutable constructor parameter. To use different Builder Rewards recipients on different chains while maintaining CREATE3 determinism, the deployment script deploys Manager implementations with chain-specific `builderRewardsRecipient` values. These implementations will have identical addresses across chains thanks to CREATE3, but will have different immutable values. WETH is NOT stored in Manager - it is only used by Auction implementations.

**✅ Deterministic Across Chains:**

- **DAO contracts** (Token, Metadata, Auction proxy, Treasury, Governor) when deployed via `Manager.deployDeterministic()` with same:
  - Deployer wallet address
  - `deploySalt` parameter
  - `ImplementationParams` (explicit implementation addresses)

**Why DAO Determinism Works Despite Manager Differences:**
The salt calculation for DAO contracts is:

```
salt = keccak256(deployerWalletAddress ++ deploySalt ++ contractLabel)
```

**Manager address is NOT included**. This means:

- Manager A on Chain 1 and Manager B on Chain 2 can be at different addresses
- Manager implementations ARE NOW IDENTICAL across chains (as of V3 with CREATE3)
- DAOs will deploy to **identical addresses** if same user + same deploySalt + same ImplementationParams
- **V3 Advantage**: Using `yarn deploy:dao` with Manager's immutable implementation addresses now produces identical DAO addresses because implementations are identical across chains

### Fund Recovery Use Case

A key benefit of cross-chain DAO determinism is fund recovery:

**Scenario:**

1. DAO "CoolDAO" is deployed on Mainnet with Treasury at address `0x1234...`
2. User accidentally sends 10 ETH to `0x1234...` on Base (where CoolDAO doesn't exist yet)
3. Funds are locked at an address with no contract

**Solution:**

1. Original DAO deployer calls `Manager.deployDeterministic()` on Base
2. Uses the **same wallet**, **same `deploySalt`**, and **same `ImplementationParams`** as the Mainnet deployment
3. Treasury deploys to `0x1234...` on Base (same address as Mainnet)
4. The 10 ETH is now controlled by the Treasury contract
5. Governance can vote to recover the funds

**Security:**

- The salt includes the **original deployer's wallet address**, preventing anyone else from deploying to the predicted address
- Even if an attacker predicts the address, they cannot deploy there unless they control the original deployer's wallet
- Manager addresses can be different on each chain without affecting security

**Important:** This works regardless of whether:

- Manager proxies are at different addresses on Mainnet vs Base
- The Manager was upgraded since the original DAO deployment

The only requirements are: same deployer wallet + same deploySalt + same ImplementationParams.

**V3 Simplification**: With CREATE3, Manager implementations are now identical across all chains, so using `yarn deploy:dao` (which uses Manager's immutable implementation addresses) automatically provides the correct matching ImplementationParams.

### Deterministic Deployment Factories

**CREATE2 Factory** (`0x4e59b44847b379578588920cA78FbF26c0B4956C`):

- Used for: Manager proxy, DAO proxies (via DAOFactory)
- Address formula: `keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))`
- Limitation: Address depends on bytecode (different constructor args = different addresses)

**CREATE3 Factory** (`0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`):

- Used for: All implementations, DAOFactory, minters, migration deployer
- Address formula: Two-step process where final address = `f(salt, deployer)`, independent of bytecode
- Advantage: Same address even when constructor args differ across chains

**DAOFactory** (deployed via CREATE3 with salt `keccak256("NOUNS_BUILDER_DAO_FACTORY_V1")`):

- Purpose: Canonical deployer for DAO proxy contracts
- Why it exists: Enables cross-chain DAO determinism despite different Manager addresses
- Architecture: Each Manager implementation references its own DAOFactory instance as an immutable
- Security: DAOFactory constructor validates that `msg.sender == manager` to ensure correct binding
- Deployment: DAOFactory is deployed via CREATE3, making its address deterministic across all chains
- Usage: Manager calls `daoFactory.deploy(salt, creationCode)` which internally uses CREATE2 factory

Both factories are deployed on all supported networks:

- Ethereum Mainnet (1)
- Sepolia (11155111)
- Optimism (10)
- Optimism Sepolia (11155420)
- Base (8453)
- Base Sepolia (84532)

The Manager constructor validates that CREATE2 factory exists on deployment. If deploying to a new chain where either factory is not present, it must be deployed first.

### Example Workflows

**Scenario 1: Cross-Chain DAO Deployment (Direct API Call - Recommended)**

For guaranteed identical DAO addresses across chains when Manager implementations differ:

```solidity
// Deploy on Mainnet
IManager.ImplementationParams memory params = IManager.ImplementationParams({
    token: 0x1111...,      // Same implementation address on all chains
    metadataRenderer: 0x2222...,
    auction: 0x3333...,
    treasury: 0x4444...,
    governor: 0x5555...
});
manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt, params);

// Deploy on Optimism - SAME params, different Manager address is OK
manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt, params);
```

**Result:** Identical DAO addresses on both chains regardless of Manager differences.

**Scenario 2: Using `yarn deploy:dao` Script (V3 - Fully Deterministic)**

This script uses Manager's immutable implementation addresses. In V3, all implementations are fully deterministic:

```bash
# Step 1: Deploy infrastructure with same DEPLOY_SALT on both chains
NETWORK=mainnet PRIVATE_KEY=<key> DEPLOY_SALT=my_protocol_v1 yarn deploy:v3-new
NETWORK=optimism PRIVATE_KEY=<key> DEPLOY_SALT=my_protocol_v1 yarn deploy:v3-new

# Step 2: Deploy DAOs with same DEPLOY_SALT - produces identical DAO addresses
NETWORK=mainnet PRIVATE_KEY=<key> DEPLOY_SALT=my_dao_v1 yarn deploy:dao
NETWORK=optimism PRIVATE_KEY=<key> DEPLOY_SALT=my_dao_v1 yarn deploy:dao
```

**Result (V3):** ✅ All DAO addresses will be identical across chains because:

- Manager implementations are at same addresses (builderRewardsRecipient as immutable, different values per chain but same address via CREATE3)
- Auction implementations are at same addresses (WETH as immutable, reads builderRewardsRecipient from Manager)
- Same deployer + same DEPLOY_SALT = same DAO addresses

**Scenario 3: Fresh Infrastructure Deployment (V3 - Fully Deterministic)**

```bash
# Deploy Manager and implementations on both chains with same DEPLOY_SALT
NETWORK=mainnet PRIVATE_KEY=<key> DEPLOY_SALT=my_protocol_v1 yarn deploy:v3-new
NETWORK=optimism PRIVATE_KEY=<key> DEPLOY_SALT=my_protocol_v1 yarn deploy:v3-new
```

**Result (as of V3):**

- ✅ Manager proxy at same address (same DEPLOY_SALT + deployer, CREATE2 with all-zero bootstrap impl)
- ✅ **All implementations at IDENTICAL addresses** (builderRewardsRecipient as immutable in Manager, WETH as immutable in Auction)
- ✅ Using `yarn deploy:dao` with same DEPLOY_SALT will produce **identical DAO addresses**

**How V3 Achieves Full Determinism:**

- **Manager proxy** deployed via CREATE2 with all-zero bootstrap implementation and atomic initialization
- **Manager proxy initialization** included in proxy constructor data (`abi.encodeWithSignature("initialize(address)", owner)`)
- **Security**: Atomic initialization prevents front-running attacks where attacker could call `initialize()` before deployer
- **All implementations deployed via CREATE3** (bytecode-independent address calculation)
- **CREATE3 factory** at `0xD252d074EEe65b64433a5a6f30Ab67569362E7e0` enables same addresses even when constructor args differ per chain
- **How CREATE3 works**: Two-step process (CREATE2 proxy + CREATE from proxy) where final address = f(salt, deployer), NOT f(bytecode)
- **builderRewardsRecipient** is an immutable in Manager implementation (changeable only by upgrading to new Manager impl)
- **WETH** is an immutable in Auction implementation (NOT stored in Manager)
- **Result**: Identical implementation addresses across all chains regardless of chain-specific parameters like `protocolRewards`, `crossDomainMessenger`, `weth`, `builderRewardsRecipient`, etc.

## Ownership and Address Maintenance

- `yarn addresses:check-manager-owner`
  - Reads live `Manager.owner()` on supported networks.
  - Compares against `ManagerOwner` in `addresses/*.json`.
  - Non-zero exit when drift exists.

- `yarn addresses:sync-manager-owner`
  - Same as check, but writes updates to `addresses/*.json`.

- `yarn addresses:check-builder-rewards`
  - Reads live `manager.builderRewardsRecipient()` where available.
  - Compares against `BuilderRewardsRecipient` in `addresses/*.json`.
  - Prints current Auction `builderRewardsBPS/referralRewardsBPS` for each network when callable.

- `yarn addresses:sync-builder-rewards`
  - Same as check, but writes `BuilderRewardsRecipient` updates when on-chain value is available.

- `yarn upgrade:check-status`
  - Prints manager owner/latest implementation/version status.
  - Checks registered upgrades against known legacy base impls (mainnet matrix).
  - Uses upgrade targets from `addresses/<chainid>.json`.
  - Select network via `NETWORK` (defaults to `mainnet`).

Optional scoped run:

```bash
node script/updateManagerOwner.mjs --write --chain-ids 1,8453
```

```bash
node script/checkBuilderRewardsConfig.mjs --write --chain-ids 1,8453
```

## Address Book Update Policy

Current policy in this repo:

- Scripts use `block.chainid` to resolve `addresses/<chainid>.json` and write outputs to `deploys/<chainid>.*.txt`.
- Contract address fields in `addresses/<chainid>.json` are updated manually from deployment output files.
- The single automatic sync is `ManagerOwner` via `script/updateManagerOwner.mjs`.
- `BuilderRewardsRecipient` is operator-managed; `script/checkBuilderRewardsConfig.mjs` provides check/sync utilities when the on-chain getter is available.

Recommended post-deploy sequence:

1. Run deploy command and capture generated `deploys/*.txt` output.
2. Manually update `addresses/<chainid>.json` contract address fields.
3. Run `yarn addresses:sync-manager-owner` and `yarn addresses:sync-builder-rewards`.
4. Commit `deploys/*` and `addresses/*` changes together.

## Example Upgrade Flows

### Upgrading to V3 Manager (From V2 or Earlier)

When upgrading an existing Manager deployment to V3:

```bash
# Step 1: Deploy new V3 implementations
source .env
export NETWORK=mainnet
yarn deploy:v3-upgrade

# Step 2: Upgrade the Manager proxy to the new implementation
# (Use your preferred governance/multisig tool to call manager.upgradeTo(newManagerImpl))

# Step 3: Verify the new implementation's builderRewardsRecipient
cast call $MANAGER_PROXY "builderRewardsRecipient()(address)"
```

**Note:** The new Manager implementation has `builderRewardsRecipient` as an immutable constructor parameter set during deployment. To use a different value, deploy a new Manager implementation with the desired value and upgrade to it.

For additional upgrade procedures, see:

- `docs/upgrade-runbook.md`
- `docs/manager-ownership-runbook.md`
