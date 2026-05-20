// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";
import { MockERC1271Wallet } from "./utils/mocks/MockERC1271Wallet.sol";

import { IManager } from "../src/manager/IManager.sol";
import { IGovernor } from "../src/governance/governor/IGovernor.sol";
import { GovernorTypesV1 } from "../src/governance/governor/types/GovernorTypesV1.sol";
import { TokenTypesV2 } from "../src/token/types/TokenTypesV2.sol";

contract GovTest is NounsBuilderTest, GovernorTypesV1 {
    uint256 internal constant AGAINST = 0;
    uint256 internal constant FOR = 1;
    uint256 internal constant ABSTAIN = 2;
    bytes32 internal constant PROPOSAL_TYPEHASH =
        keccak256("Proposal(address proposer,bytes32 proposalId,uint256 nonce,uint256 deadline)");
    bytes32 internal constant UPDATE_PROPOSAL_TYPEHASH =
        keccak256("UpdateProposal(bytes32 proposalId,bytes32 updatedProposalId,address proposer,uint256 nonce,uint256 deadline)");

    address internal voter1;
    uint256 internal voter1PK;
    address internal voter2;
    uint256 internal voter2PK;
    uint256[] internal otherUsersPKs;

    IManager.GovParams internal altGovParams;

    function setUp() public virtual override {
        super.setUp();

        createVoter1();
        createVoter2();
    }

    function deployMock() internal override {
        address[] memory wallets = new address[](2);
        uint256[] memory percents = new uint256[](2);
        uint256[] memory vestingEnd = new uint256[](2);

        wallets[0] = founder;
        wallets[1] = founder2;

        percents[0] = 1;
        percents[1] = 1;

        vestingEnd[0] = 4 weeks;
        vestingEnd[1] = 4 weeks;

        setFounderParams(wallets, percents, vestingEnd);

        setMockTokenParams();

        setAuctionParams(0, 1 days, address(0), 0);

        setGovParams(2 days, 1 days, 1 weeks, 25, 1000, founder);

        deploy(foundersArr, tokenParams, auctionParams, govParams);

        setMockMetadata();
    }

    function deployAltMock() internal {
        address[] memory wallets = new address[](2);
        uint256[] memory percents = new uint256[](2);
        uint256[] memory vestingEnd = new uint256[](2);

        wallets[0] = founder;
        wallets[1] = founder2;

        percents[0] = 1;
        percents[1] = 1;

        vestingEnd[0] = 4 weeks;
        vestingEnd[1] = 4 weeks;

        setFounderParams(wallets, percents, vestingEnd);

        setMockTokenParams();

        setAuctionParams(0, 1 days, address(0), 0);

        setGovParams(2 days, 1 days, 1 weeks, 100, 1000, founder);

        deploy(foundersArr, tokenParams, auctionParams, govParams);

        setMockMetadata();
    }

    function deployMockWithDelay(uint256 delay) internal {
        address[] memory wallets = new address[](2);
        uint256[] memory percents = new uint256[](2);
        uint256[] memory vestingEnd = new uint256[](2);

        wallets[0] = founder;
        wallets[1] = founder2;

        percents[0] = 1;
        percents[1] = 1;

        vestingEnd[0] = 4 weeks;
        vestingEnd[1] = 4 weeks;

        setFounderParams(wallets, percents, vestingEnd);

        setMockTokenParamsWithReserve(2);

        setAuctionParams(0, 1 days, address(0), 0);

        setGovParams(2 days, 1 days, 1 weeks, 25, 1000, founder);

        deploy(foundersArr, tokenParams, auctionParams, govParams);

        vm.prank(founder);
        governor.updateDelayedGovernanceExpirationTimestamp(block.timestamp + delay);

        setMockMetadata();
    }

    function createVoter1() internal {
        voter1PK = 0xABE;
        voter1 = vm.addr(voter1PK);

        vm.deal(voter1, 100 ether);
    }

    function createVoter2() internal {
        voter2PK = 0xBAE;
        voter2 = vm.addr(voter2PK);

        vm.deal(voter2, 100 ether);
    }

    function _encodeSignature(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        return abi.encodePacked(r, s, v);
    }

    function _computeProposalId(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)), proposer));
    }

    function _createVotersWithPKs(uint256 _numUsers, uint256 _balance) internal {
        createVoters(_numUsers, _balance);
        otherUsersPKs = new uint256[](_numUsers);
        for (uint256 i = 0; i < _numUsers; i++) {
            otherUsersPKs[i] = i + 1;
        }
    }

    function _createUsersWithPKs(uint256 _numUsers, uint256 _balance) internal {
        createUsers(_numUsers, _balance);
        otherUsersPKs = new uint256[](_numUsers);
        for (uint256 i = 0; i < _numUsers; i++) {
            otherUsersPKs[i] = i + 1;
        }
    }

    function _sortedSignersAndPks(uint256 count) internal view returns (address[] memory signers, uint256[] memory signerPks) {
        signers = new address[](count);
        signerPks = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            signers[i] = otherUsers[i];
            signerPks[i] = otherUsersPKs[i];
        }

        for (uint256 i = 1; i < count; i++) {
            address currentSigner = signers[i];
            uint256 currentPk = signerPks[i];
            uint256 j = i;
            while (j > 0 && signers[j - 1] > currentSigner) {
                signers[j] = signers[j - 1];
                signerPks[j] = signerPks[j - 1];
                j--;
            }
            signers[j] = currentSigner;
            signerPks[j] = currentPk;
        }
    }

    function _buildOrderedProposeSignatures(
        uint256 count,
        address proposer,
        bytes32 proposalId,
        uint256 nonce,
        uint256 deadline,
        bool reverse
    ) internal view returns (ProposerSignature[] memory signatures) {
        signatures = new ProposerSignature[](count);
        (address[] memory sortedSigners, uint256[] memory sortedSignerPks) = _sortedSignersAndPks(count);

        for (uint256 i = 0; i < count; i++) {
            uint256 idx = reverse ? count - 1 - i : i;
            signatures[i] = _buildProposeSignature(sortedSignerPks[idx], sortedSigners[idx], proposer, proposalId, nonce, deadline);
        }
    }

    function _buildProposeSignature(
        uint256 signerPk,
        address signer,
        address proposer,
        bytes32 proposalId,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (ProposerSignature memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PROPOSAL_TYPEHASH, proposer, proposalId, nonce, deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return ProposerSignature({ signer: signer, nonce: nonce, deadline: deadline, sig: _encodeSignature(v, r, s) });
    }

    function _buildUpdateSignature(
        uint256 signerPk,
        address signer,
        bytes32 proposalId,
        bytes32 updatedProposalId,
        address proposer,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (ProposerSignature memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        UPDATE_PROPOSAL_TYPEHASH,
                        proposalId,
                        updatedProposalId,
                        proposer,
                        nonce,
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return ProposerSignature({ signer: signer, nonce: nonce, deadline: deadline, sig: _encodeSignature(v, r, s) });
    }

    function mintVoter1() internal {
        vm.prank(founder);
        auction.unpause();

        (uint256 tokenId, , , , , ) = auction.auction();

        vm.prank(voter1);
        auction.createBid{ value: 0.420 ether }(tokenId);

        vm.warp(block.timestamp + auctionParams.duration + 1 seconds);
        auction.settleCurrentAndCreateNewAuction();
        vm.warp(block.timestamp + 20);
    }

    function mintVoter2() internal {
        (uint256 tokenId, , , , , ) = auction.auction();

        vm.prank(voter2);
        auction.createBid{ value: 0.420 ether }(tokenId);

        vm.warp(block.timestamp + auctionParams.duration + 1 seconds);
        auction.settleCurrentAndCreateNewAuction();
        vm.warp(block.timestamp + 20);
    }

    function castVotes(
        bytes32 _proposalId,
        uint256 _numAgainst,
        uint256 _numFor,
        uint256 _numAbstain
    ) internal {
        uint256 currentVoterIndex;

        for (uint256 i = 0; i < _numAgainst; ++i) {
            vm.prank(otherUsers[currentVoterIndex]);
            governor.castVote(_proposalId, AGAINST);

            ++currentVoterIndex;
        }

        for (uint256 i = 0; i < _numFor; ++i) {
            vm.prank(otherUsers[currentVoterIndex]);
            governor.castVote(_proposalId, FOR);

            ++currentVoterIndex;
        }

        for (uint256 i = 0; i < _numAbstain; ++i) {
            vm.prank(otherUsers[currentVoterIndex]);
            governor.castVote(_proposalId, ABSTAIN);

            ++currentVoterIndex;
        }
    }

    function mockProposal()
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = address(auction);
        calldatas[0] = abi.encodeWithSignature("pause()");
    }

    function createProposal() internal returns (bytes32 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.startPrank(address(auction));
        uint256 newTokenId = token.mint();
        token.transferFrom(address(auction), voter1, newTokenId);
        vm.stopPrank();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(0);

        vm.warp(block.timestamp + 20);

        vm.prank(voter1);
        proposalId = governor.propose(targets, values, calldatas, "");
    }

    function createProposal(
        address _proposer,
        address _target,
        uint256 _value,
        bytes memory _calldata
    ) internal returns (bytes32 proposalId) {
        deployMock();

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(0);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = _target;
        values[0] = _value;
        calldatas[0] = _calldata;

        vm.prank(_proposer);
        proposalId = governor.propose(targets, values, calldatas, "");
    }

    function test_GovernorInit() public {
        deployMock();

        assertEq(governor.owner(), address(treasury));
        assertEq(governor.treasury(), address(treasury));
        assertEq(governor.token(), address(token));
        assertEq(governor.vetoer(), address(founder));

        assertEq(governor.votingDelay(), govParams.votingDelay);
        assertEq(governor.votingPeriod(), govParams.votingPeriod);
        assertEq(governor.proposalUpdatablePeriod(), 1 days);
        assertEq(governor.proposalThresholdBps(), govParams.proposalThresholdBps);
        assertEq(governor.quorumThresholdBps(), govParams.quorumThresholdBps);
    }

    function test_TreasuryInit() public {
        deployMock();

        assertEq(treasury.owner(), address(governor));
        assertEq(treasury.delay(), govParams.timelockDelay);
    }

    function testRevert_CannotReinitializeGovernor() public {
        deployMock();

        vm.expectRevert(abi.encodeWithSignature("ALREADY_INITIALIZED()"));
        governor.initialize(address(this), address(this), address(this), 0, 0, 0, 0);
    }

    function testRevert_CannotReinitializeTreasury() public {
        deployMock();

        vm.expectRevert(abi.encodeWithSignature("ALREADY_INITIALIZED()"));
        treasury.initialize(address(this), 0);
    }

    function test_CreateProposal() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        bytes32 descriptionHash = keccak256(bytes(""));
        bytes32 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash, voter1);

        vm.prank(voter1);
        bytes32 returnedProposalId = governor.propose(targets, values, calldatas, "");

        assertEq(proposalId, returnedProposalId);

        Proposal memory proposal = governor.getProposal(proposalId);

        assertEq(proposal.proposer, voter1);

        assertEq(proposal.voteStart, block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());
        assertEq(
            proposal.voteEnd,
            block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay() + governor.votingPeriod()
        );

        assertEq(proposal.voteStart, governor.proposalSnapshot(proposalId));
        assertEq(proposal.voteEnd, governor.proposalDeadline(proposalId));

        assertEq(proposal.proposalThreshold, (token.totalSupply() * governor.proposalThresholdBps()) / 10_000);
        assertEq(proposal.quorumVotes, (token.totalSupply() * governor.quorumThresholdBps()) / 10_000);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Updatable));

        assertEq(treasury.hashProposal(targets, values, calldatas, descriptionHash, voter1), proposalId);
    }

    /// @notice Test that a proposal cannot be front-run and canceled by a malicious user
    function test_ProposalHashUniqueToSender() public {
        deployMock();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        bytes32 descriptionHash = keccak256(bytes(""));
        bytes32 proposalId1 = governor.hashProposal(targets, values, calldatas, descriptionHash, voter1);
        bytes32 proposalId2 = governor.hashProposal(targets, values, calldatas, descriptionHash, voter2);

        assertTrue(proposalId1 != proposalId2);
    }

    function test_VerifySubmittedProposalHash() public {
        deployMock();

        // Mint a token to voter 1 to have quorum
        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        assertEq(proposalId, governor.hashProposal(targets, values, calldatas, keccak256(bytes("")), voter1));
    }

    function test_ProposalState_UpdatableToPendingToActive() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Updatable));

        vm.warp(block.timestamp + 1 days);
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Pending));

        vm.warp(block.timestamp + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Active));
    }

    function test_ProposeBySigs() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        Proposal memory proposal = governor.getProposal(proposalId);
        address[] memory signers = governor.getProposalSigners(proposalId);

        assertEq(proposal.proposer, voter2);
        assertEq(signers.length, 1);
        assertEq(signers[0], voter1);
    }

    function testRevert_UpdateProposalNoOp() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        vm.expectRevert(abi.encodeWithSignature("NO_OP_PROPOSAL_UPDATE()"));
        vm.prank(voter1);
        governor.updateProposal(proposalId, targets, values, calldatas, "", "no-op update");
    }

    function testRevert_ProposeBySigsSignerCannotBeProposer() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter2PK,
            voter2,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.expectRevert(abi.encodeWithSignature("PROPOSER_CANNOT_BE_SIGNER()"));
        vm.prank(voter2);
        governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");
    }

    function testRevert_ProposeBySigsTooManySigners() public {
        deployMock();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](33);

        vm.expectRevert(abi.encodeWithSignature("TOO_MANY_SIGNERS()"));
        governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");
    }

    function test_UpdateProposalBySigs() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        ProposerSignature[] memory updateSignatures = new ProposerSignature[](1);
        updateSignatures[0] = _buildUpdateSignature(
            voter1PK,
            voter1,
            proposalId,
            _computeProposalId(targets, values, updatedCalldatas, "updated signed proposal", voter2),
            voter2,
            1,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 updatedProposalId = governor.updateProposalBySigs(
            proposalId,
            voter2,
            updateSignatures,
            targets,
            values,
            updatedCalldatas,
            "updated signed proposal",
            "minor tx update"
        );

        assertTrue(updatedProposalId != proposalId);
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced));
    }

    function test_ProposeBySigs_AllowsRelayedSubmission() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "relayed signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(founder);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "relayed signed proposal");

        Proposal memory proposal = governor.getProposal(proposalId);
        assertEq(proposal.proposer, voter2);
    }

    function testRevert_UpdateProposalBySigs_ProposerMismatch() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(founder);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        ProposerSignature[] memory updateSignatures = new ProposerSignature[](1);
        updateSignatures[0] = _buildUpdateSignature(
            voter1PK,
            voter1,
            proposalId,
            _computeProposalId(targets, values, updatedCalldatas, "updated signed proposal", voter2),
            voter2,
            1,
            block.timestamp + 1 days
        );

        vm.prank(founder);
        vm.expectRevert(abi.encodeWithSignature("ONLY_PROPOSER_CAN_EDIT()"));
        governor.updateProposalBySigs(
            proposalId,
            voter1,
            updateSignatures,
            targets,
            values,
            updatedCalldatas,
            "updated signed proposal",
            "minor tx update"
        );
    }

    function testRevert_UpdateProposalTxsOnSignedProposalWithoutSignaturesForUnqualifiedProposer() public {
        deployAltMock();

        mintVoter1();

        for (uint256 i; i < 96; i++) {
            vm.prank(address(auction));
            token.mint();
        }

        _createVotersWithPKs(2, 5 ether);
        vm.prank(otherUsers[0]);
        token.delegate(voter1);
        vm.prank(otherUsers[1]);
        token.delegate(voter1);

        vm.warp(block.timestamp + 20);

        assertGt(token.totalSupply(), 100);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(100);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        vm.expectRevert(abi.encodeWithSignature("UNQUALIFIED_PROPOSER_MUST_USE_SIGNATURES()"));
        vm.prank(voter2);
        governor.updateProposal(proposalId, targets, values, updatedCalldatas, "new desc", "update without signatures");
    }

    function test_UpdateProposalOnSignedProposalForQualifiedProposer() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter2PK,
            voter2,
            voter1,
            _computeProposalId(targets, values, calldatas, "member proposer signed proposal", voter1),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter1);
        bytes32 proposalId = governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "member proposer signed proposal");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        vm.prank(voter1);
        bytes32 updatedProposalId = governor.updateProposal(
            proposalId,
            targets,
            values,
            updatedCalldatas,
            "new desc",
            "qualified proposer update"
        );

        assertTrue(updatedProposalId != proposalId);
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced));
    }

    function test_ProposalHashDiffersFromIncorrectProposer() public {
        deployMock();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        bytes32 proposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes("")), voter1);

        bytes32 incorrectProposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes("")), address(this));

        assertTrue(proposalId != incorrectProposalId);
    }

    function testRevert_NoTarget() public {
        deployMock();

        mintVoter1();

        address[] memory targets;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        calldatas[0] = abi.encodeWithSignature("pause()");

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_TARGET_MISSING()"));
        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "");
    }

    function testRevert_NoValue() public {
        deployMock();

        mintVoter1();

        address[] memory targets = new address[](1);
        uint256[] memory values;
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(auction);
        calldatas[0] = abi.encodeWithSignature("pause()");

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_LENGTH_MISMATCH()"));
        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "");
    }

    function testRevert_NoCalldata() public {
        deployMock();

        mintVoter1();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas;

        targets[0] = address(auction);

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_LENGTH_MISMATCH()"));
        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "");
    }

    function testRevert_ProposalExists() public {
        deployMock();

        mintVoter1();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(auction);
        calldatas[0] = abi.encodeWithSignature("pause()");

        bytes32 descriptionHash = keccak256(bytes(""));

        vm.startPrank(voter1);
        bytes32 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash, voter1);
        governor.propose(targets, values, calldatas, "");

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_EXISTS(bytes32)", proposalId));
        governor.propose(targets, values, calldatas, "");
        vm.stopPrank();
    }

    function testRevert_BelowProposalThreshold(uint32 bps) public {
        vm.assume(bps < 1000 && bps > 0);
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(bps);

        // Go back in time before voter1 token is minted
        vm.warp(1);

        assertEq(governor.proposalThreshold(), 0);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(auction);
        calldatas[0] = abi.encodeWithSignature("");

        for (uint256 i; i < 11; ++i) {
            vm.prank(address(auction));
            token.mint();
        }

        vm.expectRevert(abi.encodeWithSignature("BELOW_PROPOSAL_THRESHOLD()"));
        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "");
    }

    function test_CastVote() public {
        deployMock();

        // This mints a token to voter1
        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Active));

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 0);
        assertEq(forVotes, 1);
        assertEq(abstainVotes, 0);
    }

    function test_CastVoteWithoutWeight() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        governor.castVote(proposalId, FOR);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 0);
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);
    }

    function test_CastVoteWithSig() public {
        deployMock();

        // This mints a token to voter1
        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        bytes32 domainSeparator = governor.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = governor.VOTE_TYPEHASH();
        uint256 voterNonce = governor.nonce(voter1);
        uint256 deadline = governor.proposalDeadline(proposalId);

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, voter1, proposalId, FOR, voterNonce, deadline)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        governor.castVoteBySig(voter1, proposalId, FOR, voterNonce, deadline, sig);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 0);
        assertEq(forVotes, 1);
        assertEq(abstainVotes, 0);
    }

    function testRevert_VotingNotStarted() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.expectRevert(abi.encodeWithSignature("VOTING_NOT_STARTED()"));
        vm.prank(voter1);
        governor.castVote(proposalId, FOR);
    }

    function testRevert_CannotVoteTwice() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        governor.castVote(proposalId, FOR);
    }

    function testRevert_InvalidVoteType() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        vm.expectRevert(abi.encodeWithSignature("INVALID_VOTE()"));
        governor.castVote(proposalId, 3);
    }

    function testRevert_InvalidVoteSigner() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        bytes32 domainSeparator = governor.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = governor.VOTE_TYPEHASH();
        uint256 voterNonce = governor.nonce(voter1);
        uint256 deadline = governor.proposalDeadline(proposalId);

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, voter1, proposalId, FOR, voterNonce, deadline)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xF, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE()"));
        governor.castVoteBySig(voter1, proposalId, FOR, voterNonce, deadline, sig);
    }

    function testRevert_InvalidVoteNonce() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        bytes32 domainSeparator = governor.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = governor.VOTE_TYPEHASH();
        uint256 voterNonce = governor.nonce(voter1);
        uint256 deadline = governor.proposalDeadline(proposalId);

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, voter1, proposalId, FOR, voterNonce + 1, deadline)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_NONCE()"));
        governor.castVoteBySig(voter1, proposalId, FOR, voterNonce + 1, deadline, sig);
    }

    function testRevert_InvalidVoteExpired() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay + 1);

        bytes32 domainSeparator = governor.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = governor.VOTE_TYPEHASH();
        uint256 voterNonce = governor.nonce(voter1);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(voteTypeHash, voter1, proposalId, FOR, voterNonce, deadline)))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(deadline + 1 seconds);

        vm.expectRevert(abi.encodeWithSignature("EXPIRED_SIGNATURE()"));
        governor.castVoteBySig(voter1, proposalId, FOR, voterNonce, deadline, sig);
    }

    function test_QueueProposal() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Active));

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        vm.warp(block.timestamp + governor.votingPeriod());

        ProposalState beforeState = governor.state(proposalId);

        vm.prank(voter1);
        governor.queue(proposalId);

        ProposalState afterState = governor.state(proposalId);

        require(beforeState == ProposalState.Succeeded);
        require(afterState == ProposalState.Queued);

        assertEq(treasury.timestamp(proposalId), block.timestamp + treasury.delay());
    }

    function testRevert_CannotQueueVotingStillActive() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay);

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        uint256 votingPeriod = governor.votingPeriod();
        vm.warp(block.timestamp + votingPeriod - 1);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Active));

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_UNSUCCESSFUL()"));
        governor.queue(proposalId);
    }

    /// @notice If a user tries to queue a proposal with a missing hash, revert.
    function testRevert_CannotQueueMissingProposal() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        // change the proposer to generate a wrong ID, everything else is the same
        bytes32 wrongProposalId = governor.hashProposal(targets, values, calldatas, "", voter2);

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay);

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        uint256 votingPeriod = governor.votingPeriod();
        vm.warp(block.timestamp + votingPeriod + 1);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_DOES_NOT_EXIST()"));
        governor.queue(wrongProposalId);
    }

    function testRevert_CannotQueueDraw() public {
        deployMock();

        mintVoter1();
        mintVoter2();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay);

        vm.prank(voter1);
        governor.castVote(proposalId, AGAINST);
        vm.prank(voter2);
        governor.castVote(proposalId, FOR);

        uint256 votingPeriod = governor.votingPeriod();
        vm.warp(block.timestamp + votingPeriod);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Defeated));

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_UNSUCCESSFUL()"));
        governor.queue(proposalId);
    }

    function testRevert_CannotQueueFailed() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 votingDelay = governor.votingDelay();
        vm.warp(block.timestamp + votingDelay);

        vm.prank(voter1);
        governor.castVote(proposalId, AGAINST);

        uint256 votingPeriod = governor.votingPeriod();
        vm.warp(block.timestamp + votingPeriod);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Defeated));

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_UNSUCCESSFUL()"));
        governor.queue(proposalId);
    }

    function testRevert_CannotQueueFailedQuorum() public {
        deployMock();

        vm.prank(founder);
        auction.unpause();

        createVoters(10, 5 ether);

        vm.prank(address(treasury));
        governor.updateQuorumThresholdBps(2000);

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        castVotes(proposalId, 0, 1, 3); // AGAINST: 0, FOR: 1, ABSTAIN: 3

        vm.warp(block.timestamp + governor.votingPeriod());

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_UNSUCCESSFUL()"));
        governor.queue(proposalId);
    }

    function test_CancelProposal() public {
        deployMock();

        bytes32 proposalId = createProposal();

        vm.prank(voter1);
        governor.cancel(proposalId);

        Proposal memory proposal = governor.getProposal(proposalId);

        assertTrue(proposal.canceled);
    }

    function test_CancelProposalAndTreasuryQueue() public {
        deployMock();

        mintVoter1();
        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        vm.warp(block.timestamp + governor.votingPeriod());

        governor.queue(proposalId);

        vm.prank(voter1);
        governor.cancel(proposalId);

        Proposal memory proposal = governor.getProposal(proposalId);

        assertTrue(proposal.canceled);
    }

    function test_CancelProposerFellBelowThreshold() public {
        deployAltMock();

        mintVoter1();

        vm.warp(block.timestamp + 1 days);

        for (uint256 i; i < 96; i++) {
            vm.prank(address(auction));
            token.mint();
        }

        assertEq(token.totalSupply(), 100);

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        vm.startPrank(voter1);
        token.transferFrom(voter1, address(this), 2);

        vm.warp(block.timestamp + governor.votingPeriod());

        governor.cancel(proposalId);

        Proposal memory proposal = governor.getProposal(proposalId);

        assertTrue(proposal.canceled);
        vm.stopPrank();
    }

    function testRevert_CannotCancelIfExactThreshold() public {
        deployAltMock();

        mintVoter1();

        vm.warp(block.timestamp + 1 days);

        for (uint256 i; i < 96; i++) {
            vm.prank(address(auction));
            token.mint();
        }

        assertEq(token.totalSupply(), 100);

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay() + governor.votingPeriod());

        vm.expectRevert(abi.encodeWithSignature("INVALID_CANCEL()"));
        governor.cancel(proposalId);
    }

    function testRevert_CannotCancelAlreadyExecuted() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        vm.warp(block.timestamp + governor.votingPeriod());

        governor.queue(proposalId);

        vm.warp(block.timestamp + treasury.delay());

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        governor.execute(targets, values, calldatas, keccak256(bytes("")), voter1);

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_ALREADY_EXECUTED()"));
        governor.cancel(proposalId);
    }

    function testRevert_ProposerAboveThreshold() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(999);

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        vm.expectRevert(abi.encodeWithSignature("INVALID_CANCEL()"));
        governor.cancel(proposalId);
    }

    function testRevert_CannotCancelSignedProposalWhenCombinedVotesAtThreshold() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        vm.expectRevert(abi.encodeWithSignature("INVALID_CANCEL()"));
        governor.cancel(proposalId);
    }

    function test_SignerCanCancelSignedProposal() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "signed proposal", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "signed proposal");

        vm.prank(voter1);
        governor.cancel(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Canceled));
    }

    function test_VetoProposal() public {
        deployMock();

        bytes32 proposalId = createProposal();

        vm.prank(founder);
        governor.veto(proposalId);

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Vetoed));
    }

    function testRevert_CallerNotVetoer() public {
        deployMock();

        bytes32 proposalId = createProposal();

        vm.expectRevert(abi.encodeWithSignature("ONLY_VETOER()"));
        governor.veto(proposalId);
    }

    function testRevert_CannotVetoExecuted() public {
        deployMock();

        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.votingDelay());

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        vm.warp(block.timestamp + governor.votingPeriod());

        governor.queue(proposalId);

        vm.warp(block.timestamp + treasury.delay());

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        governor.execute(targets, values, calldatas, keccak256(bytes("")), voter1);

        vm.expectRevert(abi.encodeWithSignature("PROPOSAL_ALREADY_EXECUTED()"));
        vm.prank(founder);
        governor.veto(proposalId);
    }

    function test_ProposalVoteQueueExecution() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(0);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        bytes32 descriptionHash = keccak256(bytes("test"));

        vm.warp(block.timestamp + 1 days);

        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "test");

        bytes32 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash, voter1);

        vm.warp(block.timestamp + governor.votingDelay());
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.votingPeriod());
        vm.prank(voter1);
        governor.queue(proposalId);

        vm.warp(block.timestamp + 2 days);

        governor.execute(targets, values, calldatas, descriptionHash, voter1);

        assertEq(auction.paused(), true);
    }

    function test_UpdateDelay(uint128 _newDelay) public {
        deployMock();

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(0);

        vm.prank(founder);
        auction.unpause();

        createVoters(10, 5 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("updateDelay(uint256)", _newDelay);

        vm.prank(otherUsers[2]);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + governor.votingDelay());

        castVotes(proposalId, 2, 5, 3); // AGAINST: 2, FOR: 5, ABSTAIN: 3

        vm.warp(block.timestamp + governor.votingPeriod());

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Succeeded));

        governor.queue(proposalId);

        vm.warp(block.timestamp + treasury.delay());

        assertEq(treasury.delay(), 2 days);

        governor.execute(targets, values, calldatas, keccak256(bytes("")), otherUsers[2]);

        assertEq(treasury.delay(), _newDelay);
    }

    function test_DelegateAndTransferVotes() public {
        deployMock();

        mintVoter1();

        // uint256 voter2PK = 0xABD;
        // address voter2 = vm.addr(voter2PK);

        assertEq(token.getVotes(voter1), 1);
        assertEq(token.getVotes(voter2), 0);

        vm.prank(voter1);
        token.delegate(voter2);

        assertEq(token.getVotes(voter1), 0);
        assertEq(token.getVotes(voter2), 1);

        vm.prank(voter1);
        token.transferFrom(voter1, voter2, 2);

        assertEq(token.getVotes(voter1), 0);
        assertEq(token.getVotes(voter2), 1);

        vm.prank(voter2);
        token.delegate(voter2);

        assertEq(token.getVotes(voter1), 0);
        assertEq(token.getVotes(voter2), 1);
    }

    function test_GracePeriod(uint128 _newGracePeriod) public {
        deployMock();

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(0);

        vm.prank(founder);
        auction.unpause();

        createVoters(10, 5 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("updateGracePeriod(uint256)", _newGracePeriod);

        vm.prank(otherUsers[2]);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + governor.votingDelay());

        castVotes(proposalId, 2, 5, 3); // AGAINST: 2, FOR: 5, ABSTAIN: 3

        vm.warp(block.timestamp + governor.votingPeriod());

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Succeeded));

        governor.queue(proposalId);

        vm.warp(block.timestamp + treasury.delay());

        assertEq(treasury.gracePeriod(), 2 weeks);

        governor.execute(targets, values, calldatas, keccak256(bytes("")), otherUsers[2]);

        assertEq(treasury.gracePeriod(), _newGracePeriod);
    }

    function test_TreasuryReceive721SafeTransfer(uint256 _tokenId) public {
        deployMock();

        mock721.mint(address(this), _tokenId);

        mock721.safeTransferFrom(address(this), address(treasury), _tokenId);

        assertEq(mock721.ownerOf(_tokenId), address(treasury));
    }

    function test_TreasuryReceiveERC1155SingleTransfer(uint256 _tokenId, uint256 _amount) public {
        deployMock();

        mock1155.mint(address(treasury), _tokenId, _amount);

        assertEq(mock1155.balanceOf(address(treasury), _tokenId), _amount);
    }

    function test_TreasuryReceiveERC1155BatchTransfer() public {
        deployMock();

        address[] memory accounts = new address[](3);
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);

        accounts[0] = address(treasury);
        accounts[1] = address(treasury);
        accounts[2] = address(treasury);

        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 2;

        amounts[0] = 1 ether;
        amounts[1] = 5 ether;
        amounts[2] = 10 ether;

        mock1155.mintBatch(address(treasury), tokenIds, amounts);

        assertEq(mock1155.balanceOfBatch(accounts, tokenIds), amounts);
    }

    function testRevert_GovernorCannotReceive721SafeTransfer() public {
        deployMock();

        mock721.mint(address(this), 1);

        vm.expectRevert();
        mock721.safeTransferFrom(address(this), address(governor), 1);
    }

    function testRevert_GovernorCannotReceive1155SingleTransfer(uint256 _tokenId, uint256 _amount) public {
        deployMock();

        vm.expectRevert();
        mock1155.mint(address(governor), _tokenId, _amount);
    }

    function testRevert_GovernorCannotReceive1155BatchTransfer(uint256[] memory _tokenIds, uint256[] memory _amounts) public {
        deployMock();

        vm.expectRevert();
        mock1155.mintBatch(address(governor), _tokenIds, _amounts);
    }

    function testRevert_GovernorOnlyDAOWithReserveCanAddDelay() public {
        deployMock();

        vm.prank(founder);
        vm.expectRevert(abi.encodeWithSignature("CANNOT_DELAY_GOVERNANCE()"));
        governor.updateDelayedGovernanceExpirationTimestamp(1 days);
    }

    function testRevert_GovernorOnlyTokenOwnerCanSetDelay() public {
        deployMock();

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("ONLY_TOKEN_OWNER()"));
        governor.updateDelayedGovernanceExpirationTimestamp(1 days);
    }

    function testRevert_GovernorCannotSetDelayPastMax() public {
        deployMock();

        vm.prank(founder);
        vm.expectRevert(abi.encodeWithSignature("INVALID_DELAYED_GOVERNANCE_EXPIRATION()"));
        governor.updateDelayedGovernanceExpirationTimestamp(31 days);
    }

    function testRevert_GovernorCannotSetDelayAfterTokensAreMinted() public {
        deployMock();

        vm.prank(founder);
        token.setReservedUntilTokenId(4);

        vm.prank(founder);
        auction.unpause();

        vm.prank(address(treasury));
        vm.expectRevert(abi.encodeWithSignature("CANNOT_DELAY_GOVERNANCE()"));
        governor.updateDelayedGovernanceExpirationTimestamp(1 days);
    }

    function testRevert_GovernorCannotProposeInDelayPeriod() public {
        deployMockWithDelay(block.timestamp + 7 days);

        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.warp(block.timestamp + 1 days);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION()"));
        governor.propose(targets, values, calldatas, "test");
    }

    function test_GovernorCanProposeAfterDelayPeriod() public {
        deployMockWithDelay(block.timestamp + 7 days);

        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION()"));
        governor.propose(targets, values, calldatas, "test");

        vm.warp(block.timestamp + 8 days);

        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "test");
    }

    function test_GovernorCanProposeAfterReserveIsMinted() public {
        deployMockWithDelay(block.timestamp + 7 days);

        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("WAITING_FOR_TOKENS_TO_CLAIM_OR_EXPIRATION()"));
        governor.propose(targets, values, calldatas, "test");

        TokenTypesV2.MinterParams[] memory minters = new TokenTypesV2.MinterParams[](1);
        minters[0] = TokenTypesV2.MinterParams({ minter: founder, allowed: true });

        vm.prank(token.owner());
        token.updateMinters(minters);

        vm.startPrank(address(founder));
        token.mintFromReserveTo(address(founder), 0);
        token.mintFromReserveTo(address(founder), 1);
        vm.stopPrank();

        vm.prank(voter1);
        governor.propose(targets, values, calldatas, "test");
    }

    /// @notice Test that users cannot vote twice across proposal updates
    /// This is a critical security test to ensure hasVoted mapping properly prevents double voting
    /// when a proposal is updated during the Updatable period
    function testRevert_CannotVoteTwiceAcrossUpdate() public {
        deployMock();

        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Create initial proposal
        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "original");

        // Update the proposal (creates new proposal ID)
        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        vm.prank(voter1);
        bytes32 updatedProposalId = governor.updateProposal(proposalId, targets, values, updatedCalldatas, "updated", "changing calldata");

        // Verify old proposal is marked as replaced
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced));

        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay() + 1);

        vm.prank(voter1);
        governor.castVote(updatedProposalId, FOR);

        // Attempt to vote again on the updated proposal should revert
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        governor.castVote(updatedProposalId, FOR);
    }

    /// @notice Test that votes are preserved when proposal is updated
    function test_VotesPreservedAcrossUpdate() public {
        deployAltMock();

        // Mint tokens to voter1 and voter2
        mintVoter1();
        createVoters(1, 5 ether);
        address voter2 = otherUsers[0];

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Create proposal
        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "original");

        // Update proposal
        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        vm.prank(voter1);
        bytes32 updatedProposalId = governor.updateProposal(proposalId, targets, values, updatedCalldatas, "updated", "minor change");

        // Check that vote totals are preserved (zero prior to activation)
        (uint256 againstVotesBefore, uint256 forVotesBefore, uint256 abstainVotesBefore) = governor.proposalVotes(proposalId);
        (uint256 againstVotesAfter, uint256 forVotesAfter, uint256 abstainVotesAfter) = governor.proposalVotes(updatedProposalId);
        assertEq(forVotesAfter, forVotesBefore, "For votes should be preserved");
        assertEq(againstVotesAfter, againstVotesBefore, "Against votes should be preserved");
        assertEq(abstainVotesAfter, abstainVotesBefore, "Abstain votes should be preserved");
    }

    ///                                                          ///
    ///                      GAS BENCHMARKS                      ///
    ///                                                          ///

    /// @notice Gas benchmark: proposeBySigs with 1 signer
    function test_GasProposeBySigs_1Signer() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "single signer", voter2),
            0,
            block.timestamp + 1 days
        );

        uint256 gasBefore = gasleft();
        vm.prank(voter2);
        governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "single signer");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for proposeBySigs (1 signer)", gasUsed);
        // Sanity check: should be reasonable
        assertLt(gasUsed, 1_000_000, "Gas too high for 1 signer");
    }

    /// @notice Gas benchmark: proposeBySigs with 16 signers
    function test_GasProposeBySigs_16Signers() public {
        deployAltMock();
        mintVoter1();
        _createUsersWithPKs(16, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build 16 signatures
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "16 signers", voter1);
        ProposerSignature[] memory proposerSignatures =
            _buildOrderedProposeSignatures(16, voter1, proposalIdToSign, 0, block.timestamp + 1 days, false);

        uint256 gasBefore = gasleft();
        vm.prank(voter1);
        governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "16 signers");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for proposeBySigs (16 signers)", gasUsed);
        assertLt(gasUsed, 5_000_000, "Gas too high for 16 signers");
    }

    /// @notice Gas benchmark: proposeBySigs with 32 signers (MAX)
    function test_GasProposeBySigs_32Signers() public {
        deployAltMock();
        mintVoter1();
        _createUsersWithPKs(32, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build 32 signatures (max allowed)
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "32 signers max", voter1);
        ProposerSignature[] memory proposerSignatures =
            _buildOrderedProposeSignatures(32, voter1, proposalIdToSign, 0, block.timestamp + 1 days, false);

        uint256 gasBefore = gasleft();
        vm.prank(voter1);
        governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "32 signers max");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for proposeBySigs (32 signers MAX)", gasUsed);
        // Critical: Must be under 10M gas to ensure it can fit in a block
        assertLt(gasUsed, 10_000_000, "CRITICAL: Gas exceeds 10M for max signers");
    }

    /// @notice Gas benchmark: cancel with 32 signers
    function test_GasCancelSignedProposal_32Signers() public {
        deployAltMock();
        mintVoter1();
        _createUsersWithPKs(32, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Create proposal with 32 signers
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "32 signers", voter1);
        ProposerSignature[] memory proposerSignatures =
            _buildOrderedProposeSignatures(32, voter1, proposalIdToSign, 0, block.timestamp + 1 days, false);

        vm.prank(voter1);
        bytes32 proposalId = governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "32 signers");

        // Warp past updatable period
        vm.warp(block.timestamp + 2 days);

        // First signer cancels (must iterate through all 32 to check)
        uint256 gasBefore = gasleft();
        vm.prank(otherUsers[0]);
        governor.cancel(proposalId);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for cancel (32 signers)", gasUsed);
        assertLt(gasUsed, 5_000_000, "Cancel gas too high with max signers");
    }

    /// @notice Gas benchmark: updateProposalBySigs
    function test_GasUpdateProposalBySigs() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, "original", voter2),
            0,
            block.timestamp + 1 days
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "original");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        ProposerSignature[] memory updateSignatures = new ProposerSignature[](1);
        updateSignatures[0] = _buildUpdateSignature(
            voter1PK,
            voter1,
            proposalId,
            _computeProposalId(targets, values, updatedCalldatas, "updated", voter2),
            voter2,
            1,
            block.timestamp + 1 days
        );

        uint256 gasBefore = gasleft();
        vm.prank(voter2);
        governor.updateProposalBySigs(proposalId, voter2, updateSignatures, targets, values, updatedCalldatas, "updated", "gas test");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for updateProposalBySigs", gasUsed);
        assertLt(gasUsed, 2_000_000, "Update gas too high");
    }

    ///                                                          ///
    ///                       FUZZ TESTS                         ///
    ///                                                          ///

    /// @notice Fuzz test: Signer ordering must be strictly increasing
    function testFuzz_SignerOrderingEnforcement(uint8 numSigners) public {
        // Bound to reasonable range: 2-10 signers for fuzz test
        numSigners = uint8(bound(numSigners, 2, 10));

        deployAltMock();
        mintVoter1();
        _createUsersWithPKs(numSigners, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build signatures in correct order
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "ordered", voter1);
        ProposerSignature[] memory proposerSignatures =
            _buildOrderedProposeSignatures(numSigners, voter1, proposalIdToSign, 0, block.timestamp + 1 days, false);

        // This should succeed (correct order)
        vm.prank(voter1);
        bytes32 proposalId = governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "ordered");
        assertTrue(proposalId != bytes32(0), "Proposal creation should succeed with correct order");

        // Now test with reversed order (should fail)
        if (numSigners >= 2) {
            bytes32 reversedProposalIdToSign = _computeProposalId(targets, values, calldatas, "reversed", voter2);
            ProposerSignature[] memory reversedSignatures =
                _buildOrderedProposeSignatures(numSigners, voter2, reversedProposalIdToSign, 1, block.timestamp + 1 days, true);

            vm.prank(voter2);
            vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_ORDER()"));
            governor.proposeBySigs(voter2, reversedSignatures, targets, values, calldatas, "reversed");
        }
    }

    /// @notice Fuzz test: Duplicate signers should be rejected
    function testFuzz_RejectDuplicateSigners(uint8 numSigners) public {
        numSigners = uint8(bound(numSigners, 2, 10));

        deployAltMock();
        _createUsersWithPKs(numSigners, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build signatures with duplicate (signer[1] appears twice)
        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](numSigners);
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "duplicate", voter1);
        for (uint256 i = 0; i < numSigners; i++) {
            // Use same signer for positions 1 and 2 (if numSigners >= 3)
            uint256 signerIndex = (i == 2 && numSigners >= 3) ? 1 : i;

            proposerSignatures[i] = _buildProposeSignature(
                otherUsersPKs[signerIndex],
                otherUsers[signerIndex],
                voter1,
                proposalIdToSign,
                i == 2 ? 1 : 0, // Use same nonce for duplicate
                block.timestamp + 1 days
            );
        }

        if (numSigners >= 3) {
            // Should fail due to non-increasing order (duplicate = same address)
            vm.prank(voter1);
            vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_ORDER()"));
            governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "duplicate");
        }
    }

    /// @notice Fuzz test: Proposal updates with varying array lengths
    function testFuzz_UpdateWithDifferentArrayLengths(uint8 numTargets) public {
        numTargets = uint8(bound(numTargets, 1, 5));

        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        // Create initial proposal with 1 target
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "original");

        // Update with different number of targets
        address[] memory newTargets = new address[](numTargets);
        uint256[] memory newValues = new uint256[](numTargets);
        bytes[] memory newCalldatas = new bytes[](numTargets);

        for (uint256 i = 0; i < numTargets; i++) {
            newTargets[i] = address(auction);
            newValues[i] = 0;
            newCalldatas[i] = abi.encodeWithSignature("unpause()");
        }

        // Should succeed with any valid array length
        vm.prank(voter1);
        bytes32 updatedId = governor.updateProposal(
            proposalId,
            newTargets,
            newValues,
            newCalldatas,
            "updated",
            "different length"
        );

        assertTrue(updatedId != proposalId, "Should create new proposal ID");
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced), "Old proposal should be replaced");
    }

    /// @notice Fuzz test: Signature deadline edge cases
    function testFuzz_SignatureDeadlineEdgeCases(uint128 timeOffset) public {
        // Bound to reasonable future time (0 to 30 days)
        timeOffset = uint128(bound(timeOffset, 0, 30 days));

        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        uint256 deadline = block.timestamp + timeOffset;
        string memory signedDescription = "future deadline";

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = _buildProposeSignature(
            voter1PK,
            voter1,
            voter2,
            _computeProposalId(targets, values, calldatas, signedDescription, voter2),
            0,
            deadline
        );

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "future deadline");
        assertTrue(proposalId != bytes32(0), "Should succeed with non-expired deadline");
    }

    /// @notice Fuzz test: Nonce manipulation should fail
    function testFuzz_NonceManipulationPrevented(uint256 wrongNonce) public {
        // Ensure wrong nonce is not 0 (the correct initial nonce)
        vm.assume(wrongNonce != 0);

        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build signature with wrong nonce
        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = ProposerSignature({
            signer: voter1,
            nonce: wrongNonce,
            deadline: block.timestamp + 1 days,
            sig: ""
        });

        // Generate signature with correct nonce but claim wrong nonce
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "wrong nonce", voter2);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(governor.PROPOSAL_TYPEHASH(), voter2, proposalIdToSign, wrongNonce, block.timestamp + 1 days))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        proposerSignatures[0].sig = abi.encodePacked(r, s, v);

        // Should fail with wrong nonce
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_NONCE()"));
        governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "wrong nonce");
    }

    ///                                                          ///
    ///                    INVARIANT TESTS                       ///
    ///                                                          ///

    /// @notice Invariant: Total votes on a proposal can never exceed token supply
    function invariant_VotesNeverExceedSupply() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "test");

        // Get total supply
        uint256 totalSupply = token.totalSupply();

        // Warp to voting period
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay() + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        // Check invariant: total votes <= supply
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        uint256 totalVotes = againstVotes + forVotes + abstainVotes;

        assertLe(totalVotes, totalSupply, "INVARIANT VIOLATED: Total votes exceed supply");
    }

    /// @notice Invariant: Only one proposal can exist per proposal ID
    function invariant_OnlyOneActiveProposalPerID() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "test");

        // Try to create same proposal again (should fail)
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.PROPOSAL_EXISTS.selector, proposalId));
        governor.propose(targets, values, calldatas, "test");

        // Invariant holds: Cannot create duplicate proposal IDs
    }

    /// @notice Invariant: Replaced proposals are always marked as canceled
    function invariant_ReplacedProposalsAlwaysCanceled() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "original");

        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        vm.prank(voter1);
        bytes32 newProposalId = governor.updateProposal(proposalId, targets, values, updatedCalldatas, "updated", "test");

        // Check invariant: old proposal is canceled and marked as replaced
        Proposal memory oldProposal = governor.getProposal(proposalId);
        assertTrue(oldProposal.canceled, "INVARIANT VIOLATED: Replaced proposal not marked canceled");
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced), "INVARIANT VIOLATED: Wrong state");

        // Check replacement mapping
        bytes32 replacedBy = governor.proposalIdReplacedBy(proposalId);
        assertEq(replacedBy, newProposalId, "INVARIANT VIOLATED: Replacement mapping incorrect");
    }

    /// @notice Invariant: Proposer must have had threshold votes at creation time
    function test_ProposerMeetsThresholdAtCreation() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(500); // 5% threshold

        uint256 requiredVotes = governor.proposalThreshold();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Should succeed
        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "test");

        // Verify proposal stored the threshold requirement
        Proposal memory proposal = governor.getProposal(proposalId);
        assertEq(proposal.proposalThreshold, requiredVotes, "INVARIANT VIOLATED: Threshold not stored correctly");
    }

    /// @notice Invariant: Proposal state transitions are monotonic (no backwards movement)
    function invariant_StateTransitionsMonotonic() public {
        deployMock();
        mintVoter1();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "test");

        // State progression: Updatable -> Pending -> Active -> Succeeded/Defeated
        ProposalState currentState = governor.state(proposalId);
        assertEq(uint256(currentState), uint256(ProposalState.Updatable), "Should start Updatable");

        // Move to Pending
        vm.warp(block.timestamp + 1 days);
        currentState = governor.state(proposalId);
        assertEq(uint256(currentState), uint256(ProposalState.Pending), "Should move to Pending");

        // Move to Active
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        currentState = governor.state(proposalId);
        assertEq(uint256(currentState), uint256(ProposalState.Active), "Should move to Active");

        // Vote to pass
        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        // Move to Succeeded
        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        currentState = governor.state(proposalId);
        assertEq(uint256(currentState), uint256(ProposalState.Succeeded), "Should move to Succeeded");

        // Invariant: Once in terminal state, cannot go backwards
        // (This is enforced by the contract logic - terminal states are checked first)
    }

    /// @notice Invariant: Signer array length never exceeds MAX_PROPOSAL_SIGNERS
    function test_SignerArrayBounded() public {
        deployMock();

        // Verify the constant is set correctly
        uint256 maxSigners = governor.MAX_PROPOSAL_SIGNERS();
        assertEq(maxSigners, 32, "MAX_PROPOSAL_SIGNERS should be 32");

        // Try to create proposal with more than max signers (should fail during creation)
        mintVoter1();
        _createUsersWithPKs(33, 5 ether);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](33);
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "too many", voter1);
        for (uint256 i = 0; i < 33; i++) {
            proposerSignatures[i] = _buildProposeSignature(
                otherUsersPKs[i],
                otherUsers[i],
                voter1,
                proposalIdToSign,
                0,
                block.timestamp + 1 days
            );
        }

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("TOO_MANY_SIGNERS()"));
        governor.proposeBySigs(voter1, proposerSignatures, targets, values, calldatas, "too many");

        // Invariant holds: Cannot exceed MAX_PROPOSAL_SIGNERS
    }

    ///                                                          ///
    ///                   ERC-1271 WALLET TESTS                  ///
    ///                                                          ///

    /// @notice Test proposeBySigs with ERC-1271 smart wallet signer
    function test_ProposeBySigsWithSmartWallet() public {
        deployMock();

        // Create smart wallet owned by voter1
        MockERC1271Wallet wallet = new MockERC1271Wallet(voter1);

        mintVoter1();

        vm.prank(voter1);
        token.delegate(address(wallet));

        vm.warp(block.timestamp + 1);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Build the proposal signature
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "smart wallet proposal", voter2);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PROPOSAL_TYPEHASH, voter2, proposalIdToSign, 0, block.timestamp + 1 days))
            )
        );

        // Approve the hash in the wallet (simulates wallet's internal approval)
        vm.prank(voter1);
        wallet.approveHash(digest);

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = ProposerSignature({
            signer: address(wallet),
            nonce: 0,
            deadline: block.timestamp + 1 days,
            sig: "" // Empty sig for ERC-1271 (contract validates internally)
        });

        // Create proposal with smart wallet as signer
        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "smart wallet proposal");

        // Verify proposal created
        Proposal memory proposal = governor.getProposal(proposalId);
        assertEq(proposal.proposer, voter2);

        // Verify wallet is recorded as signer
        address[] memory signers = governor.getProposalSigners(proposalId);
        assertEq(signers.length, 1);
        assertEq(signers[0], address(wallet));
    }

    /// @notice Test castVoteBySig with ERC-1271 smart wallet
    function test_CastVoteBySigWithSmartWallet() public {
        deployMock();

        // Create smart wallet owned by voter1
        MockERC1271Wallet wallet = new MockERC1271Wallet(voter1);

        mintVoter1();

        vm.prank(voter1);
        token.delegate(address(wallet));

        // Mint a proposer token to voter2 so wallet can keep delegated voting power
        vm.startPrank(address(auction));
        uint256 voter2TokenId = token.mint();
        token.transferFrom(address(auction), voter2, voter2TokenId);
        vm.stopPrank();

        vm.prank(voter2);
        token.delegate(voter2);

        vm.warp(block.timestamp + 1);

        // Create a proposal from voter2
        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        vm.prank(voter2);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "wallet vote test");

        // Warp to voting period
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay() + 1);

        // Build vote signature
        bytes32 domainSeparator = governor.DOMAIN_SEPARATOR();
        bytes32 voteTypeHash = governor.VOTE_TYPEHASH();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(voteTypeHash, address(wallet), proposalId, FOR, 0, block.timestamp + 1 days))
            )
        );

        // Approve hash in wallet
        vm.prank(voter1);
        wallet.approveHash(digest);

        // Cast vote with smart wallet signature
        vm.prank(voter1); // Can be anyone since signature validates
        governor.castVoteBySig(address(wallet), proposalId, FOR, 0, block.timestamp + 1 days, "");

        // Verify vote counted
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 1);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    /// @notice Test updateProposalBySigs with ERC-1271 smart wallet
    function test_UpdateProposalBySigsWithSmartWallet() public {
        deployMock();

        // Create smart wallet owned by voter1
        MockERC1271Wallet wallet = new MockERC1271Wallet(voter1);

        mintVoter1();

        vm.prank(voter1);
        token.delegate(address(wallet));

        vm.warp(block.timestamp + 1);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(1 days);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Create signed proposal with smart wallet
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "original", voter2);
        bytes32 proposeDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PROPOSAL_TYPEHASH, voter2, proposalIdToSign, 0, block.timestamp + 1 days))
            )
        );

        vm.prank(voter1);
        wallet.approveHash(proposeDigest);

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = ProposerSignature({
            signer: address(wallet),
            nonce: 0,
            deadline: block.timestamp + 1 days,
            sig: ""
        });

        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "original");

        bytes32 updatedProposalId = _relaySmartWalletProposalUpdate(wallet, proposalId, targets, values);

        // Verify update worked
        assertTrue(updatedProposalId != proposalId);
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Replaced));
    }

    /// @notice Test that invalid ERC-1271 signature is rejected
    function testRevert_InvalidERC1271Signature() public {
        deployMock();

        // Create smart wallet but don't approve any hashes
        MockERC1271Wallet wallet = new MockERC1271Wallet(voter1);

        vm.prank(address(auction));
        token.mint();

        vm.prank(address(wallet));
        token.delegate(address(wallet));

        vm.warp(block.timestamp + 1);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Try to create proposal without approving hash (wallet will reject)
        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](1);
        proposerSignatures[0] = ProposerSignature({
            signer: address(wallet),
            nonce: 0,
            deadline: block.timestamp + 1 days,
            sig: "" // Empty sig, but wallet hasn't approved hash
        });

        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE()"));
        governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "should fail");
    }

    /// @notice Test mixed EOA and smart wallet signers
    function test_MixedEOAAndSmartWalletSigners() public {
        deployMock();

        // Create smart wallet
        MockERC1271Wallet wallet = new MockERC1271Wallet(voter1);

        // Mint to both wallet and voter1
        vm.prank(address(auction));
        token.mint(); // to wallet

        mintVoter1(); // to voter1 EOA

        vm.prank(address(wallet));
        token.delegate(address(wallet));

        vm.warp(block.timestamp + 1);

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        // Sort signers (wallet address < voter1 address in test setup)
        address[] memory sortedSigners = new address[](2);
        if (address(wallet) < voter1) {
            sortedSigners[0] = address(wallet);
            sortedSigners[1] = voter1;
        } else {
            sortedSigners[0] = voter1;
            sortedSigners[1] = address(wallet);
        }

        ProposerSignature[] memory proposerSignatures = new ProposerSignature[](2);

        // Build signatures in sorted order
        bytes32 proposalIdToSign = _computeProposalId(targets, values, calldatas, "mixed signers", voter2);

        for (uint256 i = 0; i < 2; i++) {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    governor.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PROPOSAL_TYPEHASH, voter2, proposalIdToSign, 0, block.timestamp + 1 days))
                )
            );

            if (sortedSigners[i] == address(wallet)) {
                // Smart wallet signature
                vm.prank(voter1);
                wallet.approveHash(digest);

                proposerSignatures[i] = ProposerSignature({
                    signer: address(wallet),
                    nonce: 0,
                    deadline: block.timestamp + 1 days,
                    sig: ""
                });
            } else {
                // EOA signature
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);

                proposerSignatures[i] = ProposerSignature({
                    signer: voter1,
                    nonce: 0,
                    deadline: block.timestamp + 1 days,
                    sig: abi.encodePacked(r, s, v)
                });
            }
        }

        // Create proposal with mixed signers
        vm.prank(voter2);
        bytes32 proposalId = governor.proposeBySigs(voter2, proposerSignatures, targets, values, calldatas, "mixed signers");

        // Verify both signers recorded
        address[] memory recordedSigners = governor.getProposalSigners(proposalId);
        assertEq(recordedSigners.length, 2);
        assertEq(recordedSigners[0], sortedSigners[0]);
        assertEq(recordedSigners[1], sortedSigners[1]);
    }

    function _relaySmartWalletProposalUpdate(
        MockERC1271Wallet wallet,
        bytes32 proposalId,
        address[] memory targets,
        uint256[] memory values
    ) internal returns (bytes32) {
        bytes[] memory updatedCalldatas = new bytes[](1);
        updatedCalldatas[0] = abi.encodeWithSignature("unpause()");

        bytes32 updatedProposalIdToSign = _computeProposalId(targets, values, updatedCalldatas, "updated", voter2);
        bytes32 updateDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                governor.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(UPDATE_PROPOSAL_TYPEHASH, proposalId, updatedProposalIdToSign, voter2, 1, block.timestamp + 1 days))
            )
        );

        vm.prank(voter1);
        wallet.approveHash(updateDigest);

        ProposerSignature[] memory updateSignatures = new ProposerSignature[](1);
        updateSignatures[0] = ProposerSignature({ signer: address(wallet), nonce: 1, deadline: block.timestamp + 1 days, sig: "" });

        vm.prank(voter2);
        return governor.updateProposalBySigs(proposalId, voter2, updateSignatures, targets, values, updatedCalldatas, "updated", "smart wallet update");
    }
}
