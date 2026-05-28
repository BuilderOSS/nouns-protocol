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
import { IGnosisSafe } from "./interfaces/IGnosisSafe.sol";
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
    function registerSafe(address _safe, address _execModule, address _policy, bytes32 _policyHash) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        _registerSafe(_safe, _execModule, _policy, _policyHash);
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

        // Check pause states
        if (allSafesPaused) revert ALL_SAFES_PAUSED();
        if (safePaused[_safeId]) revert SAFE_PAUSED();

        SafeConfigV2 storage cfg = safes[_safeId];
        if (cfg.safe == address(0)) revert SAFE_NOT_REGISTERED();
        if (!cfg.active) revert SAFE_INACTIVE();

        // Check spending limits
        _checkSpendingLimits(_safeId, _value);

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
            active: cfg.active
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

    /// @notice Number of registered safes
    function safeCount() external view returns (uint32) {
        return _safeCount;
    }

    /// @notice Returns the safe id for a safe address
    function getSafeIdByAddress(address _safe) external view returns (uint32) {
        return safeIds[_safe];
    }

    /// @notice Checks if a safe is ready for registration (module enabled)
    /// @param _safe The safe address
    /// @param _execModule The module address to check
    /// @return ready True if module is enabled on the safe
    function isSafeReady(address _safe, address _execModule) external view returns (bool ready) {
        if (_safe == address(0) || _execModule == address(0)) return false;
        try IGnosisSafe(_safe).isModuleEnabled(_execModule) returns (bool enabled) {
            return enabled;
        } catch {
            return false;
        }
    }

    ///                                                          ///
    ///                      SAFETY MECHANISMS                   ///
    ///                                                          ///

    /// @notice Sets spending limits for a safe
    /// @param _safeId The safe id
    /// @param _perTxLimit Maximum value per transaction (0 = no limit)
    /// @param _dailyLimit Maximum value per day (0 = no limit)
    function setSafeSpendingLimits(uint32 _safeId, uint256 _perTxLimit, uint256 _dailyLimit) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();

        safeSpendingLimits[_safeId] = _perTxLimit;
        safeSpendingTrackers[_safeId].dailyLimit = _dailyLimit;

        emit SafeSpendingLimitUpdated(_safeId, _perTxLimit, _dailyLimit);
    }

    /// @notice Pauses a specific safe
    /// @param _safeId The safe id to pause
    function pauseSafe(uint32 _safeId) external {
        if (msg.sender != guardian && msg.sender != address(this)) revert ONLY_GUARDIAN();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();

        safePaused[_safeId] = true;
        emit SafePaused(_safeId, msg.sender);
    }

    /// @notice Unpauses a specific safe
    /// @param _safeId The safe id to unpause
    function unpauseSafe(uint32 _safeId) external {
        if (msg.sender != guardian && msg.sender != address(this)) revert ONLY_GUARDIAN();
        if (_safeId == 0 || _safeId > _safeCount) revert INVALID_SAFE_ID();

        safePaused[_safeId] = false;
        emit SafeUnpaused(_safeId, msg.sender);
    }

    /// @notice Emergency pause all safe execution
    function pauseAllSafes() external {
        if (msg.sender != guardian && msg.sender != address(this)) revert ONLY_GUARDIAN();

        allSafesPaused = true;
        emit AllSafesPaused(msg.sender);
    }

    /// @notice Unpause all safe execution
    function unpauseAllSafes() external {
        if (msg.sender != guardian && msg.sender != address(this)) revert ONLY_GUARDIAN();

        allSafesPaused = false;
        emit AllSafesUnpaused(msg.sender);
    }

    /// @notice Sets the guardian address
    /// @param _guardian The new guardian address
    function setGuardian(address _guardian) external {
        if (msg.sender != address(this)) revert ONLY_TREASURY();

        emit GuardianUpdated(guardian, _guardian);
        guardian = _guardian;
    }

    /// @notice Gets the guardian address
    function getGuardian() external view returns (address) {
        return guardian;
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
    function _registerSafe(address _safe, address _execModule, address _policy, bytes32 _policyHash) internal {
        if (_safe == address(0)) revert ADDRESS_ZERO();
        if (_execModule == address(0)) revert INVALID_MODULE();
        if (safeIds[_safe] != 0) revert SAFE_ALREADY_REGISTERED();

        // Verify module is enabled on Safe
        if (!IGnosisSafe(_safe).isModuleEnabled(_execModule)) revert MODULE_NOT_ENABLED();

        unchecked {
            _safeCount++;
        }

        uint32 newId = _safeCount;

        safes[newId] = SafeConfigV2({
            safe: _safe,
            execModule: _execModule,
            policy: _policy,
            policyHash: _policyHash,
            active: true
        });
        safeIds[_safe] = newId;

        emit SafeRegistered(newId, _safe, _execModule, _policy, _policyHash);
    }

    /// @dev Sets global policy metadata
    function _setGlobalPolicy(address _policy, bytes32 _policyHash, bool _enforce) internal {
        globalPolicy = GlobalPolicyV2({ policy: _policy, policyHash: _policyHash, enforce: _enforce });
        emit GlobalPolicyUpdated(_policy, _policyHash, _enforce);
    }

    /// @dev Checks and updates spending limits for a safe
    function _checkSpendingLimits(uint32 _safeId, uint256 _value) internal {
        // Check per-transaction limit
        uint256 perTxLimit = safeSpendingLimits[_safeId];
        if (perTxLimit > 0 && _value > perTxLimit) {
            revert SPENDING_LIMIT_EXCEEDED();
        }

        // Check daily limit
        SpendingTrackerV2 storage tracker = safeSpendingTrackers[_safeId];
        if (tracker.dailyLimit > 0) {
            // Reset if new day
            if (block.timestamp >= tracker.lastResetTime + 1 days) {
                tracker.spentToday = 0;
                tracker.lastResetTime = uint64(block.timestamp);
            }

            // Check if adding this transaction would exceed daily limit
            if (tracker.spentToday + _value > tracker.dailyLimit) {
                revert DAILY_LIMIT_EXCEEDED();
            }

            // Update spent amount
            tracker.spentToday += _value;
        }
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
