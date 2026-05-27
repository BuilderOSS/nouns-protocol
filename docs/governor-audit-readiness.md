# Governor Upgrade Audit Readiness

## Scope

This checklist covers governor changes introduced on branch `feat/governor-signed-proposals-updatable-state`.

Reference architecture: `docs/governor-architecture.md`.

Key feature additions:

- `proposeBySigs`
- `updateProposal`
- `updateProposalBySigs`
- `Updatable` proposal state
- `castVoteBySig` ABI upgrade (`bytes` signature path)

## Security Invariants

- Signature validation uses OpenZeppelin `SignatureChecker` for EOA + ERC1271 compatibility.
- Signed proposing uses strict ordered signer list.
- Signed proposing enforces a hard cap of 16 signers per proposal.
- Signed propose/update paths validate each signature and run per-signer `getVotes` before the final threshold check,
  so a proposer can be griefed into an expensive revert path with many valid signers; this is bounded by `MAX_PROPOSAL_SIGNERS` (16).
- Proposer cannot appear in signer set (`PROPOSER_CANNOT_BE_SIGNER`) to avoid vote double counting.
- Signature replay protections:
  - vote signatures use existing `nonces` mapping,
  - propose/update signatures use `proposeSigNonces`,
  - signatures expire via deadline checks.
- Third-party cancellation for signed proposals checks combined proposer + signer votes.
- Proposal updates are only allowed in `Updatable` state.
- No-op proposal updates (same resulting proposal id) revert with `NO_OP_PROPOSAL_UPDATE`.
- For signed proposals, unsigned `updateProposal` is only allowed if proposer met threshold at creation-time reference (`timeCreated - 1`), otherwise `updateProposalBySigs` is required.

## Storage / Upgrade Safety

- Legacy `Proposal` struct layout is preserved (no in-place field insertion).
- New fields are append-only through `GovernorStorageV3` mappings:
  - `_proposalUpdatablePeriod`
  - `proposeSigNonces`
  - `proposalSigners`
  - `proposalUpdatePeriodEnds`
  - `proposalIdReplacedBy`
- `ProposalState.Updatable` is appended to enum tail to preserve existing numeric values.

## User Flow Coverage (Gov.t.sol)

- Member proposer, no signatures:
  - create + standard lifecycle: `test_CreateProposal`, `test_ProposalVoteQueueExecution`
- Caller proposer, with signatures:
  - create: `test_ProposeBySigs`
  - unsigned update blocked if unqualified: `testRevert_UpdateProposalTxsOnSignedProposalWithoutSignaturesForUnqualifiedProposer`
  - signed update path: `test_UpdateProposalBySigs`
- Member proposer, with signatures:
  - proposer can unsigned-update during updatable window if independently qualified: `test_UpdateProposalOnSignedProposalForQualifiedProposer`
- State transitions:
  - `Updatable -> Pending -> Active`: `test_ProposalState_UpdatableToPendingToActive`
- Signed-proposal cancellation semantics:
  - combined-vote threshold for third-party cancellation: `testRevert_CannotCancelSignedProposalWhenCombinedVotesAtThreshold`
  - signer cancel ability: `test_SignerCanCancelSignedProposal`
- Signature edge cases:
  - invalid signer/nonce/expiry: `testRevert_InvalidVoteSigner`, `testRevert_InvalidVoteNonce`, `testRevert_InvalidVoteExpired`
  - proposer in signer set blocked: `testRevert_ProposeBySigsSignerCannotBeProposer`

## Integration / UX Notes

- `castVoteBySig` ABI breaking change:
  - old: `(deadline, v, r, s)`
  - new: `(nonce, deadline, bytes sig)`
- Proposal updates create replacement IDs and mark old proposals canceled.
- Indexers/UI should follow replacement mappings and present revision diffs.
- Read helpers are available for indexer/client consistency:
  - `proposalIdReplacedBy(oldId)`
  - `getProposalSigners(proposalId)`
  - `proposalUpdatePeriodEnd(proposalId)`

## Operational Rollout Checks

- Existing upgraded DAOs: set `_proposalUpdatablePeriod` after governor upgrade (legacy value remains unchanged unless set).
- New DAOs initialized with upgraded governor default to `_proposalUpdatablePeriod = 1 days`.
- Ensure frontends, indexers, and SDK clients migrate to new `castVoteBySig` ABI.
- Verify offchain signature builders use updated EIP-712 payloads and nonce sources.
