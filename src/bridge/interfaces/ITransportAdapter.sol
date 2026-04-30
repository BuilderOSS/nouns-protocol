// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ITransportAdapter {
    function sendMessage(uint256 dstChainId, bytes calldata envelope, bytes calldata options)
        external
        returns (bytes32 messageId);

    function decodeMessage(bytes calldata transportMessage)
        external
        view
        returns (bytes memory envelope, bytes32 transportMsgId);
}
