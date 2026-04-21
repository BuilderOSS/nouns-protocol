# Governor Upgrade Spec (Hybrid EAS + Onchain Sigs)

## Scope

- Add `proposeBySigs` and `updateProposalBySigs` to Governor.
- Add `Updatable -> Pending -> Active` lifecycle.
- Add `updateProposal` for proposer edits in updatable window.
- Keep proposal candidates off-core (EAS + subgraph).
- Make all signature verification ERC-1271 compatible.
- Use nonce + deadline/expiry for vote/propose/update signatures.
- Remove legacy vote-by-sig `v,r,s` API and use uniform `bytes signature` API.

## Non-goals

- No onchain `ProposalCandidates` contract in this phase.
- No Manager deploy flow rewrite required for candidate contracts.
- No full ERC-4337 implementation in this phase (only compatibility-ready flows).

## Lifecycle

For proposal creation:

- `updatePeriodEnd = now + proposalUpdatablePeriod`
- `voteStart = updatePeriodEnd + votingDelay`
- `voteEnd = voteStart + votingPeriod`

State transitions:

- `Updatable` while `now < updatePeriodEnd`
- `Pending` while `now < voteStart`
- `Active` while `now < voteEnd`
- Existing terminal states unchanged.

Updates are disallowed once proposal is `Active`.

## Signature Model

All signatures are EIP-712 and verified with EOA + ERC-1271 support.

- Vote signature: `voter, proposalId, support, nonce, deadline`
- Propose signature: `proposer, txsHash, nonce, deadline`
- Update signature: `proposalId, proposer, txsHash, nonce, deadline`

Notes:

- Signatures for proposal sponsorship bind to tx bundle hash (not description text).
- `updateProposal` allows full edits (description and txs) during `Updatable` when either:
  - the proposal has no signers, or
  - the proposer independently met proposal threshold at creation time.
- `updateProposalBySigs` remains available as an optional stricter path for sponsor re-approval.
- Signer arrays are strict ordered (cheap validation); frontend must sort before submit.

## Proposal Identity & Updates

The current protocol proposal id is hash-based and includes description hash.
Any description/tx change creates a new proposal id.

Update flow:

- Validate old proposal is updatable and caller is proposer.
- Compute new proposal id from updated content.
- Copy proposal timing/requirements metadata to new id.
- Mark old id canceled.
- Emit explicit replacement event `oldProposalId -> newProposalId`.

## Storage Additions

Add append-only `GovernorStorageV3`:

- `proposalUpdatablePeriod`
- `proposeSigNonces`
- `proposalSigners[proposalId]`
- `proposalIdReplacedBy`

Vote signature nonces use the existing EIP-712 `nonces` mapping.

Extend proposal type with:

- no new fields (existing `Proposal` layout remains upgrade-safe)

Add side mappings for:

- `proposalUpdatePeriodEnds[proposalId]`

## Breaking Changes

- `castVoteBySig` ABI changed from `(v, r, s)` to `(nonce, deadline, sig)`.
- Integrations relying on the old selector must migrate to the new signature payload and calldata format.

## Core Functions

- `proposeBySigs(...)`
- `updateProposal(...)`
- `updateProposalBySigs(...)`
- `castVoteBySig(...)` (new bytes signature API)
- `updateProposalUpdatablePeriod(uint256 newPeriod)`

Signature revocation by hash is intentionally omitted; replay protection relies on nonces + deadlines.

## EAS Hybrid Boundary

- EAS provides candidate drafting and revision/discussion UX.
- Governor enforces threshold/signature validity on final promotion and updates.
- Subgraph controls canonical latest draft selection policy.

## Upgrade / Rollout

Existing DAOs:

1. Deploy new Governor implementation.
2. Register upgrade in Manager.
3. Execute Governor proxy `upgradeTo` via DAO ownership path.
4. Set `proposalUpdatablePeriod` via owner/governance setter.

New DAO deploy defaults can be wired in a follow-up Manager update.
