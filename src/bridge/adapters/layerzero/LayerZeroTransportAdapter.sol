// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "../../../lib/utils/Ownable.sol";
import { ITransportAdapter } from "../../interfaces/ITransportAdapter.sol";
import { IDestinationMessageReceiver } from "../../interfaces/IDestinationMessageReceiver.sol";
import { ILayerZeroEndpointV2 } from "./ILayerZeroEndpointV2.sol";

/// @notice Default in-repo transport adapter implementation scaffold for LayerZero-style delivery
/// @dev This adapter keeps bridge-protocol details isolated from source/destination bridge logic.
contract LayerZeroTransportAdapter is Ownable, ITransportAdapter {
    ILayerZeroEndpointV2 public immutable endpoint;

    mapping(uint256 => uint32) public destinationEids;

    event DestinationEidSet(uint256 indexed chainId, uint32 indexed eid);
    event MessageSent(uint256 indexed dstChainId, uint32 indexed dstEid, bytes32 indexed messageId, bytes envelope);
    event MessageRelayed(address indexed destinationExecutor, uint8 indexed adapterId, bytes32 indexed messageId);

    error INVALID_ADDRESS();
    error INVALID_DESTINATION();

    constructor(address _owner, address _endpoint) initializer {
        if (_owner == address(0) || _endpoint == address(0)) revert INVALID_ADDRESS();
        __Ownable_init(_owner);
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function setDestinationEid(uint256 _chainId, uint32 _eid) external onlyOwner {
        if (_eid == 0) revert INVALID_DESTINATION();
        destinationEids[_chainId] = _eid;
        emit DestinationEidSet(_chainId, _eid);
    }

    /// @notice Sends encoded envelope through the endpoint.
    /// @dev In production, fees/options should be estimated and passed with endpoint-specific semantics.
    function sendMessage(uint256 _dstChainId, bytes calldata _envelope, bytes calldata _options)
        external
        returns (bytes32 messageId)
    {
        uint32 dstEid = destinationEids[_dstChainId];
        if (dstEid == 0) revert INVALID_DESTINATION();

        messageId = endpoint.send(dstEid, _envelope, _options, payable(msg.sender));
        emit MessageSent(_dstChainId, dstEid, messageId, _envelope);
    }

    /// @notice Decodes transport message into bridge envelope bytes + protocol message id
    /// @dev Expected transportMessage format: abi.encode(bytes32 transportMsgId, bytes envelope)
    function decodeMessage(bytes calldata _transportMessage)
        external
        pure
        returns (bytes memory envelope, bytes32 transportMsgId)
    {
        (bytes32 messageId, bytes memory decodedEnvelope) = abi.decode(_transportMessage, (bytes32, bytes));
        return (decodedEnvelope, messageId);
    }

    /// @notice Managed relay hook for delivering verified messages into a destination executor
    /// @dev In production this should be invoked through verified endpoint receive path.
    function relayMessage(address _destinationExecutor, uint8 _adapterId, bytes32 _messageId, bytes calldata _envelope)
        external
        onlyOwner
    {
        if (_destinationExecutor == address(0)) revert INVALID_ADDRESS();

        IDestinationMessageReceiver(_destinationExecutor).receiveMessage(abi.encode(_messageId, _envelope), _adapterId);
        emit MessageRelayed(_destinationExecutor, _adapterId, _messageId);
    }
}
