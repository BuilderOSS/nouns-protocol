# EAS Schema Design: Proposal Candidates

**Version:** 3.5.0
**Date:** 2026-05-27
**Purpose:** Off-chain proposal drafting, discussion, and signature collection using Ethereum Attestation Service (EAS)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Schema Definitions](#schema-definitions)
4. [Workflow & User Journey](#workflow--user-journey)
5. [Technical Implementation](#technical-implementation)
6. [Code Examples](#code-examples)
7. [Integration with proposeBySigs](#integration-with-proposebysigs)
8. [Frontend Integration](#frontend-integration)
9. [Subgraph Integration](#subgraph-integration)
10. [Security Considerations](#security-considerations)

---

## Overview

### What are Proposal Candidates?

Proposal Candidates are **draft proposals** that exist off-chain before being submitted as formal on-chain proposals. They enable:

- **Permissionless Ideation**: Any user can create a draft proposal
- **Community Discussion**: Comments and feedback on proposals before formal submission
- **Social Signaling**: Informal support to gauge community interest
- **Signature Collection**: Gather sponsor signatures for `proposeBySigs` submission
- **Version Control**: Iterate on proposals with parallel versioning

### Why Use EAS?

- **Decentralized & Permanent**: Attestations are on-chain and censorship-resistant
- **Composable**: Other apps can read and reference attestations
- **Cost-Effective**: Much cheaper than creating on-chain proposals
- **Self-Contained**: No off-chain storage required - salt stored in attestation
- **Already Integrated**: Leverages existing EAS infrastructure (PropDates)

### Key Features

✅ **Parallel Versioning**: Each edit creates a new attestation; sponsors choose which to sign
✅ **Self-Contained Grouping**: Salt stored in attestation enables version linking
✅ **No Off-Chain Dependencies**: Everything on EAS, no DB/localStorage needed
✅ **Formal Signatures**: EIP-712 signatures stored on-chain via EAS
✅ **Seamless Submission**: Signatures ready to pass directly to `proposeBySigs`
✅ **JSON Metadata**: Structured proposal data matching existing frontend patterns
✅ **Fully Revocable**: All schemas are revocable for maximum flexibility

### Deployed Schema UIDs

#### Sepolia Testnet

```javascript
// Schema UIDs for Sepolia testnet
const PROPOSAL_CANDIDATE_SCHEMA_UID =
  "0x5d1c687645ae02fa0f235cc55ce24ab4e6c1d729f82c281689fd3f9f150932f3";
const CANDIDATE_COMMENT_SCHEMA_UID =
  "0x1decf999b02cbecd8697ae7cf0c4017bc0115adbee476da79634332fdff965b2";
const CANDIDATE_SPONSOR_SIGNATURE_SCHEMA_UID =
  "0xeb66ca8d752474c808c9922734355ea6ec385c2515d66433aeabbf2a7b9fcaa5";
```

**EAS Scan Links:**

- [ProposalCandidate](https://sepolia.easscan.org/schema/view/0x5d1c687645ae02fa0f235cc55ce24ab4e6c1d729f82c281689fd3f9f150932f3)
- [CandidateComment](https://sepolia.easscan.org/schema/view/0x1decf999b02cbecd8697ae7cf0c4017bc0115adbee476da79634332fdff965b2)
- [CandidateSponsorSignature](https://sepolia.easscan.org/schema/view/0xeb66ca8d752474c808c9922734355ea6ec385c2515d66433aeabbf2a7b9fcaa5)

#### Mainnet

```javascript
// Schema UIDs for Ethereum mainnet (TBD)
const PROPOSAL_CANDIDATE_SCHEMA_UID = "TBD";
const CANDIDATE_COMMENT_SCHEMA_UID = "TBD";
const CANDIDATE_SPONSOR_SIGNATURE_SCHEMA_UID = "TBD";
```

---

## Architecture

### Simplified Design

**Key Insight:** Each version is a separate attestation. Grouping happens via `candidateId = hash(proposer + salt)`, where the `salt` is stored in the attestation itself.

```
┌─────────────────────────────────────────────────────────────────┐
│                   ProposalCandidate v1                           │
│  candidateId: 0xabc, salt: 0x123, version: 1, proposalId: ...  │
│  UID: 0x111                                                      │
└────┬────────────────────────────────────────────────────────────┘
     │
     │ (User edits, creates new version)
     │ (Reads salt from v1, reuses same candidateId)
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ProposalCandidate v2                           │
│  candidateId: 0xabc, salt: 0x123, version: 2, proposalId: ...  │
│  UID: 0x222                                                      │
└────┬────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ProposalCandidate v3                           │
│  candidateId: 0xabc, salt: 0x123, version: 3, proposalId: ...  │
│  UID: 0x333                                                      │
└─────────────────────────────────────────────────────────────────┘

     Each version has independent:
     - Sponsor Signatures (EIP-712) → point to candidateVersionUID
     - Comments → point to candidateId (candidate-level)
```

### How It Works

1. **First Version (v1)**
   - Frontend generates random `salt` (bytes32)
   - Calculates `candidateId = keccak256(abi.encodePacked(proposer, salt))`
   - Creates attestation with salt, candidateId, version: 1, proposal data

2. **Subsequent Versions (v2, v3, ...)**
   - Frontend queries EAS for previous version by candidateId
   - Extracts `salt` from previous attestation
   - Reuses same `candidateId = keccak256(abi.encodePacked(proposer, salt))`
   - Creates new attestation with same salt, candidateId, incremented version, new data

3. **Subgraph Aggregation**
   - Groups all attestations by `candidateId`
   - Orders by `versionNumber`
   - Provides unified view of proposal evolution

### Schema Relationships

| Schema                        | References          | Purpose                                           |
| ----------------------------- | ------------------- | ------------------------------------------------- |
| **ProposalCandidate**         | -                   | Proposal version (self-contained)                 |
| **CandidateComment**          | candidateId         | Discussion + sentiment (FOR/AGAINST/ABSTAIN/NONE) |
| **CandidateSponsorSignature** | candidateVersionUID | Formal EIP-712 signature for specific version     |

---

## Schema Definitions

### Schema 1: ProposalCandidate

**Purpose:** Complete proposal version with all data

**Revocable:** Yes (proposers can revoke outdated versions)
**Resolver:** None

**Deployed Schema UIDs:**

- **Sepolia**: `0x5d1c687645ae02fa0f235cc55ce24ab4e6c1d729f82c281689fd3f9f150932f3`
- **Mainnet**: TBD

#### Schema String

```
bytes32 candidateId,bytes32 salt,uint64 versionNumber,address[] targets,uint256[] values,bytes[] calldatas,string description,bytes32 proposalId
```

#### Field Definitions

| Field           | Type      | Description                        | Constraints                                                                    |
| --------------- | --------- | ---------------------------------- | ------------------------------------------------------------------------------ |
| `candidateId`   | bytes32   | Unique candidate identifier        | `keccak256(abi.encodePacked(attester, salt))`                                  |
| `salt`          | bytes32   | Random salt for grouping versions  | Generated on v1, reused for all versions                                       |
| `versionNumber` | uint64    | Version number (1, 2, 3...)        | Increments with each edit                                                      |
| `targets`       | address[] | Target contract addresses          | Length must match values/calldatas                                             |
| `values`        | uint256[] | ETH values for each call           | Length must match targets/calldatas                                            |
| `calldatas`     | bytes[]   | Encoded function calls             | Length must match targets/values                                               |
| `description`   | string    | JSON-stringified proposal metadata | See description format below                                                   |
| `proposalId`    | bytes32   | Pre-calculated proposal ID         | `keccak256(abi.encode(targets, values, calldatas, descriptionHash, attester))` |

**Note:** The `attester` field (implicit in EAS) is the proposer/creator address. The creation timestamp is available from EAS via `event.block.timestamp` in subgraph or `attestation.time` in SDK queries.

#### Description Format (JSON)

The `description` field is a **JSON string** matching your existing proposal format:

```json
{
  "version": 1,
  "title": "Treasury Diversification Proposal",
  "description": "Allocate 10% of treasury to diversified assets...",
  "transactionBundles": [
    {
      "type": "transfer",
      "summary": "Transfer 100 ETH to Diversification Multisig",
      "callCount": 1
    }
  ],
  "representedAddress": "0x...", // optional
  "discussionUrl": "https://forum.dao.org/proposal-123" // optional
}
```

**Frontend Extracts:**

- Title from `JSON.parse(description).title`
- Summary from `JSON.parse(description).description`
- Transaction details from `transactionBundles`

#### CandidateId Calculation

**Critical:** The candidateId groups all versions together:

```solidity
bytes32 candidateId = keccak256(abi.encodePacked(attester, salt));
```

**Why it works:**

- `attester`: Same for all versions (creator doesn't change)
- `salt`: Stored in v1, reused in v2, v3, etc.
- Result: Same candidateId across all versions!

**Note:** `attester` is the EAS attestation creator (automatically set when creating attestation).

#### ProposalId Calculation

**Critical:** The `proposalId` MUST be calculated exactly as the Governor contract does:

```solidity
bytes32 proposalId = keccak256(
    abi.encode(
        targets,
        values,
        calldatas,
        keccak256(bytes(description)),
        attester  // The proposer
    )
);
```

This ensures signatures collected for this version will work with `proposeBySigs`.

**Note:** Use the attestation creator's address (the signer) as the proposer in the calculation.

#### Example Attestation Data

**Version 1 (First):**

```javascript
{
  candidateId: "0xabc123...", // keccak256(attester, salt)
  salt: "0x789def...", // Randomly generated
  versionNumber: 1,
  targets: ["0xTreasury..."],
  values: [BigNumber.from(0)],
  calldatas: ["0x..."], // encoded call
  description: '{"version":1,"title":"Treasury Diversification","description":"...","transactionBundles":[...]}',
  proposalId: "0x5678..." // Calculated with attester as proposer
}
// attester: "0xAlice..." (implicit in EAS)
// timestamp: Available from EAS attestation (event.block.timestamp)
```

**Version 2 (Revision):**

```javascript
{
  candidateId: "0xabc123...", // SAME as v1
  salt: "0x789def...", // SAME as v1 (copied from v1)
  versionNumber: 2, // Incremented
  targets: ["0xTreasury..."], // May be different
  values: [BigNumber.from(0)], // May be different
  calldatas: ["0x..."], // May be different
  description: '{"version":1,"title":"Updated Title","description":"...","transactionBundles":[...]}', // Different
  proposalId: "0x9abc..." // DIFFERENT (new content)
}
// attester: "0xAlice..." (SAME, implicit in EAS)
// timestamp: Later than v1 (from EAS attestation)
```

---

### Schema 2: CandidateComment

**Purpose:** Discussion, feedback, and informal voting on proposals

**Revocable:** Yes (users can delete their comments)
**Resolver:** None

**Deployed Schema UIDs:**

- **Sepolia**: `0x1decf999b02cbecd8697ae7cf0c4017bc0115adbee476da79634332fdff965b2`
- **Mainnet**: TBD

#### Schema String

```
bytes32 candidateId,uint8 support,string comment,bytes32 parentCommentUID
```

#### Field Definitions

| Field              | Type    | Description                           | Constraints                                |
| ------------------ | ------- | ------------------------------------- | ------------------------------------------ |
| `candidateId`      | bytes32 | Candidate identifier                  | Must exist                                 |
| `support`          | uint8   | Sentiment/vote                        | 0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE        |
| `comment`          | string  | Comment text (markdown)               | Can be empty for vote-only; max 5000 chars |
| `parentCommentUID` | bytes32 | UID of parent comment (for threading) | 0x0 if top-level comment                   |

**Note:** The `attester` field (implicit in EAS) is the commenter's address.

#### Support Values

| Value | Name    | Meaning      | Use Case                                |
| ----- | ------- | ------------ | --------------------------------------- |
| 0     | FOR     | Support      | "I like this idea"                      |
| 1     | AGAINST | Opposition   | "I disagree with this approach"         |
| 2     | ABSTAIN | Neutral      | "I see both sides" or "Needs more info" |
| 3     | NONE    | No sentiment | Pure comment/question                   |

#### Key Design Principles

**Revocable for Flexibility:**

- Comments can be revoked/deleted by the commenter
- Users can either delete old comments or create new ones to express evolving opinions
- Frontend should handle revoked comments gracefully (filter them out)
- Example: User posts FOR on v1, then either revokes it or posts new AGAINST on v2

**Candidate-Level (Not Version-Specific):**

- All comments reference the overall candidateId
- Users naturally update their view as new versions are released
- Latest non-revoked comment from a user shows their current opinion
- Frontend aggregates "current sentiment" = latest non-revoked comment from each user

**Comment + Vote Unified:**

- Can vote with explanation: `support=FOR, comment="Great idea because..."`
- Can vote without comment: `support=FOR, comment=""`
- Can comment without vote: `support=NONE, comment="Question: how does X work?"`
- More expressive than separate schemas

#### Example Attestation Data

```javascript
// Initial support with reasoning
{
  candidateId: "0xabc123...",
  support: 0, // FOR
  comment: "Great idea! We need treasury diversification. The 10% allocation seems reasonable.",
  parentCommentUID: "0x0000000000000000000000000000000000000000000000000000000000000000"
}

// Question without sentiment
{
  candidateId: "0xabc123...",
  support: 3, // NONE
  comment: "Have you considered what happens if the market crashes during rebalancing?",
  parentCommentUID: "0x0000000000000000000000000000000000000000000000000000000000000000"
}

// Opposition with explanation
{
  candidateId: "0xabc123...",
  support: 1, // AGAINST
  comment: "I'm against v2 because the timelock was removed. Security risk.",
  parentCommentUID: "0x0000000000000000000000000000000000000000000000000000000000000000"
}

// Changed opinion (new attestation, append-only)
// Same user (Alice) who originally posted FOR, now posts AGAINST after v2 released
{
  candidateId: "0xabc123...",
  support: 1, // AGAINST (changed from FOR!)
  comment: "After seeing v2, I'm now against this. The removal of safeguards is concerning.",
  parentCommentUID: "0x0000000000000000000000000000000000000000000000000000000000000000"
}
// Frontend shows Alice's LATEST sentiment = AGAINST

// Reply to comment (inherits context, can have different sentiment)
{
  candidateId: "0xabc123...",
  support: 0, // FOR (disagreeing with parent's AGAINST)
  comment: "I disagree - the timelock removal is actually necessary for efficiency.",
  parentCommentUID: "0x9876..." // UID of the AGAINST comment
}

// Vote-only (no comment text)
{
  candidateId: "0xabc123...",
  support: 2, // ABSTAIN
  comment: "", // Empty string
  parentCommentUID: "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

#### Sentiment Evolution Example

Alice's journey with a candidate:

```
Time 0 (v1 released):
  support: FOR, comment: "Love this idea!"

Time +2 days (v2 released, Alice dislikes changes):
  support: AGAINST, comment: "v2 removed safety features, now against"

Time +4 days (v3 released, concerns addressed):
  support: FOR, comment: "v3 fixed my concerns, supporting again"
```

**Frontend displays:**

- Alice's current sentiment: FOR (latest)
- Alice's comment history: Shows evolution (FOR → AGAINST → FOR)
- Aggregate sentiment: Count latest comment from each unique user

---

### Schema 3: CandidateSponsorSignature

**Purpose:** Store formal EIP-712 signatures for `proposeBySigs`

**Revocable:** Yes (sponsor can revoke signature)
**Resolver:** None

**Deployed Schema UIDs:**

- **Sepolia**: `0xeb66ca8d752474c808c9922734355ea6ec385c2515d66433aeabbf2a7b9fcaa5`
- **Mainnet**: TBD

#### Schema String

```
bytes32 candidateVersionUID,bytes32 proposalId,uint256 nonce,uint256 deadline,bytes signature
```

#### Field Definitions

| Field                 | Type    | Description                                           | Constraints                             |
| --------------------- | ------- | ----------------------------------------------------- | --------------------------------------- |
| `candidateVersionUID` | bytes32 | UID of specific ProposalCandidate version attestation | Must exist                              |
| `proposalId`          | bytes32 | Proposal ID being signed                              | Must match version's proposalId         |
| `nonce`               | uint256 | Signer's nonce at signing time                        | From `proposeSignatureNonce(signer)`    |
| `deadline`            | uint256 | Signature expiration timestamp                        | Must be future timestamp                |
| `signature`           | bytes   | Full EIP-712 signature                                | 65 bytes (ECDSA) or variable (ERC-1271) |

**Note:** The `attester` field (implicit in EAS) is the signer/sponsor's address.

**Signatures are for SPECIFIC VERSIONS** (candidateVersionUID). Each version competes for signatures.

#### Signature Validation

Before accepting a signature attestation, validate:

1. ✅ Signature not expired (`block.timestamp < deadline`)
2. ✅ Nonce matches current on-chain nonce
3. ✅ Signature is valid EIP-712 signature
4. ✅ Signer has sufficient voting power (optional, for UX)
5. ✅ Proposer is not the signer (contract requirement)

#### Example Attestation Data

```javascript
{
  candidateVersionUID: "0x222...", // UID of ProposalCandidate version 2 attestation
  proposalId: "0x9abc...", // Version 2's proposalId
  nonce: BigNumber.from(5),
  deadline: 1716912000, // 24 hours from now
  signature: "0x1234abcd..." // 65+ bytes
}
```

#### Revocation

Sponsors can revoke their signature by revoking the EAS attestation.

**Frontend must filter out revoked signatures before submission.**

---

## Workflow & User Journey

### Phase 1: Creating First Version

```
┌──────────────┐
│ 1. Creator   │  Visits "Create Proposal Candidate" page
│    Alice     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 2. Frontend  │  Generates random salt: 0x789def...
│              │  Calculates candidateId: keccak256(Alice, salt)
│              │  = 0xabc123...
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 3. Creator   │  Fills in proposal form:
│    Alice     │  - Title: "Treasury Diversification"
│              │  - Description: "Allocate 10%..."
│              │  - Transactions: [...]
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 4. Frontend  │  Builds JSON description
│              │  Calculates proposalId
│              │  Creates ProposalCandidate attestation:
│              │  - candidateId: 0xabc123
│              │  - salt: 0x789def
│              │  - versionNumber: 1
│              │  - targets, values, calldatas
│              │  - description (JSON)
│              │  - proposalId
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 5. Result    │  Version 1 created!
│              │  UID: 0x111
│              │  candidateId: 0xabc123
└──────────────┘
```

### Phase 2: Community Engagement

```
┌──────────────┐
│ 6. Community │  Discovers candidate 0xabc123
│    Bob, Carol│
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 7. Bob       │  Creates CandidateComment attestation
│   Supports   │  - candidateId: 0xabc123
│              │  - support: 1 (FOR)
│              │  - comment: "Great idea! We need this."
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 8. Carol     │  Creates CandidateComment attestation
│   Questions  │  - candidateId: 0xabc123
│              │  - support: 0 (NONE - just asking)
│              │  - comment: "What about adding X?"
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 9. Dave      │  Creates CandidateComment attestation
│   Opposes    │  - candidateId: 0xabc123
│              │  - support: 2 (AGAINST)
│              │  - comment: "This approach won't scale."
└──────────────┘

       Current Sentiment Tally:
       FOR: 1 (Bob)
       AGAINST: 1 (Dave)
       ABSTAIN: 0
       Comments: 3 total
```

### Phase 3: Iteration & Sentiment Evolution

```
┌──────────────┐
│ 10. Creator  │  Receives feedback from Carol
│     Alice    │  Decides to address concerns
│              │  Creates version 2
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 11. Frontend │  Queries EAS for candidateId: 0xabc123
│              │  Finds version 1 (UID: 0x111)
│              │  Extracts salt: 0x789def
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 12. Creator  │  Edits proposal:
│     Alice    │  - Addresses Carol's question
│              │  - Modified approach based on Dave's concern
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 13. Frontend │  Creates NEW ProposalCandidate attestation:
│              │  - candidateId: 0xabc123 (SAME!)
│              │  - salt: 0x789def (SAME!)
│              │  - versionNumber: 2 (INCREMENTED!)
│              │  - targets, values, calldatas (UPDATED)
│              │  - description (UPDATED JSON)
│              │  - proposalId: 0x9abc (NEW!)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 14. Result   │  Version 2 created!
│              │  UID: 0x222
│              │
│              │  Now TWO versions exist:
│              │  - Version 1 (UID: 0x111)
│              │  - Version 2 (UID: 0x222)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 15. Dave     │  Reviews v2, opinion changes!
│   Changes    │  Creates NEW CandidateComment:
│   Opinion    │  - candidateId: 0xabc123
│              │  - support: 1 (FOR - changed from AGAINST!)
│              │  - comment: "v2 addresses my scaling concerns. Now supporting!"
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Updated    │  Dave's sentiment history:
│   Sentiment  │  Time 0: AGAINST ("won't scale")
│              │  Time +2 days: FOR ("v2 addresses concerns")
│              │
│              │  Current Sentiment (latest from each user):
│              │  FOR: 2 (Bob, Dave ✅ changed)
│              │  AGAINST: 0
│              │  ABSTAIN: 0
└──────────────┘
```

### Phase 4: Signature Collection

```
┌──────────────┐
│ 14. Sponsors │  Review both versions
│     Bob, Dave│  Decide which to sign
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 15. Bob      │  Prefers Version 2
│              │  Generates EIP-712 signature for:
│              │  - proposer: Alice
│              │  - proposalId: 0x9abc (v2's ID)
│              │
│              │  Creates CandidateSponsorSignature:
│              │  - candidateVersionUID: 0x222 (v2)
│              │  - proposalId: 0x9abc
│              │  - signature: 0x...
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 16. Dave     │  Prefers Version 1
│              │  Signs for Version 1:
│              │  - candidateVersionUID: 0x111 (v1)
│              │  - proposalId: 0x5678 (v1's ID)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 17. Results  │  Version 1: 1 signature (Dave)
│              │  Version 2: 1 signature (Bob)
│              │
│              │  More sponsors needed!
└──────────────┘
```

### Phase 5: Submission

```
┌──────────────┐
│ 18. Eve      │  Signs Version 2
│              │  Now: v2 has 2 signatures (Bob, Eve)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 19. Check    │  Proposal threshold: 2 signatures
│     Threshold│  Version 2: 2 signatures ✅
│              │  Version 1: 1 signature ❌
│              │
│              │  Version 2 can be submitted!
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 20. Creator  │  Clicks "Submit Version 2"
│     Alice    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 21. Frontend │  Queries signatures for v2 (UID: 0x222)
│              │  Finds: Bob, Eve
│              │  Sorts: [Bob, Eve] by address
│              │  Validates: Not revoked, not expired
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 22. Submit   │  Calls governor.proposeBySigs(
│     On-Chain │    proposerSignatures: [Bob sig, Eve sig],
│              │    targets: v2.targets,
│              │    values: v2.values,
│              │    calldatas: v2.calldatas,
│              │    description: v2.description
│              │  )
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ 23. Success  │  On-chain proposal created! 🎉
│              │  proposalId: 0x9abc (matches v2)
└──────────────┘
```

---

## Technical Implementation

### 1. Salt Generation (First Version)

```javascript
import { ethers } from "ethers";

function generateSalt(): string {
  // Generate random 32 bytes
  return ethers.utils.hexlify(ethers.utils.randomBytes(32));
}

// Example
const salt = generateSalt();
// "0x789def123456abcd..."
```

### 2. CandidateId Calculation

```javascript
function calculateCandidateId(attester: string, salt: string): string {
  // candidateId = keccak256(abi.encodePacked(attester, salt))
  const candidateId = ethers.utils.keccak256(
    ethers.utils.solidityPack(["address", "bytes32"], [attester, salt])
  );
  return candidateId;
}

// Example
const attester = "0xAlice..."; // The proposer/creator
const salt = "0x789def...";
const candidateId = calculateCandidateId(attester, salt);
// "0xabc123..."
```

### 3. ProposalId Calculation

```javascript
function calculateProposalId(
  targets: string[],
  values: ethers.BigNumber[],
  calldatas: string[],
  description: string,
  proposer: string
): string {
  // Calculate description hash
  const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));

  // Encode and hash (same as Governor contract)
  const proposalId = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ["address[]", "uint256[]", "bytes[]", "bytes32", "address"],
      [targets, values, calldatas, descriptionHash, proposer]
    )
  );

  return proposalId;
}
```

**⚠️ CRITICAL:** This MUST match the Governor contract's calculation exactly.

### 4. Description JSON Building

```javascript
function buildDescriptionJSON(
  title: string,
  description: string,
  transactionBundles: Array<{
    type: string,
    summary: string,
    callCount: number,
  }>,
  representedAddress?: string,
  discussionUrl?: string
): string {
  const metadata = {
    version: 1,
    title: title.trim(),
    description: description.trim(),
    transactionBundles,
    ...(representedAddress ? { representedAddress: representedAddress.trim() } : {}),
    ...(discussionUrl ? { discussionUrl: discussionUrl.trim() } : {}),
  };

  return JSON.stringify(metadata);
}

// Example
const descriptionJSON = buildDescriptionJSON(
  "Treasury Diversification",
  "Allocate 10% of treasury...",
  [
    {
      type: "transfer",
      summary: "Transfer 100 ETH to Diversification Multisig",
      callCount: 1,
    },
  ],
  undefined,
  "https://forum.dao.org/proposal-123"
);

// Result: '{"version":1,"title":"Treasury Diversification","description":"...","transactionBundles":[...],"discussionUrl":"..."}'
```

### 5. Extracting Previous Salt (For New Versions)

```javascript
import { GraphQLClient, gql } from "graphql-request";

async function getPreviousVersionSalt(
  graphqlClient: GraphQLClient,
  candidateId: string
): Promise<{ salt: string, latestVersion: number } | null> {
  const query = gql`
    query GetLatestVersion($candidateId: String!) {
      attestations(
        where: {
          schema: { equals: "${PROPOSAL_CANDIDATE_SCHEMA_UID}" }
          decodedDataJson: { contains: $candidateId }
        }
        orderBy: { timeCreated: desc }
        take: 1
      ) {
        id
        decodedDataJson
      }
    }
  `;

  const data = await graphqlClient.request(query, { candidateId });

  if (data.attestations.length === 0) {
    return null;
  }

  const decoded = JSON.parse(data.attestations[0].decodedDataJson);
  const salt = decoded.find((d) => d.name === "salt").value.value;
  const versionNumber = parseInt(decoded.find((d) => d.name === "versionNumber").value.value);

  return {
    salt,
    latestVersion: versionNumber,
  };
}

// Usage
const previous = await getPreviousVersionSalt(graphqlClient, candidateId);
if (previous) {
  const nextVersionNumber = previous.latestVersion + 1;
  const salt = previous.salt; // Reuse this salt!
}
```

---

## Code Examples

### Example 1: Create First Version (v1)

```javascript
import { EAS, SchemaEncoder } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

async function createFirstCandidateVersion(
  eas: EAS,
  signer: ethers.Signer,
  proposalData: {
    title: string,
    description: string,
    targets: string[],
    values: ethers.BigNumber[],
    calldatas: string[],
    transactionBundles: Array<any>,
    representedAddress?: string,
    discussionUrl?: string,
  }
): Promise<{
  candidateId: string,
  candidateVersionUID: string,
  salt: string,
}> {
  const proposer = await signer.getAddress();

  // 1. Generate salt (FIRST TIME ONLY)
  const salt = ethers.utils.hexlify(ethers.utils.randomBytes(32));

  // 2. Calculate candidateId
  const candidateId = calculateCandidateId(proposer, salt);

  // 3. Build description JSON
  const descriptionJSON = buildDescriptionJSON(
    proposalData.title,
    proposalData.description,
    proposalData.transactionBundles,
    proposalData.representedAddress,
    proposalData.discussionUrl
  );

  // 4. Calculate proposalId
  const proposalId = calculateProposalId(
    proposalData.targets,
    proposalData.values,
    proposalData.calldatas,
    descriptionJSON,
    proposer
  );

  // 5. Encode schema data (note: proposer is implicit via EAS attester, timestamp from event.block.timestamp)
  const schemaEncoder = new SchemaEncoder(
    "bytes32 candidateId,bytes32 salt,uint64 versionNumber,address[] targets,uint256[] values,bytes[] calldatas,string description,bytes32 proposalId"
  );

  const encodedData = schemaEncoder.encodeData([
    { name: "candidateId", value: candidateId, type: "bytes32" },
    { name: "salt", value: salt, type: "bytes32" },
    { name: "versionNumber", value: 1, type: "uint64" },
    { name: "targets", value: proposalData.targets, type: "address[]" },
    { name: "values", value: proposalData.values, type: "uint256[]" },
    { name: "calldatas", value: proposalData.calldatas, type: "bytes[]" },
    { name: "description", value: descriptionJSON, type: "string" },
    { name: "proposalId", value: proposalId, type: "bytes32" },
  ]);

  // 6. Create attestation (revocable so proposer can clean up old versions)
  const tx = await eas.connect(signer).attest({
    schema: PROPOSAL_CANDIDATE_SCHEMA_UID,
    data: {
      recipient: ethers.constants.AddressZero,
      expirationTime: 0,
      revocable: true,
      data: encodedData,
    },
  });

  const receipt = await tx.wait();
  const candidateVersionUID = receipt.logs[0].topics[1];

  console.log("Created Version 1!");
  console.log("  candidateId:", candidateId);
  console.log("  candidateVersionUID:", candidateVersionUID);
  console.log("  salt:", salt);

  return { candidateId, candidateVersionUID, salt };
}
```

---

### Example 2: Create New Version (v2, v3, ...)

```javascript
async function createNewCandidateVersion(
  eas: EAS,
  graphqlClient: GraphQLClient,
  signer: ethers.Signer,
  candidateId: string, // Existing candidate
  proposalData: {
    title: string,
    description: string,
    targets: string[],
    values: ethers.BigNumber[],
    calldatas: string[],
    transactionBundles: Array<any>,
    representedAddress?: string,
    discussionUrl?: string,
  }
): Promise<{
  candidateVersionUID: string,
  versionNumber: number,
}> {
  const proposer = await signer.getAddress();

  // 1. Fetch previous version to get salt and version number
  const previous = await getPreviousVersionSalt(graphqlClient, candidateId);

  if (!previous) {
    throw new Error("Candidate not found");
  }

  const salt = previous.salt; // REUSE SALT!
  const nextVersionNumber = previous.latestVersion + 1;

  // 2. Verify candidateId matches
  const verifiedCandidateId = calculateCandidateId(proposer, salt);
  if (verifiedCandidateId !== candidateId) {
    throw new Error("CandidateId mismatch - wrong proposer or salt");
  }

  // 3. Build description JSON
  const descriptionJSON = buildDescriptionJSON(
    proposalData.title,
    proposalData.description,
    proposalData.transactionBundles,
    proposalData.representedAddress,
    proposalData.discussionUrl
  );

  // 4. Calculate NEW proposalId (content changed)
  const proposalId = calculateProposalId(
    proposalData.targets,
    proposalData.values,
    proposalData.calldatas,
    descriptionJSON,
    proposer
  );

  // 5. Encode schema data (note: proposer is implicit via EAS attester, timestamp from event.block.timestamp)
  const schemaEncoder = new SchemaEncoder(
    "bytes32 candidateId,bytes32 salt,uint64 versionNumber,address[] targets,uint256[] values,bytes[] calldatas,string description,bytes32 proposalId"
  );

  const encodedData = schemaEncoder.encodeData([
    { name: "candidateId", value: candidateId, type: "bytes32" },
    { name: "salt", value: salt, type: "bytes32" }, // SAME salt
    { name: "versionNumber", value: nextVersionNumber, type: "uint64" }, // Incremented
    { name: "targets", value: proposalData.targets, type: "address[]" },
    { name: "values", value: proposalData.values, type: "uint256[]" },
    { name: "calldatas", value: proposalData.calldatas, type: "bytes[]" },
    { name: "description", value: descriptionJSON, type: "string" },
    { name: "proposalId", value: proposalId, type: "bytes32" }, // NEW proposalId
  ]);

  // 6. Create attestation (revocable so proposer can clean up old versions)
  const tx = await eas.connect(signer).attest({
    schema: PROPOSAL_CANDIDATE_SCHEMA_UID,
    data: {
      recipient: ethers.constants.AddressZero,
      expirationTime: 0,
      revocable: true,
      data: encodedData,
    },
  });

  const receipt = await tx.wait();
  const candidateVersionUID = receipt.logs[0].topics[1];

  console.log(`Created Version ${nextVersionNumber}!`);
  console.log("  candidateVersionUID:", candidateVersionUID);
  console.log("  candidateId:", candidateId, "(same as before)");

  return { candidateVersionUID, versionNumber: nextVersionNumber };
}
```

---

### Example 3: Comment on a Candidate (with optional vote)

```javascript
// Support values
const SUPPORT = {
  FOR: 0, // Support the proposal
  AGAINST: 1, // Oppose the proposal
  ABSTAIN: 2, // Neutral stance
  NONE: 3, // No sentiment, just commenting
};

async function commentOnCandidate(
  eas: EAS,
  signer: ethers.Signer,
  candidateId: string,
  support: number, // 0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE
  comment: string = "", // Can be empty for vote-only
  parentCommentUID: string = ethers.constants.HashZero // For replies
): Promise<string> {
  const schemaEncoder = new SchemaEncoder(
    "bytes32 candidateId,uint8 support,string comment,bytes32 parentCommentUID"
  );

  const encodedData = schemaEncoder.encodeData([
    { name: "candidateId", value: candidateId, type: "bytes32" },
    { name: "support", value: support, type: "uint8" },
    { name: "comment", value: comment, type: "string" },
    { name: "parentCommentUID", value: parentCommentUID, type: "bytes32" },
  ]);

  const tx = await eas.connect(signer).attest({
    schema: CANDIDATE_COMMENT_SCHEMA_UID,
    data: {
      recipient: ethers.constants.AddressZero,
      expirationTime: 0,
      revocable: true, // Users can delete their comments
      data: encodedData,
    },
  });

  const receipt = await tx.wait();
  const commentUID = receipt.logs[0].topics[1];

  console.log("Comment added:", commentUID);
  return commentUID;
}

// Usage examples:

// Support with reason
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.FOR,
  "Great idea! This addresses a real need."
);

// Question without sentiment
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.NONE,
  "Have you considered the gas costs?"
);

// Opposition with explanation
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.AGAINST,
  "This approach has security concerns."
);

// Vote-only (no comment text)
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.ABSTAIN,
  "" // Empty comment
);

// Reply to another comment
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.FOR,
  "I disagree with your concerns - here's why...",
  "0xparentCommentUID..."
);

// Change opinion (append new comment)
// User previously posted AGAINST, now posts FOR after v2
await commentOnCandidate(
  eas,
  signer,
  candidateId,
  SUPPORT.FOR,
  "Version 2 addresses my concerns. Now supporting!"
);
```

---

### Example 4: Sign a Specific Version

```javascript
async function signCandidateVersion(
  eas: EAS,
  governor: ethers.Contract,
  token: ethers.Contract,
  signer: ethers.Signer,
  candidateVersionUID: string,
  versionData: {
    proposer: string;
    proposalId: string;
  },
  deadlineMinutes: number = 1440 // 24 hours
): Promise<string> {
  const signerAddr = await signer.getAddress();

  // 1. Generate EIP-712 signature
  const chainId = (await signer.provider!.getNetwork()).chainId;
  const symbol = await token.symbol();
  const nonce = await governor.proposeSignatureNonce(signerAddr);
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
    proposer: versionData.proposer,
    proposalId: versionData.proposalId,
    nonce,
    deadline
  };

  // Sign (ethers v5)
  const sig = await signer._signTypedData(domain, types, value);

  // 2. Create signature attestation on EAS
  const schemaEncoder = new SchemaEncoder(
    'bytes32 candidateVersionUID,bytes32 proposalId,uint256 nonce,uint256 deadline,bytes signature'
  );

  const encodedData = schemaEncoder.encodeData([
    { name: 'candidateVersionUID', value: candidateVersionUID, type: 'bytes32' },
    { name: 'proposalId', value: versionData.proposalId, type: 'bytes32' },
    { name: 'nonce', value: nonce, type: 'uint256' },
    { name: 'deadline', value: deadline, type: 'uint256' },
    { name: 'signature', value: sig, type: 'bytes' }
  ]);

  const tx = await eas.connect(signer).attest({
    schema: CANDIDATE_SPONSOR_SIGNATURE_SCHEMA_UID,
    data: {
      recipient: versionData.attester, // Recipient is the proposer (attester of the version)
      expirationTime: deadline, // Use same deadline
      revocable: true, // Sponsor can revoke
      data: encodedData
    }
  });

  const receipt = await tx.wait();
  const signatureUID = receipt.logs[0].topics[1];

  console.log('Signature added:', signatureUID);
  return signatureUID;
}
```

---

### Example 5: Query All Versions of a Candidate

```javascript
async function getCandidateVersions(
  graphqlClient: GraphQLClient,
  candidateId: string
): Promise<
  Array<{
    uid: string,
    versionNumber: number,
    attester: string, // The proposer/creator
    proposalId: string,
    description: any, // Parsed JSON
    targets: string[],
    values: string[],
    calldatas: string[],
    createdAt: number,
  }>
> {
  const query = gql`
    query GetVersions($candidateId: String!) {
      attestations(
        where: {
          schema: { equals: "${PROPOSAL_CANDIDATE_SCHEMA_UID}" }
          decodedDataJson: { contains: $candidateId }
        }
        orderBy: { timeCreated: asc }
      ) {
        id
        attester
        decodedDataJson
        timeCreated
      }
    }
  `;

  const data = await graphqlClient.request(query, { candidateId });

  return data.attestations.map((att) => {
    const decoded = JSON.parse(att.decodedDataJson);

    return {
      uid: att.id,
      versionNumber: parseInt(decoded.find((d) => d.name === "versionNumber").value.value),
      attester: att.attester, // Proposer comes from EAS attester field, not decoded data
      proposalId: decoded.find((d) => d.name === "proposalId").value.value,
      description: JSON.parse(decoded.find((d) => d.name === "description").value.value),
      targets: decoded.find((d) => d.name === "targets").value.value,
      values: decoded.find((d) => d.name === "values").value.value,
      calldatas: decoded.find((d) => d.name === "calldatas").value.value,
      createdAt: att.timeCreated,
    };
  });
}

// Usage
const versions = await getCandidateVersions(graphqlClient, candidateId);
console.log("Candidate has", versions.length, "versions");
versions.forEach((v) => {
  console.log(`v${v.versionNumber}: ${v.description.title}`);
});
```

---

## Integration with proposeBySigs

### Complete Submission Flow

```javascript
async function submitCandidateVersionToGovernor(
  eas: EAS,
  governor: ethers.Contract,
  graphqlClient: GraphQLClient,
  proposerSigner: ethers.Signer,
  candidateVersionUID: string
): Promise<{
  success: boolean,
  proposalId?: string,
  txHash?: string,
  error?: string,
}> {
  try {
    // 1. Fetch version data from EAS
    const version = await getCandidateVersionByUID(graphqlClient, candidateVersionUID);

    // 2. Fetch all signatures for this version
    const signatures = await getSignaturesForVersion(graphqlClient, candidateVersionUID);

    // 3. Validate signatures
    const now = Math.floor(Date.now() / 1000);
    const validSignatures = [];

    for (const sig of signatures) {
      // Filter revoked
      if (sig.revoked) continue;

      // Filter expired
      if (now > sig.deadline) continue;

      // Verify proposalId matches
      if (sig.proposalId !== version.proposalId) continue;

      // Verify nonce (optional - will fail on-chain if wrong)
      const currentNonce = await governor.proposeSignatureNonce(sig.attester);
      if (!currentNonce.eq(sig.nonce)) continue;

      validSignatures.push(sig);
    }

    // 4. Check if we have enough signatures
    const proposalThreshold = await governor.proposalThreshold();
    const proposer = await proposerSigner.getAddress();
    const proposerVotes = await governor.getVotes(proposer, now);

    let totalVotes = proposerVotes;
    for (const sig of validSignatures) {
      const signerVotes = await governor.getVotes(sig.attester, now);
      totalVotes = totalVotes.add(signerVotes);
    }

    if (totalVotes.lt(proposalThreshold)) {
      return {
        success: false,
        error: `Insufficient voting power. Have ${totalVotes.toString()}, need ${proposalThreshold.toString()}`,
      };
    }

    // 5. Sort signers by address (REQUIRED by contract)
    validSignatures.sort((a, b) => (a.attester.toLowerCase() < b.attester.toLowerCase() ? -1 : 1));

    // 6. Format signatures for contract
    const proposerSignatures = validSignatures.map((sig) => ({
      signer: sig.attester,
      nonce: ethers.BigNumber.from(sig.nonce),
      deadline: sig.deadline,
      sig: sig.signature,
    }));

    // 7. Submit to Governor
    console.log("Submitting proposal with", proposerSignatures.length, "signatures...");

    const tx = await governor.connect(proposerSigner).proposeBySigs(
      proposerSignatures,
      version.targets,
      version.values,
      version.calldatas,
      version.description // Raw JSON string
    );

    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();

    // 8. Extract proposalId from event
    const event = receipt.events?.find((e) => e.event === "ProposalCreated");
    const proposalId = event?.args?.proposalId;

    console.log("Proposal created on-chain:", proposalId);

    return {
      success: true,
      proposalId,
      txHash: receipt.transactionHash,
    };
  } catch (error) {
    console.error("Error submitting proposal:", error);
    return {
      success: false,
      error: error.message,
    };
  }
}
```

---

## Frontend Integration

### Display Candidate with All Versions

```typescript
interface CandidateVersion {
  uid: string;
  versionNumber: number;
  proposalId: string;
  metadata: {
    title: string;
    description: string;
    transactionBundles: any[];
    discussionUrl?: string;
  };
  targets: string[];
  values: BigNumber[];
  calldatas: string[];
  signatureCount: number;
  totalVotingPower: BigNumber;
  createdAt: number;
}

interface Candidate {
  candidateId: string;
  proposer: string;
  versions: CandidateVersion[];
  commentCount: number;
  currentSentiment: {
    for: number;
    against: number;
    abstain: number;
  };
}

function CandidateView({ candidateId }: { candidateId: string }) {
  const [candidate, setCandidate] = useState<Candidate | null>(null);

  useEffect(() => {
    async function load() {
      // Fetch all versions
      const versions = await getCandidateVersions(graphqlClient, candidateId);

      // For each version, get signature count
      const versionsWithSigs = await Promise.all(
        versions.map(async (v) => {
          const sigs = await getSignaturesForVersion(graphqlClient, v.uid);
          const validSigs = sigs.filter((s) => !s.revoked && Date.now() / 1000 < s.deadline);

          return {
            ...v,
            signatureCount: validSigs.length,
            totalVotingPower: await calculateTotalVotingPower(validSigs),
          };
        })
      );

      // Get comments with sentiment
      const comments = await getCandidateComments(graphqlClient, candidateId);

      // Calculate current sentiment (latest from each user)
      const sentimentByUser = new Map();
      comments.forEach((comment) => {
        const existing = sentimentByUser.get(comment.commenter);
        if (!existing || comment.createdAt > existing.createdAt) {
          sentimentByUser.set(comment.commenter, comment);
        }
      });

      const currentSentiment = {
        for: Array.from(sentimentByUser.values()).filter((c) => c.support === 0).length,
        against: Array.from(sentimentByUser.values()).filter((c) => c.support === 1).length,
        abstain: Array.from(sentimentByUser.values()).filter((c) => c.support === 2).length,
      };

      setCandidate({
        candidateId,
        proposer: versionsWithSigs[0].attester, // Proposer from EAS attester
        versions: versionsWithSigs,
        commentCount: comments.length,
        currentSentiment,
      });
    }
    load();
  }, [candidateId]);

  if (!candidate) return <Loading />;

  // Find leading version (most signatures)
  const leadingVersion = candidate.versions.reduce((prev, current) =>
    current.signatureCount > prev.signatureCount ? current : prev
  );

  return (
    <div className="candidate-view">
      {/* Header */}
      <div className="candidate-header">
        <h1>{leadingVersion.metadata.title}</h1>
        <p>
          By: <Address address={candidate.proposer} />
        </p>
        <div className="stats">
          <span>{candidate.versions.length} versions</span>
          <span>{candidate.commentCount} comments</span>
        </div>
        <div className="sentiment">
          <span className="for">👍 {candidate.currentSentiment.for} FOR</span>
          <span className="against">👎 {candidate.currentSentiment.against} AGAINST</span>
          <span className="abstain">🤷 {candidate.currentSentiment.abstain} ABSTAIN</span>
        </div>
      </div>

      {/* Versions */}
      <div className="versions">
        <h2>Versions</h2>
        {candidate.versions
          .sort((a, b) => b.versionNumber - a.versionNumber)
          .map((version) => (
            <VersionCard
              key={version.uid}
              version={version}
              isLeading={version.uid === leadingVersion.uid}
              canSubmit={version.signatureCount >= SIGNATURE_THRESHOLD}
            />
          ))}
      </div>

      {/* Actions */}
      <div className="actions">
        <button onClick={() => createNewVersion(candidateId)}>Create New Version</button>
      </div>
    </div>
  );
}
```

---

### Version Card Component

```typescript
function VersionCard({
  version,
  isLeading,
  canSubmit,
}: {
  version: CandidateVersion;
  isLeading: boolean;
  canSubmit: boolean;
}) {
  const [signatures, setSignatures] = useState([]);
  const [threshold, setThreshold] = useState(0);
  const [canSign, setCanSign] = useState(false);

  useEffect(() => {
    async function load() {
      const sigs = await getSignaturesForVersion(graphqlClient, version.uid);
      setSignatures(sigs.filter((s) => !s.revoked && Date.now() / 1000 < s.deadline));

      const thresh = await governor.proposalThreshold();
      setThreshold(thresh);

      // Check if current user can sign
      const userVotes = await getUserVotingPower();
      const userAddress = await signer.getAddress();
      const alreadySigned = sigs.some(
        (s) => s.attester.toLowerCase() === userAddress.toLowerCase()
      );
      setCanSign(userVotes > 0 && !alreadySigned && userAddress !== version.attester);
    }
    load();
  }, [version.uid]);

  const progress = Math.min((version.totalVotingPower / threshold) * 100, 100);

  return (
    <div className={`version-card ${isLeading ? "leading" : ""}`}>
      {/* Header */}
      <div className="version-header">
        <h3>
          Version {version.versionNumber}
          {isLeading && <span className="badge">Most Signed</span>}
        </h3>
        <time>{new Date(version.createdAt * 1000).toLocaleDateString()}</time>
      </div>

      {/* Content */}
      <div className="version-content">
        <h4>{version.metadata.title}</h4>
        <p>{version.metadata.description}</p>

        {version.metadata.discussionUrl && (
          <a href={version.metadata.discussionUrl} target="_blank">
            Discussion →
          </a>
        )}
      </div>

      {/* Transaction Bundles */}
      <div className="transactions">
        <h5>Transactions ({version.metadata.transactionBundles.length})</h5>
        <ul>
          {version.metadata.transactionBundles.map((bundle, i) => (
            <li key={i}>
              <strong>{bundle.type}</strong>: {bundle.summary} ({bundle.callCount} calls)
            </li>
          ))}
        </ul>
      </div>

      {/* Signature Progress */}
      <div className="signature-progress">
        <div className="progress-bar">
          <div className="progress-fill" style={{ width: `${progress}%` }} />
        </div>
        <p>
          {version.signatureCount} signatures (
          {ethers.utils.formatUnits(version.totalVotingPower, 0)} /{" "}
          {ethers.utils.formatUnits(threshold, 0)} voting power)
        </p>
      </div>

      {/* Signers */}
      <div className="signers">
        {signatures.map((sig) => (
          <Avatar key={sig.uid} address={sig.attester} />
        ))}
      </div>

      {/* Actions */}
      <div className="actions">
        {canSign && <button onClick={() => signVersion(version)}>Sign This Version</button>}

        {canSubmit && (
          <button className="primary" onClick={() => submitVersion(version.uid)}>
            Submit to Governor
          </button>
        )}
      </div>
    </div>
  );
}
```

---

## Subgraph Integration

### Schema Extensions

```graphql
# Proposal Candidate (version)
type ProposalCandidateVersion @entity {
  id: ID! # candidateVersionUID (EAS attestation UID)
  candidateId: Bytes!
  salt: Bytes!
  attester: Bytes! # The proposer/creator (from EAS attestation)
  versionNumber: BigInt!
  targets: [Bytes!]!
  values: [BigInt!]!
  calldatas: [Bytes!]!
  description: String! # Raw JSON string
  proposalId: Bytes!
  createdAt: BigInt! # From event.block.timestamp (not stored in schema)
  # Parsed from description JSON
  title: String!
  summary: String!
  discussionUrl: String

  # Relations
  signatures: [CandidateSponsorSignature!]! @derivedFrom(field: "version")

  # Aggregates
  signatureCount: BigInt!
  totalVotingPower: BigInt!
}

# Candidate Group (virtual grouping by candidateId)
type ProposalCandidateGroup @entity {
  id: ID! # candidateId
  proposer: Bytes! # The creator (attester from first version)
  salt: Bytes!
  createdAt: BigInt! # First version timestamp
  # Relations
  versions: [ProposalCandidateVersion!]! @derivedFrom(field: "candidateId")
  comments: [CandidateComment!]! @derivedFrom(field: "candidate")

  # Aggregates
  versionCount: BigInt!
  commentCount: BigInt!
  latestVersionNumber: BigInt!
  leadingVersion: ProposalCandidateVersion # Version with most signatures
  # Sentiment aggregates (from latest comment of each user)
  currentForCount: BigInt! # Users whose latest comment is FOR
  currentAgainstCount: BigInt! # Users whose latest comment is AGAINST
  currentAbstainCount: BigInt! # Users whose latest comment is ABSTAIN
}

# Comment with integrated sentiment
type CandidateComment @entity {
  id: ID! # attestationUID
  candidate: Bytes! # candidateId
  commenter: Bytes!
  support: Int! # 0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE
  comment: String! # Can be empty string
  parentComment: CandidateComment # optional (for threading)
  createdAt: BigInt!

  # Relations
  replies: [CandidateComment!]! @derivedFrom(field: "parentComment")
}

# Sponsor Signature
type CandidateSponsorSignature @entity {
  id: ID! # attestationUID
  version: ProposalCandidateVersion!
  signer: Bytes!
  proposalId: Bytes!
  nonce: BigInt!
  deadline: BigInt!
  signature: Bytes!
  revoked: Boolean!
  createdAt: BigInt!
  votingPower: BigInt!
}
```

### Useful Queries

```graphql
# Get all candidates (grouped) with sentiment
query GetAllCandidates {
  proposalCandidateGroups(orderBy: createdAt, orderDirection: desc) {
    id
    proposer
    versionCount
    commentCount
    latestVersionNumber
    currentForCount
    currentAgainstCount
    currentAbstainCount
    leadingVersion {
      id
      title
      signatureCount
    }
  }
}

# Get candidate with all versions and sentiment
query GetCandidate($candidateId: ID!) {
  proposalCandidateGroup(id: $candidateId) {
    id
    proposer
    salt
    versionCount
    commentCount
    currentForCount
    currentAgainstCount
    currentAbstainCount
    versions(orderBy: versionNumber, orderDirection: asc) {
      id
      versionNumber
      title
      summary
      description
      targets
      values
      calldatas
      proposalId
      signatureCount
      totalVotingPower
      createdAt
      signatures(where: { revoked: false }) {
        signer
        votingPower
        deadline
      }
    }
    comments(orderBy: createdAt, orderDirection: asc) {
      id
      commenter
      support # 0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE
      comment
      createdAt
      parentComment {
        id
      }
      replies {
        id
        commenter
        support
        comment
        createdAt
      }
    }
  }
}

# Get current sentiment (latest from each user)
query GetCurrentSentiment($candidateId: Bytes!) {
  # Get all comments for candidate
  candidateComments(where: { candidate: $candidateId }, orderBy: createdAt, orderDirection: desc) {
    id
    commenter
    support
    comment
    createdAt
  }
}
# Note: Frontend must dedupe by commenter and take latest

# Get signatures for a version (ready for submission)
query GetVersionSignatures($candidateVersionUID: ID!) {
  proposalCandidateVersion(id: $candidateVersionUID) {
    id
    attester # The proposer/creator
    proposalId
    description
    targets
    values
    calldatas
    signatures(where: { revoked: false }, orderBy: signer, orderDirection: asc) {
      signer
      nonce
      deadline
      signature
    }
  }
}
```

---

## Security Considerations

### 1. Salt Security

- **Storage**: Salt is stored in EAS attestation (public)
- **Collision**: Extremely unlikely with 32-byte random values
- **Tampering**: Immutable once attested
- **Reuse**: Must query previous version to get correct salt

### 2. CandidateId Integrity

- **Calculation**: Must use same formula as initial version
- **Verification**: Frontend should verify candidateId matches before creating new version
- **Uniqueness**: Unique per (proposer, salt) pair

### 3. ProposalId Integrity

- **Critical**: Must match Governor contract calculation exactly
- **Changes**: Every version has different proposalId (different content)
- **Signatures**: Bound to specific proposalId

### 4. Signature Expiry

- **Always validate** `deadline` before submission
- **Recommend**: 24-48 hour deadlines for coordination
- **Frontend**: Show expiry countdown

### 5. Nonce Invalidation

- **Check**: Verify nonce matches on-chain before submission
- **Warning**: Nonce changes if signer sponsors another proposal
- **UX**: Notify sponsors if their signature becomes invalid

### 6. Proposer Verification

- **Immutable**: Proposer set in v1, must remain same
- **Validation**: Verify proposer matches attester
- **Signatures**: All signatures must reference same proposer

### 7. Signature Revocation

- **EAS Built-in**: Sponsors can revoke attestations
- **Filter**: Frontend MUST exclude revoked signatures
- **Check**: Query `revoked` field before submission

### 8. Version Ordering

- **Trust**: versionNumber is self-reported
- **Validation**: Subgraph should verify sequential ordering
- **Display**: Show versions in chronological order

### 9. Signer Ordering

- **Critical**: Must sort by address before calling `proposeBySigs`
- **Contract Requirement**: Will revert if not sorted
- **Implementation**: Use `.sort()` on addresses

### 10. Gas Considerations

- **Large Arrays**: targets/values/calldatas can be large
- **EAS Limit**: Consider chunking very large proposals
- **Alternative**: Store large calldata on IPFS, reference in description

---

## Summary

### Schema UIDs (To Be Deployed)

| Schema                    | UID     | Revocable        | Purpose                                           |
| ------------------------- | ------- | ---------------- | ------------------------------------------------- |
| ProposalCandidate         | `0x...` | No               | Proposal versions with execution data             |
| CandidateComment          | `0x...` | No (append-only) | Discussion + sentiment (FOR/AGAINST/ABSTAIN/NONE) |
| CandidateSponsorSignature | `0x...` | Yes              | Formal EIP-712 signatures for submission          |

**Total:** 3 schemas (simplified from original 5)

### Key Design Principles

✅ **Self-Contained**: Salt stored in attestation, no off-chain dependencies
✅ **Permissionless**: Anyone can create candidates
✅ **Parallel Versioning**: Versions compete for signatures
✅ **Democratic**: Most-signed version wins
✅ **Transparent**: All data on-chain via EAS
✅ **Compatible**: Direct integration with `proposeBySigs`
✅ **Familiar**: JSON format matches existing proposal structure
✅ **Unified Sentiment**: Comments + votes in one schema
✅ **Append-Only History**: Full evolution of opinions preserved
✅ **Candidate-Level Feedback**: Opinions evolve with versions

### Workflow Summary

1. **Create v1**: Generate salt, create attestation
2. **Community Engages**: Comment + vote (FOR/AGAINST/ABSTAIN/NONE)
3. **Creator Iterates**: Create v2+ based on feedback (reuses salt)
4. **Sentiment Evolves**: Users update opinions via new comments (append-only)
5. **Sponsors Sign**: Each sponsor picks their preferred version
6. **Submit**: Most-signed version goes on-chain via `proposeBySigs`

**Sentiment Flow:**

- User posts FOR on v1
- Creator releases v2 with changes
- User dislikes v2, posts AGAINST (new comment)
- Creator addresses concerns in v3
- User likes v3, posts FOR again (new comment)
- Frontend shows user's latest sentiment: FOR

### Next Steps

1. **Deploy EAS Schemas** on target network(s)
2. **Update Frontend**:
   - Salt generation for v1
   - Salt extraction for v2+
   - Multi-version display
   - Signature collection UI
3. **Extend Subgraph**:
   - Index ProposalCandidate attestations
   - Group by candidateId
   - Parse JSON descriptions
4. **Test Workflow**:
   - Create candidate (v1)
   - Edit candidate (v2, v3)
   - Collect signatures across versions
   - Submit winning version
5. **Launch** with community education

---

**Document Version:** 3.0.0
**Last Updated:** 2026-05-27
**Maintainer:** Protocol Team

---

## Changelog

### v3.5.0 (2026-05-27)

- **BREAKING**: Reordered support values to match standard voting convention
  - Changed from: 0=NONE, 1=FOR, 2=AGAINST, 3=ABSTAIN
  - Changed to: **0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE**
- Updated SUPPORT constants in code examples
- Updated all example attestation data with new support values
- Updated subgraph schema comments and GraphQL queries
- Updated frontend sentiment aggregation code
- **Note**: This matches Governor contract voting patterns (0=AGAINST, 1=FOR, 2=ABSTAIN) but adapted for comments
- **CandidateComment schema needs redeployment** (support value semantics changed)

### v3.4.0 (2026-05-27) - **DEPLOYED TO SEPOLIA**

- **🚀 DEPLOYED**: ProposalCandidate schema redeployed to Sepolia with `createdAt` field removed
- **BREAKING**: Removed redundant `createdAt` field from ProposalCandidate schema
- Timestamp is available from EAS via `event.block.timestamp` (subgraph) or `attestation.time` (SDK)
- Updated schema string: removed `uint64 createdAt` field
- Updated all code examples to remove `createdAt` calculation and encoding
- Updated example attestation data with timestamp notes
- Updated subgraph schema documentation with comment explaining timestamp source
- **Gas savings**: Removes one uint64 (8 bytes) per ProposalCandidate attestation

**Updated Schema String:**

```
bytes32 candidateId,bytes32 salt,uint64 versionNumber,address[] targets,uint256[] values,bytes[] calldatas,string description,bytes32 proposalId
```

**New Sepolia UID:**

- ProposalCandidate: `0x5d1c687645ae02fa0f235cc55ce24ab4e6c1d729f82c281689fd3f9f150932f3` ✅

### v3.3.0 (2026-05-27) - **DEPLOYED TO SEPOLIA**

- **🚀 DEPLOYED**: All three schemas deployed to Sepolia testnet
- **BREAKING**: All schemas are now revocable (changed from mixed revocability)
  - ProposalCandidate: Now revocable (proposers can clean up old versions)
  - CandidateComment: Now revocable (users can delete comments)
  - CandidateSponsorSignature: Remains revocable (sponsors can withdraw)
- Added deployed schema UIDs for Sepolia with EAS Scan links
- Updated code examples to use `revocable: true` for all attestations
- Updated design principles to reflect revocable comments
- Frontend must filter out revoked attestations in queries

**Sepolia Schema UIDs (v3.3.0 - ProposalCandidate now outdated):**

- ProposalCandidate: `0xbb0e97dc7584b3a3d9557cd542382565322414be291ab69fb092586bde09aad0` ❌ (outdated, had `createdAt` field)
- CandidateComment: `0x1decf999b02cbecd8697ae7cf0c4017bc0115adbee476da79634332fdff965b2` ✅ (still valid)
- CandidateSponsorSignature: `0xeb66ca8d752474c808c9922734355ea6ec385c2515d66433aeabbf2a7b9fcaa5` ✅ (still valid)

### v3.2.0 (2026-05-27)

- **BREAKING**: Renamed `versionUID` to `candidateVersionUID` throughout for clarity
- Makes it explicit that the UID references a ProposalCandidate version attestation
- Updated schema string in CandidateSponsorSignature: `versionUID` → `candidateVersionUID`
- Updated all code examples, function parameters, and subgraph queries
- Improved naming consistency: clearly indicates what type of entity is being referenced

### v3.1.0 (2026-05-27)

- **BREAKING**: Removed redundant `proposer` field from `ProposalCandidate` schema
- The proposer/creator is now **implicit** via EAS `attester` field (automatically included in every attestation)
- Updated schema string: removed `address proposer` field
- Updated all code examples to use `attester` instead of `proposer`
- Updated subgraph schemas with comments clarifying `attester` usage
- Gas savings: one less address field per attestation
- Updated candidateId calculation references to use `attester`

### v3.0.0 (2026-05-27)

- **BREAKING**: Combined `CandidateSupport` and `CandidateComment` into single `CandidateComment` schema
- Added `support` field to comments: 0=FOR, 1=AGAINST, 2=ABSTAIN, 3=NONE
- Changed to **append-only** (non-revocable) comments for full history
- **Candidate-level** sentiment (not version-specific) - opinions evolve with versions
- Reduced total schemas from 4 to 3
- Added sentiment evolution examples throughout
- Updated subgraph schema with sentiment aggregates
- Enhanced queries for sentiment tracking

### v2.0.0 (2026-05-27)

- Simplified from 5 schemas to 4 by combining parent and version schemas
- Salt stored in attestation for self-contained version linking
- JSON description format matching existing frontend
- No off-chain dependencies

### v1.0.0 (Initial)

- Original design with separate parent and version schemas
