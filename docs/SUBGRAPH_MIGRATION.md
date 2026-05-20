# Subgraph Migration Guide: Governor v2.1.0

**Target:** Governor upgrades with updatable proposals and signed sponsorship
**Priority:** P1 - Required for mainnet launch
**Complexity:** Medium (new entities + relationships)

---

## Overview

The Governor v2.1.0 upgrade introduces:
- Signed proposal creation (`proposeBySigs`)
- Proposal updates with revision tracking
- New proposal state: `Replaced`
- Signer sponsorship tracking

**Breaking changes:**
- Proposal IDs change when proposals are updated
- Need to track proposal revision history
- New events to index

---

## New Events to Index

### 1. ProposalSignersSet
```solidity
event ProposalSignersSet(bytes32 proposalId, address[] signers);
```

**When emitted:** After `proposeBySigs` creates a signed proposal

**What to index:**
- Link signers to proposal
- Store signer order (important for validation)
- Track sponsorship relationships

### 2. ProposalUpdated
```solidity
event ProposalUpdated(
    bytes32 oldProposalId,
    bytes32 newProposalId,
    address[] targets,
    uint256[] values,
    bytes[] calldatas,
    string description,
    string updateMessage
);
```

**When emitted:** After `updateProposal` or `updateProposalBySigs`

**What to index:**
- Create new proposal entity for `newProposalId`
- Mark `oldProposalId` as replaced
- Link old → new in revision chain
- Store update message for history

### 3. ProposalUpdatablePeriodUpdated
```solidity
event ProposalUpdatablePeriodUpdated(
    uint256 prevProposalUpdatablePeriod,
    uint256 newProposalUpdatablePeriod
);
```

**When emitted:** When DAO updates the updatable period setting

**What to index:**
- Track governor configuration changes
- Useful for analytics/governance dashboards

---

## Schema Updates

### New Entities

#### ProposalSigner
```graphql
type ProposalSigner @entity {
  id: ID! # proposalId-signerAddress
  proposal: Proposal!
  signer: Account!
  position: Int! # Order in signer array (important!)
  timestamp: BigInt!
  txHash: Bytes!
}
```

#### ProposalRevision
```graphql
type ProposalRevision @entity {
  id: ID! # oldProposalId-newProposalId
  oldProposal: Proposal!
  newProposal: Proposal!
  updateMessage: String!
  timestamp: BigInt!
  txHash: Bytes!
}
```

### Modified Entities

#### Proposal (additions)
```graphql
type Proposal @entity {
  id: ID! # proposalId
  # ... existing fields ...

  # NEW FIELDS
  signers: [ProposalSigner!]! @derivedFrom(field: "proposal")
  replacedBy: Proposal # null if not replaced
  replacesProposal: Proposal # null if original proposal
  revisionHistory: [ProposalRevision!]! @derivedFrom(field: "oldProposal")
  updatePeriodEnd: BigInt # timestamp when updates stop
  state: ProposalState! # now includes "REPLACED"
}
```

#### ProposalState (enum update)
```graphql
enum ProposalState {
  PENDING
  ACTIVE
  CANCELED
  DEFEATED
  SUCCEEDED
  QUEUED
  EXPIRED
  EXECUTED
  VETOED
  UPDATABLE  # NEW
  REPLACED   # NEW
}
```

#### Governor (additions)
```graphql
type Governor @entity {
  id: ID! # governor address
  # ... existing fields ...

  # NEW FIELDS
  proposalUpdatablePeriod: BigInt!
}
```

---

## Handler Functions

### handleProposalSignersSet
```typescript
import { ProposalSignersSet } from "../generated/Governor/Governor";
import { ProposalSigner, Proposal, Account } from "../generated/schema";

export function handleProposalSignersSet(event: ProposalSignersSet): void {
  let proposal = Proposal.load(event.params.proposalId.toHexString());
  if (!proposal) {
    log.error("Proposal not found for ProposalSignersSet: {}", [
      event.params.proposalId.toHexString(),
    ]);
    return;
  }

  let signers = event.params.signers;

  for (let i = 0; i < signers.length; i++) {
    let signerId = event.params.proposalId
      .toHexString()
      .concat("-")
      .concat(signers[i].toHexString());

    let proposalSigner = new ProposalSigner(signerId);
    proposalSigner.proposal = proposal.id;
    proposalSigner.signer = signers[i].toHexString();
    proposalSigner.position = i;
    proposalSigner.timestamp = event.block.timestamp;
    proposalSigner.txHash = event.transaction.hash;

    proposalSigner.save();

    // Ensure Account entity exists
    let account = Account.load(signers[i].toHexString());
    if (!account) {
      account = new Account(signers[i].toHexString());
      account.save();
    }
  }
}
```

