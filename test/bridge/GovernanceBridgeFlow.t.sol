// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "../utils/NounsBuilderTest.sol";
import { BridgeTypes } from "../../src/bridge/types/BridgeTypes.sol";
import { SourceBridgeAdapter } from "../../src/bridge/SourceBridgeAdapter.sol";
import { DestinationExecutor } from "../../src/bridge/DestinationExecutor.sol";
import { SingleAdapterPolicy } from "../../src/bridge/policies/SingleAdapterPolicy.sol";
import { MockTransportAdapter } from "../utils/mocks/MockTransportAdapter.sol";
import { MockWalletExecutionAdapter } from "../utils/mocks/MockWalletExecutionAdapter.sol";
import { MockSafeExecutionTarget } from "../utils/mocks/MockSafeExecutionTarget.sol";

contract GovernanceBridgeFlowTest is NounsBuilderTest, BridgeTypes {
    SourceBridgeAdapter internal sourceAdapter;
    DestinationExecutor internal destinationExecutor;
    SingleAdapterPolicy internal verificationPolicy;
    MockTransportAdapter internal transportAdapter;
    MockWalletExecutionAdapter internal walletAdapter;
    MockSafeExecutionTarget internal target;

    bytes32 internal daoId;
    address internal proposer;

    uint8 internal constant ADAPTER_ID = 1;

    function setUp() public override {
        super.setUp();
        deployMock();

        daoId = keccak256(abi.encode(address(token)));

        sourceAdapter = new SourceBridgeAdapter(address(this), address(treasury), daoId);
        verificationPolicy = new SingleAdapterPolicy();
        destinationExecutor = new DestinationExecutor(
            address(this),
            daoId,
            block.chainid,
            address(sourceAdapter),
            address(this),
            address(this),
            BridgeMode.MANAGED,
            address(verificationPolicy),
            1,
            1 days,
            1 days
        );
        transportAdapter = new MockTransportAdapter();
        walletAdapter = new MockWalletExecutionAdapter();
        target = new MockSafeExecutionTarget();

        sourceAdapter.setTransportAdapter(ADAPTER_ID, address(transportAdapter));
        sourceAdapter.setDestinationExecutor(block.chainid, address(destinationExecutor));
        destinationExecutor.setTransportAdapterManaged(ADAPTER_ID, address(transportAdapter));

        _registerWalletViaSourceCommand();

        proposer = makeAddr("proposer");
        _setupProposerVotingPower();
    }

    function test_GovernanceExecutesBridgedCommand() public {
        ExecuteCommand memory executeCommand = ExecuteCommand({
            walletId: 1,
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setNumber.selector, 111),
            operation: 0
        });

        Command memory command = Command({ commandType: CommandType.EXECUTE, data: abi.encode(executeCommand) });

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(sourceAdapter);
        calldatas[0] = abi.encodeWithSelector(
            sourceAdapter.sendCommand.selector,
            ADAPTER_ID,
            block.chainid,
            uint64(0),
            abi.encode(command),
            bytes("")
        );

        vm.warp(block.timestamp + 20);

        vm.prank(proposer);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(proposer);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        governor.queue(proposalId);

        vm.warp(block.timestamp + treasury.delay() + 1);

        governor.execute(targets, values, calldatas, keccak256(bytes("")), proposer);

        transportAdapter.relay(
            address(destinationExecutor), ADAPTER_ID, transportAdapter.lastMessageId(), transportAdapter.lastEnvelope()
        );

        assertEq(target.number(), 111);
    }

    function _registerWalletViaSourceCommand() internal {
        WalletConfigCommand memory walletCommand = WalletConfigCommand({
            walletId: 0,
            wallet: makeAddr("wallet"),
            adapter: address(walletAdapter),
            policy: address(0),
            policyHash: bytes32(0),
            active: true
        });

        Command memory command = Command({ commandType: CommandType.ADD_WALLET, data: abi.encode(walletCommand) });
        BridgeEnvelope memory envelope = BridgeEnvelope({
            daoId: daoId,
            sourceChainId: block.chainid,
            destinationChainId: block.chainid,
            sourceSender: address(sourceAdapter),
            nonce: 1,
            deadline: 0,
            payload: abi.encode(command)
        });

        transportAdapter.relay(address(destinationExecutor), ADAPTER_ID, keccak256("wallet-register"), abi.encode(envelope));
    }

    function _setupProposerVotingPower() internal {
        vm.startPrank(address(auction));
        uint256 newTokenId = token.mint();
        token.transferFrom(address(auction), proposer, newTokenId);
        vm.stopPrank();

        vm.prank(address(treasury));
        governor.updateProposalThresholdBps(1);
    }
}
