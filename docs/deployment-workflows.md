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

- `yarn prepare:v3-upgrade`
  - Prepares new v3 upgrade artifacts for existing manager deployments. It does not execute the upgrade.
  - Deploys: Token, MetadataRenderer, Auction, Treasury, Governor and Manager implementations via CREATE3 factory.
  - Uses CREATE3 salts derived from `DEPLOY_SALT` - same salts as `v3-new` for consistency.
  - Reuses existing implementation addresses from `addresses/<chainid>.json`.
  - Output file: `deploys/<chainid>.version3_prepare_upgrade.txt` (includes deploy salt and explicitly records `Upgrade Executed: false`).
  - **IMPORTANT:** The new Manager implementation will have a new `builderRewardsRecipient` immutable value. To change this value, you must deploy a NEW Manager implementation with the desired value and upgrade to it.

- `yarn deploy:erc721-redeem-minter`
  - Deploys ERC721 redeem minter only.
  - Uses CREATE2 salts derived from `DEPLOY_SALT`.
  - Output file: `deploys/<chainid>.erc721_redeem_minter.txt`.

- `yarn deploy:dao`
  - Runs `DeployNewDAO.s.sol` deterministic DAO deployment flow.
  - Requires `DEPLOY_SALT`.
  - **Uses Manager's immutable implementation addresses** (`manager.tokenImpl()`, `manager.auctionImpl()`, etc.) automatically.
  - **For cross-chain identical DAO addresses:** Manager implementations must be at the same addresses on all chains. Implementation addresses CANNOT be overridden per-deployment; they are set when the Manager implementation is deployed and are immutable.
  - Prints the predicted token, metadata, auction, treasury, and governor addresses before broadcast.
  - Deterministic addresses depend on: deployer address, `DEPLOY_SALT`, and Manager's immutable implementation addresses.
  - Legacy `Manager.deploy(...)` remains for backward compatibility, but new integrations should use deterministic deploy.
  - Intended for controlled deployment/testing flows.
  - **Governance Parameters:** Configured in the script via `GovParams` struct:
    - `timelockDelay`: Time delay to execute queued transactions (default: 2 days)
    - `votingDelay`: Time delay before voting starts (default: 2 days)
    - `votingPeriod`: Duration of voting period (default: 2 days)
    - `proposalThresholdBps`: Basis points of supply required to create proposals (default: 50 = 0.5%)
    - `quorumThresholdBps`: Basis points of supply required for quorum (default: 1000 = 10%)
    - `vetoer`: Address authorized to veto proposals (default: address(0) = no vetoer)
    - `proposalUpdatablePeriod`: Time proposals are editable after creation (default: 1 day, range: 0-24 weeks)

## Cross-Chain Deterministic Deployments

### Overview

The Manager contract uses **DAOFactory** as a canonical deployer to enable **cross-chain deterministic DAO deployments**. DAOFactory is deployed via CREATE3 at a deterministic address on all chains, which then uses CREATE2 to deploy DAO proxies. This architecture enables DAOs to have identical addresses across multiple chains, even when Manager proxies are deployed at different addresses on each chain.

**Key Components:**

- **DAOFactory**: Canonical factory contract deployed via CREATE3 (bytecode-independent determinism)
  - Salt: `keccak256("DAO_FACTORY")`
  - Deterministic address across all chains despite being bound to chain-specific Manager addresses
- **Manager**: References DAOFactory as an immutable for DAO deployments
  - Each Manager implementation is bound to a specific DAOFactory instance
  - DAOFactory address is set at Manager construction time

### How It Works

DAO addresses are calculated using CREATE3, where DAOFactory acts as the deployer. CREATE3 provides bytecode-independent determinism - the same salt and deployer address always produce the same deployed address, regardless of constructor arguments or implementation changes.

**Address Calculation:**
DAOFactory uses the Solmate CREATE3 library, which internally:

1. Deploys a proxy deployer contract via CREATE2
2. That proxy deployer deploys the actual contract via CREATE

The final address depends only on:

- `DAO_FACTORY_ADDRESS` = Address of DAOFactory contract (same on all chains)
- `salt` = `keccak256(deployerWallet ++ DEPLOY_SALT ++ contractLabel)`
  - `deployerWallet`: The founder's wallet address (first founder in the array)
  - `DEPLOY_SALT`: User-provided salt for namespacing
  - `contractLabel`: Contract-specific identifier ("TOKEN", "METADATA", etc.)

**Deployment Flow:**

1. Manager validates implementations and DAOFactory exists
2. Manager calls `DAOFactory.deployProxy(salt, proxyCreationCode)` for each contract
3. DAOFactory uses CREATE3 to deploy ERC1967Proxy at deterministic address
4. DAOFactory validates deployment succeeded and matches predicted address
5. Manager initializes each proxy with DAO-specific parameters

### Requirements for Cross-Chain DAO Determinism

To achieve identical DAO addresses across chains when using `deployDeterministic()`, you must use:

1. **Same deployer address** (user wallet) on all chains
2. **Same `deploySalt`** value passed to `deployDeterministic()`
3. **Same Manager implementation addresses** (tokenImpl, metadataImpl, auctionImpl, treasuryImpl, governorImpl) which are immutables set at Manager construction
4. **Same proxy bytecode** (ERC1967Proxy from the same compiler version)

**Important Notes:**

- **Manager proxy addresses CAN be different** on each chain without affecting DAO address determinism
- **Manager implementation addresses ARE NOW IDENTICAL** across chains (as of V3 with CREATE3)
- Previously (V2): Implementation addresses differed due to chain-specific constructor parameters
- Now (V3): CREATE3 ensures identical implementation addresses regardless of constructor differences
- The salt calculation uses the **deployer's wallet address**, NOT the Manager contract address
- DAO addresses depend on the Manager's immutable implementation addresses (tokenImpl, auctionImpl, etc.)

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
  - Manager implementation addresses (tokenImpl, auctionImpl, governorImpl, etc.)

**Why DAO Determinism Works Despite Manager Differences:**
The salt calculation for DAO contracts is:

```
salt = keccak256(deployerWalletAddress ++ deploySalt ++ contractLabel)
```

**Manager address is NOT included**. This means:

- Manager A on Chain 1 and Manager B on Chain 2 can be at different addresses
- Manager implementations ARE NOW IDENTICAL across chains (as of V3 with CREATE3)
- DAOs will deploy to **identical addresses** if same user + same deploySalt + same Manager implementation addresses
- **V3 Advantage**: Using `yarn deploy:dao` now produces identical DAO addresses because Manager implementations are identical across chains

### Fund Recovery Use Case

A key benefit of cross-chain DAO determinism is fund recovery:

**Scenario:**

