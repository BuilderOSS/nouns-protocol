// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { GovTest } from "./Gov.t.sol";
import { Governor } from "../src/governance/governor/Governor.sol";
import { IGovernor } from "../src/governance/governor/IGovernor.sol";
import { ERC1967Proxy } from "../src/lib/proxy/ERC1967Proxy.sol";

/// @title GovUpgrade
/// @notice Integration tests for Governor upgrade path
/// @dev Tests upgrading from a previous Governor version to the current version
contract GovUpgrade is GovTest {
    Governor public newGovernorImpl;

    function setUp() public override {
        super.setUp();
    }

    /// @notice Test complete upgrade path: old version -> new version
    /// @dev This test simulates a real DAO upgrade scenario
    function test_UpgradePath_OldToNew() public {
        deployMock();
        mintVoter1();

        // Step 1: Create a proposal with the deployed governor
        bytes32 oldProposalId = _createProposalWithDescription("upgrade-old-proposal");

        // Verify proposal exists
        IGovernor.Proposal memory oldProposal = governor.getProposal(oldProposalId);
        assertEq(oldProposal.proposer, voter1, "Proposer should be voter1");
        assertTrue(oldProposal.voteStart != 0, "Proposal should exist");

        // Step 2: Vote on the old proposal to verify state
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        vm.prank(voter1);
        governor.castVote(oldProposalId, FOR);

        (, uint256 forVotes,) = governor.proposalVotes(oldProposalId);
        assertTrue(forVotes > 0, "Votes should be cast");

        // Refresh proposal snapshot after vote so comparisons include vote state
        oldProposal = governor.getProposal(oldProposalId);

        // Step 3: Deploy new Governor implementation
        newGovernorImpl = new Governor(address(manager));

        // Step 4: Register the upgrade in Manager
        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        // Verify registration
        assertTrue(
            manager.isRegisteredUpgrade(address(governorImpl), address(newGovernorImpl)),
            "Upgrade should be registered"
        );

        // Step 5: Upgrade the Governor proxy
        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Step 6: Verify storage integrity - old proposal should still exist
        IGovernor.Proposal memory oldProposalAfterUpgrade = governor.getProposal(oldProposalId);
        assertEq(oldProposalAfterUpgrade.proposer, voter1, "Old proposer should be preserved");
        assertEq(oldProposalAfterUpgrade.voteStart, oldProposal.voteStart, "Vote start should be preserved");
        assertEq(oldProposalAfterUpgrade.voteEnd, oldProposal.voteEnd, "Vote end should be preserved");
        assertEq(oldProposalAfterUpgrade.forVotes, oldProposal.forVotes, "For votes should be preserved");

        // Step 7: Verify old proposal state is still correct
        assertTrue(governor.state(oldProposalId) == ProposalState.Active, "Old proposal should still be active");

        // Step 8: Complete old proposal lifecycle
        vm.warp(block.timestamp + governor.votingPeriod());
        assertTrue(governor.state(oldProposalId) == ProposalState.Succeeded, "Old proposal should succeed");

        governor.queue(oldProposalId);
        assertTrue(governor.state(oldProposalId) == ProposalState.Queued, "Old proposal should be queued");

        // Step 9: Test new features on upgraded Governor
        // Note: proposalUpdatablePeriod should retain prior value (not reinitialized)
        // Update the updatable period (new feature governance control)
        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(2 days);
        assertEq(governor.proposalUpdatablePeriod(), 2 days, "Updatable period should be updated");

        // Create a new proposal with the upgraded governor
        vm.warp(block.timestamp + 1 days);
        vm.prank(voter1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 newProposalId = governor.propose(targets, values, calldatas, "New proposal after upgrade");

        // Verify new proposal has update period set
        uint256 newProposalUpdateEnd = governor.proposalUpdatePeriodEnd(newProposalId);
        assertTrue(newProposalUpdateEnd > 0, "New proposal should have update period");

        // Test update feature (new functionality)
        assertTrue(governor.state(newProposalId) == ProposalState.Updatable, "New proposal should be updatable");

        vm.prank(voter1);
        bytes32 updatedProposalId = governor.updateProposal(
            newProposalId,
            targets,
            values,
            calldatas,
            "Updated proposal after upgrade",
            "Testing upgrade path"
        );

        // Verify replacement mapping (new feature)
        assertEq(governor.proposalIdReplacedBy(newProposalId), updatedProposalId, "Replacement mapping should be set");
        assertTrue(governor.state(newProposalId) == ProposalState.Replaced, "Old proposal should be replaced");
    }

    /// @notice Test that proposalUpdatablePeriod is preserved across upgrade
    function test_UpgradePath_PreservesUpdatablePeriod() public {
        deployMock();

        // Set a custom updatable period before upgrade
        vm.prank(address(treasury));
        governor.updateProposalUpdatablePeriod(3 days);

        uint256 periodBeforeUpgrade = governor.proposalUpdatablePeriod();
        assertEq(periodBeforeUpgrade, 3 days, "Period should be set before upgrade");

        // Deploy and register new implementation
        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        // Upgrade
        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Verify period is preserved (not reinitialized)
        uint256 periodAfterUpgrade = governor.proposalUpdatablePeriod();
        assertEq(periodAfterUpgrade, periodBeforeUpgrade, "Period should be preserved after upgrade");
    }

    /// @notice Test proposeBySigs works after upgrade
    function test_UpgradePath_ProposeBySigsWorksAfterUpgrade() public {
        deployMock();
        _createUsersWithPKs(2, 100 ether);
        _mintTokensToUsers(2);

        // Deploy and upgrade
        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Test proposeBySigs (new feature)
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = mockProposal();
        bytes32 proposalId = _computeProposalId(targets, values, calldatas, "test", founder);

        ProposerSignature[] memory signatures = _buildOrderedProposeSignatures(
            2,
            founder,
            proposalId,
            0,
            block.timestamp + 1 days,
            false
        );

        vm.prank(founder);
        bytes32 createdProposalId = governor.proposeBySigs(founder, signatures, targets, values, calldatas, "test");

        // Verify signed proposal was created
        assertTrue(createdProposalId != bytes32(0), "Proposal should be created");

        address[] memory storedSigners = governor.getProposalSigners(createdProposalId);
        assertEq(storedSigners.length, 2, "Should have 2 signers");
    }

    /// @notice Test castVoteBySig new signature format works after upgrade
    function test_UpgradePath_NewVoteSignatureFormatWorks() public {
        deployMock();
        mintVoter1();

        // Create proposal before upgrade
        bytes32 proposalId = _createProposalWithDescription("upgrade-vote-sig-proposal");

        // Deploy and upgrade
        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Warp to voting period
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        // Test new vote signature format (with nonce)
        uint256 nonce = 0; // First vote signature for voter1 should use nonce 0

        bytes32 voteHash = keccak256(abi.encode(governor.VOTE_TYPEHASH(), voter1, proposalId, FOR, nonce, block.timestamp + 1 days));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", governor.DOMAIN_SEPARATOR(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PK, digest);
        bytes memory sig = _encodeSignature(v, r, s);

        // Cast vote with new signature format
        governor.castVoteBySig(voter1, proposalId, FOR, nonce, block.timestamp + 1 days, sig);

        // Verify vote was cast
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertTrue(forVotes > 0, "Vote should be cast");

        // Note: Nonce would be incremented to 1, but we can't verify since nonces is internal
        // The fact that the vote succeeded proves the nonce was correct
    }

    /// @notice Test multiple sequential upgrades
    function test_UpgradePath_MultipleSequentialUpgrades() public {
        deployMock();
        mintVoter1();

        // Create proposal with original version
        bytes32 proposalId1 = _createProposalWithDescription("upgrade-proposal-1");

        // First upgrade
        Governor newImpl1 = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newImpl1));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newImpl1));

        // Create proposal after first upgrade
        vm.warp(block.timestamp + 1 days);
        bytes32 proposalId2 = _createProposalWithDescription("upgrade-proposal-2");

        // Second upgrade (simulating future upgrade)
        Governor newImpl2 = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(newImpl1), address(newImpl2));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newImpl2));

        // Verify both old proposals still exist and are readable
        IGovernor.Proposal memory proposal1 = governor.getProposal(proposalId1);
        IGovernor.Proposal memory proposal2 = governor.getProposal(proposalId2);

        assertTrue(proposal1.voteStart != 0, "First proposal should exist");
        assertTrue(proposal2.voteStart != 0, "Second proposal should exist");

        // Create proposal after second upgrade
        vm.warp(block.timestamp + 1 days);
        bytes32 proposalId3 = _createProposalWithDescription("upgrade-proposal-3");

        IGovernor.Proposal memory proposal3 = governor.getProposal(proposalId3);
        assertTrue(proposal3.voteStart != 0, "Third proposal should exist");
    }

    /// @notice Test that unregistered upgrade fails
    function testRevert_UpgradePath_UnregisteredUpgradeFails() public {
        deployMock();

        // Deploy new implementation but don't register it
        newGovernorImpl = new Governor(address(manager));

        // Attempt upgrade without registration should fail
        vm.prank(address(treasury));
        vm.expectRevert();
        governor.upgradeTo(address(newGovernorImpl));
    }

    /// @notice Test that only treasury (owner) can upgrade
    function testRevert_UpgradePath_OnlyOwnerCanUpgrade() public {
        deployMock();

        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        // Attempt upgrade from non-owner should fail
        vm.prank(founder);
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        governor.upgradeTo(address(newGovernorImpl));
    }

    /// @notice Test storage layout compatibility across upgrade
    function test_UpgradePath_StorageLayoutCompatibility() public {
        deployMock();
        mintVoter1();

        // Record various storage values before upgrade
        uint256 votingDelayBefore = governor.votingDelay();
        uint256 votingPeriodBefore = governor.votingPeriod();
        uint256 proposalThresholdBpsBefore = governor.proposalThresholdBps();
        uint256 quorumThresholdBpsBefore = governor.quorumThresholdBps();
        address vetoerBefore = governor.vetoer();
        address tokenBefore = governor.token();
        address treasuryBefore = governor.treasury();

        // Create proposal to test proposal storage
        bytes32 proposalId = _createProposalWithDescription("upgrade-storage-layout");

        // The proposal helper configures threshold/updatable period before proposing.
        // Capture the actual pre-upgrade values after setup to verify storage preservation.
        proposalThresholdBpsBefore = governor.proposalThresholdBps();

        IGovernor.Proposal memory proposalBefore = governor.getProposal(proposalId);

        // Upgrade
        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Verify all storage values are preserved
        assertEq(governor.votingDelay(), votingDelayBefore, "Voting delay should be preserved");
        assertEq(governor.votingPeriod(), votingPeriodBefore, "Voting period should be preserved");
        assertEq(governor.proposalThresholdBps(), proposalThresholdBpsBefore, "Proposal threshold should be preserved");
        assertEq(governor.quorumThresholdBps(), quorumThresholdBpsBefore, "Quorum threshold should be preserved");
        assertEq(governor.vetoer(), vetoerBefore, "Vetoer should be preserved");
        assertEq(governor.token(), tokenBefore, "Token should be preserved");
        assertEq(governor.treasury(), treasuryBefore, "Treasury should be preserved");

        // Verify proposal storage is preserved
        IGovernor.Proposal memory proposalAfter = governor.getProposal(proposalId);
        assertEq(proposalAfter.proposer, proposalBefore.proposer, "Proposer should be preserved");
        assertEq(proposalAfter.timeCreated, proposalBefore.timeCreated, "Time created should be preserved");
        assertEq(proposalAfter.voteStart, proposalBefore.voteStart, "Vote start should be preserved");
        assertEq(proposalAfter.voteEnd, proposalBefore.voteEnd, "Vote end should be preserved");
        assertEq(proposalAfter.proposalThreshold, proposalBefore.proposalThreshold, "Proposal threshold should be preserved");
        assertEq(proposalAfter.quorumVotes, proposalBefore.quorumVotes, "Quorum votes should be preserved");
    }

    /// @notice Test that voting history is preserved across upgrade
    function test_UpgradePath_VotingHistoryPreserved() public {
        deployMock();
        mintVoter1();

        bytes32 proposalId = _createProposalWithDescription("upgrade-voting-history");

        // Cast vote before upgrade
        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay());

        vm.prank(voter1);
        governor.castVote(proposalId, FOR);

        // Verify vote was cast by checking vote count
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        uint256 votesBefore = forVotes;
        assertTrue(votesBefore > 0, "Vote should be cast before upgrade");

        // Upgrade
        newGovernorImpl = new Governor(address(manager));

        vm.prank(address(manager.owner()));
        manager.registerUpgrade(address(governorImpl), address(newGovernorImpl));

        vm.prank(address(treasury));
        governor.upgradeTo(address(newGovernorImpl));

        // Verify vote count is preserved after upgrade
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, votesBefore, "Vote count should be preserved");

        // Verify cannot vote again (voting history is preserved)
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        governor.castVote(proposalId, FOR);
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

    function _createProposalWithDescription(string memory description) internal returns (bytes32 proposalId) {
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
        proposalId = governor.propose(targets, values, calldatas, description);
    }
}
