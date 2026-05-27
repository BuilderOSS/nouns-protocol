# Frontend Migration Guide: Governor V2 Upgrade

This guide helps frontend developers migrate their applications to support the upgraded Governor contract with updatable proposals and signature-based sponsorship.

## Breaking Changes

### 1. `castVoteBySig` ABI Change

**CRITICAL**: The function signature for `castVoteBySig` has changed. This is a **versioned breaking change** — the Governor contract version has been bumped from 2.0.0 to 2.1.0.

**⚠️ IMPORTANT**: Old vote-signing code will **stop working** immediately after a DAO upgrades to Governor v2.1.0. Frontends must coordinate their deployment with the on-chain upgrade. See the `upgrade-runbook.md` for rollout sequencing guidance.

#### Old ABI (V1)
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

#### New ABI (V2)
```solidity
function castVoteBySig(
    address voter,
    bytes32 proposalId,
    uint256 support,
    uint256 nonce,
    uint256 deadline,
    bytes calldata sig
) external returns (uint256);
```

#### Key Differences
1. **Added `nonce` parameter** (before `deadline`)
2. **Replaced `v, r, s` with `bytes sig`** (supports both ECDSA and ERC-1271)
3. **Parameter order changed**

---

## Migration Steps

### Step 1: Update Vote Signature Construction

#### Old Code (V1)
```javascript
// V1 - Using ethers.js v5
const domain = {
  name: `${tokenSymbol} GOV`,
  version: '1',
  chainId: chainId,
  verifyingContract: governorAddress
};

const types = {
  Vote: [
    { name: 'voter', type: 'address' },
    { name: 'proposalId', type: 'bytes32' },
    { name: 'support', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

const value = {
  voter: voterAddress,
  proposalId: proposalId,
  support: support, // 0 = Against, 1 = For, 2 = Abstain
  deadline: deadline
};

const signature = await signer._signTypedData(domain, types, value);
const { v, r, s } = ethers.utils.splitSignature(signature);

// Submit to contract
await governor.castVoteBySig(voterAddress, proposalId, support, deadline, v, r, s);
```

#### New Code (V2)
```javascript
// V2 - Using ethers.js v5
const domain = {
  name: `${tokenSymbol} GOV`,
  version: '1',
  chainId: chainId,
  verifyingContract: governorAddress
};

const types = {
  Vote: [
    { name: 'voter', type: 'address' },
    { name: 'proposalId', type: 'bytes32' },
    { name: 'support', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

// Fetch current nonce for voter
const nonce = await governor.nonce(voterAddress);

const value = {
  voter: voterAddress,
  proposalId: proposalId,
  support: support, // 0 = Against, 1 = For, 2 = Abstain
  nonce: nonce,
  deadline: deadline
};

const signature = await signer._signTypedData(domain, types, value);

// Submit to contract with bytes signature (no splitting needed)
await governor.castVoteBySig(voterAddress, proposalId, support, nonce, deadline, signature);
```

#### Using ethers.js v6
```javascript
import { ethers } from 'ethers';

const domain = {
  name: `${tokenSymbol} GOV`,
  version: '1',
  chainId: chainId,
  verifyingContract: governorAddress
};

const types = {
  Vote: [
    { name: 'voter', type: 'address' },
    { name: 'proposalId', type: 'bytes32' },
    { name: 'support', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

const nonce = await governor.nonce(voterAddress);

const value = {
  voter: voterAddress,
  proposalId: proposalId,
  support: support,
  nonce: nonce,
  deadline: deadline
};

const signature = await signer.signTypedData(domain, types, value);

await governor.castVoteBySig(voterAddress, proposalId, support, nonce, deadline, signature);
```

---

### Step 2: Add Support for New Proposal Types

#### Signed Proposal Creation

```javascript
// New feature: proposeBySigs. The transaction sender is the proposer.
const proposerAddress = await signer.getAddress();

const domain = {
  name: `${tokenSymbol} GOV`,
  version: '1',
  chainId: chainId,
  verifyingContract: governorAddress
};

const types = {
  Proposal: [
    { name: 'proposer', type: 'address' },
    { name: 'proposalId', type: 'bytes32' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

// Calculate proposal ID
const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));
const proposalId = ethers.utils.keccak256(
  ethers.utils.defaultAbiCoder.encode(
    ['address[]', 'uint256[]', 'bytes[]', 'bytes32', 'address'],
    [targets, values, calldatas, descriptionHash, proposerAddress]
  )
);

// Collect signatures from sponsors (must be sorted by address ascending)
const signers = ['0x123...', '0x456...', '0x789...'].sort(); // MUST be sorted
const proposerSignatures = [];

for (const signerAddress of signers) {
  const nonce = await governor.proposeSignatureNonce(signerAddress);

  const value = {
    proposer: proposerAddress,
    proposalId: proposalId,
    nonce: nonce,
    deadline: deadline
  };

  // Get signature from signer
  const signature = await signerWallet._signTypedData(domain, types, value);

  proposerSignatures.push({
    signer: signerAddress,
    nonce: nonce,
    deadline: deadline,
    sig: signature
  });
}

// Submit signed proposal
await governor.connect(signer).proposeBySigs(
  proposerSignatures,
  targets,
  values,
  calldatas,
  description
);
```

