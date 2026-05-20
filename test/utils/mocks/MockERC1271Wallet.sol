// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title MockERC1271Wallet
/// @notice Mock smart contract wallet implementing ERC-1271 signature verification
/// @dev Used for testing proposeBySigs and castVoteBySig with smart wallets
contract MockERC1271Wallet {
    /// @notice ERC-1271 magic value for valid signature
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    /// @notice Address that is authorized to sign on behalf of this wallet
    address public owner;

    /// @notice Approved signature hashes
    mapping(bytes32 => bool) public approvedHashes;

    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Approve a specific hash for signature validation
    /// @dev This simulates the wallet's internal approval mechanism
    function approveHash(bytes32 hash) external {
        require(msg.sender == owner, "Only owner");
        approvedHashes[hash] = true;
    }

    /// @notice ERC-1271 signature validation
    /// @param hash The hash to validate
    /// @return magicValue The ERC-1271 magic value if valid
    function isValidSignature(bytes32 hash, bytes memory) external view returns (bytes4 magicValue) {
        // Check if hash was pre-approved
        if (approvedHashes[hash]) {
            return MAGICVALUE;
        }

        // Alternative: validate signature is from owner
        // (For testing, we'll use the pre-approval mechanism)
        return bytes4(0);
    }

    /// @notice Helper to get the owner's EOA signature and approve it
    /// @dev This would be used in tests to prepare the wallet
    function prepareSignature(bytes32 hash) external {
        require(msg.sender == owner, "Only owner");
        approvedHashes[hash] = true;
    }

    /// @notice Revoke approval for a hash
    function revokeHash(bytes32 hash) external {
        require(msg.sender == owner, "Only owner");
        approvedHashes[hash] = false;
    }
}
