// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { UUPS } from "../../lib/proxy/UUPS.sol";
import { Ownable } from "../../lib/utils/Ownable.sol";
import { EIP712 } from "../../lib/utils/EIP712.sol";
import { SafeCast } from "../../lib/utils/SafeCast.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { GovernorStorageV1 } from "./storage/GovernorStorageV1.sol";
import { GovernorStorageV2 } from "./storage/GovernorStorageV2.sol";
import { GovernorStorageV3 } from "./storage/GovernorStorageV3.sol";
import { Token } from "../../token/Token.sol";
import { Treasury } from "../treasury/Treasury.sol";
import { IManager } from "../../manager/IManager.sol";
import { IGovernor } from "./IGovernor.sol";
import { ProposalHasher } from "./ProposalHasher.sol";
import { VersionedContract } from "../../VersionedContract.sol";

/// @title Governor
/// @author Rohan Kulkarni
/// @notice A DAO's proposal manager and transaction scheduler
/// @custom:repo github.com/ourzora/nouns-protocol
/// Modified from:
/// - OpenZeppelin Contracts v4.7.3 (governance/extensions/GovernorTimelockControl.sol)
/// - NounsDAOLogicV1.sol commit 2cbe6c7 - licensed under the BSD-3-Clause license.
contract Governor is IGovernor, VersionedContract, UUPS, Ownable, EIP712, ProposalHasher, GovernorStorageV1, GovernorStorageV2, GovernorStorageV3 {
    ///                                                          ///
    ///                         IMMUTABLES                       ///
    ///                                                          ///

    /// @notice The EIP-712 typehash to vote with a signature
    bytes32 public immutable VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 proposalId,uint256 support,uint256 nonce,uint256 deadline)");

    /// @notice The EIP-712 typehash to sponsor proposal submission
    bytes32 public immutable PROPOSAL_TYPEHASH = keccak256("Proposal(address proposer,bytes32 txsHash,uint256 nonce,uint256 deadline)");

    /// @notice The EIP-712 typehash to sponsor proposal update
    bytes32 public immutable UPDATE_PROPOSAL_TYPEHASH =
        keccak256("UpdateProposal(bytes32 proposalId,address proposer,bytes32 txsHash,uint256 nonce,uint256 deadline)");

    /// @notice The minimum proposal threshold bps setting
    uint256 public immutable MIN_PROPOSAL_THRESHOLD_BPS = 1;

    /// @notice The maximum proposal threshold bps setting
    uint256 public immutable MAX_PROPOSAL_THRESHOLD_BPS = 1000;

    /// @notice The minimum quorum threshold bps setting
    uint256 public immutable MIN_QUORUM_THRESHOLD_BPS = 200;

    /// @notice The maximum quorum threshold bps setting
    uint256 public immutable MAX_QUORUM_THRESHOLD_BPS = 2000;

    /// @notice The minimum voting delay setting
    uint256 public immutable MIN_VOTING_DELAY = 1 seconds;

    /// @notice The maximum voting delay setting
    uint256 public immutable MAX_VOTING_DELAY = 24 weeks;

    /// @notice The minimum voting period setting
    uint256 public immutable MIN_VOTING_PERIOD = 10 minutes;

    /// @notice The maximum voting period setting
    uint256 public immutable MAX_VOTING_PERIOD = 24 weeks;

    /// @notice The maximum proposal updatable period setting
    uint256 public immutable MAX_PROPOSAL_UPDATABLE_PERIOD = 24 weeks;

    /// @notice The default period a newly-created proposal is editable
    uint256 public constant DEFAULT_PROPOSAL_UPDATABLE_PERIOD = 1 days;

    /// @notice The maximum number of signer sponsors allowed per proposal
    uint256 public constant MAX_PROPOSAL_SIGNERS = 32;

    /// @notice The maximum delayed governance expiration setting
    uint256 public immutable MAX_DELAYED_GOVERNANCE_EXPIRATION = 30 days;

    /// @notice The basis points for 100%
    uint256 private immutable BPS_PER_100_PERCENT = 10_000;

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

    /// @notice Initializes a DAO's governor
    /// @param _treasury The DAO's treasury address
    /// @param _token The DAO's governance token address
    /// @param _vetoer The address eligible to veto proposals
    /// @param _votingDelay The voting delay
    /// @param _votingPeriod The voting period
    /// @param _proposalThresholdBps The proposal threshold basis points
    /// @param _quorumThresholdBps The quorum threshold basis points
    function initialize(
        address _treasury,
        address _token,
        address _vetoer,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThresholdBps,
        uint256 _quorumThresholdBps
    ) external initializer {
        // Ensure the caller is the contract manager
        if (msg.sender != address(manager)) revert ONLY_MANAGER();

        // Ensure non-zero addresses are provided
        if (_treasury == address(0)) revert ADDRESS_ZERO();
        if (_token == address(0)) revert ADDRESS_ZERO();

        // If a vetoer is specified, store its address
        if (_vetoer != address(0)) settings.vetoer = _vetoer;

        // Ensure the specified governance settings are valid
        if (_proposalThresholdBps < MIN_PROPOSAL_THRESHOLD_BPS || _proposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS)
            revert INVALID_PROPOSAL_THRESHOLD_BPS();
        if (_quorumThresholdBps < MIN_QUORUM_THRESHOLD_BPS || _quorumThresholdBps > MAX_QUORUM_THRESHOLD_BPS) revert INVALID_QUORUM_THRESHOLD_BPS();
        if (_proposalThresholdBps >= _quorumThresholdBps) revert INVALID_PROPOSAL_THRESHOLD_BPS();
        if (_votingDelay < MIN_VOTING_DELAY || _votingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (_votingPeriod < MIN_VOTING_PERIOD || _votingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        // Store the governor settings
        settings.treasury = Treasury(payable(_treasury));
        settings.token = Token(_token);
        settings.votingDelay = SafeCast.toUint48(_votingDelay);
        settings.votingPeriod = SafeCast.toUint48(_votingPeriod);
        settings.proposalThresholdBps = SafeCast.toUint16(_proposalThresholdBps);
        settings.quorumThresholdBps = SafeCast.toUint16(_quorumThresholdBps);
        _proposalUpdatablePeriod = uint48(DEFAULT_PROPOSAL_UPDATABLE_PERIOD);

        // Initialize EIP-712 support
        __EIP712_init(string.concat(settings.token.symbol(), " GOV"), "1");

        // Grant ownership to the treasury
        __Ownable_init(_treasury);
    }

    ///                                                          ///
    ///                        CREATE PROPOSAL                   ///
    ///                                                          ///

    /// @notice Creates a proposal
    /// @param _targets The target addresses to call
    /// @param _values The ETH values of each call
    /// @param _calldatas The calldata of each call
    /// @param _description The proposal description
    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external returns (bytes32) {
        // Ensure governance is not delayed or all reserved tokens have been minted
        if (block.timestamp < delayedGovernanceExpirationTimestamp && settings.token.remainingTokensInReserve() > 0) {
            revert WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION();
        }

        // Get the current proposal threshold
        uint256 currentProposalThreshold = proposalThreshold();

        // Cannot realistically underflow and `getVotes` would revert
        unchecked {
            // Ensure the caller's voting weight is greater than or equal to the threshold
            if (getVotes(msg.sender, block.timestamp - 1) <= proposalThreshold()) {
                revert BELOW_PROPOSAL_THRESHOLD();
            }
        }

        _validateProposalArrays(_targets, _values, _calldatas);

        return _createProposal(_targets, _values, _calldatas, _description, msg.sender, currentProposalThreshold);
    }

    /// @notice Creates a proposal backed by signer approvals
    function proposeBySigs(
        ProposerSignature[] memory _proposerSignatures,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external returns (bytes32) {
        if (_proposerSignatures.length == 0) revert MUST_PROVIDE_SIGNATURES();
        if (_proposerSignatures.length > MAX_PROPOSAL_SIGNERS) revert TOO_MANY_SIGNERS();

        // Ensure governance is not delayed or all reserved tokens have been minted
        if (block.timestamp < delayedGovernanceExpirationTimestamp && settings.token.remainingTokensInReserve() > 0) {
            revert WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION();
        }

        _validateProposalArrays(_targets, _values, _calldatas);

        bytes32 txsHash = _hashTxs(_targets, _values, _calldatas);

        uint256 votes = getVotes(msg.sender, block.timestamp - 1);
        address[] memory signers = new address[](_proposerSignatures.length);

        for (uint256 i = 0; i < _proposerSignatures.length; ++i) {
            ProposerSignature memory proposerSignature = _proposerSignatures[i];

            if (proposerSignature.signer == msg.sender) revert PROPOSER_CANNOT_BE_SIGNER();

            if (i > 0 && proposerSignature.signer <= _proposerSignatures[i - 1].signer) {
                revert INVALID_SIGNATURE_ORDER();
            }

            _verifyProposeSignature(msg.sender, txsHash, proposerSignature);

            signers[i] = proposerSignature.signer;
            votes += getVotes(proposerSignature.signer, block.timestamp - 1);
        }

        uint256 currentProposalThreshold = proposalThreshold();
        if (votes <= currentProposalThreshold) revert VOTES_BELOW_PROPOSAL_THRESHOLD();

        bytes32 proposalId = _createProposal(_targets, _values, _calldatas, _description, msg.sender, currentProposalThreshold);

        address[] storage proposalSignersList = proposalSigners[proposalId];
        uint256 signersLen = signers.length;
        for (uint256 i; i < signersLen; ++i) {
            proposalSignersList.push(signers[i]);
        }

        emit ProposalSignersSet(proposalId, signers);

        return proposalId;
    }

    /// @notice Updates an existing proposal during updatable period
    function updateProposal(
        bytes32 _proposalId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        string memory _updateMessage
    ) external returns (bytes32) {
        _checkCanUpdateProposal(_proposalId);
        _validateProposalArrays(_targets, _values, _calldatas);

        Proposal memory oldProposal = proposals[_proposalId];
        address[] storage signers = proposalSigners[_proposalId];

        if (signers.length > 0 && !_proposerMetThresholdAtCreation(oldProposal)) {
            revert UNQUALIFIED_PROPOSER_MUST_USE_SIGNATURES();
        }

        bytes32 newProposalId = _replaceProposal(_proposalId, oldProposal, signers, _targets, _values, _calldatas, _description);

        emit ProposalUpdated(_proposalId, newProposalId, _targets, _values, _calldatas, _description, _updateMessage);

        return newProposalId;
    }

    /// @notice Updates a signed proposal with signer approvals
    function updateProposalBySigs(
        bytes32 _proposalId,
        ProposerSignature[] memory _proposerSignatures,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        string memory _updateMessage
    ) external returns (bytes32) {
        _checkCanUpdateProposal(_proposalId);
        _validateProposalArrays(_targets, _values, _calldatas);

        Proposal memory oldProposal = proposals[_proposalId];
        address[] storage signers = proposalSigners[_proposalId];

        if (signers.length == 0) revert MUST_PROVIDE_SIGNATURES();
        if (_proposerSignatures.length != signers.length) revert SIGNER_COUNT_MISMATCH();

        bytes32 txsHash = _hashTxs(_targets, _values, _calldatas);

        for (uint256 i = 0; i < _proposerSignatures.length; ++i) {
            ProposerSignature memory proposerSignature = _proposerSignatures[i];
            if (proposerSignature.signer != signers[i]) revert INVALID_SIGNATURE_ORDER();

            _verifyUpdateSignature(_proposalId, msg.sender, txsHash, proposerSignature);
        }

        bytes32 newProposalId = _replaceProposal(_proposalId, oldProposal, signers, _targets, _values, _calldatas, _description);

        emit ProposalUpdated(_proposalId, newProposalId, _targets, _values, _calldatas, _description, _updateMessage);

        return newProposalId;
    }

    ///                                                          ///
    ///                          CAST VOTE                       ///
    ///                                                          ///

    /// @notice Casts a vote
    /// @param _proposalId The proposal id
    /// @param _support The support value (0 = Against, 1 = For, 2 = Abstain)
    function castVote(bytes32 _proposalId, uint256 _support) external returns (uint256) {
        return _castVote(_proposalId, msg.sender, _support, "");
    }

    /// @notice Casts a vote with a reason
    /// @param _proposalId The proposal id
    /// @param _support The support value (0 = Against, 1 = For, 2 = Abstain)
    /// @param _reason The vote reason
    function castVoteWithReason(
        bytes32 _proposalId,
        uint256 _support,
        string memory _reason
    ) external returns (uint256) {
        return _castVote(_proposalId, msg.sender, _support, _reason);
    }

    /// @notice Casts a signed vote
    /// @param _voter The voter address
    /// @param _proposalId The proposal id
    /// @param _support The support value (0 = Against, 1 = For, 2 = Abstain)
    /// @param _nonce The expected nonce for the voter signature
    /// @param _deadline The signature deadline
    /// @param _sig The full EIP-712 signature bytes
    function castVoteBySig(
        address _voter,
        bytes32 _proposalId,
        uint256 _support,
        uint256 _nonce,
        uint256 _deadline,
        bytes calldata _sig
    ) external returns (uint256) {
        // Ensure the deadline has not passed
        if (block.timestamp > _deadline) revert EXPIRED_SIGNATURE();

        uint256 expectedNonce = nonces[_voter];
        if (_nonce != expectedNonce) revert INVALID_SIGNATURE_NONCE();

        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, _voter, _proposalId, _support, _nonce, _deadline));
        bytes32 digest = _hashTypedData(structHash);

        if (!SignatureChecker.isValidSignatureNow(_voter, digest, _sig)) revert INVALID_SIGNATURE();

        nonces[_voter] = expectedNonce + 1;

        return _castVote(_proposalId, _voter, _support, "");
    }

    /// @dev Stores a vote
    /// @param _proposalId The proposal id
    /// @param _voter The voter address
    /// @param _support The vote choice
    function _castVote(
        bytes32 _proposalId,
        address _voter,
        uint256 _support,
        string memory _reason
    ) internal returns (uint256) {
        // Ensure voting is active
        if (state(_proposalId) != ProposalState.Active) revert VOTING_NOT_STARTED();

        // Ensure the voter hasn't already voted
        if (hasVoted[_proposalId][_voter]) revert ALREADY_VOTED();

        // Ensure the vote is valid
        if (_support > 2) revert INVALID_VOTE();

        // Record the voter as having voted
        hasVoted[_proposalId][_voter] = true;

        // Get the pointer to the proposal
        Proposal storage proposal = proposals[_proposalId];

        // Used to store the voter's weight
        uint256 weight;

        // Cannot realistically underflow and `getVotes` would revert
        unchecked {
            // Get the voter's weight at the time the proposal was created
            weight = getVotes(_voter, proposal.timeCreated);

            // If the vote is against:
            if (_support == 0) {
                // Update the total number of votes against
                proposal.againstVotes += SafeCast.toUint32(weight);

                // Else if the vote is for:
            } else if (_support == 1) {
                // Update the total number of votes for
                proposal.forVotes += SafeCast.toUint32(weight);

                // Else if the vote is to abstain:
            } else if (_support == 2) {
                // Update the total number of votes abstaining
                proposal.abstainVotes += SafeCast.toUint32(weight);
            }
        }

        emit VoteCast(_voter, _proposalId, _support, weight, _reason);

        return weight;
    }

    ///                                                          ///
    ///                        QUEUE PROPOSAL                    ///
    ///                                                          ///

    /// @notice Queues a proposal
    /// @param _proposalId The proposal id
    function queue(bytes32 _proposalId) external returns (uint256 eta) {
        // Ensure the proposal has succeeded
        if (state(_proposalId) != ProposalState.Succeeded) revert PROPOSAL_UNSUCCESSFUL();

        // Schedule the proposal for execution
        eta = settings.treasury.queue(_proposalId);

        emit ProposalQueued(_proposalId, eta);
    }

    ///                                                          ///
    ///                       EXECUTE PROPOSAL                   ///
    ///                                                          ///

    /// @notice Executes a proposal
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
    ) external payable returns (bytes32) {
        // Get the proposal id
        bytes32 proposalId = hashProposal(_targets, _values, _calldatas, _descriptionHash, _proposer);

        // Ensure the proposal is queued
        if (state(proposalId) != ProposalState.Queued) revert PROPOSAL_NOT_QUEUED(proposalId);

        // Mark the proposal as executed
        proposals[proposalId].executed = true;

        // Execute the proposal
        settings.treasury.execute{ value: msg.value }(_targets, _values, _calldatas, _descriptionHash, _proposer);

        emit ProposalExecuted(proposalId);

        return proposalId;
    }

    ///                                                          ///
    ///                        CANCEL PROPOSAL                   ///
    ///                                                          ///

    /// @notice Cancels a proposal
    /// @param _proposalId The proposal id
    function cancel(bytes32 _proposalId) external {
        // Ensure the proposal hasn't been executed
        if (state(_proposalId) == ProposalState.Executed) revert PROPOSAL_ALREADY_EXECUTED();

        // Get a copy of the proposal
        Proposal memory proposal = proposals[_proposalId];

        bool msgSenderIsProposerOrSigner = msg.sender == proposal.proposer;
        uint256 votes = getVotes(proposal.proposer, block.timestamp - 1);
        address[] storage signers = proposalSigners[_proposalId];
        uint256 signersLen = signers.length;
        for (uint256 i; i < signersLen; ++i) {
            msgSenderIsProposerOrSigner = msgSenderIsProposerOrSigner || msg.sender == signers[i];
            votes += getVotes(signers[i], block.timestamp - 1);
        }

        // Cannot realistically underflow and `getVotes` would revert
        unchecked {
            // Ensure the caller is the proposer/signer or backing votes have dropped below the proposal threshold
            if (!msgSenderIsProposerOrSigner && votes >= proposal.proposalThreshold) revert INVALID_CANCEL();
        }

        // Update the proposal as canceled
        proposals[_proposalId].canceled = true;

        // If the proposal was queued:
        if (settings.treasury.isQueued(_proposalId)) {
            // Cancel the proposal
            settings.treasury.cancel(_proposalId);
        }

        emit ProposalCanceled(_proposalId);
    }

    ///                                                          ///
    ///                        VETO PROPOSAL                     ///
    ///                                                          ///

    /// @notice Vetoes a proposal
    /// @param _proposalId The proposal id
    function veto(bytes32 _proposalId) external {
        // Ensure the caller is the vetoer
        if (msg.sender != settings.vetoer) revert ONLY_VETOER();

        // Ensure the proposal has not been executed
        if (state(_proposalId) == ProposalState.Executed) revert PROPOSAL_ALREADY_EXECUTED();

        // Get the pointer to the proposal
        Proposal storage proposal = proposals[_proposalId];

        // Update the proposal as vetoed
        proposal.vetoed = true;

        // If the proposal was queued:
        if (settings.treasury.isQueued(_proposalId)) {
            // Cancel the proposal
            settings.treasury.cancel(_proposalId);
        }

        emit ProposalVetoed(_proposalId);
    }

    ///                                                          ///
    ///                        PROPOSAL STATE                    ///
    ///                                                          ///

    /// @notice The state of a proposal
    /// @param _proposalId The proposal id
    function state(bytes32 _proposalId) public view returns (ProposalState) {
        // Get a copy of the proposal
        Proposal memory proposal = proposals[_proposalId];

        // Ensure the proposal exists
        if (proposal.voteStart == 0) revert PROPOSAL_DOES_NOT_EXIST();

        // If the proposal was executed:
        if (proposal.executed) {
            return ProposalState.Executed;

            // Else if the proposal was canceled:
        } else if (proposal.canceled) {
            // Check if this was a replacement (updated proposal)
            if (proposalIdReplacedBy[_proposalId] != bytes32(0)) {
                return ProposalState.Replaced;
            }
            return ProposalState.Canceled;

            // Else if the proposal was vetoed:
        } else if (proposal.vetoed) {
            return ProposalState.Vetoed;

            // Else if proposal is still in updatable period:
        } else if (block.timestamp < proposalUpdatePeriodEnds[_proposalId]) {
            return ProposalState.Updatable;

            // Else if voting has not started:
        } else if (block.timestamp < proposal.voteStart) {
            return ProposalState.Pending;

            // Else if voting has not ended:
        } else if (block.timestamp < proposal.voteEnd) {
            return ProposalState.Active;

            // Else if the proposal failed (outvoted OR didn't reach quorum):
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < proposal.quorumVotes) {
            return ProposalState.Defeated;

            // Else if the proposal has not been queued:
        } else if (settings.treasury.timestamp(_proposalId) == 0) {
            return ProposalState.Succeeded;

            // Else if the proposal can no longer be executed:
        } else if (settings.treasury.isExpired(_proposalId)) {
            return ProposalState.Expired;

            // Else the proposal is queued
        } else {
            return ProposalState.Queued;
        }
    }

    /// @notice The voting weight of an account at a timestamp
    /// @param _account The account address
    /// @param _timestamp The specific timestamp
    function getVotes(address _account, uint256 _timestamp) public view returns (uint256) {
        return settings.token.getPastVotes(_account, _timestamp);
    }

    /// @notice The current number of votes required to submit a proposal
    function proposalThreshold() public view returns (uint256) {
        unchecked {
            return (settings.token.totalSupply() * settings.proposalThresholdBps) / BPS_PER_100_PERCENT;
        }
    }

    /// @notice The current number of votes required to be in favor of a proposal in order to reach quorum
    function quorum() public view returns (uint256) {
        unchecked {
            return (settings.token.totalSupply() * settings.quorumThresholdBps) / BPS_PER_100_PERCENT;
        }
    }

    /// @notice The data stored for a given proposal
    /// @param _proposalId The proposal id
    function getProposal(bytes32 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /// @notice The signers that sponsored a signed proposal
    /// @param _proposalId The proposal id
    function getProposalSigners(bytes32 _proposalId) external view returns (address[] memory) {
        return proposalSigners[_proposalId];
    }

    /// @notice The timestamp until which proposal updates are allowed
    /// @param _proposalId The proposal id
    function proposalUpdatePeriodEnd(bytes32 _proposalId) external view returns (uint256) {
        return proposalUpdatePeriodEnds[_proposalId];
    }

    /// @notice The timestamp when voting starts for a proposal
    /// @param _proposalId The proposal id
    function proposalSnapshot(bytes32 _proposalId) external view returns (uint256) {
        return proposals[_proposalId].voteStart;
    }

    /// @notice The timestamp when voting ends for a proposal
    /// @param _proposalId The proposal id
    function proposalDeadline(bytes32 _proposalId) external view returns (uint256) {
        return proposals[_proposalId].voteEnd;
    }

    /// @notice The vote counts for a proposal
    /// @param _proposalId The proposal id
    function proposalVotes(bytes32 _proposalId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        Proposal memory proposal = proposals[_proposalId];

        return (proposal.againstVotes, proposal.forVotes, proposal.abstainVotes);
    }

    /// @notice The timestamp valid to execute a proposal
    /// @param _proposalId The proposal id
    function proposalEta(bytes32 _proposalId) external view returns (uint256) {
        return settings.treasury.timestamp(_proposalId);
    }

    ///                                                          ///
    ///                      GOVERNOR SETTINGS                   ///
    ///                                                          ///

    /// @notice The basis points of the token supply required to create a proposal
    function proposalThresholdBps() external view returns (uint256) {
        return settings.proposalThresholdBps;
    }

    /// @notice The basis points of the token supply required to reach quorum
    function quorumThresholdBps() external view returns (uint256) {
        return settings.quorumThresholdBps;
    }

    /// @notice The amount of time until voting begins after a proposal is created
    function votingDelay() external view returns (uint256) {
        return settings.votingDelay;
    }

    /// @notice The amount of time to vote on a proposal
    function votingPeriod() external view returns (uint256) {
        return settings.votingPeriod;
    }

    /// @notice The amount of time a proposal is editable after creation
    function proposalUpdatablePeriod() external view returns (uint256) {
        return _proposalUpdatablePeriod;
    }

    /// @notice The current proposal-signature nonce for an account
    /// @param _account The signer address
    function proposeSignatureNonce(address _account) external view returns (uint256) {
        return proposeSigNonces[_account];
    }

    /// @notice The address eligible to veto any proposal (address(0) if burned)
    function vetoer() external view returns (address) {
        return settings.vetoer;
    }

    /// @notice The address of the governance token
    function token() external view returns (address) {
        return address(settings.token);
    }

    /// @notice The address of the treasury
    function treasury() external view returns (address) {
        return address(settings.treasury);
    }

    ///                                                          ///
    ///                       UPDATE SETTINGS                    ///
    ///                                                          ///

    /// @notice Updates the voting delay
    /// @param _newVotingDelay The new voting delay
    function updateVotingDelay(uint256 _newVotingDelay) external onlyOwner {
        if (_newVotingDelay < MIN_VOTING_DELAY || _newVotingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();

        emit VotingDelayUpdated(settings.votingDelay, _newVotingDelay);

        settings.votingDelay = uint48(_newVotingDelay);
    }

    /// @notice Updates the voting period
    /// @param _newVotingPeriod The new voting period
    function updateVotingPeriod(uint256 _newVotingPeriod) external onlyOwner {
        if (_newVotingPeriod < MIN_VOTING_PERIOD || _newVotingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        emit VotingPeriodUpdated(settings.votingPeriod, _newVotingPeriod);

        settings.votingPeriod = uint48(_newVotingPeriod);
    }

    /// @notice Updates the proposal updatable period
    /// @param _newProposalUpdatablePeriod The new proposal updatable period
    function updateProposalUpdatablePeriod(uint256 _newProposalUpdatablePeriod) external onlyOwner {
        if (_newProposalUpdatablePeriod > MAX_PROPOSAL_UPDATABLE_PERIOD) revert INVALID_PROPOSAL_UPDATABLE_PERIOD();

        emit ProposalUpdatablePeriodUpdated(_proposalUpdatablePeriod, _newProposalUpdatablePeriod);

        _proposalUpdatablePeriod = uint48(_newProposalUpdatablePeriod);
    }

    /// @notice Updates the minimum proposal threshold
    /// @param _newProposalThresholdBps The new proposal threshold basis points
    function updateProposalThresholdBps(uint256 _newProposalThresholdBps) external onlyOwner {
        if (
            _newProposalThresholdBps < MIN_PROPOSAL_THRESHOLD_BPS ||
            _newProposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS ||
            _newProposalThresholdBps >= settings.quorumThresholdBps
        ) revert INVALID_PROPOSAL_THRESHOLD_BPS();

        emit ProposalThresholdBpsUpdated(settings.proposalThresholdBps, _newProposalThresholdBps);

        settings.proposalThresholdBps = uint16(_newProposalThresholdBps);
    }

    /// @notice Updates the minimum quorum threshold
    /// @param _newQuorumVotesBps The new quorum votes basis points
    function updateQuorumThresholdBps(uint256 _newQuorumVotesBps) external onlyOwner {
        if (
            _newQuorumVotesBps < MIN_QUORUM_THRESHOLD_BPS ||
            _newQuorumVotesBps > MAX_QUORUM_THRESHOLD_BPS ||
            settings.proposalThresholdBps >= _newQuorumVotesBps
        ) revert INVALID_QUORUM_THRESHOLD_BPS();

        emit QuorumVotesBpsUpdated(settings.quorumThresholdBps, _newQuorumVotesBps);

        settings.quorumThresholdBps = uint16(_newQuorumVotesBps);
    }

    /// @notice Updates the delayed governance expiration timestamp
    /// @param _newDelayedTimestamp The new delayed governance expiration timestamp
    function updateDelayedGovernanceExpirationTimestamp(uint256 _newDelayedTimestamp) external {
        // We want the founder to be able to set a governance delay if they are using a minter contract like MerkleReserveMinter
        if (msg.sender != settings.token.owner()) {
            revert ONLY_TOKEN_OWNER();
        }

        // Ensure the new timestamp is not too far in the future
        if (_newDelayedTimestamp > block.timestamp + MAX_DELAYED_GOVERNANCE_EXPIRATION) {
            revert INVALID_DELAYED_GOVERNANCE_EXPIRATION();
        }

        // Delay should only be set if no tokens have been minted to prevent active DAOs from accidentally or maliciously enabling this functionality
        // Delay is only available for DAOs that have reserved tokens
        if (settings.token.totalSupply() > 0 || settings.token.reservedUntilTokenId() == 0) {
            revert CANNOT_DELAY_GOVERNANCE();
        }

        emit DelayedGovernanceExpirationTimestampUpdated(delayedGovernanceExpirationTimestamp, _newDelayedTimestamp);

        delayedGovernanceExpirationTimestamp = _newDelayedTimestamp;
    }

    /// @notice Updates the vetoer
    /// @param _newVetoer The new vetoer address
    function updateVetoer(address _newVetoer) external onlyOwner {
        if (_newVetoer == address(0)) revert ADDRESS_ZERO();

        emit VetoerUpdated(settings.vetoer, _newVetoer);

        settings.vetoer = _newVetoer;
    }

    /// @notice Burns the vetoer
    function burnVetoer() external onlyOwner {
        emit VetoerUpdated(settings.vetoer, address(0));

        delete settings.vetoer;
    }

    function _createProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        address _proposer,
        uint256 _proposalThreshold
    ) internal returns (bytes32 proposalId) {
        bytes32 descriptionHash = keccak256(bytes(_description));
        proposalId = hashProposal(_targets, _values, _calldatas, descriptionHash, _proposer);

        Proposal storage proposal = proposals[proposalId];
        if (proposal.voteStart != 0) revert PROPOSAL_EXISTS(proposalId);

        uint256 snapshot;
        uint256 deadline;
        uint256 updatePeriodEnd;

        unchecked {
            updatePeriodEnd = block.timestamp + _proposalUpdatablePeriod;
            snapshot = updatePeriodEnd + settings.votingDelay;
            deadline = snapshot + settings.votingPeriod;
        }

        proposal.voteStart = SafeCast.toUint32(snapshot);
        proposal.voteEnd = SafeCast.toUint32(deadline);
        proposal.proposalThreshold = SafeCast.toUint32(_proposalThreshold);
        proposal.quorumVotes = SafeCast.toUint32(quorum());
        proposal.proposer = _proposer;
        proposal.timeCreated = SafeCast.toUint32(block.timestamp);

        proposalUpdatePeriodEnds[proposalId] = SafeCast.toUint32(updatePeriodEnd);

        emit ProposalCreated(proposalId, _targets, _values, _calldatas, _description, descriptionHash, proposal);
    }

    function _validateProposalArrays(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas
    ) internal pure {
        uint256 numTargets = _targets.length;
        if (numTargets == 0) revert PROPOSAL_TARGET_MISSING();
        if (numTargets != _values.length || numTargets != _calldatas.length) revert PROPOSAL_LENGTH_MISMATCH();
    }

    function _checkCanUpdateProposal(bytes32 _proposalId) internal view {
        if (state(_proposalId) != ProposalState.Updatable) revert CAN_ONLY_EDIT_UPDATABLE_PROPOSALS();
        if (msg.sender != proposals[_proposalId].proposer) revert ONLY_PROPOSER_CAN_EDIT();
    }

    function _proposerMetThresholdAtCreation(Proposal memory _proposal) internal view returns (bool) {
        if (_proposal.timeCreated == 0) {
            return false;
        }

        return getVotes(_proposal.proposer, uint256(_proposal.timeCreated) - 1) >= _proposal.proposalThreshold;
    }

    function _replaceProposal(
        bytes32 _oldProposalId,
        Proposal memory _oldProposal,
        address[] storage _oldSigners,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) internal returns (bytes32 newProposalId) {
        bytes32 descriptionHash = keccak256(bytes(_description));
        newProposalId = hashProposal(_targets, _values, _calldatas, descriptionHash, _oldProposal.proposer);

        if (newProposalId == _oldProposalId) {
            revert NO_OP_PROPOSAL_UPDATE();
        }

        if (proposals[newProposalId].voteStart != 0) revert PROPOSAL_EXISTS(newProposalId);

        Proposal storage newProposal = proposals[newProposalId];

        newProposal.proposer = _oldProposal.proposer;
        newProposal.timeCreated = _oldProposal.timeCreated;
        newProposal.againstVotes = _oldProposal.againstVotes;
        newProposal.forVotes = _oldProposal.forVotes;
        newProposal.abstainVotes = _oldProposal.abstainVotes;
        newProposal.voteStart = _oldProposal.voteStart;
        newProposal.voteEnd = _oldProposal.voteEnd;
        newProposal.proposalThreshold = _oldProposal.proposalThreshold;
        newProposal.quorumVotes = _oldProposal.quorumVotes;

        proposalUpdatePeriodEnds[newProposalId] = proposalUpdatePeriodEnds[_oldProposalId];

        address[] storage newSigners = proposalSigners[newProposalId];
        uint256 oldSignersLen = _oldSigners.length;
        for (uint256 i; i < oldSignersLen; ++i) {
            newSigners.push(_oldSigners[i]);
        }

        proposals[_oldProposalId].canceled = true;
        proposalIdReplacedBy[_oldProposalId] = newProposalId;
    }

    function _verifyProposeSignature(
        address _proposer,
        bytes32 _txsHash,
        ProposerSignature memory _proposerSignature
    ) internal {
        if (block.timestamp > _proposerSignature.deadline) revert EXPIRED_SIGNATURE();
        if (_proposerSignature.nonce != proposeSigNonces[_proposerSignature.signer]) revert INVALID_SIGNATURE_NONCE();

        bytes32 structHash = keccak256(
            abi.encode(PROPOSAL_TYPEHASH, _proposer, _txsHash, _proposerSignature.nonce, _proposerSignature.deadline)
        );
        bytes32 digest = _hashTypedData(structHash);

        if (!SignatureChecker.isValidSignatureNow(_proposerSignature.signer, digest, _proposerSignature.sig)) {
            revert INVALID_SIGNATURE();
        }

        proposeSigNonces[_proposerSignature.signer] = _proposerSignature.nonce + 1;
    }

    function _verifyUpdateSignature(
        bytes32 _proposalId,
        address _proposer,
        bytes32 _txsHash,
        ProposerSignature memory _proposerSignature
    ) internal {
        if (block.timestamp > _proposerSignature.deadline) revert EXPIRED_SIGNATURE();
        if (_proposerSignature.nonce != proposeSigNonces[_proposerSignature.signer]) revert INVALID_SIGNATURE_NONCE();

        bytes32 structHash = keccak256(
            abi.encode(
                UPDATE_PROPOSAL_TYPEHASH,
                _proposalId,
                _proposer,
                _txsHash,
                _proposerSignature.nonce,
                _proposerSignature.deadline
            )
        );
        bytes32 digest = _hashTypedData(structHash);

        if (!SignatureChecker.isValidSignatureNow(_proposerSignature.signer, digest, _proposerSignature.sig)) {
            revert INVALID_SIGNATURE();
        }

        proposeSigNonces[_proposerSignature.signer] = _proposerSignature.nonce + 1;
    }

    function _hashTxs(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_targets, _values, _calldatas));
    }

    function _hashTypedData(bytes32 _structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), _structHash));
    }

    ///                                                          ///
    ///                       GOVERNOR UPGRADE                   ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract and that the new implementation is valid
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {
        // Ensure the new implementation is a registered upgrade
        if (!manager.isRegisteredUpgrade(_getImplementation(), _newImpl)) revert INVALID_UPGRADE(_newImpl);
    }
}