#### Proposal Updates

```javascript
// New feature: updateProposal (for qualified proposers without signatures)
await governor.updateProposal(
  oldProposalId,
  newTargets,
  newValues,
  newCalldatas,
  newDescription,
  'Updated to fix typo in description'
);

// New feature: updateProposalBySigs (requires signer re-approval)
const domain = {
  name: `${tokenSymbol} GOV`,
  version: '1',
  chainId: chainId,
  verifyingContract: governorAddress
};

const types = {
  UpdateProposal: [
    { name: 'proposalId', type: 'bytes32' },
    { name: 'updatedProposalId', type: 'bytes32' },
    { name: 'proposer', type: 'address' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

// Calculate new proposal ID
const updatedDescriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(newDescription));
const updatedProposalId = ethers.utils.keccak256(
  ethers.utils.defaultAbiCoder.encode(
    ['address[]', 'uint256[]', 'bytes[]', 'bytes32', 'address'],
    [newTargets, newValues, newCalldatas, updatedDescriptionHash, proposerAddress]
  )
);

// Collect signatures from the sponsor set for this update.
// The signer set need NOT match the original proposal's signers — signers
// can be added, removed, or replaced entirely, subject to the same
// ordering/uniqueness/threshold rules as proposal creation.
const updateSigners = [...sponsorAddresses].sort(); // MUST be sorted; need not match original

const updateSignatures = [];
for (const signerAddress of updateSigners) {
  const nonce = await governor.proposeSignatureNonce(signerAddress);

  const value = {
    proposalId: oldProposalId,
    updatedProposalId: updatedProposalId,
    proposer: proposerAddress,
    nonce: nonce,
    deadline: deadline
  };

  const signature = await signerWallet._signTypedData(domain, types, value);

  updateSignatures.push({
    signer: signerAddress,
    nonce: nonce,
    deadline: deadline,
    sig: signature
  });
}

await governor.updateProposalBySigs(
  oldProposalId,
  updateSignatures,
  newTargets,
  newValues,
  newCalldatas,
  newDescription,
  'Updated with signer approval'
);
```

---

### Step 3: Update Proposal State Handling

#### New Proposal States

```javascript
// Add new states to your enum/constants
const ProposalState = {
  Pending: 0,
  Active: 1,
  Canceled: 2,
  Defeated: 3,
  Succeeded: 4,
  Queued: 5,
  Expired: 6,
  Executed: 7,
  Vetoed: 8,
  Updatable: 9,    // NEW
  Replaced: 10      // NEW
};

// Update state display logic
function getProposalStateLabel(state) {
  switch(state) {
    case ProposalState.Updatable:
      return 'Updatable';
    case ProposalState.Replaced:
      return 'Replaced';
    // ... other states
  }
}

// Handle proposal replacements in UI
async function getLatestProposalId(proposalId) {
  let currentId = proposalId;
  let replacedBy = await governor.proposalIdReplacedBy(currentId);

  // Follow replacement chain to get latest version
  while (replacedBy !== ethers.constants.HashZero) {
    currentId = replacedBy;
    replacedBy = await governor.proposalIdReplacedBy(currentId);
  }

  return currentId;
}
```

---

### Step 4: Add Updatable Period Display

```javascript
// Show update deadline in proposal UI
async function getProposalUpdateDeadline(proposalId) {
  const updatePeriodEnd = await governor.proposalUpdatePeriodEnd(proposalId);
  return new Date(updatePeriodEnd.toNumber() * 1000);
}

// Check if proposal can be updated
async function canUpdateProposal(proposalId) {
  const state = await governor.state(proposalId);
  return state === ProposalState.Updatable;
}

// Display in UI
const updateDeadline = await getProposalUpdateDeadline(proposalId);
const canUpdate = await canUpdateProposal(proposalId);

if (canUpdate) {
  console.log(`Proposal can be updated until ${updateDeadline.toLocaleString()}`);
}
```

---

### Step 5: Update Timeline Calculations

#### Old Timeline (V1)
```javascript
const voteStart = creationTime + votingDelay;
const voteEnd = voteStart + votingPeriod;
```

