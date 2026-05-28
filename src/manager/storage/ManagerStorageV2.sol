// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ManagerTypesV2 } from "../types/ManagerTypesV2.sol";

/// @notice Manager Storage V2
/// @notice Append-only storage for bridge deployment tracking
contract ManagerStorageV2 is ManagerTypesV2 {
    /// @notice DAO id => source bridge adapter
    mapping(bytes32 => address) internal sourceBridgeAdapterByDao;

    /// @notice DAO id => destination chain id => bridge infra addresses
    mapping(bytes32 => mapping(uint256 => BridgeAddressesV2)) internal bridgeAddressesByDaoByChain;
}