1. DAO "CoolDAO" is deployed on Mainnet with Treasury at address `0x1234...`
2. User accidentally sends 10 ETH to `0x1234...` on Base (where CoolDAO doesn't exist yet)
3. Funds are locked at an address with no contract

**Solution:**

1. Original DAO deployer calls `Manager.deployDeterministic()` on Base
2. Uses the **same wallet** and **same `deploySalt`** as the Mainnet deployment
3. Manager must have the same implementation addresses as the Mainnet Manager
4. Treasury deploys to `0x1234...` on Base (same address as Mainnet)
5. The 10 ETH is now controlled by the Treasury contract
6. Governance can vote to recover the funds

**Security:**

- The salt includes the **original deployer's wallet address**, preventing anyone else from deploying to the predicted address
- Even if an attacker predicts the address, they cannot deploy there unless they control the original deployer's wallet
- Manager addresses can be different on each chain without affecting security

**Important:** This works regardless of whether:

- Manager proxies are at different addresses on Mainnet vs Base
- The Manager was upgraded since the original DAO deployment

The only requirements are: same deployer wallet + same deploySalt + same Manager implementation addresses.

**V3 Simplification**: With CREATE3, Manager implementations are now identical across all chains, so using `yarn deploy:dao` (which uses Manager's immutable implementation addresses) automatically produces identical DAO addresses.

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
- Constructor: Stores the manager address (validation happens in deployProxy(), not constructor)
- Authorization: `deployProxy()` validates `msg.sender == manager` before deployment
- Deployment: DAOFactory is deployed via CREATE3, making its address deterministic across all chains
- Usage: Manager calls `daoFactory.deployProxy(salt, creationCode)` which internally uses CREATE3 library from Solmate

Both factories are deployed on all supported networks:

- Ethereum Mainnet (1)
- Sepolia (11155111)
- Optimism (10)
- Optimism Sepolia (11155420)
- Base (8453)
- Base Sepolia (84532)

The Manager constructor validates that CREATE2 factory exists on deployment. If deploying to a new chain where either factory is not present, it must be deployed first.

### Example Workflows

**Scenario 1: Cross-Chain DAO Deployment (Direct API Call)**

For guaranteed identical DAO addresses across chains:

```solidity
// Deploy on Mainnet
// Implementation addresses come from Manager's immutables (tokenImpl, auctionImpl, etc.)
// These CANNOT be overridden per-deployment
manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt);

// Deploy on Optimism - SAME deploySalt, Manager must have same implementation addresses
manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt);
```

**Result:** Identical DAO addresses on both chains if:

- Same deployer wallet
- Same `deploySalt`
- Same Manager implementation addresses (tokenImpl, auctionImpl, governorImpl, etc.)
- Manager proxy addresses can differ without affecting DAO determinism

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

## DAOFactory Architecture

### Why DAOFactory Exists

The DAOFactory contract was introduced in V3 to solve a critical cross-chain determinism problem:

**The Problem:**

- DAO proxy addresses must be deterministic across chains for fund recovery
- CREATE2 address calculation includes the deployer's address
- If Manager deploys DAOs directly, DAO addresses depend on Manager's address
- Manager proxies can be at different addresses on different chains (due to deployment timing, nonce differences, etc.)
- **Result:** Same DAO would have different addresses on different chains

**The Solution:**

- Introduce DAOFactory as a canonical deployer
- DAOFactory is deployed via CREATE3 at the same address on all chains
- Manager delegates all DAO deployments to DAOFactory
- DAO addresses now depend on DAOFactory's address (which is identical) instead of Manager's address (which can differ)
- **Result:** Same DAO has identical addresses across all chains

### How DAOFactory Works

**Deployment:**

```solidity
// DAOFactory is deployed via CREATE3 with a fixed salt
bytes32 salt = keccak256("NOUNS_BUILDER_DAO_FACTORY_V1");
address daoFactory = CREATE3Factory.deploy(salt, creationCode);

// Each Manager stores its DAOFactory as an immutable
Manager manager = new Manager(tokenImpl, ..., daoFactory);
```

**DAO Deployment Flow:**

```solidity
// 1. User calls Manager.deployDeterministic()
manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt);

// 2. Manager derives salts and delegates to DAOFactory
bytes32 tokenSalt = keccak256(abi.encode(msg.sender, deploySalt, "TOKEN"));
address token = daoFactory.deployProxy(tokenSalt, tokenProxyCreationCode);

// 3. DAOFactory validates caller and deploys via CREATE3
function deployProxy(bytes32 salt, bytes memory creationCode) external returns (address) {
    if (msg.sender != manager) revert UNAUTHORIZED();
    return CREATE3.deploy(salt, creationCode, 0);
}
```

**Key Benefits:**

- **Cross-chain determinism**: DAOFactory at same address on all chains
- **Manager flexibility**: Managers can be at different addresses without affecting DAOs
- **Upgrade safety**: Manager upgrades don't change DAO addresses
- **Security**: Only the authorized Manager can deploy through its DAOFactory

### DAOFactory vs CREATE3Factory

**CREATE3Factory** (`0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`):

- Used for: implementations, DAOFactory itself, minters
- Public: Anyone can deploy
- Bytecode-independent determinism
- Salt namespacing: `keccak256(deployer ++ salt)`

**DAOFactory** (deployed via CREATE3):

- Used for: DAO proxies only
- Restricted: Only authorized Manager can deploy
- Bytecode-independent determinism (uses CREATE3 internally)
- Salt includes deployer wallet to prevent frontrunning

### Bootstrap Deployment Sequence

There's a circular dependency: Manager needs DAOFactory address, but DAOFactory needs Manager address. Here's how it's resolved:

```solidity
// Step 1: Deploy temporary Manager implementation with zero DAOFactory
Manager tempManagerImpl = new Manager(tokenImpl, ..., address(0));

// Step 2: Deploy Manager proxy pointing to temp implementation
ERC1967Proxy managerProxy = new ERC1967Proxy(
    address(tempManagerImpl),
    abi.encodeWithSignature("initialize(address)", owner)
);

// Step 3: Predict DAOFactory address (CREATE3 determinism)
bytes32 daoFactorySalt = keccak256("NOUNS_BUILDER_DAO_FACTORY_V1");
address predictedDAOFactory = CREATE3.getDeployed(daoFactorySalt, address(this));

// Step 4: Deploy DAOFactory (now knows Manager proxy address)
bytes memory daoFactoryCode = abi.encodePacked(
    type(DAOFactory).creationCode,
    abi.encode(address(managerProxy))
);
address daoFactory = CREATE3Factory.deploy(daoFactorySalt, daoFactoryCode);
require(daoFactory == predictedDAOFactory, "Address mismatch");

// Step 5: Deploy real Manager implementation with correct DAOFactory
Manager realManagerImpl = new Manager(tokenImpl, ..., daoFactory);

// Step 6: Upgrade Manager proxy to real implementation
IManager(address(managerProxy)).upgradeTo(address(realManagerImpl));
```

**Result:**

- Manager proxy initialized atomically (prevents frontrunning)
- DAOFactory bound to Manager proxy
- Manager implementation has correct DAOFactory immutable
- All addresses deterministic across chains

### Security Considerations

**Authorization:**

- DAOFactory only accepts deployments from its bound Manager
- Prevents unauthorized parties from deploying to predicted DAO addresses
- Each Manager has its own DAOFactory instance

**Salt Construction:**

- Includes deployer wallet address: `keccak256(deployer ++ deploySalt ++ label)`
- Prevents different deployers from colliding
- Only original deployer can recreate identical DAO addresses

**Immutability:**

- Manager's `daoFactory` address is immutable
- Cannot be changed after Manager deployment
- To change DAOFactory, must deploy new Manager implementation

**Upgrade Path:**

- Manager can be upgraded to new implementation
- New implementation can reference new DAOFactory
- Existing DAOs unaffected (already deployed)
- Future DAOs use new DAOFactory

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
yarn prepare:v3-upgrade

# Step 2: Upgrade the Manager proxy to the new implementation
# (Use your preferred governance/multisig tool to call manager.upgradeTo(newManagerImpl))

# Step 3: Verify the new implementation's builderRewardsRecipient
cast call $MANAGER_PROXY "builderRewardsRecipient()(address)"
```

**Note:** The new Manager implementation has `builderRewardsRecipient` as an immutable constructor parameter set during deployment. To use a different value, deploy a new Manager implementation with the desired value and upgrade to it.

For additional upgrade procedures, see:

- `docs/upgrade-runbook.md`
- `docs/manager-ownership-runbook.md`
