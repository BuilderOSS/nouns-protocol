# Frontend & Subgraph Integration Guide: Updatable Proposals

**Version:** Governor v2.1.0
**Target Audience:** Frontend Engineers & Subgraph Developers
**Last Updated:** 2026-05-27

This comprehensive guide details all events, functions, types, and integration requirements for both frontend applications and subgraph indexers supporting the Governor v2.1.0 upgrade with updatable proposals and signature-based sponsorship.

---

## Table of Contents

1. [Overview](#overview)
2. [Breaking Changes](#breaking-changes)
3. [Events Reference](#events-reference)
4. [Functions Reference](#functions-reference)
5. [Types & Enums](#types--enums)
6. [Subgraph Integration](#subgraph-integration)
7. [Frontend Integration](#frontend-integration)
8. [Signature Generation](#signature-generation)
9. [Testing & Validation](#testing--validation)

---

## Overview

### What's New in v2.1.0

- **Signed Proposals**: Create proposals with up to 16 signer sponsors
- **Proposal Updates**: Edit proposals during an updatable period
- **Flexible Signer Sets**: Update proposals with different signer combinations
- **ERC-1271 Support**: Smart contract wallet signature validation
- **New Proposal States**: `Updatable` and `Replaced` states
- **Enhanced Nonce System**: Separate nonces for votes and proposals

### Key Constants

```solidity
MIN_PROPOSAL_THRESHOLD_BPS = 1              // 0.01%
MAX_PROPOSAL_THRESHOLD_BPS = 1000           // 10%
MIN_QUORUM_THRESHOLD_BPS = 200              // 2%
MAX_QUORUM_THRESHOLD_BPS = 2000             // 20%
MIN_VOTING_DELAY = 1 seconds
MAX_VOTING_DELAY = 24 weeks
MIN_VOTING_PERIOD = 10 minutes
MAX_VOTING_PERIOD = 24 weeks
MAX_PROPOSAL_UPDATABLE_PERIOD = 24 weeks
DEFAULT_PROPOSAL_UPDATABLE_PERIOD = 1 days
MAX_PROPOSAL_SIGNERS = 16                   // Reduced from 32
MAX_DELAYED_GOVERNANCE_EXPIRATION = 30 days
BPS_PER_100_PERCENT = 10000                 // 100%
```

---

## Breaking Changes

### CRITICAL: `castVoteBySig` ABI Change

The function signature has changed from v1 to v2. **Old voting code will break immediately after upgrade.**

#### V1 (Old - DO NOT USE)
```solidity
function castVoteBySig(
    address voter,
    bytes32 proposalId,
    uint256 support,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
) external returns (uint256);
```

#### V2 (New - REQUIRED)
```solidity
function castVoteBySig(
    address voter,
    bytes32 proposalId,
    uint256 support,
    uint256 nonce,      // NEW: Added before deadline
    uint256 deadline,
    bytes calldata sig  // NEW: Replaces v,r,s
) external returns (uint256);
```

**Changes:**
1. Added `nonce` parameter (4th position)
2. Replaced `v, r, s` with single `bytes sig` parameter
3. Parameter order changed

---

## Events Reference

### NEW Events (v2.1.0)

#### 1. ProposalUpdated
Emitted when a proposal is updated and replaced with a new proposal ID.

```solidity
event ProposalUpdated(
    bytes32 oldProposalId,
    bytes32 newProposalId,
    address proposer,
    address[] targets,
    uint256[] values,
    bytes[] calldatas,
    string description,
    string updateMessage
);
```

**Subgraph Usage:**
- Track proposal replacement chains
- Store update history with messages
- Link old and new proposal entities

**Frontend Usage:**
- Display update notifications
- Show update message in proposal timeline
- Redirect users to latest proposal version

---

#### 2. ProposalSignersSet
Emitted when signers are registered for a signed proposal.

```solidity
event ProposalSignersSet(
    bytes32 proposalId,
    address[] signers
);
```

**Subgraph Usage:**
- Create Signer entities linked to proposals
- Index signer participation metrics
- Enable filtering proposals by signer

**Frontend Usage:**
- Display proposal sponsors
- Show signer badges/avatars
- Calculate total voting power behind proposal

---

#### 3. ProposalUpdatablePeriodUpdated
Emitted when the governance setting for updatable period changes.

```solidity
event ProposalUpdatablePeriodUpdated(
    uint256 prevProposalUpdatablePeriod,
    uint256 newProposalUpdatablePeriod
);
```

**Subgraph Usage:**
- Track governance parameter changes
- Store historical settings

**Frontend Usage:**
- Update UI calculations for proposal timelines
- Show governance setting changes

---

### Existing Events (Enhanced)

#### 4. ProposalCreated
```solidity
event ProposalCreated(
    bytes32 proposalId,
    address[] targets,
    uint256[] values,
    bytes[] calldatas,
    string description,
    bytes32 descriptionHash,
    Proposal proposal  // Struct with metadata
);
```

**Important:** The `Proposal` struct parameter contains:
```solidity
struct Proposal {
    address proposer;
    uint32 timeCreated;
    uint32 againstVotes;
    uint32 forVotes;
    uint32 abstainVotes;
    uint32 voteStart;
    uint32 voteEnd;
    uint32 proposalThreshold;
    uint32 quorumVotes;
    bool executed;
    bool canceled;
    bool vetoed;
}
```

---

#### 5. ProposalQueued
```solidity
event ProposalQueued(
    bytes32 proposalId,
    uint256 eta  // Estimated time of execution
);
```

---

#### 6. ProposalExecuted
```solidity
event ProposalExecuted(bytes32 proposalId);
```

---

#### 7. ProposalCanceled
```solidity
event ProposalCanceled(bytes32 proposalId);
```

---

#### 8. ProposalVetoed
```solidity
event ProposalVetoed(bytes32 proposalId);
```

---

#### 9. VoteCast
```solidity
event VoteCast(
    address voter,
    bytes32 proposalId,
    uint256 support,  // 0=Against, 1=For, 2=Abstain
    uint256 weight,   // Voting power used
    string reason     // Optional reason (empty string if none)
);
```

---

#### 10. VotingDelayUpdated
```solidity
event VotingDelayUpdated(
    uint256 prevVotingDelay,
    uint256 newVotingDelay
);
```

---

#### 11. VotingPeriodUpdated
```solidity
event VotingPeriodUpdated(
    uint256 prevVotingPeriod,
    uint256 newVotingPeriod
);
```

---

#### 12. ProposalThresholdBpsUpdated
```solidity
event ProposalThresholdBpsUpdated(
    uint256 prevBps,
    uint256 newBps
);
```

---

#### 13. QuorumVotesBpsUpdated
```solidity
event QuorumVotesBpsUpdated(
    uint256 prevBps,
    uint256 newBps
);
```

---

#### 14. VetoerUpdated
```solidity
event VetoerUpdated(
    address prevVetoer,
    address newVetoer
);
```

---

#### 15. DelayedGovernanceExpirationTimestampUpdated
```solidity
event DelayedGovernanceExpirationTimestampUpdated(
    uint256 prevTimestamp,
    uint256 newTimestamp
);
```

---

## Functions Reference

### NEW Functions (v2.1.0)

#### 1. proposeBySigs
Creates a proposal from msg.sender backed by offchain signer sponsorships.

```solidity
function proposeBySigs(
    ProposerSignature[] memory proposerSignatures,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
) external returns (bytes32);
```

**Parameters:**
- `proposerSignatures`: Array of sponsor signatures (max 16, sorted by signer address)
- `targets`: Array of contract addresses to call
- `values`: Array of ETH values for each call
- `calldatas`: Array of encoded function calls
- `description`: Proposal description (markdown supported)

**Returns:** New proposal ID (bytes32)

**Requirements:**
- Signers must be in ascending address order
- Proposer (msg.sender) cannot be a signer
- Total voting power (proposer + signers) must meet proposal threshold
- Each signature must be valid and not expired

---

#### 2. updateProposal
Updates an existing proposal during the updatable period (proposer-only, no signatures required).

```solidity
function updateProposal(
    bytes32 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description,
    string memory updateMessage
) external returns (bytes32);
```

**Parameters:**
- `proposalId`: ID of the proposal to update
- `targets`: New target addresses
- `values`: New ETH values
- `calldatas`: New calldata
- `description`: New description
- `updateMessage`: Human-readable reason for update

**Returns:** New proposal ID (bytes32)

**Requirements:**
- Caller must be the original proposer
- Proposal state must be `Updatable`
- Must be within updatable period
- Proposal must not have been created with signatures (use `updateProposalBySigs` instead)
- Update must actually change something (no-op updates rejected)

---

#### 3. updateProposalBySigs
Updates a signed proposal with new signer approvals.

```solidity
function updateProposalBySigs(
    bytes32 proposalId,
    ProposerSignature[] memory proposerSignatures,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description,
    string memory updateMessage
) external returns (bytes32);
```

**Parameters:**
- `proposalId`: ID of the proposal to update
- `proposerSignatures`: New set of sponsor signatures (can differ from original)
- `targets`: New target addresses
- `values`: New ETH values
- `calldatas`: New calldata
- `description`: New description
- `updateMessage`: Human-readable reason for update

**Returns:** New proposal ID (bytes32)

**Requirements:**
- Caller must be the original proposer
- Proposal state must be `Updatable`
- Original proposal must have been created with signatures
- New signers need not match original signers
- Total voting power must still meet proposal threshold

---

#### 4. getProposalSigners
Returns the addresses that sponsored a signed proposal.

```solidity
function getProposalSigners(bytes32 proposalId) external view returns (address[] memory);
```

**Returns:** Array of signer addresses (empty array if not a signed proposal)

---

#### 5. proposalUpdatePeriodEnd
Returns the timestamp until which a proposal can be updated.

```solidity
function proposalUpdatePeriodEnd(bytes32 proposalId) external view returns (uint256);
```

**Returns:** Unix timestamp (seconds)

**Usage:**
```javascript
const updateDeadline = await governor.proposalUpdatePeriodEnd(proposalId);
const canUpdate = Date.now() / 1000 < updateDeadline;
```

---

#### 6. proposalUpdatablePeriod
Returns the global setting for how long proposals are editable.

```solidity
function proposalUpdatablePeriod() external view returns (uint256);
```

**Returns:** Duration in seconds (default: 1 day)

---

#### 7. proposeSignatureNonce
Returns the current proposal-signature nonce for an account.

```solidity
function proposeSignatureNonce(address account) external view returns (uint256);
```

**Returns:** Current nonce (uint256)

**Note:** This is separate from `nonce(address)` which is for vote signatures.

---

#### 8. updateProposalUpdatablePeriod
Updates the governance setting for proposal updatable period.

```solidity
function updateProposalUpdatablePeriod(uint256 newProposalUpdatablePeriod) external;
```

**Requirements:**
- Only callable by governance (via proposal execution)
- Must be between 0 and `MAX_PROPOSAL_UPDATABLE_PERIOD` (24 weeks)

---

### Core Functions (Updated)

#### 9. propose
Standard proposal creation by a qualified proposer.

```solidity
function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
) external returns (bytes32);
```

**Requirements:**
- Caller must have voting power >= proposal threshold
- Cannot propose during delayed governance period

---

#### 10. castVote
Cast a vote on an active proposal.

```solidity
function castVote(
    bytes32 proposalId,
    uint256 support  // 0=Against, 1=For, 2=Abstain
) external returns (uint256);
```

**Returns:** Voter's voting weight

---

#### 11. castVoteWithReason
Cast a vote with an explanation.

```solidity
function castVoteWithReason(
    bytes32 proposalId,
    uint256 support,
    string memory reason
) external returns (uint256);
```

---

#### 12. castVoteBySig (NEW SIGNATURE)
Cast a vote using an EIP-712 signature.

```solidity
function castVoteBySig(
    address voter,
    bytes32 proposalId,
    uint256 support,
    uint256 nonce,      // NEW in v2
    uint256 deadline,
    bytes calldata sig  // NEW in v2 (replaces v,r,s)
) external returns (uint256);
```

**See Breaking Changes section for migration details.**

---

#### 13. queue
Queue a successful proposal for execution.

```solidity
function queue(bytes32 proposalId) external returns (uint256 eta);
```

**Requirements:**
- Proposal state must be `Succeeded`

---

#### 14. execute
Execute a queued proposal.

```solidity
function execute(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash,
    address proposer
) external payable returns (bytes32);
```

**Requirements:**
- Proposal must be queued
- Current time must be >= ETA
- Must provide original proposal parameters

---

#### 15. cancel
Cancel a proposal.

```solidity
function cancel(bytes32 proposalId) external;
```

**Requirements:**
- Callable by proposer OR
- Callable by anyone if proposer's voting power dropped below threshold

---

#### 16. veto
Veto a proposal (vetoer only).

```solidity
function veto(bytes32 proposalId) external;
```

**Requirements:**
- Caller must be the vetoer
- Proposal cannot already be executed

---

### View Functions

#### 17. state
Get the current state of a proposal.

```solidity
function state(bytes32 proposalId) external view returns (ProposalState);
```

**Returns:** ProposalState enum (0-10)

---

#### 18. getVotes
Get voting power of an account at a specific timestamp.

```solidity
function getVotes(address account, uint256 timestamp) external view returns (uint256);
```

---

#### 19. proposalThreshold
Get current minimum voting power needed to create a proposal.

```solidity
function proposalThreshold() external view returns (uint256);
```

**Calculation:** `(token.totalSupply() * proposalThresholdBps) / 10000`

---

#### 20. quorum
Get current minimum votes needed for a proposal to pass.

```solidity
function quorum() external view returns (uint256);
```

**Calculation:** `(token.totalSupply() * quorumThresholdBps) / 10000`

---

#### 21. getProposal
Get full proposal details.

```solidity
function getProposal(bytes32 proposalId) external view returns (Proposal memory);
```

---

#### 22. proposalSnapshot
Get timestamp when voting starts.

```solidity
function proposalSnapshot(bytes32 proposalId) external view returns (uint256);
```

---

#### 23. proposalDeadline
Get timestamp when voting ends.

```solidity
function proposalDeadline(bytes32 proposalId) external view returns (uint256);
```

---

#### 24. proposalVotes
Get vote tallies for a proposal.

```solidity
function proposalVotes(bytes32 proposalId) external view returns (
    uint256 againstVotes,
    uint256 forVotes,
    uint256 abstainVotes
);
```

---

#### 25. proposalEta
Get execution timestamp for a queued proposal.

```solidity
function proposalEta(bytes32 proposalId) external view returns (uint256);
```

---

#### Additional Getters

```solidity
function proposalThresholdBps() external view returns (uint256);
function quorumThresholdBps() external view returns (uint256);
function votingDelay() external view returns (uint256);
function votingPeriod() external view returns (uint256);
function vetoer() external view returns (address);
function token() external view returns (address);
function treasury() external view returns (address);
function nonce(address account) external view returns (uint256);  // For vote signatures
function VOTE_TYPEHASH() external view returns (bytes32);
```

---

## Types & Enums

### ProposalState Enum

```solidity
enum ProposalState {
    Pending,      // 0 - Updatable period ended, voting not started
    Active,       // 1 - Voting is open
    Canceled,     // 2 - Proposal was canceled
    Defeated,     // 3 - Proposal failed (didn't reach quorum or majority)
    Succeeded,    // 4 - Proposal passed, ready to queue
    Queued,       // 5 - Proposal queued in treasury
    Expired,      // 6 - Execution deadline passed
    Executed,     // 7 - Proposal was executed
    Vetoed,       // 8 - Proposal was vetoed
    Updatable,    // 9 - NEW: Proposal can be edited
    Replaced      // 10 - NEW: Proposal was replaced by an update
}
```

**State Transitions:**

```
Updatable → Pending → Active → Succeeded → Queued → Executed
                   ↓         ↓           ↓
                Canceled  Defeated    Expired
                   ↓         ↓           ↓
                Vetoed    Vetoed      Vetoed

Updatable → Replaced (when updated)
```

---

### Proposal Struct

```solidity
struct Proposal {
    address proposer;           // Creator address
    uint32 timeCreated;         // Creation timestamp
    uint32 againstVotes;        // Against vote count
    uint32 forVotes;            // For vote count
    uint32 abstainVotes;        // Abstain vote count
    uint32 voteStart;           // Voting start timestamp
    uint32 voteEnd;             // Voting end timestamp
    uint32 proposalThreshold;   // Required threshold at creation
    uint32 quorumVotes;         // Required quorum at creation
    bool executed;              // Execution flag
    bool canceled;              // Cancelation flag
    bool vetoed;                // Veto flag
}
```

---

### ProposerSignature Struct (NEW)

```solidity
struct ProposerSignature {
    address signer;     // Address of sponsor
    uint256 nonce;      // Current nonce for this signer
    uint256 deadline;   // Signature expiry timestamp
    bytes sig;          // EIP-712 signature bytes
}
```

---

### EIP-712 TypeHashes

```solidity
// Vote signature
VOTE_TYPEHASH = keccak256(
    "Vote(address voter,bytes32 proposalId,uint256 support,uint256 nonce,uint256 deadline)"
);

// Proposal signature (for proposeBySigs)
PROPOSAL_TYPEHASH = keccak256(
    "Proposal(address proposer,bytes32 proposalId,uint256 nonce,uint256 deadline)"
);

// Update signature (for updateProposalBySigs)
UPDATE_PROPOSAL_TYPEHASH = keccak256(
    "UpdateProposal(bytes32 proposalId,bytes32 updatedProposalId,address proposer,uint256 nonce,uint256 deadline)"
);
```

---

## Subgraph Integration

### Schema Updates Required

#### 1. Proposal Entity Enhancements

```graphql
type Proposal @entity {
  id: ID!  # proposalId (bytes32 as hex string)
  proposalNumber: BigInt!
  proposer: Bytes!
  targets: [Bytes!]!
  values: [BigInt!]!
  calldatas: [Bytes!]!
  description: String!
  descriptionHash: Bytes!
  createdAt: BigInt!
  updatedAt: BigInt  # NEW: Last update timestamp

  # NEW: Update tracking
  replacedBy: Proposal  # Points to newer version if updated
  replaces: Proposal    # Points to older version
  updateMessage: String # Reason for update
  updateCount: BigInt!  # Number of times updated

  # NEW: Signed proposal support
  signers: [ProposalSigner!]! @derivedFrom(field: "proposal")
  isSigned: Boolean!

  # State tracking
  state: ProposalState!

  # Timing
  updatePeriodEnd: BigInt!  # NEW
  voteStart: BigInt!
  voteEnd: BigInt!
  executionETA: BigInt

  # Voting
  forVotes: BigInt!
  againstVotes: BigInt!
  abstainVotes: BigInt!
  votes: [Vote!]! @derivedFrom(field: "proposal")
  quorum: BigInt!
  proposalThreshold: BigInt!

  # Terminal states
  queued: Boolean!
  executed: Boolean!
  canceled: Boolean!
  vetoed: Boolean!

  # Events
  events: [ProposalEvent!]! @derivedFrom(field: "proposal")
}
```

---

#### 2. ProposalSigner Entity (NEW)

```graphql
type ProposalSigner @entity {
  id: ID!  # proposalId-signerAddress
  proposal: Proposal!
  signer: Bytes!
  votingPower: BigInt!  # At time of signing
  timestamp: BigInt!
  signature: Bytes!
}
```

---

#### 3. ProposalEvent Entity

```graphql
enum ProposalEventType {
  CREATED
  UPDATED      # NEW
  QUEUED
  EXECUTED
  CANCELED
  VETOED
}

type ProposalEvent @entity {
  id: ID!  # txHash-logIndex
  proposal: Proposal!
  type: ProposalEventType!
  timestamp: BigInt!
  txHash: Bytes!

  # For UPDATED events
  updateMessage: String
  newProposalId: Bytes
}
```

---

#### 4. Vote Entity (No Changes)

```graphql
type Vote @entity {
  id: ID!  # proposalId-voterAddress
  proposal: Proposal!
  voter: Bytes!
  support: VoteType!
  weight: BigInt!
  reason: String
  timestamp: BigInt!
  txHash: Bytes!
}

enum VoteType {
  AGAINST
  FOR
  ABSTAIN
}
```

---

#### 5. GovernorSettings Entity Enhancement

```graphql
type GovernorSettings @entity {
  id: ID!  # "SETTINGS"
  votingDelay: BigInt!
  votingPeriod: BigInt!
  proposalThresholdBps: BigInt!
  quorumThresholdBps: BigInt!
  proposalUpdatablePeriod: BigInt!  # NEW
  vetoer: Bytes!

  # Historical tracking
  settingChanges: [SettingChange!]! @derivedFrom(field: "settings")
}
```

---

### Event Handler Updates

#### Handler: ProposalCreated

```typescript
export function handleProposalCreated(event: ProposalCreatedEvent): void {
  let proposal = new Proposal(event.params.proposalId.toHexString());

  proposal.proposalNumber = getNextProposalNumber();
  proposal.proposer = event.params.proposal.proposer;
  proposal.targets = event.params.targets;
  proposal.values = event.params.values;
  proposal.calldatas = event.params.calldatas;
  proposal.description = event.params.description;
  proposal.descriptionHash = event.params.descriptionHash;
  proposal.createdAt = event.block.timestamp;
  proposal.updatedAt = null;

  // NEW: Initialize update tracking
  proposal.replacedBy = null;
  proposal.replaces = null;
  proposal.updateMessage = null;
  proposal.updateCount = BigInt.fromI32(0);
  proposal.isSigned = false;

  // Calculate timestamps
  let governor = GovernorContract.bind(event.address);
  proposal.updatePeriodEnd = event.params.proposal.timeCreated.plus(
    governor.proposalUpdatablePeriod()
  );
  proposal.voteStart = event.params.proposal.voteStart;
  proposal.voteEnd = event.params.proposal.voteEnd;

  // Initialize vote counts
  proposal.forVotes = BigInt.fromI32(0);
  proposal.againstVotes = BigInt.fromI32(0);
  proposal.abstainVotes = BigInt.fromI32(0);
  proposal.quorum = event.params.proposal.quorumVotes;
  proposal.proposalThreshold = event.params.proposal.proposalThreshold;

  // Initialize state
  proposal.state = getProposalState(event.params.proposalId, governor);
  proposal.queued = false;
  proposal.executed = false;
  proposal.canceled = false;
  proposal.vetoed = false;

  proposal.save();

  // Create event
  createProposalEvent(
    event,
    proposal,
    "CREATED",
    null,
    null
  );
}
```

---

#### Handler: ProposalUpdated (NEW)

```typescript
export function handleProposalUpdated(event: ProposalUpdatedEvent): void {
  // Load old proposal
  let oldProposal = Proposal.load(event.params.oldProposalId.toHexString());
  if (!oldProposal) {
    log.warning("Old proposal {} not found for update", [
      event.params.oldProposalId.toHexString()
    ]);
    return;
  }

  // Mark old proposal as replaced
  oldProposal.replacedBy = event.params.newProposalId.toHexString();
  oldProposal.state = "REPLACED";
  oldProposal.save();

  // Create new proposal
  let newProposal = new Proposal(event.params.newProposalId.toHexString());

  // Inherit from old proposal
  newProposal.proposalNumber = oldProposal.proposalNumber;
  newProposal.proposer = event.params.proposer;
  newProposal.targets = event.params.targets;
  newProposal.values = event.params.values;
  newProposal.calldatas = event.params.calldatas;
  newProposal.description = event.params.description;
  newProposal.descriptionHash = Bytes.fromByteArray(
    crypto.keccak256(ByteArray.fromUTF8(event.params.description))
  );
  newProposal.createdAt = oldProposal.createdAt;  // Keep original creation time
  newProposal.updatedAt = event.block.timestamp;

  // Update tracking
  newProposal.replaces = oldProposal.id;
  newProposal.replacedBy = null;
  newProposal.updateMessage = event.params.updateMessage;
  newProposal.updateCount = oldProposal.updateCount.plus(BigInt.fromI32(1));
  newProposal.isSigned = oldProposal.isSigned;

  // Recalculate timestamps
  let governor = GovernorContract.bind(event.address);
  let proposalData = governor.getProposal(event.params.newProposalId);

  newProposal.updatePeriodEnd = proposalData.timeCreated.plus(
    governor.proposalUpdatablePeriod()
  );
  newProposal.voteStart = proposalData.voteStart;
  newProposal.voteEnd = proposalData.voteEnd;

  // Initialize vote counts
  newProposal.forVotes = BigInt.fromI32(0);
  newProposal.againstVotes = BigInt.fromI32(0);
  newProposal.abstainVotes = BigInt.fromI32(0);
  newProposal.quorum = proposalData.quorumVotes;
  newProposal.proposalThreshold = proposalData.proposalThreshold;

  // Initialize state
  newProposal.state = getProposalState(event.params.newProposalId, governor);
  newProposal.queued = false;
  newProposal.executed = false;
  newProposal.canceled = false;
  newProposal.vetoed = false;

  newProposal.save();

  // Create event
  createProposalEvent(
    event,
    newProposal,
    "UPDATED",
    event.params.updateMessage,
    event.params.newProposalId
  );
}
```

---

#### Handler: ProposalSignersSet (NEW)

```typescript
export function handleProposalSignersSet(event: ProposalSignersSetEvent): void {
  let proposal = Proposal.load(event.params.proposalId.toHexString());
  if (!proposal) {
    log.warning("Proposal {} not found for signers", [
      event.params.proposalId.toHexString()
    ]);
    return;
  }

  // Mark as signed proposal
  proposal.isSigned = true;
  proposal.save();

  // Create signer entities
  let governor = GovernorContract.bind(event.address);
  let token = TokenContract.bind(governor.token());

  for (let i = 0; i < event.params.signers.length; i++) {
    let signer = event.params.signers[i];
    let signerId = event.params.proposalId.toHexString() + "-" + signer.toHexString();

    let proposalSigner = new ProposalSigner(signerId);
    proposalSigner.proposal = proposal.id;
    proposalSigner.signer = signer;
    proposalSigner.votingPower = token.getVotes(signer, proposal.voteStart);
    proposalSigner.timestamp = event.block.timestamp;
    proposalSigner.signature = Bytes.empty();  // Not stored on-chain

    proposalSigner.save();
  }
}
```

---

#### Handler: ProposalUpdatablePeriodUpdated (NEW)

```typescript
export function handleProposalUpdatablePeriodUpdated(
  event: ProposalUpdatablePeriodUpdatedEvent
): void {
  let settings = loadOrCreateSettings();

  settings.proposalUpdatablePeriod = event.params.newProposalUpdatablePeriod;
  settings.save();

  // Track change
  createSettingChange(
    event,
    "PROPOSAL_UPDATABLE_PERIOD",
    event.params.prevProposalUpdatablePeriod,
    event.params.newProposalUpdatablePeriod
  );
}
```

---

### Helper: Get Proposal State

```typescript
function getProposalState(proposalId: Bytes, governor: GovernorContract): string {
  let stateInt = governor.state(proposalId);

  // Map integer to enum string
  if (stateInt == 0) return "PENDING";
  if (stateInt == 1) return "ACTIVE";
  if (stateInt == 2) return "CANCELED";
  if (stateInt == 3) return "DEFEATED";
  if (stateInt == 4) return "SUCCEEDED";
  if (stateInt == 5) return "QUEUED";
  if (stateInt == 6) return "EXPIRED";
  if (stateInt == 7) return "EXECUTED";
  if (stateInt == 8) return "VETOED";
  if (stateInt == 9) return "UPDATABLE";
  if (stateInt == 10) return "REPLACED";

  return "UNKNOWN";
}
```

---

### Subgraph Queries

#### Get Latest Proposal Version

```graphql
query GetLatestProposal($proposalId: ID!) {
  proposal(id: $proposalId) {
    id
    replacedBy {
      id
      replacedBy {
        id
        # Chain continues...
      }
    }
  }
}
```

#### Get Proposal Update History

```graphql
query GetProposalHistory($proposalNumber: BigInt!) {
  proposals(
    where: { proposalNumber: $proposalNumber }
    orderBy: updatedAt
    orderDirection: asc
  ) {
    id
    description
    updateMessage
    updatedAt
    state
    replaces {
      id
    }
    replacedBy {
      id
    }
  }
}
```

#### Get Signed Proposals

```graphql
query GetSignedProposals {
  proposals(where: { isSigned: true }) {
    id
    description
    proposer
    signers {
      signer
      votingPower
    }
  }
}
```

#### Get Proposals by Signer

```graphql
query GetProposalsBySigner($signer: Bytes!) {
  proposalSigners(where: { signer: $signer }) {
    proposal {
      id
      description
      state
      proposer
    }
    votingPower
  }
}
```

---

## Frontend Integration

### 1. Proposal Timeline Calculation

```typescript
interface ProposalTimeline {
  created: Date;
  updateDeadline: Date;
  votingStarts: Date;
  votingEnds: Date;
  executionETA: Date | null;
}

async function getProposalTimeline(
  governor: Contract,
  proposalId: string
): Promise<ProposalTimeline> {
  const proposal = await governor.getProposal(proposalId);
  const updatePeriodEnd = await governor.proposalUpdatePeriodEnd(proposalId);
  const eta = await governor.proposalEta(proposalId);

  return {
    created: new Date(proposal.timeCreated.toNumber() * 1000),
    updateDeadline: new Date(updatePeriodEnd.toNumber() * 1000),
    votingStarts: new Date(proposal.voteStart.toNumber() * 1000),
    votingEnds: new Date(proposal.voteEnd.toNumber() * 1000),
    executionETA: eta.gt(0) ? new Date(eta.toNumber() * 1000) : null
  };
}
```

---

### 2. Proposal State Display

```typescript
const ProposalStateConfig = {
  PENDING: {
    label: 'Pending',
    color: 'gray',
    description: 'Waiting for voting to begin'
  },
  ACTIVE: {
    label: 'Active',
    color: 'blue',
    description: 'Voting in progress'
  },
  CANCELED: {
    label: 'Canceled',
    color: 'red',
    description: 'Proposal was canceled'
  },
  DEFEATED: {
    label: 'Defeated',
    color: 'red',
    description: 'Proposal did not pass'
  },
  SUCCEEDED: {
    label: 'Succeeded',
    color: 'green',
    description: 'Proposal passed, ready to queue'
  },
  QUEUED: {
    label: 'Queued',
    color: 'yellow',
    description: 'Queued for execution'
  },
  EXPIRED: {
    label: 'Expired',
    color: 'gray',
    description: 'Execution window passed'
  },
  EXECUTED: {
    label: 'Executed',
    color: 'green',
    description: 'Proposal was executed'
  },
  VETOED: {
    label: 'Vetoed',
    color: 'red',
    description: 'Proposal was vetoed'
  },
  UPDATABLE: {
    label: 'Updatable',
    color: 'purple',
    description: 'Proposal can be edited'
  },
  REPLACED: {
    label: 'Replaced',
    color: 'orange',
    description: 'Proposal was updated'
  }
};

function ProposalStateBadge({ state }: { state: number }) {
  const stateNames = [
    'PENDING', 'ACTIVE', 'CANCELED', 'DEFEATED', 'SUCCEEDED',
    'QUEUED', 'EXPIRED', 'EXECUTED', 'VETOED', 'UPDATABLE', 'REPLACED'
  ];

  const stateName = stateNames[state];
  const config = ProposalStateConfig[stateName];

  return (
    <span className={`badge badge-${config.color}`} title={config.description}>
      {config.label}
    </span>
  );
}
```

---

### 3. Follow Proposal Replacement Chain

```typescript
async function getLatestProposalVersion(
  governor: Contract,
  proposalId: string
): Promise<string> {
  let currentId = proposalId;
  let replacedBy = await governor.proposalIdReplacedBy(currentId);

  // Follow chain to latest version
  while (replacedBy !== ethers.constants.HashZero) {
    currentId = replacedBy;
    replacedBy = await governor.proposalIdReplacedBy(currentId);
  }

  return currentId;
}

// Usage in component
useEffect(() => {
  async function redirectToLatest() {
    const latestId = await getLatestProposalVersion(governor, proposalId);
    if (latestId !== proposalId) {
      // Redirect or show warning
      router.push(`/proposals/${latestId}`);
    }
  }
  redirectToLatest();
}, [proposalId]);
```

---

### 4. Check Update Permissions

```typescript
async function canUpdateProposal(
  governor: Contract,
  proposalId: string,
  userAddress: string
): Promise<{ canUpdate: boolean; reason?: string }> {
  // Check state
  const state = await governor.state(proposalId);
  if (state !== 9) { // Not UPDATABLE
    return { canUpdate: false, reason: 'Proposal is no longer updatable' };
  }

  // Check if user is proposer
  const proposal = await governor.getProposal(proposalId);
  if (proposal.proposer.toLowerCase() !== userAddress.toLowerCase()) {
    return { canUpdate: false, reason: 'Only the proposer can update' };
  }

  // Check time window
  const updateDeadline = await governor.proposalUpdatePeriodEnd(proposalId);
  const now = Math.floor(Date.now() / 1000);
  if (now > updateDeadline.toNumber()) {
    return { canUpdate: false, reason: 'Update period has ended' };
  }

  return { canUpdate: true };
}
```

---

### 5. Display Proposal Signers

```typescript
interface ProposalSigner {
  address: string;
  votingPower: BigNumber;
  ensName?: string;
}

async function getProposalSigners(
  governor: Contract,
  token: Contract,
  proposalId: string,
  provider: Provider
): Promise<ProposalSigner[]> {
  const signers = await governor.getProposalSigners(proposalId);
  const proposal = await governor.getProposal(proposalId);

  const signersWithData = await Promise.all(
    signers.map(async (address) => {
      const votingPower = await token.getVotes(address, proposal.voteStart);
      const ensName = await provider.lookupAddress(address);

      return {
        address,
        votingPower,
        ensName: ensName || undefined
      };
    })
  );

  return signersWithData;
}

// Component
function ProposalSigners({ proposalId }: { proposalId: string }) {
  const [signers, setSigners] = useState<ProposalSigner[]>([]);

  useEffect(() => {
    getProposalSigners(governor, token, proposalId, provider)
      .then(setSigners);
  }, [proposalId]);

  if (signers.length === 0) return null;

  return (
    <div className="proposal-signers">
      <h3>Sponsored by {signers.length} signer{signers.length > 1 ? 's' : ''}</h3>
      <ul>
        {signers.map(signer => (
          <li key={signer.address}>
            <Address address={signer.address} ensName={signer.ensName} />
            <span className="voting-power">
              {ethers.utils.formatUnits(signer.votingPower, 0)} votes
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

---

## Signature Generation

### 1. Vote Signature (Updated for v2)

```typescript
import { ethers } from 'ethers';

interface VoteSignature {
  voter: string;
  proposalId: string;
  support: number;
  nonce: ethers.BigNumber;
  deadline: number;
  sig: string;
}

async function generateVoteSignature(
  governor: ethers.Contract,
  token: ethers.Contract,
  signer: ethers.Signer,
  proposalId: string,
  support: 0 | 1 | 2,  // 0=Against, 1=For, 2=Abstain
  deadlineMinutes: number = 60
): Promise<VoteSignature> {
  const voter = await signer.getAddress();
  const chainId = (await signer.provider!.getNetwork()).chainId;

  // Get token symbol for domain
  const symbol = await token.symbol();

  // Get current nonce
  const nonce = await governor.nonce(voter);

  // Set deadline
  const deadline = Math.floor(Date.now() / 1000) + (deadlineMinutes * 60);

  // EIP-712 domain
  const domain = {
    name: `${symbol} GOV`,
    version: '1',
    chainId: chainId,
    verifyingContract: governor.address
  };

  // EIP-712 types
  const types = {
    Vote: [
      { name: 'voter', type: 'address' },
      { name: 'proposalId', type: 'bytes32' },
      { name: 'support', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };

  // Message
  const value = {
    voter,
    proposalId,
    support,
    nonce,
    deadline
  };

  // Sign (ethers v5)
  const sig = await signer._signTypedData(domain, types, value);

  return {
    voter,
    proposalId,
    support,
    nonce,
    deadline,
    sig
  };
}

// Submit vote signature
async function submitVoteSignature(
  governor: ethers.Contract,
  voteSignature: VoteSignature
): Promise<ethers.ContractTransaction> {
  return governor.castVoteBySig(
    voteSignature.voter,
    voteSignature.proposalId,
    voteSignature.support,
    voteSignature.nonce,
    voteSignature.deadline,
    voteSignature.sig
  );
}
```

---

### 2. Proposal Signature (NEW)

```typescript
interface ProposalSignature {
  signer: string;
  proposer: string;
  proposalId: string;
  nonce: ethers.BigNumber;
  deadline: number;
  sig: string;
}

async function generateProposalSignature(
  governor: ethers.Contract,
  token: ethers.Contract,
  signer: ethers.Signer,
  proposer: string,
  targets: string[],
  values: ethers.BigNumber[],
  calldatas: string[],
  description: string,
  deadlineMinutes: number = 60
): Promise<ProposalSignature> {
  const signerAddress = await signer.getAddress();
  const chainId = (await signer.provider!.getNetwork()).chainId;

  // Calculate proposal ID
  const descriptionHash = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(description)
  );
  const proposalId = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['address[]', 'uint256[]', 'bytes[]', 'bytes32', 'address'],
      [targets, values, calldatas, descriptionHash, proposer]
    )
  );

  // Get token symbol
  const symbol = await token.symbol();

  // Get current nonce
  const nonce = await governor.proposeSignatureNonce(signerAddress);

  // Set deadline
  const deadline = Math.floor(Date.now() / 1000) + (deadlineMinutes * 60);

  // EIP-712 domain
  const domain = {
    name: `${symbol} GOV`,
    version: '1',
    chainId: chainId,
    verifyingContract: governor.address
  };

  // EIP-712 types
  const types = {
    Proposal: [
      { name: 'proposer', type: 'address' },
      { name: 'proposalId', type: 'bytes32' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };

  // Message
  const value = {
    proposer,
    proposalId,
    nonce,
    deadline
  };

  // Sign
  const sig = await signer._signTypedData(domain, types, value);

  return {
    signer: signerAddress,
    proposer,
    proposalId,
    nonce,
    deadline,
    sig
  };
}

// Collect multiple signatures and submit
async function createSignedProposal(
  governor: ethers.Contract,
  proposerSigner: ethers.Signer,
  sponsorSigners: ethers.Signer[],
  targets: string[],
  values: ethers.BigNumber[],
  calldatas: string[],
  description: string
): Promise<ethers.ContractTransaction> {
  const proposer = await proposerSigner.getAddress();

  // Collect signatures from sponsors
  const signatures = await Promise.all(
    sponsorSigners.map(signer =>
      generateProposalSignature(
        governor,
        token,
        signer,
        proposer,
        targets,
        values,
        calldatas,
        description
      )
    )
  );

  // Sort by signer address (REQUIRED)
  signatures.sort((a, b) =>
    a.signer.toLowerCase() < b.signer.toLowerCase() ? -1 : 1
  );

  // Format for contract
  const proposerSignatures = signatures.map(sig => ({
    signer: sig.signer,
    nonce: sig.nonce,
    deadline: sig.deadline,
    sig: sig.sig
  }));

  // Submit with proposer's wallet
  return governor.connect(proposerSigner).proposeBySigs(
    proposerSignatures,
    targets,
    values,
    calldatas,
    description
  );
}
```

---

### 3. Update Proposal Signature (NEW)

```typescript
interface UpdateProposalSignature {
  signer: string;
  proposer: string;
  oldProposalId: string;
  newProposalId: string;
  nonce: ethers.BigNumber;
  deadline: number;
  sig: string;
}

async function generateUpdateSignature(
  governor: ethers.Contract,
  token: ethers.Contract,
  signer: ethers.Signer,
  proposer: string,
  oldProposalId: string,
  newTargets: string[],
  newValues: ethers.BigNumber[],
  newCalldatas: string[],
  newDescription: string,
  deadlineMinutes: number = 60
): Promise<UpdateProposalSignature> {
  const signerAddress = await signer.getAddress();
  const chainId = (await signer.provider!.getNetwork()).chainId;

  // Calculate new proposal ID
  const newDescriptionHash = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(newDescription)
  );
  const newProposalId = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['address[]', 'uint256[]', 'bytes[]', 'bytes32', 'address'],
      [newTargets, newValues, newCalldatas, newDescriptionHash, proposer]
    )
  );

  // Get token symbol
  const symbol = await token.symbol();

  // Get current nonce
  const nonce = await governor.proposeSignatureNonce(signerAddress);

  // Set deadline
  const deadline = Math.floor(Date.now() / 1000) + (deadlineMinutes * 60);

  // EIP-712 domain
  const domain = {
    name: `${symbol} GOV`,
    version: '1',
    chainId: chainId,
    verifyingContract: governor.address
  };

  // EIP-712 types
  const types = {
    UpdateProposal: [
      { name: 'proposalId', type: 'bytes32' },
      { name: 'updatedProposalId', type: 'bytes32' },
      { name: 'proposer', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };

  // Message
  const value = {
    proposalId: oldProposalId,
    updatedProposalId: newProposalId,
    proposer,
    nonce,
    deadline
  };

  // Sign
  const sig = await signer._signTypedData(domain, types, value);

  return {
    signer: signerAddress,
    proposer,
    oldProposalId,
    newProposalId,
    nonce,
    deadline,
    sig
  };
}
```

---

### 4. Ethers v6 Compatibility

```typescript
// For ethers v6, use signTypedData instead of _signTypedData
import { ethers } from 'ethers'; // v6

// Replace this line:
const sig = await signer._signTypedData(domain, types, value);

// With this:
const sig = await signer.signTypedData(domain, types, value);
```

---

## Testing & Validation

### Frontend Test Checklist

- [ ] Vote signature generation (v2 format)
- [ ] Vote signature submission
- [ ] Expired vote signature rejection
- [ ] Invalid nonce rejection
- [ ] Proposal signature generation
- [ ] Multi-signer collection and sorting
- [ ] Signed proposal creation
- [ ] Proposal update (non-signed)
- [ ] Proposal update (signed with new signers)
- [ ] Proposal state display (all 11 states)
- [ ] Proposal timeline calculation
- [ ] Updatable period countdown
- [ ] Replacement chain following
- [ ] Signer display with voting power
- [ ] ERC-1271 signature support

---

### Subgraph Test Checklist

- [ ] ProposalCreated event indexing
- [ ] ProposalUpdated event indexing
- [ ] ProposalSignersSet event indexing
- [ ] Proposal replacement chain tracking
- [ ] Update count tracking
- [ ] Signer entity creation
- [ ] State transition tracking
- [ ] Timeline recalculation on updates
- [ ] Settings updates
- [ ] Query: Get latest proposal version
- [ ] Query: Get proposal history
- [ ] Query: Get signed proposals
- [ ] Query: Get proposals by signer

---

### Test Script Examples

#### Test Vote Signature

```typescript
import { ethers } from 'ethers';
import GovernorABI from './abis/Governor.json';

async function testVoteSignature() {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(PRIVATE_KEY, provider);
  const governor = new ethers.Contract(GOVERNOR_ADDRESS, GovernorABI, signer);
  const token = new ethers.Contract(TOKEN_ADDRESS, TokenABI, signer);

  const proposalId = '0x...';
  const support = 1; // For

  console.log('Generating vote signature...');
  const voteSig = await generateVoteSignature(
    governor,
    token,
    signer,
    proposalId,
    support,
    60
  );

  console.log('Vote signature:', voteSig);

  console.log('Submitting vote...');
  const tx = await submitVoteSignature(governor, voteSig);

  console.log('Transaction:', tx.hash);
  const receipt = await tx.wait();

  console.log('Vote cast successfully!', receipt.status === 1 ? '✅' : '❌');
}
```

---

#### Test Signed Proposal Creation

```typescript
async function testSignedProposal() {
  const proposer = new ethers.Wallet(PROPOSER_KEY, provider);
  const signer1 = new ethers.Wallet(SIGNER1_KEY, provider);
  const signer2 = new ethers.Wallet(SIGNER2_KEY, provider);

  const targets = [TREASURY_ADDRESS];
  const values = [ethers.utils.parseEther('1')];
  const calldatas = ['0x'];
  const description = 'Test signed proposal';

  console.log('Creating signed proposal...');
  const tx = await createSignedProposal(
    governor,
    proposer,
    [signer1, signer2],
    targets,
    values,
    calldatas,
    description
  );

  console.log('Transaction:', tx.hash);
  const receipt = await tx.wait();

  // Extract proposal ID from event
  const event = receipt.events?.find(e => e.event === 'ProposalCreated');
  const proposalId = event?.args?.proposalId;

  console.log('Proposal created!', proposalId);

  // Verify signers
  const signers = await governor.getProposalSigners(proposalId);
  console.log('Signers:', signers);
}
```

---

## Migration Checklist

### Subgraph Migration
- [ ] Update schema with new entities (ProposalSigner)
- [ ] Add new fields to Proposal entity
- [ ] Add ProposalUpdated event handler
- [ ] Add ProposalSignersSet event handler
- [ ] Add ProposalUpdatablePeriodUpdated handler
- [ ] Update state calculation logic
- [ ] Add replacement chain tracking
- [ ] Test queries for proposal history
- [ ] Test queries for signed proposals
- [ ] Deploy and sync subgraph

### Frontend Migration
- [ ] Update Governor ABI
- [ ] Update castVoteBySig implementation
- [ ] Add proposal update UI
- [ ] Add signed proposal creation UI
- [ ] Update proposal state display (add 2 new states)
- [ ] Add proposal timeline with update period
- [ ] Add replacement redirect logic
- [ ] Add signer display component
- [ ] Update nonce fetching (separate for votes/proposals)
- [ ] Test vote signatures (new format)
- [ ] Test proposal signatures
- [ ] Test update signatures
- [ ] Coordinate deployment with contract upgrade

---

## Support & Resources

- **Contract Source**: `src/governance/governor/Governor.sol`
- **Interface**: `src/governance/governor/IGovernor.sol`
- **Architecture**: `docs/governor-architecture.md`
- **Lifecycle**: `docs/governor-proposal-lifecycle.md`
- **Upgrade Runbook**: `docs/upgrade-runbook.md`

For questions or issues, please refer to the protocol documentation or open an issue in the repository.

---

**Document Version:** 1.0.0
**Contract Version:** Governor v2.1.0
**Last Updated:** 2026-05-27
