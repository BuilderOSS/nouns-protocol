// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { GovTest } from "./Gov.t.sol";

/// @title GovFuzz
/// @notice Fuzz tests for Governor signed proposal and update features
/// @dev Run with: forge test --match-contract GovFuzz
contract GovFuzz is GovTest {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Fuzz test: proposeBySigs with variable signer count
    /// @param signerCount Number of signers (bounded to 1-32)
    function testFuzz_ProposeBySigs_VariableSignerCount(uint8 signerCount) public {
        // Bound to valid range
        signerCount = uint8(bound(signerCount, 1, 32));

        deployMock();
        _createUsersWithPKs(signerCount, 100 ether);
        _mintTokensToUsers(signerCount);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(
            signerCount,
            founder,
            proposalId,
            0,
            block.timestamp + 1 days,
            false
        );

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(founder, signatures, targets, values, calldatas, "test");

        // Verify proposal was created
        assertTrue(createdProposalId != bytes32(0), "Proposal should be created");

        // Verify signers were stored correctly
        address[] memory storedSigners = governor.getProposalSigners(createdProposalId);
        assertEq(storedSigners.length, signerCount, "Signer count mismatch");
    }

    /// @notice Fuzz test: Vote signature with variable deadline
    /// @param deadlineOffset Deadline offset from current time (bounded to 1 hour - 1 year)
    function testFuzz_CastVoteBySig_VariableDeadline(uint256 deadlineOffset) public {
        // Bound deadline to reasonable range: 1 hour to 1 year
        deadlineOffset = bound(deadlineOffset, 1 hours, 365 days);

        deployMock();
        mintVoter1();

        bytes32 proposalId = createProposal();
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        uint256 deadline = block.timestamp + deadlineOffset;
        uint256 nonce = 0; // First vote signature for voter1

        bytes32 voteHash = keccak256(abi.encode(governor.VOTE_TYPEHASH(), voter1, proposalId, FOR, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = _encodeSignature(v, r, s);

        // Should succeed as long as deadline is in the future
        governor.castVoteBySig(voter1, proposalId, FOR, 0, deadline, sig);

        // Verify vote was cast
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertTrue(forVotes > 0, "Vote should be cast");
    }

    /// @notice Fuzz test: Vote signature fails with expired deadline
    /// @param expiredOffset How far in the past the deadline is (bounded to 1 second - 1 year)
    function testFuzz_CastVoteBySig_ExpiredDeadline_Reverts(uint256 expiredOffset) public {
        // Bound to reasonable past range
        expiredOffset = bound(expiredOffset, 1, 365 days);

        deployMock();
        mintVoter1();

        bytes32 proposalId = createProposal();
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        vm.assume(expiredOffset <= block.timestamp);
        uint256 deadline = block.timestamp - expiredOffset;

        bytes32 voteHash = keccak256(abi.encode(governor.VOTE_TYPEHASH(), voter1, proposalId, FOR, 0, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = _encodeSignature(v, r, s);

        // Should revert with expired signature
        vm.expectRevert(abi.encodeWithSignature("EXPIRED_SIGNATURE()"));
        governor.castVoteBySig(voter1, proposalId, FOR, 0, deadline, sig);
    }

    /// @notice Fuzz test: Proposal update timing
    /// @param warpTime Time to warp before attempting update (bounded to 0 - 2 weeks)
    function testFuzz_UpdateProposal_Timing(uint256 warpTime) public {
        // Bound to test range
        warpTime = bound(warpTime, 0, 2 weeks);

        deployMock();
        mintVoter1();

        bytes32 proposalId = createProposal();

        uint256 updatePeriodEnd = governor.proposalUpdatePeriodEnd(proposalId);

        vm.warp(block.timestamp + warpTime);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        if (block.timestamp < updatePeriodEnd) {
            // Should succeed if within update period
            vm.prank(voter1);
            governor.updateProposal(proposalId, targets, values, calldatas, "Updated", "Timing test");
        } else {
            // Should revert if past update period
            vm.prank(voter1);
            vm.expectRevert(abi.encodeWithSignature("CAN_ONLY_EDIT_UPDATABLE_PROPOSALS()"));
            governor.updateProposal(proposalId, targets, values, calldatas, "Updated", "Timing test");
        }
    }

    /// @notice Fuzz test: Invalid nonce for vote signature
    /// @param invalidNonce Wrong nonce value
    function testFuzz_CastVoteBySig_InvalidNonce_Reverts(uint256 invalidNonce) public {
        deployMock();
        mintVoter1();

        uint256 correctNonce = 0; // First vote, nonce should be 0

        // Ensure invalidNonce is actually invalid
        vm.assume(invalidNonce != correctNonce);

        bytes32 proposalId = createProposal();
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        bytes32 voteHash = keccak256(abi.encode(governor.VOTE_TYPEHASH(), voter1, proposalId, FOR, invalidNonce, block.timestamp + 1 days));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = _encodeSignature(v, r, s);

        // Should revert with invalid nonce
        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_NONCE()"));
        governor.castVoteBySig(voter1, proposalId, FOR, invalidNonce, block.timestamp + 1 days, sig);
    }

    /// @notice Fuzz test: Invalid nonce for propose signature
    /// @param invalidNonce Wrong nonce value
    function testFuzz_ProposeBySigs_InvalidNonce_Reverts(uint256 invalidNonce) public {
        deployMock();
        _createUsersWithPKs(1, 100 ether);
        _mintTokensToUsers(1);

        uint256 correctNonce = governor.proposeSignatureNonce(otherUsers[0]);

        // Ensure invalidNonce is actually invalid
        vm.assume(invalidNonce != correctNonce);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        // Build signature with invalid nonce
        ProposerSignature[] memory signatures = new ProposerSignature[](1);
        bytes32 structHash = keccak256(abi.encode(PROPOSAL_TYPEHASH, founder, proposalId, invalidNonce, block.timestamp + 1 days));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherUsersPKs[0], digest);

        signatures[0] = ProposerSignature({
            signer: otherUsers[0],
            nonce: invalidNonce,
            deadline: block.timestamp + 1 days,
            sig: _encodeSignature(v, r, s)
        });

        vm.prank(founder);
        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE_NONCE()"));
        governor.proposeBySigs(founder, signatures, targets, values, calldatas, "test");
    }

    /// @notice Fuzz test: Support value variations for voting
    /// @param support Vote support value (0 = Against, 1 = For, 2 = Abstain, 3+ = Invalid)
    function testFuzz_CastVote_SupportValues(uint256 support) public {
        deployMock();
        mintVoter1();

        bytes32 proposalId = createProposal();
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        vm.prank(voter1);

        if (support <= 2) {
            // Valid support values: should succeed
            governor.castVote(proposalId, support);

            // Verify vote was recorded correctly
            (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

            if (support == 0) {
                assertTrue(againstVotes > 0, "Against vote should be recorded");
            } else if (support == 1) {
                assertTrue(forVotes > 0, "For vote should be recorded");
            } else if (support == 2) {
                assertTrue(abstainVotes > 0, "Abstain vote should be recorded");
            }
        } else {
            // Invalid support values: should revert
            vm.expectRevert(abi.encodeWithSignature("INVALID_VOTE()"));
            governor.castVote(proposalId, support);
        }
    }

    /// @notice Fuzz test: updateProposalBySigs with variable signer count
    /// @param signerCount Number of signers (bounded to 1-16 for performance)
    function testFuzz_UpdateProposalBySigs_VariableSignerCount(uint8 signerCount) public {
        // Bound to reasonable range for fuzz testing (32 would be too slow)
        signerCount = uint8(bound(signerCount, 1, 16));

        deployMock();
        _createUsersWithPKs(signerCount, 100 ether);
        _mintTokensToUsers(signerCount);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(
            signerCount,
            founder,
            proposalId,
            0,
            block.timestamp + 1 days,
            false
        );

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(founder, signatures, targets, values, calldatas, "test");

        // Create update signatures
        bytes32 updatedProposalId = _computeProposalId(targets, values, calldatas, "updated", founder);
        ProposerSignature[] memory updateSigs = _buildOrderedUpdateSignatures(
            signerCount,
            createdProposalId,
            updatedProposalId,
            founder,
            1,
            block.timestamp + 1 days
        );

        vm.prank(founder);
        bytes32 newProposalId = governor.updateProposalBySigs(
            createdProposalId,
            founder,
            updateSigs,
            targets,
            values,
            calldatas,
            "updated",
            "Fuzz test update"
        );

        // Verify replacement mapping
        assertEq(governor.proposalIdReplacedBy(createdProposalId), newProposalId, "Replacement mapping should be set");

        // Verify old proposal is in Replaced state
        assertTrue(
            governor.state(createdProposalId) == ProposalState.Replaced,
            "Old proposal should be in Replaced state"
        );
    }

    /// @notice Fuzz test: Cancel with varying combined vote thresholds
    /// @param voterTokens Number of tokens to mint for proposer (affects vote threshold)
    function testFuzz_Cancel_ThresholdBoundary(uint16 voterTokens) public {
        // Bound to reasonable token count (1-1000)
        voterTokens = uint16(bound(voterTokens, 1, 1000));

        deployMock();

        // Mint specific number of tokens to voter1
        for (uint256 i = 0; i < voterTokens; i++) {
            vm.prank(address(auction));
            uint256 tokenId = token.mint();
            vm.prank(address(auction));
            token.transferFrom(address(auction), voter1, tokenId);
        }

        vm.warp(block.timestamp + 1);

        bytes32 proposalId = createProposal();

        uint256 proposalThreshold = governor.proposalThreshold();
        uint256 voter1Votes = governor.getVotes(voter1, block.timestamp - 1);

        // Try to cancel as a third party
        if (voter1Votes < proposalThreshold) {
            // Should succeed if below threshold
            vm.prank(founder);
            governor.cancel(proposalId);
            assertTrue(governor.state(proposalId) == ProposalState.Canceled, "Should be canceled");
        } else {
            // Should revert if at or above threshold
            vm.prank(founder);
            vm.expectRevert(abi.encodeWithSignature("INVALID_CANCEL()"));
            governor.cancel(proposalId);
        }
    }

    /// @notice Fuzz test: Proposal updatable period configuration
    /// @param updatablePeriod Custom updatable period (bounded to 0 - MAX)
    function testFuzz_ProposalUpdatablePeriod_Configuration(uint48 updatablePeriod) public {
        // Bound to valid range (0 to MAX_PROPOSAL_UPDATABLE_PERIOD which is 24 weeks)
        updatablePeriod = uint48(bound(updatablePeriod, 0, 24 weeks));

        deployMock();

        // Update the updatable period
        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(updatablePeriod);

        assertEq(governor.proposalUpdatablePeriod(), updatablePeriod, "Updatable period should be set");

        // Create a proposal and verify the update period end
        mintVoter1();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);

        vm.prank(voter1);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "Fuzz updatable period");

        uint256 expectedUpdateEnd = block.timestamp + updatablePeriod;
        assertEq(governor.proposalUpdatePeriodEnd(proposalId), expectedUpdateEnd, "Update period end should be correct");
    }

    // Helper function to build update signatures (copied from gas benchmark)
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
