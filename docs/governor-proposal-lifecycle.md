# Governor Proposal Lifecycle Reference

This is a practical reference for how proposals move through governance in this protocol, which periods control each phase, where each value is read onchain, and who can update it.

## Quick Mental Model

- A proposal has an edit window first (`Updatable`), then a voting delay (`Pending`), then voting (`Active`).
- If voting succeeds, it moves to treasury timelock (`Queued`) and can be executed.
- Proposal identity is hash-based. Any tx-bundle or description change creates a new proposal id.
- Proposal updates create a replacement link: old id is canceled, new id becomes canonical.

## Full State Machine

State evaluation is implemented in `Governor.state(proposalId)`.

Priority order:

1. `Executed`
2. `Canceled`
3. `Vetoed`
4. `Updatable` (while `block.timestamp < proposalUpdatePeriodEnd`)
5. `Pending` (after update window, before vote start)
6. `Active` (between vote start and vote end)
7. `Defeated` (outvoted or quorum not met)
8. `Succeeded` (passed but not queued yet)
9. `Expired` (queued but treasury grace period elapsed)
10. `Queued`

Terminal states are `Executed`, `Canceled`, `Vetoed`, and `Expired`.

## Timeline Formula

At proposal creation (`_createProposal`):

- `updatePeriodEnd = now + proposalUpdatablePeriod`
- `voteStart = updatePeriodEnd + votingDelay`
- `voteEnd = voteStart + votingPeriod`

For updated proposals, these timestamps are preserved from the original proposal and copied to the replacement id.
This means chained updates share a single update window: if A is updated to B and B to C,
all revisions use A's original `proposalUpdatePeriodEnd`.

## Periods and Parameters

### Governor Periods

| Name                                   | Meaning                                                 | Query                                             | Default (fresh governor init)   | Bounds                      | Who can update                                                                       |
| -------------------------------------- | ------------------------------------------------------- | ------------------------------------------------- | ------------------------------- | --------------------------- | ------------------------------------------------------------------------------------ |
| `proposalUpdatablePeriod`              | How long proposals stay editable after creation         | `Governor.proposalUpdatablePeriod()`              | `1 days`                        | `<= 24 weeks`               | `Governor.updateProposalUpdatablePeriod(...)` (`onlyOwner`)                          |
| `proposalUpdatePeriodEnd`              | Per-proposal timestamp when updates stop                | `Governor.proposalUpdatePeriodEnd(proposalId)`    | Computed per proposal           | N/A                         | Not directly mutable                                                                 |
| `votingDelay`                          | Delay between update window end and vote start          | `Governor.votingDelay()`                          | Deploy-time input (`GovParams`) | `1 second` to `24 weeks`    | `Governor.updateVotingDelay(...)` (`onlyOwner`)                                      |
| `votingPeriod`                         | Duration of active voting window                        | `Governor.votingPeriod()`                         | Deploy-time input (`GovParams`) | `10 minutes` to `24 weeks`  | `Governor.updateVotingPeriod(...)` (`onlyOwner`)                                     |
| `delayedGovernanceExpirationTimestamp` | Optional pre-governance gate for reserve-token launches | `Governor.delayedGovernanceExpirationTimestamp()` | `0` (unless set)                | `<= now + 30 days` when set | `Governor.updateDelayedGovernanceExpirationTimestamp(...)` (token owner only, gated) |

### Treasury Periods

| Name                     | Meaning                                  | Query                    | Default                                       | Who can update                                              |
| ------------------------ | ---------------------------------------- | ------------------------ | --------------------------------------------- | ----------------------------------------------------------- |
| `delay` (timelock delay) | Wait after queue before execution        | `Treasury.delay()`       | Deploy-time input (`GovParams.timelockDelay`) | `Treasury.updateDelay(...)` (treasury-only call path)       |
| `gracePeriod`            | Execution window after eta before expiry | `Treasury.gracePeriod()` | `2 weeks` (in-contract default)               | `Treasury.updateGracePeriod(...)` (treasury-only call path) |

## Creation Paths

### Standard proposal (`propose`)

- Caller must be above proposal threshold at `block.timestamp - 1`.
- Proposal is created with computed timing and threshold/quorum snapshots.

### Sponsored proposal (`proposeBySigs`)

