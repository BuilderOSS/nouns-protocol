// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { DestinationExecutor } from "../../src/bridge/DestinationExecutor.sol";
import { SingleAdapterPolicy } from "../../src/bridge/policies/SingleAdapterPolicy.sol";
import { BridgeTypes } from "../../src/bridge/types/BridgeTypes.sol";
import { MockTransportAdapter } from "../utils/mocks/MockTransportAdapter.sol";
import { MockWalletExecutionAdapter } from "../utils/mocks/MockWalletExecutionAdapter.sol";
import { MockSafeExecutionTarget } from "../utils/mocks/MockSafeExecutionTarget.sol";

contract DestinationExecutorTest is Test, BridgeTypes {
    DestinationExecutor internal executor;
    SingleAdapterPolicy internal policy;
    MockTransportAdapter internal transportAdapter;
    MockWalletExecutionAdapter internal walletAdapter;
    MockSafeExecutionTarget internal target;

    bytes32 internal constant DAO_ID = keccak256("dao");
    uint8 internal constant ADAPTER_ID = 1;

    address internal sourceSender = makeAddr("sourceSender");
    uint64 internal nonce;

    function setUp() public {
        policy = new SingleAdapterPolicy();

        executor = new DestinationExecutor(
            address(this),
            DAO_ID,
            1,
            sourceSender,
            address(this),
            address(this),
            BridgeMode.MANAGED,
            address(policy),
            1,
            1 days,
            1 days
        );

        transportAdapter = new MockTransportAdapter();
        walletAdapter = new MockWalletExecutionAdapter();
        target = new MockSafeExecutionTarget();

        executor.setTransportAdapterManaged(ADAPTER_ID, address(transportAdapter));
    }

    function test_AddWalletAndExecute() public {
        WalletConfigCommand memory add = WalletConfigCommand({
            walletId: 0,
            wallet: makeAddr("wallet"),
            adapter: address(walletAdapter),
            policy: address(0),
            policyHash: bytes32(0),
            active: true
        });

        _relay(Command({ commandType: CommandType.ADD_WALLET, data: abi.encode(add) }), keccak256("m1"));

        assertEq(executor.walletCount(), 1);

        ExecuteCommand memory exec =
            ExecuteCommand({ walletId: 1, target: address(target), value: 0, data: abi.encodeWithSelector(target.setNumber.selector, 7), operation: 0 });

        _relay(Command({ commandType: CommandType.EXECUTE, data: abi.encode(exec) }), keccak256("m2"));

        assertEq(target.number(), 7);
    }

    function test_ReplayProtection() public {
        Command memory cmd = Command({ commandType: CommandType.SET_MODE, data: abi.encode(SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: uint64(block.timestamp + 1 days), execute: false, cancel: false })) });

        BridgeEnvelope memory envelope = _buildEnvelope(abi.encode(cmd));
        bytes memory encodedEnvelope = abi.encode(envelope);
        bytes32 msgId = keccak256("message-id");

        transportAdapter.relay(address(executor), ADAPTER_ID, msgId, encodedEnvelope);

        vm.expectRevert(DestinationExecutor.MESSAGE_ALREADY_CONSUMED.selector);
        transportAdapter.relay(address(executor), ADAPTER_ID, msgId, encodedEnvelope);
    }

    function test_ManagedPolicyChangeRevertsViaSourceCommand() public {
        SetPolicyCommand memory setPolicy =
            SetPolicyCommand({ policy: address(policy), threshold: 1, adapterSetVersion: 0 });

        vm.expectRevert(DestinationExecutor.MODE_MUST_BE_SOVEREIGN.selector);
        _relay(Command({ commandType: CommandType.SET_POLICY, data: abi.encode(setPolicy) }), keccak256("p1"));
    }

    function test_TwoWayModeSwitchAndSovereignPolicyUpdate() public {
        uint64 eta = uint64(block.timestamp + 1 days);

        SetModeCommand memory request = SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: eta, execute: false, cancel: false });
        _relay(Command({ commandType: CommandType.SET_MODE, data: abi.encode(request) }), keccak256("s1"));

        vm.warp(eta + 1);

        SetModeCommand memory execute = SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: 0, execute: true, cancel: false });
        _relay(Command({ commandType: CommandType.SET_MODE, data: abi.encode(execute) }), keccak256("s2"));

        assertEq(uint8(executor.mode()), uint8(BridgeMode.SOVEREIGN));

        SetPolicyCommand memory setPolicy =
            SetPolicyCommand({ policy: address(policy), threshold: 1, adapterSetVersion: 2 });
        _relay(Command({ commandType: CommandType.SET_POLICY, data: abi.encode(setPolicy) }), keccak256("s3"));

        assertEq(executor.adapterSetVersion(), 2);
    }

    function testRevert_ManagedConfigBlockedWhileModeChangePending() public {
        uint64 eta = uint64(block.timestamp + 1 days);

        SetModeCommand memory request = SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: eta, execute: false, cancel: false });
        _relay(Command({ commandType: CommandType.SET_MODE, data: abi.encode(request) }), keccak256("p1"));

        vm.expectRevert(DestinationExecutor.MODE_CHANGE_PENDING.selector);
        executor.setTransportAdapterManaged(2, makeAddr("adapter2"));

        vm.expectRevert(DestinationExecutor.MODE_CHANGE_PENDING.selector);
        executor.setVerificationPolicyManaged(address(policy), 1, 0);
    }

    function testRevert_SetManagedConfigInSovereignMode() public {
        uint64 eta = uint64(block.timestamp + 1 days);

        _relay(
            Command({
                commandType: CommandType.SET_MODE,
                data: abi.encode(SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: eta, execute: false, cancel: false }))
            }),
            keccak256("m1")
        );

        vm.warp(eta + 1);

        _relay(
            Command({
                commandType: CommandType.SET_MODE,
                data: abi.encode(SetModeCommand({ mode: BridgeMode.SOVEREIGN, eta: 0, execute: true, cancel: false }))
            }),
            keccak256("m2")
        );

        vm.expectRevert(DestinationExecutor.MODE_MUST_BE_MANAGED.selector);
        executor.setTransportAdapterManaged(2, makeAddr("adapter2"));

        vm.expectRevert(DestinationExecutor.MODE_MUST_BE_MANAGED.selector);
        executor.setVerificationPolicyManaged(address(policy), 1, 0);
    }

    function _relay(Command memory command, bytes32 messageId) internal {
        BridgeEnvelope memory envelope = _buildEnvelope(abi.encode(command));
        transportAdapter.relay(address(executor), ADAPTER_ID, messageId, abi.encode(envelope));
    }

    function _buildEnvelope(bytes memory payload) internal returns (BridgeEnvelope memory envelope) {
        nonce++;
        envelope = BridgeEnvelope({
            daoId: DAO_ID,
            sourceChainId: 1,
            destinationChainId: block.chainid,
            sourceSender: sourceSender,
            nonce: nonce,
            deadline: 0,
            payload: payload
        });
    }
}
