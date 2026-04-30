# Nouns Builder Cross-Chain Treasury Control Spec

## Status

- Draft v0.2
- Audience: protocol engineers, auditors, governance/frontend teams, infra operators

## Executive Summary

This spec defines a bridge-agnostic cross-chain execution system where:

- Governance and timelock remain on one source chain (`Governor` + canonical `Treasury`).
- Bridge logic is isolated from core protocol contracts.
- Destination chains use lightweight executors (no destination Treasury required).
- Destination execution controls Safe wallets first, with wallet adapter extensibility.
- Transport is pluggable (LayerZero/Hyperlane/Wormhole/etc.) behind a generic interface.

Managed bridge infrastructure is offered as the default, while DAOs can opt into sovereign bridge infrastructure.

---

## Canonical Product Goals

1. A DAO on one source chain can govern and operate Safes across multiple destination chains.
2. Safes should be deployed deterministically so addresses can match across chains when initialization invariants match.
3. Frontend setup flow should be simple and state-driven.
4. Signers/threshold should be configured securely at initial Safe deployment.
5. If deterministic address parity is desired, post-deployment owner/threshold changes are chain-local and will not retroactively carry to other chains.

---

## Scope and Non-Goals

## Scope (Phase 1)

1. Source `Treasury` sends cross-chain commands through a `SourceBridgeAdapter`.
2. Per-DAO destination `DestinationExecutor` verifies and executes commands.
3. Safe execution supported through `SafeWalletAdapter` and Safe module enablement.
4. Single transport verification mode by default, with a clean seam for future quorum mode.
5. Managed default deployment and configuration tooling.
6. LayerZero transport adapter is the in-repo default implementation for v1.

## Non-Goals (Phase 1)

1. Full destination governance stack (`Governor`/`Treasury`) on each chain.
2. Token bridge liquidity systems.
3. Multi-bridge quorum execution logic fully implemented in v1.

---

## Design Principles

1. **Core isolation**: no bridge-protocol-specific code inside core `Treasury` or `Governor`.
2. **Least privilege**: destination contracts only execute authenticated, replay-safe commands.
3. **Per-DAO isolation**: each DAO has isolated destination execution state.
4. **Simplicity first**: single-path happy flow in v1; extensibility hooks for v2.
5. **Reusability**: transport and wallet layers are adapter-based.
6. **Deterministic readiness**: explicit chain state before recommending funding.

---

## High-Level Architecture

```mermaid
flowchart LR
  subgraph Source Chain
    G[Governor]
    T[Treasury]
    SBA[SourceBridgeAdapter]
  end

  subgraph Bridge Layer
    TA[ITransportAdapter]
  end

  subgraph Destination Chain
    DE[DestinationExecutor (per DAO)]
    WA[SafeWalletAdapter]
    S[(Safe)]
  end

  G --> T
  T --> SBA
  SBA --> TA
  TA --> DE
  DE --> WA
  WA --> S
```

---

## Chain Role Matrix

| Chain Role       | Required Contracts                                                                          | Notes                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Source only      | `Governor`, `Treasury`, `SourceBridgeAdapter`, transport sender config                      | No destination executor needed unless chain also receives bridged commands |
| Destination only | `DestinationExecutor`, transport receiver adapter, `SafeWalletAdapter`, Safe module on Safe | No destination Treasury required                                           |
| Dual role        | both source + destination sets                                                              | Common in multi-DAO/multi-region setups                                    |

Important: `GovernorSafeModule` is required on any chain where Safe execution through module is used (source local safe ops and/or destination bridged safe ops).

---

## Contract Responsibilities

1. **SourceBridgeAdapter**

   - Called by source `Treasury` via governance-approved execution.
   - Encodes command envelope and routes through selected transport adapter.
   - Maintains per-DAO source-side nonceing and destination bindings.

2. **ITransportAdapter implementations**

   - Bridge-specific send/receive verification and decoding.
   - No DAO policy logic.

