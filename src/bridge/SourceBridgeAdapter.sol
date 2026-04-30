// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "../lib/utils/Ownable.sol";
import { ITransportAdapter } from "./interfaces/ITransportAdapter.sol";
import { BridgeTypes } from "./types/BridgeTypes.sol";

/// @notice Source-chain bridge adapter called by canonical Treasury
contract SourceBridgeAdapter is Ownable, BridgeTypes {
    address public immutable treasury;
    bytes32 public immutable daoId;

    mapping(uint8 => address) public transportAdapters;
    mapping(uint256 => address) public destinationExecutors;
    mapping(uint256 => uint64) public nonces;

    event TransportAdapterSet(uint8 indexed adapterId, address indexed adapter);
    event DestinationExecutorSet(uint256 indexed chainId, address indexed destinationExecutor);
    event BridgeCommandSent(
        bytes32 indexed messageId,
        uint8 indexed adapterId,
        uint256 indexed destinationChainId,
        address destinationExecutor,
        uint64 nonce,
        bytes payload
    );

    error ONLY_TREASURY();
    error INVALID_ADDRESS();
    error INVALID_ADAPTER();
    error INVALID_DESTINATION();

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert ONLY_TREASURY();
        _;
    }

    constructor(address _owner, address _treasury, bytes32 _daoId) initializer {
        if (_owner == address(0) || _treasury == address(0)) revert INVALID_ADDRESS();

        __Ownable_init(_owner);

        treasury = _treasury;
        daoId = _daoId;
    }

    function setTransportAdapter(uint8 _adapterId, address _adapter) external onlyOwner {
        if (_adapter == address(0)) revert INVALID_ADDRESS();
        transportAdapters[_adapterId] = _adapter;
        emit TransportAdapterSet(_adapterId, _adapter);
    }

    function setDestinationExecutor(uint256 _chainId, address _destinationExecutor) external onlyOwner {
        if (_destinationExecutor == address(0)) revert INVALID_ADDRESS();
        destinationExecutors[_chainId] = _destinationExecutor;
        emit DestinationExecutorSet(_chainId, _destinationExecutor);
    }

    function sendCommand(uint8 _adapterId, uint256 _destinationChainId, uint64 _deadline, bytes calldata _payload, bytes calldata _options)
        external
        onlyTreasury
        returns (bytes32 messageId)
    {
        address adapter = transportAdapters[_adapterId];
        if (adapter == address(0)) revert INVALID_ADAPTER();

        address destinationExecutor = destinationExecutors[_destinationChainId];
        if (destinationExecutor == address(0)) revert INVALID_DESTINATION();

        uint64 nonce;
        unchecked {
            nonces[_destinationChainId]++;
            nonce = nonces[_destinationChainId];
        }

        BridgeEnvelope memory envelope = BridgeEnvelope({
            daoId: daoId,
            sourceChainId: block.chainid,
            destinationChainId: _destinationChainId,
            sourceSender: address(this),
            nonce: nonce,
            deadline: _deadline,
            payload: _payload
        });

        messageId = ITransportAdapter(adapter).sendMessage(_destinationChainId, abi.encode(envelope), _options);

        emit BridgeCommandSent(messageId, _adapterId, _destinationChainId, destinationExecutor, nonce, _payload);
    }
}
