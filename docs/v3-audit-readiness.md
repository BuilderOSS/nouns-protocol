# V3 Protocol Upgrade Audit Readiness

## Scope

This checklist covers ALL V3 protocol changes introduced on branch `feat/updatable-proposals`.

Reference architecture:
- Governor features: `docs/governor-architecture.md`
- Deployment model: `docs/deployment-workflows.md`
- Proposal lifecycle: `docs/governor-proposal-lifecycle.md`

## Key V3 Feature Additions

### Governor Enhancements
- `proposeBySigs` - collective proposal creation with EIP-712 signatures
- `updateProposal` - proposal edits during updatable window
- `updateProposalBySigs` - signed proposal updates
- `Updatable` proposal state - time-bounded edit window before voting
- `castVoteBySig` ABI upgrade - unified `bytes` signature path (breaking change)

### Manager & Deployment Infrastructure
- CREATE3 deterministic deployments for all implementations
- CREATE2 deterministic DAO deployments via `deployDeterministic`
- Cross-chain deterministic Manager proxy deployment
- `builderRewardsRecipient` as immutable in Manager (changeable via upgrade)
- WETH removed from Manager, kept only in Auction as immutable
- Prediction helpers: `predictDeterministicAddresses`

### EAS Integration (Off-Chain Coordination)
- ProposalCandidate schema for draft proposals
- CandidateComment schema for discussion
- CandidateSponsorSignature schema for formal endorsements
- Versioning system via `candidateId` + `salt`

---

## Security Invariants

### Governor Signature Validation
- Signature validation uses OpenZeppelin `SignatureChecker` for EOA + ERC1271 compatibility
- Signed proposing uses strict ordered signer list (ascending addresses, no duplicates)
- Signed proposing enforces hard cap: **16 signers per proposal** (`MAX_PROPOSAL_SIGNERS`)
- Signed propose/update paths validate each signature and run per-signer `getVotes` before threshold check
  - Proposer can be griefed into expensive revert path with many valid signers
  - This is bounded by `MAX_PROPOSAL_SIGNERS` (16) to limit gas costs
- Proposer cannot appear in signer set (`PROPOSER_CANNOT_BE_SIGNER`) to avoid vote double counting

### Signature Replay Protection
- Vote signatures use existing `nonces` mapping
- Propose/update signatures use dedicated `proposeSigNonces` mapping
- All signatures expire via `deadline` checks
- Nonce increments prevent replay across different operations

### Proposal Update Constraints
- Updates only allowed in `Updatable` state (`block.timestamp < proposalUpdatePeriodEnd`)
- No-op updates (same resulting proposal id) revert with `NO_OP_PROPOSAL_UPDATE`
- For signed proposals:
  - Unsigned `updateProposal` only allowed if proposer met threshold at creation-time reference (`timeCreated - 1`)
  - Otherwise `updateProposalBySigs` required with fresh signature validation

### Proposal Cancellation
- Third-party cancellation for signed proposals checks combined proposer + signer votes
- Signer can cancel their own sponsored proposals
- Proposer can always cancel their own proposals

### Voting Power Snapshot Preservation
- **CRITICAL**: When proposal is updated, `timeCreated` timestamp is preserved from original
- All vote weight queries use original creation timestamp, NOT update timestamp
- Prevents proposers from gaming the system by updating to capture favorable snapshots

---

## Manager & Deployment Security

### CREATE3 Determinism
- All implementations deployed via CREATE3 factory at `0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`
- CREATE3 address formula: `f(salt, deployer)` - **independent of bytecode**
- This enables identical addresses across chains even with different constructor args
- Examples of chain-specific constructor args that don't break determinism:
  - `builderRewardsRecipient` in Manager
  - `protocolRewards` in Auction
  - `crossDomainMessenger` in L2MigrationDeployer
  - `weth` in Auction

### CREATE2 Determinism
- Manager proxy deployed via CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- Bootstrap Manager implementation (`managerImpl0`) uses **all-zero constructor args** for cross-chain determinism
- Manager proxy includes initialization data in constructor for **atomic initialization**
- Security: Prevents front-running attacks where attacker could call `initialize()` before deployer

