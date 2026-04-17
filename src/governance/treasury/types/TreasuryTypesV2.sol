// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { TreasuryTypesV1 } from "./TreasuryTypesV1.sol";

/// @notice TreasuryTypesV2
/// @author Nouns Builder
/// @notice V2 custom data types for safe routing support
contract TreasuryTypesV2 is TreasuryTypesV1 {
    /// @notice Safe-level treasury execution configuration
    struct SafeConfigV2 {
        address safe;
        address execModule;
        address policy;
        bytes32 policyHash;
        bool active;
    }

    /// @notice Optional global policy baseline metadata
    struct GlobalPolicyV2 {
        address policy;
        bytes32 policyHash;
        bool enforce;
    }
}
