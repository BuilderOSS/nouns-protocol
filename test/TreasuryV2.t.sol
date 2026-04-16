// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";
import { GovernorSafeModule } from "../src/governance/treasury/GovernorSafeModule.sol";
import { ITreasury } from "../src/governance/treasury/ITreasury.sol";
import { MockGnosisSafe } from "./utils/mocks/MockGnosisSafe.sol";
import { MockSafeExecutionTarget } from "./utils/mocks/MockSafeExecutionTarget.sol";

contract TreasuryV2Test is NounsBuilderTest {
    MockGnosisSafe internal mainSafe;
    GovernorSafeModule internal mainModule;

    function setUp() public override {
        super.setUp();
        deployMock();

        mainSafe = new MockGnosisSafe();
        mainModule = new GovernorSafeModule(address(treasury));
        mainSafe.enableModule(address(mainModule));
    }

    function test_InitializeV2() public {
        vm.prank(address(manager));
        treasury.initializeV2(address(mainSafe), address(mainModule), address(0), bytes32(0), address(0), bytes32(0), false);

        assertEq(treasury.safeCount(), 1);
        assertEq(treasury.mainSafeId(), 1);

        ITreasury.SafeConfig memory safeConfig = treasury.getSafe(1);
        assertEq(safeConfig.safe, address(mainSafe));
        assertEq(safeConfig.execModule, address(mainModule));
        assertEq(safeConfig.isMain, true);
    }

    function test_RegisterSafe_OnlyTreasury() public {
        vm.prank(address(manager));
        treasury.initializeV2(address(mainSafe), address(mainModule), address(0), bytes32(0), address(0), bytes32(0), false);

        MockGnosisSafe secondarySafe = new MockGnosisSafe();
        GovernorSafeModule secondaryModule = new GovernorSafeModule(address(treasury));
        secondarySafe.enableModule(address(secondaryModule));

        vm.expectRevert();
        treasury.registerSafe(address(secondarySafe), address(secondaryModule), address(0), bytes32(0), false);

        vm.prank(address(treasury));
        treasury.registerSafe(address(secondarySafe), address(secondaryModule), address(0), bytes32(0), false);

        assertEq(treasury.safeCount(), 2);
        assertEq(treasury.getSafeIdByAddress(address(secondarySafe)), 2);
    }

    function test_ExecOnSafe() public {
        vm.prank(address(manager));
        treasury.initializeV2(address(mainSafe), address(mainModule), address(0), bytes32(0), address(0), bytes32(0), false);

        MockSafeExecutionTarget target = new MockSafeExecutionTarget();
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0, data, 0);

        assertEq(target.number(), 42);
        assertEq(target.caller(), address(mainSafe));
    }

    function test_ExecOnSafe_InvalidOperation() public {
        vm.prank(address(manager));
        treasury.initializeV2(address(mainSafe), address(mainModule), address(0), bytes32(0), address(0), bytes32(0), false);

        MockSafeExecutionTarget target = new MockSafeExecutionTarget();
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        vm.prank(address(treasury));
        vm.expectRevert();
        treasury.execOnSafe(1, address(target), 0, data, 1);
    }
}
