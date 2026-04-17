// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { TreasuryTypesV2 } from "../types/TreasuryTypesV2.sol";

/// @notice TreasuryStorageV2
/// @author Nouns Builder
/// @notice Append-only treasury storage for safe routing
contract TreasuryStorageV2 is TreasuryTypesV2 {
    /// @notice Number of safes registered
    uint32 internal _safeCount;

    /// @notice Safe config indexed by id
    mapping(uint32 => SafeConfigV2) internal safes;

    /// @notice Safe address to id mapping
    mapping(address => uint32) internal safeIds;

    /// @notice Optional global policy metadata
    GlobalPolicyV2 internal globalPolicy;
}
