// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title ICrossDomainMessenger
/// @author Builder Protocol
/// @notice Interface for cross-domain messaging between L1 and L2
interface ICrossDomainMessenger {
    /// @notice Retrieves the address of the contract or wallet that initiated the currently
    ///         executing message on the other chain. Will throw an error if there is no message
    ///         currently being executed. Allows the recipient of a call to see who triggered it.
    /// @return Address of the sender of the currently executing message on the other chain.
    function xDomainMessageSender() external view returns (address);
}
