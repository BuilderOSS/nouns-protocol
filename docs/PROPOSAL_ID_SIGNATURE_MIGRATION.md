# ProposalId Signature Migration Plan

## Goal

Migrate signed proposal flows from signing transaction payload hash (`txsHash`) to signing canonical `proposalId` so signatures bind to the exact proposal identity used onchain.

## Contract Changes

### 1) EIP-712 typehash updates

- `PROPOSAL_TYPEHASH`
  - From: `Proposal(address proposer,bytes32 txsHash,uint256 nonce,uint256 deadline)`
  - To: `Proposal(address proposer,bytes32 proposalId,uint256 nonce,uint256 deadline)`

- `UPDATE_PROPOSAL_TYPEHASH`
  - From: `UpdateProposal(bytes32 proposalId,address proposer,bytes32 txsHash,uint256 nonce,uint256 deadline)`
  - To: `UpdateProposal(bytes32 proposalId,bytes32 updatedProposalId,address proposer,uint256 nonce,uint256 deadline)`

### 2) `proposeBySigs` verification

- Compute canonical id before signature verification:
  - `proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)), msg.sender)`
- Verify each proposer signature against this `proposalId`.

### 3) `updateProposalBySigs` verification

- Compute canonical updated id:
  - `updatedProposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)), msg.sender)`
- Verify each signature over:
  - `{ oldProposalId, updatedProposalId, proposer, nonce, deadline }`

### 4) Helper cleanup

- Remove transaction-only signature hashing helper (`_hashTxs`) from signed proposal flows.

## Frontend / EAS Candidate Changes

### 1) Candidate data model

When collecting signatures, store and display:

- `targets`
- `values`
- `calldatas`
- `description`
- `proposer` (expected caller of `proposeBySigs`)
- derived `proposalId`

Treat `(targets, values, calldatas, description, proposer)` as immutable for a signature batch.

### 2) Signature payload generation

Generate EIP-712 proposer signatures over:

- `proposer`
- `proposalId`
- `nonce`
- `deadline`

Do not sign `txsHash` for new candidates.

### 3) UX updates

- Show "You are signing proposal ID `<id>`" in wallet confirmation UI.
- If any candidate field changes, invalidate old signatures and require re-collection.
- Include explicit warning in UI: editing description changes `proposalId`.

### 4) Update flow (`updateProposalBySigs`)

For update-signatures, compute and display both:

- `oldProposalId`
- `updatedProposalId`

Signers sign both ids, proposer, nonce, deadline.

## Backward Compatibility and Rollout

Because typehash semantics changed, old `txsHash` signatures are incompatible with new contracts.

### Recommended rollout

1. Deploy upgrade containing new typehashes and verification logic.
2. Frontend feature flag:
   - disabled until upgrade confirmed
   - then enabled for proposalId-signing only
3. Mark pre-upgrade candidates as legacy and non-submittable via `proposeBySigs`.
4. Offer one-click "Clone as V2 Candidate" to regenerate signatures.

### Legacy candidate handling

- Option A (recommended): hard cutover to proposalId signatures.
- Option B: dual-path support in UI for historical chains/contracts only (not for this upgraded governor).

## Indexer / Subgraph Changes

Update any offchain services that reconstruct signature payloads:

- Stop deriving `txsHash` for proposer-signature validity checks.
- Derive canonical `proposalId` from proposal payload and proposer.
- For update signatures, derive `updatedProposalId` and include with `oldProposalId`.

No event schema changes are required for this migration, but offchain signature validation logic must be updated.

## Security and Product Tradeoffs

### Benefits

- Signatures bind to exact executable payload + description + proposer identity.
- Prevents description drift between what users read and what they signed.
- Aligns signatures with canonical onchain proposal identity.

### Tradeoff

- Any change to description or proposer invalidates existing signatures and requires recollection.

## Test Plan

### Contract/unit tests

- `proposeBySigs` succeeds when signature matches computed `proposalId`.
- `proposeBySigs` fails when description differs from signed description.
- `updateProposalBySigs` succeeds only when signature binds `{oldProposalId, updatedProposalId}`.
- `updateProposalBySigs` fails when updated description/calldata differ from signed updated identity.
- signer ordering and nonce checks still enforced.
- ERC-1271 signer flows pass for propose/update/vote paths.

### Existing suite status

- `forge test --match-path test/Gov.t.sol`
- Result: **87 passed, 0 failed**

## Operational Checklist

1. Deploy governor upgrade.
2. Flip frontend to proposalId-signing.
3. Invalidate legacy signature bundles.
4. Re-index if any signature-validation cache exists.
5. Monitor first signed proposal submission end-to-end.
