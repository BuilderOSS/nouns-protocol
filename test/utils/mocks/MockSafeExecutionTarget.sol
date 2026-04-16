// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

contract MockSafeExecutionTarget {
    uint256 public number;
    address public caller;
    uint256 public valueReceived;

    function setNumber(uint256 _number) external payable {
        number = _number;
        caller = msg.sender;
        valueReceived = msg.value;
    }
}
