// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ManagerTypesV1 } from "./ManagerTypesV1.sol";

/// @title ManagerTypesV2
/// @notice Manager V2 bridge-related custom types
interface ManagerTypesV2 is ManagerTypesV1 {
    /// @notice Stores deployed bridge contract addresses for a DAO on a destination chain
    struct BridgeAddressesV2 {
        address sourceBridgeAdapter;
        address destinationExecutor;
        address transportAdapter;
        address safeWalletAdapter;
        address verificationPolicy;
    }
}
