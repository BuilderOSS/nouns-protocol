// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { SourceBridgeAdapter } from "../../src/bridge/SourceBridgeAdapter.sol";
import { BridgeTypes } from "../../src/bridge/types/BridgeTypes.sol";
import { MockTransportAdapter } from "../utils/mocks/MockTransportAdapter.sol";

contract SourceBridgeAdapterTest is Test, BridgeTypes {
    SourceBridgeAdapter internal sourceAdapter;
    MockTransportAdapter internal transport;

    address internal treasury = makeAddr("treasury");

    function setUp() public {
        sourceAdapter = new SourceBridgeAdapter(address(this), treasury, keccak256("dao"));
        transport = new MockTransportAdapter();

        sourceAdapter.setTransportAdapter(1, address(transport));
        sourceAdapter.setDestinationExecutor(10, makeAddr("dest-executor"));
    }

    function test_SendCommandByTreasury() public {
        Command memory command = Command({ commandType: CommandType.EXECUTE, data: abi.encode(uint256(1)) });

        vm.prank(treasury);
        sourceAdapter.sendCommand(1, 10, 0, abi.encode(command), bytes("options"));

        assertEq(sourceAdapter.nonces(10), 1);
        assertEq(transport.lastDstChainId(), 10);
    }

    function testRevert_SendCommandNotTreasury() public {
        vm.expectRevert(SourceBridgeAdapter.ONLY_TREASURY.selector);
        sourceAdapter.sendCommand(1, 10, 0, bytes("payload"), bytes(""));
    }
}