### handleProposalUpdated
```typescript
import { ProposalUpdated } from "../generated/Governor/Governor";
import { Proposal, ProposalRevision } from "../generated/schema";

export function handleProposalUpdated(event: ProposalUpdated): void {
  let oldProposal = Proposal.load(event.params.oldProposalId.toHexString());
  if (!oldProposal) {
    log.error("Old proposal not found for ProposalUpdated: {}", [
      event.params.oldProposalId.toHexString(),
    ]);
    return;
  }

  // Mark old proposal as replaced
  oldProposal.state = "REPLACED";
  oldProposal.replacedBy = event.params.newProposalId.toHexString();
  oldProposal.save();

  // Create new proposal entity (ProposalCreated event should handle most fields)
  // But we need to link it here
  let newProposal = Proposal.load(event.params.newProposalId.toHexString());
  if (!newProposal) {
    // Edge case: if ProposalUpdated fires before ProposalCreated is indexed
    log.warning("New proposal not yet indexed for ProposalUpdated: {}", [
      event.params.newProposalId.toHexString(),
    ]);
    return;
  }

  newProposal.replacesProposal = oldProposal.id;
  newProposal.save();

  // Create revision entity
  let revisionId = event.params.oldProposalId
    .toHexString()
    .concat("-")
    .concat(event.params.newProposalId.toHexString());

  let revision = new ProposalRevision(revisionId);
  revision.oldProposal = oldProposal.id;
  revision.newProposal = newProposal.id;
  revision.updateMessage = event.params.updateMessage;
  revision.timestamp = event.block.timestamp;
  revision.txHash = event.transaction.hash;

  revision.save();
}
```

### handleProposalUpdatablePeriodUpdated
```typescript
import { ProposalUpdatablePeriodUpdated } from "../generated/Governor/Governor";
import { Governor } from "../generated/schema";

export function handleProposalUpdatablePeriodUpdated(
  event: ProposalUpdatablePeriodUpdated
): void {
  let governor = Governor.load(event.address.toHexString());
  if (!governor) {
    log.error("Governor not found: {}", [event.address.toHexString()]);
    return;
  }

  governor.proposalUpdatablePeriod = event.params.newProposalUpdatablePeriod;
  governor.save();
}
```

### Update handleProposalCreated
```typescript
// Add to existing ProposalCreated handler:
export function handleProposalCreated(event: ProposalCreated): void {
  // ... existing code ...

  // NEW: Set updatePeriodEnd timestamp
  let governorContract = GovernorContract.bind(event.address);
  let updatePeriodEnd = governorContract.proposalUpdatePeriodEnd(event.params.proposalId);

  proposal.updatePeriodEnd = updatePeriodEnd;

  // NEW: Initialize state based on current time
  if (event.block.timestamp < updatePeriodEnd) {
    proposal.state = "UPDATABLE";
  } else if (event.block.timestamp < proposal.voteStart) {
    proposal.state = "PENDING";
  } else {
    proposal.state = "ACTIVE";
  }

  proposal.save();
}
```

---

## Example Queries

### 1. Get Current Version of a Proposal
```graphql
query GetCurrentProposal($proposalId: ID!) {
  proposal(id: $proposalId) {
    id
    state
    replacedBy {
      id
      # Recursively follow replacement chain
      replacedBy {
        id
      }
    }
  }
}
```

**Client-side logic:**
```typescript
function getCurrentProposalId(proposalId: string, data: any): string {
  let current = data.proposal;
  while (current?.replacedBy) {
    current = current.replacedBy;
  }
  return current.id;
}
```

### 2. Get Full Revision History
```graphql
query GetProposalRevisions($proposalId: ID!) {
  proposal(id: $proposalId) {
    id
    description
    revisionHistory(orderBy: timestamp, orderDirection: asc) {
      newProposal {
        id
        description
        updateMessage
        timestamp
      }
    }
  }
}
```

### 3. Get All Proposals by Signer
```graphql
query GetProposalsBySigner($signerAddress: ID!) {
  proposalSigners(where: { signer: $signerAddress }) {
    proposal {
      id
      description
      state
      proposer {
        id
      }
      timestamp
    }
    position
  }
}
```

### 4. Get Proposals Pending Update
```graphql
query GetUpdatableProposals($currentTimestamp: BigInt!) {
  proposals(
    where: {
      state: "UPDATABLE"
      updatePeriodEnd_gt: $currentTimestamp
    }
    orderBy: timestamp
    orderDirection: desc
  ) {
    id
    description
    proposer {
      id
    }
    updatePeriodEnd
    signers {
      signer {
        id
      }
    }
  }
}
```

### 5. Get Proposal with All Metadata
```graphql
query GetProposalDetails($proposalId: ID!) {
  proposal(id: $proposalId) {
    id
    description
    state
    proposer {
      id
    }
    signers {
      signer {
        id
      }
      position
    }
    replacedBy {
      id
    }
    replacesProposal {
      id
    }
    revisionHistory {
      newProposal {
        id
        description
      }
      updateMessage
      timestamp
    }
    voteStart
    voteEnd
    updatePeriodEnd
    forVotes
    againstVotes
    abstainVotes
  }
}
```

