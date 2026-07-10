# MerklePropertyIPFS Encoding Guide

## Overview

The MerklePropertyIPFS contract uses `keccak256(abi.encodePacked(tokenId, attributes))` for leaf generation, where:

- `tokenId` is `uint256`
- `attributes` is `uint16[16]` (fixed-size array)

## Key Finding

**Solidity's `abi.encodePacked()` pads array elements to 32 bytes.**

- Encoding: `abi.encodePacked(uint256, uint16[16])`
- Result: 544 bytes total
  - 32 bytes for `uint256`
  - 512 bytes for `uint16[16]` (each `uint16` padded to 32 bytes)

## JavaScript/TypeScript Implementation

To match Solidity's encoding, use viem's `encodePacked` with array parameter:

```javascript
import { keccak256, encodePacked } from "viem";

function generateLeaf(tokenId, attributes) {
  // attributes must be an array of 16 uint16 values
  const encoded = encodePacked(["uint256", "uint16[16]"], [tokenId, attributes]);

  return keccak256(encoded);
}
```

**Important:** Use the array type `'uint16[16]'`, not individual `'uint16'` parameters.

## Verification

### Run JavaScript Generator

```bash
node script/generateMerkleTree.mjs
```

This generates:

- Merkle tree for 4 sample tokens
- Merkle root
- Proofs for each token
- Solidity-ready test data

### Run Tests

```bash
forge test --match-contract MerklePropertyIPFSTest -vv
```

Key tests:

- `test_EncodingLength()` - Verifies 544-byte encoding
- `test_CrossVerification_JavaScriptAndSolidity()` - Confirms JS matches Solidity
- `test_MultiTokenMerkleTree()` - Tests complete 4-token tree with proofs
- `test_SetManyAttributes()` - Tests batch operations

## Files

- `script/generateMerkleTree.mjs` - Tree generation utility
- `test/utils/MerkleTreeHelper.sol` - Solidity helper for encoding/proof generation
- `test/MerklePropertyIPFS.t.sol` - Comprehensive test suite

All tests pass ✓
