// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "../../../lib/utils/Ownable.sol";
import { ITransportAdapter } from "../../interfaces/ITransportAdapter.sol";
import { IDestinationMessageReceiver } from "../../interfaces/IDestinationMessageReceiver.sol";
import { ILayerZeroEndpointV2, Origin } from "./ILayerZeroEndpointV2.sol";

/// @notice LayerZero V2 OApp transport adapter for cross-chain DAO governance
/// @dev Implements proper OApp pattern with lzReceive, fee estimation, and peer verification
contract LayerZeroTransportAdapter is Ownable, ITransportAdapter {
    ILayerZeroEndpointV2 public immutable endpoint;

    mapping(uint256 => uint32) public destinationEids;
    mapping(uint32 => bytes32) public peers; // srcEid => peer address (bytes32)
    mapping(bytes32 => address) public executors; // daoId => executor address
    mapping(bytes32 => uint8) public executorAdapterIds; // daoId => adapterId

    event DestinationEidSet(uint256 indexed chainId, uint32 indexed eid);
    event PeerSet(uint32 indexed srcEid, bytes32 indexed peer);
    event ExecutorSet(bytes32 indexed daoId, address indexed executor, uint8 adapterId);
    event MessageSent(uint256 indexed dstChainId, uint32 indexed dstEid, bytes32 indexed messageId, bytes envelope);
    event MessageReceived(bytes32 indexed guid, uint32 indexed srcEid, bytes32 indexed sender, bytes envelope);

    error INVALID_ADDRESS();
    error INVALID_DESTINATION();
    error INVALID_PEER();
    error INVALID_ENDPOINT_CALLER();
    error INSUFFICIENT_FEE();

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

    /// @notice Sets trusted peer for source endpoint
    /// @param _srcEid Source endpoint ID
    /// @param _peer Peer address as bytes32
    function setPeer(uint32 _srcEid, bytes32 _peer) external onlyOwner {
        peers[_srcEid] = _peer;
        emit PeerSet(_srcEid, _peer);
    }

    /// @notice Maps daoId to destination executor for message routing
    /// @param _daoId DAO identifier
    /// @param _executor Destination executor address
    /// @param _adapterId Adapter ID for this transport
    function setExecutor(bytes32 _daoId, address _executor, uint8 _adapterId) external onlyOwner {
        if (_executor == address(0)) revert INVALID_ADDRESS();
        executors[_daoId] = _executor;
        executorAdapterIds[_daoId] = _adapterId;
        emit ExecutorSet(_daoId, _executor, _adapterId);
    }

    /// @notice Quotes the fee for sending a message
    /// @param _dstChainId Destination chain ID
    /// @param _envelope Encoded envelope
    /// @param _options LayerZero options
    /// @param _payInLzToken Whether to pay in LZ token
    /// @return nativeFee Native fee amount
    /// @return lzTokenFee LZ token fee amount
    function quoteFee(uint256 _dstChainId, bytes calldata _envelope, bytes calldata _options, bool _payInLzToken)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        uint32 dstEid = destinationEids[_dstChainId];
        if (dstEid == 0) revert INVALID_DESTINATION();

        return endpoint.quote(dstEid, _envelope, _options, _payInLzToken);
    }

    /// @notice Sends encoded envelope through the endpoint with fee validation
    /// @param _dstChainId Destination chain ID
    /// @param _envelope Encoded envelope
    /// @param _options LayerZero options
    /// @return messageId Message GUID
    function sendMessage(uint256 _dstChainId, bytes calldata _envelope, bytes calldata _options)
        external
        payable
        returns (bytes32 messageId)
    {
        uint32 dstEid = destinationEids[_dstChainId];
        if (dstEid == 0) revert INVALID_DESTINATION();

        // Quote and validate fee
        (uint256 nativeFee,) = endpoint.quote(dstEid, _envelope, _options, false);
        if (msg.value < nativeFee) revert INSUFFICIENT_FEE();

        // Send message
        messageId = endpoint.send{ value: nativeFee }(dstEid, _envelope, _options, payable(msg.sender));

        // Refund excess
        if (msg.value > nativeFee) {
            (bool success,) = msg.sender.call{ value: msg.value - nativeFee }("");
            require(success, "Refund failed");
        }

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

    /// @notice LayerZero endpoint callback for receiving messages
    /// @dev Called by endpoint when message arrives from source chain
    /// @param _origin Origin information (srcEid, sender, nonce)
    /// @param _guid Message GUID
    /// @param _message Encoded message payload
    /// @param _executor Executor address (unused, for compatibility)
    /// @param _extraData Extra data (unused, for compatibility)
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        // Only endpoint can call this
        if (msg.sender != address(endpoint)) revert INVALID_ENDPOINT_CALLER();

        // Verify peer
        if (peers[_origin.srcEid] != _origin.sender) revert INVALID_PEER();

        // Decode envelope to extract daoId
        bytes memory envelope = _message;
        bytes32 daoId;
        assembly {
            // daoId is first 32 bytes of envelope (after length prefix)
            daoId := mload(add(envelope, 32))
        }

        // Get executor for this DAO
        address destinationExecutor = executors[daoId];
        if (destinationExecutor == address(0)) revert INVALID_ADDRESS();

        uint8 adapterId = executorAdapterIds[daoId];

        // Forward to destination executor
        IDestinationMessageReceiver(destinationExecutor).receiveMessage(
            abi.encode(_guid, envelope), adapterId
        );

        emit MessageReceived(_guid, _origin.srcEid, _origin.sender, envelope);
    }

    /// @notice Allows endpoint to set a delegate for message execution
    /// @param _delegate Delegate address
    function setDelegate(address _delegate) external onlyOwner {
        endpoint.setDelegate(_delegate);
    }

    /// @notice Fallback to receive ETH for fees
    receive() external payable {}
}
