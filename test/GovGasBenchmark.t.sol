// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { GovTest } from "./Gov.t.sol";
import { console2 } from "forge-std/console2.sol";

/// @title GovGasBenchmark
/// @notice Gas benchmarking tests for Governor signed proposal features
/// @dev Run with: forge test --match-contract GovGasBenchmark --gas-report
contract GovGasBenchmark is GovTest {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Benchmark: Regular propose (no signatures)
    function test_GasBenchmark_RegularPropose() public {
        deployMock();
        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        uint256 gasBefore = gasleft();
        governor.propose(targets, values, calldatas, "Regular proposal");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for regular propose:", gasUsed);
    }

    /// @notice Benchmark: proposeBySigs with 1 signer
    function test_GasBenchmark_ProposeBySigs_1Signer() public {
        deployMock();
        _createUsersWithPKs(1, 100 ether);
        _mintTokensToUsers(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(1, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.proposeBySigs(signatures, targets, values, calldatas, "test");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for proposeBySigs with 1 signer:", gasUsed);
    }

    /// @notice Benchmark: proposeBySigs with 8 signers
    function test_GasBenchmark_ProposeBySigs_8Signers() public {
        deployMock();
        _createUsersWithPKs(8, 100 ether);
        _mintTokensToUsers(8);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(8, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.proposeBySigs(signatures, targets, values, calldatas, "test");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for proposeBySigs with 8 signers:", gasUsed);
    }

    /// @notice Benchmark: proposeBySigs with 16 signers
    function test_GasBenchmark_ProposeBySigs_16Signers() public {
        deployMock();
        _createUsersWithPKs(16, 100 ether);
        _mintTokensToUsers(16);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(16, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.proposeBySigs(signatures, targets, values, calldatas, "test");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for proposeBySigs with 16 signers:", gasUsed);
    }

    /// @notice Benchmark: proposeBySigs with 24 signers
    function test_GasBenchmark_ProposeBySigs_24Signers() public {
        deployMock();
        _createUsersWithPKs(24, 100 ether);
        _mintTokensToUsers(24);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(24, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.proposeBySigs(signatures, targets, values, calldatas, "test");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for proposeBySigs with 24 signers:", gasUsed);
    }

    /// @notice Benchmark: proposeBySigs with 32 signers (maximum)
    function test_GasBenchmark_ProposeBySigs_32Signers() public {
        deployMock();
        _createUsersWithPKs(32, 100 ether);
        _mintTokensToUsers(32);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(32, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.proposeBySigs(signatures, targets, values, calldatas, "test");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for proposeBySigs with 32 signers (max):", gasUsed);
    }

    /// @notice Benchmark: updateProposal (without signatures)
    function test_GasBenchmark_UpdateProposal() public {
        deployMock();
        mintVoter1();

        vm.prank(voter1);
        bytes32 proposalId = createProposal();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(voter1);
        uint256 gasBefore = gasleft();
        governor.updateProposal(proposalId, targets, values, calldatas, "Updated proposal", "Gas benchmark update");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for updateProposal (no signatures):", gasUsed);
    }

    /// @notice Benchmark: updateProposalBySigs with 1 signer
    function test_GasBenchmark_UpdateProposalBySigs_1Signer() public {
        deployMock();
        _createUsersWithPKs(1, 100 ether);
        _mintTokensToUsers(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(1, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        // Create update signatures
        bytes32 updatedProposalId = _computeProposalId(targets, values, calldatas, "updated", founder);
        ProposerSignature[] memory updateSigs = _buildOrderedUpdateSignatures(1, createdProposalId, updatedProposalId, founder, 1, block.timestamp + 1 days);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.updateProposalBySigs(createdProposalId, updateSigs, targets, values, calldatas, "updated", "Gas benchmark");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for updateProposalBySigs with 1 signer:", gasUsed);
    }

    /// @notice Benchmark: updateProposalBySigs with 8 signers
    function test_GasBenchmark_UpdateProposalBySigs_8Signers() public {
        deployMock();
        _createUsersWithPKs(8, 100 ether);
        _mintTokensToUsers(8);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(8, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        // Create update signatures
        bytes32 updatedProposalId = _computeProposalId(targets, values, calldatas, "updated", founder);
        ProposerSignature[] memory updateSigs = _buildOrderedUpdateSignatures(8, createdProposalId, updatedProposalId, founder, 1, block.timestamp + 1 days);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.updateProposalBySigs(createdProposalId, updateSigs, targets, values, calldatas, "updated", "Gas benchmark");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for updateProposalBySigs with 8 signers:", gasUsed);
    }

    /// @notice Benchmark: updateProposalBySigs with 16 signers
    function test_GasBenchmark_UpdateProposalBySigs_16Signers() public {
        deployMock();
        _createUsersWithPKs(16, 100 ether);
        _mintTokensToUsers(16);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(16, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        // Create update signatures
        bytes32 updatedProposalId = _computeProposalId(targets, values, calldatas, "updated", founder);
        ProposerSignature[] memory updateSigs = _buildOrderedUpdateSignatures(16, createdProposalId, updatedProposalId, founder, 1, block.timestamp + 1 days);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.updateProposalBySigs(createdProposalId, updateSigs, targets, values, calldatas, "updated", "Gas benchmark");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for updateProposalBySigs with 16 signers:", gasUsed);
    }

    /// @notice Benchmark: updateProposalBySigs with 32 signers (maximum)
    function test_GasBenchmark_UpdateProposalBySigs_32Signers() public {
        deployMock();
        _createUsersWithPKs(32, 100 ether);
        _mintTokensToUsers(32);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(32, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        // Create update signatures
        bytes32 updatedProposalId = _computeProposalId(targets, values, calldatas, "updated", founder);
        ProposerSignature[] memory updateSigs = _buildOrderedUpdateSignatures(32, createdProposalId, updatedProposalId, founder, 1, block.timestamp + 1 days);

        vm.prank(founder);
        uint256 gasBefore = gasleft();
        governor.updateProposalBySigs(createdProposalId, updateSigs, targets, values, calldatas, "updated", "Gas benchmark");
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for updateProposalBySigs with 32 signers (max):", gasUsed);
    }

    /// @notice Benchmark: castVoteBySig
    function test_GasBenchmark_CastVoteBySig() public {
        deployMock();
        mintVoter1();

        bytes32 proposalId = createProposal();

        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        bytes32 voteHash = keccak256(abi.encode(governor.VOTE_TYPEHASH(), voter1, proposalId, FOR, 0, block.timestamp + 1 days));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = _encodeSignature(v, r, s);

        uint256 gasBefore = gasleft();
        governor.castVoteBySig(voter1, proposalId, FOR, 0, block.timestamp + 1 days, sig);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for castVoteBySig:", gasUsed);
    }

    /// @notice Benchmark: cancel with 1 signer
    function test_GasBenchmark_Cancel_1Signer() public {
        deployMock();
        _createUsersWithPKs(1, 100 ether);
        _mintTokensToUsers(1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(1, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        vm.prank(otherUsers[0]);
        uint256 gasBefore = gasleft();
        governor.cancel(createdProposalId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for cancel with 1 signer:", gasUsed);
    }

    /// @notice Benchmark: cancel with 16 signers
    function test_GasBenchmark_Cancel_16Signers() public {
        deployMock();
        _createUsersWithPKs(16, 100 ether);
        _mintTokensToUsers(16);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(16, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        vm.prank(otherUsers[0]);
        uint256 gasBefore = gasleft();
        governor.cancel(createdProposalId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for cancel with 16 signers:", gasUsed);
    }

    /// @notice Benchmark: cancel with 32 signers (maximum)
    function test_GasBenchmark_Cancel_32Signers() public {
        deployMock();
        _createUsersWithPKs(32, 100 ether);
        _mintTokensToUsers(32);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(32, founder, proposalId, 0, block.timestamp + 1 days, false);

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(signatures, targets, values, calldatas, "test");

        vm.prank(otherUsers[0]);
        uint256 gasBefore = gasleft();
        governor.cancel(createdProposalId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for cancel with 32 signers (max):", gasUsed);
    }

    // Helper function to build update signatures
    function _buildOrderedUpdateSignatures(
        uint256 count,
        bytes32 oldProposalId,
        bytes32 newProposalId,
        address proposer,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (ProposerSignature[] memory signatures) {
        signatures = new ProposerSignature[](count);
        (address[] memory sortedSigners, uint256[] memory sortedSignerPks) = _sortedSignersAndPks(count);

        for (uint256 i = 0; i < count; i++) {
            bytes32 structHash = keccak256(abi.encode(UPDATE_PROPOSAL_TYPEHASH, oldProposalId, newProposalId, proposer, nonce, deadline));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sortedSignerPks[i], digest);

            signatures[i] = ProposerSignature({
                signer: sortedSigners[i],
                nonce: nonce,
                deadline: deadline,
                sig: _encodeSignature(v, r, s)
            });
        }
    }

    // Helper function to mint tokens to otherUsers
    function _mintTokensToUsers(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            vm.prank(address(auction));
            uint256 tokenId = token.mint();
            vm.prank(address(auction));
            token.transferFrom(address(auction), otherUsers[i], tokenId);
        }
        vm.warp(block.timestamp + 1); // Advance time for voting power to take effect
    }
}
