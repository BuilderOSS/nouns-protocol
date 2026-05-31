// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { IUUPS } from "../../lib/interfaces/IUUPS.sol";
import { IOwnable } from "../../lib/utils/Ownable.sol";
import { IEIP712 } from "../../lib/utils/EIP712.sol";
import { GovernorTypesV1 } from "./types/GovernorTypesV1.sol";
import { IManager } from "../../manager/IManager.sol";

/// @title IGovernor
/// @author Rohan Kulkarni
/// @notice The external Governor events, errors and functions
interface IGovernor is IUUPS, IOwnable, IEIP712, GovernorTypesV1 {
    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///
    /// @notice Emitted when a proposal is created
    /// @param proposalId The proposal ID
    /// @param targets The target addresses
    /// @param values The ETH values
    /// @param calldatas The calldata payloads
    /// @param description The proposal description
    /// @param descriptionHash The hash of the description
    /// @param proposal The proposal struct
    event ProposalCreated(
        bytes32 proposalId, address[] targets, uint256[] values, bytes[] calldatas, string description, bytes32 descriptionHash, Proposal proposal
    );

    /// @notice Emitted when a proposal is updated and replaced with a new id
    /// @param oldProposalId The old proposal ID
    /// @param newProposalId The new proposal ID
    /// @param proposer The proposer address
    /// @param targets The target addresses
    /// @param values The ETH values
    /// @param calldatas The calldata payloads
    /// @param description The proposal description
    /// @param updateMessage The update message
    event ProposalUpdated(
        bytes32 oldProposalId,
        bytes32 newProposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        string updateMessage
    );

    /// @notice Emitted when proposal signers are set on signed proposal creation
    /// @param proposalId The proposal ID
    /// @param signers The signer addresses
    event ProposalSignersSet(bytes32 proposalId, address[] signers);

    /// @notice Emitted when a proposal is queued
    /// @param proposalId The proposal ID
    /// @param eta The execution timestamp
    event ProposalQueued(bytes32 proposalId, uint256 eta);

    /// @notice Emitted when a proposal is executed
    /// @param proposalId The proposal id
    event ProposalExecuted(bytes32 proposalId);

    /// @notice Emitted when a proposal is canceled
    /// @param proposalId The proposal ID
    event ProposalCanceled(bytes32 proposalId);

    /// @notice Emitted when a proposal is vetoed
    /// @param proposalId The proposal ID
    event ProposalVetoed(bytes32 proposalId);

    /// @notice Emitted when a vote is cast for a proposal
    /// @param voter The voter address
    /// @param proposalId The proposal ID
    /// @param support The vote support (0=against, 1=for, 2=abstain)
    /// @param weight The vote weight
    /// @param reason The vote reason
    event VoteCast(address voter, bytes32 proposalId, uint256 support, uint256 weight, string reason);

    /// @notice Emitted when the governor's voting delay is updated
    /// @param prevVotingDelay The previous voting delay
    /// @param newVotingDelay The new voting delay
    event VotingDelayUpdated(uint256 prevVotingDelay, uint256 newVotingDelay);

    /// @notice Emitted when the governor's voting period is updated
    /// @param prevVotingPeriod The previous voting period
    /// @param newVotingPeriod The new voting period
    event VotingPeriodUpdated(uint256 prevVotingPeriod, uint256 newVotingPeriod);

    /// @notice Emitted when the basis points of the governor's proposal threshold is updated
    /// @param prevBps The previous basis points
    /// @param newBps The new basis points
    event ProposalThresholdBpsUpdated(uint256 prevBps, uint256 newBps);

    /// @notice Emitted when the basis points of the governor's quorum votes is updated
    /// @param prevBps The previous basis points
    /// @param newBps The new basis points
    event QuorumVotesBpsUpdated(uint256 prevBps, uint256 newBps);

    //// @notice Emitted when the governor's vetoer is updated
    /// @param prevVetoer The previous vetoer address
    /// @param newVetoer The new vetoer address
    event VetoerUpdated(address prevVetoer, address newVetoer);

