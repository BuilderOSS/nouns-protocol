// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";
import { GovernorSafeModule } from "../src/governance/treasury/GovernorSafeModule.sol";
import { ITreasury } from "../src/governance/treasury/ITreasury.sol";
import { MockGnosisSafe } from "./utils/mocks/MockGnosisSafe.sol";
import { MockSafeExecutionTarget } from "./utils/mocks/MockSafeExecutionTarget.sol";

contract TreasuryV2Test is NounsBuilderTest {
    MockGnosisSafe internal primarySafe;
    GovernorSafeModule internal primaryModule;

    function setUp() public override {
        super.setUp();
        deployMock();

        primarySafe = new MockGnosisSafe();
        primaryModule = new GovernorSafeModule(address(treasury));
        primarySafe.enableModule(address(primaryModule));
    }

    function test_RegisterSafe() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        assertEq(treasury.safeCount(), 1);

        ITreasury.SafeConfig memory safeConfig = treasury.getSafe(1);
        assertEq(safeConfig.safe, address(primarySafe));
        assertEq(safeConfig.execModule, address(primaryModule));
        assertEq(safeConfig.active, true);
    }

    function test_RegisterSafe_OnlyTreasury() public {
        MockGnosisSafe secondarySafe = new MockGnosisSafe();
        GovernorSafeModule secondaryModule = new GovernorSafeModule(address(treasury));
        secondarySafe.enableModule(address(secondaryModule));

        vm.expectRevert();
        treasury.registerSafe(address(secondarySafe), address(secondaryModule), address(0), bytes32(0));

        vm.prank(address(treasury));
        treasury.registerSafe(address(secondarySafe), address(secondaryModule), address(0), bytes32(0));

        assertEq(treasury.safeCount(), 1);
        assertEq(treasury.getSafeIdByAddress(address(secondarySafe)), 1);
    }

    function testRevert_RegisterSafe_DuplicateSafe() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        vm.prank(address(treasury));
        vm.expectRevert();
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));
    }

    function test_SetGlobalPolicy() public {
        address policy = makeAddr("policy");
        bytes32 policyHash = keccak256("global-policy-v1");

        vm.prank(address(treasury));
        treasury.setGlobalPolicy(policy, policyHash, true);

        ITreasury.GlobalPolicy memory globalPolicy = treasury.getGlobalPolicy();
        assertEq(globalPolicy.policy, policy);
        assertEq(globalPolicy.policyHash, policyHash);
        assertEq(globalPolicy.enforce, true);
    }

    function test_UpdateSafe() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        GovernorSafeModule newModule = new GovernorSafeModule(address(treasury));
        primarySafe.enableModule(address(newModule));

        vm.prank(address(treasury));
        treasury.updateSafe(1, false, address(newModule), address(1234), keccak256("policy"));

        ITreasury.SafeConfig memory safeConfig = treasury.getSafe(1);
        assertEq(safeConfig.active, false);
        assertEq(safeConfig.execModule, address(newModule));
        assertEq(safeConfig.policy, address(1234));
        assertEq(safeConfig.policyHash, keccak256("policy"));
    }

    function test_ExecOnSafe() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        MockSafeExecutionTarget target = new MockSafeExecutionTarget();
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        vm.prank(address(treasury));
        treasury.execOnSafe(1, address(target), 0, data, 0);

        assertEq(target.number(), 42);
        assertEq(target.caller(), address(primarySafe));
    }

    function test_ExecOnSafe_InvalidOperation() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        MockSafeExecutionTarget target = new MockSafeExecutionTarget();
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        vm.prank(address(treasury));
        vm.expectRevert();
        treasury.execOnSafe(1, address(target), 0, data, 1);
    }

    function testRevert_ExecOnSafe_InactiveSafe() public {
        vm.prank(address(treasury));
        treasury.registerSafe(address(primarySafe), address(primaryModule), address(0), bytes32(0));

        vm.prank(address(treasury));
        treasury.updateSafe(1, false, address(primaryModule), address(0), bytes32(0));

        MockSafeExecutionTarget target = new MockSafeExecutionTarget();
        bytes memory data = abi.encodeWithSelector(target.setNumber.selector, 42);

        vm.prank(address(treasury));
        vm.expectRevert();
        treasury.execOnSafe(1, address(target), 0, data, 0);
    }

    function testRevert_RegisterSafe_ModuleNotEnabled() public {
        MockGnosisSafe newSafe = new MockGnosisSafe();
        GovernorSafeModule newModule = new GovernorSafeModule(address(treasury));
        // Intentionally NOT enabling the module on the safe

        vm.prank(address(treasury));
        vm.expectRevert();
        treasury.registerSafe(address(newSafe), address(newModule), address(0), bytes32(0));
    }

    function test_IsSafeReady() public {
        // Primary safe has module enabled
        bool ready = treasury.isSafeReady(address(primarySafe), address(primaryModule));
        assertEq(ready, true);

        // New safe without module enabled
        MockGnosisSafe newSafe = new MockGnosisSafe();
        GovernorSafeModule newModule = new GovernorSafeModule(address(treasury));
        bool notReady = treasury.isSafeReady(address(newSafe), address(newModule));
        assertEq(notReady, false);

        // Enable and check again
        newSafe.enableModule(address(newModule));
        bool nowReady = treasury.isSafeReady(address(newSafe), address(newModule));
        assertEq(nowReady, true);
    }

    function test_IsSafeReady_InvalidInputs() public {
        bool result1 = treasury.isSafeReady(address(0), address(primaryModule));
        assertEq(result1, false);

        bool result2 = treasury.isSafeReady(address(primarySafe), address(0));
        assertEq(result2, false);
    }
}