3. **DestinationExecutor (per DAO)**

   - Verifies source chain + source sender.
   - Enforces replay protection and optional deadline checks.
   - Maintains wallet whitelist and adapter configuration.
   - Dispatches commands to wallet adapter.

4. **SafeWalletAdapter**
   - Executes calls via Safe module path.
   - Restricts operation mode to `CALL` in v1 unless explicitly expanded.

---

## Destination Without Treasury

Destination chains do not require full Treasury contracts in this architecture.

Why:

1. Governance/timelock authority remains on source chain.
2. Destination only needs verified command execution.
3. Lower deployment and audit surface.
4. Easier extension to other wallet types.

---

## Safe Integration Model

For Safe execution on any destination chain, all of the following are required:

1. Safe exists on destination chain.
2. DAO module is deployed on that chain.
3. Module is enabled on that Safe.
4. DestinationExecutor wallet registry contains the Safe and points to `SafeWalletAdapter`.

Linking model:

- `DestinationExecutor.wallets[walletId].adapter` selects wallet adapter.
- For Safe wallets, adapter executes via enabled Safe module.

---

## Deterministic Safe Address Strategy

To preserve same Safe address across chains, deployment must keep invariants identical:

1. Safe factory/singleton/fallback/multisend assumptions.
2. Owners list order and threshold.
3. Initial module list.
4. Initializer bytes.
5. Salt/nonce strategy.

If any invariant differs, resulting Safe address may differ.

### Determinism and owner edits

- Deterministic parity is about initial deployment config.
- Later owner/threshold edits are local chain state changes.
- Those edits do not automatically propagate to other chains.
- If parity is required, governance must execute equivalent owner edits chain-by-chain.

---

## Message and Command Model

### Envelope

```solidity
struct BridgeEnvelope {
  bytes32 daoId;
  uint256 sourceChainId;
  uint256 destinationChainId;
  address sourceSender;
  uint64 nonce;
  uint64 deadline; // optional, 0 means no deadline
  bytes payload;
}

```

### Command types (v1)

```solidity
enum CommandType {
  EXECUTE,
  ADD_WALLET,
  UPDATE_WALLET,
  REMOVE_WALLET,
  SET_POLICY,
  SET_ADAPTER,
  SET_MODE
}

struct ExecuteCommand {
  uint32 walletId;
  address target;
  uint256 value;
  bytes data;
  uint8 operation;
}

```

---

## Replay Protection

```solidity
mapping(bytes32 => bool) public consumed;
```

Message key:

```text
keccak256(sourceChainId, sourceSender, nonce, keccak256(payload))
```

Rules:

1. Reject consumed messages.
2. Mark consumed before external wallet call.
3. Enforce deadline when non-zero.

---

## Destination Wallet Registry

```solidity
struct WalletConfig {
  address wallet;
  address adapter;
  address policy;
  bytes32 policyHash;
  bool active;
}

```

All wallet updates are source-authenticated command-driven actions.

---

## Managed vs Sovereign Control

### Modes

```solidity
enum BridgeMode {
  MANAGED,
  SOVEREIGN
}

```

### Intended semantics

- `MANAGED`:
  - Managed admin controls transport/policy infra configuration.
  - DAO source governance controls wallet lifecycle and execute commands.
- `SOVEREIGN`:
  - DAO source governance controls transport/policy/wallet configs.
  - Managed admin has no config mutation path.

### Two-way mode switching

- Support `MANAGED <-> SOVEREIGN`.
- Require mode-switch timelock and cooldown.
- Freeze sensitive config updates while switch is pending.
- Emit explicit mode switch events.

---

## Minimal Quorum-Ready Seam (Without v1 Complexity)

To preserve simplicity in v1:

1. Use single adapter verification policy by default (`threshold=1`).
2. Keep executor transport-agnostic.
3. Add a minimal policy hook interface for future upgrades.

