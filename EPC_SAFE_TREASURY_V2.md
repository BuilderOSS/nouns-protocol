# Safe Treasury V2 EPC

## Goal

Upgrade the Treasury implementation to support Safe-based execution with one main Safe and optional additional vault Safes, while preserving the existing Governor proposal API and timelock semantics.

## Scope (Phase 1)

- New DAO deployments only.
- Keep Governor proposal calldata shape unchanged.
- Keep Treasury queue/cancel/execute semantics unchanged.
- Add Safe routing in Treasury with governance-controlled safe registry.
- Add configurable per-safe policy references and optional global baseline policy reference.

## Non-Goals (Phase 1)

- Existing DAO migration tooling.
- Cross-chain bridge executor.
- Custom in-Treasury policy math engine.

## Architecture

- Governor remains the proposal and voting engine.
- Treasury remains the timelock and top-level executor.
- Safe module path is used for actions that must execute from Safe ownership context.
- Proposal routing for additional safes is done through `execOnSafe(...)` calls encoded in existing proposal calldata arrays.

## Ownership Model

- Treasury owner remains Governor.
- Governor owner remains Treasury.
- Main Safe is used as the auction payout treasury for new deployments.
- Auction and Token ownership transfer path therefore resolves to main Safe after launch.
- Metadata ownership follows Token ownership.

## Security Principles

- Governance-only config updates through `msg.sender == address(this)` guards.
- Minimal new mutable state in Treasury.
- Default disallow Safe delegatecall operation in Treasury-routed execution.
- Rich execution events for traceability.
- Use external audited policy/guard modules for limits.

## Treasury V2 Additions

### Storage

- `mainSafeId`
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
- `isMain`

### New Functions

- `initializeV2(...)`
- `registerSafe(...)`
- `updateSafe(...)`
- `setMainSafe(...)`
- `setGlobalPolicy(...)`
- `execOnSafe(...)`
- getters for `mainSafeId`, `safeCount`, `safe`, `safeIdByAddress`, `globalPolicy`

### New Events

- `SafeRegistered`
- `SafeUpdated`
- `MainSafeUpdated`
- `GlobalPolicyUpdated`
- `SafeExecution`

## Execution Routing

- Existing direct call execution path remains intact.
- For safe-routed calls, proposal action targets Treasury and calls `execOnSafe`.
- `execOnSafe` validates safe registration/activity and forwards to module.

## Per-Safe Limits

- Implemented by assigning policy contract references per Safe.
- Optional global policy reference can be set as a baseline.
- Treasury records policy addresses and policy hashes; policy enforcement occurs in external guard/module stack.

## Manager Support

- Keep existing `deploy(...)` behavior unchanged for backwards compatibility.
- Add `deployWithSafe(...)` for new DAO creation with a configured main Safe.
- `deployWithSafe(...)` sets auction treasury recipient to main Safe and initializes Treasury V2 safe config.

## Testing Plan

- Preserve existing tests for timelock behavior.
- Add tests for:
  - `initializeV2` constraints,
  - governance-only safe registry mutations,
  - `execOnSafe` authorization and failure paths,
  - manager `deployWithSafe` ownership outcomes.

## Rollout

1. Deploy Treasury V2 + module contracts.
2. Register upgrade in Manager.
3. Use `deployWithSafe` for new DAOs.
4. Follow-on migration tooling for existing DAOs in Phase 2.