    /// @notice Emitted when the governor's delay is updated
    /// @param prevTimestamp The previous timestamp
    /// @param newTimestamp The new timestamp
    event DelayedGovernanceExpirationTimestampUpdated(uint256 prevTimestamp, uint256 newTimestamp);

    /// @notice Emitted when proposal updatable period is updated
    /// @param prevProposalUpdatablePeriod The previous updatable period
    /// @param newProposalUpdatablePeriod The new updatable period
    event ProposalUpdatablePeriodUpdated(uint256 prevProposalUpdatablePeriod, uint256 newProposalUpdatablePeriod);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    error INVALID_PROPOSAL_THRESHOLD_BPS();

    error INVALID_QUORUM_THRESHOLD_BPS();

    error INVALID_VOTING_DELAY();

    error INVALID_VOTING_PERIOD();

    error INVALID_DELAYED_GOVERNANCE_EXPIRATION();

    /// @dev Reverts if a proposal already exists
    /// @param proposalId The proposal id
    error PROPOSAL_EXISTS(bytes32 proposalId);

    /// @dev Reverts if a proposal isn't queued
    /// @param proposalId The proposal id
    error PROPOSAL_NOT_QUEUED(bytes32 proposalId);

    /// @dev Reverts if the proposer didn't specify a target address
    error PROPOSAL_TARGET_MISSING();

    /// @dev Reverts if the number of targets, values, and calldatas does not match
    error PROPOSAL_LENGTH_MISMATCH();

    /// @dev Reverts if a proposal didn't succeed
    error PROPOSAL_UNSUCCESSFUL();

    /// @dev Reverts if a proposal was already executed
    error PROPOSAL_ALREADY_EXECUTED();

    /// @dev Reverts if a proposal is in a terminal state and cannot be canceled
    error PROPOSAL_IN_TERMINAL_STATE();

    /// @dev Reverts if a specified proposal doesn't exist
    error PROPOSAL_DOES_NOT_EXIST();

    /// @dev Reverts if the proposer's voting weight is below the proposal threshold
    error BELOW_PROPOSAL_THRESHOLD();

    /// @dev Reverts if a vote was prematurely cast
    error VOTING_NOT_STARTED();

    /// @dev Reverts if the caller wasn't the vetoer
    error ONLY_VETOER();

    /// @dev Reverts if the caller already voted
    error ALREADY_VOTED();

    /// @dev Reverts if a proposal was attempted to be canceled incorrectly
    error INVALID_CANCEL();

    /// @dev Reverts if a vote was attempted to be cast incorrectly
    error INVALID_VOTE();

    /// @dev Reverts if a proposal was attempted to be created before expiration or all tokens have been claimed
    error WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION();

    /// @dev Reverts if governance cannot be delayed
    error CANNOT_DELAY_GOVERNANCE();

    /// @dev Reverts if the caller was not the token owner
    error ONLY_TOKEN_OWNER();

    /// @dev Reverts if the caller was not the contract manager
    error ONLY_MANAGER();

    error INVALID_PROPOSAL_UPDATABLE_PERIOD();

    error CAN_ONLY_EDIT_UPDATABLE_PROPOSALS();

    error ONLY_PROPOSER_CAN_EDIT();

    error MUST_PROVIDE_SIGNATURES();

    error TOO_MANY_SIGNERS();

    error VOTES_BELOW_PROPOSAL_THRESHOLD();

    error INVALID_SIGNATURE_ORDER();

    error INVALID_SIGNATURE_NONCE();

    error PROPOSER_CANNOT_BE_SIGNER();

    error SIGNED_PROPOSAL_MUST_USE_SIGNATURES();

    error NO_OP_PROPOSAL_UPDATE();

    ///                                                          ///
    ///                          FUNCTIONS                       ///
    ///                                                          ///

