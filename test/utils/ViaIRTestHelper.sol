// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";

/// @title ViaIRTestHelper
/// @notice Helper contract to prevent timestamp caching issues when using via_ir compilation
/// @dev When via_ir=true is enabled, the Solidity IR compiler can cache block.timestamp values
///      incorrectly across vm.warp() calls in tests. This helper ensures explicit timestamp
///      tracking to avoid that issue.
///
///      Example Problem (with via_ir):
///      ```
///      vm.warp(block.timestamp + 1 days);  // block.timestamp may use cached value
///      vm.warp(block.timestamp + 1 days);  // Warps backwards!
///      ```
///
///      Solution (with ViaIRTestHelper):
///      ```
///      uint256 t1 = getCurrentTime();
///      warpSafe(t1 + 1 days);
///      uint256 t2 = getCurrentTime();
///      warpSafe(t2 + 1 days);
///      ```
abstract contract ViaIRTestHelper is Test {
    ///                                                          ///
    ///                          STORAGE                         ///
    ///                                                          ///
    /// @notice Explicitly tracked test time to avoid block.timestamp caching
    uint256 internal _testTime;

    ///                                                          ///
    ///                      TIME MANAGEMENT                     ///
    ///                                                          ///

    /// @notice Initialize test time from current block.timestamp
    /// @dev Call this in setUp() after any initial vm.rollFork() or vm.warp()
    function initTime() internal {
        _testTime = block.timestamp;
    }

    /// @notice Initialize test time with explicit value
    /// @param _timestamp The timestamp to initialize with
    function initTime(uint256 _timestamp) internal {
        _testTime = _timestamp;
        vm.warp(_timestamp);
    }

    /// @notice Warp to a specific timestamp with explicit tracking
    /// @param _timestamp The timestamp to warp to
    /// @dev Always use this instead of vm.warp() directly when using via_ir
    function warpSafe(uint256 _timestamp) internal {
        _testTime = _timestamp;
        vm.warp(_timestamp);
    }

    /// @notice Get the current test time
    /// @return The current tracked timestamp
    /// @dev Use this instead of block.timestamp in calculations to avoid caching
    function getCurrentTime() internal view returns (uint256) {
        return _testTime;
    }

    /// @notice Advance time by a specific duration
    /// @param _duration The duration to advance (in seconds)
    /// @return The new current time
    function advanceTime(uint256 _duration) internal returns (uint256) {
        _testTime += _duration;
        vm.warp(_testTime);
        return _testTime;
    }

    ///                                                          ///
    ///                    PROPOSAL TIMELINE                     ///
    ///                                                          ///

    /// @notice Timeline for a Governor proposal lifecycle
    struct ProposalTimeline {
        uint256 proposalTime;
        uint256 updatePeriodEnd;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 queueTime;
        uint256 executeTime;
    }

    /// @notice Create a proposal timeline with explicit timestamps
    /// @param _startTime The starting timestamp (usually getCurrentTime())
    /// @param _updatePeriod Duration of the updatable period
    /// @param _votingDelay Delay before voting starts
    /// @param _votingPeriod Duration of voting
    /// @param _executionDelay Treasury timelock delay
    /// @return timeline The calculated proposal timeline
    function createProposalTimeline(uint256 _startTime, uint256 _updatePeriod, uint256 _votingDelay, uint256 _votingPeriod, uint256 _executionDelay)
        internal
        pure
        returns (ProposalTimeline memory timeline)
    {
        timeline.proposalTime = _startTime;
        timeline.updatePeriodEnd = _startTime + _updatePeriod;
        timeline.voteStart = timeline.updatePeriodEnd + _votingDelay;
        timeline.voteEnd = timeline.voteStart + _votingPeriod;
        timeline.queueTime = timeline.voteEnd;
        timeline.executeTime = timeline.queueTime + _executionDelay;
    }

    ///                                                          ///
    ///                    AUCTION TIMELINE                      ///
    ///                                                          ///

    /// @notice Timeline for an auction lifecycle
    struct AuctionTimeline {
        uint256 auctionStart;
        uint256 auctionEnd;
        uint256 settlementTime;
    }

    /// @notice Create an auction timeline with explicit timestamps
    /// @param _startTime The auction start timestamp
    /// @param _duration The auction duration
    /// @return timeline The calculated auction timeline
    function createAuctionTimeline(uint256 _startTime, uint256 _duration) internal pure returns (AuctionTimeline memory timeline) {
        timeline.auctionStart = _startTime;
        timeline.auctionEnd = _startTime + _duration;
        timeline.settlementTime = timeline.auctionEnd;
    }
}