### DAO Deployment Determinism
- DAOs deployed via `Manager.deployDeterministic` use CREATE2 factory
- DAO addresses depend on: deployer wallet, deploySalt, and implementation addresses
- Implementation addresses are now identical across chains (via CREATE3)
- This enables cross-chain fund recovery: deploy same DAO on different chain to access funds sent to predicted address

### Manager Immutables
- `tokenImpl`, `metadataImpl`, `auctionImpl`, `treasuryImpl`, `governorImpl` - set at construction
- `builderRewardsRecipient` - set at construction, changeable only by upgrading Manager implementation
- NO `weth` in Manager (moved to Auction only)

### Auction Immutables
- `WETH` - set at construction, chain-specific value
- Reads `builderRewardsRecipient` from Manager at runtime via `manager.builderRewardsRecipient()`

### Cross-Chain Validation
- CREATE2 factory existence validated in Manager constructor via `_validateCreate2Factory()`
- CREATE3 prediction uses `msg.sender` not `address(this)` for Foundry broadcast compatibility
- All deterministic address predictions verified on deployment

---

## Storage / Upgrade Safety

### Governor Storage
- Legacy `Proposal` struct layout **preserved** (no in-place field insertion)
- New fields are append-only through `GovernorStorageV3` mappings:
  - `_proposalUpdatablePeriod`
  - `proposeSigNonces`
  - `proposalSigners`
  - `proposalUpdatePeriodEnds`
  - `proposalIdReplacedBy`
- `ProposalState.Updatable` appended to enum tail to preserve existing numeric values

### Manager Storage
- Manager immutables **cannot be changed** without deploying new implementation
- No new storage slots added in V3
- Upgrade-safe: existing DAOs retain all state

### DAO Contract Storage
- Token, Metadata, Auction, Treasury, Governor all use append-only storage patterns
- ERC1967 proxy upgrade slots preserved
- Version information queryable via `IVersionedContract.contractVersion()`

---

## Test Coverage

### Governor Tests (test/Gov.t.sol, test/GovUpgrade.t.sol)

**Standard Proposal Creation:**
- Member proposer, no signatures: `test_CreateProposal`, `test_ProposalVoteQueueExecution`
- Threshold validation: `testRevert_CannotProposeWithoutEnoughVotes`

**Signed Proposal Creation:**
- Caller proposer with signatures: `test_ProposeBySigs`
- Proposer in signer set blocked: `testRevert_ProposeBySigsSignerCannotBeProposer`
- Signer array ordering enforced: tests verify strict ascending order requirement
- Too many signers: validation via `MAX_PROPOSAL_SIGNERS` constant

**Proposal Updates:**
- Unsigned update for unsigned proposals: standard update path
- Unsigned update blocked for signed proposals (unqualified proposer): `testRevert_UpdateProposalTxsOnSignedProposalWithoutSignaturesForUnqualifiedProposer`
- Signed update path: `test_UpdateProposalBySigs`
- Qualified proposer can unsigned-update signed proposal: `test_UpdateProposalOnSignedProposalForQualifiedProposer`

**State Transitions:**
- `Updatable -> Pending -> Active`: `test_ProposalState_UpdatableToPendingToActive`
- Full lifecycle with updates

**Cancellation:**
- Combined-vote threshold for third-party cancellation: `testRevert_CannotCancelSignedProposalWhenCombinedVotesAtThreshold`
- Signer cancel ability: `test_SignerCanCancelSignedProposal`

**Signature Validation:**
- Invalid signer: `testRevert_InvalidVoteSigner`
- Invalid nonce: `testRevert_InvalidVoteNonce`
- Expired signature: `testRevert_InvalidVoteExpired`

**Gas Benchmarking:**
- `test_GasProposeBySigs_1Signer`
- `test_GasProposeBySigs_16Signers`
- `test_GasProposeBySigs_16Signers_Max`
- `test_GasUpdateProposalBySigs`
- `test_GasCancelSignedProposal_16Signers`

### Manager Tests (test/Manager.t.sol)

**Deterministic Deployment:**
- `test_DeployDeterministicMatchesPrediction` - verifies addresses match predictions
- `test_PredictDeterministicAddressesChangesWithDeployer` - different deployers = different addresses
- `test_PredictDeterministicAddressesChangesWithSalt` - different salts = different addresses
- `test_PredictDeterministicAddressesChangesWithImplementationBundle` - different implementations = different addresses
- `test_CrossChainDeterminismWithDifferentManagerAddresses` - verifies DAO addresses are identical even with different Manager addresses
- `test_FundRecoveryScenario` - validates cross-chain fund recovery use case

