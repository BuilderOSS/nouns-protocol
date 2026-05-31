// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { UUPS } from "../../../src/lib/proxy/UUPS.sol";
import { Ownable } from "../../../src/lib/utils/Ownable.sol";
import { EIP712 } from "../../../src/lib/utils/EIP712.sol";
import { SafeCast } from "../../../src/lib/utils/SafeCast.sol";

import { GovernorStorageV1 } from "../../../src/governance/governor/storage/GovernorStorageV1.sol";
import { GovernorStorageV2 } from "../../../src/governance/governor/storage/GovernorStorageV2.sol";
import { Token } from "../../../src/token/Token.sol";
import { Treasury } from "../../../src/governance/treasury/Treasury.sol";
import { IManager } from "../../../src/manager/IManager.sol";
import { ProposalHasher } from "../../../src/governance/governor/ProposalHasher.sol";

/// @notice Test-only Governor fixture matching the pre-updatable-proposals storage shape.
contract LegacyGovernorV2 is UUPS, Ownable, EIP712, ProposalHasher, GovernorStorageV1, GovernorStorageV2 {
    event ProposalCreated(
        bytes32 proposalId, address[] targets, uint256[] values, bytes[] calldatas, string description, bytes32 descriptionHash, Proposal proposal
    );
    event VoteCast(address voter, bytes32 proposalId, uint256 support, uint256 weight, string reason);

    error ALREADY_VOTED();
    error BELOW_PROPOSAL_THRESHOLD();
    error INVALID_PROPOSAL_THRESHOLD_BPS();
    error INVALID_QUORUM_THRESHOLD_BPS();
    error INVALID_VOTE();
    error INVALID_VOTING_DELAY();
    error INVALID_VOTING_PERIOD();
    error ONLY_MANAGER();
    error PROPOSAL_DOES_NOT_EXIST();
    error PROPOSAL_EXISTS(bytes32 proposalId);
    error PROPOSAL_LENGTH_MISMATCH();
    error PROPOSAL_TARGET_MISSING();
    error VOTING_NOT_STARTED();
    error WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION();

    uint256 public immutable MIN_PROPOSAL_THRESHOLD_BPS = 1;
    uint256 public immutable MAX_PROPOSAL_THRESHOLD_BPS = 1000;
    uint256 public immutable MIN_QUORUM_THRESHOLD_BPS = 200;
    uint256 public immutable MAX_QUORUM_THRESHOLD_BPS = 2000;
    uint256 public immutable MIN_VOTING_DELAY = 1 seconds;
    uint256 public immutable MAX_VOTING_DELAY = 24 weeks;
    uint256 public immutable MIN_VOTING_PERIOD = 10 minutes;
    uint256 public immutable MAX_VOTING_PERIOD = 24 weeks;
    uint256 private immutable BPS_PER_100_PERCENT = 10_000;

    IManager private immutable manager;

    constructor(address _manager) payable initializer {
        manager = IManager(_manager);
    }

    function initialize(
        address _treasury,
        address _token,
        address _vetoer,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThresholdBps,
        uint256 _quorumThresholdBps
    ) external initializer {
        if (msg.sender != address(manager)) revert ONLY_MANAGER();
        if (_treasury == address(0) || _token == address(0)) revert ADDRESS_ZERO();
        if (_vetoer != address(0)) settings.vetoer = _vetoer;
        if (_proposalThresholdBps < MIN_PROPOSAL_THRESHOLD_BPS || _proposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS) {
            revert INVALID_PROPOSAL_THRESHOLD_BPS();
        }
        if (_quorumThresholdBps < MIN_QUORUM_THRESHOLD_BPS || _quorumThresholdBps > MAX_QUORUM_THRESHOLD_BPS) revert INVALID_QUORUM_THRESHOLD_BPS();
        if (_proposalThresholdBps >= _quorumThresholdBps) revert INVALID_PROPOSAL_THRESHOLD_BPS();
        if (_votingDelay < MIN_VOTING_DELAY || _votingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (_votingPeriod < MIN_VOTING_PERIOD || _votingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        settings.treasury = Treasury(payable(_treasury));
        settings.token = Token(_token);
        settings.votingDelay = SafeCast.toUint48(_votingDelay);
        settings.votingPeriod = SafeCast.toUint48(_votingPeriod);
        settings.proposalThresholdBps = SafeCast.toUint16(_proposalThresholdBps);
        settings.quorumThresholdBps = SafeCast.toUint16(_quorumThresholdBps);

        __EIP712_init(string.concat(settings.token.symbol(), " GOV"), "1");
        __Ownable_init(_treasury);
    }

    function propose(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, string memory _description)
        external
        returns (bytes32)
    {
        if (block.timestamp < delayedGovernanceExpirationTimestamp && settings.token.remainingTokensInReserve() > 0) {
            revert WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION();
        }

        uint256 currentProposalThreshold = proposalThreshold();
        if (getVotes(msg.sender, block.timestamp - 1) <= currentProposalThreshold) revert BELOW_PROPOSAL_THRESHOLD();

        uint256 numTargets = _targets.length;
        if (numTargets == 0) revert PROPOSAL_TARGET_MISSING();
        if (numTargets != _values.length || numTargets != _calldatas.length) revert PROPOSAL_LENGTH_MISMATCH();

        bytes32 descriptionHash = keccak256(bytes(_description));
        bytes32 proposalId = hashProposal(_targets, _values, _calldatas, descriptionHash, msg.sender);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.voteStart != 0) revert PROPOSAL_EXISTS(proposalId);

        uint256 snapshot = block.timestamp + settings.votingDelay;
        uint256 deadline = snapshot + settings.votingPeriod;

        proposal.voteStart = SafeCast.toUint32(snapshot);
        proposal.voteEnd = SafeCast.toUint32(deadline);
        proposal.proposalThreshold = SafeCast.toUint32(currentProposalThreshold);
        proposal.quorumVotes = SafeCast.toUint32(quorum());
        proposal.proposer = msg.sender;
        proposal.timeCreated = SafeCast.toUint32(block.timestamp);

        emit ProposalCreated(proposalId, _targets, _values, _calldatas, _description, descriptionHash, proposal);
        return proposalId;
    }

    function castVote(bytes32 _proposalId, uint256 _support) external returns (uint256) {
        return _castVote(_proposalId, msg.sender, _support, "");
    }

    function _castVote(bytes32 _proposalId, address _voter, uint256 _support, string memory _reason) internal returns (uint256) {
        if (state(_proposalId) != ProposalState.Active) revert VOTING_NOT_STARTED();
        if (hasVoted[_proposalId][_voter]) revert ALREADY_VOTED();
        if (_support > 2) revert INVALID_VOTE();

        hasVoted[_proposalId][_voter] = true;
        Proposal storage proposal = proposals[_proposalId];
        uint256 weight = getVotes(_voter, proposal.timeCreated);

        if (_support == 0) proposal.againstVotes += SafeCast.toUint32(weight);
        else if (_support == 1) proposal.forVotes += SafeCast.toUint32(weight);
        else proposal.abstainVotes += SafeCast.toUint32(weight);

        emit VoteCast(_voter, _proposalId, _support, weight, _reason);
        return weight;
    }

    function state(bytes32 _proposalId) public view returns (ProposalState) {
        Proposal memory proposal = proposals[_proposalId];
        if (proposal.voteStart == 0) revert PROPOSAL_DOES_NOT_EXIST();
        if (proposal.executed) return ProposalState.Executed;
        if (proposal.canceled) return ProposalState.Canceled;
        if (proposal.vetoed) return ProposalState.Vetoed;
        if (block.timestamp < proposal.voteStart) return ProposalState.Pending;
        if (block.timestamp < proposal.voteEnd) return ProposalState.Active;
        if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < proposal.quorumVotes) return ProposalState.Defeated;
        if (settings.treasury.timestamp(_proposalId) == 0) return ProposalState.Succeeded;
        if (settings.treasury.isExpired(_proposalId)) return ProposalState.Expired;
        return ProposalState.Queued;
    }

    function getVotes(address _account, uint256 _timestamp) public view returns (uint256) {
        return settings.token.getPastVotes(_account, _timestamp);
    }

    function proposalThreshold() public view returns (uint256) {
        return (settings.token.totalSupply() * settings.proposalThresholdBps) / BPS_PER_100_PERCENT;
    }

    function quorum() public view returns (uint256) {
        return (settings.token.totalSupply() * settings.quorumThresholdBps) / BPS_PER_100_PERCENT;
    }

    function getProposal(bytes32 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    function proposalVotes(bytes32 _proposalId) external view returns (uint256, uint256, uint256) {
        Proposal memory proposal = proposals[_proposalId];
        return (proposal.againstVotes, proposal.forVotes, proposal.abstainVotes);
    }

    function votingDelay() external view returns (uint256) {
        return settings.votingDelay;
    }

    function votingPeriod() external view returns (uint256) {
        return settings.votingPeriod;
    }

    function proposalThresholdBps() external view returns (uint256) {
        return settings.proposalThresholdBps;
    }

    function quorumThresholdBps() external view returns (uint256) {
        return settings.quorumThresholdBps;
    }

    function vetoer() external view returns (address) {
        return settings.vetoer;
    }

    function token() external view returns (address) {
        return address(settings.token);
    }

    function treasury() external view returns (address) {
        return address(settings.treasury);
    }

    function updateProposalThresholdBps(uint256 _newProposalThresholdBps) external onlyOwner {
        if (
            _newProposalThresholdBps < MIN_PROPOSAL_THRESHOLD_BPS || _newProposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS
                || _newProposalThresholdBps >= settings.quorumThresholdBps
        ) revert INVALID_PROPOSAL_THRESHOLD_BPS();
        settings.proposalThresholdBps = uint16(_newProposalThresholdBps);
    }

    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {
        if (!manager.isRegisteredUpgrade(_getImplementation(), _newImpl)) revert INVALID_UPGRADE(_newImpl);
    }
}
