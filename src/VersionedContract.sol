// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title VersionedContract
/// @author Builder Protocol
/// @notice Abstract contract that provides version information for deployed contracts
abstract contract VersionedContract {
    /// @notice Returns the current version of the contract
    function contractVersion() external pure returns (string memory) {
        return "3.0.0";
    }
}