**Prediction Stability:**
- `test_PredictDeterministicAddressesStableAcrossManagerUpgrade` - predictions unchanged after Manager upgrade

**Collision Prevention:**
- `test_DeployDeterministicSameSaltDifferentDeployersDoNotConflict` - different deployers can use same salt

**Validation:**
- `testRevert_DeployDeterministicWithZeroImplementation` - rejects zero address implementations
- `testRevert_PredictDeterministicAddressesWithZeroImplementation` - prediction rejects zero address
- `testRevert_DeployDeterministicWithUsedSalt` - prevents salt reuse

**Version Queries:**
- `test_GetDAOVersions` - verify version information queryable
- `test_GetLatestVersions` - verify latest versions queryable

### Forking Tests (test/forking/)

**Mainnet Manager Upgrade (TestMainnetManagerUpgrade.t.sol):**
- `test_UpgradeAuthorization_OnlyOwnerCanUpgrade`
- `test_UpgradeExecution_OwnerCanUpgrade`
- `test_PostUpgrade_ImmutablesPreserved`
- `test_PostUpgrade_OwnershipPreserved`
- `test_PostUpgrade_ExistingDAOAddressesQueryable`
- `test_PostUpgrade_UpgradeRegistryPreserved`
- `test_Validation_ZeroAddressImplementationReverts`
- `test_Validation_EOAImplementationReverts`
- `test_VersionInfo_GetDAOVersions`
- `test_VersionInfo_GetLatestVersions`

**Purple DAO System Upgrade (TestPurpleDAOSystemUpgrade.t.sol):**
- Full DAO stack upgrade (Token, Metadata, Auction, Treasury, Governor)
- Cross-contract integration validation
- State preservation checks

---

## Breaking Changes

### ABI Breaking Changes

**1. `castVoteBySig` signature changed:**
```solidity
// OLD (V2):
function castVoteBySig(
  address voter,
  bytes32 proposalId,
  uint256 support,
  uint256 deadline,
  uint8 v,
  bytes32 r,
  bytes32 s
) external returns (uint256);

// NEW (V3):
function castVoteBySig(
  address voter,
  bytes32 proposalId,
  uint256 support,
  uint256 nonce,
  uint256 deadline,
  bytes calldata sig
) external returns (uint256);
```

**Impact:**
- Different function selector
- Integrations using old signature will fail
- Requires signature payload migration from `(v,r,s)` to `bytes`

### Deployment Workflow Changes

**1. Manager deployment now requires all-zero bootstrap implementation:**
```solidity
// managerImpl0 MUST use all-zero constructor args for cross-chain determinism
new Manager(address(0), address(0), address(0), address(0), address(0), address(0))
```

**2. Manager proxy uses atomic initialization to prevent front-running:**
```solidity
// CRITICAL: Include initialization data in proxy constructor for atomic deployment
// This prevents front-running attacks where someone else calls initialize() before deployer
manager = Manager(
    deployViaFactory(
        abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(managerImpl0, abi.encodeWithSignature("initialize(address)", deployerAddress))
        ),
        salt
    )
);
// No separate initialize() call needed - initialization happens atomically in constructor
```

---

## Integration / UX Notes

### For Frontends
- **Proposal IDs are content hashes**: Any tx-bundle or description change creates new proposal id
- **Follow replacement links**: Use `proposalIdReplacedBy(oldId)` to track proposal evolution
- **Show revision history**: Display all versions of a proposal via replacement chain
- **Voting timeline adjustment**: Voting starts at `creation + proposalUpdatablePeriod + votingDelay` (not just `creation + votingDelay`)
- **Migrate `castVoteBySig`**: Update to new signature format with nonce parameter

### For Indexers/Subgraphs
- **Track proposal replacements**: Index `ProposalUpdated` events and maintain replacement mappings
- **Query helpers available**:
  - `proposalIdReplacedBy(oldId)` - get replacement proposal id
  - `getProposalSigners(proposalId)` - get all signers for a proposal
  - `proposalUpdatePeriodEnd(proposalId)` - get edit window end timestamp
- **EAS integration**: Query ProposalCandidate attestations for draft proposals
- **Version information**: Use `getDAOVersions(token)` and `getLatestVersions()`

