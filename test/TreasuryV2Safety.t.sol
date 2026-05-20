// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";
import { GovernorSafeModule } from "../src/governance/treasury/GovernorSafeModule.sol";
import { ITreasury } from "../src/governance/treasury/ITreasury.sol";
import { MockGnosisSafe } from "./utils/mocks/MockGnosisSafe.sol";
import { MockSafeExecutionTarget } from "./utils/mocks/MockSafeExecutionTarget.sol";

contract TreasuryV2SafetyTest is NounsBuilderTest {
    MockGnosisSafe internal safe;
    GovernorSafeModule internal safeModule;
    MockSafeExecutionTarget internal target;
    address internal guardian;

    function setUp() public override {
        super.setUp();
        deployMock();

        safe = new MockGnosisSafe();
        safeModule = new GovernorSafeModule(address(treasury));
        safe.enableModule(address(safeModule));
        target = new MockSafeExecutionTarget();
        guardian = makeAddr("guardian");

        // Fund the safe for value transfers
        vm.deal(address(safe), 100 ether);

        // Register safe
        vm.prank(address(treasury));
        treasury.registerSafe(address(safe), address(safeModule), address(0), bytes32(0));

        // Set guardian
        vm.prank(address(treasury));
        treasury.setGuardian(guardian);
    }

    ///                                                          ///
    ///                    SPENDING LIMITS                       ///
    ///                                                          ///

    function test_SetSafeSpendingLimits() public {
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 1 ether, 10 ether);
    }

    function testRevert_SetSafeSpendingLimits_OnlyTreasury() public {
        vm.expectRevert();
        treasury.setSafeSpendingLimits(1, 1 ether, 10 ether);
    }

    function testRevert_ExecOnSafe_PerTxLimitExceeded() public {
        // Set per-transaction limit to 1 ether
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 1 ether, 0);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Try to execute with 2 ether (exceeds limit)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.SPENDING_LIMIT_EXCEEDED.selector);
        treasury.execOnSafe(1, address(target), 2 ether, data, 0);
    }

    function test_ExecOnSafe_WithinPerTxLimit() public {
        // Set per-transaction limit to 1 ether
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 1 ether, 0);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Execute with 0.5 ether (within limit)
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0.5 ether, data, 0);

        assertEq(target.number(), 42);
    }

    function testRevert_ExecOnSafe_DailyLimitExceeded() public {
        // Set daily limit to 5 ether
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 0, 5 ether);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // First tx: 3 ether (within limit)
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 3 ether, data, 0);

        // Second tx: 3 ether (would exceed daily limit of 5)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.DAILY_LIMIT_EXCEEDED.selector);
        treasury.execOnSafe(1, address(target), 3 ether, data, 0);
    }

    function test_DailyLimitResetsAfter24Hours() public {
        // Set daily limit to 5 ether
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 0, 5 ether);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Spend 5 ether
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 5 ether, data, 0);

        // Try to spend more immediately (should fail)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.DAILY_LIMIT_EXCEEDED.selector);
        treasury.execOnSafe(1, address(target), 1 ether, data, 0);

        // Warp 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);

        // Now should work again
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 5 ether, data, 0);
    }

    ///                                                          ///
    ///                      PAUSE MECHANISMS                    ///
    ///                                                          ///

    function test_PauseSafe_Guardian() public {
        vm.prank(guardian);
        treasury.pauseSafe(1);
    }

    function test_PauseSafe_Treasury() public {
        vm.prank(address(treasury));
        treasury.pauseSafe(1);
    }

    function testRevert_PauseSafe_Unauthorized() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(ITreasury.ONLY_GUARDIAN.selector);
        treasury.pauseSafe(1);
    }

    function testRevert_ExecOnSafe_Paused() public {
        // Pause the safe
        vm.prank(guardian);
        treasury.pauseSafe(1);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Try to execute (should fail)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.SAFE_PAUSED.selector);
        treasury.execOnSafe(1, address(target), 0, data, 0);
    }

    function test_UnpauseSafe() public {
        // Pause
        vm.prank(guardian);
        treasury.pauseSafe(1);

        // Unpause
        vm.prank(guardian);
        treasury.unpauseSafe(1);

        // Should work now
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0, data, 0);

        assertEq(target.number(), 42);
    }

    function test_PauseAllSafes_Guardian() public {
        vm.prank(guardian);
        treasury.pauseAllSafes();
    }

    function test_PauseAllSafes_Treasury() public {
        vm.prank(address(treasury));
        treasury.pauseAllSafes();
    }

    function testRevert_PauseAllSafes_Unauthorized() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(ITreasury.ONLY_GUARDIAN.selector);
        treasury.pauseAllSafes();
    }

    function testRevert_ExecOnSafe_AllPaused() public {
        // Pause all safes
        vm.prank(guardian);
        treasury.pauseAllSafes();

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Try to execute (should fail)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.ALL_SAFES_PAUSED.selector);
        treasury.execOnSafe(1, address(target), 0, data, 0);
    }

    function test_UnpauseAllSafes() public {
        // Pause all
        vm.prank(guardian);
        treasury.pauseAllSafes();

        // Unpause all
        vm.prank(guardian);
        treasury.unpauseAllSafes();

        // Should work now
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0, data, 0);

        assertEq(target.number(), 42);
    }

    ///                                                          ///
    ///                      GUARDIAN MANAGEMENT                 ///
    ///                                                          ///

    function test_SetGuardian() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(address(treasury));
        treasury.setGuardian(newGuardian);

        assertEq(treasury.getGuardian(), newGuardian);
    }

    function testRevert_SetGuardian_OnlyTreasury() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(guardian);
        vm.expectRevert();
        treasury.setGuardian(newGuardian);
    }

    function test_GuardianCanPauseAfterUpdate() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(address(treasury));
        treasury.setGuardian(newGuardian);

        // New guardian should be able to pause
        vm.prank(newGuardian);
        treasury.pauseSafe(1);

        // Old guardian should not
        vm.prank(guardian);
        vm.expectRevert(ITreasury.ONLY_GUARDIAN.selector);
        treasury.unpauseSafe(1);
    }

    ///                                                          ///
    ///                   COMBINED SAFETY TESTS                  ///
    ///                                                          ///

    function test_CombinedLimitsAndPause() public {
        // Set both limits
        vm.prank(address(treasury));
        treasury.setSafeSpendingLimits(1, 1 ether, 5 ether);

        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        // Execute within limits
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0.5 ether, data, 0);

        // Pause
        vm.prank(guardian);
        treasury.pauseSafe(1);

        // Should fail due to pause (even though within limits)
        vm.prank(address(treasury));
        vm.expectRevert(ITreasury.SAFE_PAUSED.selector);
        treasury.execOnSafe(1, address(target), 0.5 ether, data, 0);

        // Unpause
        vm.prank(guardian);
        treasury.unpauseSafe(1);

        // Should work again
        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0.5 ether, data, 0);
    }
}
