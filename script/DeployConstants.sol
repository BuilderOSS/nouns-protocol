// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title DeployConstants
/// @notice Shared salt constants for deterministic cross-chain deployments
/// @dev All deployment scripts should inherit this to ensure consistent salt usage
abstract contract DeployConstants {
    // Manager-related salts
    bytes32 internal constant MANAGER_IMPL_0_SALT = keccak256("MANAGER_IMPL_0");
    bytes32 internal constant MANAGER_PROXY_SALT = keccak256("MANAGER_PROXY");
    bytes32 internal constant MANAGER_IMPL_SALT = keccak256("MANAGER_IMPL");

    // Implementation salts
    bytes32 internal constant TOKEN_IMPL_SALT = keccak256("TOKEN_IMPL");
    bytes32 internal constant METADATA_RENDERER_IMPL_SALT = keccak256("METADATA_RENDERER_IMPL");
    bytes32 internal constant AUCTION_IMPL_SALT = keccak256("AUCTION_IMPL");
    bytes32 internal constant TREASURY_IMPL_SALT = keccak256("TREASURY_IMPL");
    bytes32 internal constant GOVERNOR_IMPL_SALT = keccak256("GOVERNOR_IMPL");

    // Additional contract salts
    bytes32 internal constant MERKLE_PROPERTY_IPFS_SALT = keccak256("MERKLE_PROPERTY_IPFS");
    bytes32 internal constant MERKLE_RESERVE_MINTER_SALT = keccak256("MERKLE_RESERVE_MINTER");
    bytes32 internal constant ERC721_REDEEM_MINTER_SALT = keccak256("ERC721_REDEEM_MINTER");
    bytes32 internal constant L2_MIGRATION_DEPLOYER_SALT = keccak256("L2_MIGRATION_DEPLOYER");

    /// @notice Derives the final CREATE2 salt from deploy salt and label
    /// @param deploySalt The base deployment salt (from DEPLOY_SALT env var)
    /// @param label The contract-specific salt label
    /// @return The derived salt for CREATE2 deployment
    function _deriveSalt(bytes32 deploySalt, bytes32 label) internal pure returns (bytes32) {
        return keccak256(abi.encode(deploySalt, label));
    }
}
