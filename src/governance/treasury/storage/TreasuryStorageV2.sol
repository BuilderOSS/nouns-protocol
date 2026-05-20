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

    /// @notice Per-safe spending limits (value per transaction)
    mapping(uint32 => uint256) internal safeSpendingLimits;

    /// @notice Per-safe daily spending limits tracking
    mapping(uint32 => SpendingTrackerV2) internal safeSpendingTrackers;

    /// @notice Per-safe pause state
    mapping(uint32 => bool) internal safePaused;

    /// @notice Global safe execution pause
    bool internal allSafesPaused;

    /// @notice Guardian address with emergency pause power
    address internal guardian;
}
