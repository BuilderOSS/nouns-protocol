// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { UUPS } from "../../lib/proxy/UUPS.sol";
import { Ownable } from "../../lib/utils/Ownable.sol";
import { ERC721TokenReceiver, ERC1155TokenReceiver } from "../../lib/utils/TokenReceiver.sol";
import { SafeCast } from "../../lib/utils/SafeCast.sol";

import { TreasuryStorageV1 } from "./storage/TreasuryStorageV1.sol";
import { TreasuryStorageV2 } from "./storage/TreasuryStorageV2.sol";
import { ITreasury } from "./ITreasury.sol";
import { IGovernorSafeModule } from "./interfaces/IGovernorSafeModule.sol";
import { ProposalHasher } from "../governor/ProposalHasher.sol";
import { IManager } from "../../manager/IManager.sol";
import { VersionedContract } from "../../VersionedContract.sol";

/// @title Treasury
/// @author Rohan Kulkarni
/// @notice A DAO's treasury and transaction executor
/// @custom:repo github.com/ourzora/nouns-protocol 
/// Modified from:
/// - OpenZeppelin Contracts v4.7.3 (governance/TimelockController.sol)
/// - NounsDAOExecutor.sol commit 2cbe6c7 - licensed under the BSD-3-Clause license.
contract Treasury is ITreasury, VersionedContract, UUPS, Ownable, ProposalHasher, TreasuryStorageV1, TreasuryStorageV2 {
    ///                                                          ///
    ///                         CONSTANTS                        ///
    ///                                                          ///

    /// @notice The default grace period setting
    uint128 private constant INITIAL_GRACE_PERIOD = 2 weeks;

    /// @notice Safe operation mode for CALL
    uint8 private constant SAFE_OP_CALL = 0;

    ///                                                          ///
    ///                         IMMUTABLES                       ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    IManager private immutable manager;

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    /// @param _manager The contract upgrade manager address
    constructor(address _manager) payable initializer {
        manager = IManager(_manager);
    }

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /// @notice Initializes an instance of a DAO's treasury
    /// @param _governor The DAO's governor address
    /// @param _delay The time delay to execute a queued transaction
    function initialize(address _governor, uint256 _delay) external initializer {
        // Ensure the caller is the contract manager
        if (msg.sender != address(manager)) revert ONLY_MANAGER();

        // Ensure a governor address was provided
        if (_governor == address(0)) revert ADDRESS_ZERO();

        // Grant ownership to the governor
        __Ownable_init(_governor);

        // Store the time delay
        settings.delay = SafeCast.toUint128(_delay);

        // Set the default grace period
        settings.gracePeriod = INITIAL_GRACE_PERIOD;

        emit DelayUpdated(0, _delay);
    }

    /// @notice Initializes v2 safe routing support
    function initializeV2(
        address _mainSafe,
        address _mainSafeModule,
        address _mainSafePolicy,
        bytes32 _mainSafePolicyHash,
        address _globalPolicy,
        bytes32 _globalPolicyHash,
        bool _enforceGlobalPolicy
    ) external reinitializer(2) {
        if (_mainSafe == address(0)) revert ADDRESS_ZERO();
        if (_mainSafeModule == address(0)) revert INVALID_MODULE();

        if (msg.sender != owner() && msg.sender != address(manager)) revert ONLY_MANAGER();

        _registerSafe(_mainSafe, _mainSafeModule, _mainSafePolicy, _mainSafePolicyHash, true);
        _setGlobalPolicy(_globalPolicy, _globalPolicyHash, _enforceGlobalPolicy);
    }

    ///                                                          ///
    ///                      TRANSACTION STATE                   ///
    ///                                                          ///

    /// @notice The timestamp that a proposal is valid to execute
    /// @param _proposalId The proposal id
    function timestamp(bytes32 _proposalId) external view returns (uint256) {
        return timestamps[_proposalId];
    }

    /// @notice If a queued proposal can no longer be executed
    /// @param _proposalId The proposal id
    function isExpired(bytes32 _proposalId) external view returns (bool) {
        unchecked {
            return block.timestamp > (timestamps[_proposalId] + settings.gracePeriod);
        }
    }

    /// @notice If a proposal is queued
    /// @param _proposalId The proposal id
    function isQueued(bytes32 _proposalId) public view returns (bool) {
        return timestamps[_proposalId] != 0;
    }

    /// @notice If a proposal is ready to execute (does not consider expiration)
    /// @param _proposalId The proposal id
    function isReady(bytes32 _proposalId) public view returns (bool) {
        return timestamps[_proposalId] != 0 && block.timestamp >= timestamps[_proposalId];
    }

    ///                                                          ///
    ///                        QUEUE PROPOSAL                    ///
    ///                                                          ///

    /// @notice Schedules a proposal for execution
    /// @param _proposalId The proposal id
    function queue(bytes32 _proposalId) external onlyOwner returns (uint256 eta) {
        // Ensure the proposal was not already queued
        if (isQueued(_proposalId)) revert PROPOSAL_ALREADY_QUEUED();

        // Cannot realistically overflow
        unchecked {
            // Compute the timestamp that the proposal will be valid to execute
            eta = block.timestamp + settings.delay;
        }

        // Store the timestamp
        timestamps[_proposalId] = eta;

        emit TransactionScheduled(_proposalId, eta);
    }

    ///                                                          ///
    ///                       EXECUTE PROPOSAL                   ///
    ///                                                          ///

    /// @notice Executes a queued proposal
    /// @param _targets The target addresses to call
    /// @param _values The ETH values of each call
    /// @param _calldatas The calldata of each call
    /// @param _descriptionHash The hash of the description
    /// @param _proposer The proposal creator
    function execute(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _calldatas,
        bytes32 _descriptionHash,
        address _proposer
    ) external payable onlyOwner {
        // Get the proposal id
        bytes32 proposalId = hashProposal(_targets, _values, _calldatas, _descriptionHash, _proposer);

        // Ensure the proposal is ready to execute
        if (!isReady(proposalId)) revert EXECUTION_NOT_READY(proposalId);

        // Remove the proposal from the queue
        delete timestamps[proposalId];

        // Cache the number of targets
        uint256 numTargets = _targets.length;

        // Cannot realistically overflow
        unchecked {
            // For each target:
            for (uint256 i = 0; i < numTargets; ++i) {
                // Execute the transaction
                (bool success, ) = _targets[i].call{ value: _values[i] }(_calldatas[i]);

                // Ensure the transaction succeeded
                if (!success) revert EXECUTION_FAILED(i);
            }
        }

        emit TransactionExecuted(proposalId, _targets, _values, _calldatas);
    }

    ///                                                          ///
    ///                       CANCEL PROPOSAL                    ///
    ///                                                          ///

    /// @notice Removes a queued proposal
    /// @param _proposalId The proposal id
    function cancel(bytes32 _proposalId) external onlyOwner {
        // Ensure the proposal is queued
        if (!isQueued(_proposalId)) revert PROPOSAL_NOT_QUEUED();

        // Remove the proposal from the queue
        delete timestamps[_proposalId];

        emit TransactionCanceled(_proposalId);
    }

    ///                                                          ///
    ///                      TREASURY SETTINGS                   ///
    ///                                                          ///

    /// @notice The time delay to execute a queued transaction
    function delay() external view returns (uint256) {
        return settings.delay;
    }

    /// @notice The time period to execute a proposal
    function gracePeriod() external view returns (uint256) {
        return settings.gracePeriod;
    }

    ///                                                          ///
    ///                       UPDATE SETTINGS                    ///
    ///                                                          ///

    /// @notice Updates the transaction delay
    /// @param _newDelay The new time delay
    function updateDelay(uint256 _newDelay) external {
        // Ensure the caller is the treasury itself
        if (msg.sender != address(this)) revert ONLY_TREASURY();

        emit DelayUpdated(settings.delay, _newDelay);

        // Update the delay
        settings.delay = SafeCast.toUint128(_newDelay);
    }

    /// @notice Updates the execution grace period
    /// @param _newGracePeriod The new grace period
    function updateGracePeriod(uint256 _newGracePeriod) external {
        // Ensure the caller is the treasury itself
        if (msg.sender != address(this)) revert ONLY_TREASURY();

        emit GracePeriodUpdated(settings.gracePeriod, _newGracePeriod);

        // Update the grace period
        settings.gracePeriod = SafeCast.toUint128(_newGracePeriod);
    }

    /// @notice Registers a treasury safe
    function registerSafe(address _safe, address _execModule, address _policy, bytes32 _policyHash, bool _setAsMain) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        _registerSafe(_safe, _execModule, _policy, _policyHash, _setAsMain);
    }

    /// @notice Updates an existing treasury safe
    function updateSafe(uint32 _safeId, bool _active, address _execModule, address _policy, bytes32 _policyHash) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();
        if (_execModule == address(0)) revert INVALID_MODULE();

        SafeConfigV2 storage cfg = safes[_safeId];
        if (cfg.safe == address(0)) revert SAFE_NOT_REGISTERED();

        cfg.active = _active;
        cfg.execModule = _execModule;
        cfg.policy = _policy;
        cfg.policyHash = _policyHash;

        emit SafeUpdated(_safeId, _active, _execModule, _policy, _policyHash);
    }

    /// @notice Sets which registered safe is the main safe
    function setMainSafe(uint32 _safeId) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();

        SafeConfigV2 storage newMain = safes[_safeId];
        if (newMain.safe == address(0)) revert SAFE_NOT_REGISTERED();
        if (!newMain.active) revert SAFE_INACTIVE();

        uint32 prevMainId = _mainSafeId;
        if (prevMainId != 0) {
            safes[prevMainId].isMain = false;
        }

        newMain.isMain = true;
        _mainSafeId = _safeId;

        emit MainSafeUpdated(prevMainId, _safeId);
    }

    /// @notice Sets global policy metadata
    function setGlobalPolicy(address _policy, bytes32 _policyHash, bool _enforce) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        _setGlobalPolicy(_policy, _policyHash, _enforce);
    }

    /// @notice Executes through a registered safe module
    /// @dev Callable only by this treasury during proposal execution
    function execOnSafe(uint32 _safeId, address _target, uint256 _value, bytes calldata _data, uint8 _operation)
        external
        returns (bytes memory returnData)
    {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        if (_operation != SAFE_OP_CALL) revert INVALID_OPERATION();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();

        SafeConfigV2 storage cfg = safes[_safeId];
        if (cfg.safe == address(0)) revert SAFE_NOT_REGISTERED();
        if (!cfg.active) revert SAFE_INACTIVE();

        try IGovernorSafeModule(cfg.execModule).execTransactionFromModule(cfg.safe, _target, _value, _data, _operation) returns (
            bytes memory _returnData
        ) {
            emit SafeExecution(_safeId, cfg.safe, _target, _value, _operation, _data, _returnData);
            return _returnData;
        } catch {
            revert SAFE_EXECUTION_FAILED();
        }
    }

    /// @notice Gets safe config for a safe id
    function getSafe(uint32 _safeId) external view returns (ITreasury.SafeConfig memory) {
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();
        SafeConfigV2 memory cfg = safes[_safeId];
        return ITreasury.SafeConfig({
            safe: cfg.safe,
            execModule: cfg.execModule,
            policy: cfg.policy,
            policyHash: cfg.policyHash,
            active: cfg.active,
            isMain: cfg.isMain
        });
    }

    /// @notice Gets global policy metadata
    function getGlobalPolicy() external view returns (ITreasury.GlobalPolicy memory) {
        return ITreasury.GlobalPolicy({
            policy: globalPolicy.policy,
            policyHash: globalPolicy.policyHash,
            enforce: globalPolicy.enforce
        });
    }

    /// @notice The current main safe id
    function mainSafeId() external view returns (uint32) {
        return _mainSafeId;
    }

    /// @notice Number of registered safes
    function safeCount() external view returns (uint32) {
        return _safeCount;
    }

    /// @notice Returns the safe id for a safe address
    function getSafeIdByAddress(address _safe) external view returns (uint32) {
        return safeIds[_safe];
    }

    ///                                                          ///
    ///                        RECEIVE TOKENS                    ///
    ///                                                          ///

    /// @dev Accepts all ERC-721 transfers
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    /// @dev Accepts all ERC-1155 single id transfers
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @dev Accept all ERC-1155 batch id transfers
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }

    /// @dev Accepts ETH transfers
    receive() external payable {}

    /// @dev Registers a safe config
    function _registerSafe(address _safe, address _execModule, address _policy, bytes32 _policyHash, bool _setAsMain) internal {
        if (_safe == address(0)) revert ADDRESS_ZERO();
        if (_execModule == address(0)) revert INVALID_MODULE();
        if (safeIds[_safe] != 0) revert SAFE_ALREADY_REGISTERED();

        unchecked {
            _safeCount++;
        }

        uint32 newId = _safeCount;

        safes[newId] = SafeConfigV2({
            safe: _safe,
            execModule: _execModule,
            policy: _policy,
            policyHash: _policyHash,
            active: true,
            isMain: false
        });
        safeIds[_safe] = newId;

        emit SafeRegistered(newId, _safe, false, _execModule, _policy, _policyHash);

        if (_setAsMain || _mainSafeId == 0) {
            uint32 prevMainId = _mainSafeId;
            if (prevMainId != 0) {
                safes[prevMainId].isMain = false;
            }

            safes[newId].isMain = true;
            _mainSafeId = newId;

            emit MainSafeUpdated(prevMainId, newId);
        }
    }

    /// @dev Sets global policy metadata
    function _setGlobalPolicy(address _policy, bytes32 _policyHash, bool _enforce) internal {
        globalPolicy = GlobalPolicyV2({ policy: _policy, policyHash: _policyHash, enforce: _enforce });
        emit GlobalPolicyUpdated(_policy, _policyHash, _enforce);
    }

    ///                                                          ///
    ///                       TREASURY UPGRADE                   ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract and that the new implementation is valid
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override {
        // Ensure the caller is the treasury itself
        if (msg.sender != address(this)) revert ONLY_TREASURY();

        // Ensure the new implementation is a registered upgrade
        if (!manager.isRegisteredUpgrade(_getImplementation(), _newImpl)) revert INVALID_UPGRADE(_newImpl);
    }
}