### For Signature Builders
- **Nonce management**: `proposeSigNonces` shared between `proposeBySigs` and `updateProposalBySigs`
- **Sequence carefully**: Propose and update signatures must sequence against same nonce counter
- **Include deadline**: All signatures require expiry timestamp
- **Use EIP-712 typed data**: OpenZeppelin's `SignatureChecker` validates both EOA and ERC-1271

### For Cross-Chain Operators
- **Use same deployer wallet**: Cross-chain determinism requires same EOA on all chains
- **Use same DEPLOY_SALT**: Must be identical for matching addresses
- **Implementations auto-match**: V3 CREATE3 ensures implementation addresses are identical
- **Fund recovery enabled**: Can deploy DAO on new chain to access funds sent to predicted address

---

## Operational Rollout Checks

### Pre-Deployment
- [ ] Verify CREATE2 factory exists at `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- [ ] Verify CREATE3 factory exists at `0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`
- [ ] Set `DEPLOY_SALT` environment variable (use same value for cross-chain)
- [ ] Set `PRIVATE_KEY` for deployer wallet (use same wallet for cross-chain)
- [ ] Configure `addresses/<chainid>.json` with chain-specific values:
  - `WETH`
  - `ProtocolRewards`
  - `BuilderRewardsRecipient`
  - `CrossDomainMessenger` (L2s only)

### Fresh V3 Deployment (`yarn deploy:v3-new`)
- [ ] Deploy succeeds without reverts
- [ ] Verify Manager proxy address matches prediction
- [ ] Verify all implementation addresses match predictions
- [ ] Verify Manager proxy initialized with correct owner
- [ ] Verify `Manager.builderRewardsRecipient()` returns expected address
- [ ] Record all addresses in `deploys/<chainid>.version3_new.txt`
- [ ] Update `addresses/<chainid>.json` with deployed addresses

### Existing Manager Upgrade (`yarn deploy:v3-upgrade`)
- [ ] Deploy new implementations
- [ ] Verify new Manager implementation has correct `builderRewardsRecipient` immutable
- [ ] Execute `Manager.upgradeTo(newManagerImpl)` via manager owner
- [ ] Verify Manager upgrade successful
- [ ] Register upgrade paths:
  - [ ] `Manager.registerUpgrade(oldTokenImpl, newTokenImpl)`
  - [ ] `Manager.registerUpgrade(oldAuctionImpl, newAuctionImpl)`
  - [ ] `Manager.registerUpgrade(oldGovernorImpl, newGovernorImpl)`
  - [ ] Optional: metadata/treasury if changed

### Existing DAO Governor Upgrade
- [ ] Verify Manager has registered upgrade path for Governor
- [ ] Create governance proposal to upgrade Governor proxy
- [ ] Execute `Governor.upgradeTo(newGovernorImpl)` via treasury
- [ ] Set `proposalUpdatablePeriod` via `Governor.updateProposalUpdatablePeriod(1 days)`
- [ ] Verify Governor upgrade successful
- [ ] Verify `proposalUpdatablePeriod` set correctly

### Frontend/SDK Migration
- [ ] Update `castVoteBySig` call sites to new ABI
- [ ] Update signature builders to use `(nonce, deadline, bytes sig)` format
- [ ] Implement proposal replacement link following
- [ ] Add updatable period display to proposal timeline
- [ ] Test EAS integration for proposal candidates
- [ ] Verify EIP-712 signature payloads match contract expectations

### Cross-Chain Deployment Verification
- [ ] Verify Manager proxy address identical on all chains (if using same salt/deployer)
- [ ] Verify all implementation addresses identical on all chains
- [ ] Test `predictDeterministicAddresses` returns same results on all chains
- [ ] Deploy test DAO with same parameters on multiple chains
- [ ] Verify DAO addresses identical on all chains

### Post-Deployment Validation
- [ ] Run `yarn addresses:check-manager-owner` to verify owner
- [ ] Run `yarn addresses:check-builder-rewards` to verify builder rewards config
- [ ] Create test proposal via `propose` (standard path)
- [ ] Create test proposal via `proposeBySigs` (signed path)
- [ ] Test proposal update during updatable window
- [ ] Verify voting works with new `castVoteBySig` ABI
- [ ] Execute full proposal lifecycle: create → update → vote → queue → execute

---

## Known Limitations & Design Decisions

### Signer Cap (16)
- **Rationale**: Prevents gas griefing attacks where many invalid signatures cause expensive reverts
- **Mitigation**: Frontends should batch multiple signature collection rounds if needed
- **Alternative**: Off-chain aggregation via EAS for larger coordination

### Voting Snapshot Preservation on Update
- **Rationale**: Prevents proposers from gaming snapshots by updating during favorable token distribution
- **Trade-off**: Long edit windows may mean voters acquired tokens after proposal draft but before finalization
- **Mitigation**: Keep `proposalUpdatablePeriod` reasonably short (default 1 day)

### Manager Immutables (builderRewardsRecipient)
- **Rationale**: Gas optimization (immutable read ~3 gas vs storage ~100 gas)
- **Trade-off**: Requires Manager upgrade to change builder rewards recipient
- **Mitigation**: CREATE3 ensures upgrades don't break cross-chain determinism

### CREATE3 Reliance
- **Dependency**: Requires CREATE3 factory deployed at `0xD252d074EEe65b64433a5a6f30Ab67569362E7e0`
- **Mitigation**: Factory is deployed on all major EVM chains
- **Fallback**: Can deploy CREATE3 factory if missing on new chain

### EAS Off-Chain Coordination
- **Trade-off**: Proposal candidates live off-chain, not on-chain
- **Benefit**: Lower gas costs for proposal drafting and discussion
- **Risk**: Requires EAS availability and subgraph indexing
- **Mitigation**: Can still create proposals directly via `propose` without EAS

---

## Audit Focus Areas

### High Priority
1. **Signature validation** - verify EIP-712 + ERC-1271 compatibility
2. **Proposal identity calculation** - ensure hash collisions impossible
3. **Voting snapshot preservation** - verify `timeCreated` immutability on updates
4. **Cross-chain determinism** - verify CREATE2/CREATE3 address calculations
5. **Storage layout preservation** - verify no breaking changes for upgrades
6. **Nonce management** - verify replay protection across all signature types

### Medium Priority
1. **Signer array validation** - verify ordering/uniqueness enforcement
2. **Update window enforcement** - verify state machine correctness
3. **Cancellation logic** - verify proposer vs third-party paths
4. **Manager immutables** - verify constructor parameter handling
5. **Gas griefing bounds** - verify MAX_PROPOSAL_SIGNERS enforced

### Low Priority
1. **Version query helpers** - verify correct information returned
2. **Event emissions** - verify complete audit trail
3. **Error messages** - verify clear revert reasons
4. **Documentation** - verify code comments match implementation

---

## Reference Implementations

### Example: Propose by Signatures
```solidity
// Collect signatures off-chain (EIP-712)
bytes[] memory sigs = collectSignatures(...);
address[] memory signers = [0xAAA..., 0xBBB..., 0xCCC...]; // MUST be sorted

