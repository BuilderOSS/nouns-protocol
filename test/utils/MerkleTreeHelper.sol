// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";

/// @title MerkleTreeHelper
/// @notice Helper contract for generating and verifying merkle tree leaves for MerklePropertyIPFS
/// @dev This contract demonstrates the correct encoding method for leaf generation
contract MerkleTreeHelper is Test {
    /// @notice Generate a leaf hash using the contract's encoding method
    /// @dev This matches the encoding used in MerklePropertyIPFS.sol line 91:
    ///      keccak256(abi.encodePacked(_params.tokenId, _params.attributes))
    /// @param tokenId The token ID
    /// @param attributes The attributes array (uint16[16])
    /// @return The leaf hash
    function generateLeaf(uint256 tokenId, uint16[16] memory attributes) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenId, attributes));
    }

    /// @notice Get the raw encoded bytes for debugging
    /// @param tokenId The token ID
    /// @param attributes The attributes array (uint16[16])
    /// @return The encoded bytes
    function getEncodedBytes(uint256 tokenId, uint16[16] memory attributes) public pure returns (bytes memory) {
        return abi.encodePacked(tokenId, attributes);
    }

    /// @notice Get the length of encoded bytes for verification
    /// @param tokenId The token ID
    /// @param attributes The attributes array (uint16[16])
    /// @return The length of encoded bytes
    function getEncodedLength(uint256 tokenId, uint16[16] memory attributes) public pure returns (uint256) {
        return abi.encodePacked(tokenId, attributes).length;
    }

    /// @notice Get encoding details for verification
    /// @param tokenId The token ID
    /// @param attributes The attributes array (uint16[16])
    /// @return encodedLength The length of the encoded data (544 bytes)
    /// @return encodedHash The hash of the encoded data
    function compareEncodingMethods(uint256 tokenId, uint16[16] memory attributes) public pure returns (uint256 encodedLength, bytes32 encodedHash) {
        // abi.encodePacked with array: each uint16 is padded to 32 bytes
        // Expected: 32 bytes (uint256) + 512 bytes (16 * 32 bytes per uint16) = 544 bytes total
        bytes memory encoded = abi.encodePacked(tokenId, attributes);
        encodedLength = encoded.length;
        encodedHash = keccak256(encoded);
    }

    /// @notice Build a simple merkle tree from leaves and get the root
    /// @dev Uses a simple binary merkle tree structure
    /// @param leaves The leaf hashes (must be power of 2 for simplicity)
    /// @return root The merkle root
    function buildMerkleRoot(bytes32[] memory leaves) public pure returns (bytes32 root) {
        uint256 n = leaves.length;
        require(n > 0, "Empty leaves");

        // For single leaf, return the leaf
        if (n == 1) return leaves[0];

        // Build tree bottom-up
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    // Sort hashes before hashing (OpenZeppelin standard)
                    bytes32 left = currentLevel[i];
                    bytes32 right = currentLevel[i + 1];
                    nextLevel[i / 2] = left < right ? _hashPair(left, right) : _hashPair(right, left);
                } else {
                    // Odd number of nodes, promote the last one
                    nextLevel[i / 2] = currentLevel[i];
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    /// @notice Generate a merkle proof for a given leaf
    /// @param leaves All leaf hashes
    /// @param index Index of the leaf to prove
    /// @return proof The merkle proof
    function generateProof(bytes32[] memory leaves, uint256 index) public pure returns (bytes32[] memory proof) {
        require(index < leaves.length, "Index out of bounds");

        // Calculate proof length (tree height)
        uint256 treeHeight = 0;
        uint256 n = leaves.length;
        while (n > 1) {
            treeHeight++;
            n = (n + 1) / 2;
        }

        proof = new bytes32[](treeHeight);
        uint256 proofIndex = 0;

        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = index;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    bytes32 left = currentLevel[i];
                    bytes32 right = currentLevel[i + 1];

                    // If current index is part of this pair, add sibling to proof
                    if (i == currentIndex || i + 1 == currentIndex) {
                        proof[proofIndex++] = (i == currentIndex) ? right : left;
                    }

                    nextLevel[i / 2] = left < right ? _hashPair(left, right) : _hashPair(right, left);
                } else {
                    nextLevel[i / 2] = currentLevel[i];
                }
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        return proof;
    }

    /// @notice Hash a pair of nodes (internal helper)
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }

    /// @notice Verify a merkle proof
    /// @param proof The merkle proof
    /// @param root The merkle root
    /// @param leaf The leaf hash
    /// @return True if proof is valid
    function verifyProof(bytes32[] memory proof, bytes32 root, bytes32 leaf) public pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            computedHash = computedHash < proofElement ? _hashPair(computedHash, proofElement) : _hashPair(proofElement, computedHash);
        }

        return computedHash == root;
    }
}
