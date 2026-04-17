# Safe Treasury V2 EPC

## Goal

Upgrade the canonical `Treasury` contract to support optional Safe-based execution lanes without requiring DAOs to migrate all assets out of Treasury.

## Scope (Phase 1)

- Keep Governor proposal calldata shape unchanged.
- Keep Treasury queue/cancel/execute semantics unchanged.
- Add governance-managed Safe registry and `execOnSafe(...)` routing.
- Add optional global policy metadata and per-safe policy metadata.

## Non-Goals (Phase 1)

- No required main Safe.
- No forced migration of existing DAO assets from Treasury to Safe.
- No generic vault adapter abstraction in this release.
- No bridge/cross-chain execution support.

## Architecture

- Governor remains proposal and voting engine.
- Treasury remains canonical timelock and treasury account.
- Safes are optional managed execution vaults.
- Proposal routing to Safe is done by including a Treasury call to `execOnSafe(...)` in proposal calldata.

## Ownership Model

- Treasury owner remains Governor.
- Governor owner remains Treasury.
- Existing DAOs can keep Token/Auction/Metadata owned by Treasury unless governance explicitly migrates ownership later.

## Security Principles

- Treasury Safe registry and policy mutations are governance-only via `msg.sender == address(this)`.
- `execOnSafe(...)` is governance-only via `msg.sender == address(this)`.
- Restrict Safe operations to `CALL` mode in Phase 1.
- Use external policy modules for enforcement; Treasury stores policy metadata only.

## Treasury V2 Additions

### Storage

- `safeCount`
- `safes[safeId]`
- `safeIdByAddress[safe]`
- `globalPolicy` metadata

### Safe Config

- `safe`
- `execModule`
- `policy`
- `policyHash`
- `active`

### New Functions

- `registerSafe(...)`
- `updateSafe(...)`
- `setGlobalPolicy(...)`
- `execOnSafe(...)`
- getters for `safeCount`, `safe`, `safeIdByAddress`, `globalPolicy`

### New Events

- `SafeRegistered`
- `SafeUpdated`
- `GlobalPolicyUpdated`
- `SafeExecution`

## Execution Routing

- Existing direct call execution path remains intact.
- For safe-routed calls, proposal action targets Treasury and calls `execOnSafe(...)`.
- `execOnSafe` validates id/activity/op mode and routes through configured module.

## Per-Safe Limits

- Implemented by assigning policy references per Safe.
- Optional global policy metadata can be set as baseline intent.
- Enforcement logic remains in external guard/module stack.

## Upgrade Process

### Existing DAOs

1. Governance passes proposal to upgrade Treasury implementation.
2. Governance optionally sets global policy metadata.
3. Governance registers one or more Safes.
4. Governance uses `execOnSafe(...)` for specific actions as needed.

### New DAOs

- Manager deploys latest Treasury implementation by default.
- DAO enables Safe lanes later through governance calls.

## Testing Plan

- Preserve timelock behavior tests.
- Add tests for:
  - governance-only safe registry mutation,
  - duplicate/invalid safe registration failures,
  - global policy metadata updates,
  - `execOnSafe` success and failure modes.