### 6. Get Governor Configuration
```graphql
query GetGovernorConfig($governorAddress: ID!) {
  governor(id: $governorAddress) {
    proposalUpdatablePeriod
    votingDelay
    votingPeriod
    proposalThresholdBps
    quorumThresholdBps
  }
}
```

---

## Migration Strategy

### For Existing Subgraphs

#### Step 1: Schema Migration
1. Add new entities to `schema.graphql`
2. Run `graph codegen` to generate types
3. Deploy to testnet first

#### Step 2: Add Event Handlers
1. Update `subgraph.yaml` with new event mappings:
```yaml
eventHandlers:
  - event: ProposalSignersSet(indexed bytes32,address[])
    handler: handleProposalSignersSet
  - event: ProposalUpdated(bytes32,bytes32,address[],uint256[],bytes[],string,string)
    handler: handleProposalUpdated
  - event: ProposalUpdatablePeriodUpdated(uint256,uint256)
    handler: handleProposalUpdatablePeriodUpdated
```

2. Implement handlers in `mapping.ts`

#### Step 3: Backfill Historical Data (Optional)
For proposals created before upgrade:
- Set `updatePeriodEnd = voteStart` (no updatable period)
- Leave `signers` empty
- No revision history

#### Step 4: Frontend Integration
Update UI to:
- Follow `replacedBy` chain to show current version
- Display revision history
- Show signer sponsorships
- Handle `REPLACED` state (e.g., redirect to current version)

---

## Testing Checklist

- [ ] Deploy subgraph to testnet
- [ ] Create signed proposal → verify signers indexed
- [ ] Update proposal → verify revision chain created
- [ ] Query current proposal ID → verify follows replacement
- [ ] Query revision history → verify ordering correct
- [ ] Update governor config → verify indexed
- [ ] Check all state transitions include `UPDATABLE` and `REPLACED`

---

## Performance Considerations

### Indexed Fields
Add database indexes for common queries:
```graphql
type Proposal @entity {
  state: ProposalState! @index
  updatePeriodEnd: BigInt @index
  timestamp: BigInt @index
}

type ProposalSigner @entity {
  signer: Account! @index
  timestamp: BigInt @index
}
```

### Pagination
For large DAOs, use pagination:
```graphql
query GetProposals($first: Int!, $skip: Int!) {
  proposals(
    first: $first
    skip: $skip
    orderBy: timestamp
    orderDirection: desc
  ) {
    # fields
  }
}
```

### Caching Strategy
- Cache current proposal ID mappings in frontend
- Invalidate on `ProposalUpdated` events
- Use GraphQL subscriptions for real-time updates

---

## Common Issues and Solutions

### Issue 1: Proposal Not Found on Update
**Symptom:** `ProposalUpdated` fires before `ProposalCreated` indexed

**Solution:**
```typescript
// In handleProposalUpdated:
if (!newProposal) {
  log.warning("Deferring ProposalUpdated until ProposalCreated indexed");
  // Option A: Store in temporary entity and process later
  // Option B: Re-query after delay (in client)
  return;
}
```

### Issue 2: Circular Replacement Chains
**Symptom:** Infinite loop following `replacedBy`

**Solution:**
```typescript
function getCurrentProposalId(
  proposalId: string,
  maxDepth: number = 10
): string {
  let current = proposalId;
  let depth = 0;

  while (depth < maxDepth) {
    let proposal = Proposal.load(current);
    if (!proposal || !proposal.replacedBy) break;

    current = proposal.replacedBy;
    depth++;
  }

  if (depth >= maxDepth) {
    log.error("Circular replacement chain detected: {}", [proposalId]);
  }

  return current;
}
```

### Issue 3: State Sync Issues
**Symptom:** Proposal state doesn't match contract

**Solution:** Add periodic state refresh:
```typescript
// Called on block or timer
export function refreshProposalState(proposalId: string): void {
  let governorContract = GovernorContract.bind(governorAddress);
  let contractState = governorContract.state(Bytes.fromHexString(proposalId));

  let proposal = Proposal.load(proposalId);
  if (proposal) {
    proposal.state = proposalStateToString(contractState);
    proposal.save();
  }
}
```

---

## Reference Implementation

Full reference subgraph available at:
- GitHub: `BuilderOSS/nouns-protocol-subgraph` (update branch)
- Example DAOs: Nouns Builder testnet deployments

---

## Support

- **Subgraph Issues:** [BuilderOSS/nouns-protocol-subgraph/issues](https://github.com/BuilderOSS/nouns-protocol-subgraph/issues)
- **Governor Docs:** `docs/governor-architecture.md`
- **Discord:** Builder DAO community channel

---

**Last Updated:** 2026-05-20
**Version:** v2.1.0 Subgraph Migration
**Status:** Production-Ready