// Submit on-chain
governor.proposeBySigs(
  targets,
  values,
  calldatas,
  description,
  signers,
  sigs
);
```

### Example: Update Proposal
```solidity
// For unsigned proposals
governor.updateProposal(
  originalProposalId,
  newTargets,
  newValues,
  newCalldatas,
  newDescription
);

// For signed proposals
governor.updateProposalBySigs(
  originalProposalId,
  newTargets,
  newValues,
  newCalldatas,
  newDescription,
  newSigners,  // Can be different from original
  newSigs
);
```

### Example: Cross-Chain Deterministic Deploy
```bash
# Chain 1 (Mainnet)
NETWORK=mainnet PRIVATE_KEY=$KEY DEPLOY_SALT=my_dao_v1 yarn deploy:dao

# Chain 2 (Optimism) - SAME deployer, SAME salt
NETWORK=optimism PRIVATE_KEY=$KEY DEPLOY_SALT=my_dao_v1 yarn deploy:dao

# Result: Identical DAO addresses on both chains
```

---

## Version Information

- **Governor Version**: Query via `Governor.contractVersion()`
- **Manager Version**: Query via `Manager.contractVersion()`
- **DAO Versions**: Query via `Manager.getDAOVersions(tokenAddress)`
- **Latest Versions**: Query via `Manager.getLatestVersions()`

All version strings follow semantic versioning format.
