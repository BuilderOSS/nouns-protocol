// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ITransportAdapter } from "../../../src/bridge/interfaces/ITransportAdapter.sol";
import { IDestinationMessageReceiver } from "../../../src/bridge/interfaces/IDestinationMessageReceiver.sol";

contract MockTransportAdapter is ITransportAdapter {
    bytes public lastEnvelope;
    uint256 public lastDstChainId;
    bytes public lastOptions;
    bytes32 public lastMessageId;

    function sendMessage(uint256 _dstChainId, bytes calldata _envelope, bytes calldata _options)
        external
        returns (bytes32 messageId)
    {
        lastDstChainId = _dstChainId;
        lastEnvelope = _envelope;
        lastOptions = _options;
        messageId = keccak256(abi.encode(_dstChainId, _envelope, _options, block.timestamp));
        lastMessageId = messageId;
    }

    function decodeMessage(bytes calldata _transportMessage)
        external
        pure
        returns (bytes memory envelope, bytes32 transportMsgId)
    {
        (bytes32 messageId, bytes memory decodedEnvelope) = abi.decode(_transportMessage, (bytes32, bytes));
        return (decodedEnvelope, messageId);
    }

    function relay(address _destinationExecutor, uint8 _adapterId, bytes32 _messageId, bytes calldata _envelope) external {
        IDestinationMessageReceiver(_destinationExecutor).receiveMessage(abi.encode(_messageId, _envelope), _adapterId);
    }
}
