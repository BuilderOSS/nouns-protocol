# Migration Guide: `castVoteBySig` Breaking Change

**Status:** ⚠️ BREAKING CHANGE
**Affected Version:** v2.1.0+
**Priority:** CRITICAL - Must coordinate before mainnet upgrade

---

## Overview

The `castVoteBySig` function signature has changed to support:
- ERC-1271 smart wallet compatibility
- Explicit nonce tracking (prevents replay attacks)
- Uniform `bytes` signature format (aligns with modern standards)

**This is a BREAKING CHANGE** - old signatures will not work with upgraded Governor contracts.

---

## What Changed

### Old API (v2.0.0 and earlier)

```solidity
function castVoteBySig(
    address _voter,
    bytes32 _proposalId,
    uint256 _support,      // 0 = Against, 1 = For, 2 = Abstain
    uint256 _deadline,
    uint8 _v,              // ECDSA v value
    bytes32 _r,            // ECDSA r value
    bytes32 _s             // ECDSA s value
) external returns (uint256);
```

### New API (v2.1.0+)

```solidity
function castVoteBySig(
    address _voter,
    bytes32 _proposalId,
    uint256 _support,      // 0 = Against, 1 = For, 2 = Abstain
    uint256 _nonce,        // ⬅️ NEW: explicit nonce
    uint256 _deadline,
    bytes calldata _sig    // ⬅️ NEW: full signature bytes (supports ERC-1271)
) external returns (uint256);
```

---

## Key Differences

| Aspect | Old (v2.0.0) | New (v2.1.0+) |
|--------|-------------|---------------|
| **Signature format** | Split `(v, r, s)` | Combined `bytes` |
| **Nonce handling** | Implicit (internal counter) | Explicit parameter |
| **ERC-1271 support** | No (EOA only) | Yes (smart wallets) |
| **Parameter order** | `(voter, id, support, deadline, v, r, s)` | `(voter, id, support, nonce, deadline, sig)` |

---

## Migration Steps for Integrators

### Step 1: Update Function Signature

**Before:**
```javascript
// ethers.js v5
const tx = await governor.castVoteBySig(
  voter,
  proposalId,
  support,
  deadline,
  v,
  r,
  s
);
```

**After:**
```javascript
// ethers.js v5
const nonce = await governor.nonces(voter);
const tx = await governor.castVoteBySig(
  voter,
  proposalId,
  support,
  nonce,      // ⬅️ NEW
  deadline,
  signature   // ⬅️ Combined bytes
);
```

### Step 2: Update EIP-712 Signature Generation

The EIP-712 struct now includes the nonce:

**Before:**
```javascript
const domain = {
  name: await governor.name(),
  version: "1",
  chainId: await ethers.provider.getNetwork().then(n => n.chainId),
  verifyingContract: governor.address
};

const types = {
  Vote: [
    { name: "voter", type: "address" },
    { name: "proposalId", type: "uint256" },  // Note: was uint256, now bytes32
    { name: "support", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" }
  ]
};

const value = {
  voter: voterAddress,
  proposalId,
  support,
  nonce,     // This was fetched internally before
  deadline
};

const signature = await signer._signTypedData(domain, types, value);
```

**After:**
```javascript
const domain = {
  name: await governor.name(),
  version: "1",
  chainId: await ethers.provider.getNetwork().then(n => n.chainId),
  verifyingContract: governor.address
};

const types = {
  Vote: [
    { name: "voter", type: "address" },
    { name: "proposalId", type: "bytes32" },  // ⬅️ Changed from uint256
    { name: "support", type: "uint256" },
    { name: "nonce", type: "uint256" },       // ⬅️ Now explicit
    { name: "deadline", type: "uint256" }
  ]
};

// Fetch nonce BEFORE signing
const nonce = await governor.nonces(voterAddress);

const value = {
  voter: voterAddress,
  proposalId,  // Already bytes32 format
  support,
  nonce,       // ⬅️ Explicitly passed
  deadline
};

const signature = await signer._signTypedData(domain, types, value);
// signature is already in bytes format - no need to split into v,r,s
```

---

## Complete Examples

### ethers.js v5

```javascript
import { ethers } from 'ethers';

async function castVoteBySig(governor, voter, proposalId, support, deadline) {
  // 1. Get the voter's current nonce
  const nonce = await governor.nonces(voter.address);

  // 2. Build EIP-712 domain
  const domain = {
    name: await governor.name(),
    version: "1",
    chainId: (await governor.provider.getNetwork()).chainId,
    verifyingContract: governor.address
  };

  // 3. Define types (note: proposalId is bytes32, not uint256)
  const types = {
    Vote: [
      { name: "voter", type: "address" },
      { name: "proposalId", type: "bytes32" },
      { name: "support", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" }
    ]
  };

  // 4. Build value object
  const value = {
    voter: voter.address,
    proposalId,
    support,
    nonce,
    deadline
  };

  // 5. Sign
  const signature = await voter._signTypedData(domain, types, value);

  // 6. Submit (signature is already bytes, no splitting needed)
  const tx = await governor.castVoteBySig(
    voter.address,
    proposalId,
    support,
    nonce,
    deadline,
    signature
  );

  return tx.wait();
}

// Usage
const proposalId = "0x...";
const support = 1; // For
const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

await castVoteBySig(governor, voterSigner, proposalId, support, deadline);
```

