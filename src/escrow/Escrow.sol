// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title Escrow
/// @author Builder Protocol
/// @notice Simple escrow contract for holding and distributing ETH
contract Escrow {
    /// @notice The owner address with permission to set the claimer
    address public owner;
    /// @notice The claimer address with permission to withdraw funds
    address public claimer;

    error OnlyOwner();
    error OnlyClaimer();

    /// @notice Emitted when funds are claimed
    /// @param balance The amount of ETH claimed
    event Claimed(uint256 balance);

    /// @notice Emitted when the claimer address is changed
    /// @param oldClaimer The previous claimer address
    /// @param newClaimer The new claimer address
    event ClaimerChanged(address oldClaimer, address newClaimer);

    /// @notice Emitted when ETH is received by the contract
    /// @param amount The amount of ETH received
    event Received(uint256 amount);

    constructor(address _owner, address _claimer) {
        owner = _owner;
        claimer = _claimer;
    }

    /// @notice Claims all funds from the escrow and sends to the specified recipient
    /// @param recipient The address to receive the escrowed funds
    function claim(address recipient) public returns (bool) {
        if (msg.sender != claimer) {
            revert OnlyClaimer();
        }
        emit Claimed(address(this).balance);
        (bool success,) = recipient.call{ value: address(this).balance }("");
        return success;
    }

    /// @notice Sets a new claimer address
    /// @param _claimer The new claimer address
    function setClaimer(address _claimer) public {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        claimer = _claimer;
    }

    /// @notice Receives ETH sent to the contract
    receive() external payable {
        emit Received(msg.value);
    }
}