    /// @notice Initializes a DAO's governor
    /// @param treasury The DAO's treasury address
    /// @param token The DAO's governance token address
    /// @param vetoer The address eligible to veto proposals
    /// @param votingDelay The voting delay
    /// @param votingPeriod The voting period
    /// @param proposalThresholdBps The proposal threshold basis points
    /// @param quorumThresholdBps The quorum threshold basis points
    function initialize(
        address treasury,
        address token,
        address vetoer,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 proposalThresholdBps,
        uint256 quorumThresholdBps
    ) external;

    /// @notice Creates a proposal
    /// @param targets The target addresses to call
    /// @param values The ETH values of each call
    /// @param calldatas The calldata of each call
    /// @param description The proposal description
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
        external
        returns (bytes32);

    /// @notice Creates a proposal from msg.sender backed by offchain signer sponsorships
    /// @param proposerSignatures The proposer signatures
    /// @param targets The target addresses to call
    /// @param values The ETH values of each call
    /// @param calldatas The calldata of each call
    /// @param description The proposal description
    function proposeBySigs(
        ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (bytes32);

    /// @notice Updates an existing proposal during updatable period
    /// @param proposalId The proposal ID to update
    /// @param targets The target addresses to call
    /// @param values The ETH values of each call
    /// @param calldatas The calldata of each call
    /// @param description The proposal description
    /// @param updateMessage The update message
    function updateProposal(
        bytes32 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external returns (bytes32);

    /// @notice Updates a signed proposal with signer approvals
    /// @param proposalId The proposal ID to update
    /// @param proposerSignatures The proposer signatures
    /// @param targets The target addresses to call
    /// @param values The ETH values of each call
    /// @param calldatas The calldata of each call
    /// @param description The proposal description
    /// @param updateMessage The update message
    function updateProposalBySigs(
        bytes32 proposalId,
        ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external returns (bytes32);

    /// @notice Casts a vote
    /// @param proposalId The proposal id
    /// @param support The support value (0 = Against, 1 = For, 2 = Abstain)
    function castVote(bytes32 proposalId, uint256 support) external returns (uint256);

    /// @notice Casts a vote with a reason
    /// @param proposalId The proposal id
    /// @param support The support value (0 = Against, 1 = For, 2 = Abstain)
    /// @param reason The vote reason
    function castVoteWithReason(bytes32 proposalId, uint256 support, string memory reason) external returns (uint256);

    /// @notice Casts a signed vote
    /// @param voter The voter address
    /// @param proposalId The proposal id
    /// @param support The support value (0 = Against, 1 = For, 2 = Abstain)
    /// @param nonce The expected vote signature nonce
    /// @param deadline The signature deadline
    /// @param sig The EIP-712 signature bytes
    function castVoteBySig(address voter, bytes32 proposalId, uint256 support, uint256 nonce, uint256 deadline, bytes calldata sig)
        external
        returns (uint256);

    /// @notice Queues a proposal
    /// @param proposalId The proposal id
    /// @return eta The execution timestamp
    function queue(bytes32 proposalId) external returns (uint256 eta);

    /// @notice Executes a proposal
    /// @param targets The target addresses to call
    /// @param values The ETH values of each call
    /// @param calldatas The calldata of each call
    /// @param descriptionHash The hash of the description
    /// @param proposer The proposal creator
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, address proposer)
        external
        payable
        returns (bytes32);

    /// @notice Cancels a proposal
    /// @param proposalId The proposal id
    function cancel(bytes32 proposalId) external;

    /// @notice Vetoes a proposal
    /// @param proposalId The proposal id
    function veto(bytes32 proposalId) external;

    /// @notice The state of a proposal
    /// @param proposalId The proposal id
    function state(bytes32 proposalId) external view returns (ProposalState);

    /// @notice The voting weight of an account at a timestamp
    /// @param account The account address
    /// @param timestamp The specific timestamp
    function getVotes(address account, uint256 timestamp) external view returns (uint256);

    /// @notice The current number of votes required to submit a proposal
    function proposalThreshold() external view returns (uint256);

    /// @notice The current number of votes required to be in favor of a proposal in order to reach quorum
    function quorum() external view returns (uint256);

    /// @notice The details of a proposal
    /// @param proposalId The proposal id
    function getProposal(bytes32 proposalId) external view returns (Proposal memory);

    /// @notice The signers that sponsored a signed proposal
    /// @param proposalId The proposal id
    function getProposalSigners(bytes32 proposalId) external view returns (address[] memory);

    /// @notice The timestamp until which proposal updates are allowed
    /// @param proposalId The proposal id
    function proposalUpdatePeriodEnd(bytes32 proposalId) external view returns (uint256);

    /// @notice The timestamp when voting starts for a proposal
    /// @param proposalId The proposal id
    function proposalSnapshot(bytes32 proposalId) external view returns (uint256);

    /// @notice The timestamp when voting ends for a proposal
    /// @param proposalId The proposal id
    function proposalDeadline(bytes32 proposalId) external view returns (uint256);

    /// @notice The vote counts for a proposal
    /// @param proposalId The proposal id
    /// @return againstVotes The number of votes against
    /// @return forVotes The number of votes for
    /// @return abstainVotes The number of abstain votes
    function proposalVotes(bytes32 proposalId) external view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);

    /// @notice The timestamp valid to execute a proposal
    /// @param proposalId The proposal id
    function proposalEta(bytes32 proposalId) external view returns (uint256);

    /// @notice The minimum basis points of the total token supply required to submit a proposal
    function proposalThresholdBps() external view returns (uint256);

    /// @notice The minimum basis points of the total token supply required to reach quorum
    function quorumThresholdBps() external view returns (uint256);

    /// @notice The amount of time until voting begins after a proposal is created
    function votingDelay() external view returns (uint256);

    /// @notice The amount of time to vote on a proposal
    function votingPeriod() external view returns (uint256);

    /// @notice The amount of time a proposal is editable after creation
    function proposalUpdatablePeriod() external view returns (uint256);

    /// @notice The current proposal-signature nonce for an account
    /// @param account The signer address
    function proposeSignatureNonce(address account) external view returns (uint256);

    /// @notice The address eligible to veto any proposal (address(0) if burned)
    function vetoer() external view returns (address);

    /// @notice The address of the governance token
    function token() external view returns (address);

    /// @notice The address of the DAO treasury
    function treasury() external view returns (address);

    /// @notice Updates the voting delay
    /// @param newVotingDelay The new voting delay
    function updateVotingDelay(uint256 newVotingDelay) external;

    /// @notice Updates the voting period
    /// @param newVotingPeriod The new voting period
    function updateVotingPeriod(uint256 newVotingPeriod) external;

    /// @notice Updates the proposal updatable period
    /// @param newProposalUpdatablePeriod The new proposal updatable period
    function updateProposalUpdatablePeriod(uint256 newProposalUpdatablePeriod) external;

    /// @notice Updates the minimum proposal threshold
    /// @param newProposalThresholdBps The new proposal threshold basis points
    function updateProposalThresholdBps(uint256 newProposalThresholdBps) external;

    /// @notice Updates the minimum quorum threshold
    /// @param newQuorumVotesBps The new quorum votes basis points
    function updateQuorumThresholdBps(uint256 newQuorumVotesBps) external;

    /// @notice Updates the delayed governance expiration timestamp
    /// @param _newDelayedTimestamp The new delayed governance expiration timestamp
    function updateDelayedGovernanceExpirationTimestamp(uint256 _newDelayedTimestamp) external;

    /// @notice Updates the vetoer
    /// @param newVetoer The new vetoer address
    function updateVetoer(address newVetoer) external;

    /// @notice Burns the vetoer
    function burnVetoer() external;

    /// @notice The EIP-712 typehash to vote with a signature
    function VOTE_TYPEHASH() external view returns (bytes32);
}
