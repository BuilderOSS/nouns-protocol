// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "../lib/utils/Ownable.sol";
import { ITransportAdapter } from "./interfaces/ITransportAdapter.sol";
import { IVerificationPolicy } from "./interfaces/IVerificationPolicy.sol";
import { IWalletExecutionAdapter } from "./interfaces/IWalletExecutionAdapter.sol";
import { BridgeTypes } from "./types/BridgeTypes.sol";

/// @notice Per-DAO destination chain command executor
contract DestinationExecutor is Ownable, BridgeTypes {
    bytes32 public immutable daoId;
    uint64 public immutable modeChangeMinDelay;
    uint64 public immutable modeChangeCooldown;

    uint256 public sourceChainId;
    address public sourceSender;

    address public managedAdmin;
    address public guardian;

    BridgeMode public mode;
    bool public paused;

    address public verificationPolicy;
    uint8 public verificationThreshold;
    uint32 public adapterSetVersion;

    uint64 public lastModeChange;

    struct PendingModeChange {
        BridgeMode toMode;
        uint64 eta;
        bool exists;
    }

    PendingModeChange public pendingModeChange;

    mapping(uint8 => address) public transportAdapters;
    mapping(address => bool) public isTransportAdapter;

    mapping(bytes32 => mapping(uint8 => bool)) public hasAttested;
    mapping(bytes32 => uint8) public attestationCounts;
    mapping(bytes32 => bool) public consumed;

    uint32 public walletCount;
    mapping(uint32 => WalletConfig) internal wallets;
    mapping(address => uint32) public walletIdByAddress;

    event MessageAccepted(bytes32 indexed msgKey, uint256 sourceChainId, address indexed sourceSender, uint64 nonce);
    event MessageRejected(bytes32 indexed msgKey, bytes reason);
    event AttestationRecorded(bytes32 indexed msgKey, uint8 adapterId, uint8 count);

    event WalletAdded(uint32 indexed walletId, address wallet, address adapter, address policy, bytes32 policyHash);
    event WalletUpdated(uint32 indexed walletId, bool active, address adapter, address policy, bytes32 policyHash);
    event WalletRemoved(uint32 indexed walletId, address wallet);

    event BridgeModeChangeRequested(uint8 fromMode, uint8 toMode, uint64 eta);
    event BridgeModeChanged(uint8 fromMode, uint8 toMode);
    event BridgeModeChangeCanceled(uint8 canceledToMode);

    event TransportAdapterUpdated(uint8 indexed adapterId, address indexed adapter);
    event VerificationPolicyUpdated(address indexed policy, uint8 threshold, uint32 adapterSetVersion);
    event ManagedAdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    event CrossChainExecution(
        uint32 indexed walletId,
        address indexed target,
        uint256 value,
        uint8 operation,
        bool success,
        bytes returnData
    );

    error INVALID_ADDRESS();
    error INVALID_MODE();
    error INVALID_ENVELOPE();
    error INVALID_SOURCE();
    error INVALID_DESTINATION();
    error INVALID_DEADLINE();
    error INVALID_ADAPTER();
    error INVALID_WALLET();
    error INVALID_POLICY();
    error MESSAGE_ALREADY_CONSUMED();
    error NOT_VERIFIED();
    error ONLY_MANAGED_ADMIN();
    error ONLY_GUARDIAN();
    error EXECUTION_PAUSED();
    error MODE_MUST_BE_MANAGED();
    error MODE_MUST_BE_SOVEREIGN();
    error MODE_CHANGE_PENDING();
    error MODE_CHANGE_NOT_PENDING();
    error MODE_CHANGE_NOT_READY();
    error MODE_CHANGE_COOLDOWN();

    modifier onlyManagedAdmin() {
        if (msg.sender != managedAdmin) revert ONLY_MANAGED_ADMIN();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert ONLY_GUARDIAN();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert EXECUTION_PAUSED();
        _;
    }

    constructor(
        address _owner,
        bytes32 _daoId,
        uint256 _sourceChainId,
        address _sourceSender,
        address _managedAdmin,
        address _guardian,
        BridgeMode _mode,
        address _verificationPolicy,
        uint8 _verificationThreshold,
        uint64 _modeChangeMinDelay,
        uint64 _modeChangeCooldown
    ) initializer {
        if (_owner == address(0) || _sourceSender == address(0) || _managedAdmin == address(0)) revert INVALID_ADDRESS();
        if (_verificationPolicy == address(0)) revert INVALID_POLICY();

        __Ownable_init(_owner);

        daoId = _daoId;
        sourceChainId = _sourceChainId;
        sourceSender = _sourceSender;
        managedAdmin = _managedAdmin;
        guardian = _guardian;
        mode = _mode;
        verificationPolicy = _verificationPolicy;
        verificationThreshold = _verificationThreshold;
        modeChangeMinDelay = _modeChangeMinDelay;
        modeChangeCooldown = _modeChangeCooldown;
        lastModeChange = uint64(block.timestamp);
    }

    function getWallet(uint32 _walletId) external view returns (WalletConfig memory) {
        return wallets[_walletId];
    }

    function setManagedAdmin(address _managedAdmin) external onlyOwner {
        if (_managedAdmin == address(0)) revert INVALID_ADDRESS();
        emit ManagedAdminUpdated(managedAdmin, _managedAdmin);
        managedAdmin = _managedAdmin;
    }

    function setGuardian(address _guardian) external onlyOwner {
        emit GuardianUpdated(guardian, _guardian);
        guardian = _guardian;
    }

    function pause() external {
        if (msg.sender != guardian && msg.sender != owner()) revert ONLY_GUARDIAN();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external {
        if (msg.sender != guardian && msg.sender != owner()) revert ONLY_GUARDIAN();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setTransportAdapterManaged(uint8 _adapterId, address _adapter) external onlyManagedAdmin {
        if (mode != BridgeMode.MANAGED) revert MODE_MUST_BE_MANAGED();
        if (pendingModeChange.exists) revert MODE_CHANGE_PENDING();
        _setTransportAdapter(_adapterId, _adapter);
    }

    function setVerificationPolicyManaged(address _policy, uint8 _threshold, uint32 _adapterSetVersion)
        external
        onlyManagedAdmin
    {
        if (mode != BridgeMode.MANAGED) revert MODE_MUST_BE_MANAGED();
        if (pendingModeChange.exists) revert MODE_CHANGE_PENDING();
        _setVerificationPolicy(_policy, _threshold, _adapterSetVersion);
    }

    function receiveMessage(bytes calldata _transportMessage, uint8 _adapterId) external whenNotPaused {
        if (msg.sender != transportAdapters[_adapterId]) revert INVALID_ADAPTER();

        (bytes memory rawEnvelope,) = ITransportAdapter(msg.sender).decodeMessage(_transportMessage);
        BridgeEnvelope memory envelope = abi.decode(rawEnvelope, (BridgeEnvelope));

        if (envelope.daoId != daoId) revert INVALID_ENVELOPE();
        if (envelope.sourceChainId != sourceChainId || envelope.sourceSender != sourceSender) revert INVALID_SOURCE();
        if (envelope.destinationChainId != block.chainid) revert INVALID_DESTINATION();
        if (envelope.deadline != 0 && block.timestamp > envelope.deadline) revert INVALID_DEADLINE();

        bytes32 msgKey =
            keccak256(abi.encode(envelope.sourceChainId, envelope.sourceSender, envelope.nonce, keccak256(envelope.payload)));

        if (consumed[msgKey]) revert MESSAGE_ALREADY_CONSUMED();

        if (!hasAttested[msgKey][_adapterId]) {
            hasAttested[msgKey][_adapterId] = true;
            unchecked {
                attestationCounts[msgKey]++;
            }
            emit AttestationRecorded(msgKey, _adapterId, attestationCounts[msgKey]);
        }

        if (!IVerificationPolicy(verificationPolicy).isSatisfied(
            attestationCounts[msgKey], verificationThreshold, adapterSetVersion
        )) {
            emit MessageRejected(msgKey, abi.encodePacked("NOT_VERIFIED"));
            revert NOT_VERIFIED();
        }

        consumed[msgKey] = true;

        _dispatch(envelope.payload);

        emit MessageAccepted(msgKey, envelope.sourceChainId, envelope.sourceSender, envelope.nonce);
    }

    function _dispatch(bytes memory _payload) internal {
        Command memory command = abi.decode(_payload, (Command));

        if (command.commandType == CommandType.EXECUTE) {
            _execute(abi.decode(command.data, (ExecuteCommand)));
            return;
        }

        if (command.commandType == CommandType.ADD_WALLET) {
            _addWallet(abi.decode(command.data, (WalletConfigCommand)));
            return;
        }

        if (command.commandType == CommandType.UPDATE_WALLET) {
            _updateWallet(abi.decode(command.data, (WalletConfigCommand)));
            return;
        }

        if (command.commandType == CommandType.REMOVE_WALLET) {
            _removeWallet(abi.decode(command.data, (RemoveWalletCommand)));
            return;
        }

        if (command.commandType == CommandType.SET_POLICY) {
            if (mode != BridgeMode.SOVEREIGN) revert MODE_MUST_BE_SOVEREIGN();
            SetPolicyCommand memory setPolicyCommand = abi.decode(command.data, (SetPolicyCommand));
            _setVerificationPolicy(
                setPolicyCommand.policy, setPolicyCommand.threshold, setPolicyCommand.adapterSetVersion
            );
            return;
        }

        if (command.commandType == CommandType.SET_ADAPTER) {
            if (mode != BridgeMode.SOVEREIGN) revert MODE_MUST_BE_SOVEREIGN();
            SetAdapterCommand memory setAdapterCommand = abi.decode(command.data, (SetAdapterCommand));
            _setTransportAdapter(setAdapterCommand.adapterId, setAdapterCommand.adapter);
            return;
        }

        if (command.commandType == CommandType.SET_MODE) {
            _setMode(abi.decode(command.data, (SetModeCommand)));
            return;
        }

        revert INVALID_ENVELOPE();
    }

    function _execute(ExecuteCommand memory _command) internal {
        WalletConfig memory walletConfig = wallets[_command.walletId];
        if (!walletConfig.active || walletConfig.wallet == address(0) || walletConfig.adapter == address(0)) {
            revert INVALID_WALLET();
        }

        bytes memory returnData = IWalletExecutionAdapter(walletConfig.adapter).execute(
            walletConfig.wallet, _command.target, _command.value, _command.data, _command.operation
        );

        emit CrossChainExecution(
            _command.walletId,
            _command.target,
            _command.value,
            _command.operation,
            true,
            returnData
        );
    }

    function _addWallet(WalletConfigCommand memory _command) internal {
        if (_command.wallet == address(0) || _command.adapter == address(0)) revert INVALID_WALLET();
        if (walletIdByAddress[_command.wallet] != 0) revert INVALID_WALLET();

        uint32 walletId = _command.walletId;
        if (walletId == 0) {
            unchecked {
                walletCount++;
            }
            walletId = walletCount;
        } else {
            if (walletId != walletCount + 1) revert INVALID_WALLET();
            walletCount = walletId;
        }

        wallets[walletId] = WalletConfig({
            wallet: _command.wallet,
            adapter: _command.adapter,
            policy: _command.policy,
            policyHash: _command.policyHash,
            active: _command.active
        });
        walletIdByAddress[_command.wallet] = walletId;

        emit WalletAdded(walletId, _command.wallet, _command.adapter, _command.policy, _command.policyHash);
    }

    function _updateWallet(WalletConfigCommand memory _command) internal {
        if (_command.walletId == 0 || _command.walletId > walletCount) revert INVALID_WALLET();
        if (_command.adapter == address(0)) revert INVALID_WALLET();

        WalletConfig storage cfg = wallets[_command.walletId];
        if (cfg.wallet == address(0)) revert INVALID_WALLET();

        if (_command.wallet != address(0) && _command.wallet != cfg.wallet) {
            if (walletIdByAddress[_command.wallet] != 0) revert INVALID_WALLET();
            delete walletIdByAddress[cfg.wallet];
            cfg.wallet = _command.wallet;
            walletIdByAddress[cfg.wallet] = _command.walletId;
        }

        cfg.adapter = _command.adapter;
        cfg.policy = _command.policy;
        cfg.policyHash = _command.policyHash;
        cfg.active = _command.active;

        emit WalletUpdated(_command.walletId, cfg.active, cfg.adapter, cfg.policy, cfg.policyHash);
    }

    function _removeWallet(RemoveWalletCommand memory _command) internal {
        if (_command.walletId == 0 || _command.walletId > walletCount) revert INVALID_WALLET();

        WalletConfig storage cfg = wallets[_command.walletId];
        if (cfg.wallet == address(0)) revert INVALID_WALLET();

        address wallet = cfg.wallet;
        delete walletIdByAddress[wallet];
        delete wallets[_command.walletId];

        emit WalletRemoved(_command.walletId, wallet);
    }

    function _setMode(SetModeCommand memory _command) internal {
        if (_command.cancel) {
            if (!pendingModeChange.exists) revert MODE_CHANGE_NOT_PENDING();
            emit BridgeModeChangeCanceled(uint8(pendingModeChange.toMode));
            delete pendingModeChange;
            return;
        }

        if (_command.execute) {
            if (!pendingModeChange.exists) revert MODE_CHANGE_NOT_PENDING();
            if (pendingModeChange.toMode != _command.mode) revert INVALID_MODE();
            if (block.timestamp < pendingModeChange.eta) revert MODE_CHANGE_NOT_READY();
            if (block.timestamp < uint256(lastModeChange) + modeChangeCooldown) revert MODE_CHANGE_COOLDOWN();

            BridgeMode previousMode = mode;
            mode = _command.mode;
            lastModeChange = uint64(block.timestamp);
            delete pendingModeChange;

            emit BridgeModeChanged(uint8(previousMode), uint8(mode));
            return;
        }

        if (pendingModeChange.exists) revert MODE_CHANGE_PENDING();
        if (_command.mode == mode) revert INVALID_MODE();
        if (_command.eta < block.timestamp + modeChangeMinDelay) revert MODE_CHANGE_NOT_READY();

        pendingModeChange = PendingModeChange({ toMode: _command.mode, eta: _command.eta, exists: true });
        emit BridgeModeChangeRequested(uint8(mode), uint8(_command.mode), _command.eta);
    }

    function _setTransportAdapter(uint8 _adapterId, address _adapter) internal {
        if (_adapter == address(0)) revert INVALID_ADAPTER();

        address oldAdapter = transportAdapters[_adapterId];
        if (oldAdapter != address(0)) {
            isTransportAdapter[oldAdapter] = false;
        }

        transportAdapters[_adapterId] = _adapter;
        isTransportAdapter[_adapter] = true;

        emit TransportAdapterUpdated(_adapterId, _adapter);
    }

    function _setVerificationPolicy(address _policy, uint8 _threshold, uint32 _adapterSetVersion) internal {
        if (_policy == address(0)) revert INVALID_POLICY();

        verificationPolicy = _policy;
        verificationThreshold = _threshold;
        adapterSetVersion = _adapterSetVersion;

        emit VerificationPolicyUpdated(_policy, _threshold, _adapterSetVersion);
    }
}
