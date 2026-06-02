// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title GovernorStorageV3
/// @author Builder Protocol
/// @notice Additional Governor storage for signed proposal flows and updates
contract GovernorStorageV3 {
    /// @notice The amount of time proposals remain updatable after creation
    uint48 internal _proposalUpdatablePeriod;

    /// @notice Nonce used for propose/update signatures
    mapping(address => uint256) internal proposeSigNonces;

    /// @notice Signers that sponsored a signed proposal
    mapping(bytes32 => address[]) internal proposalSigners;

    /// @notice The timestamp until which a proposal can be updated
    /// @dev Uses uint32 (overflows in year 2106), consistent with existing voteStart/voteEnd tech debt
    mapping(bytes32 => uint32) internal proposalUpdatePeriodEnds;

    /// @notice Mapping from previous proposal id to replacement id created by update
    mapping(bytes32 => bytes32) public proposalIdReplacedBy;
}