### ethers.js v6

```javascript
import { ethers } from 'ethers';

async function castVoteBySig(governor, voter, proposalId, support, deadline) {
  const nonce = await governor.nonces(voter.address);

  const domain = {
    name: await governor.name(),
    version: "1",
    chainId: (await governor.runner.provider.getNetwork()).chainId,
    verifyingContract: await governor.getAddress()
  };

  const types = {
    Vote: [
      { name: "voter", type: "address" },
      { name: "proposalId", type: "bytes32" },
      { name: "support", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" }
    ]
  };

  const value = {
    voter: voter.address,
    proposalId,
    support,
    nonce,
    deadline
  };

  const signature = await voter.signTypedData(domain, types, value);

  const tx = await governor.castVoteBySig(
    voter.address,
    proposalId,
    support,
    nonce,
    deadline,
    signature
  );

  return tx.wait();
}
```

### viem

```typescript
import { walletClient, publicClient } from './config';
import { parseAbi } from 'viem';

const governorAbi = parseAbi([
  'function name() view returns (string)',
  'function nonces(address) view returns (uint256)',
  'function castVoteBySig(address,bytes32,uint256,uint256,uint256,bytes) returns (uint256)'
]);

async function castVoteBySig(
  governorAddress,
  voter,
  proposalId,
  support,
  deadline
) {
  // 1. Get nonce
  const nonce = await publicClient.readContract({
    address: governorAddress,
    abi: governorAbi,
    functionName: 'nonces',
    args: [voter]
  });

  // 2. Sign typed data
  const signature = await walletClient.signTypedData({
    account: voter,
    domain: {
      name: await publicClient.readContract({
        address: governorAddress,
        abi: governorAbi,
        functionName: 'name'
      }),
      version: '1',
      chainId: await publicClient.getChainId(),
      verifyingContract: governorAddress
    },
    types: {
      Vote: [
        { name: 'voter', type: 'address' },
        { name: 'proposalId', type: 'bytes32' },
        { name: 'support', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' }
      ]
    },
    primaryType: 'Vote',
    message: {
      voter,
      proposalId,
      support,
      nonce,
      deadline
    }
  });

  // 3. Submit
  const hash = await walletClient.writeContract({
    address: governorAddress,
    abi: governorAbi,
    functionName: 'castVoteBySig',
    args: [voter, proposalId, support, nonce, deadline, signature]
  });

  return publicClient.waitForTransactionReceipt({ hash });
}
```

### wagmi v2 React Hook

```typescript
import { useAccount, useSignTypedData, useWriteContract, useReadContract } from 'wagmi';
import { useEffect, useState } from 'react';

function useVoteBySig(governorAddress: `0x${string}`) {
  const { address } = useAccount();
  const [nonce, setNonce] = useState<bigint>();

  // Read voter's current nonce
  const { data: currentNonce } = useReadContract({
    address: governorAddress,
    abi: governorAbi,
    functionName: 'nonces',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  useEffect(() => {
    if (currentNonce !== undefined) {
      setNonce(currentNonce);
    }
  }, [currentNonce]);

  const { signTypedDataAsync } = useSignTypedData();
  const { writeContractAsync } = useWriteContract();

  const castVote = async (
    proposalId: `0x${string}`,
    support: 0 | 1 | 2,
    deadline: bigint
  ) => {
    if (!address || nonce === undefined) {
      throw new Error('Wallet not connected or nonce not loaded');
    }

    // Sign
    const signature = await signTypedDataAsync({
      domain: {
        name: 'NOUN GOV', // Adjust based on your token symbol
        version: '1',
        chainId: 1, // Adjust for your network
        verifyingContract: governorAddress
      },
      types: {
        Vote: [
          { name: 'voter', type: 'address' },
          { name: 'proposalId', type: 'bytes32' },
          { name: 'support', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' }
        ]
      },
      primaryType: 'Vote',
      message: {
        voter: address,
        proposalId,
        support: BigInt(support),
        nonce,
        deadline
      }
    });

    // Submit
    return writeContractAsync({
      address: governorAddress,
      abi: governorAbi,
      functionName: 'castVoteBySig',
      args: [address, proposalId, BigInt(support), nonce, deadline, signature]
    });
  };

  return { castVote, nonce };
}
```

---

## Common Errors and Troubleshooting

### Error: `INVALID_SIGNATURE`

**Cause:** Signature format mismatch or incorrect EIP-712 struct.

