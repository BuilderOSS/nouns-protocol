# Upgrade Runbook (Any Chain)

## Scope

This runbook covers protocol implementation upgrades for any supported chain.

- Deploying new implementations (`Manager`, `Token`, `Auction`, `Governor`, and optionally `MetadataRenderer`/`Treasury`)
- Updating Manager and registering allowed upgrade paths
- Executing per-DAO upgrade proposals
- Verifying post-upgrade state and versions

Use this for production and testnet rollouts by substituting chain-specific addresses and RPC aliases.

## Inputs

Before starting, define:

- `CHAIN_ID`
- `NETWORK` (Foundry alias)
- `MANAGER_PROXY`
- `NEW_MANAGER_IMPL`
- `NEW_TOKEN_IMPL`
- `NEW_AUCTION_IMPL`
- `NEW_GOVERNOR_IMPL`
- Optional: `NEW_METADATA_IMPL`, `NEW_TREASURY_IMPL`

## Phase 0: Baseline Snapshot

Capture current onchain state right before rollout:

```bash
RPC_ALIAS=${NETWORK}

cast call $MANAGER_PROXY "owner()(address)" --rpc-url $RPC_ALIAS
cast call $MANAGER_PROXY "tokenImpl()(address)" --rpc-url $RPC_ALIAS
cast call $MANAGER_PROXY "auctionImpl()(address)" --rpc-url $RPC_ALIAS
cast call $MANAGER_PROXY "governorImpl()(address)" --rpc-url $RPC_ALIAS
cast call $MANAGER_PROXY "metadataImpl()(address)" --rpc-url $RPC_ALIAS
cast call $MANAGER_PROXY "treasuryImpl()(address)" --rpc-url $RPC_ALIAS
```

Optional EIP-1967 implementation slot check:

```bash
cast storage $MANAGER_PROXY 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC --rpc-url $RPC_ALIAS
```

## Phase 1: Deploy New Implementations

```bash
source .env
export NETWORK=<network>
yarn deploy:v2-upgrade
```

Record outputs from `deploys/*.txt` and update `addresses/<chainid>.json` manually.

## Phase 2: Update Manager and Register Upgrades

Manager owner executes:

1. `Manager.upgradeTo(NEW_MANAGER_IMPL)`
2. `Manager.registerUpgrade(baseTokenImpl, NEW_TOKEN_IMPL)` for each base token impl to support
3. `Manager.registerUpgrade(baseAuctionImpl, NEW_AUCTION_IMPL)` for each base auction impl to support
4. `Manager.registerUpgrade(baseGovernorImpl, NEW_GOVERNOR_IMPL)` for each base governor impl to support
5. Optional: register metadata/treasury upgrade paths if these contracts changed

Use your manager owner path:

- DAO treasury governance proposal, or
- multisig transaction batch.

## Phase 3: Upgrade Existing DAOs

Each DAO upgrades itself through its own governance flow.

Typical sequence:

1. `Token.upgradeTo(NEW_TOKEN_IMPL)`
2. `Auction.pause()`
3. `Auction.upgradeTo(NEW_AUCTION_IMPL)`
4. `Auction.unpause()`
5. `Governor.upgradeTo(NEW_GOVERNOR_IMPL)`

Apply additional contract upgrades if part of the rollout scope.

## Governor-Specific Compatibility Notes

- `castVoteBySig` ABI changed from `(deadline, v, r, s)` to `(nonce, deadline, bytes sig)`.
- Signed proposal update policy:
  - signed proposals can use unsigned `updateProposal` only if proposer independently met threshold at creation-time reference,
  - otherwise proposer must use `updateProposalBySigs`.

See:

- `docs/governor-architecture.md`
- `docs/governor-audit-readiness.md`

## Verification Checklist

After manager and DAO upgrades:

1. Manager proxy implementation equals `NEW_MANAGER_IMPL`.
2. `tokenImpl()`, `auctionImpl()`, `governorImpl()` match expected new impls.
3. `isRegisteredUpgrade(base, new)` is `true` for each expected registration.
4. `getLatestVersions()` reflects expected latest versions.
5. For each upgraded DAO, `getDAOVersions(token)` reflects expected versions.
6. Governance-specific config set as expected (for example `_proposalUpdatablePeriod`).

## Operational Safety

- Run a canary DAO upgrade before broad rollout.
- Keep pause/upgrade/unpause in one proposal where feasible.
- Preserve historic upgrade registrations unless there is a clear reason to remove them.
- Persist rollout artifacts (`deploys/*`, address manifests, proposal links, tx hashes).
