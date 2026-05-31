// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { AuctionTypesV2 } from "../types/AuctionTypesV2.sol";

/// @title AuctionStorageV2
/// @author Builder Protocol
/// @notice Storage contract for Auction V2 with referral and founder reward support
contract AuctionStorageV2 is AuctionTypesV2 {
    /// @notice The referral for the current auction bid
    address public currentBidReferral;

    /// @notice The founder reward settings
    FounderReward public founderReward;
}