**Solution:**
- Ensure `proposalId` is typed as `bytes32` (not `uint256`)
- Fetch nonce BEFORE signing (don't use cached/stale nonce)
- Verify domain separator matches on-chain value

### Error: `INVALID_SIGNATURE_NONCE`

**Cause:** Nonce mismatch between signed value and current on-chain nonce.

**Solution:**
```javascript
// CORRECT: Fetch nonce immediately before signing
const nonce = await governor.nonces(voter);
const signature = await signTypedData(... nonce ...);
await governor.castVoteBySig(..., nonce, ...);

// WRONG: Don't reuse old nonces
const nonce = 5; // Hardcoded or cached - DON'T DO THIS
```

### Error: `EXPIRED_SIGNATURE`

**Cause:** Current `block.timestamp > deadline`.

**Solution:**
- Use reasonable deadline (e.g., 1 hour from now)
- Account for clock skew and block time variability
- If user delays, regenerate signature with new deadline

### Smart Wallet (ERC-1271) Not Working

**Cause:** Smart wallet's `isValidSignature` implementation issue.

**Debug:**
1. Verify wallet implements ERC-1271 correctly
2. Check wallet has approved the signature
3. Test with EOA first to isolate issue

---

## Testing Your Migration

### Testnet Checklist

Before deploying to mainnet:

- [ ] Deploy upgraded Governor to testnet (Sepolia/Base Sepolia)
- [ ] Create test proposal
- [ ] Generate vote signature with NEW format
- [ ] Submit via `castVoteBySig`
- [ ] Verify vote counted correctly
- [ ] Test with both EOA and smart wallet
- [ ] Test nonce increment after each vote

### Compatibility Test Script

```javascript
const { ethers } = require('ethers');

async function testNewVoteBySig(governorAddress, voterPrivateKey) {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const voter = new ethers.Wallet(voterPrivateKey, provider);
  const governor = new ethers.Contract(governorAddress, ABI, provider);

  console.log('Testing new castVoteBySig format...');

  // 1. Check nonce
  const nonceBefore = await governor.nonces(voter.address);
  console.log(`Nonce before: ${nonceBefore}`);

  // 2. Create test proposal (or use existing)
  const proposalId = "0x..."; // Replace with real proposal
  const support = 1; // For
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // 3. Sign and submit
  const domain = {
    name: await governor.name(),
    version: "1",
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: governor.address
  };

  const types = {
    Vote: [
      { name: "voter", type: "address" },
      { name: "proposalId", type: "bytes32" },
      { name: "support", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" }
    ]
  };

  const value = {
    voter: voter.address,
    proposalId,
    support,
    nonce: nonceBefore,
    deadline
  };

  const signature = await voter._signTypedData(domain, types, value);

  const tx = await governor.connect(voter).castVoteBySig(
    voter.address,
    proposalId,
    support,
    nonceBefore,
    deadline,
    signature
  );

  await tx.wait();
  console.log(`✅ Vote cast successfully! Tx: ${tx.hash}`);

  // 4. Verify nonce incremented
  const nonceAfter = await governor.nonces(voter.address);
  console.log(`Nonce after: ${nonceAfter}`);

  if (nonceAfter.eq(nonceBefore.add(1))) {
    console.log('✅ Nonce incremented correctly');
  } else {
    console.error('❌ Nonce did not increment!');
  }
}
```

---

## Timeline and Rollout

### Recommended Schedule

**Weeks 1-2: Preparation**
- Share this guide with all integrators
- Update internal tooling/SDKs
- Test on local fork

**Week 3: Testnet**
- Deploy to testnet
- Run integration tests
- Gather feedback from partners

**Week 4: Coordination**
- Confirm all partners ready
- Schedule mainnet upgrade window
- Prepare communication plan

**Week 5: Mainnet**
- Upgrade Manager contract
- Upgrade first canary DAO
- Monitor for 48 hours

**Week 6+: Rollout**
- Upgrade remaining DAOs
- Provide ongoing support

---

## Support and Resources

- **GitHub Issues:** [nouns-protocol/issues](https://github.com/BuilderOSS/nouns-protocol/issues)
- **Documentation:** `docs/governor-architecture.md`
- **Discord:** [Link to community Discord]
- **Audit Report:** [Link when available]

---

## FAQ

### Q: Do I need to update if I don't use `castVoteBySig`?

**A:** No. Regular `castVote` (direct voting) is unchanged. Only signature-based voting is affected.

### Q: Can I support both old and new formats during transition?

**A:** No. Once Governor is upgraded, only the new format works. This is why coordination is critical.

### Q: What about pending signatures generated with old format?

**A:** They will fail. Users must regenerate signatures after upgrade.

### Q: Does this affect `propose` or `queue` functions?

**A:** No. Only `castVoteBySig` is affected.

### Q: How do I know which version a Governor is running?

**A:** Check the function selector:
```javascript
const selector = governor.interface.getSighash('castVoteBySig');
// Old: "0x..." (7 params)
// New: "0x..." (6 params, different selector)
```

Or check for `proposeSignatureNonce` view function (only in v2.1.0+):
```javascript
try {
  await governor.proposeSignatureNonce(someAddress);
  console.log('v2.1.0+');
} catch {
  console.log('v2.0.0 or earlier');
}
```

---

**Last Updated:** 2026-05-20
**Maintainers:** Builder Protocol Team
**Questions?** Open an issue or reach out on Discord
