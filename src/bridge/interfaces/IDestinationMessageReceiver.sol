// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IDestinationMessageReceiver {
    function receiveMessage(bytes calldata transportMessage, uint8 adapterId) external;
}