#### New Timeline (V2)
```javascript
const proposalUpdatablePeriod = await governor.proposalUpdatablePeriod();
const votingDelay = await governor.votingDelay();
const votingPeriod = await governor.votingPeriod();

const updatePeriodEnd = creationTime + proposalUpdatablePeriod;
const voteStart = updatePeriodEnd + votingDelay;
const voteEnd = voteStart + votingPeriod;
```

---

## ERC-1271 Smart Wallet Support

The new signature system supports ERC-1271 smart contract wallets:

```javascript
// Example: Using a Gnosis Safe or other smart wallet
// The signature format is the same, but verification happens via ERC-1271

// For smart wallets, you'll need to:
// 1. Get the signature approval from the smart wallet
// 2. The wallet's isValidSignature(hash, signature) will be called on-chain

// The frontend doesn't need special handling - just pass the bytes signature
// The Governor contract automatically detects if the signer is a contract
// and uses ERC-1271 verification instead of ECDSA recovery
```

---

## Nonce Management

### Vote Nonces
```javascript
// Each voter has a separate nonce for vote signatures
const voteNonce = await governor.nonce(voterAddress);
```

### Propose/Update Nonces
```javascript
// Each proposer/signer has a separate nonce for proposal signatures
const proposeNonce = await governor.proposeSignatureNonce(signerAddress);
```

### Important
- Nonces increment with each signature use
- Nonces prevent signature replay
- Track nonces separately for votes vs proposals
- Failed transactions **do not** increment nonces (only successful ones do)

---

## Migration Checklist

- [ ] Update `castVoteBySig` function calls to new signature
- [ ] Implement nonce fetching for vote signatures
- [ ] Change signature format from `{v,r,s}` to `bytes`
- [ ] Add support for `Updatable` and `Replaced` states
- [ ] Implement proposal update UI/logic
- [ ] Add proposal replacement tracking
- [ ] Update timeline calculations to include update period
- [ ] Display update deadline for updatable proposals
- [ ] Add signed proposal creation flow (optional)
- [ ] Handle proposal signers display (optional)
- [ ] Test with both EOA and smart wallet signers
- [ ] Update ABI files from new contract deployment

---

## Example: Complete Vote-by-Signature Flow

```javascript
import { ethers } from 'ethers';

async function castVoteBySig(governor, voter, signer, proposalId, support) {
  // 1. Get token symbol for domain
  const tokenAddress = await governor.token();
  const token = new ethers.Contract(tokenAddress, tokenAbi, provider);
  const symbol = await token.symbol();

  // 2. Get current nonce
  const nonce = await governor.nonce(voter);

  // 3. Set deadline (e.g., 1 hour from now)
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // 4. Prepare EIP-712 domain and types
  const domain = {
    name: `${symbol} GOV`,
    version: '1',
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: governor.address
  };

  const types = {
    Vote: [
      { name: 'voter', type: 'address' },
      { name: 'proposalId', type: 'bytes32' },
      { name: 'support', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };

  const value = {
    voter: voter,
    proposalId: proposalId,
    support: support,
    nonce: nonce,
    deadline: deadline
  };

  // 5. Sign
  const signature = await signer._signTypedData(domain, types, value);

  // 6. Submit to contract
  const tx = await governor.castVoteBySig(
    voter,
    proposalId,
    support,
    nonce,
    deadline,
    signature
  );

  await tx.wait();
  console.log('Vote cast successfully!');
}
```

---

## Testing Your Migration

### Test Cases to Verify

1. **Basic vote-by-sig** with EOA
2. **Vote-by-sig** with expired deadline (should revert)
3. **Vote-by-sig** with wrong nonce (should revert)
4. **Signed proposal creation** with multiple signers
5. **Proposal update** during updatable period
6. **Proposal update** after updatable period (should revert)
7. **Proposal replacement chain** tracking
8. **Timeline calculations** including update period

### Quick Test Script

```javascript
// Test that signature construction works
const testVoteSignature = async () => {
  const nonce = await governor.nonce(voterAddress);
  console.log('Current nonce:', nonce.toString());

  // Try to cast vote
  try {
    await castVoteBySig(governor, voterAddress, signer, proposalId, 1);
    console.log('✅ Vote signature working');
  } catch (error) {
    console.error('❌ Vote signature failed:', error);
  }
};
```

---

## Support and Resources

- **Governor Contract**: `src/governance/governor/Governor.sol`
- **Architecture Doc**: `docs/governor-architecture.md`
- **Proposal Lifecycle**: `docs/governor-proposal-lifecycle.md`
- **Audit Readiness**: `docs/governor-audit-readiness.md`

For questions or issues, please refer to the protocol documentation or open an issue in the repository.