- Requires at least one signature.
- `msg.sender` is the proposal's proposer; callers cannot submit on behalf of a different proposer.
- Signers must be strictly increasing by address (sorted, unique).
- Proposer cannot also appear as a signer.
- Combined votes (proposer + signers) must exceed proposal threshold.
- Signatures are EIP-712 with nonce + deadline replay protection.
- Signer sponsorship is capped: max `16` signers per proposal.
- `proposeBySigs` and `updateProposalBySigs` share the same per-signer nonce mapping (`proposeSigNonces`),
  so off-chain signing flows must sequence propose/update sponsorship signatures against one shared counter.

### Signature Ordering Requirements (CRITICAL)

#### Why Ordering Matters

The `proposeBySigs` and `updateProposalBySigs` functions require signatures to be sorted by signer address in **ascending order** (lowest address to highest address). This is enforced for:

1. **Gas efficiency**: Cheap ordering check vs expensive signature verification
2. **Duplicate prevention**: Ensures no signer counted twice
3. **Deterministic validation**: Consistent validation order

#### Gas Warning

**IMPORTANT**: Signatures are validated (~30k gas each) BEFORE checking if combined votes meet the threshold. If you submit:

- Unsorted signatures → Reverts with `INVALID_SIGNATURE_ORDER` (wastes gas)
- Signatures with insufficient voting power → Reverts with `VOTES_BELOW_PROPOSAL_THRESHOLD` (wastes MORE gas)

**Gas Cost Breakdown:**
| Signers | Validation Gas | Wasted if Wrong Order | Wasted if Below Threshold |
|---------|----------------|----------------------|---------------------------|
| 1 | ~30k | ~30k | ~30k |
| 4 | ~120k | ~120k | ~120k |
| 8 | ~240k | ~240k | ~240k |
| 16 | ~480k | ~480k | ~480k |

#### How to Sort Addresses

**JavaScript/TypeScript:**

```javascript
// Given an array of signers with {address, signature}
const signers = [
  { address: "0xCCC...", signature: "0x..." },
  { address: "0xAAA...", signature: "0x..." },
  { address: "0xBBB...", signature: "0x..." },
];

// Sort by address (case-insensitive)
const sorted = signers.sort((a, b) =>
  a.address.toLowerCase().localeCompare(b.address.toLowerCase()),
);

// Result: [0xAAA, 0xBBB, 0xCCC]
```

**Solidity (for testing/off-chain computation):**

```solidity
function sortAddresses(address[] memory addresses)
  public pure returns (address[] memory)
{
  address[] memory sorted = new address[](addresses.length);
  for (uint i = 0; i < addresses.length; i++) {
    sorted[i] = addresses[i];
  }

  // Insertion sort (sufficient for ≤16 elements)
  for (uint i = 1; i < sorted.length; i++) {
    address current = sorted[i];
    uint j = i;
    while (j > 0 && sorted[j-1] > current) {
      sorted[j] = sorted[j-1];
      j--;
    }
    sorted[j] = current;
  }
  return sorted;
}
```

**Python:**

```python
# Sort list of signer addresses
signers = ["0xCCC...", "0xAAA...", "0xBBB..."]
sorted_signers = sorted(signers, key=str.lower)
# Result: ['0xAAA...', '0xBBB...', '0xCCC...']
```

#### Pre-Flight Validation

To avoid wasting gas, validate voting power BEFORE submitting:

```javascript
// 1. Get current proposal threshold
const threshold = await governor.proposalThreshold();

// 2. Calculate combined voting power
let totalVotes = await governor.getVotes(proposer, lastBlock);
for (const signer of signers) {
  const votes = await governor.getVotes(signer.address, lastBlock);
  totalVotes += votes;
}

// 3. Check threshold before submitting
if (totalVotes <= threshold) {
  throw new Error(`Insufficient votes: ${totalVotes} <= ${threshold}`);
}

// 4. Sort signers
const sortedSigners = signers.sort((a, b) =>
  a.address.toLowerCase().localeCompare(b.address.toLowerCase()),
);

// 5. Submit
await governor.proposeBySigs(sortedSigners, targets, values, calldatas, description);
```

#### Common Pitfalls

❌ **Wrong:** Unsorted addresses

```javascript
signers = [
  { address: "0xCCC...", signature: "..." },
  { address: "0xAAA...", signature: "..." },
]; // WRONG ORDER - will revert
```

❌ **Wrong:** Including proposer as signer

```javascript
signers = [
  { address: proposerAddress, signature: "..." }, // Proposer cannot be signer
];
```

