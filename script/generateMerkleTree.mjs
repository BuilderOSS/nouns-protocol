#!/usr/bin/env node

/**
 * Merkle Tree Generator for MerklePropertyIPFS Testing
 *
 * This script generates merkle trees for testing the MerklePropertyIPFS contract.
 * It uses the correct encoding method that matches Solidity's abi.encodePacked behavior:
 * encodePacked(['uint256', 'uint16[16]'], [tokenId, [attr0, attr1, ...]])
 *
 * The Solidity contract uses: keccak256(abi.encodePacked(tokenId, attributes))
 * where attributes is uint16[16]
 */

import { keccak256, encodePacked } from "viem";

/**
 * Generate a leaf hash using the correct encoding method
 * This matches Solidity's abi.encodePacked(uint256, uint16[16])
 */
function generateLeaf(tokenId, attributes) {
  if (attributes.length !== 16) {
    throw new Error("Attributes must have exactly 16 elements");
  }

  const encoded = encodePacked(["uint256", "uint16[16]"], [tokenId, attributes]);
  const hash = keccak256(encoded);

  return { hash, encoded, length: (encoded.length - 2) / 2 };
}

/**
 * Build a merkle tree from leaves
 * Uses sorted pairs as per OpenZeppelin standard
 */
function buildMerkleTree(leaves) {
  if (leaves.length === 0) {
    throw new Error("Cannot build tree from empty leaves");
  }

  if (leaves.length === 1) {
    return {
      root: leaves[0],
      layers: [leaves],
    };
  }

  const layers = [leaves];

  while (layers[layers.length - 1].length > 1) {
    const currentLayer = layers[layers.length - 1];
    const nextLayer = [];

    for (let i = 0; i < currentLayer.length; i += 2) {
      if (i + 1 < currentLayer.length) {
        const left = currentLayer[i];
        const right = currentLayer[i + 1];

        // Sort hashes before combining (OpenZeppelin standard)
        const sortedPair = left < right ? [left, right] : [right, left];
        const combined = keccak256(encodePacked(["bytes32", "bytes32"], sortedPair));
        nextLayer.push(combined);
      } else {
        // Odd number of nodes, promote the last one
        nextLayer.push(currentLayer[i]);
      }
    }

    layers.push(nextLayer);
  }

  return {
    root: layers[layers.length - 1][0],
    layers,
  };
}

/**
 * Generate a merkle proof for a given leaf index
 */
function generateProof(tree, leafIndex) {
  const proof = [];
  let currentIndex = leafIndex;

  for (let layerIndex = 0; layerIndex < tree.layers.length - 1; layerIndex++) {
    const layer = tree.layers[layerIndex];
    const isLeftNode = currentIndex % 2 === 0;
    const siblingIndex = isLeftNode ? currentIndex + 1 : currentIndex - 1;

    if (siblingIndex < layer.length) {
      proof.push(layer[siblingIndex]);
    }

    currentIndex = Math.floor(currentIndex / 2);
  }

  return proof;
}

/**
 * Verify a merkle proof
 */
function verifyProof(proof, root, leaf) {
  let computedHash = leaf;

  for (const proofElement of proof) {
    const sortedPair =
      computedHash < proofElement ? [computedHash, proofElement] : [proofElement, computedHash];
    computedHash = keccak256(encodePacked(["bytes32", "bytes32"], sortedPair));
  }

  return computedHash === root;
}

/**
 * Main function
 */
function main() {
  console.log("=".repeat(80));
  console.log("MerklePropertyIPFS Tree Generation");
  console.log("=".repeat(80));

  // Test data: 4 tokens with different attributes
  const tokens = [
    {
      tokenId: 0n,
      attributes: [1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    },
    {
      tokenId: 1n,
      attributes: [5, 8, 4, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    },
    {
      tokenId: 2n,
      attributes: [10, 15, 20, 25, 30, 35, 40, 45, 0, 0, 0, 0, 0, 0, 0, 0],
    },
    {
      tokenId: 3n,
      attributes: [
        100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600,
      ],
    },
  ];

  console.log("\n" + "=".repeat(80));
  console.log("GENERATING LEAVES");
  console.log("=".repeat(80));

  const leaves = tokens.map((token) => {
    const result = generateLeaf(token.tokenId, token.attributes);
    console.log(`\nToken ${token.tokenId}:`);
    console.log(`  Attributes: [${token.attributes.join(", ")}]`);
    console.log(`  Encoded length: ${result.length} bytes`);
    console.log(`  Leaf hash: ${result.hash}`);
    return result.hash;
  });

  const tree = buildMerkleTree(leaves);
  console.log(`\n${"=".repeat(80)}`);
  console.log(`Merkle Root: ${tree.root}`);
  console.log("=".repeat(80));

  // Generate and verify proofs
  console.log("\n" + "=".repeat(80));
  console.log("PROOFS");
  console.log("=".repeat(80));

  tokens.forEach((token, index) => {
    const proof = generateProof(tree, index);
    const isValid = verifyProof(proof, tree.root, leaves[index]);
    console.log(`\nToken ${token.tokenId}:`);
    console.log(
      `  Proof: [${proof.map((p) => `\n    ${p}`).join(",")}${proof.length > 0 ? "\n  " : ""}]`,
    );
    console.log(`  Valid: ${isValid}`);
  });

  console.log("\n" + "=".repeat(80));
  console.log("SOLIDITY TEST DATA");
  console.log("=".repeat(80));
  console.log("\nCopy these values for Solidity tests:\n");

  console.log(`bytes32 merkleRoot = ${tree.root};`);

  tokens.forEach((token, index) => {
    const proof = generateProof(tree, index);
    console.log(`\n// Token ${token.tokenId}:`);
    console.log(`bytes32[] memory proof${token.tokenId} = new bytes32[](${proof.length});`);
    proof.forEach((p, i) => {
      console.log(`proof${token.tokenId}[${i}] = ${p};`);
    });
  });

  console.log("\n" + "=".repeat(80));
  console.log("ENCODING DETAILS");
  console.log("=".repeat(80));
  console.log("\nSolidity uses abi.encodePacked(uint256, uint16[16])");
  console.log("Each uint16 in the array is padded to 32 bytes");
  console.log("Total: 32 bytes (uint256) + 512 bytes (16 × 32) = 544 bytes\n");
  console.log("=".repeat(80) + "\n");
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { generateLeaf, buildMerkleTree, generateProof, verifyProof };