```solidity
interface IVerificationPolicy {
  function isSatisfied(
    bytes32 msgKey,
    uint8 threshold,
    uint32 adapterSetVersion
  ) external view returns (bool);
}

```

Future quorum mode can be introduced by policy/config upgrade without rewriting executor core.

---

## Transport Abstraction

```solidity
interface ITransportAdapter {
  function sendMessage(
    uint256 dstChainId,
    bytes calldata envelope,
    bytes calldata options
  ) external returns (bytes32 messageId);

  function decodeMessage(bytes calldata transportMessage)
    external
    view
    returns (bytes memory envelope, bytes32 transportMsgId);
}

```

No bridge-protocol-specific branching in `DestinationExecutor`.

---

## Manager Integration

Manager maintains bridge implementation registries separate from core DAO contracts.

### Registry scope

1. `SourceBridgeAdapter` impls
2. `DestinationExecutor` impls
3. Transport adapter impls
4. Wallet adapter impls
5. Verification policy impls

### Managed deployment support

1. Deploy per-DAO destination executor.
2. Attach default transport and wallet adapters.
3. Register source<->destination bindings.

---

## Frontend UX Specification

## Treasury tab flow: Register Safe

1. Input Safe address and target chain.
2. Check module deployment (factory/subgraph lookup).
3. If needed, deploy module.
4. Prompt signer to enable module on Safe.
5. Verify module enabled onchain.
6. Create governance proposal to register wallet/executor binding.

## Optional flow: Create Safe + module enabled

1. User chooses signer set + threshold.
2. Frontend computes deterministic deployment config.
3. Safe is created with module enabled in initial setup.
4. User proceeds to governance registration step.

## Required readiness states

1. `executor_deployed`
2. `transport_configured`
3. `safe_deployed`
4. `module_deployed`
5. `module_enabled`
6. `wallet_registered`
7. `ready_for_funding`

If deterministic deployment fails on any chain, mark chain `not_initialized` and warn users not to fund there.

---

## Security Checklist

1. Verify transport adapter caller allowlist.
2. Verify source chain and source sender.
3. Enforce replay protection.
4. Enforce wallet whitelist + adapter allowlist.
5. Restrict operation mode (`CALL` only in v1).
6. Enforce pause path for incident response.
7. Emit complete audit events for receipt/config/execution.

---

## Event Model (Minimum)

```solidity
event MessageAccepted(bytes32 indexed msgKey, uint256 sourceChainId, address indexed sourceSender, uint64 nonce);
event MessageRejected(bytes32 indexed msgKey, bytes reason);

event WalletAdded(uint32 indexed walletId, address wallet, address adapter, address policy, bytes32 policyHash);
event WalletUpdated(uint32 indexed walletId, bool active, address adapter, address policy, bytes32 policyHash);
event WalletRemoved(uint32 indexed walletId, address wallet);

event BridgeModeChangeRequested(uint8 fromMode, uint8 toMode, uint64 eta);
event BridgeModeChanged(uint8 fromMode, uint8 toMode);

event CrossChainExecution(
    uint32 indexed walletId,
    address indexed target,
    uint256 value,
    uint8 operation,
    bool success,
    bytes returnData
);
```

---

## Phased Rollout

## Phase 1

1. SourceBridgeAdapter
2. DestinationExecutor (per DAO)
3. SafeWalletAdapter
4. One default transport adapter
5. Managed onboarding UI and readiness state machine

## Phase 2

1. Additional transport adapters
2. Fallback transport strategy
3. Policy enhancements

## Phase 3

1. Optional multi-bridge quorum policy mode
2. Additional wallet/vault adapters

---

## Open Decisions

1. Default mode for new managed installs (`MANAGED` expected).
2. Mode-switch timelock/cooldown values.
3. First default transport adapter.
   - Selected: LayerZero (in-repo default for v1).
4. Whether Safe module is bound to `(treasury, safe)` in v1 or v1.1.