❌ **Wrong:** Duplicate addresses

```javascript
signers = [
  { address: "0xAAA...", signature: "..." },
  { address: "0xAAA...", signature: "..." }, // Duplicate
];
```

✅ **Correct:** Sorted, unique, excluding proposer

```javascript
signers = [
  { address: "0xAAA...", signature: "..." },
  { address: "0xBBB...", signature: "..." },
  { address: "0xCCC...", signature: "..." },
]; // Correct ascending order
```

## Update Paths

### `updateProposal`

- **For unsigned proposals only**. This path reverts if the proposal has any signers.
- Allowed only while proposal state is `Updatable`.
- Caller must be the original proposer.
- Signed proposals must use `updateProposalBySigs` instead.

### `updateProposalBySigs`

- **For signed proposals** (or to convert an unsigned proposal to a signed one).
- Also only while `Updatable` and proposer-only caller.
- Accepts an arbitrary new signer set, subject to the same ordering/uniqueness/threshold rules as proposal creation.
- The new signer set does NOT need to match the original proposal's signers (can add, remove, or replace signers entirely).
- If the original proposal was unsigned, calling `updateProposalBySigs` with zero signatures is allowed (proposer-only re-hash).

### No-op updates

- If updated content hashes to the same proposal id, update reverts with `NO_OP_PROPOSAL_UPDATE`.
- Re-submitting an earlier revision's exact content does not "undo" an update if that proposal id already exists:
  if that id is already present in storage (for example, the original now-canceled id), the update reverts with `PROPOSAL_EXISTS`.

### Replacement behavior

- New id receives copied metadata (timings, votes, thresholds, signers).
- Old id is marked canceled.
- Link is recorded in `proposalIdReplacedBy(oldId)`.

### Voting Power Snapshot (Frozen at Original Creation)

**IMPORTANT**: When a proposal is updated, the voting power snapshot remains frozen at the **original** `timeCreated` timestamp.

- The `timeCreated` field is deliberately preserved from the original proposal when creating the replacement.
- Voters cast votes weighted by their token balance at the time the proposal was **first created**, NOT when it was updated.
- This prevents proposers from gaming the system by updating proposals to capture favorable snapshots.
- All vote queries use `getVotes(_voter, proposal.timeCreated)`, which points to the original creation time even for updated proposals.

## Query Cheat Sheet

- Current lifecycle state: `Governor.state(proposalId)`
- Full proposal record: `Governor.getProposal(proposalId)`
- Edit-window end: `Governor.proposalUpdatePeriodEnd(proposalId)`
- Vote start: `Governor.proposalSnapshot(proposalId)`
- Vote end: `Governor.proposalDeadline(proposalId)`
- Vote totals: `Governor.proposalVotes(proposalId)`
- Timelock eta: `Governor.proposalEta(proposalId)`
- Signer list: `Governor.getProposalSigners(proposalId)`
- Replacement pointer: `Governor.proposalIdReplacedBy(oldProposalId)`
- Global config:
  - `Governor.proposalUpdatablePeriod()`
  - `Governor.votingDelay()`
  - `Governor.votingPeriod()`
  - `Governor.proposalThresholdBps()`
  - `Governor.quorumThresholdBps()`
  - `Treasury.delay()`
  - `Treasury.gracePeriod()`

## Who Can Change What

- Governor `onlyOwner` settings are DAO-controlled (Governor owner is treasury).
- Treasury delay/grace updates are treasury-only functions, so they are changed through governance execution.
- Delayed governance expiration is special: only token owner can set it, and only under launch-time constraints.

## Defaults and Upgrade Notes

- New DAOs (fresh governor initialization) default to `proposalUpdatablePeriod = 1 day`.
- Existing DAOs upgrading implementation do not rerun initializer, so existing stored value is retained until explicitly updated.
- Most governance knobs (`votingDelay`, `votingPeriod`, thresholds, timelock delay) are deploy-time parameters, not protocol-global hardcoded defaults.

## Common Integration Pitfalls

- Treat proposal ids as revisioned content ids, not permanent mutable objects.
- Always follow `proposalIdReplacedBy` when rendering history.
- Do not assume voting starts at creation + `votingDelay`; it is creation + `proposalUpdatablePeriod` + `votingDelay`.
- Signed sponsorship binds canonical proposal id, including description hash and proposer.
